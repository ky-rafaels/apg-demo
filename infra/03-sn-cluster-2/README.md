# Container registry configuration
export REGISTRY_URL="https://registry.internal.example.com"
<!-- export REGISTRY_USERNAME="admin" -->
<!-- export REGISTRY_PASSWORD="SuperSecurePassword" -->
export REGISTRY_CA="/Users/kylerafaels/Projects/nutanix/apg/mgmt-certs/registry-ca.crt"

# Cluster configuration
export CLUSTER_NAME="nkp-workload-2"

# Kubernetes API Server VIP (must be on same subnet as your nodes)
export CLUSTER_VIP="192.168.1.46"

# Network interface name (find using 'ip address' on control plane nodes)
export CLUSTER_VIP_ETH_INTERFACE="enp3s0"

# Control plane node IP addresses (minimum 3 for production)
export CONTROL_PLANE_1_ADDRESS="192.168.1.46"

# SSH configuration for node access
export SSH_USER="nutanix"
export SSH_PRIVATE_KEY_FILE="/Users/kylerafaels/.ssh/nkp-control"
export SSH_PRIVATE_KEY_SECRET_NAME=${CLUSTER_NAME}-ssh-key

```bash
kubectl create secret generic ${SSH_PRIVATE_KEY_SECRET_NAME} \
  --from-file=ssh-privatekey="${SSH_PRIVATE_KEY_FILE}"
kubectl label secret ${SSH_PRIVATE_KEY_SECRET_NAME} clusterctl.cluster.x-k8s.io/move=""
```

# Create package bundle

```bash
# Ensure you are in unpacked airgap bundle 
nkp create package-bundle ubuntu-22.04 --artifacts-directory image-artifacts/

nkp upload image-artifacts \
--artifacts-directory ./image-artifacts \
--ssh-host 192.168.1.46 \
--ssh-username nutanix \
--ssh-private-key-file /Users/kylerafaels/.ssh/nkp-control
```

# Create the NKP cluster manifest
```bash
nkp create cluster preprovisioned \
  --cluster-name=${CLUSTER_NAME} \
  --namespace=edge-clusters \
  --control-plane-endpoint-host=${CLUSTER_VIP} \
  --pre-provisioned-inventory-file=worker-preprovisioned-inventory.yaml \
  --ssh-private-key-file=${SSH_PRIVATE_KEY_FILE} \
  --registry-mirror-url=${REGISTRY_URL} \
  --registry-mirror-cacert=${REGISTRY_CA} \
  --control-plane-replicas=1 \
  --worker-replicas=0 \
  --dry-run \
  --output=yaml \
  > ${CLUSTER_NAME}.yaml
  ```
  --virtual-ip-interface ${CLUSTER_VIP_ETH_INTERFACE} \