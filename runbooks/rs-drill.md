# 還原演練模式（rs）

`rs`（restore drill）是一套獨立於 dev/qat/demo/release 之外的演練環境，用來驗證「把 release 的資料庫備份還原後，服務是否能正常運作」。涉及三個服務——`new-caring-web-api`、`Frontend/Web`（`new-caring-web`）、`new-caring-event-consumer`——各自的 `values_rs.yaml`，以及專用的 Cloud SQL instance `rs`。

> 大寫佔位符對應 `.claude/gcp-env.md` 記載的固定值：`<PROJECT_ID>` = `static-map-242406`、`<REGION>` = `asia-east1`。

## 涉及的資源

| 資源                                       | 現況                                                                                 |
| -------------------------------------------- | -------------------------------------------------------------------------------------- |
| Cloud SQL instance `rs`                     | 已存在（`static-map-242406:asia-east1:rs`），平時不使用，演練時才還原資料進去        |
| `Infrastructure/argocd/values.yaml`         | `apps.applications` 中有 `new-caring-web-api-rs`、`new-caring-web-rs`、`new-caring-event-consumer-rs` 三個 entry，平時整段註解、不生效 |
| `values_rs.yaml`（三個服務各一份）          | 平時存在但未部署，`App.Version` 需在演練前對齊 release 版本                          |
| GCLB backend-service `new-caring-web-api-rs` | 已存在但平時**沒有掛任何 NEG**（`gcloud compute backend-services list` 可見 BACKENDS 為空） |
| GCLB backend-service `new-caring-web-rs`     | 同上，平時沒有掛 NEG                                                                  |
| `new-caring-event-consumer-rs`               | 無 Service/NEG（Event Consumer 類型不對外，見 `docs/conventions.md`）                |

⚠️ **backend-service 名稱與 NEG 名稱不同**：這兩個 backend-service 命名是 `new-caring-web-api-rs` / `new-caring-web-rs`（**沒有** `-80` 結尾，跟其他環境的 `<namespace>-80` 命名不一致），但它們要掛的 NEG 名稱仍是 K8s Service annotation 產生的 `<namespace>-80`，也就是 `new-caring-web-api-rs-80` / `new-caring-web-rs-80`。執行 Phase 4 時務必分清楚這兩者。

對外網域走 `lb-dev` URL Map 的 `rs-urlmatcher`（host rule `*-rs.caringcm.com.tw`），詳見 `.claude/gcp-env.md`「網路入口」與 `runbooks/maintenance-mode.md` 的對照表。

---

## 啟動流程（Phase 1 → 4，嚴格相依，每個 Phase 完成並經操作者確認後才能進入下一個）

### Phase 1 — 還原 Cloud SQL 備份到 `rs` instance

1. 列出 `caring-release-pg` 最新的備份（唯讀，所有 Tier 皆可執行）：

   ```bash
   gcloud sql backups list --instance=caring-release-pg \
     --project static-map-242406 --limit=5 \
     --sort-by="~startTime"
   ```

2. **⚠️ 高風險操作，一律先確認、不可省略：** 這個指令會**完全覆蓋 `rs` instance 現有的所有資料**，不可逆。無論 Tier，AI 必須先列出即將執行的完整指令，並明確告知「此操作會覆蓋 `rs` instance 目前所有資料，且無法復原」，取得操作者明確同意後才能繼續（Tier 2 由 AI 執行；Tier 1 提供指令文字，操作者自行執行）：

   ```bash
   gcloud sql backups restore <BACKUP_ID> \
     --restore-instance=rs \
     --backup-instance=caring-release-pg \
     --project static-map-242406
   ```

3. 還原完成後，**提醒操作者手動處理**（AI 不會、也沒有管道連線資料庫執行 SQL DML，此步驟必須由操作者自行完成）：

   ```
   還原完成後，請手動將 rs 資料庫中對應 Organization 的 Hostname 欄位，
   改成這次演練要用的網域（*-rs.caringcm.com.tw 底下的實際 host，
   見 .claude/gcp-env.md），否則應用程式內部的連結/驗證邏輯會指向錯誤網域。
   ```

4. **操作者明確回覆「Phase 1 已完成」後，才能進入 Phase 2。** 在此之前，即使操作者要求，也不進行 Phase 2 的檔案編輯。

---

### Phase 2 — 反註解 Application 設定並對齊版本號

1. 編輯 `Infrastructure/argocd/values.yaml`，取消「還原演練」區塊三個 entry 的整段註解：`new-caring-web-api-rs`、`new-caring-web-rs`、`new-caring-event-consumer-rs`。

2. 對這三個服務，各自讀取 `values_release.yaml` 目前的 `App.Version`，更新對應的 `values_rs.yaml` 使其一致：

   ```bash
   grep -n "Version:" Microservices/Caring/Backend/Api/new-caring-web-api/values_release.yaml
   grep -n "Version:" Microservices/Caring/Frontend/Web/values_release.yaml
   grep -n "Version:" Microservices/Caring/Event/Consumer/new-caring-event-consumer/values_release.yaml
   ```

   只更新 `App.Version` 這一個欄位，**其餘欄位維持 `values_rs.yaml` 原有的值不變**（尤其 `SqlProxy.InstanceName` 必須維持指向 `rs` instance，絕對不能被誤蓋成 release 的連線設定）。

3. 顯示這次變更摘要（diff），依黑名單規則提供 `git push` 指令文字給操作者執行（AI 永遠不執行 git 寫入類指令）。

4. **操作者確認 push 完成、且 ArgoCD 已看到最新 commit 後，才能進入 Phase 3。**

---

### Phase 3 — 在 ArgoCD 啟動 rs Applications（操作者執行，`argocd` 為黑名單指令）

AI 永遠不執行任何 `argocd` 子指令，一律以指令文字提供：

```bash
argocd app sync new-caring-web-api-rs
argocd app sync new-caring-web-rs
argocd app sync new-caring-event-consumer-rs
```

提醒操作者可用以下唯讀指令確認三個 Application 是否皆已 `Synced`/`Healthy`：

```bash
kubectl -n argocd get application new-caring-web-api-rs new-caring-web-rs new-caring-event-consumer-rs
```

**操作者確認三個 Application 皆已 Synced/Healthy 後，才能進入 Phase 4。**

---

### Phase 4 — 掛載 GCLB backend NEG

1. 唯讀確認 Phase 3 部署出來的 Service 是否已產生對應 NEG，以及目前 backend-service 的掛載狀態：

   ```bash
   kubectl -n new-caring-web-api-rs get service -o jsonpath='{.metadata.annotations}'
   kubectl -n new-caring-web-rs get service -o jsonpath='{.metadata.annotations}'

   gcloud compute backend-services describe new-caring-web-api-rs \
     --region asia-east1 --project static-map-242406 --format="yaml(backends)"
   gcloud compute backend-services describe new-caring-web-rs \
     --region asia-east1 --project static-map-242406 --format="yaml(backends)"
   ```

2. **不論 Tier，執行前一律先列出即將執行的完整指令，並明確詢問操作者是否要執行**（與 `runbooks/maintenance-mode.md` 相同的確認機制），取得同意後：Tier 2 由 AI 直接執行；Tier 1 提供指令文字，操作者自行執行。

   ```bash
   for zone in a b c; do
     gcloud compute backend-services add-backend new-caring-web-api-rs \
       --network-endpoint-group=new-caring-web-api-rs-80 \
       --network-endpoint-group-zone=asia-east1-$zone \
       --balancing-mode=RATE --max-rate-per-endpoint=100 \
       --region=asia-east1 --project static-map-242406
   done

   for zone in a b c; do
     gcloud compute backend-services add-backend new-caring-web-rs \
       --network-endpoint-group=new-caring-web-rs-80 \
       --network-endpoint-group-zone=asia-east1-$zone \
       --balancing-mode=RATE --max-rate-per-endpoint=100 \
       --region=asia-east1 --project static-map-242406
   done
   ```

3. 驗證（唯讀）：

   ```bash
   curl -sI https://<*-rs.caringcm.com.tw 底下的實際 host>/
   ```

4. 回報操作者還原演練環境已就緒。

---

## 關閉流程（無嚴格相依性，逐項還原/刪除即可，順序不拘）

- **還原 Phase 4**：移除掛上的 NEG（是否要保留 backend-service 空殼待下次演練，或連 backend-service 一併刪除，需向操作者確認）：

  ```bash
  for zone in a b c; do
    gcloud compute backend-services remove-backend new-caring-web-api-rs \
      --network-endpoint-group=new-caring-web-api-rs-80 \
      --network-endpoint-group-zone=asia-east1-$zone \
      --region=asia-east1 --project static-map-242406
  done
  # new-caring-web-rs 同樣處理
  ```

- **還原 Phase 3**：提醒操作者在 ArgoCD 手動刪除三個 rs Application（純粹把 `Infrastructure/argocd/values.yaml` 的 entry 註解回去，並不會自動清除叢集內已建立的資源，必須操作者手動 `argocd app delete` 才會真正移除）：

  ```bash
  argocd app delete new-caring-web-api-rs
  argocd app delete new-caring-web-rs
  argocd app delete new-caring-event-consumer-rs
  ```

- **還原 Phase 2**：把 `Infrastructure/argocd/values.yaml` 「還原演練」區塊三個 entry 重新註解回去，提供 `git push` 指令文字給操作者執行。

- **還原 Phase 1**：`rs` instance 的資料可以保留到下次演練直接覆蓋，不強制清除；是否要清空或停用由操作者自行決定，AI 不主動建議刪除 Cloud SQL instance。

- **若曾因「疑難排除」章節臨時調整過 `new-caring-web-page` 的 dev 版本**：務必依該章節步驟切回原始版本，否則真實 dev 環境會停留在被臨時切換過去的版本。

---

## 中斷後恢復

若不確定目前演練進行到哪個 Phase：

```bash
echo "--- Phase 1：rs instance 是否有資料 ---"
gcloud sql operations list --instance=rs --project static-map-242406 --limit=3

echo "--- Phase 2：Application entry 是否已反註解、版本是否對齊 ---"
grep -n "new-caring-web-api-rs:\|new-caring-web-rs:\|new-caring-event-consumer-rs:" Infrastructure/argocd/values.yaml

echo "--- Phase 3：ArgoCD Application 狀態 ---"
kubectl -n argocd get application new-caring-web-api-rs new-caring-web-rs new-caring-event-consumer-rs 2>&1

echo "--- Phase 4：backend-service 是否已掛 NEG ---"
gcloud compute backend-services describe new-caring-web-api-rs \
  --region asia-east1 --project static-map-242406 --format="yaml(backends)"
```

| 診斷結果                                             | 代表已完成到 | 下一步  |
| ------------------------------------------------------ | ------------ | ------- |
| `Infrastructure/argocd/values.yaml` 的 entry 仍是註解狀態 | 尚未開始     | Phase 1 |
| entry 已反註解，ArgoCD Application 不存在或 OutOfSync   | Phase 2      | Phase 3 |
| Application 皆 Synced/Healthy，backend-service 無 NEG   | Phase 3      | Phase 4 |
| backend-service 已掛 NEG                                | Phase 4      | 演練環境已就緒 |

---

## 疑難排除

### 還原完成後，前端行為異常

`new-caring-web-page` **沒有** `values_rs.yaml`，`rs-urlmatcher` 的 `web-page` 路由規則導向的是**與真實 dev 環境共用**的 `new-caring-web-page-dev-80`（見 Phase 2 反查結果；此服務不在 rs 的三個服務清單內）。若還原測試時前端出現與預期不符的行為，很可能是這個共用的 dev 版本 web-page，跟已切齊 release 版本的 web-api／資料庫之間版本不一致所致。

**處理方式：**

1. 記下 `new-caring-web-page` 目前在 dev 環境的版本（結束演練後要切回，務必先記錄）：

   ```bash
   grep -n "Version:" Microservices/Caring/Frontend/Page/new-caring-web-page/values_dev.yaml
   ```

2. ⚠️ **這個改動會影響真實的 dev 環境，不是獨立於 rs 之外的變更**——`new-caring-web-page-dev` 這個 Application 平時就在服務真正的 dev 流量，調整期間會讓 dev 環境的前端版本暫時跟著改變。執行前必須向操作者說明此風險並取得明確同意，不可逕自進行。

3. 取得同意後，把 `values_dev.yaml` 的 `App.Version` 對齊 `values_release.yaml` 目前的版本：

   ```bash
   grep -n "Version:" Microservices/Caring/Frontend/Page/new-caring-web-page/values_release.yaml
   ```

   顯示 diff，依黑名單規則提供 `git push` 指令文字給操作者執行（AI 永遠不執行 git 寫入類指令）。

4. 提醒操作者在 ArgoCD 手動 sync 既有的 `new-caring-web-page-dev` Application。

5. 重新測試 rs 環境的前端行為。

6. **結束還原演練時，務必把 `values_dev.yaml` 的 `App.Version` 切回步驟 1 記錄的原始版本**，同樣走「顯示 diff → 提供 git push 指令文字 → 提醒操作者 ArgoCD sync」流程（見「關閉流程」對應提醒），否則真實 dev 環境會停留在被臨時切換過去的版本。
