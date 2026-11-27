variable "resource_group_name" {
  type    = string
  default = "rg-policy-aks"
}

variable "cluster_name" {
  type    = string
  default = "aks-policy-assistant"
}

variable "environments" {
  type    = set(string)
  default = ["dev", "test", "stage", "prod"]
}

variable "gitops_repo_url" {
  description = "The Git repository Argo CD watches."
  type        = string
  default     = "https://github.com/Ositau/policy-assistant-aks-gitops.git"
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version (10.20.0 = Argo CD v3.6.3)."
  type        = string
  default     = "10.20.0"
}
