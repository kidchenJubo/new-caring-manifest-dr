# 初始化 AI 輔助（首次 Bootstrap）

## 觸發條件

AI 於每次對話開始時，先確認 `.claude/gcp-env.md` 是否存在。**若不存在**，必須先完成本流程，才能回應其他操作請求；若存在，跳過本流程，依 `CLAUDE.md`「AI 輔助部署指南」章節走一般流程。

本流程是 `CLAUDE.md` 黑名單「寫入或修改 `CLAUDE.md`」「寫入或修改 `.claude/` 下任何檔案」的**唯一例外**，且僅限下列步驟 1–4 的範圍。流程結束、`.claude/gcp-env.md` 建立完成後，例外即自動失效，後續 session 回到完全黑名單狀態。除此流程外，黑名單其餘規則不受影響。

## 流程

### 改寫原則（適用步驟 1–2）

- **Bootstrap 期間的上下文隔離**：進入本流程時，現有的 `CLAUDE.md`、`docs/`、`runbooks/`、`gcp-env.md` 都是**待改寫的來源範本**，其中的 project ID、cluster name、endpoint 等均屬於來源專案的值（例如 `jubo-care-platform`），不是目標專案的正確配置。AI 在 bootstrap 期間輸出的所有診斷訊息與指令範例，其中的 project ID 只能來自操作者明確告知的目標值，或以 `<PROJECT_ID>` 佔位符表示；**禁止將現有 `gcp-env.md` 的具體值直接引用到對目標專案的描述中**。若 `gcloud config` 顯示的預設 project 與目標專案不同，只需提示操作者「目前 gcloud 預設 project 不是目標專案，請確認是否需要切換」，不要在訊息中直接寫出來源專案的名稱。
- **局部修正 vs 整份重寫**：若一個 runbook 大部分段落（多數 Phase／步驟）都建立在目標專案不存在的機制上（例如整份 `new-env.md` 都是 Gateway + cert-manager 流程，但目標專案用 GCLB），逐行替換字串會留下結構性錯誤，改為保留「這份 runbook 想解決的問題」與整體骨架（前置作業 → 建立設定 → 佈建網路資源 → DNS／憑證（若有）→ 收尾更新 `gcp-env.md`），內容依實際腳本與資源整份重寫。
- **找不到對應機制時誠實標記，不可虛構**：若 repo 中完全找不到某個環節的痕跡（例如 DNS 或憑證由誰管理），標記為 `TBD`，附上已嘗試的搜尋方式與範圍，交由操作者補充；絕不能為了讓文件看起來完整而編造一個「看起來合理」的流程。
- **不移植專案特例**：像 JCP 專案「storage-worker 依賴 GCS bucket → Pub/Sub notification」這類綁定特定服務的手動建立資源清單，是該專案的特例，不代表目標專案也有類似依賴；若目標專案沒有對應的手動資源清單，直接整段移除，不得套用原專案的情境改寫成看似通用的版本。
- **與特定機制無關的段落維持不變**：不依賴特定網路工具或部署機制的內容（例如一般 `kubectl` 診斷指令、`CrashLoopBackOff`／`ImagePullBackOff`／`OOMKilled` SOP）通常在任何專案都適用，不需修改。
- **同一字串常重複出現，逐段修改容易漏改**：像 `scripts/` 這類字面字串常同時出現在慣例說明、指令範例、腳本清單等多個獨立段落，只巡查一次容易遺漏；修改完成後一律用全文搜尋驗證（見下方「完成改寫後必須驗證」）。
- **改寫後的內容只呈現目標專案本身，不留比較痕跡**：確認某項與 JCP 不符後，直接以目標專案的實際慣例重寫該段落內容；成品中不得出現「與 JCP 類專案不同」「原始檔案是 XXX」「不同於範本」之類的比較性說明。這些比較只是本流程判斷「要不要改、改成什麼」的中間過程，不是給讀者看的內容——未來讀 `CLAUDE.md`／`docs/`／`runbooks/` 的操作者只在乎這個專案本身怎麼運作，不知道也不需要知道 JCP 的存在，比較性文字只會造成困惑、降低可讀性。
- **刪除不適用的段落時不留說明，描述目標專案只用肯定句**：當 JCP 的某個機制或慣例（例如 TBD 佔位符、`storage-worker` 依賴、PSC）在目標專案不存在，直接刪除對應段落，改寫為目標專案實際的做法。**禁止出現「本專案沒有 X」「這個專案不使用 X」「無 X 機制」等否定句**——這類句子無論是出現在文件內容、流程說明或診斷指引中，都代表 AI 仍以 JCP 作為對照基準來描述目標專案，違反本原則。

  禁止示例：
  - 「沒有共用 `values.yaml` base + 環境覆寫的機制，也沒有 `TBD` 佔位符慣例」
  - 「本專案沒有 `TBD` 佔位符機制，需直接比對欄位值是否合理」
  - 「本專案不使用 PSC」

  正確寫法：直接描述目標專案的實際做法。若整段在目標專案不適用，整段刪除，不加任何替代說明。

1. **掃描專案結構，校正 `CLAUDE.md`**
   - 讀取實際目錄與檔案內容（不得假設目錄名稱與本 repo 相同，例如 `apps/`、`charts/`、`scripts/` 僅為 JCP 專案的命名，其他專案可能完全不同）
   - 依下方「CLAUDE.md 假設值檢查清單」逐項偵測，確認每個假設項目在目標專案的實際情況
   - 對「CLAUDE.md 預設寫法」與實際不符的項目，改寫 `CLAUDE.md` 中對應的段落、對話範例、指令片段；若某機制（例如某種 values 佔位符慣例）在目標專案根本不存在，該整段規則可整段重寫或刪除，不限於替換路徑字串
   - 不得變更「AI 的執行邊界規則」中的 Tier 分級架構、白名單／黑名單分類本身，以及本流程（bootstrap）自身的觸發條件與例外範圍
   - 掃描過程中發現檢查清單未列出的其他隱含假設（例如 Secret 管理工具、CI/CD 觸發方式、monorepo/multi-repo 結構），依同樣模式新增一列並記錄
   - 列出「修正前 → 修正後」摘要供操作者確認

   ### CLAUDE.md 假設值檢查清單

   | 假設項目                    | CLAUDE.md 預設寫法（JCP 專案）                                                                     | 偵測方式                                                                                                                                                                     | 不符時需改寫的位置                                                                                                                                                                             |
   | --------------------------- | -------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
   | 服務 chart / 程式碼目錄結構 | 扁平的 `charts/<service>/`                                                                         | `find . -iname "Chart.yaml"` 或等效指令，確認實際路徑深度與命名層級（例如依 Domain / Layer 分層）                                                                            | `CLAUDE.md` 文件索引與對話範例；`docs/conventions.md`；`runbooks/new-service.md`                                                                                                               |
   | 部署管理機制                | 每服務一個 `apps/services/<service>.yaml`，ArgoCD **ApplicationSet**，用 YAML 註解控制環境是否啟用 | 搜尋 ArgoCD 相關設定（`grep -rl "kind: Application" .` 等），確認是實際的 ApplicationSet、還是單一設定檔 + map（例如 Helm `range` 產生一般 Application），或其他 GitOps 工具 | `CLAUDE.md`「AI 輔助部署指南」對話範例；`docs/conventions.md`「ArgoCD ApplicationSet 範本」；`runbooks/new-service.md`、`runbooks/deployment.md`「環境升級前置確認」「在 ArgoCD 啟用自動同步」 |
   | 環境清單                    | `dev` / `qat` / `uat` / `prod`                                                                     | 列舉實際環境名稱來源（values 檔名、ArgoCD 設定、CI/CD 變數等），不得假設一定包含 `prod` 或只有四個環境                                                                       | `CLAUDE.md` 對話範例、「初始化 AI 輔助」以外各章節提到的環境名稱；`.claude/gcp-env.md` 範本的環境表格；所有 runbooks 中的環境範例                                                              |
   | values 檔名與層級慣例       | `values-<env>.yaml`（dash 分隔），有共用 `values.yaml` base + `TBD` 佔位符慣例                     | 檢查實際檔名分隔符（`-` 或 `_`）、是否存在共用 base values 檔、是否真的用 `TBD` 標記待填值                                                                                   | `CLAUDE.md`「Values 完整性檢查」章節（邏輯可能整段不適用於目標專案，需重寫或移除）；`docs/conventions.md`「Values 層級結構」；`runbooks/new-service.md`、`runbooks/deployment.md`              |
   | 腳本目錄與檔名              | `scripts/` 目錄，`bind-workload-identity.sh` 等固定檔名                                            | 找出實際腳本目錄（可能不叫 `scripts/`）與腳本檔名清單                                                                                                                        | `CLAUDE.md`「AI 的執行邊界規則」白名單／預設層表格中 `./scripts/*` 相關規則、對話範例；「初始化 AI 輔助」建立的 `.claude/settings.json`；`runbooks/new-service.md`、`runbooks/new-env.md`      |
   | 網路入口工具                | GKE Gateway API + cert-manager + PSC                                                               | 見「`.claude/gcp-env.md` 基本範本」中「環境與網路入口」小節的偵測指令；同時搜尋是否有移除舊工具的痕跡（例如移除 Istio 的腳本），代表現況可能與歷史文件不同                   | `CLAUDE.md` 文件索引「新增環境」「Stale Config 自動偵測」章節；`runbooks/new-env.md`、`runbooks/troubleshooting.md`                                                                            |

   > 此表非窮盡清單，僅列出已知常見的落差類型；每次執行本流程都應假設目標專案的實際結構可能與上表全部不同。

   **完成改寫後必須驗證，不能只靠巡查記憶：** 同一個字面字串（例如 `scripts/`）常會在 `CLAUDE.md` 內重複出現在不同章節（例如白名單／預設層表格**與**對話範例各出現一次），逐段閱讀容易漏改其中幾處。改寫完成後，對上表「CLAUDE.md 預設寫法」欄位出現的具體字串（至少包含 `scripts/`、`charts/`、`apps/services`、`jubo-care-platform`、`asia-east1`、`jubo.health`、`prod` 等已知會重複出現的字面字串）逐一在 `CLAUDE.md` 全文搜尋：

   ```bash
   grep -n "scripts/\|charts/\|apps/services\|jubo-care-platform\|asia-east1\|jubo\.health\|prod" CLAUDE.md
   ```

   任何搜尋結果都代表遺漏，需回頭修正；改到 0 筆結果才算步驟 1 完成。

2. **校正 `docs/conventions.md` 與 `runbooks/*.md`**
   - 依步驟 1 檢查清單中「不符時需改寫的位置」欄位，逐一修正 `docs/conventions.md` 與對應 runbook
   - 不確定影響範圍時，對步驟 1 表格「CLAUDE.md 預設寫法」欄位出現的關鍵字（如 `charts/`、`values-`、`scripts/`、`ApplicationSet`）在 `docs/` 與 `runbooks/` 全文搜尋，確認是否也需要修正
   - 依下方「docs/conventions.md 與 runbooks 假設值檢查清單」逐一確認每個檔案內建立在 JCP 專案機制上的段落是否適用
   - 確認各 runbook 的指令、路徑、環境變數對應目前 repo 結構
   - 列出修正摘要供操作者確認

   **完成改寫後必須驗證，不能只靠巡查記憶：** 對步驟 1「CLAUDE.md 假設值檢查清單」表格「CLAUDE.md 預設寫法」欄位出現的具體字串，在 `docs/conventions.md` 與所有 `runbooks/*.md` 全文搜尋，確認沒有殘留：

   ```bash
   grep -rn "scripts/\|charts/\|apps/services\|jubo-care-platform\|asia-east1\|jubo\.health\|prod" docs/ runbooks/
   ```

   `runbooks/bootstrap.md` 本身的檢查清單表格會刻意保留這些字串作為「JCP 專案範例」，執行上述搜尋時可排除此檔案；其餘檔案任何搜尋結果都代表遺漏，需回頭修正。

   ### docs/conventions.md 與 runbooks 假設值檢查清單

   | 檔案                  | 段落／假設                                                                                                          | JCP 預設寫法                                                             | 偵測與處理方式                                                                                                                                                |
   | --------------------- | ------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
   | `docs/conventions.md` | 服務類型與範本                                                                                                      | API／Worker 兩類，各自固定範本清單（✓/— 表格）                           | 列出實際 `templates/` 目錄按服務類型分組，依實際範本檔案重寫表格；類別數量（可能有 Frontend 等第三類）與各類所含範本都可能不同                                |
   | `docs/conventions.md` | 命名慣例（Namespace／Image／ConfigMap／KSA／ArgoCD Application）                                                    | 固定格式，含 `jcp` 專案前綴                                              | 逐列核對目標專案實際命名規則；不適用的列刪除，格式不同的列改寫，不得保留 JCP 專屬前綴                                                                         |
   | `docs/conventions.md` | Values 層級結構                                                                                                     | 共用 `values.yaml` base + 各環境 `values-<env>.yaml` 覆寫 + `TBD` 佔位符 | 對齊步驟 1 檢查清單「values 檔名與層級慣例」列的偵測結果；若每個環境是各自完整一份 values（無繼承關係）或無 `TBD` 慣例，改寫本節說明實際模式                  |
   | `docs/conventions.md` | 範本關鍵慣例（container port、health check 路徑、`preStop`、環境變數分隔符、resources 渲染方式、`imagePullPolicy`） | 依 JCP 實際 Helm template 寫定的具體值                                   | 讀取目標專案實際 `templates/deployment.yaml` 等內容逐項核對；模板結構差異大時（例如不同語言框架的健康檢查路徑），整節依實際內容重寫                           |
   | `docs/conventions.md` | Secret 管理                                                                                                         | 固定的 secret 名稱清單（`argocd-dex-ms-secret` 等）                      | 找出目標專案實際的 Secret 資源與管理工具（K8s Secret／External Secrets Operator／Sealed Secrets 等），依實際情況重寫清單                                      |
   | `docs/conventions.md` | Cloud SQL Proxy（native sidecar 模式與旗標）                                                                        | 每服務皆用 Cloud SQL Proxy `initContainers` native sidecar               | 確認資料庫連線機制是否確實是 Cloud SQL Proxy sidecar，或用其他方式（VPC peering、不同旗標、甚至非 Cloud SQL 資料庫）；機制不同則整節重寫或移除                |
   | `docs/conventions.md` | Workload Identity（GSA）                                                                                            | 依環境分不同 GSA（`sa-dev`／`sa-release`）                               | 確認是否真的按環境分不同帳號；若共用單一 GSA，改為單一列，移除環境分流敘述                                                                                    |
   | `docs/conventions.md` | Cloud Storage Bucket + Pub/Sub Notification                                                                         | JCP 專案 `storage-worker` 專屬的 GCS→Pub/Sub 手動建立資源清單            | 依「不移植專案特例」原則，目標專案沒有類似依賴則整節移除                                                                                                      |
   | `docs/conventions.md` | HTTPRoute URL 路徑推導規則                                                                                          | 依 chart name 用固定公式推導 `/api/...`，掛載至 `jcp-<env>-gateway`      | 僅在確認網路入口工具為 Gateway API 時保留；其他工具改寫為實際路由規則，規則不明確時標記 `TBD`                                                                 |
   | `docs/conventions.md` | ArgoCD ApplicationSet 範本                                                                                          | 每服務一個 ApplicationSet，`elements` 列表以註解控制環境                 | 依步驟 1「部署管理機制」偵測結果決定：若是單一設定檔 + map，整節改寫為該檔案的實際範本結構（例如 Helm `range` 產生 Application）                              |
   | `docs/conventions.md` | ArgoCD 自我管理（URL／驗證方式／RBAC／Client ID）                                                                   | JCP 專案實際值                                                           | 純欄位值差異，非機制差異：直接依查詢結果覆寫；若目標專案未自建 ArgoCD self-management chart，整節移除                                                         |
   | `new-service.md`      | 服務類型選擇                                                                                                        | API／Worker 兩類，各自固定範本清單                                       | 列出實際 `templates/` 目錄按服務類型分組，依實際範本檔案重寫表格；類別數量與各類所含範本都可能不同                                                            |
   | `new-service.md`      | Chart／程式碼複製步驟                                                                                               | `cp -r charts/storage-api charts/<service-name>`                         | 依步驟 1 偵測到的目錄結構改寫為「複製既有同類服務目錄」的通用指令，不假設固定路徑深度                                                                         |
   | `new-service.md`      | Image repository 路徑格式                                                                                           | `<REGION>-docker.pkg.dev/<PROJECT_ID>/<PROJECT_ID>/jcp-<service-name>`   | 確認 Artifact Registry repo 名稱是否等於 project id（可能是獨立 repo 名稱），以及 image name 是否等於 chart/service name（可能不同，需分開標示）              |
   | `new-service.md`      | Workload Identity 綁定腳本                                                                                          | `scripts/bind-workload-identity.sh` 的 `bind_dev()`／`bind_prod()`       | 依步驟 1 偵測到的實際腳本改寫；若所有環境共用同一 GSA（無 dev/prod 函數區分），移除環境分流敘述                                                               |
   | `new-service.md`      | HTTPRoute URL 路徑推導公式                                                                                          | 依 chart name 用固定公式推導 `/api/...`                                  | 僅在確認網路入口工具為 Gateway API／有等效路由規則時保留；否則替換為實際路由機制說明，規則不明確時標記 `TBD`，不可虛構公式                                    |
   | `new-service.md`      | Cloud SQL 連線字串使用者名稱                                                                                        | 依環境使用不同 GSA（`sa-dev`／`sa-release`）                             | 確認是否真的按環境分不同 GSA；若共用單一 GSA，改為單一格式，命名待確認時標記 `TBD`                                                                            |
   | `deployment.md`       | 部署流程圖、URL 組成                                                                                                | HTTPRoute 向 Gateway 註冊                                                | 依步驟 1 判斷的網路入口工具替換對應步驟（例如 GCLB backend-service + NEG），機制不明時標記 `TBD`                                                              |
   | `deployment.md`       | 部署前檢查「Gateway 可用性確認」                                                                                    | 檢查 `gcp-env.md` External IP + TLS bootstrap 腳本                       | 改為對應網路工具的可用性確認方式；若無自動化 TLS/憑證 bootstrap 流程，移除該步驟而非留空模板                                                                  |
   | `deployment.md`       | 變更摘要範本／環境升級前置確認                                                                                      | 引用 `charts/`、`apps/services/` 路徑與 Gateway/TLS 檢查項               | 依步驟 1 偵測到的目錄結構與網路工具替換對應路徑與檢查項                                                                                                       |
   | `deployment.md`       | 「解除 element 注解」用語、ArgoCD 自動同步範本                                                                      | 針對每服務一個 ApplicationSet 檔案操作                                   | 若部署機制是單一設定檔 + map，改為對應區塊的整段註解／取消註解、`syncPolicy` 加在對應 map 項目下                                                              |
   | `deployment.md`       | 回滾指令                                                                                                            | `argocd app history` / `rollback`                                        | 通常維持不變（ArgoCD CLI 語法與底層資源型態無關），但需確認 Application 命名慣例一致                                                                          |
   | `new-env.md`          | 全檔案骨架                                                                                                          | 完整 GKE Gateway + cert-manager + PSC 佈建流程（Phase 1–5）              | 落差通常最大：依「改寫原則」的整份重寫規則處理，只保留「新增環境」的目的與骨架，內容依實際佈建方式（腳本／console／Terraform 等）重寫；找不到的環節標記 `TBD` |
   | `new-env.md`          | PSC（內部 Gateway）章節                                                                                             | Producer／Consumer PSC service attachment 設定                           | repo 內若無任何 PSC 痕跡，整段移除，不保留弱化版本                                                                                                            |
   | `new-env.md`          | Storage Bucket + Pub/Sub Notification 章節                                                                          | JCP 專案 `storage-worker` 專屬的 GCS→Pub/Sub 手動建立資源清單            | 依「不移植專案特例」原則，若目標專案沒有類似依賴則整段移除                                                                                                    |
   | `troubleshooting.md`  | 網路相關診斷章節（如「504 / PSC 連線異常」「cert-manager 憑證卡住」）                                               | 針對 Gateway/cert-manager/PSC 的診斷指令                                 | 依步驟 1 偵測到的網路工具整段替換診斷指令與標題（例如改為「GCLB 連線異常」查 backend-service／NEG 健康狀態），無等效機制的章節整段移除                        |
   | `troubleshooting.md`  | 一般診斷指令、CrashLoopBackOff、ImagePullBackOff、OOMKilled                                                         | —                                                                        | 通常維持不變，僅需確認 `kubectl` 指令中的資源命名慣例一致                                                                                                     |

   > 此表同樣非窮盡清單；比對過程中發現其他建立在 JCP 專案特定機制上的段落，依同一模式（JCP 預設寫法 → 偵測方式 → 處理方式）新增列並記錄。

3. **建立 `.claude/gcp-env.md`**
   - 向操作者索取本專案對應的 GCP project ID 與 GKE cluster name
   - 以唯讀指令（`gcloud projects describe`、`gcloud container clusters describe` 等）確認目前 `gcloud` / `kubectl` 身份具備查詢權限；若權限不足，停止流程並回報缺少的角色
   - 以下方「`.claude/gcp-env.md` 基本範本」為骨架建立檔案，依實際查詢結果填入；查詢不到的欄位標記 `TBD` 由操作者後續補齊
   - 「環境與網路入口」小節依步驟 1 判斷出的實際網路工具，只保留對應的子小節，其餘子小節整段刪除
   - 依下方「`.claude/gcp-env.md` 章節適用性檢查」逐一確認範本中每個表格對目標專案是否適用；不適用的整段移除，**不得**留空表格或填入猜測值（同「改寫原則」的 `TBD` 規則）

   ### `.claude/gcp-env.md` 章節適用性檢查

   | 章節                                                                    | 前提假設                                               | 若不適用                                                                                  |
   | ----------------------------------------------------------------------- | ------------------------------------------------------ | ----------------------------------------------------------------------------------------- |
   | ArgoCD                                                                  | 已部署 ArgoCD 且需記錄其 URL／驗證方式／RBAC           | 未使用 ArgoCD（或用其他 GitOps 工具）→ 整節移除或改為對應工具的等效資訊                   |
   | Cloud SQL                                                               | 服務透過 Cloud SQL 存取資料庫                          | 使用其他資料庫服務或連線方式 → 整節移除                                                   |
   | Cloud Storage                                                           | 服務依賴 GCS bucket（如 storage-worker 模式）          | 無此類依賴 → 整節移除，不得比照 JCP 的 bucket 命名慣例套用                                |
   | 網路（Cloud NAT）                                                       | 叢集對外連線經固定 Cloud NAT IP                        | 未設定 Cloud NAT 或用其他 egress 方式 → 整節移除                                          |
   | PSC NAT Subnets | 有內部 Gateway 透過 PSC 對接 consumer VPC | 步驟 1 已判定無 PSC 痕跡 → 整段移除，與 `runbooks/new-env.md` 的 PSC 章節處理方式一致；consumer project 不由 AI 預填，由操作者自行加入「AI 允許查詢的 GCP Projects」 |
   | 環境與網路入口                                                          | 已由「環境與網路入口小節」處理，見上方步驟 1／範本說明 | —                                                                                         |

   > 「AI 允許查詢的 GCP Projects」表格與「GCP 專案」「GKE 叢集」表格為固定必填（AI 白名單查詢範圍的基礎），不可整節移除，只能依實際值填寫或標記 `TBD`。

4. **建立 `.claude/settings.json`**
   - 以下方「`.claude/settings.json` 基本範本」為骨架建立檔案，內容需與 `CLAUDE.md`「AI 的執行邊界規則」黑名單完全對應，作為技術強制層
   - 完成後回報建立的規則清單，供操作者確認範圍是否正確

5. **請操作者自行完成的設定**
   - 提示操作者建立 `.claude/OPERATOR.local`（見 `CLAUDE.md`「操作者設定（必讀）」章節），並說明各 Tier 對應的權限範圍
   - 提示操作者補齊 `.claude/gcp-env.md`, `runbooks/*.md` 與 `docs/*.md` 中標記 `TBD` 的欄位
   - 提示操作者完成上述設定後開啟新 session，AI 才會套用最新設定
   - 提示操作者檢視 `CLAUDE.md`「文件索引」表格，依本專案特有情境（如專屬 runbook、額外檢查流程等）補上對應列

## `.claude/gcp-env.md` 基本範本

未知欄位一律標記 `TBD`，不得憑空填入猜測值。`AI 允許查詢的 GCP Projects` 表格**只填入主要 project**；其他 project 由操作者視需求自行新增，AI 不預設填入任何額外 project。

````markdown
# GCP 環境資訊

此檔案由 Claude Code 讀取作為環境參照。所有端點、資源名稱以此為準。

**維護說明：** 此檔案記錄的是慢變動資訊（Gateway IP、Forwarding Rule 名稱等）。
當叢集 controller 更換、Gateway 重建、IP 異動時，請操作者手動更新對應欄位。
更新後建立新 session，AI 才會讀到最新值。

⚠️ 對這個專案下任何 `gcloud` 指令都必須明確帶 `--project <PROJECT_ID>`，不要依賴預設值，否則會查到/改到錯的專案。

⚠️ 執行任何 `kubectl` 指令前，必須先確認目前 context 對應到正確叢集，不要依賴殘留的 context：

```bash
kubectl config current-context

# 預期值：gke_<PROJECT_ID>_<REGION>_<CLUSTER_NAME>
```

若不符，先執行以下指令切換，再繼續操作：

```bash
gcloud container clusters get-credentials <CLUSTER_NAME> --region <REGION> --project <PROJECT_ID>
```

---

## AI 允許查詢的 GCP Projects

AI 只能對下列 project 執行任何 `gcloud` / `kubectl` 指令（包含唯讀）。未列出的 project 一律拒絕，不論操作者 Tier。

| Project ID     | 說明          |
| -------------- | ------------- |
| `<PROJECT_ID>` | 主要專案：TBD |

新增允許的 project 請直接在此表格加入一行並說明用途。

---

## GCP 專案

| 項目              | 值             |
| ----------------- | -------------- |
| Project ID        | `<PROJECT_ID>` |
| Project Number    | TBD            |
| Region            | TBD            |
| Artifact Registry | TBD            |

## GKE 叢集

| 項目         | 值               |
| ------------ | ---------------- |
| Cluster name | `<CLUSTER_NAME>` |
| Location     | TBD              |
| Project      | `<PROJECT_ID>`   |
| Version      | TBD              |

## ArgoCD

| 項目      | 值  |
| --------- | --- |
| URL       | TBD |
| 登入方式  | TBD |
| RBAC      | TBD |
| Client ID | TBD |

---

## 環境與網路入口

**此表為環境的唯一清單。** 新增或移除環境時只需更新此表，runbooks 與 docs 中的 `<env>` 佔位符自動適用。表格本身與網路工具無關，一律保留。

| 環境  | 狀態 | External IP | API URL | Internal IP |
| ----- | ---- | ----------- | ------- | ----------- |
| `dev` | TBD  | TBD         | TBD     | TBD         |

新增環境時，依序更新：External IP（入口資源佈建後）、Internal IP（PSC 完成後，若無 PSC 則省略）、狀態欄位。

**判斷專案實際使用的網路工具**（不得假設一定是 Gateway API），再從下列子小節挑選對應的一種填入，其餘子小節整段刪除：

```bash
kubectl api-resources | grep -iE "gateway|ingress|virtualservice"
grep -rlE "kind:\s*(Gateway|Ingress|VirtualService)" apps/ charts/ 2>/dev/null
```

### 若使用 GKE Gateway API

取得目前值的指令：

```bash
kubectl -n gateway-system get gateway <gateway-name> \
  -o jsonpath='{.metadata.annotations.networking\.gke\.io/forwarding-rules}'
```

| Gateway | Forwarding Rule 名稱 |
| ------- | -------------------- |
| TBD     | TBD                  |

### 若使用 Ingress（GCE ingress controller / nginx 等）

取得目前值的指令：

```bash
kubectl get ingress -n <ns> <ingress-name> \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

| Ingress 名稱 | Ingress Class | Load Balancer IP |
| ------------ | ------------- | ---------------- |
| TBD          | TBD           | TBD              |

### 若使用 Istio

取得目前值的指令：

```bash
kubectl -n istio-system get svc istio-ingressgateway \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

| Istio Gateway 名稱 | VirtualService | Ingress Gateway Service IP |
| ------------------ | -------------- | -------------------------- |
| TBD                | TBD            | TBD                        |

### 若直接使用 GCLB（無 K8s 層網路資源）

取得目前值的指令：

```bash
gcloud compute forwarding-rules list --project <PROJECT_ID>
```

| Forwarding Rule 名稱 | Backend Service |
| -------------------- | --------------- |
| TBD                  | TBD             |

---

## Cloud SQL

| 環境  | Instance Connection Name |
| ----- | ------------------------ |
| `dev` | TBD                      |

## Cloud Storage

| 環境  | Bucket |
| ----- | ------ |
| `dev` | TBD    |

---

## 網路

| 項目            | 值  |
| --------------- | --- |
| Cloud NAT 名稱  | TBD |
| Egress (NAT) IP | TBD |
| Cloud Router    | TBD |

### PSC NAT Subnets（Producer 端）

| 環境  | Subnet 名稱 | CIDR |
| ----- | ----------- | ---- |
| `dev` | TBD         | TBD  |

新增環境時，從現有最大第三段 +1 開始分配，並在此表新增一行。
````

## `.claude/settings.json` 基本範本

此範本對應 `CLAUDE.md`「AI 的執行邊界規則」黑名單的每一項；黑名單新增項目時，此範本與實際建立的檔案都要同步更新。

```json
{
  "permissions": {
    "deny": [
      "Bash(git push*)",
      "Bash(git commit*)",
      "Bash(git add*)",
      "Bash(git reset*)",
      "Bash(git rebase*)",
      "Bash(git merge*)",
      "Bash(git checkout*)",
      "Bash(git restore*)",
      "Bash(git clean*)",
      "Bash(git branch -D*)",
      "Bash(git branch -d*)",
      "Bash(git stash drop*)",
      "Bash(argocd *)",
      "Bash(gcloud iam *)",
      "Bash(gcloud projects add-iam-policy-binding*)",
      "Bash(gcloud projects remove-iam-policy-binding*)",
      "Bash(gcloud iam service-accounts create*)",
      "Bash(gcloud iam service-accounts delete*)",
      "Bash(gcloud iam service-accounts disable*)",
      "Bash(./scripts/*)",
      "Bash(bash scripts/*)",
      "Bash(sh scripts/*)",
      "Write(CLAUDE.md)",
      "Edit(CLAUDE.md)",
      "Write(.claude/*)",
      "Edit(.claude/*)"
    ]
  }
}
```

> 執行 `./scripts/*` 屬於白名單／預設層（依 Tier 判斷是否直接執行或提供指令文字），不在此黑名單技術層強制封鎖；若專案希望技術層也封鎖腳本執行，可自行加入 `"Bash(./scripts/*)"`、`"Bash(bash scripts/*)"`、`"Bash(sh scripts/*)"`。
>
> `Write(CLAUDE.md)` / `Edit(CLAUDE.md)` / `Write(.claude/*)` / `Edit(.claude/*)` 四條規則對應本流程（`runbooks/bootstrap.md`）的唯一例外：本流程執行期間，操作者需暫時將這四條規則從 `.claude/settings.json` 移除，流程結束建立完成後應立即加回，恢復完整黑名單封鎖。
