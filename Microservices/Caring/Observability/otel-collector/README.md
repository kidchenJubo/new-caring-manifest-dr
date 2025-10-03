# OpenTelemetry Collector

## 功能特色

- 支援 OTLP gRPC 和 HTTP 協定
- 整合 Google Cloud Monitoring、Trace 和 Logging
- 支援 Google Managed Prometheus
- 自動收集 Kubernetes 資源屬性
- 輕量級資源配置（CPU: 50m-200m, Memory: 100Mi-200Mi）
- **簡化的設定檔案，沒有複雜的模板函數**
- 與團隊其他專案保持一致的命名和設定風格

## 安裝步驟

### 1. 建立 GCP Service Account（如果尚未建立）

```bash
# 建立 Service Account
gcloud iam service-accounts create otel-collector \
    --display-name="OpenTelemetry Collector" \
    --description="Service account for OpenTelemetry Collector"

# 綁定必要的 GCP 權限
gcloud projects add-iam-policy-binding static-map-242406 \
    --member="serviceAccount:otel-collector@static-map-242406.iam.gserviceaccount.com" \
    --role="roles/monitoring.metricWriter"

gcloud projects add-iam-policy-binding static-map-242406 \
    --member="serviceAccount:otel-collector@static-map-242406.iam.gserviceaccount.com" \
    --role="roles/cloudtrace.agent"

gcloud projects add-iam-policy-binding static-map-242406 \
    --member="serviceAccount:otel-collector@static-map-242406.iam.gserviceaccount.com" \
    --role="roles/logging.logWriter"
```

### 2. 安裝到 Kubernetes

```bash
# 建立命名空間
kubectl create namespace opentelemetry

# 安裝 Chart
helm install otel-collector . -n opentelemetry
```

## 配置說明

### 基本配置
- **副本數**: 1 (輕量級使用)
- **資源限制**: CPU 50m-200m, Memory 100Mi-200Mi
- **服務端口**: 4317 (gRPC), 4318 (HTTP)
- **命名空間**: opentelemetry

### 認證設定
- **Kubernetes API**: 透過 ServiceAccount token 自動認證
- **GCP 服務**: 透過 GKE Workload Identity 認證
- **Service Account**: `otel-collector@static-map-242406.iam.gserviceaccount.com`

## 使用方式

您的應用程式可以透過以下端點發送遙測資料：

- **gRPC**: `otel-collector.opentelemetry.svc.cluster.local:4317`
- **HTTP**: `http://otel-collector.opentelemetry.svc.cluster.local:4318`

### 應用程式設定範例

```yaml
# 在您的應用程式 ConfigMap 中
OpenTelemetry__EndPoint: "http://otel-collector.opentelemetry.svc.cluster.local:4318"
OpenTelemetry__Protocol: "http"
```

## 監控和日誌

Collector 會自動將資料發送到：
- **Google Cloud Monitoring** - 指標資料
- **Google Cloud Trace** - 追蹤資料  
- **Google Cloud Logging** - 日誌資料
- **Google Managed Prometheus** - Prometheus 格式指標

## 故障排除

### 檢查部署狀態
```bash
# 檢查 Pod 狀態
kubectl get pods -n opentelemetry

# 檢查 ServiceAccount
kubectl get serviceaccount -n opentelemetry

# 檢查日誌
kubectl logs -n opentelemetry -l app=opentelemetry-collector
```

### 常見問題

1. **ServiceAccount 權限問題**：
   ```bash
   # 檢查 RBAC 權限
   kubectl auth can-i get pods --as=system:serviceaccount:opentelemetry:opentelemetry-collector
   ```

2. **GCP 認證問題**：
   ```bash
   # 檢查 Workload Identity 綁定
   gcloud iam service-accounts get-iam-policy otel-collector@static-map-242406.iam.gserviceaccount.com
   ```

## 檔案結構

```
otel-collector/
├── Chart.yaml                    # Helm Chart 資訊
├── values.yaml                   # 簡化的設定檔案
├── README.md                     # 使用說明
└── templates/
    ├── configMap.yaml           # Collector 配置
    ├── deployment.yaml          # 部署設定
    ├── rbac.yaml               # 權限設定
    ├── service.yaml            # 服務設定
    └── serviceAccount.yaml     # 服務帳戶
```
