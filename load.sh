#!/bin/bash

IMGS=("registry.k8s.io/ingress-nginx/controller:v1.7.1" \
 "registry.k8s.io/ingress-nginx/kube-webhook-certgen:v20230312-helm-chart-4.5.2-28-g66a760794" \
 "quay.io/jetstack/cert-manager-controller:v1.11.0" \
 "quay.io/jetstack/cert-manager-cainjector:v1.11.0" \
 "registry.k8s.io/etcd:3.5.6-0" \
 "registry.k8s.io/kube-controller-manager:v1.26.1" \
 "registry.k8s.io/kube-apiserver:v1.26.1" \
 "timberio/vector:0.28.1-distroless-libc" \
 "docker.io/loftsh/vcluster:0.14.1" \
 "docker.io/muvaf/kube-state-metrics:v2.8.1-upbound003" \
 "envoyproxy/envoy:v1.26-latest" \
 "upbound/crossplane:v1.12.1-up.1" \
 "velero/velero-plugin-for-gcp:v1.5.1" \
 "velero/velero:v1.10.0" \
)

for IMG in "${IMGS[@]}"; do
    docker pull $IMG
    kind load docker-image $IMG
done