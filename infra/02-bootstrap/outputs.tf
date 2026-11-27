output "argocd_dashboard" {
  value = "kubectl -n argocd port-forward svc/argocd-server 8080:443, then open https://localhost:8080 (user admin, password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
}
