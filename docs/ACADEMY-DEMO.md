# AWS Academy demonstration: provision, test, destroy

This runbook uses the existing Terraform root and ONE shared S3 state, both now
and when Jenkins integration is added later. The root Jenkinsfile is unchanged.
No AWS resources, Kubernetes workloads or remote state were changed while preparing
this implementation. Commands below are operator instructions, not completed actions.

## Decisions and capacity

| Resource | Previous Academy example | Demonstration configuration |
|---|---|---|
| Toolchain EC2 | 1 x t3.large, 8 GiB, 60 GiB root EBS, EIP | Disabled; local Jenkins/Nexus/SonarQube retained |
| Workers | 2 x t3.large, 16 GiB total, max 4 | 2 x t3.large, 16 GiB total, min/desired/max 2 |
| Worker storage | Implicit module/AMI default | 2 x 20 GiB encrypted gp3, deleted with workers |
| NAT | One NAT + EIP | Retained for private workers |
| Argo CD | Internal NLB | ClusterIP; authenticated EKS port-forward |
| Application ingress | One public NLB | Retained, shared by all application namespaces |
| Monitoring | 7 days, unbounded default resources | 6 hours / 1 GB Prometheus retention; bounded requests/limits |
| ECR deletion | Always force-deleted | Protected by default; Academy explicitly enables deletion |

Two t3.medium workers provide 8 GiB raw, less after kubelet/system reservations.
The chart requests 384 MiB app + 256 MiB MySQL per feature: five features request
3,200 MiB. Staging adds 640 MiB. Production requests two 512 MiB app pods plus
256 MiB MySQL: 1,280 MiB. These application requests alone total 5,120 MiB.
Argo components request about 704 MiB (736 MiB with optional notifications).
Monitoring requests about 960 MiB plus chart sidecars/jobs; CoreDNS, CNI,
kube-proxy, EBS CSI, Metrics Server and OS/kubelet overhead need additional room.
Two mediums do not leave reasonable startup/upgrade/runtime headroom for this set.
Two t3.large nodes are the smallest conservative homogeneous option evaluated for
the full team demonstration. This is a planning estimate, not a measured load test.
For an explicitly reduced one-feature-only exercise, mediums can be evaluated by
changing node_instance_type, but that is not the supported full-team baseline.

All existing app replica counts, production HPA, ingress, storage, monitoring and
Argo controllers are retained. No cluster autoscaler is installed; worker capacity
is intentionally fixed. HPA cannot add nodes. Watch requests, actual consumption,
OOM events, pod/IP limits and T3 CPU credits during concurrent builds/deployments.
The sum of limits can exceed available RAM: run a demonstration, not a load test.
Prometheus/Grafana storage is ephemeral, so monitoring history can disappear on
pod replacement; the shorter retention is unsuitable for production auditing.
Staging/prod MySQL remain on 5/10 GiB gp3 PVCs with Delete reclaim policy.

Approximate us-east-1 Linux on-demand budget: original Academy configuration
~$0.45/hour versus ~ $0.34/hour now, including standard EKS control plane,
workers, NAT, one public ingress NLB, basic disks and public IP allocations.
These are rounded estimates excluding traffic, cross-AZ NAT traffic, NLB LCUs,
ECR storage/scanning, logs, T3 surplus credits and taxes. The saving is roughly
$0.11/hour, mostly the duplicate toolchain host and extra NLB. Regional rates and
actual usage must be reviewed before deployment. Existing local hardware is excluded.
Idle EKS, nodes, EBS, NAT, NLBs and public IPv4 allocations continue charging.
Closing a terminal or expiring Academy credentials is NOT teardown.

Private worker networking is preserved: no public worker IPs, no new inbound
Internet rules. A single NAT supports ECR/S3 image pulls, public Git repositories
and AWS APIs. Removing it without replacing all required routes/endpoints would
break deployment. Multiple interface endpoints plus an Internet path for GitHub
are not a clear saving for this short, small lab. Only application HTTP ingress
is public; this is the pre-existing demonstration endpoint, not production TLS.

## Verified compatibility and remaining permissions

Read-only checks on 2026-10-29 found:

- Terraform 1.15.8 on Windows AMD64; AWS CLI v2 available on Windows.
- LabRole exists and trusts both eks.amazonaws.com and ec2.amazonaws.com.
- LabInstanceProfile exists and contains LabRole.
- EKS 1.34 is in STANDARD_SUPPORT until 2026-12-02; available AZs were returned.
- The example addon versions were returned as compatible with 1.34 in us-east-1.
- No EKS clusters or ECR repositories were returned in us-east-1.
- Expected bucket fst-events-tfstate-<account>-us-east-1 returned 404.

These checks do NOT prove iam:PassRole, ECR creation/push/lifecycle/tagging,
EKS/nodegroup/addon/access-entry creation, service-linked role availability,
EC2/VPC/NAT/ELB/EBS quotas or write permissions. Backend object writes and lock
object creation/deletion also remain unverified. No creation permissions were tested.

Pinned modules: VPC 5.16.0, EKS 20.37.2; providers remain on the existing lockfile.
EKS now uses a repository-owned copy of 20.37.2 with a conditional IAM lookup;
see [the Academy access fix](ACADEMY-EKS-ACCESS.md) before planning. It preserves
administrator access for the actual voclabs operator, not the LabRole node role.
Explicit AL2023 avoids the old AL2 default, which cannot serve Kubernetes 1.34.
Academy mode creates no custom cluster/node/toolchain IAM roles, OIDC provider
or customer KMS key. Worker-role EBS CSI relies on LabRole permissions and pod
IMDSv2 access (hop limit 2); verify dynamic PVC provisioning in the real cluster.
AWS-managed at-rest protection is not replaced with a custom Academy KMS key.
The API public endpoint accepts only admin_cidr (/32); private endpoint remains enabled.
For a first bootstrap, the saved infrastructure plan establishes EKS before Helm
and Kubernetes provider operations. A full plan/apply MUST then follow; targeting
is a one-time bootstrap workaround, not the normal daily workflow.

Argo chart 9.1.7 provides Argo CD 3.2.1; ingress-nginx chart 4.14.5 supports 1.34;
monitoring chart 79.8.2 targets Kubernetes >=1.25. Existing live releases, if any,
need explicit chart/CRD upgrade review: these version changes are intended for a
fresh demonstration cluster, not an unattended upgrade of production.

## State: approval before bootstrap or migration

Use the SAME bucket, region, key platform/terraform.tfstate, and default workspace
for the whole team. Do not create feature-specific workspaces or state keys for
the shared VPC/EKS/ECR. Backend locking serializes writes; it cannot prevent an
old branch configuration reverting another person's infrastructure. Assign one
operator/reviewed configuration revision. Later Jenkins must use this same backend
and a common infrastructure lock; disableConcurrentBuilds is branch-local.

S3 ListAllMyBuckets is unnecessary. Required bucket-scoped permissions include
ListBucket and state GetObject/PutObject, with GetObject/PutObject/DeleteObject
on the .tflock object. Native locking needs Terraform >=1.10. Preserve encryption,
versioning and public-access blocking. Bucket and lock live outside this Terraform
root and are never destroyed by its teardown. Versioned state still has small costs.

Do not run bootstrap until separately approved. After approval, the explicit helper
requires BOOTSTRAP <bucket> before changes and distinguishes 404 from denied or
ambiguous head-bucket failures. It never writes state objects or creates a new state.

```powershell
# ONLY after explicit approval to create/configure the backend:
.\platform\scripts\bootstrap-state.ps1 -Region us-east-1
```

Existing S3/DynamoDB users: preserve the current bucket/key/region and lock settings
until a separately approved locking transition. Do not copy over a working backend
file. No script automatically migrates state, changes keys, force-unlocks or deletes
the bucket/table. If S3 object/locking writes are denied, stop provisioning and agree
on a separately reviewed backend; per-branch local state is not a safe fallback.

## Exact PowerShell preparation and deployment

Prerequisites: AWS CLI v2, Terraform >=1.10, kubectl matching the cluster minor,
Docker Desktop for the optional local tunnel, and valid temporary Academy
credentials (access key, secret key AND session token) supplied through a secure
local profile. Never print credentials, run get-login-password directly in the
console, commit secrets, or place credentials in backend.hcl.

Run from C:\IGL5-G2-EventsProjetcs. Copy examples ONLY when real files do not exist:

```powershell
$ErrorActionPreference = 'Stop'
# If local script execution is blocked, trust/review these files first. This is
# process-only and does not alter machine/user execution policy:
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
$env:AWS_REGION = 'us-east-1'
$env:AWS_DEFAULT_REGION = 'us-east-1'
$env:AWS_PAGER = ''
aws sts get-caller-identity --query '{Account:Account,Arn:Arn}' --output json
if ($LASTEXITCODE -ne 0) { throw 'Refresh the Academy session first' }

if (!(Test-Path platform/terraform/terraform.tfvars)) {
    Copy-Item platform/terraform/terraform.tfvars.academy.example platform/terraform/terraform.tfvars
}
if (!(Test-Path platform/terraform/backend.hcl)) {
    Copy-Item platform/terraform/backend.hcl.example platform/terraform/backend.hcl
}
aws iam get-role --role-name LabRole --query Role.Arn --output text
Invoke-RestMethod https://checkip.amazonaws.com
notepad platform/terraform/terraform.tfvars
notepad platform/terraform/backend.hcl
```

Replace LabRole ARN, admin_cidr and backend account ID with actual values. Keep
enable_devops_ec2=false. If enabling it later, use a Windows forward-slash SSH
public-key path and pin devops_ami_id to avoid most_recent AMI replacement drift.
Disabling an ALREADY provisioned optional EC2 destroys that host and its tool data;
review the plan. Moved blocks retain addresses when the host remains enabled.

Supply a new Grafana password without echoing it or storing it in the command history:

```powershell
$grafanaSecret = Read-Host 'New Grafana password (16+ characters)' -AsSecureString
$grafanaPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($grafanaSecret)
try { $env:TF_VAR_grafana_admin_password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($grafanaPointer) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($grafanaPointer) }
# Do not display this environment variable. Keep it available for later plans/teardown.
```

Supply optional GitHub/Slack tokens through secure environment/credential handling.
Slack notifications are disabled when no bot token is supplied; Alertmanager retains
its configured Slack receivers but cannot deliver to Slack without a webhook.
Sensitive Terraform values still exist in state and saved plans: protect backend
and local filesystem access; never archive plan JSON in Jenkins.

Argo children and the application chart read main; GitOps runtime values read gitops.
Local uncommitted files cannot be read by Argo. Have the reviewed platform changes
published to main through the team's normal process BEFORE the full platform apply.
This task does not commit, push, merge, or change branches. gitops_revision selects
the root manifest source only; it does not rewrite nested child sources.

After backend approval/existence and configuration review:

```powershell
terraform -chdir=platform/terraform fmt -check -recursive
.\platform\scripts\academy.ps1 -Action Init

# First deployment only (saved targeted bootstrap plan, same state):
.\platform\scripts\academy.ps1 -Action PlanInfrastructure
.\platform\scripts\academy.ps1 -Action ApplyInfrastructure
# Type APPLY INFRASTRUCTURE only after reviewing the plan and costs.

# Every deployment, including immediately after the first bootstrap:
.\platform\scripts\academy.ps1 -Action Plan
.\platform\scripts\academy.ps1 -Action Apply
# Type APPLY PLATFORM after reviewing the saved full plan.
.\platform\scripts\academy.ps1 -Action Outputs

$clusterName = terraform -chdir=platform/terraform output -raw eks_cluster_name
$vpcId = terraform -chdir=platform/terraform output -raw vpc_id
aws eks update-kubeconfig --region us-east-1 --name $clusterName
kubectl get nodes -o wide
kubectl get pods -A
kubectl top nodes
kubectl get pvc -A
kubectl get applications -n argocd
```

Record clusterName and vpcId before teardown; successful destruction removes outputs.
Inspect Pending/OOMKilled pods and CSI events before running the full team demo.
Repeat the full Plan command: a settled configuration should have no changes.
Do not rerun targeted bootstrap plans as a normal workflow. Never reuse an old saved
plan after changing variables, refreshing a failed deployment or another operator's
apply. On expired credentials/partial failure: refresh all three credential values,
keep the state, inspect the error, and generate/review a fresh full plan. Terraform
records successful partial resources; automatic rollback/destroy is not appropriate.

## Private Argo access from local Jenkins

There is no public Argo endpoint and no inbound worker exposure. For a Windows-only
admin UI, run this foreground command and keep the terminal open:

```powershell
kubectl -n argocd port-forward --address 127.0.0.1 service/argocd-server 8085:80
```

localhost inside the Jenkins agent is not Windows localhost. For Jenkins, use the
separate tunnel image on the existing private Docker network. It publishes NO host
ports. It authenticates to EKS using a dedicated local Academy shared-credentials
file; Argo still requires its own restricted Jenkins API token. All network members
are trusted local CI containers; untrusted containers must not join jenkins-net.
Plain HTTP is confined to this local Docker network; upstream Kubernetes traffic
uses TLS. Stop/remove the tunnel after testing. Reconnect if port-forward exits or
credentials expire. The helper is AMD64, matching the existing local agent.

```powershell
# Prepare a dedicated directory OUTSIDE the repo containing only this session's
# AWS shared-credentials file, named credentials, with a [default] lab profile.
# Enter credentials through your secure local workflow; never paste them in chat.
$tunnelCredentials = Join-Path $env:LOCALAPPDATA 'events-demo\aws'
if (!(Test-Path (Join-Path $tunnelCredentials 'credentials'))) { throw 'Prepare the dedicated temporary credentials file first' }
docker build -t events-argocd-tunnel:demo platform/scripts/argocd-tunnel
docker run --rm --name events-argocd-tunnel --network jenkins-net `
  --mount "type=bind,source=$tunnelCredentials,target=/aws,readonly" `
  -e AWS_SHARED_CREDENTIALS_FILE=/aws/credentials `
  -e AWS_REGION=us-east-1 -e EKS_CLUSTER_NAME=fst-events `
  events-argocd-tunnel:demo
```

Do not add -p or --publish. Keep the foreground process running. In a second terminal:

```powershell
docker exec events-jenkins-agent curl -fsS http://events-argocd-tunnel:8080/api/version
```

Only a successful response verifies actual agent-to-Argo connectivity. No cluster
exists yet, so that connectivity was not tested during implementation. Set existing
Jenkins environment values manually through the normal secure admin workflow:
AWS_REGION=us-east-1; ECR_REGISTRY from the ecr_registry output;
ARGOCD_SERVER=events-argocd-tunnel:8080; existing ARGOCD_OPTS already uses grpc-web/plaintext.
Provision the existing argocd-token credential securely, using Argo's Jenkins account
with get/sync rights for events/*; do not expose tokens in console output/chat.
Set APPS_DOMAIN from ingress DNS/IP after the ingress NLB is ready. The existing
post-apply helper now tolerates ClusterIP Argo, but it also edits GitOps files and
creates a local commit: do not run it as a read-only discovery command.

```powershell
$ingressDns = kubectl -n ingress-nginx get service ingress-nginx-controller -o 'jsonpath={.status.loadBalancer.ingress[0].hostname}'
if (!$ingressDns) { throw 'Wait for ingress load balancer readiness first' }
$ingressIp = (Resolve-DnsName $ingressDns -Type A | Where-Object IPAddress | Select-Object -First 1).IPAddress
if (!$ingressIp) { throw 'Ingress DNS has no IPv4 address yet' }
$appsDomain = "$ingressIp.sslip.io"
Write-Host "APPS_DOMAIN=$appsDomain"
terraform -chdir=platform/terraform output -raw ecr_registry
```

The IP-based demonstration domain is temporary: regenerate it if the NLB address
changes. Setting these PowerShell variables does not configure Jenkins; enter the
non-secret values in its existing environment settings before starting a build.

The local Jenkins agent STILL needs AWS CLI and Argo CLI persistently installed,
and temporary Academy credentials bound around AWS steps. This task deliberately
does not rebuild/restart it or alter the Jenkinsfile. Windows AWS CLI availability
does not install it inside Docker. Set ECR_REGISTRY BEFORE starting the pipeline:
IMAGE is calculated in the first stage. Use an Argo CLI matching server 3.2.

## Safe teardown, confirmation and verification

Keep credentials valid, terraform.tfvars/password input, backend.hcl and kubeconfig.
Take any required MySQL/tool backups first. The helper never deletes the backend,
its lock mechanism, local deployment configuration or state file. ECR images are
deleted only when ecr_force_delete=true (Academy example); otherwise an occupied
repository intentionally blocks its deletion rather than silently losing images.

```powershell
# Read-only cloud preview; writes only the ignored local saved plan:
.\platform\scripts\academy.ps1 -Action PreviewDestroy
# Interactive cleanup and destroy; NOTHING destructive precedes its first confirmation:
.\platform\scripts\academy.ps1 -Action Destroy
```

The first confirmation is DESTROY <cluster-name> <account-id>. Before asking, the
helper reads state outputs, verifies current AWS account, cluster ARN and VPC,
selects that exact kubectl context and displays a Terraform destroy plan. It then
disables root/ingress auto-sync, removes only this cluster's Events ApplicationSet
and owned ingress/Argo Services, and waits for cluster-tagged load balancers in the
state-owned VPC (both ELB APIs). It does not issue direct AWS delete commands.
It replans after Kubernetes cleanup and requires APPLY DESTROY for the final saved
plan. The Terraform graph then removes workers, cluster, ECR, NAT/EIPs, VPC, disks
and optional EC2 resources it owns. Backend bucket/locks are outside that graph.
Cancelling the second confirmation preserves infrastructure but Kubernetes cleanup
has already happened; review a full plan/reapply to recover.

If ownership, permissions or cleanup fail, the helper stops and retains state.
For a partially provisioned cluster with no Argo/output/context, it intentionally
fails closed: review direct terraform plan -destroy with an operator and handle
only resources proven owned by the retained state. Never force-unlock, remove
finalizers, delete the VPC manually or start a new state to bypass a failure.

After a successful destroy:

```powershell
.\platform\scripts\academy.ps1 -Action Verify
terraform -chdir=platform/terraform plan -destroy -input=false
# Expect no remaining resources to destroy. Do NOT run an ordinary apply here.
# Use the recorded $vpcId to inspect Kubernetes-created EBS/ENIs not carrying project tags:
aws ec2 describe-network-interfaces --region us-east-1 --filters "Name=vpc-id,Values=$vpcId"
aws ec2 describe-volumes --region us-east-1 --filters Name=tag-key,Values=kubernetes.io/created-for/pvc/name
aws ecr describe-repositories --region us-east-1 --query 'repositories[].repositoryName'
aws s3api head-bucket --bucket fst-events-tfstate-ACCOUNT_ID-us-east-1 --region us-east-1
# The retained state bucket should still exist. Review billing/Academy balance too.
```

Verify absence of the recorded cluster/node groups, running project instances,
available project NATs, project EIPs, ingress/internal load balancers, unattached
project EBS disks and ENIs. Inventory may include unrelated resources: inspect
tags/recorded IDs, never delete them based only on appearing in a list. Terminated
instances and deleted NAT records can remain visible temporarily without charging.
Do not delete the team backend to make inventories empty. Remove/stop only the
temporary tunnel container when finished, and clear temporary credential/password
environment values through your secure local workflow.

## Validation

Backend-disabled init and Terraform validate pass with the existing provider lock.
Three plan-only mock tests cover disabled EC2 (including a nonexistent SSH key),
Academy EC2/profile, and standard AWS EC2/IAM/internal Argo options. Mocked VPC/EKS
outputs isolate root optional-resource references; these tests do not certify real
EKS creation, AWS write permissions, pod scheduling or CSI provisioning.

All six local Helm renders passed at kube-version 1.34.0: Argo, monitoring,
ingress and application review/staging/prod. Application Helm lint passed (only
an optional icon recommendation). GitOps YAML parsing, PowerShell parsing, Bash
syntax and git diff --check passed. Offline helper mocks also verified argument
forwarding, cancellation before destructive cleanup, AccessDenied fail-closed
behavior, and the confirmed 404 bootstrap path. These are local validations;
no live deployment, tunnel connection or actual teardown was exercised.

```powershell
# Local validation only, before backend init (or in an isolated copy):
terraform -chdir=platform/terraform init -backend=false -lockfile=readonly -input=false
terraform -chdir=platform/terraform fmt -check -recursive
terraform -chdir=platform/terraform validate
terraform -chdir=platform/terraform test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File platform/scripts/tests/helpers.Tests.ps1
```

Do not run backend-disabled initialization over a team's active working directory
without understanding its current backend. Deployment helpers use the approved
backend and default workspace; they never automatically migrate it.

Sources: [AWS EKS support](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html),
[Argo 3.2 tested Kubernetes versions](https://argo-cd.readthedocs.io/en/release-3.2/operator-manual/tested-kubernetes-versions/),
[ingress compatibility](https://github.com/kubernetes/ingress-nginx),
[S3 backend permissions/locking](https://developer.hashicorp.com/terraform/language/backend/s3),
[AWS EKS pricing](https://aws.amazon.com/eks/pricing/),
[T3 specifications/pricing](https://aws.amazon.com/ec2/instance-types/t3/),
[AWS VPC pricing](https://aws.amazon.com/vpc/pricing/).

## Changed-file index

Terraform changes in `platform/terraform/`:
`variables.tf`, `versions.tf`, `network.tf`, `eks.tf`, `devops-ec2.tf`,
`ansible-handoff.tf`, `outputs.tf`, `argocd.tf`, `ecr.tf`,
`terraform.tfvars.academy.example`, `terraform.tfvars.example`,
`backend.hcl.example`, `values/argocd.yaml.tftpl`.
New files there: `moved.tf`, `tests/academy.tftest.hcl`, `tests/mock-key.pub`.
`providers.tf`, templates and `.terraform.lock.hcl` were inspected and retained.

Automation: `platform/scripts/bootstrap-state.sh`, `platform/scripts/destroy.sh`,
`platform/scripts/post-apply.sh`, `platform/Makefile`.
New automation: `platform/scripts/academy.ps1`, `platform/scripts/bootstrap-state.ps1`,
`platform/scripts/tests/helpers.Tests.ps1`, and
`platform/scripts/argocd-tunnel/{Dockerfile,entrypoint.sh,.dockerignore}`.

GitOps: `platform/gitops/platform/apps/10-ingress-nginx.yaml` and
`platform/gitops/platform/apps/20-monitoring.yaml`.
Documentation/exclusions: `.gitignore`, new `platform/.gitattributes`,
`platform/README.md`, and this runbook `docs/ACADEMY-DEMO.md`.
The root Jenkinsfile, application sources, existing local Jenkins files and
pre-existing Jenkinsfile.backup were not modified.
