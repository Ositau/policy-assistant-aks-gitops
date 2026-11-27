output "cluster_name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "resource_group_name" {
  value = data.azurerm_resource_group.this.name
}

output "oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "ingress_ip" {
  description = "Point the DNS records for all four environments at this address."
  value       = azurerm_public_ip.ingress.ip_address
}

output "hostnames" {
  value = local.hostnames
}

output "app_identity_client_ids" {
  description = "Workload identity client ID per environment (goes in each environment's Helm values)."
  value       = { for env, id in azurerm_user_assigned_identity.app : env => id.client_id }
}

output "signin_client_id" {
  value = azuread_application.signin.client_id
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "registry_login_server" {
  value = data.azurerm_container_registry.acr.login_server
}
