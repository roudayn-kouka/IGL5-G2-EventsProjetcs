# Academy EKS planning: explicit operator access

## Cause and minimal module patch

The installed upstream EKS module 20.37.2 main.tf lines 8-15 declares
`aws_iam_session_context.current` with `count = local.create ? 1 : 0`.
The AWS provider 5.100.0 resolves an assumed-role STS ARN using IAM GetRole.
The current Academy identity is an assumed session of `voclabs`; its GetRole is
explicitly denied by the lab policy. This metadata lookup is not required to
provision the configured cluster/service roles.

Simply disabling enable_cluster_creator_admin_permissions is insufficient: the
data source's count is unconditional. No public input disables only that lookup.
The two consumers are the automatic cluster-creator access entry (main.tf 227)
and implicit customer KMS key administrators (main.tf 316). Academy already
disables customer KMS keys.

`platform/terraform/modules/eks-academy` contains upstream 20.37.2 runtime code
and license. Only the session-context count is changed: evaluate it only when
automatic creator access or implicit customer KMS administrators require it.
The calling module remains `module.eks`, so resource addresses are unchanged.
The existing provider lockfile is unchanged. No downloaded module source is
patched, no IAM policies/trust are changed, and no alternate identity is assumed.
UPSTREAM-SHA256.json records upstream hashes for review; only main.tf differs.

## Administrator identity and LabRole

Read-only STS verification confirmed the account's existing voclabs session.
The Terraform Kubernetes/Helm exec configuration invokes AWS get-token without
--role-arn; kubectl with the same credentials likewise authenticates as voclabs.
No EKS-specific kubeconfig exec user was found during this check (no cluster has
been applied). Different future AWS profiles must be reviewed before use.

The explicit STANDARD access entry uses the IAM role ARN
`arn:aws:iam::471112616916:role/voclabs`, not its temporary STS session ARN.
It associates AmazonEKSClusterAdminPolicy with cluster scope, preserving the same
administrator intended by the original automatic creator setting. STS account
identity is used to construct this ARN; a postcondition rejects a different caller
role or mismatched LabRole account rather than silently granting it access.

LabRole exists, trusts EKS/EC2 and itself, but does not trust voclabs for assumption.
It remains the cluster/worker service role. Adding only LabRole as administrator
would not authorize the actual local operator. Managed node groups receive their
own EKS-managed node access mapping; a role cannot have multiple access entries
with different types. Do not conflate service/node roles with operator access.

The Terraform operator still needs EKS CreateAccessEntry/AssociateAccessPolicy
and lifecycle read/delete permissions, as well as all normal cluster/node/VPC
provisioning permissions and authorized PassRole for LabRole. EKS access policies
grant Kubernetes permissions, not IAM permissions. Listing EKS access policies
confirmed AmazonEKSClusterAdminPolicy exists. Successful plans do not test write
permissions; none of those permissions was exercised by creating a resource.
The denied IAM action is avoided because it is unnecessary, not bypassed through
different credentials or altered AWS endpoints/policies.

## Bootstrap networking and validation

`module.eks` explicitly depends on `module.vpc`. Without that dependency, targeting
EKS could select only the VPC/private subnets and omit NAT/routes that private
workers require to pull images and start. The dependency includes all existing
VPC networking in the bootstrap graph; private workers and the restricted API
CIDR remain unchanged. No public node exposure is introduced.

Run `terraform -chdir=platform/terraform get` after this source change. This
refreshes local module metadata and does not migrate deployment state. Then run
`validate` and `test`. The five plan-only tests include the real patched module:
no session-context read in Academy, explicit operator admin/policy association,
unchanged IAM/network restrictions, standard automatic creator behavior, and
the existing optional-toolchain scenarios. Tests use mock providers only.

Real infrastructure planning uses the existing initialized backend and default
workspace. Plans briefly use ordinary backend locking; they do not apply or
rewrite deployment state. A generated temporary Grafana value was provided
only to satisfy the unrelated required input; Grafana is outside these targets.
Do not apply that review artifact: regenerate using the intended secret input.
Full platform planning must follow infrastructure bootstrap before installing
Argo/CD/monitoring, as explained in ACADEMY-DEMO.md.

Final verification: Terraform validation and all five mocked plan-only tests
passed. The real targeted infrastructure plan completed with exit code 0:
47 to add, 0 to change, 0 to destroy. It includes the VPC, four subnets,
NAT/EIP/routes, EKS, one two-worker node group, five addons, ECR and the operator
access entry/policy association. No IAM/KMS creation or session-context lookup
appears in the plan. The only diagnostic is the expected resource-targeting
warning. No remaining permission error occurred during planning; write permissions
and actual kubectl connectivity remain untested because nothing was applied.

Sources:
[upstream v20.37.2](https://github.com/terraform-aws-modules/terraform-aws-eks/blob/v20.37.2/main.tf),
[provider lookup implementation](https://github.com/hashicorp/terraform-provider-aws/blob/v5.100.0/internal/service/iam/session_context_data_source.go),
[AWS EKS access entry rules](https://docs.aws.amazon.com/eks/latest/userguide/creating-access-entries.html).
