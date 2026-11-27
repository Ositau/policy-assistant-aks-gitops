variable "resource_group_name" {
  description = "Resource group for the cluster and everything around it (created by scripts/bootstrap.sh)."
  type        = string
  default     = "rg-policy-aks"
}

variable "location" {
  type    = string
  default = "swedencentral"
}

# ---- The cluster ----

variable "kubernetes_version" {
  description = "AKS Kubernetes version (run `az aks get-versions -l <region>` to see what's available)."
  type        = string
  default     = "1.36"
}

variable "node_size" {
  description = "VM size for the nodes. Check your quota first: `az vm list-usage -l <region>`."
  type        = string
  default     = "Standard_D2s_v4"
}

variable "node_count" {
  type    = number
  default = 2
}

# ---- The existing Policy Assistant resources the app uses ----

variable "backend_resource_group" {
  description = "Resource group of the existing Policy Assistant (Azure OpenAI, AI Search, container registry)."
  type        = string
}

variable "openai_account_name" {
  type = string
}

variable "search_service_name" {
  type = string
}

variable "container_registry_name" {
  type = string
}

# ---- Environments and DNS ----

variable "dns_zone" {
  description = "Domain the four environments live under. DNS records are added by hand (see the guide)."
  type        = string
  default     = "ositauche.top"
}

variable "environments" {
  description = "Environment name => host name (without the domain)."
  type        = map(string)
  default = {
    dev   = "policy-dev"
    test  = "policy-test"
    stage = "policy-stage"
    prod  = "policy"
  }
}

# ---- Who may administer the cluster ----

variable "admin_object_id" {
  description = "Object ID of the person who administers the cluster (Azure RBAC Cluster Admin)."
  type        = string
}

variable "pipeline_object_id" {
  description = "Object ID of the GitHub Actions identity. Set explicitly so plans run by anyone else stay accurate."
  type        = string
}

variable "tags" {
  type = map(string)
  default = {
    project    = "policy-assistant-aks"
    managed_by = "terraform"
  }
}
