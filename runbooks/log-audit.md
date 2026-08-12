# Log Explorer 錯誤／警告巡查

> 大寫佔位符（`<PROJECT_ID>`、`<CLUSTER>`、`<WINDOW>`）對應 `.claude/gcp-env.md` 記載的專案層級固定值，執行前請代入實際值。`<WINDOW>` 未特別指定時預設 `24h`。

目的：巡查 GCP Log Explorer（Cloud Logging）目前有哪些 `ERROR`／`WARNING` severity 的 log 在發生，彙整出主要類型清單回報給操作者；其中屬於 `docs/known-benign-logs.md` 已記載的已知問題，標註「已知不處理」，不重複查證；未列在清單內的新類型，經查證後若判斷不需處理，寫入 `docs/known-benign-logs.md`，避免下次巡查重複調查同一件事。

## 執行原則

- 本流程以 `gcloud logging read`（唯讀）為主，所有 Tier 皆可直接執行；執行前依 `.claude/gcp-env.md` 慣例確認 `--project` 沒打錯，不依賴預設值
- 查詢範圍涵蓋 `.claude/gcp-env.md`「GKE 叢集」表格記載的所有叢集。目前該表只列出 `jcp-cluster`，但「VPC Network」章節提到叢集實際還有 `jcp-tw`——若操作者確認 `jcp-tw` 也在用，一併查詢；這屬於 gcp-env.md 待補值的已知落差，不在本流程內自行更新該檔案
- 分類前，**先完整讀取 `docs/known-benign-logs.md` 全文**，建立比對基準，不要只憑記憶比對
- 未在清單內的新類型，比照 `docs/known-benign-logs.md` 開頭的既有要求——「新增項目前，請先實際查證原因（原始碼、官方文件、或行為重現），不要只憑猜測就列入本表」——不得只憑訊息文字表面猜測就歸類為不需處理
- 查證後若判斷「不需處理」：依 `docs/known-benign-logs.md` 既有格式（元件／Severity／搜尋字串／原因／查證結果／動作／參考）新增一個章節。寫入前先把判斷依據（原因、查證結果）在回覆中呈現給操作者，讓操作者能看到推論過程，不做靜默寫入
- 查證後若判斷「需要處理」：維持用一般方式回報根因與建議修復方向，**不要**寫入 `docs/known-benign-logs.md`——這份文件的性質是「已知可忽略清單」，不是通用 issue tracker
- 無法判斷（查不到足夠依據）時，如實回報「無法確認是否需要處理」，不要為了湊分類勉強下結論；比照文件裡「低風險、暫不處理項目」章節的既有做法，缺乏權威來源時要明確註記

## 執行步驟

### Step 1：整體概況——依 namespace／container／severity 排行

先找出目前 log 量最大的來源，決定接下來要細看哪些地方，而不是一次撈全部訊息內容。

```bash
gcloud logging read '
  resource.type="k8s_container"
  resource.labels.cluster_name="<CLUSTER>"
  severity>=WARNING
' --project=<PROJECT_ID> --freshness=<WINDOW> \
  --format="value(resource.labels.namespace_name, resource.labels.container_name, severity)" \
  --limit=5000 \
  | sort | uniq -c | sort -rn
```

### Step 2：針對排行前面的來源，抓出具代表性的訊息內容

對 Step 1 找出的每個 `namespace_name` + `container_name` 組合，取出訊息內容分組計數，找出「主要類型」（同一類錯誤通常會有固定的 `jsonPayload.msg` / `jsonPayload.message` 或 `textPayload` 開頭字串，即使夾帶的變動內容如 metric 名稱、timestamp 不同）。

```bash
gcloud logging read '
  resource.type="k8s_container"
  resource.labels.cluster_name="<CLUSTER>"
  resource.labels.namespace_name="<NAMESPACE>"
  resource.labels.container_name="<CONTAINER>"
  severity>=WARNING
' --project=<PROJECT_ID> --freshness=<WINDOW> \
  --format="value(jsonPayload.msg, jsonPayload.message, textPayload)" \
  --limit=5000 \
  | sort | uniq -c | sort -rn | head -30
```

訊息裡有變動片段（如 metric 名稱、pod 名稱）導致同一類錯誤被拆成很多筆不同計數時，取樣幾筆完整內容判斷是否為同一根因，不要被表面的字串差異誤導成「很多種不同錯誤」。

### Step 3：比對 `docs/known-benign-logs.md`

對 Step 2 找出的每個主要類型，用元件名稱、container 名稱、訊息關鍵字比對 `docs/known-benign-logs.md` 裡的「搜尋字串」欄位：

- 相符 → 標記「✅ 已知問題，不處理」，附上文件裡對應的章節標題
- 不相符 → 標記「🔍 尚未歸類」，進入 Step 4

### Step 4：針對未歸類的類型逐一查證

依序確認：

1. **這是誰的元件**：本 repo 部署的服務（`charts/*`）、還是 GKE／GCP 系統層級元件（`kube-system` 常見，或帶 `google3` stacktrace）
2. **原始碼／官方文件**：能不能在專案原始碼、官方文件、或已知 issue（如 GitHub issue tracker）找到這個訊息的明確解釋
3. **頻率與分布**：發生頻率是否穩定、是否均勻分散在多個 pod／node（單一 pod 集中出現，通常代表該 pod 有問題，跟「系統性背景雜訊」不同性質）

   ```bash
   gcloud logging read '
     resource.type="k8s_container"
     resource.labels.cluster_name="<CLUSTER>"
     jsonPayload.msg:"<關鍵字>"
   ' --project=<PROJECT_ID> --freshness=<WINDOW> \
     --format="value(resource.labels.pod_name)" --limit=5000 \
     | sort | uniq -c | sort -rn
   ```

4. **實際功能面是否有對應異常**：這個 log 出現的期間，相關功能（如對應服務的健康檢查、autoscaling、網路連線）是否真的出問題，而不是只看 log 本身

依查證結果的確定性，比照 `docs/known-benign-logs.md` 現有兩個分層歸檔：

- 有原始碼／官方文件／直接查證證據（如讀到 DaemonSet spec 確認欄位為 `optional: true`）支持 → 「確認為預期行為」區塊
- 只能靠頻率／影響面判斷、缺乏權威來源 → 「低風險、暫不處理項目」區塊，並在動作欄位註明「純屬自行判斷、缺乏權威來源背書」

若怎麼查都無法判斷是否需要處理，不要硬塞進任一分類，直接回報「無法確認」讓操作者決定。

### Step 5：輸出格式

以清單條列回報，不需要的話不必列出全部「正常」項目：

```
✅ ArgoCD `token does not have jti or uti claim`
   出現 312 次（過去 24h），已知問題（見 known-benign-logs.md「ArgoCD：token does not have jti or uti claim」），不處理

✅ GKE Dataplane V2 `cni-writer` istio-cni-config 檢查
   出現 2,172 次（過去 24h），已知問題，不處理

🔍 [新類型] `notification-worker` container：`Failed to acquire distributed lock: context deadline exceeded`
   過去 24h 出現 47 次，集中在 uat 環境的單一 pod，其他環境未見 —— 查證後判斷：需要處理（疑似 Redis 連線逾時，非背景雜訊），不寫入 known-benign-logs.md，另外回報根因

✍️ [新增至 known-benign-logs.md] GKE 系統元件：`gke-metrics-agent` 週期性 `context canceled`
   過去 7 天穩定出現、均勻分散在全部 node，找到對應 GitHub issue 確認為已知行為，判斷不需處理，已新增至文件「確認為預期行為」章節
```

### Step 6：寫入 `docs/known-benign-logs.md`

比照文件既有格式（見文件最下方「格式慣例」章節），使用 Edit 工具在對應區塊（「確認為預期行為」或「低風險、暫不處理項目」）新增章節，內容至少包含：元件、Severity、搜尋字串、原因、查證結果、動作；有外部參考文件的附上參考連結。寫入後，在回覆裡標明「已記錄到 known-benign-logs.md」，讓操作者知道這筆已經被歸檔，之後巡查會自動命中 Step 3 的比對，不會重複查證。
