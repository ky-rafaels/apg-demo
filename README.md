# APG Demo Deployment Steps

1. Prep workload and mgmt cluster nodes by installing rocky linux on single node 
2. Deploy mgmt cluster 
3. Install Git on mgmt cluster
4. Expose Git via traefik http,tlsRoute resource
5. Enable Harbor and mount to S3 storage
6. Push application images to Harbor
7. Create flux resources to deploy sample apps or do from project resource
8. Deploy workload cluster from mgmt


# Deployment

## Prep nodes

First, prep each of the nodes for the management cluster and the workload cluster. In this case I'll be deploying a 2 node management cluster and a single node workload cluster.

1. Install ubuntu 22.04 server on each node - install with a common admin user nutanix, ssh key, and static IP address
2. After OS installed on all nodes, confirm able to access each with ssh key

```bash
ssh nutanix@192.168.1.47 -i /Users/kylerafaels/.ssh/nkp-control
ssh nutanix@192.168.1.48 -i /Users/kylerafaels/.ssh/nkp-control
ssh nutanix@192.168.1.49 -i /Users/kylerafaels/.ssh/nkp-control
```

3. Configure each for passwordless sudo access (Demo only)

```bash
visudo

# Add to file
nutanix ALL=(ALL) NOPASSWD:ALL
```

4. Each node will be using the localvolumeprovisioner to mount pvs to containers. Configure LVMs on each node for persistent storage. Run the script provided at `./scripts/create-disks.sh` on each node. You should then have a filesystem that looks something like this:
```console
$ lsblk

└─nvme1n1p3               259:15   0   3.5T  0 part
  ├─ubuntu--vg-ubuntu--lv 252:6    0   600G  0 lvm  /
  ├─ubuntu--vg-10000001   252:7    0   130G  0 lvm  /mnt/disks/10000001
  ├─ubuntu--vg-10000002   252:8    0    30G  0 lvm  /mnt/disks/10000002
  ├─ubuntu--vg-10000003   252:9    0    30G  0 lvm  /mnt/disks/10000003
  ├─ubuntu--vg-10000004   252:10   0    30G  0 lvm  /mnt/disks/10000004
  ├─ubuntu--vg-11000001   252:11   0    50G  0 lvm  /mnt/disks/11000001
  ├─ubuntu--vg-11000002   252:12   0    50G  0 lvm  /mnt/disks/11000002
  ├─ubuntu--vg-11100001   252:13   0    50G  0 lvm  /mnt/disks/11100001
  ├─ubuntu--vg-10000005   252:14   0   150G  0 lvm  /mnt/disks/10000005
  ├─ubuntu--vg-10000006   252:15   0   150G  0 lvm  /mnt/disks/10000006
  └─ubuntu--vg-10000007   252:16   0   150G  0 lvm  /mnt/disks/10000007
```

5. Update the `./mgmt-cluster/mgmt_preprovisioned_inventory.yaml`

```bash
cat << EOF > ./mgmt-cluster/mgmt_preprovisioned_inventory.yaml
---
apiVersion: infrastructure.cluster.konvoy.d2iq.io/v1alpha1
kind: PreprovisionedInventory
metadata:
  name: nkp-workload-1-control-plane
  namespace: edge-clusters
  labels:
    cluster.x-k8s.io/cluster-name: nkp-workload-1 
    clusterctl.cluster.x-k8s.io/move: ""
spec:
  hosts:
    - address: 192.168.1.48
  sshConfig:
    port: 22
    user: nutanix
    privateKeyRef:
      name: nkp-workload-1-ssh-key 
      namespace: edge-clusters
---
apiVersion: infrastructure.cluster.konvoy.d2iq.io/v1alpha1
kind: PreprovisionedInventory
metadata:
  name: nkp-workload-1-md-0
  namespace: edge-clusters 
  labels:
    cluster.x-k8s.io/cluster-name: nkp-workload-1
    clusterctl.cluster.x-k8s.io/move: ""
spec:
  hosts:
    - {} 
  sshConfig:
    port: 22
    user: nutanix
    privateKeyRef:
      name: nkp-workload-1-ssh-key
      namespace: edge-clusters
EOF
```

## Create preprovisioned cluster templates for mgmt cluster

```bash
export SSH_PRIVATE_KEY_FILE=/Users/kylerafaels/.ssh/nkp-control`

nkp create cluster preprovisioned \
--cluster-name nkp-2-17 \
--control-plane-endpoint-host 192.168.1.49 \
--control-plane-replicas 2 \
--worker-replicas 0 \
--ssh-private-key-file ${SSH_PRIVATE_KEY_FILE} \
--pre-provisioned-inventory-file ./mgmt-cluster/mgmt-preprovisioned_inventory.yaml \
--dry-run -o yaml > ./mgmt-cluster/nkp-2-17.yaml
```

### Then create the bootstrap and apply manifests.
```console
$ nkp version
catalog: v0.8.1
diagnose: v0.12.0
imagebuilder: v2.17.0
kommander: v2.17.0
konvoy: v2.17.0
konvoybundlepusher: v2.17.0
mindthegap: v1.24.0
nkp: v2.17.0
```
```bash
nkp create bootstrap

# Then apply management cluster manifests to bootstrap
kubectl apply -f ./mgmt/nkp-2-17.yaml
```

#### *~OPTIONAL~*
------
If you are running a single node management cluster, this would also be the time to remove any restrictive scheduling taints on the control plane node:
```bash
export NODE_NAME=$(kubectl get no --no-headers | awk '{ print $1 }')

# Remove taint so that normal pods can be scheduled on this node
kubectl taint no ${NODE_NAME} node-role.kubernetes.io/control-plane:NoSchedule-

# The following is required to use the control plane node for running metallb
kubectl label node ${NODE_NAME}  node.kubernetes.io/exclude-from-external-load-balancers-
```
-----

### Create capi components and move cluster resources from bootstrap to mgmt

```console
$ nkp create capi-components --kubeconfig <path-to-mgmt-kubeconfig>

# Check you are set on the bootstrap context
$ k config get-contexts
CURRENT   NAME                            CLUSTER                         AUTHINFO                        NAMESPACE
*         kind-konvoy-capi-bootstrapper   kind-konvoy-capi-bootstrapper   kind-konvoy-capi-bootstrapper   default

# Move capi resources to management cluster
$ nkp move capi-resources --to-kubeconfig ~/.kube/nkp-control-plane-onprem.conf
```

You can then view the progress by watching logs in `cappp-system`. As soon as the kubeconfig is available apply the metallb config and then the Kommander installation config:

```bash
kubectl apply -f mgmt-cluster/metallb.yaml

nkp install kommander --installer-config ./mgmt-cluster/kommander-install.conf -v5
```

## Create preprovisioned cluster templates for workload cluster 

After the management cluster is successfully created, generate the cluster manifests for the workload cluster. 

```bash
nkp create cluster preprovisioned \
--cluster-name nkp-workload-1 \
--namespace edge-clusters \
--control-plane-endpoint-host 192.168.1.48 \
--control-plane-replicas 1 \
--worker-replicas 0 \
--ssh-private-key-file ${SSH_PRIVATE_KEY_FILE} \
--pre-provisioned-inventory-file worker-preprovisioned-inventory.yaml \
--registry-mirror-url https://registry.internal.example.com \
--registry-mirror-cacert /Users/kylerafaels/Projects/nutanix/apg/mgmt-certs/registry-ca.crt \
--dry-run -o yaml > workload-nkp-2-17.yaml
```