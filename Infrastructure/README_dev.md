
# Installation

# Create Cluster With Use Public IP

[Reference](https://cloud.google.com/sdk/gcloud/reference/container/clusters/create)

```shell
gcloud container --project "static-map-242406" clusters create "caring-dev" --location "asia-east1" --no-enable-basic-auth --cluster-version "1.31.8-gke.1113000" --release-channel "stable" --machine-type "e2-medium" --image-type "COS_CONTAINERD" --disk-type "pd-balanced" --disk-size "30" --metadata disable-legacy-endpoints=true --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" --num-nodes "1" --logging=SYSTEM,WORKLOAD --monitoring=SYSTEM --enable-ip-alias --network "projects/static-map-242406/global/networks/newcaring-vpc" --subnetwork "projects/static-map-242406/regions/asia-east1/subnetworks/dev-newcaring-gke-subnet" --no-enable-intra-node-visibility --default-max-pods-per-node "110" --security-posture=standard --workload-vulnerability-scanning=disabled --no-enable-master-authorized-networks --addons HorizontalPodAutoscaling,HttpLoadBalancing,NodeLocalDNS,GcePersistentDiskCsiDriver --enable-autoupgrade --enable-autorepair --max-surge-upgrade 1 --max-unavailable-upgrade 0 --binauthz-evaluation-mode=DISABLED --no-enable-managed-prometheus --workload-pool "static-map-242406.svc.id.goog" --enable-shielded-nodes --enable-cost-allocation --private-endpoint-subnetwork "projects/static-map-242406/regions/asia-east1/subnetworks/dev-newcaring-gke-subnet" --cluster-ipv4-cidr "10.88.0.0/14" --services-ipv4-cidr "10.129.96.0/20" --spot --async
```

# Create Cluster With Use NAT IP

[Reference](https://cloud.google.com/nat/docs/gke-example)

[Reference](https://cloud.google.com/sdk/gcloud/reference/container/clusters/create)

```shell
gcloud container --project "static-map-242406" clusters create "caring-dev" --location "asia-east1" --no-enable-basic-auth --cluster-version "1.31.8-gke.1113000" --release-channel "stable" --machine-type "e2-medium" --image-type "COS_CONTAINERD" --disk-type "pd-balanced" --disk-size "30" --metadata disable-legacy-endpoints=true --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" --num-nodes "1" --logging=SYSTEM,WORKLOAD --monitoring=SYSTEM --enable-ip-alias --network "projects/static-map-242406/global/networks/newcaring-vpc" --subnetwork "projects/static-map-242406/regions/asia-east1/subnetworks/dev-newcaring-gke-subnet" --no-enable-intra-node-visibility --default-max-pods-per-node "110" --security-posture=standard --workload-vulnerability-scanning=disabled --addons HorizontalPodAutoscaling,HttpLoadBalancing,NodeLocalDNS,GcePersistentDiskCsiDriver --enable-autoupgrade --enable-autorepair --max-surge-upgrade 1 --max-unavailable-upgrade 0 --binauthz-evaluation-mode=DISABLED --no-enable-managed-prometheus --workload-pool "static-map-242406.svc.id.goog" --enable-shielded-nodes --enable-private-nodes --no-enable-master-authorized-networks --enable-cost-allocation --private-endpoint-subnetwork "projects/static-map-242406/regions/asia-east1/subnetworks/dev-newcaring-gke-subnet" --cluster-ipv4-cidr "10.88.0.0/14" --services-ipv4-cidr "10.129.96.0/20" --spot --async
```

# Delete Cluster

[Reference](https://cloud.google.com/sdk/gcloud/reference/container/clusters/delete)

```shell
gcloud container clusters delete "caring-dev" --location "asia-east1" --async
```

## Prerequisites

- kubectl
- set up kubectl credential for target cluster
- helm

```shell
gcloud container clusters get-credentials caring-dev --region=asia-east1
```

## Istio

[Reference](https://istio.io/latest/docs/setup/install/helm)

### TD;DR (太長了，不解釋)

istio components
    - istio-base
    - istiod
    - istio-ingress

### Check Using Context

```shell
kubectl config get-contexts | grep "*"
```

### Build Dependency
```shell
helm repo add istio https://istio-release.storage.googleapis.com/charts

helm repo update

helm dependency update ./Infrastructure/istio

helm dependency build ./Infrastructure/istio
```

### Install / Upgrade Istio
```shell
helm upgrade --force --install -f ./Infrastructure/istio/values_dev.yaml istio ./Infrastructure/istio -n istio-system --create-namespace --set defaultRevision=default
```

### Upgrade Istio
```shell
helm upgrade --force -f ./Infrastructure/istio/values_dev.yaml istio ./Infrastructure/istio -n istio-system --create-namespace --set defaultRevision=default
```

### Check Release
```shell
helm list -n istio-system
```

### Get External IP
```shell
kubectl get svc -A
```

## ArgoCD

### Init CRD

```shell
kubectl apply -k https://github.com/argoproj/argo-cd/manifests/crds\?ref\=stable
```

### Build Dependency

```shell
helm dependency update ./Infrastructure/argocd

helm dependency build ./Infrastructure/argocd
```

### Install / Upgrade ArgoCD With Environment

```shell
helm upgrade --force --install -f ./Infrastructure/argocd/values_dev.yaml argocd ./Infrastructure/argocd --create-namespace -n argocd
```

### Upgrade ArgoCD
```shell
helm upgrade --force -f ./Infrastructure/argocd/values_dev.yaml argocd ./Infrastructure/argocd --create-namespace -n argocd
```

### Check Release

```shell
helm list -n argocd
```

### Istio Sidecar Injection
#### need kubernetes 1.28 and above
#### Inject Sidecar To Namespace
```shell
kubectl label namespace argocd istio-injection=enabled
```
#### Undo Inject Sidecar From Namespace
```shell
kubectl label namespace argocd istio-injection-
```