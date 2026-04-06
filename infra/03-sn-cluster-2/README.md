# Container registry configuration
export REGISTRY_URL="https://registry.internal.example.com"
<!-- export REGISTRY_USERNAME="admin" -->
<!-- export REGISTRY_PASSWORD="SuperSecurePassword" -->
export REGISTRY_CA="/home/nkp/cacert.crt"

# Cluster configuration
export CLUSTER_NAME="nkp-sn-cluster-2"

# Kubernetes API Server VIP (must be on same subnet as your nodes)
export CLUSTER_VIP="xxx.yyy.zzz.70"

# Network interface name (find using 'ip address' on control plane nodes)
export CLUSTER_VIP_ETH_INTERFACE="ens3"
#The network interface name (ens3 in this example) can vary depending on the OS and platform; use the 'ip address' command on your nodes to find the correct name

# Control plane node IP addresses (minimum 3 for production)
export CONTROL_PLANE_1_ADDRESS="192.168.1.46"

# SSH configuration for node access
export SSH_USER="konvoy"
export SSH_PRIVATE_KEY_FILE="/home/nutanix/.ssh/id_rsa"
export SSH_PRIVATE_KEY_SECRET_NAME=${CLUSTER_NAME}-ssh-key