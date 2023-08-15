# Prepare the Main Cluster

* [AWS EKS](#aws-eks)
* [Azure AKS](#azure-aks)
* [Google Cloud GKE](#google-cloud-gke)
* [kind](#kind-cluster)

## AWS EKS

1. Provision a 3-node cluster using `eksctl`.
   ```bash
   export CLUSTER_NAME=johndoe-plays-1
   export REGION=us-east-1
   ```
   ```bash
   cat <<EOF | eksctl create cluster -f -
   apiVersion: eksctl.io/v1alpha5
   kind: ClusterConfig
   metadata:
     name: ${CLUSTER_NAME}
     region: ${REGION}
     version: "1.26"
   managedNodeGroups:
     - name: ng-1
       instanceType: m5.4xlarge
       desiredCapacity: 3
       volumeSize: 100
       iam:
         withAddonPolicies:
           ebs: true
   iam:
     withOIDC: true
     serviceAccounts:
       - metadata:
           name: aws-load-balancer-controller
           namespace: kube-system
         wellKnownPolicies:
           awsLoadBalancerController: true
       - metadata:
           name: efs-csi-controller-sa
           namespace: kube-system
         wellKnownPolicies:
           efsCSIController: true
   addons:
     - name: vpc-cni
       attachPolicyARNs:
         - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
     - name: aws-ebs-csi-driver
       wellKnownPolicies:
         ebsCSIController: true
   EOF
   ```

1. Install cert-manager.
   ```bash
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.0/cert-manager.yaml
   ```

1. Install ALB Load Balancer.
   ```bash
   helm install aws-load-balancer-controller aws-load-balancer-controller --namespace kube-system \
     --repo https://aws.github.io/eks-charts \
     --set clusterName=${CLUSTER_NAME} \
     --set serviceAccount.create=false \
     --set serviceAccount.name=aws-load-balancer-controller \
     --wait
   ```

1. Install ingress-nginx.
   ```bash
   helm upgrade --install ingress-nginx ingress-nginx \
     --create-namespace --namespace ingress-nginx \
     --repo https://kubernetes.github.io/ingress-nginx \
     --set 'controller.service.type=LoadBalancer' \
     --set 'controller.service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-type=external' \
     --set 'controller.service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-scheme=internet-facing' \
     --set 'controller.service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-nlb-target-type=ip' \
     --set 'controller.service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-healthcheck-protocol=http' \
     --set 'controller.service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-healthcheck-path=/healthz' \
     --set 'controller.service.annotations.service\.beta\.kubernetes\.io/aws-load-balancer-healthcheck-port=10254'
   ```

1. Configure the self-signed certificate issuer.
   ```bash
   kubectl wait deployment -n cert-manager cert-manager-webhook --for condition=Available=True --timeout=360s
   ```
1. Install Crossplane.
   ```bash
   helm upgrade --install crossplane universal-crossplane \
     --repo https://charts.upbound.io/stable \
     --namespace upbound-system --create-namespace \
     --version v1.12.2-up.2 \
     --wait
   ```

 The cluster is ready! Go to [README.md](./README.md) to continue with installation of Upbound Spaces.

## Azure AKS
1. export common variables
  ```bash
  export RESOURCE_GROUP_NAME=johndoe-plays-1
  export CLUSTER_NAME=johndoe-plays-1
  export LOCATION=westus
  ```

1. Provision a new resourceGroup
  ```bash
  az group create --name ${RESOURCE_GROUP_NAME} --location ${LOCATION}
  ```

1. Provision a new `AKS` cluster.
  ```bash
  az aks create -g ${RESOURCE_GROUP_NAME} -n ${CLUSTER_NAME} \
    --enable-managed-identity \
    --node-count 3 \
    --node-vm-size Standard_D4s_v4 \
    --enable-addons monitoring \
    --enable-msi-auth-for-monitoring \
    --generate-ssh-keys \
    --network-plugin kubenet \
    --network-policy calico
  ```

1. Acquire updated kubeconfig
  ```bash
  az aks get-credentials --resource-group ${RESOURCE_GROUP_NAME} --name ${CLUSTER_NAME}
  ```

1. Install cert-manager.
   ```bash
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.0/cert-manager.yaml
   ```
1. Configure the self-signed certificate issuer.
   ```bash
   kubectl wait deployment -n cert-manager cert-manager-webhook --for condition=Available=True --timeout=360s
   ```
1. Install Crossplane.
   ```bash
   helm upgrade --install crossplane universal-crossplane \
     --repo https://charts.upbound.io/stable \
     --namespace upbound-system --create-namespace \
     --version v1.12.2-up.2 \
     --wait
   ```

The cluster is ready! Go to [README.md](./README.md) to continue with installation of Upbound Spaces.

## Google Cloud GKE
1. export common variables
  ```bash
  export CLUSTER_NAME=johndoe-plays-1
  export LOCATION=us-west1-a
  ```

1. Provision a new `GKE` cluster.
  ```bash
  gcloud container clusters create ${CLUSTER_NAME} \
    --enable-network-policy \
    --num-nodes=3 \
    --zone=${LOCATION} \
    --machine-type=e2-standard-16
  ```

1. Acquire updated kubeconfig
  ```bash
  gcloud container clusters get-credentials ${CLUSTER_NAME} --zone=${LOCATION}
  ```

1. Install cert-manager.
   ```bash
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.0/cert-manager.yaml
   ```
1. Configure the self-signed certificate issuer.
   ```bash
   kubectl wait deployment -n cert-manager cert-manager-webhook --for condition=Available=True --timeout=360s
   ```
1. Install Crossplane.
   ```bash
   helm upgrade --install crossplane universal-crossplane \
     --repo https://charts.upbound.io/stable \
     --namespace upbound-system --create-namespace \
     --version v1.12.2-up.2 \
     --wait
   ```

The cluster is ready! Go to [README.md](./README.md) to continue with installation of Upbound Spaces.

## kind Cluster

1. Provision a `kind` cluster.
   ```bash
   cat <<EOF | kind create cluster --wait 5m --config=-
   kind: Cluster
   apiVersion: kind.x-k8s.io/v1alpha4
   nodes:
   - role: control-plane
     image: kindest/node:v1.27.3@sha256:3966ac761ae0136263ffdb6cfd4db23ef8a83cba8a463690e98317add2c9ba72
     kubeadmConfigPatches:
     - |
       kind: InitConfiguration
       nodeRegistration:
         kubeletExtraArgs:
           node-labels: "ingress-ready=true"
     extraPortMappings:
     - containerPort: 443
       hostPort: 443
       protocol: TCP
   EOF
   ```

1. Install cert-manager.
   ```bash
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.0/cert-manager.yaml
   ```
   ```
1. Install Crossplane.
   ```bash
   helm upgrade --install crossplane universal-crossplane \
     --repo https://charts.upbound.io/stable \
     --namespace upbound-system --create-namespace \
     --version v1.12.2-up.2 \
     --wait
   ```

 The cluster is ready! Go to [README.md](./README.md) to continue with installation of Upbound Spaces.
