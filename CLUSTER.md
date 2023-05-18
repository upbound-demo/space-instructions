# Prepare the Main Cluster

* [AWS EKS](#aws-eks)
* [kind](#kind-cluster)

## AWS EKS

1. Provision a 3-node cluster using `eksctl`.
   ```bash
   export CLUSTER_NAME=muvaf-plays-1
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
     --values ingress-nginx-aws.yaml
   ```

1. Prepare namespaces.
   ```bash
   kubectl create ns crossplane-system
   kubectl create ns upbound-system
   ```


1. Configure the self-signed certificate issuer.
   ```bash
   # Wait until cert-manager is ready.
   kubectl wait deployment -n cert-manager cert-manager-webhook --for condition=Available=True --timeout=360s
   ```
   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: cert-manager.io/v1
   kind: ClusterIssuer
   metadata:
     name: selfsigned
   spec:
     selfSigned: {}
   EOF
   ```
1. Install Crossplane.
   ```bash
   helm upgrade --install crossplane universal-crossplane \
     --repo https://charts.upbound.io/stable \
     --namespace crossplane-system \
     --version v1.12.1-up.1 \
     --wait
   ```

1. Install Provider AWS. It will be needed to configure IRSA for AWS
   providers in each control plane.
   ```bash
   export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
   export OIDC_PROVIDER=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${REGION} --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")
   ```

   Create a policy with permissions to create policies and roles.
   ```bash
   cat > /tmp/iam-policy.json <<EOF
   {
       "Version": "2012-10-17",
       "Statement": [
           {
               "Effect": "Allow",
               "Action": [
                   "iam:*"
               ],
               "Resource": "*"
           }
       ]
   }
   EOF
   ```
   ```bash
   aws iam create-policy --policy-name provider-aws-iam-full --policy-document file:///tmp/iam-policy.json
   ```
   Create the IAM Role to be used by the service account of provider-aws-iam.
   ```bash
   cat > /tmp/trust-relationship.json <<EOF
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
         },
         "Action": "sts:AssumeRoleWithWebIdentity",
         "Condition": {
           "StringLike": {
             "${OIDC_PROVIDER}:aud": "sts.amazonaws.com",
             "${OIDC_PROVIDER}:sub": "system:serviceaccount:crossplane-system:provider-aws-iam-*"
           }
         }
       }
     ]
   }
   EOF
   ```
   ```bash
   aws iam create-role --role-name main-cluster-provider-aws-iam --assume-role-policy-document file:///tmp/trust-relationship.json --description "The role for the provider-aws-iam running in the main cluster."
   ```
   ```bash
   aws iam attach-role-policy --role-name main-cluster-provider-aws-iam --policy-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:policy/provider-aws-iam-full
   ```

   Install the provider-aws-iam and configure it to assume the role we just created.
   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: pkg.crossplane.io/v1
   kind: Provider
   metadata:
     name: provider-aws-iam
   spec:
     package: xpkg.upbound.io/upbound-release-candidates/provider-aws-iam:v0.35.0
     controllerConfigRef:
       name: irsa
   ---
   apiVersion: pkg.crossplane.io/v1alpha1
   kind: ControllerConfig
   metadata:
     name: irsa
     annotations:
       eks.amazonaws.com/role-arn: arn:aws:iam::${AWS_ACCOUNT_ID}:role/main-cluster-provider-aws-iam
   spec: {}
   EOF
   ```
   ```bash
   kubectl wait provider.pkg.crossplane.io/provider-aws-iam \
     --for=condition=Healthy \
     --timeout=360s
   ```
   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: aws.upbound.io/v1beta1
   kind: ProviderConfig
   metadata:
     name: default
   spec:
     credentials:
       source: IRSA
   EOF
   ```

## kind Cluster

1. Provision a `kind` cluster.
   ```bash
   cat <<EOF | kind create cluster --wait 5m --config=-
   kind: Cluster
   apiVersion: kind.x-k8s.io/v1alpha4
   nodes:
   - role: control-plane
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
   > You can use `load.sh` to pre-load most of the images.

1. Prepare namespaces.
   ```bash
   kubectl create ns crossplane-system
   kubectl create ns upbound-system
   ```

1. Install ingress-nginx controller.
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.7.1/deploy/static/provider/kind/deploy.yaml
   ```
   ```bash
   # Make sure ingress-nginx gets ready.
   kubectl wait --namespace ingress-nginx \
     --for=condition=ready pod \
     --selector=app.kubernetes.io/component=controller \
     --timeout=360s
   ```

1. Install cert-manager.
   ```bash
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.0/cert-manager.yaml
   ```
1. Configure the self-signed certificate issuer.
   ```bash
   # Wait until cert-manager is ready.
   kubectl wait deployment -n cert-manager cert-manager-webhook --for condition=Available=True --timeout=360s
   ```
   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: cert-manager.io/v1
   kind: ClusterIssuer
   metadata:
     name: selfsigned
   spec:
     selfSigned: {}
   EOF
   ```
1. Install Crossplane.
   ```bash
   helm upgrade --install crossplane universal-crossplane \
     --repo https://charts.upbound.io/stable \
     --namespace crossplane-system \
     --version v1.12.1-up.1 \
     --wait
   ```
