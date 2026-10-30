
#!/bin/sh
set -eu

CLUSTER="fst-events-eks"
NODEGROUP="fst-events-nodes"
REGION="${AWS_REGION:?AWS_REGION is required}"
ACTION="${1:-up}"

ng() {
    aws eks describe-nodegroup \
        --region "$REGION" \
        --cluster-name "$CLUSTER" \
        --nodegroup-name "$NODEGROUP" "$@"
}

wait_active() {
    for i in $(seq 1 60); do
        status=$(ng --query 'nodegroup.status' --output text)

        case "$status" in
            ACTIVE) return 0 ;;
            UPDATING|CREATING) sleep 10 ;;
            *)
                echo "Node group status: $status"
                ng --query 'nodegroup.health.issues'
                exit 1
                ;;
        esac
    done

    echo "Timed out waiting for node group."
    exit 1
}

scale_to() {
    size="$1"
    echo "Scaling EKS workers to $size"

    update_id=$(aws eks update-nodegroup-config \
        --region "$REGION" \
        --cluster-name "$CLUSTER" \
        --nodegroup-name "$NODEGROUP" \
        --scaling-config "minSize=0,maxSize=1,desiredSize=$size" \
        --query 'update.id' --output text)

    for i in $(seq 1 60); do
        status=$(aws eks describe-update \
            --region "$REGION" \
            --cluster-name "$CLUSTER" \
            --nodegroup-name "$NODEGROUP" \
            --update-id "$update_id" \
            --query 'update.status' --output text)

        case "$status" in
            Successful) return 0 ;;
            Failed|Cancelled)
                echo "EKS scaling failed:"
                aws eks describe-update \
                    --region "$REGION" \
                    --cluster-name "$CLUSTER" \
                    --nodegroup-name "$NODEGROUP" \
                    --update-id "$update_id"
                exit 1
                ;;
        esac
        sleep 10
    done

    echo "EKS scaling timed out."
    exit 1
}

ready_node_exists() {
    kubectl get nodes -o json | jq -e '
        any(.items[];
            any(.status.conditions[];
                .type == "Ready" and .status == "True"
            )
        )
    ' >/dev/null
}

wait_ready() {
    for i in $(seq 1 60); do
        if ready_node_exists; then
            echo "EKS worker is Ready."
            kubectl get nodes
            return 0
        fi
        sleep 10
    done

    echo "No Ready worker after 10 minutes."
    kubectl get nodes -o wide
    ng --query 'nodegroup.health.issues'
    exit 1
}

wait_active
desired=$(ng --query 'nodegroup.scalingConfig.desiredSize' --output text)

if [ "$ACTION" = "down" ]; then
    if [ "$desired" != "0" ]; then
        scale_to 0
    fi
    echo "EKS workers scaled down."
    exit 0
fi

[ "$ACTION" = "up" ] || {
    echo "Usage: eks-workers.sh up|down"
    exit 1
}

export KUBECONFIG=/tmp/eks-kubeconfig
aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER"

if ready_node_exists; then
    echo "Worker already Ready. No scaling needed."
    exit 0
fi

case "$desired" in
    0)
        scale_to 1
        ;;
    1)
        count=$(kubectl get nodes -o json | jq '.items | length')

        if [ "$count" -eq 0 ]; then
            echo "No registered nodes despite desiredSize=1."
            echo "Recycling empty node group..."
            scale_to 0
            scale_to 1
        else
            echo "Node exists but is not Ready; waiting for recovery."
        fi
        ;;
    *)
        echo "Unexpected desired capacity: $desired"
        exit 1
        ;;
esac

wait_ready
