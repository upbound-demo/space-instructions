# Control Plane Spaces

**DISCLAIMER**: This is the alpha version of a self-hosted feature available in
[Upbound](https://www.upbound.io/product/upbound). While the
service is generally available, this specific mode is not yet production-ready
and the APIs may change any time.

## Setup

Assumes the cluster components mentioned [here](./CLUSTER.md) are installed.

## Installation

First, you need to create image pull secrets with the Google Service Account
tokens you have received.

1. Create an image pull secret to pull images from GCR. There are two ways to
   authenticate, you need to follow only one of the following instructions:

   - (Service Account Token) Save the token to a file named `gcrtoken.json`.

     ```bash
     # Change the path to where you saved the token.
     export GCP_TOKEN_PATH="THE PATH TO YOUR GCRTOKEN FILE"
     ```

     Run the following command.

     ```bash
     kubectl -n upbound-system create secret docker-registry upbound-pull-secret \
       --docker-server=https://us-west1-docker.pkg.dev \
       --docker-username=_json_key \
       --docker-password="$(cat $GCP_TOKEN_PATH)"
     ```

   - (IAM User) Run the following command.
     ```bash
     kubectl -n upbound-system create secret docker-registry upbound-pull-secret \
       --docker-server=https://us-west1-docker.pkg.dev \
       --docker-username=oauth2accesstoken \
       --docker-password="$(gcloud auth print-access-token --impersonate-service-account pull-environments-upbound-eng@orchestration-build.iam.gserviceaccount.com)"
     ```

1. Log in with Helm to be able to pull chart images from GCR.
   - (Service Account Token) Run the following command.
     ```bash
     cat $GCP_TOKEN_PATH | helm registry login us-west1-docker.pkg.dev -u _json_key --password-stdin
     ```
   - (GCP IAM User) Run the following command.
     ```bash
     gcloud auth print-access-token --impersonate-service-account pull-environments-upbound-eng@orchestration-build.iam.gserviceaccount.com | helm registry login us-west1-docker.pkg.dev -u oauth2accesstoken --password-stdin
     ```

### MXP Provisioning Machinery

1. Install `mxp`. In a local cluster, you don't need to change `ROUTER_HOST` but
   if you are deploying to a remote cluster, it needs to be **a domain you own** so
   that you can add a public DNS record for `kubectl` requests to find the router,
   hence the control plane instance.

   `CLUSTER_TYPE` enables you to deploy cluster specific resources during installation. Currently
   the only supported types are `kind`, `aks`, or `gke`. `eks` will be supported in a future
   release.

   > NOTE: if you are deploying into AKS, this CLUSTER*TYPE \_must* be 'aks'.

   ```bash
   export VERSION_NUM=0.14.0-13.g2f2dceff
   export ROUTER_HOST=proxy.upbound-127.0.0.1.nip.io
   export CLUSTER_TYPE=kind
   export UPBOUND_ACCOUNT=<your upbound account>
   ```

   ```bash
   helm -n upbound-system upgrade --install mxe oci://us-west1-docker.pkg.dev/orchestration-build/upbound-environments/spaces --version "${VERSION_NUM}" --wait \
     --set "ingress.host=${ROUTER_HOST}" \
     --set "clusterType=${CLUSTER_TYPE}" \
     --set "account=${UPBOUND_ACCOUNT}"
   ```

1. (Non-kind Cluster) Create a DNS record for the load balancer of the public
   facing ingress.
   ```bash
   kubectl get ingress -n upbound-system mcp-router-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
   ```
   Add this host name as CNAME or A record for your domain.

## Using Same Cluster as Control Plane Space

The pods of control planes can be deployed to many clusters which are
called control plane spaces.

In this section, we'll use our existing cluster as the one and only
control plane space for brevity.

1. Create `ProviderConfig`s for Helm and Kubernetes providers to deploy host
   cluster services to the existing cluster.
   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: helm.crossplane.io/v1beta1
   kind: ProviderConfig
   metadata:
     name: upbound-cluster
   spec:
    credentials:
       source: InjectedIdentity
   ---
   apiVersion: kubernetes.crossplane.io/v1alpha1
   kind: ProviderConfig
   metadata:
     name: upbound-cluster
   spec:
     credentials:
       source: InjectedIdentity
   EOF
   ```
1. We need to give necessary permissions to both provider-kubernetes and
   provider-helm service accounts to be able to install control plane space
   services to the cluster. If it wasn't the same cluster, we'd have to create
   `ProviderConfig`s that point to a kubeconfig with enough permissions.
   ```bash
   PROVIDERS=(provider-kubernetes provider-helm)
   for PROVIDER in ${PROVIDERS[@]}; do
     cat <<EOF | kubectl apply -f -
   apiVersion: v1
   kind: ServiceAccount
   metadata:
     name: $PROVIDER
     namespace: upbound-system
   ---
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRoleBinding
   metadata:
     name: $PROVIDER
   subjects:
     - kind: ServiceAccount
       name: $PROVIDER
       namespace: upbound-system
   roleRef:
     kind: ClusterRole
     name: cluster-admin
     apiGroup: rbac.authorization.k8s.io
   ---
   apiVersion: pkg.crossplane.io/v1alpha1
   kind: ControllerConfig
   metadata:
     name: $PROVIDER-incluster
   spec:
     serviceAccountName: $PROVIDER
   EOF
     kubectl patch provider.pkg.crossplane.io "crossplane-contrib-${PROVIDER}" --type merge -p "{\"spec\": {\"controllerConfigRef\": {\"name\": \"$PROVIDER-incluster\"}}}"
   done
   ```

1. Create your first control plane.

   ```bash
   cat <<EOF | kubectl apply -f -
   apiVersion: spaces.upbound.io/v1alpha1
   kind: ControlPlane
   metadata:
     name: ctp1
   spec:
     writeConnectionSecretToRef:
       name: kubeconfig-ctp1
       namespace: default
   EOF
   ```

   Wait until it's ready.

   ```bash
   kubectl wait controlplane ctp1 --for condition=Ready=True --timeout=360s
   ```

## Access ControlPlane Instance

```bash
kubectl get secret kubeconfig-ctp1 -n default -o jsonpath='{.data.kubeconfig}' | base64 -d > /tmp/ctp1.yaml
```

```bash
KUBECONFIG=/tmp/ctp1.yaml kubectl get xrd
```

# GitOps

If you are using an AWS cluster, see the instructions
[here](https://github.com/upbound-demo/environment-aws/)
