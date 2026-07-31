# 故障排除

> 大寫佔位符（`<PROJECT_ID>`、`<REGION>`）對應 `.claude/gcp-env.md` 記載的專案層級固定值（`static-map-242406`、`asia-east1`），執行前請代入實際值。

## 一般診斷指令

```bash
SERVICE=new-caring-mobile-api   # Chart name（{{ .Chart.Name }}），不一定等於服務目錄名，見 docs/conventions.md
NAMESPACE=new-caring-mobile-api-dev   # 即 Infrastructure/argocd/values.yaml 中 apps.applications 的 key

# ArgoCD application 同步與健康狀態
kubectl -n argocd get application ${NAMESPACE} -o wide

# Pod 狀態（含重啟次數）
kubectl -n ${NAMESPACE} get pods

# 最近事件
kubectl -n ${NAMESPACE} get events --sort-by='.lastTimestamp' | tail -20

# 即時 log
kubectl -n ${NAMESPACE} logs -l app=${SERVICE} --tail=100 -f

# Pod 描述（image、env var、resource 限制、probe 狀態）
kubectl -n ${NAMESPACE} describe pod -l app=${SERVICE}

# 確認目前運行的 image
kubectl -n ${NAMESPACE} get deployment ${SERVICE} \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# 一覽所有服務的 ArgoCD 狀態
kubectl -n argocd get applications
```

---

## 故障 SOP

當使用者回報服務異常時，AI 依以下 SOP 依序執行診斷指令，每個步驟回報發現後決定是否繼續下一步。

---

## CrashLoopBackOff

```bash
# 1. 確認 pod 狀態與重啟次數
kubectl -n ${NAMESPACE} get pods -l app=${SERVICE}

# 2. 讀取上一次崩潰的 log（通常含錯誤訊息）
kubectl -n ${NAMESPACE} logs -l app=${SERVICE} --previous --tail=100

# 3. 若 log 為空，查看 describe 的 Last State
kubectl -n ${NAMESPACE} describe pod -l app=${SERVICE}
```

**常見根因與處理：**

- 環境變數設定錯誤 → 確認該服務的 `values_<env>.yaml` 是否有殘留 `# TODO` 暫用值或結構缺漏（執行 Values 一致性檢查，見 `CLAUDE.md`）
- 資料庫連線失敗 → 確認 `SqlProxy.InstanceName` 是否正確（對照 `.claude/gcp-env.md`「Cloud SQL」表格），以及 `cloud-sql-proxy` initContainer 的 `startupProbe`（`/startup` port 9090）是否通過
- Workload Identity 未綁定 → 確認 KSA annotation：`kubectl -n ${NAMESPACE} get serviceaccount ${SERVICE} -o jsonpath='{.metadata.annotations}'`，應指向該服務對應的 GSA（見 `docs/conventions.md`「Workload Identity」，每服務有 dev/release 兩個 GSA，不是共用同一個）
- 映像檔問題 → 確認 image tag，見 ImagePullBackOff SOP

---

## ImagePullBackOff

```bash
# 1. 確認 pod events
kubectl -n ${NAMESPACE} describe pod -l app=${SERVICE} | grep -A 10 Events

# 2. 確認目前設定的 image
kubectl -n ${NAMESPACE} get deployment ${SERVICE} \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

**常見根因與處理：**

- Image tag 不存在 → 確認 Artifact Registry `asia-east1-docker.pkg.dev/static-map-242406/new-caring` 是否已推送該 tag（`gcloud artifacts docker images list asia-east1-docker.pkg.dev/static-map-242406/new-caring --project static-map-242406`）；本 repo 沒有 CI/CD pipeline，image 由外部流程建置，若 tag 不存在需回頭確認建置流程是否完成
- 認證失敗 → 確認 KSA 是否已綁定該服務對應的 GSA（該 GSA 需有 `roles/artifactregistry.reader` 權限）

---

## OOMKilled

```bash
# 1. 確認 pod 是否因 OOM 終止
kubectl -n ${NAMESPACE} describe pod -l app=${SERVICE} | grep -E "OOMKilled|Memory|Limits"

# 2. 確認目前 resource limits
kubectl -n ${NAMESPACE} get deployment ${SERVICE} \
  -o jsonpath='{.spec.template.spec.containers[0].resources}'
```

**處理：** 告知操作者需提高該服務 `values_<env>.yaml` 的 `App.AppResources.limits.memory`（主容器）或 `SqlProxy.SqlProxyResources.limits.memory`（若是 cloud-sql-proxy OOM），提供合理建議值（通常為當前值的 1.5–2 倍）。

---

## 502 / 504（GCLB backend-service 不健康）

本專案的對外流量走共用 GCLB（backend-service + Standalone NEG），見 `docs/conventions.md`「網路入口」。

```bash
# 1. 確認 pod 是否正常運行
kubectl -n ${NAMESPACE} get pods -l app=${SERVICE}

# 2. 確認 Service 的 NEG 是否已建立（annotation 是否正確渲染）
kubectl -n ${NAMESPACE} get service ${SERVICE} -o jsonpath='{.metadata.annotations}'

# 3. 確認對應 backend-service 的健康狀態
gcloud compute backend-services get-health ${NAMESPACE}-80 \
  --region asia-east1 --project static-map-242406

# 4. 確認 GCLB URL Map 的 host rule 是否指向正確的 backend-service
gcloud compute url-maps describe <lb|lb-dev|lb-demo> \
  --region asia-east1 --project static-map-242406 --format="yaml(hostRules,pathMatchers)"
```

**若 backend-service 找不到該 NEG，或 NEG 名稱與 `.claude/gcp-env.md` 記載不符：** 立即停止診斷，發出 ⚠️ gcp-env.md 資料異常警告（見 `CLAUDE.md`），可能是 NEG 因 Service 重建而改名，需操作者重新執行 `Shell/create_lb_backend_services.sh` 對應段落，或手動 `gcloud compute backend-services update`。

**若健康檢查全部 UNHEALTHY：** 確認 pod readiness（`GET /health` port 8080）是否真的回應 200；`k8s-health-check-new-caring` 這個 health check 是 TCP 型（`--use-serving-port`），代表 pod 只要有 process 監聽該 port 就會被判定健康，若 TCP 通但應用層仍 502，問題通常在應用本身而非 LB 層。

---

## TLS 憑證即將到期 / 網域未被憑證涵蓋

本專案的 TLS 憑證是操作者手動上傳、管理的 `SELF_MANAGED` 憑證（例如 `caringcm2026`、`caringcm2026-all`、`cloudflare`），到期或新增網域時需要操作者手動更新，不會自動涵蓋新網域。

```bash
# 1. 列出目前所有憑證與到期時間
gcloud compute ssl-certificates list --project static-map-242406 \
  --format="table(name,expireTime,managed.status)"

# 2. 確認某個網域是否被特定憑證涵蓋（SAN 清單）
gcloud compute ssl-certificates describe <cert-name> \
  --project static-map-242406 --format="value(selfManaged.certificate)" \
  | openssl x509 -noout -text | grep -A2 "Subject Alternative Name"
```

**若即將到期或新網域未被涵蓋：** 這是需要操作者手動處理的憑證管理流程（申請/續期、上傳新憑證、更新 `target-https-proxy` 綁定的憑證），不在本 repo 或任何自動化腳本的範圍內，AI 只能協助診斷與提供指令文字。
