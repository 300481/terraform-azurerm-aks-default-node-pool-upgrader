#!/bin/sh

# resource from where to get the token
RESOURCE=https%3A%2F%2Fmanagement.azure.com%2F

# Check if a node version is given, if not just exit
if [[ ${KUBERNETES_NODE_VERSION} == "empty" ]] ; then
    echo "No Kubernetes Version set for the default node pool."
    exit 0
fi

# install needed packages
echo "Install neccessary packages."
apk add curl jq

# Get Token (valid for 1 hour)
echo "Authenticate for Azure REST API."
# https://docs.microsoft.com/en-us/rest/api/azure/#create-the-request
function getToken(){
    curl -s -X POST -H "Content-Type: application/x-www-form-urlencoded" \
      -d "grant_type=client_credentials&resource=${RESOURCE}&client_id=${ARM_CLIENT_ID}&client_secret=${ARM_CLIENT_SECRET_URL_ENCODED}" \
      https://login.microsoftonline.com/${ARM_TENANT_ID}/oauth2/token | \
      jq -r '.access_token'
}
TOKEN=$(getToken)

# Get Cluster Provisioning State
# https://docs.microsoft.com/en-us/rest/api/aks/managedclusters/get
function getClusterProvisioningState(){
    curl -s -X GET -H "Authorization: Bearer ${TOKEN}" \
      https://management.azure.com/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP_NAME}/providers/Microsoft.ContainerService/managedClusters/${CLUSTER_NAME}?api-version=2020-09-01 | \
      jq -r '.properties.provisioningState'
}

echo "Waiting for succeeded Cluster Provisioning State for 10 minutes."
for COUNT in $(seq 1 60); do
    CLUSTER_PROVISIONING_STATE=$(getClusterProvisioningState)
    if [[ ${CLUSTER_PROVISIONING_STATE} == "Succeeded" ]] ; then
        echo "Cluster Provisioning State is succeeded."
        break
    fi
    if [[ ${COUNT} -eq 60 ]] ; then
        echo "ERROR: Cluster Provisioning State not succeeded within 10 minutes."
        echo "ERROR: Stopping Upgrade of Default Node Pool."
        echo "ERROR: YOUR ACTION IS REQUIRED: please update the Default Node Pool manually via the Portal."
        exit 1
    fi
    echo "Cluster Provisioning State: ${CLUSTER_PROVISIONING_STATE}"
    sleep 10
done

# Get Node Pool Orchestrator Version
# https://docs.microsoft.com/en-us/rest/api/aks/agentpools/get
function getNodePoolOrchestratorVersion(){
    curl -s -X GET -H "Authorization: Bearer ${TOKEN}" \
      https://management.azure.com/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP_NAME}/providers/Microsoft.ContainerService/managedClusters/${CLUSTER_NAME}/agentPools/${DEFAULT_POOL_NAME}?api-version=2020-09-01 | \
      jq -r '.properties.orchestratorVersion'
}
NODE_POOL_ORCHESTRATOR_VERSION=$(getNodePoolOrchestratorVersion)
if [[ ${NODE_POOL_ORCHESTRATOR_VERSION} == ${KUBERNETES_NODE_VERSION} ]] ; then
    echo "Node Pool Orchestrator Version already updated: ${KUBERNETES_NODE_VERSION}"
    exit 0
fi

# Get Node Pool Provisioning State
# https://docs.microsoft.com/en-us/rest/api/aks/agentpools/get
function getNodePoolProvisioningState(){
    curl -s -X GET -H "Authorization: Bearer ${TOKEN}" \
      https://management.azure.com/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP_NAME}/providers/Microsoft.ContainerService/managedClusters/${CLUSTER_NAME}/agentPools/${DEFAULT_POOL_NAME}?api-version=2020-09-01 | \
      jq -r '.properties.provisioningState'
}

function waitingForNodePoolProvisioningState(){
    TIMEOUT=${1:-60}
    echo "Waiting for succeeded Node Pool Provisioning State for ${TIMEOUT} times 10 seconds."
    for COUNT in $(seq 1 ${TIMEOUT}); do
        NODE_POOL_PROVISIONING_STATE=$(getNodePoolProvisioningState)
        if [[ ${NODE_POOL_PROVISIONING_STATE} == "Succeeded" ]] ; then
            echo "Node Pool Provisioning State is succeeded."
            break
        fi
        if [[ ${COUNT} -eq ${TIMEOUT} ]] ; then
            echo "ERROR: Node Pool Provisioning State not succeeded within ${TIMEOUT} times 10 seconds."
            echo "ERROR: Stopping Upgrade of Default Node Pool."
            echo "ERROR: YOUR ACTION IS REQUIRED: please update the Default Node Pool manually via the Portal."
            exit 1
        fi
        echo "Node Pool Provisioning State: ${NODE_POOL_PROVISIONING_STATE}"
        sleep 10
    done
}

# Wait for 10 minutes
waitingForNodePoolProvisioningState 60

# Get Node Pool
# https://docs.microsoft.com/en-us/rest/api/aks/agentpools/get
function getNodePool(){
    curl -s -X GET -H "Authorization: Bearer ${TOKEN}" \
      https://management.azure.com/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP_NAME}/providers/Microsoft.ContainerService/managedClusters/${CLUSTER_NAME}/agentPools/${DEFAULT_POOL_NAME}?api-version=2020-09-01
}

# Update Node Pool
# https://docs.microsoft.com/en-us/rest/api/aks/agentpools/createorupdate
function updateNodePool(){
    curl -s -X PUT -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -d @nodepool.json \
      https://management.azure.com/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP_NAME}/providers/Microsoft.ContainerService/managedClusters/${CLUSTER_NAME}/agentPools/${DEFAULT_POOL_NAME}?api-version=2020-09-01
}

# Get the current Node Pool Config, adjust it with the new version, save it in nodepool.json
getNodePool| jq ".properties.orchestratorVersion = \"${KUBERNETES_NODE_VERSION}\"" > nodepool.json

# Do the update
updateNodePool

# Get a new token for 1 hour
TOKEN=$(getToken)

# Again, wait for the succeeded Node Pool Provisioning State
# Wait for 50 minutes
waitingForNodePoolProvisioningState 300

exit 0