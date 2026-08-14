# 已知可忽略的 Log / 告警清單

本文件記錄在 Log Explorer 裡看起來像異常（`ERROR`/`WARNING` severity），但實際上是預期行為、不需要處理的 log pattern。目的是避免重複花時間追查同一批已知無害的訊息。

新增項目前，請先實際查證原因（原始碼、官方文件、或行為重現），不要只憑猜測就列入本表。

> 本文件部分項目最初是在 `jubo-care-platform` 專案的 `jcp-cluster` 查證，2026-08-12 已針對本專案的 `static-map-242406` / `caring-tw` 重新查證一輪（見各節「查證結果（`caring-tw`）」），發現有 2 項因為架構差異（本叢集未部署 GKE Dataplane V2）不適用，1 項因為未使用 GKE Ingress 資源而不會觸發，1 項目前未觀察到（但架構上理由仍可能適用），1 項確認同樣發生。往後在本專案巡查，請以標註 `caring-tw` 的查證結果為準。

---

## ArgoCD：`token does not have jti or uti claim`

| 項目     | 內容                                                                     |
| -------- | ------------------------------------------------------------------------ |
| 元件     | `argocd-server`（namespace: `argocd`）                                   |
| Severity | `WARNING`                                                                 |
| 搜尋字串 | `jsonPayload.msg:"token does not have jti"`                              |

**原因：** ArgoCD 驗證 session token 時會嘗試取出 `jti`（JWT ID）claim 做 token 追蹤/撤銷用。這個專案的 SSO 走 Dex + Microsoft Entra ID connector，**Microsoft 簽發的 token 本來就不包含 `jti`**，屬於 IdP 行為差異，不是設定錯誤。

ArgoCD 原始碼本身就預期這個情況並有處理：

```go
// util/session/sessionmanager.go
id := tokenUniqueID(claims)
if id == "" {
    log.Warnf("token does not have jti or uti claim")
}
// Workaround for Dex token, because does not have jti.
if id == "" {
    id = idToken.AccessTokenHash
}
```

`jti` 缺失時會自動改用 `AccessTokenHash` 當替代識別碼，不影響 session 驗證或安全性。次數多寡單純反映 ArgoCD 使用量（每次 session 驗證都會觸發一次檢查），不是異常累積。

**動作：** 不需處理。無法透過這個 repo 的設定消除，除非更換不透過 Dex 或會簽發 `jti` 的 IdP（沒有必要為此更換身份驗證架構）。

**查證結果（2026-08-12，`caring-tw`，`static-map-242406`）：** 本專案的 `new-caring-argocd` 同樣走 Dex + Microsoft Entra ID，架構上理由同樣適用。但實際查詢 `argocd` namespace 的 `server` container（過去 30 天），**完全沒有出現過這則警告**，即使同期間有大量 `session.SessionService/GetUserInfo` 呼叫（代表有人持續在用 ArgoCD UI）。原因未明——可能是這個環境的 Microsoft App Registration 設定剛好有回傳 `uti` claim、或版本行為差異——單純記錄「目前沒觀察到」，不代表以後不會出現；若之後真的看到這則警告，上面的原因說明依然成立，不需要重新查證原因，只需要更新這一段的出現頻率。

**參考：** [argo-cd/util/session/sessionmanager.go](https://github.com/argoproj/argo-cd/blob/master/util/session/sessionmanager.go)

---

## GKE Ingress：`k8s-ingress-svc-acct-permission-check-probe` not found

| 項目     | 內容                                                                          |
| -------- | ----------------------------------------------------------------------------- |
| 元件     | GKE Ingress controller（GKE 系統層級，非本 repo 部署的任何服務）              |
| 適用範圍 | 所有 GKE 專案通用行為，不限於 `jubo-care-platform`                            |
| 搜尋字串 | `k8s-ingress-svc-acct-permission-check-probe`                                 |

**原因：** GKE 的 Ingress controller 會定期對一個**刻意不存在**的全域 BackendService（名稱固定為 `k8s-ingress-svc-acct-permission-check-probe`）發送 GET 請求，用來驗證目前的 service account 是否具備正確的 GCP API 呼叫權限。

- 預期結果是 **"not found"**（404 類型錯誤）——這代表 API 呼叫本身有通過身分驗證，只是資源真的不存在，是健康的訊號
- 如果收到的是 **permission denied（403）**，才代表真正的權限問題，需要處理
- ⚠️ 如果專案裡真的建立了一個叫這個名字的 BackendService，這個健康檢查機制反而會失效（GET 會成功而不是回 not found）——不要用這個名稱建立任何實際資源

**動作：** 不需處理，這是 Google 官方文件記載的正常探測機制。

**查證結果（2026-08-12，`caring-tw`，`static-map-242406`）：** 查詢過去 7 天，專案內完全找不到這則訊息（`grep` 不到任何一筆）。這與本專案的網路入口機制有關——`caring-tw` 沒有使用任何 `kind: Ingress` 資源（對外流量走手動管理的 GCLB backend-service + NEG，見 `docs/conventions.md`「網路入口」），GKE 的 GCE Ingress controller 沒有東西可管理，因此不會觸發這個探測週期。**不是「訊息消失了」，是這個機制在本專案的架構下本來就不會啟動**，跟原本「所有 GKE 專案通用行為」的說法不衝突（controller 本身通用存在，但只有在實際管理 Ingress 資源時才會定期探測）。

**參考：** [Troubleshoot GKE Ingress | Google Cloud Documentation](https://docs.cloud.google.com/kubernetes-engine/docs/troubleshooting/ingress)

---

## GKE Dataplane V2：`cni-writer`：`Key file "cni_network_config" not found in ConfigMap mount path "/istio-cni-config"`

| 項目     | 內容                                                                          |
| -------- | ----------------------------------------------------------------------------- |
| 元件     | `cni-writer`（`anetd` pod，namespace: `kube-system`，GKE Dataplane V2 系統層級） |
| Severity | `WARNING`                                                                     |
| 搜尋字串 | `jsonPayload.message:"istio-cni-config"`                                     |

**原因：** `anetd` DaemonSet 本身固定掛載了一個名為 `istio-cni-plugin-config` 的 ConfigMap（volume 名稱 `istio-cni-plugin-config-vol`，掛載路徑 `/istio-cni-config`），用途是若叢集有安裝 Anthos Service Mesh / Istio，就把它的 CNI 設定合併進 Cilium 的 CNI conf 檔。這個掛載在 DaemonSet spec 裡明確標示：

```yaml
- configMap:
    name: istio-cni-plugin-config
    optional: true
  name: istio-cni-plugin-config-vol
```

`optional: true` 代表 ConfigMap 不存在時 Pod 仍能正常啟動，掛載路徑只是空的。`cni-writer` 會週期性地去讀取這個路徑檢查有沒有 Istio CNI 設定，讀不到就記一筆 WARNING，是內建的 no-op 檢查，跟叢集是否真的安裝 Istio 無關。

**已查證（2026-08-11，`jcp-cluster`）：**
- 叢集內沒有 `istio-system` namespace、沒有任何 istio 相關 pod、`kube-system` 也沒有 `istio-cni-config` ConfigMap ——確認**沒有人開啟 Istio**，純粹是 anetd 內建行為
- 過去 24 小時在 6 個 `anetd` pod 上總共出現 2,172 次（每個 pod 約 283~440 次），頻率規律、均勻分散，推測是 `cni-writer` 每隔約 3~4 分鐘做一次週期性檢查，非單次啟動才觸發
- `anetd` DaemonSet 標記 `addonmanager.kubernetes.io/mode: Reconcile`：GKE addon-manager 會定期把這個物件拉回控制平面標準版本，手動 `kubectl edit`/`patch` 移除這個掛載通常幾分鐘內會被自動改回，無法持久生效；且 `anetd` 是全 node 跑的 DaemonSet，負責 Pod 網路/NetworkPolicy/Service 轉發，貿然修改風險（整叢集網路中斷）遠大於消除這則 WARNING 的效益

**動作：** 不需處理，且**不建議嘗試移除或 override 這個掛載**——非 GitOps 管轄範圍、GKE 會自動 reconcile 改回、且風險遠高於效益。

**⚠️ 不適用於 `caring-tw`（`static-map-242406`）：** 查證（2026-08-12）發現這個叢集**完全沒有部署 GKE Dataplane V2**——`kubectl -n kube-system get ds anetd` 回報 `NotFound`，`gcloud container clusters describe caring-tw --format="yaml(networkConfig)"` 也沒有 `datapathProvider: DATAPATH_PROVIDER_V2` 欄位，代表這個叢集走的是舊版 dataplane，根本沒有 `anetd` pod 存在。這個 log pattern 完全依附在 `anetd` 元件上，**沒有 anetd 就不可能出現這則 log**，不是「查過沒發現」，是架構上不可能發生。保留這節是為了將來若叢集升級啟用 Dataplane V2，這裡的判斷依據仍然有效；在那之前，本專案的巡查不需要為這個 pattern 花時間查證。

**參考：** [addon-manager Reconcile 模式說明（kubernetes/kubernetes）](https://github.com/kubernetes/kubernetes/blob/master/cluster/addons/addon-manager/README.md)（`istio-cni-plugin-config` 的 `optional: true` 掛載設定為 `jcp-cluster` 的 `anetd` DaemonSet spec 直接查證所得，非外部文件記載）

---

# 低風險、暫不處理項目

以下項目**沒有官方文件或原始碼確認**是預期行為，只是經過查證頻率/影響範圍後，判斷目前風險低、不列為優先處理。跟上面「確認為預期行為」的項目性質不同，日後若情況改變（例如頻率明顯上升、或觀察到實際功能異常）應該重新評估，不能當作永久性的免死金牌。

## GKE 系統元件：`Error exporting metrics to UAS`（`reading from stream failed: EOF`）

| 項目     | 內容                                                                          |
| -------- | ----------------------------------------------------------------------------- |
| 元件     | `autoscaling-metrics-exporter`（`gke-metrics-agent` pod，namespace: `kube-system`，GKE 系統層級） |
| Severity | `ERROR`（訊息本身標記為 `error`，不是 stdout/stderr 誤判的情況）              |
| 搜尋字串 | `textPayload:"Error exporting metrics to UAS"`                                |

**查證結果（2026-08-11，`jcp-cluster`）：**
- 過去 24 小時 214 次、過去 7 天 1,478 次，平均每天 ~211 次，速率穩定
- 平均分散在全部 6 台 node 上（30~42 次/台），沒有集中在特定 node
- 沒有找到 Google 官方文件說明這個頻率算不算正常
- 目前沒有觀察到對應的實際功能異常（autoscaling 該加減 node 的判斷、HPA 等都正常運作）

**判斷：** 這是 Google 完全內部管理的元件（`uasexporter`，用於 autoscaling 用量計量回報），錯誤本身是串流連線被對端關閉（EOF），加上均勻分散、長期穩定的模式，比較像是這個元件本身的背景雜訊，不像是這個叢集特有的網路/設定問題。但**沒有權威來源背書**，純粹是我們自己的判斷。

**動作：** 暫不處理。若想要確定答案，需要開 Google Cloud Support case 詢問。若之後發現 autoscaling 實際運作異常（該 scale 沒 scale），應優先懷疑並重新查證這個錯誤。

**查證結果（2026-08-12，`caring-tw`，`static-map-242406`）：** 確認同樣發生。過去 24 小時共 352 次，平均分散在全部 5 個 `gke-metrics-agent` pod（70~71 次/pod），跟 `jcp-cluster` 觀察到的「均勻分散、頻率穩定」模式一致。判斷維持不變：暫不處理。

---

## GKE 系統元件：`Failed to process parsed line`（`cilium_agent_bootstrap_seconds is not configured in descriptors`）

| 項目     | 內容                                                                          |
| -------- | ----------------------------------------------------------------------------- |
| 元件     | `cilium-agent-metrics-collector`（`anetd` pod，namespace: `kube-system`，GKE Dataplane V2 系統層級） |
| Severity | `ERROR`（訊息本身標記為 `error`，不是 stdout/stderr 誤判的情況）              |
| 搜尋字串 | `jsonPayload.msg:"Failed to process parsed line" jsonPayload.metric="cilium_agent_bootstrap_seconds"` |

**原因（推測，未經官方文件證實）：** stacktrace 顯示這是 GKE 內部的 `google3/cloud/kubernetes/metrics/components/collector/prometheus` 元件，負責從 Cilium agent 本機的 `:9990/metrics` scrape Prometheus 格式的 metrics，再轉送到 Google 內部遙測管線。這個 collector 內部維護一份固定的 metric descriptor（允許清單），只轉送清單內認得的 metric；`cilium_agent_bootstrap_seconds`（Cilium agent 啟動耗時，只在啟動當下產生一次）不在這份清單內，導致該行被丟棄並記一筆 ERROR，但同一次 scrape 其他有在清單內的 metric 不受影響。

**判斷：** 跟上方「Error exporting metrics to UAS」性質相同——都是 Google 內部 metrics pipeline 因為 producer（Cilium/anetd）曝露的 metric 跟 consumer（GKE collector 的固定 descriptor 清單）沒有同步收錄所致的背景雜訊，不是這個 repo 或叢集設定造成，也無法透過 manifest 調整。

**查證結果（2026-08-11，`jcp-cluster`）：**
- 過去 24 小時共 146 次，均勻分散在全部 6 個 `anetd` pod（18~30 次/pod），沒有集中特定 node
- 過去 7 天觸發的 metric 名稱只有 `cilium_agent_bootstrap_seconds` 一種，不是大量不同 metric 都有問題
- 沒有找到 Google 官方文件說明這個 collector 的 descriptor 清單機制或這個特定 metric 的狀況
- 沒有觀察到 Cilium/Dataplane V2 實際功能異常，僅為「少轉送一個一次性 metric 到遙測系統」

**動作：** 暫不處理。純屬我們自己依頻率/影響面的判斷，沒有權威來源背書。若之後觀察到 Dataplane V2 網路功能異常，應重新查證是否與此相關（但目前推斷關聯性低，因為 `cilium_agent_bootstrap_seconds` 只是啟動耗時記錄，非持續運作所需的 metric）。

**⚠️ 不適用於 `caring-tw`（`static-map-242406`）：** 原因同上一節「GKE Dataplane V2：`cni-writer`」——這個叢集沒有部署 Dataplane V2（無 `anetd` DaemonSet），這則 log 完全依附在 `anetd` 元件上，架構上不會出現，不需要為本專案查證這個 pattern。

---

## 格式慣例（新增項目時參考）

```markdown
## <元件>：`<log 關鍵字>`

| 項目     | 內容 |
| -------- | ---- |
| 元件     |      |
| Severity |      |
| 搜尋字串 |      |

**原因：** ...

**動作：** 不需處理 / 需處理的條件（若有例外情況）

**參考：** [來源連結]
```
