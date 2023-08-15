# Control Plane Spaces

**DISCLAIMER**: This is the alpha version of a self-hosted feature available in
[Upbound](https://www.upbound.io/product/upbound). While the
service is generally available, this specific mode is not yet production-ready
and the APIs may change any time.

## Setup

Assumes the cluster components mentioned [here](./CLUSTER.md) are installed.

## Installation

Installation is broken down into the following sections:

* [Authentication](#authentication)
* [Using Up CLI](#using-up-cli)
* [Using Helm](#using-helm)

### Prerequistes

#### Acquire your Upbound Account
The Upbound representative you've been working with should provide an 
`Upbound Account` string when providing the key.json that you'll use in the 
next step.

Once you have the Upbound Account string set the following environment 
variable to be used in future steps
```
export UPBOUND_ACCOUNT=<your upbound account>
```

#### Authentication
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

1. Log in with Helm to be able to pull chart images from GCR.
   - (Service Account Token) Run the following command.
     ```bash
     cat $GCP_TOKEN_PATH | helm registry login us-west1-docker.pkg.dev -u _json_key --password-stdin
     ```

#### Set the target version
```
export VERSION_NUM=0.14.0-13.g2f2dceff
```

### Using Up CLI

The `up` CLI today will give you the most batteries included experience we can
offer. It will detect with certain prerequisites are not met and prompt you to
install them in order to move forward.

```bash
up space init --token-file=key.json "v${VERSION_NUM}" --set account=${UPBOUND_ACCOUNT}
```

You sould now be able to jump to [Create your first control plane](#create-your-first-control-plane).

### Using Helm

#### Provision Ingress to the Cluster.

1. (Non-kind Cluster) Create an Ingress:
   By default, an ingress is not created; any Kubernetes ingress provider should work just fine.
   However, spaces expects that a Service pointing to the ingress controller/pod be:
   - in the `ingress-nginx` namespace
   - be named `ingress-nginx-controller`
   Note: we expect that this requirement will be changed in the future.

   If you need an Ingress provider, Upbound recommends Nginx as a starting point. To install:
   ```bash
    helm repo add ngnix https://kubernetes.github.io/ingress-nginx
    helm repo update
    helm install -n ingress --create-namespace \
        nginx-ingress nginx/ingress-nginx
    ```

   Then, to create the Service, run:
   ```
   kubectl apply -f-<<EOM
    apiVersion: v1
    kind: Service
    metadata:
      name: ingress-nginx-controller
      namespace: ingress-nginx
    spec:
      allocateLoadBalancerNodePorts: true
      externalTrafficPolicy: Cluster
      internalTrafficPolicy: Cluster
      ipFamilies:
      - IPv4
      ipFamilyPolicy: SingleStack
      ports:
      - name: http
        port: 80
        protocol: TCP
        targetPort: http
      - name: https
        port: 443
        protocol: TCP
        targetPort: https
      selector:
        app.kubernetes.io/component: controller
        app.kubernetes.io/instance: nginx-ingress
        app.kubernetes.io/name: ingress-nginx
      sessionAffinity: None
      type: LoadBalancer
    EOM
    ```

1. (Non-kind Cluster) Create a DNS record for the load balancer of the public
   facing ingress. To get the IP address for the Ingress, run:
   ```bash
   kubectl get ingress \
        -n upbound-system mxe-router-ingress \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}
   ```
   If the above command doesn't return an IP address then your IP Address provider may not have
   allocated an address yet. Otherwise, set the IP address as an A record for the DNS hostname
   selected the `Install MXP` step.

#### Installing provider-k8s and provider-helm
1. Create ControllerConfigs for provider-helm and provider-kubernetes
   ```yaml
   apiVersion: pkg.crossplane.io/v1alpha1
   kind: ControllerConfig
   metadata:
   name: provider-helm-hub
   spec:
     serviceAccountName: provider-helm-hub
   ---
   apiVersion: pkg.crossplane.io/v1alpha1
   kind: ControllerConfig
   metadata:
     name: provider-kubernetes-hub
   spec:
     serviceAccountName: provider-kubernetes-hub
   ```
1. Deploy provider-kubernetes
   ```yaml
   apiVersion: pkg.crossplane.io/v1
   kind: Provider
   metadata:
     name: crossplane-contrib-provider-kubernetes
   spec:
     package: "xpkg.upbound.io/crossplane-contrib/provider-kubernetes:v0.7.0"
     controllerConfigRef:
       name: provider-kubernetes-hub
   ```
1. Deploy provider-helm
   ```yaml
   apiVersion: pkg.crossplane.io/v1
   kind: Provider
   metadata:
     name: crossplane-contrib-provider-helm
   spec:
     package: "xpkg.upbound.io/crossplane-contrib/provider-helm:v0.14.0"
     controllerConfigRef:
       name: provider-helm-hub
   ```

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

#### Helm install

1. Install `spaces`. In a local cluster, you don't need to change `ROUTER_HOST` 
   but if you are deploying to a remote cluster, it needs to be **a domain you own** so
   that you can add a public DNS record for `kubectl` requests to find the router,
   hence the control plane instance.

   `CLUSTER_TYPE` enables you to deploy cluster specific resources during 
   installation. Currently the only supported types are `kind`, `aks`, or 
   `gke`. `eks` will be supported in a future release.

   ```bash
   export ROUTER_HOST=proxy.upbound-127.0.0.1.nip.io
   export CLUSTER_TYPE=kind
   ```

   ```bash
   helm -n upbound-system upgrade --install spaces oci://us-west1-docker.pkg.dev/orchestration-build/upbound-environments/spaces --version "${VERSION_NUM}" --wait \
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

## Create your first control plane.

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
