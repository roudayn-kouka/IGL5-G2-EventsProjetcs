
#!/bin/sh
set -eu

: "${WORKSPACE:?Missing WORKSPACE}"
: "${AWS_REGION:?Missing AWS_REGION}"
: "${BUILD_NUMBER:?Missing BUILD_NUMBER}"
: "${FEATURE_SLUG:?Missing FEATURE_SLUG}"

TF_IMAGE="hashicorp/terraform:1.9"
TF_WORK="$WORKSPACE/terraform-demo-$BUILD_NUMBER"

export TF_VAR_aws_region="$AWS_REGION"
export TF_VAR_demo_name="fst-events-${FEATURE_SLUG}-${BUILD_NUMBER}"
export TF_IN_AUTOMATION=1

# Never overwrite an existing state from a failed cleanup
if [ -e "$TF_WORK" ]; then
    echo "ERROR: Existing Terraform demo directory: $TF_WORK"
    echo "Inspect and clean it before retrying."
    exit 1
fi

mkdir -p "$TF_WORK"
cp "$WORKSPACE/terraform/demo/main.tf" "$TF_WORK/main.tf"

tf() {
    docker run --rm \
        --volumes-from jenkins \
        -w "$TF_WORK" \
        -e AWS_ACCESS_KEY_ID \
        -e AWS_SECRET_ACCESS_KEY \
        -e AWS_SESSION_TOKEN \
        -e TF_VAR_aws_region \
        -e TF_VAR_demo_name \
        -e TF_IN_AUTOMATION \
        "$TF_IMAGE" "$@"
}

echo "========== TERRAFORM INIT =========="
tf init -input=false -no-color

cleanup() {
    result=$?
    trap - 0

    echo "========== TERRAFORM DESTROY =========="

    if tf destroy -input=false -auto-approve -no-color; then
        echo "SUCCESS: Temporary AWS resource destroyed."
        rm -rf "$TF_WORK"
    else
        echo "ERROR: Terraform destroy failed!"
        echo "State preserved at: $TF_WORK"
        result=1
    fi

    exit "$result"
}

trap cleanup 0
trap 'exit 130' INT
trap 'exit 143' TERM

echo "========== TERRAFORM PLAN =========="
tf plan -input=false -no-color -out=tfplan

echo "========== TERRAFORM APPLY =========="
tf apply -input=false -no-color tfplan

echo "========== CREATED RESOURCE =========="
tf output -raw security_group_id
echo ""

echo "Resource created successfully."
echo "Cleanup will run automatically."
