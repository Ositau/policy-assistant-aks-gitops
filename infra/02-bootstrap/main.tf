# Layer 2: the hand-over. Terraform installs Argo CD and points it at this repo's argocd/ folder.
# From then on, Argo CD installs and updates everything else from Git.

# ---------- The four environment namespaces, and the one secret each needs ----------

resource "kubernetes_namespace_v1" "env" {
  for_each = var.environments
  metadata {
    name = "policy-${each.key}"
    labels = {
      environment = each.key
    }
  }
}

# oauth2-proxy encrypts its session cookie with this key. It is not a credential for Azure or Entra ID,
# but it must never be in Git, so Terraform generates it and puts it straight into the cluster.
resource "random_password" "cookie" {
  for_each = var.environments
  length   = 32
  special  = false
}

resource "kubernetes_secret_v1" "cookie" {
  for_each = var.environments
  metadata {
    name      = "oauth2-proxy-cookie"
    namespace = kubernetes_namespace_v1.env[each.key].metadata[0].name
  }
  data = {
    "cookie-secret" = random_password.cookie[each.key].result
  }
}

# ---------- Argo CD ----------

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  wait             = true
  timeout          = 900

  values = [yamlencode({
    dex = { enabled = false } # no extra sign-in for the dashboard; reached through kubectl port-forward
    configs = {
      cm = {
        # Let Argo CD wait for a child Application to be healthy before the next sync wave
        # (needed so Envoy Gateway's CRDs exist before cert-manager and the Gateway are installed).
        "resource.customizations.health.argoproj.io_Application" = <<-LUA
          hs = {}
          hs.status = "Progressing"
          hs.message = ""
          if obj.status ~= nil and obj.status.health ~= nil then
            hs.status = obj.status.health.status
            if obj.status.health.message ~= nil then
              hs.message = obj.status.health.message
            end
          end
          return hs
        LUA
      }
      repositories = {
        # Envoy Gateway's Helm chart is published to Docker Hub as an OCI artifact.
        envoy-gateway = {
          name      = "envoy-gateway"
          type      = "helm"
          url       = "registry-1.docker.io/envoyproxy"
          enableOCI = "true"
        }
      }
    }
  })]
}

# The root app ("app of apps"): everything in argocd/ in Git, synced automatically.
resource "helm_release" "root" {
  name       = "argocd-root"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.10"

  values = [yamlencode({
    applications = {
      root = {
        namespace = "argocd"
        project   = "default"
        source = {
          repoURL        = var.gitops_repo_url
          targetRevision = "main"
          path           = "argocd"
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = { prune = true, selfHeal = true }
        }
      }
    }
  })]

  depends_on = [helm_release.argocd, kubernetes_secret_v1.cookie]
}
