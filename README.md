# Policy Assistant on AKS with Argo CD and Helm

GitOps deployment of the [Policy Assistant](https://github.com/Ositau/azure-openai-policy-assistant) (an Azure OpenAI
app that answers staff questions from company policies, filtered by the user's Entra ID groups) to Azure Kubernetes
Service, across four environments: **dev, test, stage and prod**.

- **Terraform** builds the platform in two layers: Azure resources, then the hand-over to Argo CD.
- **Helm** packages the app once; each environment is one small values file.
- **Argo CD** deploys from Git. Nobody runs `kubectl apply`.
- **GitHub Actions** builds the image once and promotes that exact image: dev and test automatically,
  stage and prod after approval (prod also needs a manual Sync in Argo CD).
- **No keys or client secrets.** GitHub signs in to Azure, pods sign in to Azure OpenAI and AI Search, and
  oauth2-proxy signs in to Entra ID, all with federated tokens.

Step-by-step guide (with every error I hit): https://ositauche.com/aks-argocd-helm-gitops-four-environments-terraform/

```
app repo ─▶ build (image once, tag = commit ID) ─▶ environments/<env>/values.yaml ─▶ Argo CD ─▶ policy-<env>
                                                     dev, test: automatic
                                                     stage, prod: approval in GitHub (+ Sync for prod)

Cloudflare DNS ─▶ static IP ─▶ Envoy Gateway (HTTPS, Let's Encrypt) ─▶ oauth2-proxy ─▶ app (127.0.0.1)
                                                                                      └─▶ Azure OpenAI, AI Search
```

## What's here

| Path | What it is |
|---|---|
| `scripts/bootstrap.sh` | One-time setup: resource groups, Terraform state, the GitHub sign-in identity and its limited roles |
| `scripts/configure.py` | Points your copy at your GitHub repo, domain and Azure resources |
| `infra/01-platform` | Terraform layer 1: AKS, static IP, one workload identity per environment, the Entra sign-in app |
| `infra/02-bootstrap` | Terraform layer 2: namespaces, oauth2-proxy cookie keys, Argo CD, the root app |
| `argocd/` | AppProjects, the platform apps (Envoy Gateway, cert-manager, the Gateway) and the 4-environment ApplicationSet |
| `platform/gateway` | The shared Gateway, Let's Encrypt issuer, HTTPS redirect, and the static IP binding |
| `charts/policy-assistant` | The Helm chart: app + oauth2-proxy, HTTPRoute, NetworkPolicy, HPA, PodDisruptionBudget |
| `environments/` | `common.yaml` plus one values file per environment. The image tag line is the only thing CI changes |
| `.github/workflows` | `infra` (plan + AI review / apply), `build`, `deploy`, `promote` |

## Versions used

AKS 1.36, Terraform 1.14, Argo CD v3.6.3 (chart 10.20.0), Envoy Gateway v1.10.0, cert-manager v1.21.3, oauth2-proxy v7.15.6.

## Cost

AKS's control plane is free on the Free tier; you pay for the two `Standard_D2s_v4` nodes, their disks, the load
balancer and one public IP: roughly £4-5 a day in Sweden Central. Tear it down when you're done (see the guide).

Written by [Osita Uche](https://ositauche.com).
