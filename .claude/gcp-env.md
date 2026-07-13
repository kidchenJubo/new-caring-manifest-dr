# GCP 環境資訊

此檔案由 Claude Code 讀取作為環境參照。所有端點、資源名稱以此為準。

**維護說明：** 此檔案記錄的是慢變動資訊（LB IP、Forwarding Rule 名稱、Cloud SQL instance 等）。
當 LB 重建、DNS 異動、Cloud SQL instance 更換時，請操作者手動更新對應欄位。
更新後建立新 session，AI 才會讀到最新值。

⚠️ **這是一個多專案共用的 GCP project**（`static-map-242406`），內含大量與本 repo（`new-caring-manifest`，即 Jubo Care「Caring」平台）無關的資源（例如 `jcp2-*`、`mohw-*`、`zgvm98/99`、`smbtest*` 等舊系統或其他平台）。AI 對這個 project 下任何 `gcloud` 指令都必須明確帶 `--project static-map-242406`，不要依賴 `gcloud config` 的預設值——**目前這台機器的 `gcloud config` 預設 project 不是 `static-map-242406`**，若省略 `--project` 會查到/改到錯誤的專案。

⚠️ 執行任何 `kubectl` 指令前，必須先確認目前 context 對應到正確叢集，不要依賴殘留的 context：

```bash
kubectl config current-context

# 預期值：gke_static-map-242406_asia-east1_caring-tw
```

若不符，先執行以下指令切換，再繼續操作：

```bash
gcloud container clusters get-credentials caring-tw --region asia-east1 --project static-map-242406
```

---

## AI 允許查詢的 GCP Projects

AI 只能對下列 project 執行任何 `gcloud` / `kubectl` 指令（包含唯讀）。未列出的 project 一律拒絕，不論操作者 Tier。

| Project ID           | 說明                                                                                                                                       |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `static-map-242406` | 主要專案：本 repo（Caring 平台）與其 GKE 叢集、Cloud SQL、Artifact Registry、共用 GCLB 皆在此 project 下。此 project 亦承載其他不相關系統，操作時務必只動 `new-caring-*` / `caring-*` 相關資源。 |

新增允許的 project 請直接在此表格加入一行並說明用途（例如未來確認 `jcp2-*` PSC 對接對象的 project 後）。

---

## GCP 專案

| 項目              | 值                                                                       |
| ----------------- | ------------------------------------------------------------------------ |
| Project ID        | `static-map-242406`                                                    |
| Project Number    | `843840949339`                                                          |
| Region            | `asia-east1`                                                            |
| Artifact Registry | `asia-east1-docker.pkg.dev/static-map-242406/new-caring`（本 repo 服務共用此 repository；project 內另有 `api-server`、`caring-face-recognition` 等其他系統的 repository，與本 repo 無關） |

## GKE 叢集

| 項目         | 值                                                              |
| ------------ | --------------------------------------------------------------- |
| Cluster name | `caring-tw`                                                     |
| Location     | `asia-east1`（regional）                                       |
| Project      | `static-map-242406`                                            |
| Version      | `1.34.8-gke.1126000`（查詢時點：2026-07-13，會隨自動升級變動） |

## ArgoCD

| 項目      | 值                                                                                                        |
| --------- | ---------------------------------------------------------------------------------------------------------- |
| URL       | `https://new-caring-argocd.jubo.health`                                                                   |
| 登入方式  | Dex + Microsoft Entra ID，限定 `@jubo.health` 帳號（`connectors.type: microsoft`, `hostedDomains: [jubo.health]`） |
| RBAC      | 所有已驗證使用者均為 `role:admin`（`configs.rbac.policy.default`，無細分角色，高風險）                     |
| Client ID | `50b6ed34-b030-4104-a14d-c8bc139b7d2b`                                                                     |
| 部署機制  | 非 ApplicationSet。`Infrastructure/argocd/templates/applications.yaml` 對 `Infrastructure/argocd/values.yaml` 的 `apps.applications` map 做 `range` 迴圈，每個 key 產生一個 `Application`。 |
| Sync 方式 | 目前 `apps.applications` 中**沒有任何一個 entry 設定 `syncPolicy.automated`**，所有 Application 皆為手動 sync（需操作者在 ArgoCD UI/CLI 觸發）。 |

---

## 環境清單

**此表為環境的唯一清單。** 各服務實際擁有的環境不一致，見下方「各服務環境對照」。

| 環境     | 狀態                                            | Cloud SQL Instance                              |
| -------- | ----------------------------------------------- | ------------------------------------------------ |
| `dev`    | 使用中                                          | `static-map-242406:asia-east1:caring-dev-pg`    |
| `dev2`   | 使用中（僅 `new-caring-web-api`、`new-caring-event-consumer` 有此環境） | `static-map-242406:asia-east1:caring-dev-pg`    |
| `qat`    | 使用中                                          | `static-map-242406:asia-east1:caring-dev-pg`    |
| `qat2`   | 使用中（僅 `new-caring-web-api`、`new-caring-event-consumer` 有此環境） | `static-map-242406:asia-east1:caring-dev-pg`    |
| `demo`   | 使用中                                          | `static-map-242406:asia-east1:caring-dev-pg`    |
| `release`| 使用中（相當於 prod，正式對外環境）             | `static-map-242406:asia-east1:caring-release-pg`|
| `rs`     | 停用（還原演練 restore drill 用；`Infrastructure/argocd/values.yaml` 中對應 Application entry 目前整段註解，未實際部署） | `static-map-242406:asia-east1:rs`               |

### 各服務環境對照

| 服務                          | 有的環境                                        |
| ----------------------------- | ------------------------------------------------ |
| `new-caring-web-api`          | dev, dev2, qat, qat2, demo, release（另有 rs values 檔，未部署） |
| `new-caring-mobile-api`       | dev, qat, demo, release                          |
| `new-caring-event-consumer`   | dev, dev2, qat, qat2, demo, release（另有 rs values 檔，未部署） |
| `new-caring-web`（Frontend/Web） | dev, qat, demo, release（另有 rs values 檔，未部署） |
| `new-caring-web-page`         | dev, qat, demo, release                          |
| `caree-notification`          | dev, qat, demo, release                          |
| `maintenance-page-proxy`      | 無環境區分（單一 `values.yaml`，跨環境共用維護頁） |

新增環境或服務時，同步更新以上兩個表格。

---

## 網路入口：共用 GCLB（Backend Service + Standalone NEG）

每個對外服務的 `Service` 加上 `cloud.google.com/neg` annotation 產生 Standalone NEG（命名 `<namespace>-80`），再由操作者手動執行 `Shell/create_lb_backend_services.sh` 建立 region external managed backend-service，掛進**既有的共用 GCLB**（`lb` / `lb-dev` / `lb-demo` 三個 URL Map，透過 host-based routing 分流到各服務的 backend-service）。這組 GCLB 同時承載大量與本 repo 無關的舊系統路由，修改時務必只動 `new-caring-*` / `caree-notification-*` / `maintenance-page-*` 相關的 host rule 與 path matcher。

TLS 憑證為手動上傳的 `SELF_MANAGED` 憑證（`caringcm2026`、`caringcm2026-all`、`cloudflare` 等），**不是** cert-manager 自動管理；到期後需操作者手動更新，不在本 repo 的 GitOps 範圍內。

Health check：`k8s-health-check-new-caring`（TCP，`--use-serving-port`），由所有 `new-caring-*-80` backend-service 共用。

| URL Map   | 對外 Forwarding Rule       | External IP      | 涵蓋環境                                    |
| --------- | --------------------------- | ---------------- | -------------------------------------------- |
| `lb-dev`  | `lb-dev-forwarding-rule`（另有 `lb-dev-forwarding-rule-3`） | `35.206.209.119` | dev, dev2, qat, qat2, rs, ArgoCD（`new-caring-argocd.jubo.health`） |
| `lb-demo` | `sso-demo`                  | `35.206.211.60`  | demo                                         |
| `lb`      | `lb-forwarding-rule`（另有 `lb-port-45001`、`lb-port-9008`） | `35.206.228.15`  | release                                      |

### 主要對外網域範例（host-based routing，非窮盡清單）

| 環境      | Web（`new-caring-web` / `new-caring-web-page`） | Mobile API                                                          | Web API（`/api/**`，與 Web 同網域） |
| --------- | ------------------------------------------------ | --------------------------------------------------------------------- | ------------------------------------ |
| `dev`     | `upgrade-dev-01.caringcm.com.tw`（或 `-03`）    | `mobile-api-dev.caringcm.com.tw`（另有 JCP 對接網域 `jcp-dev-api-caring.jubo.health`） | 同 Web 網域下 `/api/**`             |
| `dev2`    | `upgrade-dev-02.caringcm.com.tw`（或 `-04`）    | 無獨立 mobile-api 環境                                                | 同 Web 網域下 `/api/**`             |
| `qat`     | `upgrade-qat-01.caringcm.com.tw`                | `mobile-api-qat.caringcm.com.tw`（另有 `jcp-qat-api-caring.jubo.health`） | 同 Web 網域下 `/api/**`             |
| `qat2`    | `upgrade-qat-02/03/04.caringcm.com.tw`          | 無獨立 mobile-api 環境                                                | 同 Web 網域下 `/api/**`             |
| `demo`    | `sso-demo.caringcm.com.tw`（另有 `mgmt*`、`test*` 等多個舊網域指到同一 backend） | `mobile-api-demo.caringcm.com.tw`（另有 `jcp-demo-api-caring.jubo.health`） | 同 Web 網域下 `/api/**`             |
| `release` | `sso-release.caringcm.com.tw`                   | `mobile-api.caringcm.com.tw`（另有 `jcp-release-api-caring.jubo.health`） | 同 Web 網域下 `/api/**`             |

> 這些 host rule 定義在 URL Map 的 `pathMatchers`（`gcloud compute url-maps describe <lb|lb-dev|lb-demo> --region asia-east1 --project static-map-242406`），**不在此 repo 的 Helm/K8s manifest 範圍內**，新增/修改需操作者手動執行 `gcloud compute url-maps ...` 或透過 Console，本 repo 只負責 K8s 端的 Service/NEG。

---

## PSC 對接（與「JCP」平台的雙向私有連線，細節待操作者確認）

Caring 平台會呼叫另一個稱為 **JCP** 的平台的 API（見 `new-caring-mobile-api` 的 `values_dev.yaml`：`App.JCP.EndPoint: "http://jcp-dev-api.jubo.health.internal"`，其他服務的 values 亦有 TODO 註解提及「需向 JCP 團隊取得實際值」）。Project 內有兩組方向相反的 PSC（Private Service Connect）資源，推測分別對應「Caring 呼叫 JCP」與「JCP 呼叫 Caring」兩個方向，但另一端所在的 project ID 未經操作者確認前不應假設：

| 推測方向                                                                     | Forwarding Rule（本 project 內）                    | Internal IP                               | 對應 Service Attachment                          |
| ------------------------------------------------------------------------------ | ------------------------------------------------------ | -------------------------------------------- | --------------------------------------------------- |
| **Caring 為 Consumer**：呼叫 JCP 平台 API（對應 `App.JCP.EndPoint` 的 `.internal` 網域） | `jcp2-dev`, `jcp2-qat`, `jcp2-uat`, `jcp2-prod`         | `10.140.0.66` / `.67` / `.94` / `.19`      | `jcp2-dev`, `jcp2-qat`, `jcp2-uat`, `jcp2-prod`（推測位於 JCP 平台的 GCP project） |
| **Caring 為 Producer**：將自己的 mobile-api 私有暴露給 JCP 平台呼叫             | `psc-jcp-dev-api`, `psc-jcp-qat-api`, `psc-jcp-demo-api`, `psc-jcp-release-api` | `10.140.0.123` / `.124` / `.125` / `.126` | `psc-jcp-dev-api-20260129` 等（本 project 內建立，producer-forwarding-rule 待確認指向哪個 backend-service） |

> 兩組資源皆需操作者確認：(1) JCP 平台實際所在的 GCP project ID；(2) `psc-jcp-*-api` 的 producer forwarding rule 是否確實對應 `new-caring-mobile-api-<env>-80` backend-service。確認後請更新本節並補上 project ID 到「AI 允許查詢的 GCP Projects」表格（若需要對該 project 執行查詢指令）。

---

## Cloud SQL

| Instance            | Connection Name                                    | 用途                                    |
| -------------------- | ---------------------------------------------------- | ----------------------------------------- |
| `caring-dev-pg`     | `static-map-242406:asia-east1:caring-dev-pg`       | dev / dev2 / qat / qat2 / demo 共用      |
| `caring-release-pg` | `static-map-242406:asia-east1:caring-release-pg`   | release 專用                             |
| `rs`                | `static-map-242406:asia-east1:rs`                  | 還原演練（restore drill）專用，目前未部署對應服務 |

連線方式：Cloud SQL Proxy native sidecar（`--auto-iam-authn`），使用者名稱固定為 `n-c-b-a@static-map-242406.iam`（見 Workload Identity）。

---

## Workload Identity（GSA）

所有服務、所有環境**共用單一個 GSA**，並非依環境或依服務分開：

| GSA                                                       |
| ---------------------------------------------------------- |
| `n-c-b-a@static-map-242406.iam.gserviceaccount.com`      |

`serviceAccount.yaml` 中的 KSA annotation（`iam.gke.io/gcp-service-account`）一律指向此 GSA。綁定透過 `Shell/service_account_binding.sh` 執行（非函數化的 `bind_dev()`/`bind_prod()`，是逐一 namespace 條列的完整腳本，新增服務/環境需在其中補上對應的 `gcloud iam service-accounts add-iam-policy-binding` + `kubectl annotate` 兩行）。

此 GSA 另被授予 `jubo-care-platform` project 的 `roles/pubsub.subscriber`（用於訂閱該 project 的 Pub/Sub topic，見 `Shell/service_account_binding.sh` 末尾）。

---

## 網路（Cloud NAT）

| 項目            | 值                        |
| --------------- | -------------------------- |
| Cloud NAT 名稱  | `new-caring-nat`          |
| Cloud Router    | `new-caring-nat-router`   |
| VPC             | `new-caring-vpc`          |
| Egress (NAT) IP | `AUTO_ONLY`（自動配置，未固定；需要固定 IP 白名單時需改為 MANUAL_ONLY 並配置靜態位址，目前非此設定） |
