# Jubo New Caring Manifest

Jubo「Caring」平台的 GitOps manifest 儲存庫，透過 [ArgoCD](https://argo-cd.readthedocs.io/) 與 [Helm](https://helm.sh/) charts 部署在 GKE 叢集 `caring-tw`（`asia-east1`，project `static-map-242406`）上。

> ⚠️ `static-map-242406` 是多個系統共用的 GCP project，內含大量與本 repo 無關的舊系統資源。操作前請先讀 `.claude/gcp-env.md`。

## 目錄結構

```
.
├── .claude/
│   ├── gcp-env.md              # GCP 專案資訊、共用 GCLB IP、Cloud SQL instance、PSC 對接
│   ├── OPERATOR.local          # 操作者層級設定（gitignored，每位操作者自行建立）
│   └── settings.json           # Claude Code 權限設定（黑名單 deny 清單，需 commit）
├── Infrastructure/
│   └── argocd/                 # ArgoCD 自我管理 Helm chart
│       ├── Chart.yaml          # 依賴官方 argo-cd chart
│       ├── values.yaml         # ArgoCD 設定 + apps.applications（所有服務×環境的 Application 定義）
│       └── templates/
│           └── applications.yaml   # range 迴圈，依 apps.applications 產生每個 Application
├── Microservices/
│   └── Caring/
│       ├── Backend/Api/         # new-caring-web-api、new-caring-mobile-api
│       ├── Frontend/Web/        # new-caring-web（Razor 網頁）
│       ├── Frontend/Page/       # new-caring-web-page（Next 前端頁面）
│       ├── Event/Consumer/      # new-caring-event-consumer（純背景 Pub/Sub 消費者）
│       ├── Scheduler/           # CareeNotification（排程/Worker）
│       └── Proxy/               # maintenance-page-proxy（維護頁反向代理）
├── Shell/
│   ├── service_account_binding.sh       # 所有服務×環境的 Workload Identity 綁定（每服務各自 dev/release 兩個 GSA，見「GKE Workload Identity」）
│   ├── create_lb_backend_services.sh    # 建立 GCLB backend-service + NEG
│   ├── kubectl_rollout_restart_*.sh     # 手動重啟腳本
│   └── remove_istio.sh                  # 移除 Istio 用（歷史遺留）
├── docs/
│   └── conventions.md          # 服務規格、命名慣例、範本規格、Secret 現況
├── runbooks/
│   ├── troubleshooting.md      # 故障排除 SOP（CrashLoop、OOM、502、GCLB 不健康）
│   ├── new-service.md          # 新增服務流程
│   ├── new-env.md              # 新增環境流程
│   └── deployment.md           # 部署前置確認與環境升級
└── CLAUDE.md                   # Claude Code AI 行為規則與執行邊界
```

每個服務目錄下都是一份獨立的 Helm chart（`Chart.yaml` + `templates/` + `values_<env>.yaml`）。**服務目錄名稱不一定等於 Chart name**，詳見 `docs/conventions.md`。

## 服務清單

| 服務目錄                                          | Chart name              | 類型                | 說明                          |
| --------------------------------------------------- | ------------------------- | -------------------- | ----------------------------- |
| `Backend/Api/new-caring-web-api`                   | `new-caring-web-api`     | API                 | 網頁使用的 API                |
| `Backend/Api/new-caring-mobile-api`                | `new-caring-mobile-api`  | API                 | App 使用的 API                |
| `Frontend/Web`                                     | `new-caring-web`         | Web                 | Razor 網頁                    |
| `Frontend/Page/new-caring-web-page`                | `new-caring-web-page`    | 前端頁面（Node/Next）| port 3000，不連 GCP 資源      |
| `Event/Consumer/new-caring-event-consumer`         | `caring-event-consumer`  | 背景消費者           | 訂閱 Pub/Sub，不對外           |
| `Scheduler/CareeNotification`                      | `caree-notification`     | 排程/Worker          | 不對外                        |
| `Proxy/maintenance-page-proxy`                     | `maintenance-page-proxy` | Nginx 反向代理       | 反代維護頁 GCS bucket，單一環境（無 `values_<env>.yaml` 區分） |

範本檔案依類型有無 Service/HPA/PDB 的完整對照見 `docs/conventions.md`「服務類型與範本」。

## 運作方式

1. **ArgoCD 自我管理** — `Infrastructure/argocd/` 是一個 Helm chart，安裝/升級時同時把自己（`apps.applications.argocd`，`syncWave: "-20"`）與所有業務服務都寫進同一份 `values.yaml`。
2. **`applications.yaml` range 迴圈** — `Infrastructure/argocd/templates/applications.yaml` 對 `values.yaml` 的 `apps.applications` map 做迴圈，每個 key 產生一個 ArgoCD `Application`（**不是** ApplicationSet）。
3. **Helm 渲染** — 每個 `Application` 的 `spec.source.path` 指向 `Microservices/Caring/...` 下的服務目錄，`sourceHelm.valueFiles` 指定該環境的 `values_<env>.yaml`。
4. **Namespace** — 由該 entry 的 `destinationNamespace` 決定（例如 `new-caring-mobile-api-dev`）。
5. **Sync** — 目前所有 Application 皆未設定 `syncPolicy.automated`，需操作者在 ArgoCD UI/CLI 手動觸發同步。

完整結構與範例見 `docs/conventions.md`「ArgoCD Application 模式」。

## 環境

| 環境      | 狀態                                              |
| --------- | -------------------------------------------------- |
| `dev`     | 使用中                                             |
| `dev2`    | 使用中（僅 `new-caring-web-api`、`new-caring-event-consumer`） |
| `qat`     | 使用中                                             |
| `qat2`    | 使用中（僅 `new-caring-web-api`、`new-caring-event-consumer`） |
| `demo`    | 使用中                                             |
| `release` | 使用中（相當於 prod，正式對外環境）               |
| `rs`      | 還原演練用，目前未實際部署                        |

完整的 External IP、網域對照、Cloud SQL instance 詳見 `.claude/gcp-env.md`。

## 網路入口（共用 GCLB）

對外流量走**既有共用的 GCLB**（Backend Service + Standalone NEG），透過 host-based routing 分流，不是 Kubernetes 層的網路資源。每個對外 Service 加 `cloud.google.com/neg` annotation 產生 NEG，再由操作者手動用 `Shell/create_lb_backend_services.sh` 建立 backend-service 並掛入既有的 URL Map。TLS 憑證是手動上傳的 `SELF_MANAGED` 憑證，到期需操作者手動更新。詳見 `docs/conventions.md`「網路入口」與 `.claude/gcp-env.md`。

## GKE Workload Identity

每個服務各自有一組「非正式環境」（dev/dev2/qat/qat2/demo 共用）+「release」兩個 GSA，服務之間也不共用——pod 無需金鑰檔案即可向 GCP 驗證：

| 服務                       | 非正式環境 GSA                                                       | release GSA                                                   |
| --------------------------- | ---------------------------------------------------------------------- | ----------------------------------------------------------------- |
| `new-caring-web-api`       | `new-caring-web-api-dev@static-map-242406.iam.gserviceaccount.com`    | `new-caring-web-api-release@static-map-242406.iam.gserviceaccount.com` |
| `new-caring-mobile-api`    | `new-caring-mobile-api-dev@static-map-242406.iam.gserviceaccount.com` | `new-caring-mobile-api-release@static-map-242406.iam.gserviceaccount.com` |
| `new-caring-web`           | `new-caring-web-dev@static-map-242406.iam.gserviceaccount.com`        | `new-caring-web-release@static-map-242406.iam.gserviceaccount.com` |
| `caring-event-consumer`    | `caring-event-consumer-dev@static-map-242406.iam.gserviceaccount.com` | `caring-event-consumer-release@static-map-242406.iam.gserviceaccount.com` |
| `caree-notification`      | `caree-notification-dev@static-map-242406.iam.gserviceaccount.com`    | `caree-notification-release@static-map-242406.iam.gserviceaccount.com` |
| `maintenance-page-proxy`  | `n-c-b-a@static-map-242406.iam.gserviceaccount.com`（尚未拆分）        | 同左                                                              |

`rs`（還原演練）環境不算在「非正式環境」那組，而是沿用 release 的 GSA（`new-caring-web-api`、`new-caring-web`、`caring-event-consumer` 這三個有 `rs` 的服務都適用）——因為 `rs` 的資料庫是從 release 備份還原的，用 release GSA 才能直接沿用還原後資料庫裡既有的 IAM 使用者，見 `docs/conventions.md`「Workload Identity」。

綁定透過以下腳本一次性執行（涵蓋所有既有服務×環境；新增服務/環境需先在腳本中補上對應行）：

```bash
./Shell/service_account_binding.sh
```

> 這 10 個新 GSA 尚未在 GCP 建立，`Shell/service_account_binding.sh` 也尚未更新為新的 GSA 對應——建立 GSA、Workload Identity 綁定與更新這份腳本，需操作者自行完成（`gcloud iam` 相關指令為 Claude Code 黑名單）。

## Cloud SQL Proxy

所有連 DB 的服務使用 Cloud SQL Proxy **native sidecar**（`initContainers` + `restartPolicy: Always`），搭配 `--auto-iam-authn`（Workload Identity，免密碼）。

| Instance            | 用途                               |
| -------------------- | ----------------------------------- |
| `caring-dev-pg`     | dev / dev2 / qat / qat2 / demo 共用 |
| `caring-release-pg` | release 專用                        |
| `rs`                | 還原演練專用                        |

Connection name 完整值見 `.claude/gcp-env.md`「Cloud SQL」。

## ArgoCD

- URL：`https://new-caring-argocd.jubo.health`
- 登入：透過 Dex 的 Microsoft Entra ID（限 `@jubo.health` 帳號）
- RBAC：`policy.default: role:admin`——所有已驗證使用者皆為 admin
- Dex 的 Microsoft client secret 由 Jenkins 的 `azure-credentials-rotator` job 每月自動輪替，於叢集內以 `argocd-dex-ms-secret`（namespace `argocd`）管理，不進 Git

初次安裝／升級 ArgoCD 本身：

```bash
helm dependency update ./Infrastructure/argocd
helm upgrade --install -f ./Infrastructure/argocd/values.yaml argocd ./Infrastructure/argocd \
  --create-namespace -n argocd
```

完成後，ArgoCD 會依 `values.yaml` 的 `apps.applications` 自我建立所有 Application（含自己）。

## AI 輔助（Claude Code）

本 repo 已設定 [Claude Code](https://claude.ai/code) 輔助。AI 以 `CLAUDE.md` 作為操作指南，並依操作者的 GCP IAM 角色套用對應的權限層級。

### 運作方式

- `CLAUDE.md` — AI 行為規則與執行邊界，Claude Code 自動載入。專案慣例見 `docs/`，操作程序見 `runbooks/`。
- `.claude/gcp-env.md` — 環境參照（端點、IP、資源名稱）。
- `.claude/OPERATOR.local` — 操作者個人層級設定。**已 gitignore**，每位操作者自行建立。

每次對話開始時，Claude 讀取 `.claude/OPERATOR.local` 並在整個 session 內依該層級運作。若檔案不存在，預設為 Tier 1（操作者）。修改此檔案後需開啟新的 session 才會生效。

### 操作者層級

| 層級                | 所需 GCP IAM                                                                                                   | AI 協助範圍                                                                                                            |
| ------------------- | ----------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| **Tier 1 — 操作者** | `roles/container.viewer`、`roles/compute.viewer`、`roles/cloudsql.viewer`、`roles/artifactregistry.reader`、`roles/logging.viewer`、`roles/monitoring.viewer` | 唯讀診斷 + 本地 manifest 編輯；`kubectl` 寫入與 `gcloud` 建立/刪除資源以指令文字提供，操作者自行執行 |
| **Tier 2 — 部署者** | Tier 1 + `roles/container.developer`（kubectl 寫入）、`roles/compute.loadBalancerAdmin`（backend-service/URL Map）、`roles/cloudsql.editor` | 同 Tier 1；另直接執行 `kubectl` 寫入類與 `gcloud` 建立/刪除資源（黑名單外所有指令） |

> **IAM 補充說明：**
> - `Shell/service_account_binding.sh` 需要操作者自身帳號持有 `roles/iam.serviceAccountAdmin`（對目標 GSA），與 AI 輔助 Tier 無關——這個腳本本身在黑名單中，永遠由操作者親自執行。
> - Tier 2 若需 AI 直接執行更多 `gcloud` 建立/刪除資源，依實際操作內容另授對應角色。

AI **永遠不代為執行** `git push`、`argocd` 及 `./Shell/*`（黑名單強制）——這些永遠以指令文字提供，由操作者自行執行。

### 設定層級（一次性操作）

```bash
echo "tier: 1" > .claude/OPERATOR.local   # 升級至 Tier 2 需具備 container.developer 角色
```

### 對話範例

```
你：  new-caring-mobile-api-dev 一直回 502，幫我查原因。

AI：  執行 kubectl get/describe/logs 與 GCLB backend-service 健康檢查，
      找出根本原因，並提供修復指令讓你執行。
```

```
你：  幫我部署新的 API 服務 "billing-api" 到 dev。

AI：  複製既有同類服務目錄建立 Microservices/Caring/.../billing-api/，
      在 Infrastructure/argocd/values.yaml 新增對應 Application entry，
      顯示 diff，再提供 git push 和 Workload Identity 綁定指令讓你執行。
```

## 前置作業

- `gcloud` CLI 已驗證，且具備足夠的 IAM 權限
- `kubectl` 已連線至目標 GKE 叢集（`caring-tw`，`asia-east1`）
- `helm` v3+

```bash
gcloud container clusters get-credentials caring-tw \
  --region asia-east1 --project static-map-242406
```

## 新增服務 / 環境

詳細步驟見：

- `runbooks/new-service.md` — 新增服務
- `runbooks/new-env.md` — 新增環境
- `runbooks/deployment.md` — 部署前置確認與環境升級
