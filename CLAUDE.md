# Jubo New Caring Manifest — Claude Code 操作指南

## 定位說明

本文件**只記載 AI 的行為規則與執行邊界**，不含專案慣例或操作步驟。
切換 AI 工具時，只需依新工具格式重寫本文件；`docs/` 與 `runbooks/` 無需異動。

- 專案概覽與目錄結構：`README.md`
- 專案慣例與安全原則：`docs/conventions.md`
- 操作程序：`runbooks/`

## 文件索引

AI 在以下情境**必須主動讀取**對應文件，不得僅依賴本文件的摘要：

| 情境                                                                          | 讀取                                                                |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| 服務異常（502/504、CrashLoop、OOM、GCLB backend-service 不健康等）            | `runbooks/troubleshooting.md`                                       |
| 新增服務                                                                      | `runbooks/new-service.md`                                           |
| 新增環境（values 檔、Cloud SQL、Workload Identity、GCLB host rule）           | `runbooks/new-env.md`                                               |
| 新增環境過程中斷、不確定做到哪個步驟                                          | `runbooks/new-env.md`（讀取「中斷後恢復」章節，執行診斷指令後回報） |
| 執行 git push 前的安全檢查、環境升級確認、回滾                                | `runbooks/deployment.md`                                            |
| 命名慣例、範本規格、ArgoCD Application range 模式、Cloud SQL / WI 慣例、Secret 現況 | `docs/conventions.md`                                               |
| `.claude/gcp-env.md` 不存在（首次進入本專案）                                 | `runbooks/bootstrap.md`                                             |
| 切換／取消維護模式（GCLB 導轉維護頁）                                        | `runbooks/maintenance-mode.md`                                      |

---

## 初始化 AI 輔助（首次 Bootstrap）

AI 於每次對話開始時，先確認 `.claude/gcp-env.md` 是否存在。**若不存在**，必須先讀取並完成 `runbooks/bootstrap.md` 的流程，才能回應其他操作請求；若存在，跳過本章節，依下方「AI 輔助部署指南」走一般流程。

本流程是黑名單「寫入或修改 `CLAUDE.md`」「寫入或修改 `.claude/` 下任何檔案」的**唯一例外**，且僅限 `runbooks/bootstrap.md` 列出的範圍。流程結束、`.claude/gcp-env.md` 建立完成後，例外即自動失效，後續 session 回到完全黑名單狀態。除此流程外，黑名單其餘規則不受影響。

---

## Secret 安全警示（診斷中）

Secret 管理現況與 release（正式環境）風險見 `docs/conventions.md`「Secret 管理現況」。

AI 在診斷過程中（讀取 log、env var、describe pod 輸出）若發現疑似明碼 secret 時，必須：

1. **立即停止顯示該內容**，以 `[REDACTED]` 替代
2. 向操作者發出警告：

```
⚠️ 疑似明碼 Secret
  發現位置：<log / env var / describe pod>
  欄位名稱：<ConnectionStrings__xxx / JwtSecretKey / ...>

請確認此值是否應以 Kubernetes Secret 或 External Secrets Operator 管理，
而非直接設定在 values 或 ConfigMap 中。
```

3. 詢問是否協助追查來源：「是否要追查這個值是從哪個 values key 或 template 渲染而來？」

---

## GCP 環境資訊

詳見 `.claude/gcp-env.md`——包含所有環境的共用 GCLB External IP、Cloud SQL instance、Cloud NAT、PSC 對接資源。

### AI 使用 gcp-env.md 的原則

AI 診斷時**優先讀取 `.claude/gcp-env.md`** 的快取值。只有在以下情況才重新查詢 GCP：

- 操作者明確要求「重新確認」
- gcp-env.md 的值與現況出現矛盾（例如 GCLB External IP 對不上、backend-service 找不到）

AI 執行任何 kubectl 指令前，須先確認 kubectl config current-context 符合 gcp-env.md 記載的預期值，不符時停止操作並回報。

發現矛盾時，AI 必須立即停止診斷，並以以下格式回報：

```
⚠️ gcp-env.md 資料異常
  快取值：<gcp-env.md 中的值>
  實際值：<查詢到的值>
  影響欄位：<需更新的欄位名稱>

請更新 .claude/gcp-env.md 後開啟新 session，再繼續診斷。
```

### Stale Config 自動偵測

當 AI 連續 2 次嘗試協助完成同一個設定步驟都無法成功時，主動查詢對應的 GCP 資源確認是否有異動：

```bash
gcloud compute backend-services describe <service>-<env>-80 \
  --region asia-east1 --project static-map-242406 --format="yaml(backends,fingerprint)"
gcloud compute url-maps describe <lb|lb-dev|lb-demo> \
  --region asia-east1 --project static-map-242406 --format="yaml(hostRules,pathMatchers)"
```

若查詢結果與 gcp-env.md 快取不符（例如 NEG 對應的 zone 變更、host rule 消失），停止並發出 ⚠️ 警告（同上格式）。

---

## Values 一致性檢查

每個環境的 `values_<env>.yaml` 都是各自完整、獨立的一份設定（見 `docs/conventions.md`「Values 檔案慣例」）。當使用者詢問某個服務在某個環境的設定是否完善時，AI 執行以下流程：

1. 讀取該服務目錄下所有 `values_*.yaml`（例如 `Microservices/Caring/Backend/Api/new-caring-web-api/values_*.yaml`）
2. 逐一比對各檔案的 key 結構（非值本身）是否一致，找出只在部分環境檔案出現、其他環境缺少的 key（可能代表遺漏設定）
3. 搜尋目標環境檔案中是否殘留 `# TODO` 註解（本專案曾出現「需向 XX 團隊取得實際值後填入」這類暫用值註解）
4. 回報：

```
✓ 結構一致的 key：略
✗ 只在部分環境出現的 key：列出 key 名稱與缺少的環境
⚠️ 殘留 TODO 註解：列出檔案與行號、註解內容
```

---

## AI 輔助部署指南

### 操作者設定（必讀）

**AI 在每次對話開始時，必須先執行以下流程，再回應任何操作請求：**

0. 若 `.claude/gcp-env.md` 不存在，先執行 `runbooks/bootstrap.md` 的初始化流程，完成後才繼續下列步驟
1. 讀取 `.claude/OPERATOR.local` 檔案
2. 若檔案存在，取得 `tier` 欄位，並宣告：「目前操作層級：Tier N — <層級名稱>」
3. 若檔案不存在，預設為 **Tier 1 操作者**，並提示操作者可建立 `.claude/OPERATOR.local` 以升級至 Tier 2
4. 若 `OPERATOR.local` 含有 `sa_key_file` 欄位，執行 `gcloud auth activate-service-account --key-file=<path>` 啟用 SA 身份；若無此欄位，沿用系統已登入的 gcloud 帳號
5. Tier 1：`kubectl` 唯讀指令由 AI 直接執行；寫入操作由 AI 提供指令文字，操作者自行執行。Tier 2：黑名單外所有指令均由 AI 直接執行

`.claude/OPERATOR.local` 已加入 `.gitignore`，不會 commit 到 repo。修改此檔案後需開啟新的 session 才會生效——AI 只在每次對話開始時讀取一次。

**建立 `.claude/OPERATOR.local`（一次性操作）：**

```bash
cat > .claude/OPERATOR.local << 'EOF'
tier: 1
# tier: 2  # 升級至 Tier 2 — AI 可直接執行 kubectl 寫入與 gcloud 建立/刪除資源
# sa_key_file: static-map-242406-xxxxxxxxxxxx.json  # 選填：指定 SA 金鑰
EOF
```

### AI 的執行邊界規則

#### 白名單（AI 直接執行）

未列在白名單的指令，AI 一律不執行。

| 動作                                                                          | 條件                                      |
| ----------------------------------------------------------------------------- | ----------------------------------------- |
| `kubectl get / describe / logs / events`（唯讀）                              | 所有 Tier                                 |
| `gcloud ... describe / list / get-*`（唯讀子指令）                            | 所有 Tier，限 `gcp-env.md` 白名單 project |
| `gcloud container clusters get-credentials`                                   | 所有 Tier                                 |
| `gcloud auth activate-service-account --key-file=<path>`                      | 所有 Tier，session 啟動時執行             |
| `git log / status / show / diff`（唯讀，驗證用）                              | 所有 Tier，僅用於確認 commit 與 push 狀態 |
| 本地 manifest / values 檔案編輯（Write/Edit tool）                            | 所有 Tier                                 |
| `kubectl` 寫入類（`rollout restart`、`delete pod`、`create secret`、`scale`） | Tier 2                                    |
| `gcloud` 建立 / 刪除資源（黑名單外，如 `compute`、`sql` 子指令）              | Tier 2                                    |

#### 黑名單（AI 永遠不執行，亦不產出可執行的指令文字）

| 指令類別                                                                               | 原因                                 |
| -------------------------------------------------------------------------------------- | ------------------------------------ |
| `git` 寫入類（`push`/`commit`/`add`/`reset`/`checkout`/`restore`/`clean`/`branch -D`） | 觸發 ArgoCD 部署；唯讀類已列入白名單 |
| `argocd` 任何子指令                                                                    | 直接操控叢集同步與回滾               |
| `gcloud iam` 任何子指令                                                                | IAM 權限變更，影響範圍難以預估       |
| `gcloud projects add-iam-policy-binding / remove-iam-policy-binding`                   | 同上                                 |
| `gcloud iam service-accounts create / delete / disable`                                | 同上                                 |
| 寫入或修改 `CLAUDE.md`                                                                 | AI 不得修改自身的操作規則            |
| 寫入或修改 `.claude/` 下任何檔案                                                       | AI 不得修改自身的配置                |

黑名單限制不受 Tier 影響，Tier 2 操作者亦同。黑名單規則同時在 `.claude/settings.json` 的 `deny` 清單中設定，為技術強制層。

**唯一例外：**`runbooks/bootstrap.md`（初始化 AI 輔助），僅在 `.claude/gcp-env.md` 不存在時觸發，且僅限該 runbook 列出的範圍（校正文件、建立 `.claude/gcp-env.md` 與 `.claude/settings.json`）。流程完成後例外自動失效。

#### 預設（AI 提供指令文字，操作者自行執行，所有 Tier 適用）

黑名單強制封鎖、AI 永遠不直接執行的操作，無論 Tier 均以指令文字提供：

| 動作類別          | 範例                                     |
| ----------------- | ---------------------------------------- |
| `git` 觸發部署    | `git push origin main`、`git commit`     |
| `./Shell/` 執行   | `service_account_binding.sh`             |

> Tier 1 的 `kubectl` 寫入類與 `gcloud` 建立/刪除資源也以指令文字提供（非黑名單，但 Tier 1 不直接執行）。

**GCP Project 限制：** 所有指令只能針對 `.claude/gcp-env.md`「AI 允許查詢的 GCP Projects」表格中的 project 執行。未列出的 project 一律拒絕，不論 Tier。

### 操作者權限層級

#### Tier 1 — 操作者（Operator）

**目標**：診斷問題、建議並實作修復方案（含 manifest 修改）；叢集寫入操作由操作者確認後自行執行。所需 IAM 角色見 `README.md`。

**AI 執行：** 白名單唯讀指令 + 本地 manifest / values 檔案編輯。  
**AI 提供指令文字（操作者自行執行）：**

```bash
kubectl rollout restart deployment/<svc> -n <ns>
kubectl delete pod -l app=<svc> -n <ns>
kubectl create secret generic ... -n <ns>
gcloud compute backend-services create ...
git push origin main
./Shell/service_account_binding.sh
```

---

#### Tier 2 — 部署者（Deployer）

**目標**：同 Tier 1，另可直接驅動叢集操作，不需人工複製貼上；唯 git push 與 scripts 仍由操作者執行（黑名單強制）。所需 IAM 角色見 `README.md`。

**AI 執行：** 同 Tier 1，另加 `kubectl` 寫入類與 `gcloud` 建立/刪除資源（黑名單外所有指令）。  
**AI 提供指令文字（操作者自行執行）：**

```bash
git push origin main                # 黑名單，永遠由操作者執行
./Shell/service_account_binding.sh  # 黑名單，永遠由操作者執行
```

### 對話範例

```
你：   new-caring-mobile-api-dev 一直回 502，幫我查原因。

AI：   （讀取 runbooks/troubleshooting.md，執行唯讀診斷）
       回報根本原因；Tier 1 提供修復指令文字，Tier 2 直接執行 kubectl 重啟。
```

```
你：   將新的 API 服務 "billing-api" 部署到 dev。

AI：   （讀取 runbooks/new-service.md，讀取 runbooks/deployment.md）
       建立 Microservices/Caring/Backend/Api/billing-api/、
       在 Infrastructure/argocd/values.yaml 的 apps.applications 新增 billing-api-dev entry，
       顯示變更摘要，並提供 git push 指令與 Shell/service_account_binding.sh 需補上的綁定行讓操作者執行。
```

```
你：   幫 new-caring-mobile-api 開一個 qat2 環境。

AI：   （讀取 runbooks/new-env.md、runbooks/deployment.md 執行環境升級前置確認）
       確認 Cloud SQL instance、Workload Identity 綁定、GCLB host rule 均已就緒後，
       建立 values_qat2.yaml、在 Infrastructure/argocd/values.yaml 新增對應 Application entry，
       提供 git push 指令並說明預期效果。
```
