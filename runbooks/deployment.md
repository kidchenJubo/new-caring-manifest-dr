# 部署程序

## 部署流程（端到端）

```
操作者告知 AI → AI 編輯 manifest（所有 Tier）
      ↓
AI 執行部署前安全檢查（見下方）
      ↓
AI 提供 git push 指令文字 → 操作者執行
      ↓
操作者在 ArgoCD 手動觸發同步（本專案所有 Application 皆為手動 sync，無 automated）
      ↓
ArgoCD 將 Helm chart 套用至 GKE 叢集
      ↓
GKE 以 Cloud SQL Proxy native sidecar（initContainer）部署新 pod（若該服務連 DB）
      ↓
Service 的 cloud.google.com/neg annotation 更新既有 NEG
      ↓
服務上線：透過既有共用 GCLB 對外（網域見 .claude/gcp-env.md「網路入口」表格）
```

---

## 部署前安全檢查

在提供 `git push` 指令文字前，AI **必須**依序完成以下三項檢查，任一失敗則停止並告知操作者。

### 1. Values 一致性確認

執行 Values 一致性檢查（見 `CLAUDE.md`），確認目標環境的 `values_<env>.yaml` 與同服務其他環境的 key 結構一致，且沒有殘留 `# TODO` 註解代表的暫用值。

若有殘留 TODO 或結構缺漏 → 停止，列出問題並提示操作者確認是否要用暫用值繼續，或先補齊。

### 2. 網路可用性確認（僅新環境/新服務對外時需要）

若這次變更會讓一個**先前未對外**的服務/環境開始接對外流量，讀取 `.claude/gcp-env.md`「網路入口」表格確認對應的 backend-service 與 GCLB host rule 是否已存在：

- 若尚未建立 → 停止，回應：

  ```
  ⚠️ <service>-<env>-80 尚未在共用 GCLB 建立 backend-service / host rule
  請先完成 runbooks/new-env.md 或 runbooks/new-service.md 的網路入口步驟，
  否則 ArgoCD 同步後服務會就緒但無法從外部存取。
  ```

- 若已存在 → 通過，繼續下一步。純內部服務（Event Consumer、Scheduler）沒有 Service/對外流量，跳過此項。

### 3. 變更摘要輸出

在提供 `git push` 指令前輸出本次變更摘要：

```
本次變更摘要：
  修改的檔案：
    - Microservices/Caring/<Layer>/<service>/values_<env>.yaml：更新 <key> = <value>
    - Infrastructure/argocd/values.yaml：新增/修改 <destinationNamespace> entry（若有）
  預期效果：
    - 操作者手動觸發 ArgoCD 同步後將部署/更新 <destinationNamespace>
    - 服務上線後可透過 <domain> 存取（若對外）
  操作者確認的前提：
    - Workload Identity 綁定已完成（./Shell/service_account_binding.sh）
    - Cloud SQL instance 連線名稱正確（若連 DB）
確定要繼續執行 git push 嗎？
```

### 4. 部署後驗證

操作者執行 git push 後，AI 確認 commit 已到達 Git：

```bash
git log --oneline -3   # 確認最新 commit hash
git status             # 確認無 uncommitted changes
```

接著提示操作者手動觸發同步（ArgoCD UI，或若已安裝 ArgoCD CLI 且已登入 `https://new-caring-argocd.jubo.health`）：

```bash
argocd app sync <destinationNamespace>
```

---

## 環境升級前置確認

在 `Infrastructure/argocd/values.yaml` 新增一個服務的新環境 entry 前，AI 確認以下項目均已完成：

| 項目                    | 確認方式                                                                          |
| ------------------------ | ------------------------------------------------------------------------------------ |
| Cloud SQL instance       | 對照 `.claude/gcp-env.md`「Cloud SQL」表格確認 instance connection name（若服務連 DB） |
| Values 一致性            | 執行 Values 一致性檢查，無殘留 TODO 佔位值                                          |
| Workload Identity 綁定   | 確認 `Shell/service_account_binding.sh` 已補上該 namespace 的兩行並執行過            |
| GCLB backend-service     | 若對外，確認 backend-service 與 host rule 已建立（見上方「網路可用性確認」）        |

任一項目未完成 → 停止並列出缺少的項目，不進行 YAML 編輯。

---

## 在 ArgoCD 啟用自動同步

本專案目前 `Infrastructure/argocd/values.yaml` 的 `apps.applications` 中**沒有任何 entry** 設定 `syncPolicy.automated`，所有 Application 皆為手動 sync。要為某個服務啟用自動同步，在該 entry 加入：

```yaml
apps:
  applications:
    <destinationNamespace>:
      sourcePath: Microservices/Caring/<Layer>/<service>
      sourceHelm:
        valueFiles:
          - values_<env>.yaml
      destinationNamespace: <destinationNamespace>
      syncPolicy:
        automated:
          enabled: true
          prune: true # 移除從 Git 刪除的資源
          selfHeal: true # 還原手動 kubectl 修改
```

`templates/applications.yaml` 用 `dig "syncPolicy" "automated" "enabled" false $appData` 判斷是否渲染 `automated` 區塊，所以只要沒加 `enabled: true`，即使有其他 syncPolicy 欄位也不會自動同步。設定後，每次 `git push` 到 `main` 都會讓 ArgoCD 自動套用該 Application 的變更。

---

## 回滾

```bash
# 列出服務的部署歷史
argocd app history ${DESTINATION_NAMESPACE}

# 回滾至指定版本（操作者執行）
argocd app rollback ${DESTINATION_NAMESPACE} <revision-id>
```

`${DESTINATION_NAMESPACE}` 即 `Infrastructure/argocd/values.yaml` 中 `apps.applications` 的 key（同時也是 ArgoCD Application 名稱），例如 `new-caring-web-api-dev`。
