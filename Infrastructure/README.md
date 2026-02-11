# Jubo New Caring Manifest Infrastructure

# Installation

```shell
gcloud config set project "static-map-242406" && \

gcloud auth application-default set-quota-project "static-map-242406"
```

# Create Cluster With Use NAT IP

[Reference](https://cloud.google.com/nat/docs/gke-example)

[Reference](https://cloud.google.com/sdk/gcloud/reference/container/clusters/create)

```shell
gcloud container --project "static-map-242406" clusters create "caring-tw" --location "asia-east1" --no-enable-basic-auth --cluster-version "1.31.12-gke.1014000" --release-channel "stable" --machine-type "custom-4-8192" --image-type "COS_CONTAINERD" --disk-type "pd-balanced" --disk-size "30" --metadata disable-legacy-endpoints=true --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" --num-nodes "1" --logging=SYSTEM,WORKLOAD --monitoring=SYSTEM --enable-ip-alias --network "projects/static-map-242406/global/networks/default" --subnetwork "projects/static-map-242406/regions/asia-east1/subnetworks/default" --no-enable-intra-node-visibility --default-max-pods-per-node "110" --security-posture=standard --workload-vulnerability-scanning=disabled --addons HorizontalPodAutoscaling,HttpLoadBalancing,NodeLocalDNS,GcePersistentDiskCsiDriver --enable-autoupgrade --enable-autorepair --max-surge-upgrade 1 --max-unavailable-upgrade 0 --binauthz-evaluation-mode=DISABLED --no-enable-managed-prometheus --workload-pool "static-map-242406.svc.id.goog" --enable-shielded-nodes --enable-private-nodes --no-enable-master-authorized-networks --enable-cost-allocation --private-endpoint-subnetwork "projects/static-map-242406/regions/asia-east1/subnetworks/default" --cluster-ipv4-cidr "10.64.0.0/14" --services-ipv4-cidr "10.72.0.0/20" --enable-autoscaling --autoscaling-profile=balanced --min-nodes=0 --max-nodes=10 --async
```

# Delete Cluster

[Reference](https://cloud.google.com/sdk/gcloud/reference/container/clusters/delete)

```shell
gcloud container clusters delete "caring-tw" --location "asia-east1" --async
```

## Prerequisites

- kubectl
- set up kubectl credential for target cluster
- helm

```shell
gcloud container clusters get-credentials caring-tw --region=asia-east1
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
helm upgrade --force --install -f ./Infrastructure/istio/values.yaml istio ./Infrastructure/istio -n istio-system --create-namespace --set defaultRevision=default
```

### Upgrade Istio
```shell
helm upgrade --force -f ./Infrastructure/istio/values.yaml istio ./Infrastructure/istio -n istio-system --create-namespace --set defaultRevision=default
```

### Uninstall Istio
```shell
helm uninstall istio -n istio-system
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

### ArgoCD 版本

#### 1. 取得最新版本
```shell
helm search repo argo/argo-cd --versions # 查詢 argo-cd 最新的 app version 及 chart version
helm search repo argo/argocd-apps --versions # 查詢 argocd-apps 最新的 chart version
```

#### 2. 修改版本號
修改 Infrastructure/argocd/Chart.yaml
```yaml
appVersion: "3.3.0"    # 對應 ArgoCD 本身版本
dependencies:
  - name: argo-cd
    repository: https://argoproj.github.io/argo-helm
    version: ">=6.2.0"
  - name: argocd-apps
    repository: https://argoproj.github.io/argo-helm
    version: ">=1.6.2"
```

### Build Dependency

```shell
helm dependency update ./Infrastructure/argocd

helm dependency build ./Infrastructure/argocd
```

### Install / Upgrade ArgoCD With Environment

```shell
helm upgrade --force --install -f ./Infrastructure/argocd/values.yaml argocd ./Infrastructure/argocd --create-namespace -n argocd
```

### Upgrade ArgoCD
```shell
helm upgrade --force -f ./Infrastructure/argocd/values.yaml argocd ./Infrastructure/argocd --create-namespace -n argocd
```

### Uninstall ArgoCD
```shell
helm uninstall argocd -n argocd
```

### Check Release

```shell
helm list -n argocd
```

### ArgoCD 更新後同步失敗解救辦法
1. kubectl edit configmap argocd-cm // 修改密碼 (如果不知道密碼，請到其他 cluster 查詢，缺少這步驟以下登入會失敗)
2. argocd login new-caring-argocd.jubo.health --sso --sso-launch-browser --grpc-web
3. argocd app get argocd/argocd // 取得 argocd 狀況
4. argocd app terminate-op argocd/argocd // 停止同步
5. kubectl delete job argocd-redis-secret-init -n argocd // 刪除卡住的 job
6. argocd app sync argocd/argocd --strategy apply // 重新同步

同步狀態, 發現卡在 PreSync
```text
batch                      Job                 argocd     argocd-redis-secret-init                    Running             PreSync  job.batch/argocd-redis-secret-init created
```

### ArgoCD 使用 Azure 登入說明

ArgoCD 的 Azure 密碼使用 Jenkins (https://jenkins.smart-aging.tech/view/OPS/job/azure-credentials-rotator/) 維護, 一個月輪替一次

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
