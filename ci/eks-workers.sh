
#!/bin/sh
set -eu

CLUSTER="fst-events-eks"
NODEGROUP="fst-events-nodes"
REGION="${AWS_REGION:?AWS_REGION is required}"
ACTION="${1:-up}"

# ------------------------------------------------------------
# Describe the existing EKS managed node group
# ------------------------------------------------------------
ng() {
    aws eks describe-nodegroup \
        --region "$REGION" \
        --cluster-name "$CLUSTER" \
        --nodegroup-name "$NODEGROUP" "$@"
}

# ------------------------------------------------------------
# Wait until the node group is ACTIVE
# ------------------------------------------------------------
wait_active() {
    i=0

    while [ "$i" -lt 60 ]; do
        status=$(ng --query 'nodegroup.status' --output text)

        case "$status" in
            ACTIVE)
                return 0
                ;;
            UPDATING|CREATING)
                echo "Node group status: $status"
                sleep 10
                ;;
            *)
                echo "ERROR: Node group status: $status"
                ng --query 'nodegroup.health.issues'
                exit 1
                ;;
        esac

        i=$((i + 1))
    done

    echo "ERROR: Timed out waiting for node group."
    exit 1
}

# ------------------------------------------------------------
# Scale workers up or down and wait for AWS update
# ------------------------------------------------------------
scale_to() {
    size="$1"

    echo "Scaling EKS workers to $size"

    update_id=$(aws eks update-nodegroup-config \
        --region "$REGION" \
        --cluster-name "$CLUSTER" \
        --nodegroup-name "$NODEGROUP" \
        --scaling-config "minSize=0,maxSize=1,desiredSize=$size" \
        --query 'update.id' \
        --output text)

    echo "EKS update ID: $update_id"

    i=0

    while [ "$i" -lt 60 ]; do
        status=$(aws eks describe-update \
            --region "$REGION" \
            --name "$CLUSTER" \
            --nodegroup-name "$NODEGROUP" \
            --update-id "$update_id" \
            --query 'update.status' \
            --output text)

        echo "EKS update status: $status"

        case "$status" in
            Successful)
                echo "Scaling update completed."
                return 0
                ;;
            Failed|Cancelled)
                echo "ERROR: EKS scaling failed."

                aws eks describe-update \
                    --region "$REGION" \
                    --name "$CLUSTER" \
                    --nodegroup-name "$NODEGROUP" \
                    --update-id "$update_id"

                exit 1
                ;;
        esac

        i=$((i + 1))
        sleep 10
    done

    echo "ERROR: EKS scaling timed out."
    exit 1
}

# ------------------------------------------------------------
# Check whether Kubernetes has a Ready worker
# ------------------------------------------------------------
ready_node_exists() {
    kubectl get nodes -o json | jq -e '
        any(.items[];
            any(.status.conditions[];
                .type == "Ready" and .status == "True"
            )
        )
    ' >/dev/null
}

# ------------------------------------------------------------
# Wait for at least one Ready worker
# ------------------------------------------------------------
wait_ready() {
    echo "Waiting for an EKS worker to become Ready..."

    i=0

    while [ "$i" -lt 60 ]; do
        if ready_node_exists; then
            echo "EKS worker is Ready."
            kubectl get nodes
            return 0
        fi

        i=$((i + 1))
        sleep 10
    done

    echo "ERROR: No Ready worker after 10 minutes."

    kubectl get nodes -o wide || true
    ng --query 'nodegroup.health.issues'

    exit 1
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
case "$ACTION" in
    up|down) ;;
    *)
        echo "Usage: eks-workers.sh up|down"
        exit 1
        ;;
esac

wait_active

desired=$(ng \
    --query 'nodegroup.scalingConfig.desiredSize' \
    --output text)

echo "Current desired worker count: $desired"

# ------------------------------------------------------------
# DOWN: scale worker group to zero
# ------------------------------------------------------------
if [ "$ACTION" = "down" ]; then
    if [ "$desired" != "0" ]; then
        scale_to 0
    else
        echo "Workers already scaled to zero."
    fi

    echo "EKS workers stopped."
    exit 0
fi

# ------------------------------------------------------------
# UP: configure Kubernetes access
# ------------------------------------------------------------
export KUBECONFIG=/tmp/eks-kubeconfig

aws eks update-kubeconfig \
    --region "$REGION" \
    --name "$CLUSTER"

# Already healthy: do nothing
if ready_node_exists; then
    echo "Worker already Ready. No scaling needed."
    kubectl get nodes
    exit 0
fi

# ------------------------------------------------------------
# Recover missing workers
# ------------------------------------------------------------
case "$desired" in
    0)
        echo "Worker group is scaled down."
        scale_to 1
        ;;

    1)
        count=$(kubectl get nodes -o json | jq '.items | length')

        if [ "$count" -eq 0 ]; then
            echo "No registered nodes despite desiredSize=1."
            echo "Recycling empty node group..."

            scale_to 0
            wait_active
            scale_to 1
        else
            echo "Worker exists but is not Ready."
            echo "Waiting for recovery..."
        fi
        ;;

    *)
        echo "ERROR: Unexpected desired capacity: $desired"
        exit 1
        ;;
esac

# ------------------------------------------------------------
# Final verification
# ------------------------------------------------------------
wait_ready

echo "EKS worker startup completed successfully."
