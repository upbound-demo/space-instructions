# Control Plane Spaces

**DISCLAIMER**: This is the alpha version of a self-hosted feature available in
[Upbound](https://www.upbound.io/product/upbound). While the
service is generally available, this specific mode is not yet production-ready
and the APIs may change any time.

# Getting Started

* [Pre-requisites](#pre-requisites)
* Install Spaces
  * [Using Up CLI](#using-up-cli)
  * [Using Helm](#using-helm)
* [Create your first control plane](#create-your-first-control-plane)
* [Access your control plane](#access-your-control-plane)

## Pre-requisites

#### Acquire your Upbound Account
The Upbound representative you've been working with should provide an 
`Upbound Account` string when providing the key.json that you'll use in the 
next step.

Once you have the Upbound Account string set the following environment 
variable to be used in future steps
```bash
export UPBOUND_ACCOUNT=<your upbound account>
```

#### Authentication
First, you need to create image pull secrets with the Google Service Account
tokens you have received.

1. Export the path of the service account token JSON file.
   ```bash
   # Change the path to where you saved the token.
   export GCP_TOKEN_PATH="THE PATH TO YOUR GCRTOKEN FILE"
   ```

#### Set the target version

This is the Spaces version to install.
```bash
export VERSION_NUM=0.16.0
```

#### Set the router host and cluster type

The `ROUTER_HOST` is the domain name that will be used to access the control
plane instances. It will be used by the ingress controller to route requests.
Unless you're using a `kind` cluster, you will need to add DNS entries for this
domain to point to the load balancer deployed by the ingress controller, so make
sure you use a domain that you own.
```bash
# For kind
export ROUTER_HOST=proxy.upbound-127.0.0.1.nip.io

# For eks, aks or gke
# export ROUTER_HOST=proxy.example.com
```

The `CLUSTER_TYPE` is the type of the cluster you're deploying Spaces into. It
can have the following values: `kind`, `eks`, `aks`, or `gke`. Support for more
types will be added in the future.
```bash
export CLUSTER_TYPE=kind # can be "eks", "aks" or "gke"
```

## Install Spaces

### Using Up CLI

The `up` CLI today will give you the most batteries included experience we can
offer. It will detect with certain prerequisites are not met and prompt you to
install them in order to move forward.

Assuming you have your kubectl context set to the cluster you want to install
Spaces into, run the following commands:

1. Create an image pull secret so that the cluster can pull Upbound Spaces images.
   ```bash
   kubectl -n upbound-system create secret docker-registry upbound-pull-secret \
     --docker-server=https://us-west1-docker.pkg.dev \
     --docker-username=_json_key \
     --docker-password="$(cat $GCP_TOKEN_PATH)"
   ```

1. Log in with Helm to be able to pull chart images for the installation commands.
   ```bash
   cat $GCP_TOKEN_PATH | helm registry login us-west1-docker.pkg.dev -u _json_key --password-stdin
   ```
1. Install Spaces.
   ```bash
   up space init --token-file=key.json "v${VERSION_NUM}" \
     --set "ingress.host=${ROUTER_HOST}" \
     --set "clusterType=${CLUSTER_TYPE}" \
     --set "account=${UPBOUND_ACCOUNT}"
   ```

1. (Non-kind Cluster) Create a DNS record for the load balancer of the public
   facing ingress. To get the address for the Ingress, run either of the
   following:
   ```bash
   # For GKE and AKS
   kubectl get ingress \
     -n upbound-system mxe-router-ingress \
     -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
   ```
   ```bash
   # For EKS
   kubectl get ingress \
     -n upbound-system mxe-router-ingress \
     -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
   ```
   If the command above doesn't return a load balancer address then your provider
   may not have allocated it yet. Once it is available, add a DNS record for the
   `ROUTER_HOST` to point to the given load balancer address. If it's an IPv4
   address, add an `A` record, if it's a domain name, add a `CNAME` record.

You should now be able to jump to [Create your first control plane](#create-your-first-control-plane).

### Using Helm

#### Setup

Up CLI installs all the pre-requisites to your cluster before starting the
installation. With Helm method, you need to install them separately which gives
you more control over the installation process.

Follow instructions [here](./CLUSTER.md) to prepare your cluster.

#### Installation

Assuming you have your kubectl context set to the cluster you want to install
Spaces into, run the following commands:

1. Create an image pull secret so that the cluster can pull Upbound Spaces images.
   ```bash
   kubectl -n upbound-system create secret docker-registry upbound-pull-secret \
     --docker-server=https://us-west1-docker.pkg.dev \
     --docker-username=_json_key \
     --docker-password="$(cat $GCP_TOKEN_PATH)"
   ```

1. Log in with Helm to be able to pull chart images for the installation commands.
   ```bash
   cat $GCP_TOKEN_PATH | helm registry login us-west1-docker.pkg.dev -u _json_key --password-stdin
   ```
1. Install Spaces.
   ```bash
   helm -n upbound-system upgrade --install spaces \
     oci://us-west1-docker.pkg.dev/orchestration-build/upbound-environments/spaces \
     --version "${VERSION_NUM}" \
     --set "ingress.host=${ROUTER_HOST}" \
     --set "clusterType=${CLUSTER_TYPE}" \
     --set "account=${UPBOUND_ACCOUNT}" \
     --wait
   ```

1. (Non-kind Cluster) Create a DNS record for the load balancer of the public
   facing ingress. To get the address for the Ingress, run either of the
   following:
   ```bash
   # For GKE and AKS
   kubectl get ingress \
     -n upbound-system mxe-router-ingress \
     -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
   ```
   ```bash
   # For EKS
   kubectl get ingress \
     -n upbound-system mxe-router-ingress \
     -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
   ```
   If the command above doesn't return a load balancer address then your provider
   may not have allocated it yet. Once it is available, add a DNS record for the
   `ROUTER_HOST` to point to the given load balancer address. If it's an IPv4
   address, add an `A` record, if it's a domain name, add a `CNAME` record.
   

## Create Your First Control Plane

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

## Access Your Control Plane

```bash
kubectl get secret kubeconfig-ctp1 -n default -o jsonpath='{.data.kubeconfig}' | base64 -d > /tmp/ctp1.yaml
```

```bash
KUBECONFIG=/tmp/ctp1.yaml kubectl get xrd
```
