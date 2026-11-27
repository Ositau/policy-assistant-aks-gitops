# Layer 1: the platform. AKS, a fixed public IP for the way in, one identity per environment,
# and the Entra ID sign-in app. Argo CD and everything inside the cluster is layer 2 and Git.

data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

data "azurerm_cognitive_account" "openai" {
  name                = var.openai_account_name
  resource_group_name = var.backend_resource_group
}

data "azurerm_search_service" "search" {
  name                = var.search_service_name
  resource_group_name = var.backend_resource_group
}

data "azurerm_container_registry" "acr" {
  name                = var.container_registry_name
  resource_group_name = var.backend_resource_group
}

locals {
  hostnames = { for env, host in var.environments : env => "${host}.${var.dns_zone}" }
  # Every environment runs the app as the same service account name, in its own namespace.
  service_account = "policy-assistant"
}

# ---------- The cluster ----------

resource "azurerm_kubernetes_cluster" "this" {
  name                = "aks-policy-assistant"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
  node_resource_group = "${var.resource_group_name}-nodes"
  dns_prefix          = "policy-aks"
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Free"
  tags                = var.tags

  # Pods sign in to Azure with workload identity (federated tokens), never keys.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # People and pipelines sign in with Entra ID; Kubernetes permissions are Azure role assignments.
  local_account_disabled            = true
  role_based_access_control_enabled = true
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }

  default_node_pool {
    name                        = "system"
    vm_size                     = var.node_size
    node_count                  = var.node_count
    os_disk_size_gb             = 64
    temporary_name_for_rotation = "systemtmp"

    upgrade_settings {
      max_surge                     = "10%"
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type = "SystemAssigned"
  }

  # Azure CNI Overlay with Cilium: pod IPs don't use up the VNet, and NetworkPolicy is enforced.
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
  }
}

# ---------- The way in: a fixed public IP ----------

# Created here, not by Kubernetes, so it survives reinstalling the gateway or the add-ons.
# The DNS records for the four environments point at it and are added once, by hand.
resource "azurerm_public_ip" "ingress" {
  name                = "pip-policy-aks-ingress"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# The cluster attaches that IP to its load balancer, so it needs network rights on this resource group.
resource "azurerm_role_assignment" "cluster_network" {
  scope                = data.azurerm_resource_group.this.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

# The nodes pull the app image from the existing Policy Assistant registry.
resource "azurerm_role_assignment" "pull_images" {
  scope                = data.azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  principal_type       = "ServicePrincipal"
}

# ---------- Who can manage the cluster ----------

resource "azurerm_role_assignment" "cluster_admin" {
  for_each = {
    admin    = var.admin_object_id
    pipeline = var.pipeline_object_id
  }
  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = each.value
}

# ---------- One identity per environment (dev can't act as prod) ----------

resource "azurerm_user_assigned_identity" "app" {
  for_each            = var.environments
  name                = "id-policy-${each.key}"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
  tags                = var.tags
}

# Trust the app's Kubernetes service account in that environment's namespace, and nothing else.
resource "azurerm_federated_identity_credential" "app" {
  for_each            = var.environments
  name                = "aks-${each.key}"
  resource_group_name = data.azurerm_resource_group.this.name
  parent_id           = azurerm_user_assigned_identity.app[each.key].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject             = "system:serviceaccount:policy-${each.key}:${local.service_account}"
}

# The same access the Container Apps version has: ask the model, read the search index.
resource "azurerm_role_assignment" "app_openai" {
  for_each             = var.environments
  scope                = data.azurerm_cognitive_account.openai.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_user_assigned_identity.app[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "app_search" {
  for_each             = var.environments
  scope                = data.azurerm_search_service.search.id
  role_definition_name = "Search Index Data Reader"
  principal_id         = azurerm_user_assigned_identity.app[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

# ---------- Sign-in: oauth2-proxy with Entra ID, no client secret ----------

resource "azuread_application" "signin" {
  display_name     = "Policy Assistant (AKS sign-in)"
  sign_in_audience = "AzureADMyOrg"
  owners           = [var.pipeline_object_id, var.admin_object_id]

  # Put the user's security groups in the ID token: the app filters search results by them.
  group_membership_claims = ["SecurityGroup"]

  web {
    redirect_uris = [for host in values(local.hostnames) : "https://${host}/oauth2/callback"]
    implicit_grant {
      id_token_issuance_enabled = false
    }
  }
}

resource "azuread_service_principal" "signin" {
  client_id = azuread_application.signin.client_id
  owners    = [var.pipeline_object_id, var.admin_object_id]
}

# oauth2-proxy runs in the app's pod and proves who it is with the pod's federated token,
# so the sign-in app needs no client secret.
resource "azuread_application_federated_identity_credential" "signin" {
  for_each       = var.environments
  application_id = azuread_application.signin.id
  display_name   = "aks-${each.key}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject        = "system:serviceaccount:policy-${each.key}:${local.service_account}"
}
