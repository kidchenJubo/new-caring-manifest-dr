# 災難復原（DR）：完整還原到新 GKE Cluster

> ⚠️ **本文件狀態：草稿，Phase 2（`scripts/` 底下三支 script）已產生初版，尚未在真實 `dr-drill-vpc` 跑過 `--execute`。** 內容已從 JCP 專案的同名文件改寫成 `static-map-242406`（Caring 平台）專用版本。GCP 現況已於 2026-09-09 查證更新（見下方各節）：VPC 為 `default`，Cloud Router 為 `default`，承載 Caring 對外連線的 NAT 是 `ha-nat-gateway`（固定 IP `35.221.142.73`，`MANUAL_ONLY`）；`mohw-whitelist` 是另一條只涵蓋 `mohw` subnet 的 NAT，與本 repo 無關。
>
> **本文件已於 2026-09-09 對照 Outline《[2026 災難還原演練](https://jubo.getoutline.com/doc/2026-CmTa1AyIfK)》（`住宿1.0` 團隊維護，第一輪演練 2026-08-31～09-03、第二輪 2026-09-04 已實際執行）校正，細節見下方「與住宿1.0 演練的關係」一節。同時已用 `kubectl`／ArgoCD 現況核對過本 repo 目前 7 個 `-release` 服務的實際部署狀態，見下方「⚠️ release 環境現況」。**

## ⚠️ release 環境現況（2026-09-09 查證，DR 範圍的前提）

本文件「範圍限定在 release，只手動 sync 7 個 `-release` 服務」的前提，預設這 7 個服務目前在正式環境都是健康、已同步的狀態。**實際查證發現並非如此：**

| ArgoCD Application | Sync | Health |
| --- | --- | --- |
| `new-caring-web-api-release` | Synced | Healthy |
| `new-caring-mobile-api-release` | Synced | Healthy |
| `new-caring-web-release` | Synced | Healthy |
| `new-caring-web-page-release` | Synced | Healthy |
| `new-caring-event-consumer-release` | Synced | Healthy |
| `caree-notification-release` | Synced | Healthy |
| `new-caring-line-api-release` | **OutOfSync** | **Missing** |

`new-caring-line-api-release` 這個 Application 從未被同步過——`new-caring-line-api-release` namespace 存在，但 `kubectl get deploy,pod -n new-caring-line-api-release` 回傳 `No resources found`，ArgoCD 回報 6 個資源（ConfigMap／Service／ServiceAccount／Deployment／HPA／PDB）皆為 `OutOfSync`，`health.status: Missing`。同時 git 上這個服務的 release values 近期仍有多次版本 bump（`fix-line-api->LINE-1.0.9` ～ `1.0.12`），代表這是「一直在改版但沒人 sync 到 release」，不是刻意下架。

**這件事直接影響 DR 範圍界定**：本文件下方多處假設「7 個 -release 服務」是要還原的完整清單，但若正式環境本身這個服務就沒有實際運行的 Pod，DR 演練沒有必要（也無法）「還原」一個本來就沒在跑的服務——除非操作者先在正式環境把它 sync 起來。**建議操作者先確認這是否為已知狀況，再決定 DR 演練的 7 個服務清單是否要排除 `new-caring-line-api-release`（或先手動 sync 正式環境）。**

## 災難情境與演練範圍（重要，先看這段）

這份 runbook 的**前提**是：**`asia-east1` 這個 region 整個異常**，需要重建整套 Caring 平台。既然前提是整個 region 不可用，新環境（VPC 名稱 **`dr-drill-vpc`**，已由操作者建好）就**完全不跟現有的 `default` VPC 有任何關聯**（不 peering、不共用任何資源）——`default` VPC 底下的 Cloud SQL（`caring-release-pg`）、Redis（`jubo-mqtt`），在這個前提下都當作不可用，`dr-drill-vpc` 要有自己**獨立重建**的 Cloud SQL 跟 Redis。

**範圍限定在 `release`（prod）環境，只還原這一個環境**（沿用 JCP 版本文件的原始設計決策，尚未跟操作者重新確認是否維持——若要改成同時還原其他環境請告知，需要調整下方多處）。這代表：

- Cloud SQL 只需要重建 `caring-release-pg` 這一個 instance
- Redis 只需要重建 `jubo-mqtt` 這一台
- PSC 只需要重建跟 release 相關的兩個方向（見下方「PSC」一節）
- `Infrastructure/argocd/values.yaml` 的 `apps.applications` 雖然還是會照 git 定義生出其他環境（dev/dev2/qat/qat2/demo）的 Application，但**只手動 sync `argocd` 自己＋7 個 `-release` 服務**，其餘環境放著不管（不會被同步，對應的 namespace 也不會被建出來，純粹是註冊在 ArgoCD 裡但不生效，沒有風險）

**DR 環境對外用 `-dr` 字尾的獨立網域**，不直接沿用正式的 release 網域，這樣還原/演練時不會影響現有正式流量：

| 正式網域 | DR 網域 |
| --- | --- |
| `sso-release.caringcm.com.tw`（Web，`/api/**` 同網域路由給 Web API） | `sso-release-dr.caringcm.com.tw` |
| `mobile-api.caringcm.com.tw` | `mobile-api-dr.caringcm.com.tw` |
| `jcp-release-api-caring.jubo.health`（JCP 平台對接 Caring 的網域，經 PSC） | `jcp-release-api-caring-dr.jubo.health` |

**目前實際演練**規劃在 `asia-east1` 裡另開一個完全獨立、命名為 `dr-drill-vpc` 的 VPC 執行，而不是真的換到別的 region——這樣可以先把「network／Cloud SQL／Redis／GKE cluster／ArgoCD bootstrap／服務同步／GCLB 對外曝光」整條從零重建的流程練熟，之後真的要換 region 時，只是把 `--region` 換掉，架構跟步驟大致同一套（GCLB／NEG 部分請見下方「⚠️ NEG／backend-service 命名衝突」一節，換 region 後這個限制會消失，可以簡化）。

新 cluster 統一建在**同一個 GCP 專案**（`static-map-242406`）。Workload Identity pool（`static-map-242406.svc.id.goog`）是專案層級資源，不受 region／network 影響。**經跟操作者確認：DR cluster 的 release 服務 namespace 沿用跟正式環境完全相同的名稱**（例如 `new-caring-web-api-release`，不加 `-dr` 字尾）——這樣只要 KSA 名稱一致（本來就是同一套 Helm chart，會一致），**既有的 GSA↔KSA Workload Identity 綁定不需要重做**，這是這份 DR 流程能大幅簡化、且完全不需要碰 `gcloud iam`（黑名單）的關鍵前提。代價見下一節。

## 與「住宿1.0」演練（Outline 另一份文件）的關係

`static-map-242406` 這個專案裡，同時有另一組人（`住宿1.0` 團隊，PM Dora Yeh）在做一份**已經實際執行過兩輪**的 DR 演練，文件在 Outline《[2026 災難還原演練](https://jubo.getoutline.com/doc/2026-CmTa1AyIfK)》。**那份文件不可修改，本文件只參考、不重複其內容**，這裡只記錄跟本 repo（該文件稱為「住宿2.0」）有關、需要校正或承接的部分：

- **範圍完全不重疊，兩邊互不還原對方的東西**：住宿1.0 的演練是 GCE VM／Samba 檔案伺服器／Windows IIS（830+ 租戶）／82-container 的 MSSQL VM，走磁碟 snapshot 還原，**完全沒有 GKE、Helm、ArgoCD，也沒有動到 Cloud SQL `caring-release-pg`**；本文件（住宿2.0）談的 GKE／Helm／ArgoCD／Cloud SQL 還原，住宿1.0 的文件裡也明確標註「不在本次範圍」「2.0 若要納入，尚未定案」。**目前住宿2.0（本 repo）的 DR 演練尚未開始，也還沒有對面（住宿1.0）團隊確認的執行細節**——這也是本文件仍停留在 Phase 1 草稿、未產生 script 的原因之一。
- **已定案、且會直接影響本文件的兩件事**（引用自該文件「9. 住宿2.0 演練確認事項」）：
  1. 住宿2.0 若要納入演練，**必須建在同一個 `dr-drill-vpc`**（不能自己另開一個 VPC）——跟本文件原本的假設一致，不需調整。
  2. 住宿1.0／2.0 共用同一個對外 LB 與網域（`sso-release.caringcm.com.tw` 等，path-based routing：`/api/**` 等動態路徑才是打到 2.0），所以「只還原 2.0」不等於「系統可用」，反之亦然——這點本文件的 DR 範圍（只還原 release 7 個服務）需要跟住宿1.0 的還原進度對齊，不能單獨驗收「看起來能動」。
- **`dr-drill-vpc` 現況查證結果（來自住宿1.0 文件，比原先本文件掌握的更完整，見下方表格更新）**：`dr-drill-vpc` 是 custom subnet mode、**egress 預設全部拒絕，只白名單開放特定 port／目的地**（見下方防火牆表格新增的 egress 規則列）。這對 GKE 建 cluster 有兩個目前**尚未處理**的具體影響：
  1. **GKE control plane 的 CIDR（`--master-ipv4-cidr`，例如 `172.16.x.x/28`）目前不在 egress 白名單內**——住宿1.0 文件明確提醒這個疏漏「manifests as cluster 建得起來但 node 永遠 NotReady，很難追查到是防火牆」。Phase 2 bootstrap script 建 cluster 前必須先補一條 egress allow 規則。

     **⚠️ 2026-09-11 實測踩雷，這條規則本身也踩了一次坑**：一開始只開 `tcp:443`，`kubectl get/describe/apply` 都正常（走一般 kube-apiserver 通訊），但 `kubectl logs`／`exec`／`port-forward` 全部卡在 `No agent available`，一路debug 到需要看某個服務的 log 才發現——這幾個走的是 **Konnectivity**（control plane 反向連回 node 的通道），node 端要能主動連到 control plane 的 `tcp:8132`，不是 443，兩個 port 都要開才行。`caring-dr-bootstrap.sh` 已經改成 `--rules=tcp:443,tcp:8132`。
  2. 目前 `dr-drill-vpc` 唯一的 service account `dr-drill@static-map-242406.iam.gserviceaccount.com`（`logWriter`＋`metricWriter`＋`caringcm` bucket 唯讀）**缺少 `artifactregistry.reader`**——DR cluster 的 node 若要用這組 SA 從 `asia-east1-docker.pkg.dev/static-map-242406/new-caring` 拉本 repo 的 image，需要操作者先補這個角色（屬 `gcloud iam`，黑名單，只能提供指令文字）。
- **⚠️ 2026-09-09 實測踩雷：GKE control plane 的 master-authorized-networks 預設鎖死，所有人連不上**。`caring-tw-dr` 建出來後 `masterAuthorizedNetworksConfig.enabled` 是 `true`，但 `cidrBlocks`是空的——等於沒有任何來源 IP 能連到 control plane 的公開端點（`endpoint`），`kubectl`／`helm` 全部會卡在 `dial tcp <endpoint>:443: i/o timeout`，錯誤訊息本身容易誤導成「client-side schema validation 的問題」（`kubectl` 建議 `--validate=false`），但實際上是網路層連不到，加這個參數沒用。`caring-dr-bootstrap.sh` 已在建完 cluster、`get-credentials` 之前，自動偵測「執行這支 script 的機器」目前的對外 IP，加進 `master-authorized-networks` 白名單（跟既有 CIDR 合併，不覆蓋）。**這代表誰在哪台機器上跑 bootstrap，白名單就會多一個那台機器的 IP**——如果之後換一台機器繼續跑（例如換了 VPN 出口 IP），可能需要重跑一次 Step 4b 或手動補一條。
- **TLS 憑證命名更正**：住宿1.0 的 `lb-drill` 直接沿用正式環境既有的 `caringcm2026-all`（`SELF_MANAGED`，SAN 涵蓋 `*.caringcm.com.tw`），不用另外簽。本文件下方原本寫「`caringcm2026` 等」，`caringcm2026-all` 才是實際涵蓋萬用字元的那張——`sso-release-dr.caringcm.com.tw`／`mobile-api-dr.caringcm.com.tw` 應該可直接沿用同一張，**只有 `jcp-release-api-caring-dr.jubo.health`（`.jubo.health` 網域，不在 `*.caringcm.com.tw` SAN 內）仍需要另外確認憑證**。
- **「2.0 是否真的無狀態」尚未證實**：住宿1.0 文件明確提醒「沒有 PersistentVolume 不等於無狀態，可能用 emptyDir 快取、掛 GCS、或應用自己寫本機檔，這條推論必須由 2.0 負責人確認」。本次查證 `Microservices/Caring` 底下所有 chart 皆未使用 `PersistentVolumeClaim`／`gcsfuse`／`hostPath`，正式環境 release namespace 也沒有任何 PVC，**但這只證明「目前 Helm chart 結構上沒宣告」，不是「應用程式邏輯上完全無本機狀態」的證明**（例如 `ConnectionStrings.CHomeConnection`／`OldCaringConnection` 這類外部 SQL Server 依賴之外，是否還有其他未被本文件涵蓋的狀態來源，仍待確認）。
- **「獨立 VPC 不是真實 DR 的目標架構」這個判斷，住宿1.0 文件也有相同結論**：「真實災難時比較可能是還原回 `default` VPC，以保留 NEG／PSC／LB 的延續性；獨立 VPC 純粹是演練期間不影響線上服務的隔離手段」——跟本文件「⚠️ NEG／backend-service 命名衝突」一節的立場一致，這裡只是交叉確認，不需調整本文件現有寫法。

## ⚠️ NEG／backend-service 命名衝突（因為沿用相同 namespace 而產生，必須另外處理）

Caring 平台的對外曝光機制跟 JCP 不同——**JCP 用 Gateway API（`Gateway`/`HTTPRoute`），Caring 用 Standalone NEG＋手動建立的 regional backend-service＋共用 GCLB URL Map**（見 `.claude/gcp-env.md`「網路入口」一節），完全不透過 Helm chart 自動產生雲端 LB 資源，也不在這個 repo 的 GitOps 範圍內。

每個對外服務的 `templates/service.yaml` 都有這個寫死的 annotation：

```yaml
cloud.google.com/neg: '{"exposed_ports": {"80":{"name": "{{ .Release.Namespace }}-80"}}}'
```

NEG 名稱**直接等於 `<namespace>-80`，且不是 values 可調整的欄位**。因為上一節決定 DR cluster 沿用跟正式環境相同的 namespace 名稱，若不處理，DR cluster 會嘗試在**同一個 GCP 專案、同樣的 zone（`asia-east1-a/b/c`）**建立一個名為 `new-caring-web-api-release-80` 的 Standalone NEG——但正式環境的同名 NEG 已經存在。**NEG／regional backend-service 的名稱在同一個 project＋zone／region 下必須唯一，不受 VPC 區分**，所以會直接撞名失敗（`create_lb_backend_services.sh` 建立的 backend-service 也是同樣的 `$app-$env-80` 命名，一樣會撞名）。

**解法**：Workload Identity 綁定看的是 namespace／KSA 名稱，**跟 NEG／backend-service 名稱完全無關**，所以可以只在**獨立維護的 DR fork repo**裡，把會對外曝光的服務的 `templates/service.yaml` 這行 annotation 改成帶固定 `-dr` 字尾的值（例如 `{{ .Release.Namespace }}-dr-80`），`destinationNamespace`／`App.ServiceAccount`（GSA）維持不動。這樣：

**⚠️ 2026-09-11 已實際落實**：一直到這時候才真的動手改，中間 ArgoCD 已經先把舊版（沒加 `-dr` 字尾）的 chart 同步上去，`new-caring-web-api-release` 這個 Service 因此真的撞名了——`kubectl get pod` 顯示 pod 卡在 `1/2 Ready`，`readinessGates` 是 `cloud.google.com/load-balancer-neg-ready`，事件顯示 `SyncNetworkEndpointGroupFailed: found conflicting description in neg new-caring-web-api-release-80: expected cluster-uid <DR> but got cluster-uid <prod>`——這個 NEG readiness gate 因為名稱衝突永遠不會過，pod 會**永遠卡在 not-ready**，不是等久一點就會自己好。已經把 5 個有這個 annotation 的服務全部改好（`new-caring-web-api`、`new-caring-web`、`new-caring-web-page`、`new-caring-mobile-api`、`new-caring-line-api`——`new-caring-line-api` 原本沒被列在這裡，實際查證後也有這個 annotation，一併補上；`caree-notification`／`new-caring-event-consumer` 沒有對外曝光，本來就沒有這個 annotation），只在 `dr` 這個 branch 改，**需要 commit＋push 到 `dr` remote，並在 ArgoCD 重新 sync 這幾個 Application 才會生效**（改 Service 的 annotation 需要重新 apply，光是 pod 本身沒變不會自動觸發）。

- Workload Identity 綁定完全不用動，不會碰到 `gcloud iam` 黑名單
- NEG／backend-service 名稱變成 `new-caring-web-api-release-dr-80` 等，不跟正式環境撞名
- 這個修改只存在於 DR fork repo，不會回頭影響這個 repo（正式環境）的 chart

`Shell/create_lb_backend_services.sh` 對應的 DR 版本（Phase 2 產生）也要用同樣帶 `-dr` 字尾的 `$app-$env-dr-80` 命名建立 backend-service，並各自加回 3 個 zone 的 NEG backend。

**Health check 與防火牆**：正式環境共用的 `k8s-health-check-new-caring` 是 regional TCP health check，不建議跨 VPC 沿用（保持 DR 完全獨立、且日後真的換 region 時不會有殘留依賴），DR 應該建一個獨立的 `k8s-health-check-new-caring-dr`。已查證 `dr-drill-vpc` 已經有 `dr-drill-allow-health-check`（`130.211.0.0/22`、`35.191.0.0/16` → `tcp:80,443,445,8080,15021,3000`，涵蓋 Service 的 `targetPort: 8080`）與 `dr-drill-allow-lb-proxy`（proxy-only subnet `10.251.0.0/24` → `tcp:80,8080`）這兩條防火牆規則，Phase 2 不需要另外補，backend-service／NEG 建好後 health check 應該能直接過。

**⚠️ 2026-09-11 系統性比對 `default` VPC（正式環境 `caring-tw`）與 `dr-drill-vpc` 的防火牆規則差異**：完整列出兩邊所有規則後逐條比對，多數差異是其他不相關服務／VM 專用（`gvm00`／`iis-webserver`／`samba`／`zgvm98`／`zgvm99`／`sql-server-test` 等舊 VM 或 dev/qat 環境專屬 tag，跟本 repo 的 DR 範圍無關，不需要複製），判斷後只有兩項值得補上：

1. **Health check 來源 IP 不完整**：正式環境的 `allow-health-check-8080`／`default-allow-health-check` 比 `dr-drill-allow-health-check` 多兩段來源 `209.85.152.0/22`、`209.85.204.0/22`（較新的 GCLB health check 來源範圍）。`caring-dr-bootstrap.sh` 已新增 `dr-drill-allow-health-check-extra-ranges` 補上，不動既有那條規則。
2. **LB proxy-only subnet 只開特定 port，跟正式環境作法不一致**：正式環境的 `k8s-fw` 對 proxy-only subnet／pod CIDR 是開放「全部 port」到 GKE node，而 `dr-drill-allow-lb-proxy` 只開 `80,8080`——這正是前面 `new-caring-web-page` 用 `3000` 撞到的那個問題的根源類型（health check 過但真流量被擋，卡滿 30 秒才 504）。與其每次多一個新服務、新 port 就再補一條點狀規則（前面已經因此多開過一次 `dr-drill-allow-lb-proxy-web-page`），這裡直接新增 `dr-drill-allow-lb-proxy-all-ports`（來源限定在 proxy-only subnet 本身，不是對外開放，風險可控），一次解決同一類問題，之後新增服務不會再因為 port 不同而卡住。

其餘明顯有关但**刻意不採用**的項目：
- `allow-ingress-from-iap`（IAP 來源對所有 port 開放，用於任意 port 除錯）——DR 現有的 `dr-drill-allow-admin-access` 已限定在 22／3389，沒有証據顯示需要對 IAP 來源開放更多 port，先不擴大存取面，需要時再個別開。
- `default-allow-icmp`（對外 0.0.0.0/0 開放 ping）——純診斷用途，DR 資源目前都沒有對外 IP（GKE nodes 是 private），效益低，不加。
- `pcs-allow-internal`（PSC 相關）——這是 PSC endpoint 本身要不要在 DR 建的架構問題，不是單純補一條防火牆規則就能解決，維持先前已經確認過的結論：**bootstrap 沒有處理 PSC／JCP 對接**，仍是待決定的獨立事項。
- `portainer-9001`／`sql-server-postgres`／`sql-server-mssql` 裡額外幾個 GCP 服務端點 IP——都是給 DBA／維運工具用的管理性存取，不影響 app 本身連線，屬於「需要才加」的選配項目，不主動補。

**TLS 憑證**：正式環境的憑證是手動上傳的 `SELF_MANAGED` 憑證（`caringcm2026`、`caringcm2026-all`、`cloudflare` 等，見 `.claude/gcp-env.md`「網路入口」一節），不是 cert-manager 自動管理。**其中 `caringcm2026-all` 的 SAN 涵蓋 `*.caringcm.com.tw`**（住宿1.0 演練的 `lb-drill` 已驗證直接沿用這張，不用另外簽）——`sso-release-dr.caringcm.com.tw`／`mobile-api-dr.caringcm.com.tw` 應可直接沿用同一張。**只有 `jcp-release-api-caring-dr.jubo.health`（`.jubo.health` 網域，不在這張憑證 SAN 內）仍需要操作者確認是否要另外上傳憑證**，這件事跟 Cloud SQL／Redis 一樣不在 script 自動化範圍內，需操作者手動處理。

**GCLB URL Map**：不建議把 `-dr` 的 host rule 加進正式環境現有的 `lb` URL Map（這個 URL Map 承載大量正式流量與其他不相關系統，`CLAUDE.md` 也明訂任何 `gcloud compute url-maps import` 執行前一律要先產生 diff＋指令＋讓操作者明確選擇是否執行）。DR 建議**建立一個完全獨立的新 URL Map＋forwarding rule＋外部 IP**，專門承載 `-dr` 網域，跟正式環境的 GCLB 資源完全不相交——這樣整個 DR 演練（包含之後的 cleanup）都不會有任何一步需要碰正式環境正在服務流量的 GCLB 設定。

## Cloud SQL／Redis 怎麼獨立重建（只還原 release）

已查證現況（2026-09-09，`static-map-242406`）：

- **Cloud SQL `caring-release-pg`**：PostgreSQL 17，`REGIONAL`（HA，跨 zone），edition `ENTERPRISE`，tier `db-custom-4-16384`（4 vCPU／16GB），`privateNetwork` 為 `default` VPC。自動備份**已開啟**：保留 7 份（依數量計）、backup 位置 `asia`（multi-region）、每天 18:00 開始、PITR 已開啟、transaction log 保留 7 天。這代表「新建全新 instance＋`gcloud sql backups restore`」這個做法可行。
  - **⚠️ 2026-09-09 實測踩雷**：`gcloud sql instances create` 若不明確帶 `--edition`，目前會預設用 `ENTERPRISE_PLUS`，這個 edition 不接受 `db-custom-N-M` 這種傳統 tier 命名（要求 `db-perf-optimized-N-*`），直接建立會報 `Invalid Tier ... for (ENTERPRISE_PLUS) Edition` 失敗。`caring-dr-bootstrap.sh` 已修正為明確帶 `--edition=ENTERPRISE`，對齊正式環境。
  - 另外查證了 JCP 版本文件提到的「懸空 Private Services Access 保留範圍」問題**在這裡不存在**：`default` VPC 的 PSA peering（`servicenetworking-googleapis-com`）指向的保留範圍 `cloud-ids-default-ips`（`10.7.0.0/16`）**實際存在、非懸空參照**。也就是說，`gcloud sql instances clone` 理論上在這裡可行，不像 JCP 那邊會直接因為懸空參照失敗。但為了維持 DR 情境「完全不驗證正式環境網路設定」的精神、且不想在還原時意外牽動正式 instance，**仍建議採用「新建全新 instance＋restore 最新備份」的做法**，不用 clone。
  - **⚠️ 2026-09-11 實測踩雷**：正式環境的 `caring-release-pg` 有開 `cloudsql.iam_authentication` 這個 instance 層級的 database flag（app 的 `PostgreSqlMaster`／`PostgreSqlSlave` 連線字串用的是 Cloud SQL IAM Authentication，`Userid=<ksa>@static-map-242406.iam`，`cloud-sql-proxy` sidecar 也帶了 `--auto-iam-authn`），但**這個 flag 不會因為「新建 instance＋restore 備份」自動帶到 DR instance 上**——IAM DB user 本身雖然會從備份還原回來（`gcloud sql users list` 看得到 `new-caring-web-api-release@static-map-242406.iam` 這些角色），但 instance 沒開這個 flag，IAM 驗證一律被拒絕。症狀跟上面的 PSA egress 缺口很像但不同層次：**防火牆通了之後**，`cloud-sql-proxy` log 顯示連線是 `Accepted connection` 但緊接著馬上 `instance closed the connection`（不是 timeout），app `/health` 一樣 503。`caring-dr-bootstrap.sh` 已修正為建立時帶 `--database-flags=cloudsql.iam_authentication=on`；若 instance 已存在但缺這個 flag，改用 `gcloud sql instances patch --database-flags=cloudsql.iam_authentication=on` 補上（**這個 patch 會讓 instance 短暫重啟**，套用需要幾分鐘）。
  - **⚠️ 2026-09-11 實測踩雷（app log 完全消失）**：三個網路缺口都補完、pod 也 2/2 Ready 之後，實際打 `/api/v1/auth/token` 出現 500，但 Log Explorer 完全查不到這筆錯誤——一開始懷疑是查詢語法問題（`resource.labels.namespace_name` 沒帶 `resource.labels.cluster_name`，因為 DR／正式環境用同一個 namespace 名稱，這點也順便驗證過：`lb-drill` 目前掛的三個 backend-service 的 NEG 端點 IP 全部落在 `10.252.0.0/16`〔DR 專屬 pod range〕、node 名稱也都是 `caring-tw-dr` 的 node pool，確認沒有不小心打到正式環境），但就算加上 cluster 過濾，**DR cluster 完全沒有任何 `k8s_container` 類型的 log**，`kubectl logs` 對 app container 本身也是空的（`cloud-sql-proxy` 這個 sidecar 有 log，只有主程式沒有）。查證後發現：正式環境 `caring-tw` 有 `gke-managed-otel` 這個 namespace（GKE Managed OpenTelemetry Collector），DR cluster 建立時完全沒有這個 namespace——app 的 `OpenTelemetry__EndPoint` 指向 `opentelemetry-collector.gke-managed-otel.svc.cluster.local:4317`，這幾個服務的 Serilog 只走 OTLP sink（沒有 Console fallback），collector 根本不存在，log 從源頭就送不出去，不是被防火牆擋、也不是 Cloud Logging 過濾掉。根因是 GKE cluster 層級的 `--managed-otel-scope` 設定，DR 建立時沒有帶，`caring-dr-bootstrap.sh` 已補上 `--managed-otel-scope=COLLECTION_AND_INSTRUMENTATION_COMPONENTS`（`create`／`create-auto` 都加了，已存在的 cluster 也會補跑一次 `clusters update` 帶同樣參數，等同 no-op／补跑皆可，不用額外查現況）。
- **Redis `jubo-mqtt`**：GCE VM，機型 `e2-medium`，磁碟 25GB，位於 `asia-east1-b`，內部 IP `10.140.0.59`，同樣在 `default` VPC。連線字串固定是 `jubo-mqtt.asia-east1-b.c.static-map-242406.internal:6379`，各環境用不同的 `defaultDatabase` index 共用同一台（dev=0, qat=1, demo=2, release=3, dev2=4, qat2=6, rs=9）。VM 規格已確認跟 JCP 的 `jcp-tw-redis-01`（`e2-medium`＋20GB）相近，**推測**同樣是自架 Redis（非 Memorystore），但受限於目前查詢權限，**尚未直接確認 VM 內是否用 Docker Compose 跑、`redis.conf` 內容、是否關閉持久化**——這部分需要能 SSH 進這台 VM 才能確認，留待 Phase 2 或操作者自行確認。
  - **命名澄清（引用住宿1.0文件「Step 5: 還原 jubo-mqtt-drill」的架構查證）**：這台 VM 上實際跑**兩組獨立、互不依賴的 docker-compose**：`/home/nginx/`（nginx＋oauth2proxy，這是住宿1.0 LB priority-4 實際指到的服務，serve 靜態資源）與 `/home/jubo-mqtt-usr/running/`（postgres＋redis＋人臉辨識服務）。**VM 名稱雖然叫 `jubo-mqtt`，但兩組都沒有 MQTT broker**（沒有 mosquitto，沒開 1883/8883）——本 repo（住宿2.0）GKE pods 連的就是後面這組 docker-compose 裡的 redis（`6379`），有正式環境防火牆規則佐證（`jubo-mqtt-redis`，來源 `10.64.0.0/14`，即 `caring-tw` cluster 的 pod CIDR），確認這條連線真實存在、非本文件假設。
  - **⚠️ 這台 VM 是少數住宿1.0／2.0都有實際依賴的共用資源，restore 時務必確認 redis 這組 docker-compose 真的啟動成功，不能只驗 nginx**：住宿1.0 的 Step 5 決定「兩組 docker-compose 全部 clone、不拆分」，還原後的驗證腳本會掃描確認「nginx 容器正常＋postgres/redis 本機監聽」，但那份驗證的**動機與重點是 1.0 的 nginx／靜態資源**（LB priority-4 依賴的是它），redis 是否真的裝好、真的能被本 repo 的 GKE pods 連上，需要**本 repo（住宿2.0）這邊自己額外驗證**，不能假設住宿1.0 那邊的「驗證通過」等於 2.0 的 redis 依賴也沒問題。`caring-dr-validate.sh` 會額外對 `jubo-mqtt-drill:6379` 做連線／`PING` 測試，不要只看 VM 是否 RUNNING。
  - **⚠️ 2026-09-09 跟操作者確認、簡化過一次的策略**：`caring-dr-bootstrap.sh` **一律**自己建一台全新、乾淨的 VM（`caring-redis-drill`），裝 Docker＋跑一個 `docker run redis:7-alpine` 容器，純粹只為了讓本 repo（住宿2.0）的 GKE pods 有 redis 可用，不含 prod 資料、不含 nginx／samba。**不再偵測／沿用住宿1.0 team 的 `jubo-mqtt-drill`**（先前版本會先檢查對方是否已還原，存在就沿用、不存在才照對方「Step 5」snapshot 還原方法自建，這個判斷會把 DR bootstrap 的時程綁死在對方身上，操作者決定拿掉這個判斷，一律用本 repo 自己的 DR redis）。`caring-dr-cleanup.sh` 因此可以直接刪掉這台 VM，不需要再跟住宿1.0 team 協調清理時機。

  **DR repo 裡 Redis 連線字串建議填 GCE 內部 DNS hostname，不要填 IP**：`caring-redis-drill.asia-east1-b.c.static-map-242406.internal`（同一個 zone `asia-east1-b`），不管重建幾次、配到的內部 IP 是否一樣，都保持穩定。

- **`dr-drill-vpc` 目前沒有 Private Services Access peering**（已查證：`gcloud services vpc-peerings list --network=dr-drill-vpc` 回傳空結果）。Cloud SQL 私有 IP 要能被這個 VPC 存取，**這是 Phase 2 bootstrap 一定要補的一步**：先保留一個 IP range、再對 `servicenetworking.googleapis.com` 建立 peering，不是「借用 `default` VPC 的 peering」，`dr-drill-vpc` 一定要有自己的一份。

**`dr-drill-vpc` 目前已經備妥的部分（操作者已預先建好，Phase 2 不需要重建）**：

| 資源 | 值 |
| --- | --- |
| 主要 subnet | `dr-drill-subnet`（`10.250.0.0/24`，`asia-east1`，PRIVATE） |
| Proxy-only subnet | `dr-drill-proxy-only`（`10.251.0.0/24`，`asia-east1`，`REGIONAL_MANAGED_PROXY`——這是 regional external managed backend-service／LB 需要的 Envoy proxy subnet，已經備好） |
| 防火牆：`dr-drill-allow-lb-proxy`（**2026-09-11 實測踩雷**） | 這條規則（`10.251.0.0/24` proxy-only subnet → GKE node，INGRESS）只開了 `tcp:80,8080`，**沒有涵蓋 `new-caring-web-page` 用的 `targetPort: 3000`**。症狀很有誤導性：`gcloud compute backend-services get-health` 顯示 HEALTHY（health check 走另一條規則 `dr-drill-allow-health-check`，剛好有開 3000），但實際打 `/v2/`（route 到 `new-caring-web-page-release-dr-80`）會卡滿 `timeoutSec`（30 秒）才 504——因為 GCLB 的 health check 跟真正的資料流量走的是兩條不同的防火牆規則，一條開一條沒開才會出現「health 過但真流量不過」的反差。直接 port-forward 進 pod 測試（繞過 GCLB）秒回，藉此排除是 app 本身的問題。這條是住宿1.0既有的共用規則，沒有動它，另外新增一條 `dr-drill-allow-lb-proxy-web-page`（同樣 `10.251.0.0/24` → `tcp:3000`）補這個缺口 |
| Cloud Router／NAT | `dr-drill-router`／`dr-drill-nat`（`AUTO_ONLY`，`ALL_SUBNETWORKS_ALL_IP_RANGES`，已可對外連線，Phase 2 不需要另外建 NAT） |
| 防火牆：health check | `dr-drill-allow-health-check`（`130.211.0.0/22`、`35.191.0.0/16` → `tcp:80,443,445,8080,15021,3000`，涵蓋 Service 的 `targetPort: 8080`，**已就緒**）＋ 2026-09-11 新增 `dr-drill-allow-health-check-extra-ranges`（補正式環境有但這裡沒有的 `209.85.152.0/22`、`209.85.204.0/22`） |
| 防火牆：LB proxy | `dr-drill-allow-lb-proxy`（`10.251.0.0/24` proxy-only subnet → `tcp:80,8080`，**已就緒**）＋ `dr-drill-allow-lb-proxy-web-page`（補 `tcp:3000`）＋ 2026-09-11 新增 `dr-drill-allow-lb-proxy-all-ports`（同樣來源，`--rules=all`，比照正式環境 `k8s-fw` 的開放範圍，避免以後每個新服務都要重新踩一次 port 缺口的雷） |
| 防火牆：管理存取 | `dr-drill-allow-admin-access`（特定辦公室／VPN IP＋IAP range `35.235.240.0/20` → `tcp:22,3389`） |
| 防火牆：`jubo-mqtt` 相關 | `dr-drill-jubo-mqtt-postgres`（`tcp:5432`）／`dr-drill-jubo-mqtt-redis`（`tcp:6379`）／`dr-drill-jubo-mqtt-web`（`tcp:8081`），皆為特定辦公室／VPN IP 對內 ingress——看起來是為了讓 DBA／維運人員能直接連線 DR 環境的 Postgres／Redis／管理介面除錯用 |
| 防火牆：MSSQL | `dr-drill-sql-server-mssql`（`tcp:9900-9999`，特定辦公室／VPN IP ingress，給 DBA 手動連線用）——這組 port 對應 `CHomeConnection`／`OldCaringConnection` 連線字串指到的 `sql-server-drill` VM（`10.250.0.193`），**這條規則沒涵蓋 GKE pod range**，2026-09-11 已補一條 `dr-drill-sql-server-gke-access`，見下方「CHome／OldCaring 連線」一節 |
| 防火牆：egress（**新查證，先前本文件未記錄**） | `dr-drill-vpc` 的 egress 是**預設拒絕＋白名單**（`dr-drill-deny-egress-default`），目前只開放 `dr-drill-allow-egress-internal`（VPC 內部）、`dr-drill-allow-egress-metadata`（metadata server）、`dr-drill-allow-egress-web`（`tcp:80,443` 對外）、`dr-drill-allow-egress-kms`（`35.190.247.13/32:1688`，Windows KMS 啟用用，跟本 repo 無關）。**GKE control plane CIDR（`--master-ipv4-cidr`）目前不在白名單內，Phase 2 建 cluster 前必須先補一條 egress allow 規則**，否則 node 會卡在 `NotReady`（詳見上方「與住宿1.0演練的關係」一節） |
| 防火牆：egress（**2026-09-09 實測踩雷，另一個白名單缺口**） | `dr-drill-allow-egress-internal` 只涵蓋 `10.250.0.0/24`（主要 subnet）／`10.251.0.0/24`（proxy-only），**沒涵蓋後來才加的 GKE pods（`10.252.0.0/16`）／services（`10.253.0.0/20`）secondary range**——導致 pod-to-pod、甚至 pod 連 cluster DNS（kube-dns ClusterIP 落在 services range）全部被 `dr-drill-deny-egress-default` 擋掉。實際症狀：ArgoCD 網頁打得開，但內部功能出現 `dial udp <kube-dns-ip>:53: i/o timeout` 這類 DNS lookup 失敗。`caring-dr-bootstrap.sh` 已在加 secondary range 的同一步，另外補一條 `dr-drill-allow-egress-gke-pods-services` 涵蓋這兩段（不去動既有的 `dr-drill-allow-egress-internal`，那是住宿1.0 team 建的共用規則） |
| 防火牆：egress（**2026-09-11 實測踩雷，同一個坑的第三次**） | `dr-drill-allow-egress-gke-pods-services` 建立時只填了 GKE pods／services 這兩段，**沒涵蓋 Private Service Access 保留給 Cloud SQL private IP 用的範圍**（`dr-drill-psa-range`，GCP 自動配的，本次實測是 `10.164.180.0/24`，不是我們自己選的值，每次環境重建都要重新查）。症狀：`cloud-sql-proxy` sidecar log 一直是 `dial tcp 10.164.180.7:3307: i/o timeout`，app 的 `/health` 因此永遠 503、pod 卡在 not-ready。`caring-dr-bootstrap.sh` 已改成 Step 1（PSA peering）之後動態查 `dr-drill-psa-range` 的實際 CIDR，一併塞進這條規則的 `destinationRanges`；若規則已存在但沒涵蓋這段，會用 `gcloud compute firewall-rules update` 補上，而不是略過 |

**✅ 2026-09-11 已確認：CHome／OldCaring 連線在 DR 情境下走「(b) 另建複本」**：`new-caring-line-api`／`new-caring-web-api` 等服務的 `ConnectionStrings.CHomeConnection`／`OldCaringConnection` 指向的其實不是 GCP 專案外的主機，而是 `dr-drill-vpc` 內部一台既有的 VM **`sql-server-drill`**（`10.250.0.193`，`asia-east1-b`，tag `sql-server-drill`）——這是操作者／住宿1.0團隊事先建好的 DR 專用 SQL Server 複本，本 script 不建立、不刪除它。

**⚠️ 實測踩雷**：pod 都健康、Cloud SQL／Redis 都通了之後，實際打 `/api/v1/auth/token` 出現 `.NET SqlException: A network-related or instance-specific error occurred... (provider: TCP Provider, error: 40 - Could not open a connection to SQL Server)`，且這筆 log 一開始也找不到（另一個獨立問題，見上方「app log 完全消失」的 `gke-managed-otel` 踩雷）。用 `kubectl exec` 對 `10.250.0.193:9900` 做 TCP 測試直接 timeout，一開始懷疑是 `dr-drill-subnet`（`10.250.0.0/24`）跟這台 VM 所在網段「路由層級打不到」，但查證後發現 VM 就在同一個 `dr-drill-subnet` 裡，L3 是通的——真正原因跟 `jubo-mqtt`／`sql-server-drill` 都是同一套既有防火牆規則的老問題：`dr-drill-sql-server-mssql` 這條規則只開放特定辦公室／VPN IP（給 DBA 手動連線用），**沒有涵蓋 GKE pod range**，導致 pod 打不到。`caring-dr-bootstrap.sh` 已補上 Step 3b：對這台既有 VM（存在才動手，不建立也不刪除）另開一條 `dr-drill-sql-server-gke-access`（`10.252.0.0/16` → `tcp:9900-9999`），不去動既有那條 DBA 用的規則。

**DR 資源命名**：本 repo 專屬、不跟住宿1.0 共用的資源沿用「現有名稱＋`-dr` 字尾」慣例；`jubo-mqtt` 是例外，因為它是兩邊共用的同一台 VM，命名對齊住宿1.0 既有的 `-drill` 字尾慣例（見上方 Redis 段落說明）：

| 正式資源 | DR 資源（暫定，Phase 2 前可調整） |
| --- | --- |
| GKE cluster `caring-tw` | `caring-tw-dr` |
| Cloud SQL `caring-release-pg` | `caring-release-pg-dr` |
| Redis VM `jubo-mqtt`（`asia-east1-b`） | `caring-redis-drill`（同 zone，本 repo 專屬、一律自建，僅裝 docker redis，不含 prod 資料，不沿用住宿1.0 的 `jubo-mqtt-drill`） |
| VPC `default` | `dr-drill-vpc`（已建好，非本文件命名決定） |

## ⚠️ 這些新資源的名稱/連線字串跟正式環境不同，需要一份獨立維護的 DR repo

跟 JCP 版本文件不同，Caring 這個 repo 的 ArgoCD 部署機制**不是 ApplicationSet＋每個服務各自的 `apps/services/*.yaml`**，而是單一 Helm chart（`Infrastructure/argocd`）用 `templates/applications.yaml` 對 `values.yaml` 的 `apps.applications` map 做 `range` 迴圈，且**全部 Application 共用同一個 `apps.global.repoURL`／`targetRevision`**（目前是 `https://github.com/jubo-health/new-caring-manifest` / `main`）。這代表：

- DR fork repo 要改的 repoURL 只有**一個地方**（`Infrastructure/argocd/values.yaml` 的 `apps.global.repoURL`），不像 JCP 需要改 13 個 `apps/services/*.yaml`
- 需要改連線資訊的也只有 `values_release.yaml`（7 個服務各一份）：`ConnectionStrings.PostgreSqlMaster`／`PostgreSqlSlave` 裡的 `Userid`（GSA 不變，但 Cloud SQL Proxy 的 `SqlProxy.InstanceName` 要指向 `caring-release-pg-dr`）、`Redis.ConnectionString`（指向 `caring-redis-drill` 的內部 DNS hostname，`defaultDatabase` index 是否沿用 3 待 Phase 2 決定）
- 加上上一節提到的：需要對外曝光的服務要修改 `templates/service.yaml` 的 NEG annotation 字尾

照 JCP 版本文件的既有決定，**這件事不在這個 repo、也不靠 script 自動處理**——真的要做 DR 時，另外準備一份獨立維護的 GitHub repo（這個 repo 的 fork 或副本）。目前**尚未建立**這份 DR 專用 repo（JCP 版本用的是 `jcp-manifest-dr`，Caring 這邊還沒有對應的 repo，需要操作者先建立並命名）。

## ArgoCD 安裝：CRD 前置步驟＋登入方式（已簡化）

`Infrastructure/argocd` 這個 chart **管的就是 ArgoCD 自己**（`apps.applications.argocd`，`syncWave: "-20"`，全 repo同步順序最早）。DR 這裡的目的很單純：**自動裝好 ArgoCD、自動指到（DR fork）repo，能連得上操作就好**，不處理 SSO 登入，所以以下不再談 Dex／Microsoft Entra ID。

1. **CRD 未內建，但這是本 repo 刻意的覆蓋，不是 ArgoCD 原本的行為**：查證 vendored 的 `charts/argo-cd-9.4.4.tgz`（`Chart.lock` 已鎖定 `version: 9.4.4`、`digest` 校驗），這個 subchart 自己的 `values.yaml` 預設就是 `crds.install: true`＋`crds.keep: true`——**正常情況下 `helm install` 這個 chart 本來就會自動把 CRD 裝好**，這是 argo-helm 官方 chart 的標準行為，不需要另外做任何事。本 repo的 `Infrastructure/argocd/values.yaml` 是**明確把 `install` 覆蓋成 `false`**，原因是正式環境 `caring-tw` 的 CRD 早在 cluster 建立當下（`kubectl get crd` 查證：`applications.argoproj.io` 等 3 個 CRD 的建立時間精確對應 cluster 建立時間）就裝好了，之後改成 `false` 只是不想讓 Helm 在每次 `upgrade` 時繼續「管理」CRD 這個全域、跨 namespace 的資源（CRD 若被 Helm upgrade 誤刪，會 cascade 刪光叢集裡所有的 `Application` 物件），跟「ArgoCD 不需要 CRD」完全無關。

   **DR 不需要指定版本，也不需要另外重裝**：CRD 的 manifest 就內建在 `templates/crds/*.yaml` 裡，跟著這個已經被 `Chart.lock` 鎖死版本＋digest 的 vendored chart 走，沒有獨立的「CRD 版本」需要挑選或對齊。

   **⚠️ 2026-09-09 實測踩雷，設計修正過一次**：原本想法是 bootstrap 時對整個 chart 帶 `--set argo-cd.crds.install=true` 做一次 `helm install` 裝好 CRD＋ArgoCD 本體，再用第二次 `helm upgrade`（`crds.install` 改回 `false`）補上完整的 `apps.applications`——中間試過用 `--set-json apps.applications={}` 讓第一次安裝先不要建那幾十個 `Application` 物件，**結果失敗**：`helm install ... --set-json apps.applications={}` 實際上完全沒有清空 `apps.applications`，Helm 對 `--set`／`-f` 的 map 值一律做**遞迴合併**，一個空 map `{}` 合併到已經有幾十個 key 的 map 上，合併結果還是原本那個完整的大 map——這代表**map 這種結構本質上沒辦法透過 `--set` 或 `-f` 覆蓋成空**，第一次 `helm install` 依然嘗試建出全部環境的 `Application` 物件，在 CRD 還不存在（或還沒被這次 install 建立）時直接整批失敗（`no matches for kind Application ... ensure CRDs are installed first`）。

   **正確做法**：CRD 的安裝完全不透過 Helm release 追蹤，改用 `helm template --set argo-cd.crds.install=true --show-only 'charts/argo-cd/templates/crds/*'` **純本地渲染**出 3 個 CRD 的 manifest（`helm template` 不連任何叢集，只是把 YAML 印出來），直接 `kubectl apply` 套用，等 3 個 CRD `Established` 之後，再做**單次** `helm install`／`upgrade --install`——這次沿用 git 預設的 `crds.install: false`（CRD 已經用 `kubectl apply` 建好，這個 release 本來就不需要、也不應該再管一次，設成 `true` 反而會撞 `cannot be imported into the current release`），一次把 ArgoCD 本體跟全部環境（含 7 個 `-release`）的 `Application` 都建起來，不需要任何兩階段的 map 覆蓋技巧。CRD 由 `helm template` 渲染出來時仍帶 `helm.sh/resource-policy: keep` annotation（chart 預設 `crds.keep: true`），這個 annotation 本身無害，只是不影響什麼（因為 CRD 本來就不歸這個 release 管）。

   **⚠️ 2026-09-09 又踩一個雷**：一般的 client-side `kubectl apply -f -` 會把整份 manifest 塞進 `kubectl.kubernetes.io/last-applied-configuration` 這個 annotation，用來做下次 apply 的三方合併 diff——但 `applicationsets.argoproj.io` 這個 CRD 本身的 OpenAPI schema 太大，塞進 annotation 後直接超過 Kubernetes annotation 總大小 262144 bytes（256 KiB）的硬限制，`kubectl apply` 會報 `metadata.annotations: Too long`。這是 argo-cd 官方 chart 文件本來就對這幾個大型 CRD 建議的已知限制，解法是改用 **server-side apply**（`kubectl apply --server-side --force-conflicts -f -`）——用 Kubernetes 的 managed-fields 機制取代那個 annotation，沒有這個大小限制；`--force-conflicts` 是保險，避免重跑時因為欄位管理者跟前一次（client-side apply）不同而卡住。`caring-dr-bootstrap.sh` 已改用這個做法。

   **⚠️ 2026-09-09 又踩第三個雷**：CRD apply 成功後，等 `Established` 這步原本把 3 個 CRD 名稱一次傳給同一個 `kubectl wait`，結果不穩定——3 個裡只要有 1 個當下 `status.conditions` 還是 `nil`（不是空陣列，是完全還沒被 populate），`kubectl wait` 就會直接噴 `.status.conditions accessor error: <nil> is of the type <nil>, expected []interface{}` 中止整個指令，即使另外 2 個其實已經真的 `Established`。改成每個 CRD 各自獨立呼叫一次 `kubectl wait`（各自的 watch／timeout，互不影響）解決。

2. **登入方式**：`values.yaml` 裡 `configs.cm.dex.config` 設定的是正式環境的 Microsoft Entra ID SSO，**DR 不處理這個**——`argocd-dex-ms-secret` 這個 Secret 在 DR cluster 上不會被建立，Dex 這個 pod 會因為讀不到 `clientSecret` 而起不來（可能 `CrashLoopBackOff`），**這是預期中、可以忽略的狀態**，不影響 ArgoCD 本身：ArgoCD 內建的 admin 帳號（`argocd-initial-admin-secret`，chart 安裝時自動產生）走的是獨立於 Dex 的認證路徑，不受 Dex 掛掉影響。

   **你需要的是 LB mode 能連上**：沿用原本的做法，bootstrap 時把 `server.service.type` 覆蓋成 `LoadBalancer`（覆蓋 git 上的預設 `ClusterIP`），讓操作者可以直接用外部 IP＋admin 密碼登入，不需要等 DNS／Ingress。取密碼指令：`kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d`。跟 CRD 的 override 一樣，**這個 override 只在 DR bootstrap 用，不寫回 git**——`argocd` 這個 Application 可以正常跟其他 7 個 `-release` 服務一起 sync，不需要像先前版本那樣刻意延後。

   **⚠️ 2026-09-09 這裡也踩了兩輪雷**：正式環境 `server.service` 除了 `type` 還有一個 `annotations.cloud.google.com/neg`，指到跟正式環境一模一樣的 NEG 名稱 `new-caring-argocd-80`。第一次試把 `annotations` 整個覆蓋成空 map（`{}`），結果完全沒清掉——原因跟 `apps.applications` 那次一樣，Helm 對 map 的合併是遞迴的，空 map 合併到已經有 key 的 map 上不會清掉任何東西；DR cluster 的 `argocd-server` 因此帶著跟 prod 一樣的 NEG 名稱，GKE 的 NEG controller 想去管理同一個 NEG，但已經被 prod cluster 的 cluster-uid 標記擁有，觸發 `SyncNetworkEndpointGroupFailed`／`conflicting description` 錯誤（衝突偵測擋下了實際寫入，沒有動到 prod，但放著重試沒意義）。第二次試把這個 key 單獨覆蓋成 `null`（**這個技巧本身有效**，跟空 map 不同——只要 override 的 map 裡真的有這個 key，就會覆蓋掉 base 對應的 key），結果又踩另一個雷：`null` 轉成 Kubernetes annotation（`map[string]string`）之後變成空字串 `""`，Autopilot cluster 上有一個 admission webhook（`neg-annotation.common-webhooks.networking.gke.io`）只要這個 key 存在，不管值是什麼都會嚴格驗證是不是合法 JSON，空字串不合法，直接擋下整個 `helm upgrade`（"NEG annotation is invalid"）——Standard 模式沒有這個 webhook，只會在 NEG controller 事後 reconcile 時才發現撞名，Autopilot 則是在 apply 當下就擋。**最終做法**：這個 key 沒辦法真的「刪掉」也不能給空值，那就給一個合法、但改成不會撞名的 JSON 值——沿用本文件其他地方對外曝光服務的做法（NEG 名稱加 `-dr` 字尾），改成 `new-caring-argocd-dr-80`：NEG controller／webhook 都滿意，DR 自建一個獨立、閒置、不影響任何流量的 NEG（`type: LoadBalancer` 走的是另一套機制，用不到這個 NEG，純粹是繞過「無法清空」的限制）。細節與最終值見 `scripts/caring-dr-argocd-overrides.yaml`。

   **⚠️ 2026-09-09 跟操作者確認的既定決策：整個還原演練期間，ArgoCD 對外都維持 LB mode（直接用 LoadBalancer 外部 IP＋admin 密碼），不會另外設定 DNS。** 不會有 `argocd-dr.xxx` 這類網域，也不需要憑證——這跟本文件其他地方講的「-dr 網域待 DNS 記錄指過去」是兩件事，只適用於 7 個 `-release` 服務的對外網域（`sso-release-dr.caringcm.com.tw` 等），ArgoCD 本身不在那個範圍內，`caring-dr-cleanup.sh` 也因此不需要處理 ArgoCD 相關的 DNS 清理。

`argo-cd` chart dependency（`charts/argo-cd-9.4.4.tgz`）已 vendor 進這個 repo，DR fork repo 直接沿用即可，不需要額外處理 chart 依賴下載的問題。

## PSC（與「JCP」平台的雙向私有連線，只還原 release 相關的兩個方向）

跟 JCP 版本文件的角色相反——這裡是 **Caring 自己的 project（`static-map-242406`）** 同時扮演 PSC 消費端與生產端：

| 方向 | 正式環境資源（`static-map-242406` 內） | 只跟 release 相關的 |
| --- | --- | --- |
| Caring 為 Consumer（呼叫 JCP 平台 API） | `jcp2-dev`／`jcp2-qat`／`jcp2-uat`／`jcp2-prod` | `jcp2-prod`（Internal IP `10.140.0.19`） |
| Caring 為 Producer（把 mobile-api 私有暴露給 JCP 平台呼叫） | `psc-jcp-dev-api`／`psc-jcp-qat-api`／`psc-jcp-demo-api`／`psc-jcp-release-api` | `psc-jcp-release-api`（Internal IP `10.140.0.126`） |

DR 演練若要完整還原 JCP 對接，這兩個方向都需要在 `dr-drill-vpc` 裡重建對應的 forwarding rule／service attachment，且**對面 JCP 平台那個 project（尚未確認 project ID，見 `.claude/gcp-env.md`「PSC 對接」一節）也需要配合重建/改指**——這部分不在這個 repo 的管轄範圍，只整理交接清單，不寫消費端操作步驟（沿用 JCP 版本文件的既有原則）。

**⚠️ 2026-09-11 實測踩雷＋已補上（`jcp-release-api` 這個方向）**：app 呼叫 `http://jcp-release-api.jubo.health.internal` 出現 `Name or service not known`。查證後發現：
- `jcp-release-api.jubo.health.internal` 這筆紀錄所在的 private zone（`psc-jcp-api-internal-domain`）**只授權給 `default` VPC**，`dr-drill-vpc` 完全不在授權清單內，這是直接原因。
- 更根本的是：這筆紀錄指到的 `10.140.0.126` 本身是 `psc-jcp-release-api` 這個 forwarding rule 的 internal IP，**實際 target 是 `jubo-care-platform` 專案裡的 service attachment**（`target-service-attachment`，不是被呼叫的 target），代表 Caring／`static-map-242406` 在這個方向其實是 **Consumer**（呼叫 JCP 平台的 API），跟上面表格原本標注的「Producer」方向不一致——**表格這一列的方向標注需要之後找機會校正**，這裡先如實記錄查證結果，不動表格本身。且這個 IP 只在 `default` VPC 內可路由（`default` 沒有跟 `dr-drill-vpc` peering），就算修好 DNS 授權也連不到。
- 已確認 JCP 那邊的 service attachment（`psc-jcp-release-api-20260129`）accept list 是用 **project** 授權（`static-map-242406`），不是限定特定 VPC，所以 DR 另開一個 consumer endpoint 不需要對方額外開權限。

**已建立（`caring-dr-bootstrap.sh` Step 3d，idempotent，已存在則略過）**：
1. `dr-drill-psc-jcp-release-api`（`dr-drill-subnet` 內的內部 IP，`10.250.0.200`）
2. `dr-drill-psc-jcp-release-api`（PSC forwarding rule，`target-service-attachment` 指到同一個 JCP service attachment）
3. `dr-drill-jubo-health-internal`（只授權給 `dr-drill-vpc` 的獨立 private zone，`dns-name=jubo.health.internal.`，刻意不去動 `default` VPC 那個共用的 `psc-jcp-api-internal-domain`）
4. 上述 zone 裡的 `jcp-release-api.jubo.health.internal.` A record，指到 `10.250.0.200`

**尚未處理**：configmap 裡還有第二個 JCP 相關網域 `jcp2-api-gateway.jubo.health.internal`（`JcpClient__BaseUrl`，指到另一個 PSC forwarding rule `jcp2-prod`／`10.140.0.94`，同樣是 `default` VPC 專屬），從實際 log（`Jcp.Sdk.JcpApiClient`）看起來這條可能才是主要在用的路徑，之後很可能會踩到一模一樣的問題，需要的話比照同樣模式（新 PSC forwarding rule＋同一個 DR private zone 裡多加一筆 record）處理，目前尚未建立。

## 為什麼故意留這些手動斷點

- **ArgoCD 的 sync 不自動化**：`argocd` CLI 在 `CLAUDE.md` 黑名單內（不執行也不產出可執行指令文字），刻意全部留給操作者在 UI 上做。這份 repo 目前**所有** Application（不只 DR 情境）本來就都是手動 sync（`apps.applications` 沒有任何一個 entry 設定 `syncPolicy.automated`），DR 只是延續同樣的操作方式。
- **PSC 消費端／JCP 平台那端不動**：見上一節，對面 project 不在這個 repo 管轄範圍。
- **DNS 不自動改**：沿用目前的 DNS 供應商設定，這份 runbook 只負責告訴操作者「哪些記錄要指向哪個新 IP」。
- **GCLB／TLS 憑證不自動處理**：見上方「NEG／backend-service 命名衝突」一節，DR 專用的 URL Map／憑證／host rule 全部手動建立，刻意不去動正式環境現有、正在服務流量的 `lb` URL Map。

## 三支 script 的分工（Phase 2 草稿已產生，見 `scripts/`）

三支都已寫好放在 `scripts/`，共用 `scripts/caring-dr-common.sh`（變數＋`run`/`confirm`/context 檢查等工具函式）。**預設是 dry-run**（只印出會執行的指令，不會真的動任何資源），要真的執行需要另外加 `--execute`。已用 dry-run 對照過目前 GCP／`caring-tw` 現況跑過一次，語法與變數是通的，但**還沒在真實 `dr-drill-vpc` 跑過 `--execute`**，第一次正式使用前務必再過一次 dry-run 輸出。TLS／GCLB／PSC／DNS 這幾塊照操作者指示暫不展開自動化，三支 script 裡都只留提醒清單。

另外還有一支輔助 script **`scripts/caring-dr-gke-argocd.sh [--recreate] [--execute]`**：從 `caring-dr-bootstrap.sh` 擷取出「建 GKE cluster → 裝 ArgoCD」這一段（Step 4／4b／5a-5d），單獨拿出來給需要反覆測試這段的時候用，不用每次都連 PSA／Cloud SQL／Redis 一起重跑。帶 `--recreate` 會先刪掉現有的 `caring-tw-dr`（含 `argocd-server` 的 LoadBalancer Service）再重建，方便從零重測；不帶的話跟其他 script 一樣是 idempotent，cluster 已存在就略過建立，直接跑後面的 CRD／ArgoCD 步驟。

| Script | 何時執行 | 做什麼 | 需要人工介入的地方 |
| --- | --- | --- | --- |
| `scripts/caring-dr-bootstrap.sh` | 一次跑到底 | 唯讀健檢 `dr-drill-vpc`／subnet／proxy-only subnet 存在 → 確認 DR fork repo（`REPO_URL`，固定在 `caring-dr-common.sh`，用前務必確認／更新）真的存在、PAT 讀得到 → 補 PSA peering → 建 `caring-release-pg-dr`＋還原 `caring-release-pg` 最新備份 → **Redis 一律自建 `caring-redis-drill`（全新 VM＋docker redis，不沿用住宿1.0 的 `jubo-mqtt-drill`、不依賴 samba-drill）**，並確保本 repo 需要的 GKE pod range → 6379 這條路徑（獨立 tag／防火牆規則）存在 → 幫 `dr-drill-subnet` 加 pods/services secondary range → 開兩條 egress 防火牆（放行 GKE control-plane CIDR；放行 pods/services CIDR，見上方實測踩雷——既有的 `dr-drill-allow-egress-internal` 沒涵蓋這兩段，不補會導致 pod 連 cluster DNS 全部 timeout） → 建 GKE cluster `caring-tw-dr`（private nodes；**2026-09-09 跟操作者確認：預設用 Autopilot 模式**（`gcloud container clusters create-auto`，不用猜 machine type／node pool／autoscaling），只有明確帶 `GKE_MODE=standard` 才會改建 Standard 模式、比照正式環境 `caring-tw` 規格；**2026-09-11 補上 `--managed-otel-scope=COLLECTION_AND_INSTRUMENTATION_COMPONENTS`**，見下方「app log 完全消失」的實測踩雷說明，已存在的 cluster 也會補跑一次 `clusters update` 帶同樣參數）→ **自動偵測執行機器的對外 IP，加進 `master-authorized-networks` 白名單**（cluster 建出來預設鎖死，見上方實測踩雷說明）→ 切 context → **用 `helm template --show-only` 純本地渲染 3 個 CRD manifest 並 `kubectl apply`**（不透過 release 追蹤，避開 `--set`／`-f` 無法清空 map 的問題，見下方 ArgoCD 章節的實測踩雷說明）→ 建 `argocd` namespace → 建立 ArgoCD 用來 clone DR fork repo 的 repository credential Secret → **單次** `helm upgrade --install` `Infrastructure/argocd`（`server.service.type` 覆蓋成 `LoadBalancer`、`crds.install` 維持 git 預設的 `false`，`apps.global.repoURL` 指到 DR fork repo，一次建好 ArgoCD 本體＋全部環境的 Application） | 跑完印出 ArgoCD 外部 IP／admin 密碼指令、7 個 `-release` 服務需要操作者去 ArgoCD UI 手動 sync；`dr-drill@` 缺的 `artifactregistry.reader`（`gcloud iam` 黑名單）本 script 不會、也不能幫忙做 |
| （中間）操作者在 ArgoCD UI 手動操作 | bootstrap 完成後 | 只 sync `argocd` 自己＋7 個 `-release` 服務（`new-caring-line-api-release` 是否納入，見上方「⚠️ release 環境現況」） | 全部手動，本 runbook 不自動化 |
| `scripts/caring-dr-validate.sh` | `-release` 都同步、健康之後 | 檢查 7 個 Application 的 Sync／Health＋對應 namespace 的 Pod 狀態、Cloud SQL DR instance 狀態，**對 `caring-redis-drill` 建一次性 debug pod 做 `redis-cli PING` 連線測試**（見「與住宿1.0演練的關係」一節，這是本 repo／住宿2.0 特有、住宿1.0 的驗證腳本不會幫忙做的部分） | GCLB backend health、PSC、DNS 只印提醒清單，不自動驗證 |
| `scripts/caring-dr-backend-add.sh [--app <name>]...` | pod 都健康之後，要接上 GCLB 之前 | **2026-09-11 新增，同日追加自動接線功能**：對齊正式環境 `Shell/create_lb_backend_services.sh` 的既有慣例（backend-service 本來就是操作者手動建立、不透過 Helm/ArgoCD），DR 版本一律用 `<app>-release-dr-80` 命名（backend-service 名稱＝NEG 名稱，NEG 的 `-dr-80` 命名見上方 NEG 撞名章節）。預設處理 `new-caring-web-api`／`new-caring-web` 這兩個目前已開的服務，`--app` 可覆蓋成其他服務名稱（例如之後要開 `new-caring-web-page`）。idempotent：backend-service／每個 zone 的 NEG 掛載都會先查現況，已存在／已掛好的略過（**2026-09-11 修過一個 bug：判斷 NEG 是否已掛載原本用行尾錨點比對，但 gcloud 的輸出是用分號接在同一行，只有最後一個 zone 能正確判斷，已修正**）。**若 `lb-drill` 存在**，還會自動檢查／補上／更新 `drill-urlmatcher` 對應這幾個服務的 route rule（見下方「lb-drill url-map 接線」一節），`lb-drill` 不存在則印警告但不阻擋 backend-service 本身的建立 | GCLB 這一步只處理 backend-service＋（`lb-drill` 存在時）自動接線；如果之後改用正式的獨立 url-map（不是沿用 `lb-drill`），仍需要操作者手動處理 host rule／TLS，見 `runbooks/new-env.md` Phase 4 |
| （手動，後改自動）`lb-drill` url-map 接線 | 對應 backend-service 建好之後 | 原本是操作者一次性手動貼（`gcloud compute url-maps edit lb-drill ...`），仿照正式環境 `lb` 的 `release` path matcher：`web-api`（priority 2，`/api/**`）、`web-page`（priority 3，`/v2/`）、`others`（priority 5，`/**`），跟既有的 asp(1)／static(4) 不衝突。**2026-09-11 已改為 `caring-dr-backend-add.sh` 自動處理**，見下方說明 | `lb-drill` 存在才會動手，不存在只印警告 |

**⚠️ 2026-09-11 實測踩雷**：`lb-drill` 是住宿1.0team自己的資源，不是本 repo／本 script 管的——他們的演練結束後就把它砍了，連同 `lb-drill-forwarding-rule`／`lb-drill-target-proxy` 一起（本 repo 自己建的 3 個 `-dr-80` backend-service 沒有被連帶刪掉，因為那些是獨立資源）。`caring-dr-backend-add.sh` 已補上一個唯讀檢查：執行時如果查不到 `lb-drill` 這個 url-map 會印出 ⚠️ 警告，說明對面可能已經把它砍了、且在 `lb-drill` 重建＋route rule 重新貼上去之前不會有任何流量進來——但**不會阻擋 backend-service 本身的建立／補齊**（兩者沒有強依賴關係，backend-service 可以先準備好放著）。下次演練若要恢復對外流量，除了重跑 `caring-dr-backend-add.sh`，還需要操作者確認 `lb-drill`／`lb-drill-forwarding-rule`／`lb-drill-target-proxy` 是否都要跟著重建（這部分是住宿1.0 team 的資源，不在本 repo 範圍內）。

**✅ 2026-09-11 已自動化**：原本判斷「這幾個服務用的端點固定不會變，貼一次就好」，但後來發現 `lb-drill` 本身會被住宿1.0team的演練週期性砍掉重建，並不是真的一次性——`caring-dr-backend-add.sh` 因此改成：**只要 `lb-drill` 存在，就會自動檢查／補上／更新** `drill-urlmatcher` 這個 path matcher 裡 `new-caring-web-api`（priority 2，`/api/**`）、`new-caring-web-page`（priority 3，`/v2/`）、`new-caring-web`（priority 5，`/**` 其他）這幾條 route rule，完全不碰既有的 `asp`(1)／`static`(4)。做法是 `describe --format=json` 讀出目前狀態、用 `jq` 判斷該 priority 的規則是否存在／是否指到正確的 backend-service、有需要才組出更新後的 JSON 用 `url-maps import` 寫回去（**要先 `del()` 掉 `creationTimestamp`／`kind`／`selfLink`／`id`／`region` 這幾個 `describe` 才有、`import` 不接受的唯讀欄位，不然會因為 `additionalProperties` 驗證失敗**）。用一個臨時建立、跟正式 `lb-drill` 結構相同的測試 url-map 完整跑過一輪（新增→驗證→重跑驗證 idempotent→刪除測試資源），確認邏輯正確後才套用到真實情境。目前只有這 3 個 app 有預先定義好的 route rule 對應，之後用 `--app` 加其他服務時，如果沒有在 script 裡的 `DR_LB_ROUTE_PRIORITY`／`DR_LB_ROUTE_DESCRIPTION`／`DR_LB_ROUTE_MATCH` 這三個對照表補上項目，只會建 backend-service，不會自動接進 `lb-drill`（會印警告提醒）。

**附帶修好一個既有 bug（`caring-dr-backend-add.sh`，這次測試才發現）**：判斷「這個 zone 的 NEG 是否已經掛在 backend-service 上」原本用 `grep "...zones/${zone}/networkEndpointGroups/${neg}$"`（行尾錨點）比對 `gcloud ... --format="value(backends[].group)"` 的輸出，但這個 formatter 對多筆結果是用分號 `;` 接在**同一行**、不是換行——導致只有最後一個 zone 能正確比對到，其餘 zone 會被誤判成「還沒掛」而重複 `add-backend`，直接噴 `Duplicate network endpoint groups in backend service` 錯誤中止。已修正為先把分號轉成換行再比對。

**⚠️ 2026-09-11 `caring-dr-backend-remove.sh` 已被操作者刪除**：操作者判斷 `lb-drill` 本來就會被住宿1.0team自己的演練週期性砍掉重建，這支「移除 backend-service／NEG」的 script 因此沒有存在必要（backend-service 沒有端點也不會被健康檢查判定異常，留著不影響正式環境）。`caring-dr-cleanup.sh` 原本提醒「DR 專用 GCLB（backend-service／NEG）是否有殘留」那行 checklist 也一併移除，理由相同。若之後真的要清 backend-service，直接手動 `gcloud compute backend-services delete <name>-release-dr-80 --region=asia-east1` 即可，不需要專門的 script。
| `scripts/caring-dr-cleanup.sh [--purge-network]` | 演練全部驗證完成後 | 先刪 `argocd-server` 的 LoadBalancer Service（避免孤兒 forwarding rule）→ 刪 GKE cluster → 刪 Cloud SQL DR instance → 刪 Redis（`caring-redis-drill`，完全是本 script 自建，直接刪）。**2026-09-09 跟操作者確認：本 script 建立的 3 條防火牆規則一律不刪**（只影響 `dr-drill-vpc` 內部，風險低，留著可省下次重跑演練要重建的步驟），`--purge-network` 也不影響這個決定，只控制 `dr-drill-subnet` 的 secondary range 與 PSA peering／range 是否一併刪除（預設保留，重建比重建 compute 麻煩、不持續計費）。**永遠不會刪 `dr-drill-vpc`／`dr-drill-subnet`／`dr-drill-proxy-only`／`dr-drill-nat`**，那些不是本 script 建立的共用資源 | 執行前會列出將刪除的資源要求輸入 `yes` 確認；DR 專用 URL Map／憑證／`-dr` DNS 記錄仍需手動確認清乾淨，尤其若 DR 的 target-https-proxy 有引用正式環境的 `caringcm2026-all`，需要先刪掉它，否則會卡住正式環境之後要輪替這張憑證 |

## 執行步驟（Phase 2 script 產生後才能真正跑，此處先列規劃順序）

### 0. 事前準備

- **DR 專用 GitHub repo**：目前尚未建立，需要操作者先建立（這個 repo 的 fork 或副本），內容包含：7 個 `values_release.yaml` 的 Cloud SQL／Redis 連線資訊、需要對外曝光服務的 `templates/service.yaml` NEG 字尾修改、`Infrastructure/argocd/values.yaml` 的 `apps.global.repoURL` 改指向這份 DR repo。
- **GitHub token**：對 DR 專用 repo 至少有讀取權限的 PAT，存到本機檔案（不進 git）。
- **DR 專用 TLS 憑證**：`sso-release-dr.caringcm.com.tw`／`mobile-api-dr.caringcm.com.tw` 可直接沿用既有的 `caringcm2026-all`（SAN 涵蓋 `*.caringcm.com.tw`，住宿1.0 演練已驗證此做法），只需要另外確認／準備 `jcp-release-api-caring-dr.jubo.health` 的憑證。

### 1～4：跟 JCP 版本文件的流程骨架相同（bootstrap → ArgoCD UI 手動 sync → validate → 手動收尾），細節等 Phase 2 產生 script 時再展開。

### 5. 演練全部驗證完成後，清除這次建立的資源

跟 JCP 版本文件相同的原則：確認整個流程都跑通、該驗證的都驗證過之後才做這一步，避免下次重跑演練時資源名稱衝突。`argocd-server` 若用 LoadBalancer type 曝光，記得在刪 cluster 前先手動刪這個 Service（讓 in-cluster 的 cloud-controller 回收雲端資源，避免孤兒 forwarding rule）。

## 還沒做的前置準備（待辦，非本次範圍）

- [x] ~~重新登入 `gcloud`~~（2026-09-09 已完成，本次查證都是在 `kidchen@jubo.health` 底下執行）
- [x] ~~查證 `caring-release-pg` 的自動備份設定~~（已查證，見上方 Cloud SQL 一節）
- [x] ~~查證 `jubo-mqtt` 的機器規格~~（已查證：`e2-medium`／25GB／`asia-east1-b`；Docker Compose／持久化設定仍需 SSH 進 VM 才能確認，見上方一節）
- [x] ~~查證 `caring-tw` GKE cluster 模式~~（已查證：Standard 模式，非 Autopilot，見上方一節）
- [x] ~~查證 `dr-drill-vpc` 現況~~（已查證：subnet／proxy-only subnet／NAT／多數防火牆規則皆已就緒，唯獨缺 PSA peering，見上方一節）
- [x] ~~對照住宿1.0 演練文件（Outline）校正共用資源名稱~~（2026-09-09 已完成，見上方「與住宿1.0演練的關係」一節：`dr-drill-vpc`／`dr-drill-subnet`／`dr-drill-proxy-only`／`dr-drill-nat` 名稱確認一致；`caringcm2026-all` 憑證命名已更正；新發現 egress 白名單制、`dr-drill@` SA 缺 `artifactregistry.reader` 兩個缺口）
- [x] ~~確認正式環境 7 個 `-release` 服務目前是否都健康、已同步~~（2026-09-09 已用 `kubectl`／ArgoCD 查證：6 個 Synced/Healthy，`new-caring-line-api-release` **OutOfSync／Missing**，見上方「⚠️ release 環境現況」——**這件事需要操作者先確認再決定 DR 範圍**）
- [ ] `.claude/gcp-env.md`「網路（Cloud NAT）」一節：Cloud Router `default`、NAT `ha-nat-gateway`、Egress IP `35.221.142.73`（`MANUAL_ONLY`）尚未補上
- [ ] `dr-drill-vpc` 補一個 Private Services Access peering（保留 IP range＋對 `servicenetworking.googleapis.com` peering），Cloud SQL 私有 IP 才能被這個 VPC 存取——Phase 2 bootstrap script 要處理這一步
- [ ] `dr-drill-vpc` 補一條 egress allow 規則，開放 GKE control plane CIDR（`--master-ipv4-cidr`）——目前 egress 是預設拒絕＋白名單制，見上方「與住宿1.0演練的關係」一節，不補這一步 node 會卡在 `NotReady`
- [ ] 操作者授予 `dr-drill@static-map-242406.iam.gserviceaccount.com` 這個 SA `artifactregistry.reader`（`gcloud iam`，黑名單，需操作者自行執行），DR cluster 才能拉 `asia-east1-docker.pkg.dev/static-map-242406/new-caring` 底下的 image
- [x] ~~確認 `CHomeConnection`／`OldCaringConnection` 指向的外部 SQL Server 在 DR 情境下的策略~~（已確認：走「另建複本」，`sql-server-drill` VM 已存在，2026-09-11 補上 GKE pod 存取的防火牆，見上方「CHome／OldCaring 連線」一節）
- [ ] 需要能 SSH 進 `jubo-mqtt` 才能確認的細節：是否用 Docker Compose 跑 Redis、`redis.conf` 內容、是否關閉持久化——會影響 Phase 2 bootstrap script 能否完全比照 JCP 版本文件的自動化方式重建
- [ ] 建立 DR 專用 GitHub repo 並完成上方「事前準備」列出的內容
- [ ] **⚠️ 這 10 個新 per-app GSA（見 `.claude/gcp-env.md`「Workload Identity」一節）目前尚未在 GCP 建立、也還沒完成 Workload Identity 綁定**——這是 DR 流程能否成立的前提（本文件「既有 GSA↔KSA 綁定不需要重做」的假設，前提是這些綁定在正式環境上真的存在）。這 10 個 GSA 建立完成前，DR 演練即使照本文件跑完，release 環境的 pod 也一樣無法透過 Workload Identity 認證，會卡在 Cloud SQL／GCS 等需要 IAM 認證的地方。
- [ ] 確認 PSC 對面（JCP 平台）所在的 project ID，並補上「AI 允許查詢的 GCP Projects」表格
- [ ] 確認住宿2.0（本 repo）是否真的無狀態（Postgres／Redis 之外沒有其他需要還原的持久狀態）——見上方「2.0 是否真的無狀態」尚未證實一節，需 2.0（本 repo）負責人確認
- [ ] 待「住宿1.0」團隊補齊《9. 住宿2.0 演練確認事項》其餘待補清單後，再跟本文件對齊一次（該文件明訂「沒補完不要開工」）

`scripts/` 底下三支 script 已經有初版（見上方「三支 script 的分工」），但這份清單列的項目一項沒完成，就不建議對真實 `dr-drill-vpc` 跑 `--execute`——尤其是 `artifactregistry.reader`、GKE control-plane CIDR 的 egress 規則、DR fork repo 這三項，bootstrap script 目前是假設它們已經就緒才會成功跑完。
