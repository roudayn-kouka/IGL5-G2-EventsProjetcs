# EKS v20.37.2 Academy compatibility patch

Runtime-only vendored copy of
https://github.com/terraform-aws-modules/terraform-aws-eks/tree/v20.37.2
(Apache-2.0; LICENSE retained). Root .tf files, referenced runtime submodules and
user-data templates are retained. Examples and unrelated submodules are omitted.
UPSTREAM-SHA256.json records the unmodified upstream bytes copied from the
installed v20.37.2 module, including main.tf BEFORE the patch.

The sole behavioral patch is the count of data.aws_iam_session_context.current
in main.tf. Read the session's source IAM role only when automatic creator-admin
access is enabled OR an enabled customer KMS encryption key needs implicit key
administrators. Upstream reads it unconditionally whenever create=true.

Academy disables automatic creator access and customer KMS; its administrator is
explicitly configured in the calling module using STS GetCallerIdentity. The
voclabs role's denied GetRole is not requested. No identity/role assumption,
IAM trust/policy or endpoint override is introduced. All AWS authorization checks
for provisioning and EKS access entries remain in force.

Keep the root module address module.eks unchanged. No state migration is required.
Do not edit .terraform/modules. After checking out this change, terraform init
-backend=false -lockfile=readonly refreshes only local module/provider metadata;
use the existing backend as usual for real plans.

When upgrading upstream, review this patch, the complete runtime file diff and
eks-access.tftest.hcl. Do not silently regenerate or broaden the patch.
