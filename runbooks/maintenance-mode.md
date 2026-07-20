**[Manifest 專屬]**

# 維護模式切換（GCLB 導轉維護頁）

透過修改共用 GCLB 的 URL Map，把某個網域的所有流量（`priority: 0` 的 catch-all route rule）導向 `maintenance-page-80`（`maintenance-page-proxy` 服務），達到「維護模式」效果；取消時移除該筆規則，流量恢復正常路由。這是**手動 GCP 網路操作**，不透過 ArgoCD 同步，也不在任何 Helm chart 範圍內。

> 大寫佔位符對應 `.claude/gcp-env.md` 記載的固定值：`<PROJECT_ID>` = `static-map-242406`、`<REGION>` = `asia-east1`。

## 目標代號 → URL Map / pathMatcher 對照

操作者下指令時通常只講代號（例如「dev1」「release」），不會直接講 URL Map 或 pathMatcher 名稱。AI 收到指令後，**只在 `caringcm.com.tw` 這個網域下比對**（忽略 `jubo.health`、`*.internal` 等其他網域的 host rule），依下表換算成實際要修改的 URL Map 與 pathMatcher：

### `lb-dev`（dev/qat 系列）

| 操作者代號  | Host                            | pathMatcher       |
| ------------ | -------------------------------- | ------------------- |
| `dev1`      | `upgrade-dev-01.caringcm.com.tw` | `dev3-urlmatcher`  |
| `dev3`      | `upgrade-dev-03.caringcm.com.tw` | `dev3-urlmatcher`  |
| `dev2`      | `upgrade-dev-02.caringcm.com.tw` | `dev2-urlmatcher`  |
| `dev4`      | `upgrade-dev-04.caringcm.com.tw` | `dev2-urlmatcher`  |
| `qat1`      | `upgrade-qat-01.caringcm.com.tw` | `qat-urlmatcher`   |
| `qat2`      | `upgrade-qat-02.caringcm.com.tw` | `qat2-urlmatcher`  |
| `qat3`      | `upgrade-qat-03.caringcm.com.tw` | `qat2-urlmatcher`  |
| `qat4`      | `upgrade-qat-04.caringcm.com.tw` | `qat2-urlmatcher`  |
| `rs`        | `*-rs.caringcm.com.tw`           | `rs-urlmatcher`     |

⚠️ **`dev1`/`dev3` 共用同一個 `dev3-urlmatcher`；`dev2`/`dev4` 共用 `dev2-urlmatcher`；`qat2`/`qat3`/`qat4` 共用 `qat2-urlmatcher`。** 修改其中一個代號的 pathMatcher 會**同時影響同組的其他代號**。執行前必須向操作者明確列出這次會被一併影響的其他代號，取得確認後才繼續。

### `lb`（release / production）

| 操作者代號              | Host                                    | pathMatcher            |
| ------------------------- | ----------------------------------------- | ------------------------ |
| `release` / `production` | `*.caringcm.com.tw`（wildcard，主要網站） | `urlmatcher`            |
| `release` 的 sso 網域    | `sso-release.caringcm.com.tw`             | `sso-release-urlmatcher` |

操作者只講「release」或「production」時，預設指 `*.caringcm.com.tw` 這組 wildcard 規則（`urlmatcher` pathMatcher），不要動 `sso-release-urlmatcher` 或 `release-mobile-urlmatcher`，除非操作者特別提到 sso 或 mobile-api。

### `lb-demo`（demo）

| 操作者代號 | Host（示例）                                                                                        | pathMatcher       |
| ----------- | ------------------------------------------------------------------------------------------------------ | -------------------- |
| `demo`     | `sso-demo`、`mgmt`、`mgmtsmc`、`mgmttest`、`dctest`、`erstest`、`mini-test`、`sjtest`、`test`、`test00`（皆為 `*.caringcm.com.tw`） | `demo-urlmatcher`   |

`demo-urlmatcher` 同時服務上述所有 demo 相關網域，修改前同樣要向操作者列出會被一併影響的網域。

若操作者提到的代號不在上述任何一列，**先執行下方「查詢目前 host rule」指令確認**，不要臆測 pathMatcher 名稱。

---

## 查詢目前 host rule（唯讀，所有 Tier 皆可執行）

```bash
gcloud compute url-maps describe <lb|lb-dev|lb-demo> \
  --region asia-east1 --project static-map-242406 \
  --format="yaml(hostRules,pathMatchers)"
```

從輸出確認：目標 pathMatcher 目前的 `routeRules` 有哪些、priority 排序、是否已存在 `description: maintenance`（service 為 `maintenance-page-80`）的規則（可能是先前切換維護模式後遺留、priority 較大而處於未生效狀態的規則）。

---

## 啟用維護模式

1. 依對照表（或查詢結果）確定目標 URL Map 與 pathMatcher，並向操作者確認會被一併影響的其他代號（見上方⚠️）。

2. Export 該 URL Map 為本機檔案，並保留一份原始備份供之後 diff 使用（皆唯讀）：

   ```bash
   gcloud compute url-maps export <lb|lb-dev|lb-demo> \
     --region asia-east1 --project static-map-242406 \
     --destination=/tmp/<urlmap>.yaml
   cp /tmp/<urlmap>.yaml /tmp/<urlmap>.before.yaml
   ```

3. 編輯 `/tmp/<urlmap>.yaml`，找到目標 pathMatcher 的 `routeRules`：

   - 若已存在 `description: maintenance` 的規則 → 把它的 `priority` 改成 `0`。
   - 若不存在 → 在 `routeRules` 陣列中新增一筆：

     ```yaml
     - description: maintenance
       matchRules:
         - pathTemplateMatch: /**
       priority: 0
       service: https://www.googleapis.com/compute/v1/projects/static-map-242406/regions/asia-east1/backendServices/maintenance-page-80
     ```

   - **`priority: 0` 是全域最高優先權**（數字越小越先比對），本專案目前所有 pathMatcher 現有規則的 priority 皆從 `1` 起算，所以插入 `0` 不會與既有規則衝突。
   - 調整完後，確認整個 `routeRules` 陣列依 `priority` 由小到大排序（GCP 依 priority 數值比對、不依陣列順序，但本專案既有規則皆維持陣列順序與 priority 排序一致，維持此慣例以利閱讀與避免誤判）。

4. **不論 Tier，執行 import 前一律要先產生並列出以下內容給操作者看，取得明確同意後才能執行——這一步不因 Tier 2 而省略：**

   - 變更內容（diff）：

     ```bash
     diff -u /tmp/<urlmap>.before.yaml /tmp/<urlmap>.yaml
     ```

   - 即將執行的完整指令文字：

     ```bash
     gcloud compute url-maps import <lb|lb-dev|lb-demo> \
       --region asia-east1 --project static-map-242406 \
       --source=/tmp/<urlmap>.yaml
     ```

   - 明確詢問操作者，例如：「以上變更會讓 `<目標網域>`（含 `<列出所有共用同一 pathMatcher 的其他代號，若無則省略>`）全部導向維護頁，是否要執行？」並提供「執行」／「不執行」兩個選項。

   只有在操作者明確回覆同意後才能繼續：Tier 2 由 AI 直接執行該指令；Tier 1 由 AI 提供指令文字，操作者自行執行。操作者未回覆或回覆不執行時，停止流程，不進行 import，維持目前狀態。

5. 驗證（唯讀）：

   ```bash
   curl -sI https://<目標網域>/
   ```

   確認回應內容/來源已變成維護頁（`maintenance-page-proxy` 反代的 GCS 頁面）。

6. 回報操作者維護模式已啟用，並提醒稍後需執行「取消維護模式」還原，否則該網域（含所有共用同一 pathMatcher 的代號）會持續顯示維護頁。

---

## 取消維護模式

1. 依對照表確定目標 URL Map 與 pathMatcher。

2. Export 該 URL Map，並保留一份原始備份供之後 diff 使用（皆唯讀）：

   ```bash
   gcloud compute url-maps export <lb|lb-dev|lb-demo> \
     --region asia-east1 --project static-map-242406 \
     --destination=/tmp/<urlmap>.yaml
   cp /tmp/<urlmap>.yaml /tmp/<urlmap>.before.yaml
   ```

3. 編輯 `/tmp/<urlmap>.yaml`，在目標 pathMatcher 的 `routeRules` 中找到 `priority: 0` 且 `description: maintenance`（service 為 `maintenance-page-80`）的規則，**刪除整筆規則**，恢復成啟用維護模式前的路由設定。

4. **不論 Tier，執行 import 前一律要先產生並列出以下內容給操作者看，取得明確同意後才能執行——這一步不因 Tier 2 而省略：**

   - 變更內容（diff）：

     ```bash
     diff -u /tmp/<urlmap>.before.yaml /tmp/<urlmap>.yaml
     ```

   - 即將執行的完整指令文字：

     ```bash
     gcloud compute url-maps import <lb|lb-dev|lb-demo> \
       --region asia-east1 --project static-map-242406 \
       --source=/tmp/<urlmap>.yaml
     ```

   - 明確詢問操作者，例如：「以上變更會讓 `<目標網域>` 恢復正常路由（不再導向維護頁），是否要執行？」並提供「執行」／「不執行」兩個選項。

   只有在操作者明確回覆同意後才能繼續：Tier 2 由 AI 直接執行該指令；Tier 1 由 AI 提供指令文字，操作者自行執行。操作者未回覆或回覆不執行時，停止流程，不進行 import，維持目前狀態。

5. 驗證（唯讀）：

   ```bash
   curl -sI https://<目標網域>/
   ```

   確認已恢復回正常服務（不再是維護頁回應）。

6. 回報操作者維護模式已取消。

---

## 中斷後恢復 / 快速確認目前狀態

若不確定某個代號目前是否處於維護模式：

```bash
gcloud compute url-maps describe <對應的 lb|lb-dev|lb-demo> \
  --region asia-east1 --project static-map-242406 \
  --format="yaml(pathMatchers[].routeRules)" \
  | grep -B3 "maintenance-page-80"
```

若找到的該筆規則 `priority` 為 `0` → 目前為維護模式中；若 priority 較大（例如既有的遺留規則）或找不到該筆規則 → 目前為正常模式。
