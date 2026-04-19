INSTALLATION_NAME="arc-runner-set"
NAMESPACE="arc-runners"
NAMESPACES="arc-systems"

helm upgrade --install arc \
    --namespace "${NAMESPACES}" \
    --create-namespace \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller

helm upgrade --install "${INSTALLATION_NAME}" \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    -f github-runner.yaml  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set


helm upgrade --install "${INSTALLATION_NAME}-arm" \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    -f github-runner-arm.yaml  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set





#Manstier
#
helm upgrade --install "${INSTALLATION_NAME}-mantiser" \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    -f github-runner-mantiser.yaml  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set


helm upgrade --install "${INSTALLATION_NAME}-arm-mantiser" \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    -f github-runner-arm-mantiser.yaml  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set

#
helm upgrade --install "${INSTALLATION_NAME}-hrb" \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    -f github-runner-hrb.yaml  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set --debug




helm upgrade --install "${INSTALLATION_NAME}-viodlar" \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    -f github-runner-viodlar.yaml  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set --debug


helm upgrade --install "${INSTALLATION_NAME}-samma" \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    -f github-runner-samma.yaml  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set --debug



