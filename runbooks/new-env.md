# 新增環境

「新環境」指為某個（或多個）服務新增一份 `values_<env>.yaml` 並讓它在共用 GCLB 上可被存取（例如 `uat`）。

> 大寫佔位符（`<PROJECT_ID>`、`<REGION>`）對應 `.claude/gcp-env.md` 記載的專案層級固定值（`static-map-242406`、`asia-east1`），執行前請代入實際值；小寫 `<env>`/`<service>` 為隨呼叫變動的參數。

新增環境走共用 GCLB 的手動網路設定，詳見 `docs/conventions.md`「網路入口」。

## 本機前置作業

```bash
gcloud auth login
gcloud config set project static-map-242406
gcloud auth application-default login

gcloud container clusters get-credentials caring-tw \
  --region asia-east1 --project static-map-242406

kubectl get nodes
kubectl -n argocd get pods
```

## Phase 1 — 決定 Cloud SQL instance

新環境要接哪個 Cloud SQL instance，是共用既有的 `caring-dev-pg`/`caring-release-pg`，還是需要新建一個？對照 `.claude/gcp-env.md`「Cloud SQL」表格決定。若需新建：

```bash
gcloud sql instances create <instance-name> \
  --database-version=POSTGRES_<version> \
  --region=asia-east1 --project static-map-242406 \
  --network=new-caring-vpc --no-assign-ip \
  ...   # 其餘 machine-type / storage 等參數依既有 instance 規格與操作者確認
```

建立完成後把 `<instance-name>` 記入 `.claude/gcp-env.md`「Cloud SQL」表格。

## Phase 2 — 建立 values 檔並更新 ArgoCD Application 清單

對每個要在新環境上線的服務：

1. 複製該服務既有的 `values_<env>.yaml` 為 `values_<new-env>.yaml`，填入新環境的真實值（`App.Env`、`SqlProxy.InstanceName`、connection string 等）。
2. 在 `Infrastructure/argocd/values.yaml` 的 `apps.applications` 新增對應 entry（`destinationNamespace: <service-namespace>-<new-env>`），見 `docs/conventions.md`「ArgoCD Application 模式」。

## Phase 3 — Workload Identity 綁定

在 `Shell/service_account_binding.sh` 為每個服務的新 namespace 補上一組 `add-iam-policy-binding` + `kubectl annotate`（格式見 `runbooks/new-service.md` 步驟 6），操作者執行：

```bash
./Shell/service_account_binding.sh
```

## Phase 4 — GCLB 對外流量

1. 對每個需要對外的服務，操作者執行 `Shell/create_lb_backend_services.sh`（或手動 `gcloud compute backend-services create` + `add-backend`，見 `runbooks/new-service.md` 步驟 8）建立 `<chart-name>-<new-env>-80` backend-service，並掛入三個 zone 的 NEG。

2. 決定新環境掛在哪個共用 URL Map（`lb`、`lb-dev` 或 `lb-demo`，見 `.claude/gcp-env.md`「網路入口」），操作者手動執行：

   ```bash
   gcloud compute url-maps add-path-matcher <lb|lb-dev|lb-demo> \
     --region asia-east1 --project static-map-242406 \
     --path-matcher-name=<new-env>-urlmatcher \
     --new-hosts=<new-domain> \
     --default-service=<fallback-backend-service> \
     --path-rules="/api/*=<api-backend-service>,/v2/*=<web-page-backend-service>"
   ```

   實際 path rule 需依該環境要暴露哪些服務調整，可參照既有環境（例如 `qat-urlmatcher`）的規則結構。

3. **確認新網域已被現有 TLS 憑證涵蓋**：本專案的 TLS 憑證是手動上傳的 `SELF_MANAGED` 憑證（`caringcm2026`、`caringcm2026-all`、`cloudflare` 等），不會自動核發新網域的憑證。操作者需確認：

   ```bash
   gcloud compute ssl-certificates describe caringcm2026-all \
     --project static-map-242406 --format="value(selfManaged.certificate)" | openssl x509 -noout -text | grep -A2 "Subject Alternative Name"
   ```

   若新網域不在既有憑證的 SAN 清單內，需操作者重新申請/上傳涵蓋新網域的憑證並更新對應 `target-https-proxy`，此步驟**不在本 repo 或任何自動化腳本範圍內**。

4. 設定 DNS，將新網域指向對應 URL Map 的現有 External IP（不會產生新 IP，見 `.claude/gcp-env.md`「網路入口」表格）。

## Phase 5 — 收尾更新

更新 `.claude/gcp-env.md`：

- 「環境清單」表格新增這個環境，狀態標記「使用中」
- 「各服務環境對照」表格加上這個環境
- 若新建了 Cloud SQL instance，更新「Cloud SQL」表格
- 若新網域掛在既有 URL Map，更新「主要對外網域範例」表格

開啟新 session，AI 才會讀到最新的 gcp-env.md。

---

## 中斷後恢復

若操作過程中斷，AI 執行以下診斷指令確認完成到哪個 Phase，再從對應步驟繼續。

```bash
ENV=<env>
SERVICE=<chart-name>
NAMESPACE=<service-namespace>-${ENV}

echo "--- Phase 2：values 檔與 ArgoCD Application ---"
find Microservices -iname "values_${ENV}.yaml" 2>&1
grep -n "${NAMESPACE}:" Infrastructure/argocd/values.yaml 2>&1
kubectl -n argocd get application ${NAMESPACE} --no-headers 2>&1

echo "--- Phase 3：Workload Identity ---"
kubectl -n ${NAMESPACE} get serviceaccount ${SERVICE} \
  -o jsonpath='{.metadata.annotations}' 2>/dev/null && echo "" || echo "(namespace 或 KSA 尚未建立)"

echo "--- Phase 4：GCLB backend-service ---"
gcloud compute backend-services describe ${SERVICE}-${ENV}-80 \
  --region asia-east1 --project static-map-242406 \
  --format="yaml(backends)" 2>/dev/null || echo "(尚未建立)"
```

| 診斷結果                                    | 代表已完成到 | 下一步               |
| -------------------------------------------- | ------------ | --------------------- |
| values 檔不存在                              | 尚未開始     | Phase 2               |
| values 檔存在，ArgoCD Application 不存在     | Phase 2 部分 | 補上 `apps.applications` entry 並 push |
| ArgoCD Application 存在，KSA annotation 為空 | Phase 2      | Phase 3               |
| KSA annotation 已設，backend-service 不存在  | Phase 3      | Phase 4               |
| backend-service 存在，`.claude/gcp-env.md` 未更新 | Phase 4  | Phase 5               |

### 注意事項

- **`service_account_binding.sh` 可重複執行**：`kubectl annotate --overwrite` 與 `add-iam-policy-binding` 都是 idempotent，重跑不會破壞既有服務的綁定。
- **DNS 與憑證 SAN 檢查無法由 AI 自動驗證後續生效**：DNS 傳播可用 `dig <新網域>` 檢查；憑證 SAN 是否已更新需操作者確認 GCP Console 或重新執行 Phase 4 步驟 3 的指令。
