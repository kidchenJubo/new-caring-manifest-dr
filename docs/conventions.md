# Jubo New Caring Manifest — 專案慣例

本文件定義本 repo（`new-caring-manifest`）的服務規格、命名慣例、Helm chart 結構與範本規格。
AI 助理與操作者均應以此為準。

---

## 目錄結構

服務不是放在扁平的 `charts/<service>/`，而是依 Domain / Layer 分層放在 `Microservices/Caring/<Layer>/[<SubLayer>/]<service-dir>/`：

| Layer               | 範例服務目錄                                                | 說明                         |
| -------------------- | ------------------------------------------------------------- | ---------------------------- |
| `Backend/Api`        | `new-caring-web-api`、`new-caring-mobile-api`                | .NET API                     |
| `Frontend/Web`       | `Frontend/Web`（Chart name: `new-caring-web`）              | .NET Razor 網頁              |
| `Frontend/Page`      | `Frontend/Page/new-caring-web-page`                          | Node/Next 前端頁面（port 3000） |
| `Event/Consumer`     | `Event/Consumer/new-caring-event-consumer`（Chart name: `caring-event-consumer`） | 純背景 Pub/Sub 消費者        |
| `Scheduler`          | `Scheduler/CareeNotification`（Chart name: `caree-notification`） | 排程/Worker                  |
| `Proxy`              | `Proxy/maintenance-page-proxy`                                | Nginx 維護頁反向代理          |

⚠️ **服務目錄名稱不一定等於 `Chart.yaml` 的 `name`**（也就是不等於 `{{ .Chart.Name }}`，即實際 K8s 資源命名的依據）。例如目錄 `new-caring-event-consumer` 的 Chart name 是 `caring-event-consumer`；目錄 `CareeNotification` 的 Chart name 是 `caree-notification`。修改服務前務必先讀 `Chart.yaml` 確認實際 Chart name。

`.gitignore` 中的 `charts/` 只是排除任何字面上叫這個名字的目錄，本 repo 並未使用該目錄結構。

ArgoCD 自我管理的 Helm chart 放在 `Infrastructure/argocd/`，是 `Infrastructure/` 目前唯一的子目錄。

---

## 服務類型與範本

`templates/` 內含哪些檔案，依服務是否對外提供 HTTP、是否需連線資料庫而不同：

| 範本檔案              | Backend Api | Frontend Web | Frontend Page | Event Consumer | Scheduler | Proxy |
| ---------------------- | :---------: | :-----------: | :------------: | :--------------: | :-------: | :---: |
| `deployment.yaml`      |      ✓      |       ✓       |        ✓        |         ✓         |     ✓     |   ✓   |
| `configMap.yaml`       |      ✓      |       ✓       |    ✓（小寫 `configmap.yaml`） |         ✓         |     ✓     |   ✓   |
| `serviceAccount.yaml`  |      ✓      |       ✓       |        —        |         ✓         |     ✓     |   ✓   |
| `service.yaml`         |      ✓      |       ✓       |        ✓        |         —         |     —     |   ✓   |
| `hpa.yaml`（值閘控，見下） |      ✓      |       —       |        —        |         ✓         |     ✓     |   —   |
| `pdb.yaml`（值閘控，見下） |      ✓      |       —       |        —        |         —         |     —     |   —   |

對外路由由共用 GCLB（Backend Service + Standalone NEG）負責，規則寫在 GCP 的 URL Map 上，屬於手動維護的網路資源（見「網路入口」）。

**HPA/PDB 是否啟用由 values 旗標控制，不只看檔案是否存在**：`templates/hpa.yaml` 內容包在 `{{- if .Values.App.UseHPA }}` 內，`templates/pdb.yaml` 包在 `{{- if .Values.App.UsePDB.enabled }}` 內。即使某服務有這兩個範本檔案，若對應環境的 `values_<env>.yaml` 沒有把旗標打開，實際上不會產生 HPA/PDB 資源。新增服務時若複製到含這兩個範本的來源（如 `new-caring-mobile-api`），記得檢查旗標值是否符合新服務的需求。

`Frontend/Page/new-caring-web-page` 沒有 `serviceAccount.yaml`、沒有 Workload Identity annotation、沒有 `cloud-sql-proxy` initContainer——它是純前端頁面，不連 GCP 資源。

---

## 命名慣例

| 項目                 | 格式                                                                          | 範例                                                                      |
| -------------------- | ------------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| Namespace            | `<destinationNamespace>`（見 `Infrastructure/argocd/values.yaml` 該 entry）    | `new-caring-mobile-api-dev`、`caree-notification-qat`                    |
| Image                | `asia-east1-docker.pkg.dev/static-map-242406/new-caring/<image-name>:<version>` | `asia-east1-docker.pkg.dev/static-map-242406/new-caring/caring-mobile-api:2.1.4.18` |
| ConfigMap            | `{{ .Chart.Name }}-config`                                                     | `caring-mobile-api-config`                                                |
| KSA (ServiceAccount) | `{{ .Chart.Name }}`                                                            | `caring-mobile-api`                                                      |
| ArgoCD Application   | `Infrastructure/argocd/values.yaml` 的 `apps.applications` map key             | `new-caring-web-api-dev`                                                  |

Image 的 `<version>` 是**自由字串**，不是固定 semver，實際觀察到的值例如 `2.1.4.18`、`razor-dev-1783413010`、`JCP-2322-2`。image 由本 repo 之外的流程建置並推送到 Artifact Registry `asia-east1-docker.pkg.dev/static-map-242406/new-caring`，本 repo 只被動接收更新後的 tag 寫入 `values_<env>.yaml` 的 `App.Version`。

---

## Values 檔案慣例

檔名是 `values_<env>.yaml`（**底線**分隔，不是連字號），例如 `values_dev.yaml`、`values_qat2.yaml`。

每個服務的每個環境都是一份**完整、獨立**的 `values_<env>.yaml`，所有 key（包含資料庫連線字串、client secret 等）在每個檔案裡各自填滿該環境的實際值。單一環境的服務（`maintenance-page-proxy`）與 `Infrastructure/argocd` 自己的 chart values 則只有一份 `values.yaml`。

實務上偶爾會留下 `# TODO: ...` 註解標記「暫用值，待取得真實值後更新」（例如某些服務 `values_dev2.yaml`），但欄位本身仍填了一個可執行的暫用值，而不是留空或填 `TBD`。新增環境時，複製既有環境檔整份修改，不要嘗試建立共用 base 檔案。

環境變數注入方式：`ConfigMap`（**不是** Kubernetes Secret），透過 `envFrom.configMapRef` 整份注入容器（見 `templates/configMap.yaml`）。key 命名使用 `__`（雙底線）作為分隔符（ASP.NET Core 慣例），例如 `ConnectionStrings__PostgreSqlMaster`。

values 內常見的頂層區塊：`App`（服務設定、資源限制、connection string 等）與 `SqlProxy`（Cloud SQL Proxy 版本、instance、resources），皆使用**大寫開頭**的 key（.NET 慣例），與常見 Helm chart 慣用的小寫 `app.xxx` 不同。

---

## 範本關鍵慣例

- Container port：API/Web 為 **8080**；`new-caring-web-page` 為 **3000**；`maintenance-page-proxy` 為 **80**。Service port 統一對外 **80**，`targetPort` 指回容器 port。
- Liveness/Readiness probe：`GET /health`，port 8080（`initialDelaySeconds` 30/15，`periodSeconds` 20/10）。**不是所有服務都有 probe**：`new-caring-web-page` 與 `CareeNotification`（`caree-notification`）的 probe 整段被註解掉，沒有健康檢查。
- `preStop`：主容器一律 `sleep <N>`（多數服務 `sleep 20`，`Frontend/Web` 為 `sleep 10`，`maintenance-page-proxy` 為 `sleep 5; nginx -s quit`）；`cloud-sql-proxy` initContainer **不設定** `preStop`（native sidecar 由 K8s 保證在所有一般 container 退出後才收到 SIGTERM）。
- 環境變數分隔符：`__`（雙底線）。
- 資源定義：`App.AppResources`（主容器）與 `SqlProxy.SqlProxyResources`（cloud-sql-proxy），透過 `{{ toYaml .Values.xxx | indent 11 }}` 渲染在 `resources:` 下。
- `imagePullPolicy`：所有服務都沿用 K8s 預設值 `IfNotPresent`（tag 幾乎都是唯一字串，不是 `latest`），新增服務不需要額外設定這個欄位。
- `topologySpreadConstraints`（`maxSkew: 1`, `whenUnsatisfiable: ScheduleAnyway`）與 `terminationGracePeriodSeconds: 60` 是 Backend Api 層常見的额外設定，複製既有 API chart 時會一併帶過去。

---

## Secret 管理現況

資料庫密碼、client secret 等敏感值**目前直接以明文寫在 `values_<env>.yaml`**，透過 `ConfigMap` 注入容器。這是目前的**實際現況**，AI 在讀取這些檔案或任何 log/env var 輸出時，仍必須依 `CLAUDE.md`「Secret 安全警示」流程對疑似明碼 secret 進行遮蔽與警告，即使該值本來就在 repo 裡。

唯一真正的 Kubernetes `Secret` 引用出現在 `Infrastructure/argocd/values.yaml`（ArgoCD Dex 的 `$argocd-dex-ms-secret:clientSecret`，Helm chart 自身的 Vault 風格語法），代表這個 Secret 是叢集內既存、由 ArgoCD 安裝流程外部管理，**不是**給業務服務用的通用模式，不應比照套用到其他服務。

**release（正式環境）建議**：優先評估導入 External Secrets Operator 或 Kubernetes Secret，將 `values_release.yaml` 中的明文密碼移出 Git 版控範圍；此為建議事項，非目前現況。

---

## Cloud SQL Proxy

每個需連 DB 的服務使用 Kubernetes native sidecar 模式（`initContainers` + `restartPolicy: Always`），旗標：

```
--private-ip
--auto-iam-authn   (Workload Identity — 免密碼)
--port=5432
--health-check --http-address=0.0.0.0 --http-port=9090
<instance-connection-name>
```

範本結構（`templates/deployment.yaml`）：

```yaml
initContainers:
  - name: cloud-sql-proxy
    restartPolicy: Always
    image: "gcr.io/cloud-sql-connectors/cloud-sql-proxy:{{ .Values.SqlProxy.Version }}"
    args:
      - "--private-ip"
      - "--auto-iam-authn"
      - "--port=5432"
      - "--health-check"
      - "--http-address=0.0.0.0"
      - "--http-port=9090"
      - "{{ .Values.SqlProxy.InstanceName }}"
    resources:
{{ toYaml .Values.SqlProxy.SqlProxyResources | indent 11 }}
    securityContext:
      runAsNonRoot: true
    startupProbe:
      httpGet:
        path: /startup
        port: 9090
      periodSeconds: 2
      failureThreshold: 30
containers:
  - name: {{ .Chart.Name }}
    ...
```

- **`startupProbe`**：確認 proxy 內建 HTTP health check（port 9090、`/startup`）回應正常後，main container 才啟動；不是用 `tcpSocket` 探測 5432。
- **不設 `preStop`**：native sidecar 由 K8s 保證在所有一般 container 退出後才收到 SIGTERM，不需 sleep 來控制順序。

連線字串使用者名稱格式：`<該服務對應的 GSA>@static-map-242406.iam`（IAM 驗證，不需密碼欄位，見「Workload Identity」——每個服務、每組環境對應的 GSA 不同）。目前只有 3 個 Cloud SQL instance（`caring-dev-pg`、`caring-release-pg`、`rs`），dev/dev2/qat/qat2/demo 共用 `caring-dev-pg`，release 用 `caring-release-pg`，見 `.claude/gcp-env.md`「Cloud SQL」表格。

---

## Workload Identity（GSA）

每個服務各自有兩個 GSA：一個給 `dev`/`dev2`/`qat`/`qat2`/`demo`/`rs`（非正式環境）共用，一個給 `release` 專用，兩者互相獨立，服務之間也不共用 GSA。`App.ServiceAccount` 這個 values 欄位決定 `serviceAccount.yaml` 的 annotation 指向哪個 GSA：

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .Chart.Name }}
  annotations:
    iam.gke.io/gcp-service-account: {{ .Values.App.ServiceAccount }}
```

| 服務（Chart name）        | 非正式環境 GSA（dev/dev2/qat/qat2/demo）                       | release GSA                                                  |
| --------------------------- | ------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `new-caring-web-api`      | `new-caring-web-api-dev@static-map-242406.iam.gserviceaccount.com` | `new-caring-web-api-release@static-map-242406.iam.gserviceaccount.com` |
| `new-caring-mobile-api`   | `new-caring-mobile-api-dev@static-map-242406.iam.gserviceaccount.com`（僅 dev/qat/demo，此服務無 dev2/qat2/rs） | `new-caring-mobile-api-release@static-map-242406.iam.gserviceaccount.com` |
| `new-caring-web`          | `new-caring-web-dev@static-map-242406.iam.gserviceaccount.com` | `new-caring-web-release@static-map-242406.iam.gserviceaccount.com` |
| `caring-event-consumer`   | `caring-event-consumer-dev@static-map-242406.iam.gserviceaccount.com` | `caring-event-consumer-release@static-map-242406.iam.gserviceaccount.com` |
| `caree-notification`     | `caree-notification-dev@static-map-242406.iam.gserviceaccount.com`（僅 dev/qat/demo，此服務無 dev2/qat2/rs） | `caree-notification-release@static-map-242406.iam.gserviceaccount.com` |
| `maintenance-page-proxy` | `n-c-b-a@static-map-242406.iam.gserviceaccount.com`（尚未納入本次拆分，仍用舊的共用 GSA） | 同左（此服務無環境區分）                                        |

**`rs`（還原演練）不屬於上面「非正式環境」那一組，而是用該服務的 release GSA**——`rs` 的 Postgres instance 是從 `caring-release-pg` 的備份還原而來，沿用 release GSA 可以讓還原後資料庫內既有的 IAM 使用者直接生效，不需要另外在 `rs` instance 裡建立一個對應 dev GSA 的資料庫使用者。`SqlProxy.InstanceName` 仍指向 `rs` instance，只有 `App.ServiceAccount`／連線字串的 `Userid` 改用 release GSA，兩者不要混淆（見 `runbooks/rs-drill.md`）。有 `rs` 環境的服務：`new-caring-web-api`、`new-caring-web`、`caring-event-consumer`。

`new-caring-web-api` 與 `new-caring-mobile-api` 的 `templates/serviceAccount.yaml` 原本直接寫死 GSA email（不經過 values），已改為與其他服務一致的 `{{ .Values.App.ServiceAccount }}` 樣板寫法。

綁定透過 `Shell/service_account_binding.sh` 執行——這不是像 `bind_dev()`/`bind_prod()` 這種函數化腳本，而是一份逐一列出所有 `namespace × KSA` 組合的完整腳本（每個組合兩行：`gcloud iam service-accounts add-iam-policy-binding` + `kubectl annotate serviceaccount`）。新增服務或新增環境時，需要在這份腳本中補上對應的兩行；這次的 GSA 拆分也需要把既有的每一行改指向對應的新 GSA。

`n-c-b-a@static-map-242406.iam.gserviceaccount.com` 這個 GSA 被授予 `jubo-care-platform` 這個**另一個** GCP project 的 `roles/pubsub.subscriber`（見 `Shell/service_account_binding.sh` 末尾），用於訂閱該 project 的 Pub/Sub topic。改用新 GSA 後，實際使用 Pub/Sub 的服務（`new-caring-web-api`、`caring-event-consumer`）的新 GSA 也需要這個跨專案授權，否則會遺失既有的 Pub/Sub 訂閱權限——這點需要操作者確認並補上。

---

## 網路入口

對外流量路由機制是：

1. `templates/service.yaml` 在 Service 加 `cloud.google.com/neg` annotation，產生 Standalone NEG（命名 `<namespace>-80`）：

   ```yaml
   annotations:
     cloud.google.com/neg: '{"exposed_ports": {"80":{"name": "{{ .Release.Namespace }}-80"}}}'
   ```

2. 操作者手動執行 `Shell/create_lb_backend_services.sh`，用 `gcloud compute backend-services create`（region `EXTERNAL_MANAGED`）建立 backend-service，再把三個 zone 的 NEG 加進去。
3. 手動在**既有共用 GCLB**（`lb` / `lb-dev` / `lb-demo` 三個 URL Map 之一）用 `gcloud compute url-maps` 加入 host rule + path matcher，把特定網域路由到這個新 backend-service。

以上 2、3 兩步是**手動 GCP 操作**，不在此 repo 的 Helm/K8s manifest 範圍內，也不會透過 ArgoCD 同步。詳細的既有 URL Map、External IP、host 對照見 `.claude/gcp-env.md`「網路入口」章節。

TLS 憑證是手動上傳的 `SELF_MANAGED` 憑證，不是 cert-manager 自動管理，到期需操作者手動更新。

路由規則（`/api/**` → web-api、`/v2/**` → web-page、其餘 → web）寫在 GCLB URL Map 的 `pathMatchers.routeRules`，屬於手動維護的網路資源，由操作者用 `gcloud compute url-maps` 直接調整。

---

## ArgoCD Application 模式

`Infrastructure/argocd/templates/applications.yaml` 對 `Infrastructure/argocd/values.yaml` 的 `apps.applications` 這個 map 做 `range` 迴圈，每個 key 產生一個 `Application`：

```yaml
apps:
  global:
    repoURL: <repo-url>
    targetRevision: main
  applications:
    new-caring-web-api-dev:
      sourcePath: Microservices/Caring/Backend/Api/new-caring-web-api
      sourceHelm:
        valueFiles:
          - values_dev.yaml
      destinationNamespace: new-caring-web-api-dev
      # syncPolicy:
      #   automated:
      #     enabled: true
```

新增服務的新環境，就是在這個 map 底下新增一個 key（key 名稱慣例為 `<destinationNamespace>`）。目前 `apps.applications` 中**沒有任何一個 entry 設定 `syncPolicy.automated`**，所以全部 25 個 Application 皆為手動 sync，需操作者在 ArgoCD UI/CLI 觸發。若要對某個服務啟用自動同步，在該 entry 加上：

```yaml
syncPolicy:
  automated:
    enabled: true
    prune: true
    selfHeal: true
```

還原演練（`rs`）用的 entry 目前整段被註解掉（保留在檔案中但不生效），代表 `rs` 環境的 values 檔存在但未實際部署。

---

## ArgoCD 自我管理

透過 `Infrastructure/argocd/`（Helm chart 依賴 `argo-cd` `>=6.2.0`）管理，`argocd-apps` 子 chart 已明確棄用（改用上述 `applications.yaml` range 迴圈）。

| 項目      | 值                                                                       |
| --------- | -------------------------------------------------------------------------- |
| URL       | `https://new-caring-argocd.jubo.health`                                   |
| 驗證方式  | Dex + Microsoft Entra ID，限定 `@jubo.health` 帳號                       |
| RBAC      | 所有已驗證使用者均為 `role:admin`（高風險，無細分角色）                   |
| Client ID | `50b6ed34-b030-4104-a14d-c8bc139b7d2b`                                    |

自我管理入口是 `apps.applications.argocd`（`sourcePath: Infrastructure/argocd`，`syncWave: "-20"` 確保最先同步）。ArgoCD 的 Azure/Entra ID 登入密碼由 Jenkins 的 `azure-credentials-rotator` job 每月自動輪替一次，不在本 repo 管理範圍內。

`redisSecretInit.podLabels."sidecar.istio.io/inject": "false"` 是為了避免 Istio sidecar 注入導致該 Job 卡在非 Completed 狀態而加的設定，見 `Infrastructure/README.md`。

---

## Manifest 專屬 Runbook 標記

新增只適用於本 manifest 專案的 runbook 時，必須在檔案**第一行**加上以下標記：

```markdown
> **[Manifest 專屬]** <一句話說明為何只適用於本專案，例如：此流程依賴 JCP 特有的 PSC 架構>
```

bootstrap 流程掃描到這個標記時，會直接刪除整個檔案，不移植至其他 manifest 專案。

---

## 與 JCP 平台的整合

Caring 平台的部分服務（`new-caring-mobile-api` 等）會呼叫另一個稱為 **JCP** 的平台的 API（例如 `App.JCP.EndPoint: "http://jcp-dev-api.jubo.health.internal"`），透過 Private Service Connect（PSC）私有連線；同時也有反方向的 PSC 資源讓 JCP 平台呼叫回 Caring 的 mobile-api。這兩組 PSC 資源的細節（對接的 project ID、producer/consumer 方向）記錄在 `.claude/gcp-env.md`「PSC 對接」章節，部分細節待操作者確認。新增服務若需要對接 JCP 平台的 API，先確認該環境是否已有對應的 PSC 內部網域可用，而不是假設可以直接建立新的對接。
