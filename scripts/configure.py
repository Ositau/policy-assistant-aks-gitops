"""Point your copy of this repo at your own GitHub repo, domain and Azure resources.

Run it twice:

  1. Before Terraform layer 1 (your repo and your domain):
       python scripts/configure.py repo --repo https://github.com/<you>/policy-assistant-aks-gitops.git --domain example.com

  2. After layer 1 has been applied (the IDs Terraform and your Policy Assistant produced):
       terraform -chdir=infra/01-platform init -backend-config=...   (see the guide)
       python scripts/configure.py azure --backend-rg rg-policy-assistant-demo

Step 2 reads the Terraform outputs and looks up the rest with the Azure CLI. Nothing here is secret:
it's endpoints, names and IDs. Review the changes with `git diff`, then commit them.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ENVS = ("dev", "test", "stage", "prod")


def edit(path: str, pattern: str, replacement: str) -> int:
    """Regex-replace in a file (multiline). Fails loudly if the pattern isn't there."""
    file = ROOT / path
    text = file.read_text(encoding="utf-8")
    new, count = re.subn(pattern, replacement, text, flags=re.M)
    if count == 0:
        sys.exit(f"{path}: expected to find {pattern!r}; has the file changed?")
    file.write_text(new, encoding="utf-8")
    return count


def set_key(path: str, key: str, value: str) -> None:
    """Replace the value of `key: value` in a YAML file, keeping indentation and any trailing comment."""
    edit(path, rf"^(\s*{re.escape(key)}:\s*)[^\s#]+", lambda m: m.group(1) + value)


def run(*args: str) -> str:
    exe = shutil.which(args[0]) or args[0]
    return subprocess.run([exe, *args[1:]], capture_output=True, text=True, check=True).stdout.strip()


def repo_step(a: argparse.Namespace) -> None:
    repo = a.repo if a.repo.endswith(".git") else a.repo + ".git"
    for f in ("argocd/environments.yaml", "argocd/platform.yaml", "argocd/projects.yaml"):
        edit(f, r"https://github\.com/[^/\s]+/[^/\s]+\.git", repo)
    edit("infra/02-bootstrap/variables.tf", r'default\s*=\s*"https://github\.com/[^"]+\.git"', f'default     = "{repo}"')
    edit("infra/01-platform/variables.tf", r'(variable "dns_zone" \{[^}]*?default\s*=\s*)"[^"]+"', lambda m: f'{m.group(1)}"{a.domain}"')
    # Host names keep their prefixes (policy-dev, policy-test, policy-stage, policy); only the domain changes.
    edit("platform/gateway/gateway.yaml", r"^(\s*hostname:\s*policy(?:-[a-z]+)?)\.\S+", lambda m: f"{m.group(1)}.{a.domain}")
    for env in ENVS:
        edit(f"environments/{env}/values.yaml", r"^(host:\s*policy(?:-[a-z]+)?)\.\S+", lambda m: f"{m.group(1)}.{a.domain}")
    print(f"Repo and domain set: {repo}, *.{a.domain}. Check with: git diff")


def azure_step(a: argparse.Namespace) -> None:
    out = json.loads(run("terraform", f"-chdir={ROOT / 'infra/01-platform'}", "output", "-json"))
    value = lambda k: out[k]["value"]  # noqa: E731

    rg = a.backend_rg
    openai = json.loads(run("az", "cognitiveservices", "account", "list", "-g", rg,
                            "--query", "[?kind=='OpenAI'] | [0].properties.endpoint", "-o", "json"))
    search = run("az", "search", "service", "list", "-g", rg, "--query", "[0].name", "-o", "tsv")
    staff = run("az", "ad", "group", "show", "-g", a.staff_group, "--query", "id", "-o", "tsv")
    hr = run("az", "ad", "group", "show", "-g", a.hr_group, "--query", "id", "-o", "tsv")
    image = f"{value('registry_login_server')}/policy-assistant"

    common = "environments/common.yaml"
    set_key(common, "openaiEndpoint", openai)
    set_key(common, "searchEndpoint", f"https://{search}.search.windows.net")
    set_key(common, "groupStaffId", staff)
    set_key(common, "groupHrId", hr)
    set_key(common, "tenantId", value("tenant_id"))
    set_key(common, "clientId", value("signin_client_id"))
    set_key(common, "repository", image)
    set_key("charts/policy-assistant/values.yaml", "repository", image)
    for env, client_id in value("app_identity_client_ids").items():
        set_key(f"environments/{env}/values.yaml", "clientId", client_id)
    print("Azure values set from Terraform outputs and the Azure CLI. Check with: git diff")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="step", required=True)
    r = sub.add_parser("repo", help="your GitHub repo URL and DNS domain (before layer 1)")
    r.add_argument("--repo", required=True, help="https://github.com/<you>/<repo>.git")
    r.add_argument("--domain", required=True, help="the domain the four environments live under")
    z = sub.add_parser("azure", help="IDs from Terraform layer 1 and your Policy Assistant (after layer 1)")
    z.add_argument("--backend-rg", required=True, help="resource group of your Policy Assistant")
    z.add_argument("--staff-group", default="Policy Assistant - Staff")
    z.add_argument("--hr-group", default="Policy Assistant - HR")
    a = p.parse_args()
    repo_step(a) if a.step == "repo" else azure_step(a)


if __name__ == "__main__":
    main()
