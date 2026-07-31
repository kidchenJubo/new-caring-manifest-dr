# 新增服務

> 大寫佔位符（`<PROJECT_ID>`、`<REGION>`）對應 `.claude/gcp-env.md` 記載的專案層級固定值（`static-map-242406`、`asia-east1`），執行前請代入實際值；小寫 `<service-dir>`/`<env>` 為隨呼叫變動的參數。

## 服務類型選擇

依對外流量與是否連資料庫，選一個既有同類服務目錄複製。分類與範本差異見 `docs/conventions.md`「服務類型與範本」。

| 類型                  | 參考目錄                                                            | 特徵                                            |
| --------------------- | ---------------------------------------------------------------------- | ------------------------------------------------- |
| API（對外 + 連 DB）  | `Microservices/Caring/Backend/Api/new-caring-mobile-api`              | 含 Service、HPA（值閘控）、PDB（值閘控）        |
| 前端頁面（對外，不連 DB） | `Microservices/Caring/Frontend/Page/new-caring-web-page`          | 只有 deployment/configmap/service，無 ServiceAccount |
| 背景消費者（不對外，連 DB） | `Microservices/Caring/Event/Consumer/new-caring-event-consumer` | 無 Service、無 PDB                                |
| 排程/Worker（不對外，連 DB） | `Microservices/Caring/Scheduler/CareeNotification`              | 無 Service、無 PDB，probe 可能整段註解            |

## 完整檢查清單

1. **複製既有同類服務目錄**

   ```bash
   cp -r Microservices/Caring/<Layer>/<existing-service-dir> Microservices/Caring/<Layer>/<service-dir>
   ```

2. **更新 `Chart.yaml`**

   ```yaml
   name: <chart-name> # K8s 資源命名依據（{{ .Chart.Name }}），可與目錄名不同，需保持一致且不與既有服務衝突
   version: 0.1.0
   appVersion: "0.1.0"
   ```

3. **更新 `templates/deployment.yaml` 的 image**

   ```yaml
   image: "asia-east1-docker.pkg.dev/static-map-242406/new-caring/<image-name>:{{ .Values.App.Version }}"
   ```

   `<image-name>` 對應 image 建置流程（不在本 repo）推送到 Artifact Registry `new-caring` repository 的名稱。

4. **為每個要啟用的環境建立 `values_<env>.yaml`**

   每個環境各自一份完整檔案，複製既有服務的 `values_<env>.yaml` 作為骨架，逐一填入這個新服務真實的：

   - `App.Version`（初始可用一個已知存在於 Artifact Registry 的 tag）
   - `App.Env`（例如 `Development`/`QAT`/... 依服務既有慣例）
   - `App.ConnectionStrings.*`、`App.ServiceAccount`（見下方 Workload Identity）
   - 若連 DB：`SqlProxy.InstanceName`（見 `.claude/gcp-env.md`「Cloud SQL」表格，決定用共用的 `caring-dev-pg` 還是新建 instance）
   - `App.UseHPA` / `App.UsePDB.enabled`：依實際需求決定是否開啟，不要照抄來源服務的值

   執行 Values 一致性檢查確認同一服務各環境檔案的 key 結構一致（見 `CLAUDE.md`）。新服務建議先只建立 `values_dev.yaml`，其他環境等 dev 驗證過再新增。

5. **在 `Infrastructure/argocd/values.yaml` 的 `apps.applications` 新增 entry**

   ```yaml
   <service-namespace>-dev:
     sourcePath: Microservices/Caring/<Layer>/<service-dir>
     sourceHelm:
       valueFiles:
         - values_dev.yaml
     destinationNamespace: <service-namespace>-dev
   ```

   key 名稱與 `destinationNamespace` 慣例上一致，等於 ArgoCD Application 名稱。新服務預設只新增 `dev` 這一個 entry，其他環境待驗證後依「新增環境」流程（見 `runbooks/new-env.md`）逐一補上。不要加 `syncPolicy.automated`（本專案目前所有服務皆手動 sync，見 `docs/conventions.md`「ArgoCD Application 模式」）。

6. **決定並準備這個服務的 GSA**

   每個服務各自有一組「非正式環境」（dev/dev2/qat/qat2/demo 共用）+「release」兩個 GSA，服務之間不共用；`rs` 環境則沿用 release 的 GSA，不算在非正式環境那組（見 `docs/conventions.md`「Workload Identity」）。新服務需要：

   - 命名慣例：`<chart-name>-dev@static-map-242406.iam.gserviceaccount.com`、`<chart-name>-release@static-map-242406.iam.gserviceaccount.com`
   - **GSA 的建立（`gcloud iam service-accounts create`）與 Workload Identity 綁定（`gcloud iam service-accounts add-iam-policy-binding`）都屬於 `gcloud iam` 黑名單，AI 不會執行、也不會產出這兩類指令文字。** 這一步須由操作者自行完成：建立好 GSA 後，對每個要啟用的 namespace 授予 `roles/iam.workloadIdentityUser`，member 為 `serviceAccount:static-map-242406.svc.id.goog[<service-namespace>-dev/<chart-name>]`（release 比照，member 換成對應的 release namespace）。
   - 在 `values_dev.yaml` 的 `App.ServiceAccount` 填入非正式環境 GSA email（AI 可執行，本地檔案編輯）。

7. **更新 `Shell/service_account_binding.sh` 內的 `kubectl annotate` 部分**

   AI 可以幫忙補上 annotate 這一行（`kubectl annotate` 非黑名單），但**綁定用的 `gcloud iam service-accounts add-iam-policy-binding` 那一行需操作者自行加入**（同上，黑名單）：

   ```bash
   kubectl -n <service-namespace>-dev annotate --overwrite serviceaccount \
       <chart-name> \
       iam.gke.io/gcp-service-account=<chart-name>-dev@static-map-242406.iam.gserviceaccount.com
   ```

8. **操作者完成 GSA 建立與 IAM 綁定後，執行整份腳本**

   ```bash
   ./Shell/service_account_binding.sh
   ```

   這份腳本沒有分環境的函數，會重跑整份既有服務的綁定（`kubectl annotate --overwrite` 是 idempotent 的，重跑不會破壞既有服務），只是新增的那幾行才是這次真正需要的效果。

9. **若服務需要對外 HTTP 流量**：提供以下指令文字給操作者執行（不在 ArgoCD 同步範圍內，需手動 GCP 操作）：

   ```bash
   # 1. 建立 backend-service 並掛入 NEG（服務的 K8s Service 需先有 cloud.google.com/neg annotation 且已部署）
   gcloud compute backend-services create <chart-name>-dev-80 \
     --protocol=HTTP --load-balancing-scheme=EXTERNAL_MANAGED \
     --health-checks=k8s-health-check-new-caring --health-checks-region=asia-east1 \
     --region=asia-east1 --project static-map-242406

   for zone in a b c; do
     gcloud compute backend-services add-backend <chart-name>-dev-80 \
       --network-endpoint-group=<service-namespace>-dev-80 \
       --network-endpoint-group-zone=asia-east1-$zone \
       --balancing-mode=RATE --max-rate-per-endpoint=100 \
       --region=asia-east1 --project static-map-242406
   done

   # 2. 在 lb-dev URL Map 新增 host rule + path matcher 指向這個 backend-service（依實際網域規劃調整）
   #    見 .claude/gcp-env.md「網路入口」的既有 host rule 範例
   ```

   服務對外流量若只是 API 掛在既有 web/web-page 網域的 `/api/**` 下（例如新增另一個 mobile-api 分身），可能不需要新的網域，而是調整既有 URL Map path matcher 的 route rule，視實際需求與操作者確認。

10. **Commit 並 push**（操作者執行）

    ArgoCD 目前沒有任何 Application 開啟自動 sync，push 後需操作者手動在 ArgoCD UI/CLI 觸發同步（見 `runbooks/deployment.md`）。

## Cloud SQL 連線字串格式

```
Server=127.0.0.1;Port=5432;Database=<db>;Userid=<chart-name>-dev@static-map-242406.iam;Pooling=true;MinPoolSize=1;MaxPoolSize=100;ConnectionLifeTime=60;
```

使用者名稱為該服務對應的 GSA IAM 帳號（`<chart-name>-dev@static-map-242406.iam` 或 `<chart-name>-release@static-map-242406.iam`，不需密碼欄位）。
