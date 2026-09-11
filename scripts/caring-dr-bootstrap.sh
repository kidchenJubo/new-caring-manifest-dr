#!/usr/bin/env bash
# 一次跑到底：dr-drill-vpc 內建立 Cloud SQL／Redis VM／GKE cluster，手動渲染＋套用 CRD 後
# 單次 helm install 把 ArgoCD 裝起來、指向 DR fork repo。細節與決策原因見
# runbooks/disaster-recovery.md，這裡只放「要執行什麼」。
#
# ⚠️ Phase 2 草稿，尚未在真實 dr-drill-vpc 跑過。第一次使用務必先不加 --execute（預設 dry-run）
#   看一次會執行哪些指令，確認符合預期後再加 --execute 真的跑。
#
# 用法：
#   scripts/caring-dr-bootstrap.sh [--execute]
#
# REPO_URL／REPO_REVISION 固定在 scripts/caring-dr-common.sh（不再用 CLI 參數傳），
# ⚠️ 操作者執行前務必先去 common.sh 確認／更新那個值，或用環境變數覆蓋：
#   REPO_URL=https://github.com/jubo-health/xxx scripts/caring-dr-bootstrap.sh
#
# GKE_MODE 預設 autopilot（不用猜 machine type／node pool／autoscaling），
# 要改建 Standard 模式（比照正式環境規格）才需要另外帶：
#   GKE_MODE=standard scripts/caring-dr-bootstrap.sh --execute
#
# 前提（本 script 不會幫你做，見 runbook「還沒做的前置準備」清單）：
#   - dr-drill-vpc／dr-drill-subnet／dr-drill-proxy-only／dr-drill-nat 等網路資源已由操作者建好
#   - dr-drill@static-map-242406.iam.gserviceaccount.com 已補上 artifactregistry.reader
#     （gcloud iam 黑名單，這個 script 不會幫你做，也不會印出這個指令）
#   - DR 專用 GitHub fork repo（REPO_URL）已建立，且其 Infrastructure/argocd/values.yaml 已改好
#     各服務 values_release.yaml 的 Cloud SQL／Redis 連線資訊（指向 -dr 資源）
#   - 有讀取 REPO_URL 權限的 GitHub PAT 已存到 DR_GITHUB_PAT_FILE（預設 .caring-dr/github-token.txt，
#     專案根目錄下、已加進 .gitignore，單行純文字，不要換行；建議先 chmod 600）——這支 script
#     會拿它做兩件事：(1) 執行前確認 repo 真的存在、(2) 建立 ArgoCD 用來 clone 這個 repo 的
#     repository credential Secret
#   - argo-cd chart CRD／LB 兩個 override 的原因見 scripts/caring-dr-argocd-overrides.yaml

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=./caring-dr-common.sh
source "scripts/caring-dr-common.sh" "$@"

log "=== Caring DR Bootstrap ==="
log "DRY_RUN=$DRY_RUN　REPO_URL=$REPO_URL　REPO_REVISION=${REPO_REVISION:-<沿用 git 上的 main>}　GKE_MODE=$GKE_MODE"

check_gcloud_account

# -------------------------------------------------------------------------
# Step 0：唯讀健檢——先確認 dr-drill-vpc 相關資源真的存在，不存在就先停下來，
#   不要在後面的步驟才發現地基沒打好。
# -------------------------------------------------------------------------
log "--- Step 0: 檢查 dr-drill-vpc 相關資源是否已就緒 ---"
for check in \
  "compute networks describe ${DR_VPC}" \
  "compute networks subnets describe ${DR_SUBNET} --region=${REGION}" \
  "compute networks subnets describe ${DR_PROXY_SUBNET} --region=${REGION}"
do
  # shellcheck disable=SC2086
  if ! gcloud $check --project="${PROJECT_ID}" >/dev/null 2>&1; then
    log "❌ 找不到資源：gcloud $check --project=${PROJECT_ID}，請確認操作者已依 runbook 建好 dr-drill-vpc。"
    exit 1
  fi
done
log "dr-drill-vpc／subnet／proxy-only subnet 皆存在，繼續。"

log "--- Step 0b: 確認 DR fork repo（${REPO_URL}）真的存在 ---"
check_github_repo_exists "${REPO_URL}"

# -------------------------------------------------------------------------
# Step 1：Private Service Access peering（Cloud SQL 私有 IP 要靠這個）
# -------------------------------------------------------------------------
log "--- Step 1: Private Service Access peering ---"
if gcloud compute addresses describe "${DR_PSA_RANGE_NAME}" --global --project="${PROJECT_ID}" >/dev/null 2>&1; then
  log "${DR_PSA_RANGE_NAME} 已存在，略過保留 IP range。"
else
  run gcloud compute addresses create "${DR_PSA_RANGE_NAME}" \
    --project="${PROJECT_ID}" \
    --global \
    --purpose=VPC_PEERING \
    --prefix-length="${DR_PSA_RANGE_PREFIX_LENGTH}" \
    --network="${DR_VPC}"
fi

run gcloud services vpc-peerings connect \
  --project="${PROJECT_ID}" \
  --service=servicenetworking.googleapis.com \
  --ranges="${DR_PSA_RANGE_NAME}" \
  --network="${DR_VPC}"

# -------------------------------------------------------------------------
# Step 2：Cloud SQL——新建全新 instance，restore caring-release-pg 最新備份
#   （不用 clone，理由見 runbook「Cloud SQL／Redis 怎麼獨立重建」）
# -------------------------------------------------------------------------
log "--- Step 2: Cloud SQL ${DR_SQL_INSTANCE} ---"
if gcloud sql instances describe "${DR_SQL_INSTANCE}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  log "${DR_SQL_INSTANCE} 已存在，略過建立與還原備份，直接進到下一步（若要重新還原，先手動刪掉這個 instance 再重跑）。"

  # 2026-09-11 實測踩雷：app 端連線字串用 Cloud SQL IAM Authentication 登入
  # （PostgreSqlMaster Userid=...@static-map-242406.iam），但這是 instance 層級的
  # database flag，不會跟著「新建 instance + restore 備份」自動帶過來（IAM DB user
  # 本身雖然會從備份還原回來，但 flag 沒開，驗證一律被拒絕）。
  # 若 instance 已存在但漏了這個 flag，補上去，不要整台重建。
  EXISTING_SQL_FLAGS="$(gcloud sql instances describe "${DR_SQL_INSTANCE}" --project="${PROJECT_ID}" \
    --format="value(settings.databaseFlags[].name)" 2>/dev/null)"
  if [[ "$EXISTING_SQL_FLAGS" == *"cloudsql.iam_authentication"* ]]; then
    log "${DR_SQL_INSTANCE} 已有 cloudsql.iam_authentication flag，略過。"
  else
    log "${DR_SQL_INSTANCE} 缺少 cloudsql.iam_authentication flag，補上去（需要幾分鐘套用）。"
    run gcloud sql instances patch "${DR_SQL_INSTANCE}" \
      --project="${PROJECT_ID}" \
      --database-flags="cloudsql.iam_authentication=on" \
      --quiet
  fi
else
  run gcloud sql instances create "${DR_SQL_INSTANCE}" \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --database-version="${SQL_DATABASE_VERSION}" \
    --edition="${SQL_EDITION}" \
    --tier="${SQL_TIER}" \
    --availability-type="${SQL_AVAILABILITY_TYPE}" \
    --network="projects/${PROJECT_ID}/global/networks/${DR_VPC}" \
    --database-flags="cloudsql.iam_authentication=on" \
    --no-assign-ip

  # 只有這次真的新建了空 instance 才需要還原備份；已存在的 instance 代表之前跑過，
  # 不重複還原（避免每次重跑 bootstrap 都覆蓋掉可能已經在上面驗證/操作的資料）。
  LATEST_BACKUP_ID="$(gcloud sql backups list \
    --project="${PROJECT_ID}" \
    --instance="${RELEASE_SQL_INSTANCE}" \
    --sort-by="~endTime" \
    --limit=1 \
    --format="value(id)")"

  if [[ -z "$LATEST_BACKUP_ID" ]]; then
    log "❌ 查不到 ${RELEASE_SQL_INSTANCE} 的任何備份，無法還原。"
    exit 1
  fi
  log "將還原 ${RELEASE_SQL_INSTANCE} 的備份 ${LATEST_BACKUP_ID} 到 ${DR_SQL_INSTANCE}。"

  confirm "確定要用備份 ${LATEST_BACKUP_ID} 覆蓋 ${DR_SQL_INSTANCE} 的內容嗎？（只影響 DR instance，不影響正式環境）"
  run gcloud sql backups restore "${LATEST_BACKUP_ID}" \
    --project="${PROJECT_ID}" \
    --backup-instance="${RELEASE_SQL_INSTANCE}" \
    --restore-instance="${DR_SQL_INSTANCE}"
fi

# -------------------------------------------------------------------------
# Step 3：Redis——一律自己建一台全新、乾淨的 VM（${DR_REDIS_VM}），裝 Docker＋跑一個
#   docker redis 容器，純粹只為了讓本 repo（住宿2.0）的 GKE pods 有 redis 可用，
#   不嘗試還原 prod 資料、不依賴 samba-drill、不偵測／沿用住宿1.0 team 的 jubo-mqtt-drill
#   （2026-09-09 跟操作者確認：不再判斷對方是否已還原，一律用本 repo 自己的 DR redis）。
# -------------------------------------------------------------------------
log "--- Step 3: Redis（${DR_REDIS_VM}） ---"

REDIS_STARTUP_SCRIPT='#! /bin/bash
set -euo pipefail
apt-get update
apt-get install -y docker.io
systemctl enable --now docker
docker run -d --name jubo-mqtt-redis --restart unless-stopped -p 6379:6379 redis:7-alpine
'

if gcloud compute instances describe "${DR_REDIS_VM}" --zone="${REDIS_ZONE}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  log "${DR_REDIS_VM} 已存在，略過建立 VM。"
else
  run gcloud compute instances create "${DR_REDIS_VM}" \
    --project="${PROJECT_ID}" \
    --zone="${REDIS_ZONE}" \
    --machine-type="${REDIS_MACHINE_TYPE}" \
    --network="${DR_VPC}" \
    --subnet="${DR_SUBNET}" \
    --image-family="${DR_REDIS_IMAGE_FAMILY}" \
    --image-project="${DR_REDIS_IMAGE_PROJECT}" \
    --service-account="${DR_NODE_SA}" \
    --scopes=cloud-platform \
    --metadata="startup-script=${REDIS_STARTUP_SCRIPT}"
fi

# 本 repo（住宿2.0）GKE pods 真正需要的路徑：從 DR cluster 的 pod range 連到 redis:6379。
run gcloud compute instances add-tags "${DR_REDIS_VM}" \
  --project="${PROJECT_ID}" \
  --zone="${REDIS_ZONE}" \
  --tags="${DR_REDIS_ACCESS_TAG}"

if gcloud compute firewall-rules describe "${DR_REDIS_GKE_FIREWALL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  log "${DR_REDIS_GKE_FIREWALL} 已存在，略過。"
else
  run gcloud compute firewall-rules create "${DR_REDIS_GKE_FIREWALL}" \
    --project="${PROJECT_ID}" \
    --network="${DR_VPC}" \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=tcp:6379 \
    --source-ranges="${DR_GKE_PODS_RANGE_CIDR}" \
    --target-tags="${DR_REDIS_ACCESS_TAG}"
fi

# -------------------------------------------------------------------------
# Step 3b：SQL Server drill VM（sql-server-drill）的 GKE pod 存取
#   2026-09-11 實測踩雷：app 的 CHomeConnection／OldCaringConnection 連線字串指向
#   10.250.0.193:9900（Server=CHOME 的 MSSQL），這台 sql-server-drill VM 剛好也在
#   dr-drill-subnet（10.250.0.0/24）內，不是網路不通，是既有的 dr-drill-sql-server-mssql
#   這條防火牆只開放特定辦公室／VPN IP（DBA 手動連線用），沒涵蓋 GKE pod range，
#   導致 app 連線出現「Could not open a connection to SQL Server」。這台 VM 本身不是本
#   script 建的（既有資源），只補一條 GKE pod → VM 的防火牆，不去動既有那條規則。
# -------------------------------------------------------------------------
log "--- Step 3b: sql-server-drill 的 GKE pod 存取 ---"
if gcloud compute instances describe "${DR_SQLSERVER_VM}" --zone="${DR_SQLSERVER_ZONE}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  if gcloud compute firewall-rules describe "${DR_SQLSERVER_GKE_FIREWALL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    log "${DR_SQLSERVER_GKE_FIREWALL} 已存在，略過。"
  else
    run gcloud compute firewall-rules create "${DR_SQLSERVER_GKE_FIREWALL}" \
      --project="${PROJECT_ID}" \
      --network="${DR_VPC}" \
      --direction=INGRESS \
      --action=ALLOW \
      --rules="tcp:${DR_SQLSERVER_PORTS}" \
      --source-ranges="${DR_GKE_PODS_RANGE_CIDR}" \
      --target-tags="${DR_SQLSERVER_TAG}"
  fi
else
  log "找不到 ${DR_SQLSERVER_VM} 這台 VM，略過（這是既有資源，不是本 script 建的，可能還沒建好或名稱／zone 跟預期不同）。"
fi

# -------------------------------------------------------------------------
# Step 3c：GCLB health check／data-plane 防火牆補強
#   2026-09-11 系統性比對 default VPC（caring-tw 正式環境）跟 dr-drill-vpc 的防火牆規則差異後，
#   判斷有兩個缺口值得先補上（其餘差異大多是別的服務/VM 專用，跟本 repo 的 DR 範圍無關，見
#   runbook 對應段落的完整比對紀錄）：
#   (a) 正式環境的 health check 規則（allow-health-check-8080／default-allow-health-check）
#       比 dr-drill-allow-health-check 多兩段來源 IP（209.85.152.0/22、209.85.204.0/22，
#       較新的 GCLB health check 來源範圍），這裡新增一條補上，不去動既有那條規則。
#   (b) 正式環境的 k8s-fw 對 LB proxy-only subnet 是開放「全部 port」到 GKE node，
#       而 dr-drill-allow-lb-proxy 只開 80/8080——這正是前面 web-page 用 3000 撞到那個問題
#       的根源類型（health check 過但真流量被擋、卡滿 30 秒才 504）。與其每次多一個新服務、
#       新 port 就再補一條點狀規則，這裡直接開一條涵蓋全部 port 的規則（來源限定在
#       proxy-only subnet 本身，不是對外開放，風險可控），一次解決同一類問題，
#       避免以後每個新服務都要重新踩一次雷。
#   兩條都是新增規則，不動 dr-drill-allow-health-check／dr-drill-allow-lb-proxy 這兩條
#   既有的、住宿1.0team建立的共用規則本身。
# -------------------------------------------------------------------------
log "--- Step 3c: GCLB health check／data-plane 防火牆補強 ---"
if gcloud compute firewall-rules describe dr-drill-allow-health-check-extra-ranges --project="${PROJECT_ID}" >/dev/null 2>&1; then
  log "dr-drill-allow-health-check-extra-ranges 已存在，略過。"
else
  run gcloud compute firewall-rules create dr-drill-allow-health-check-extra-ranges \
    --project="${PROJECT_ID}" \
    --network="${DR_VPC}" \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=tcp:80,tcp:443,tcp:445,tcp:8080,tcp:15021,tcp:3000 \
    --source-ranges=209.85.152.0/22,209.85.204.0/22
fi

if gcloud compute firewall-rules describe dr-drill-allow-lb-proxy-all-ports --project="${PROJECT_ID}" >/dev/null 2>&1; then
  log "dr-drill-allow-lb-proxy-all-ports 已存在，略過。"
else
  run gcloud compute firewall-rules create dr-drill-allow-lb-proxy-all-ports \
    --project="${PROJECT_ID}" \
    --network="${DR_VPC}" \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=all \
    --source-ranges="${DR_PROXY_SUBNET_CIDR}"
fi

# -------------------------------------------------------------------------
# Step 3d：JCP PSC 對接（jcp-release-api）
#   2026-09-11 實測踩雷：app 呼叫 http://jcp-release-api.jubo.health.internal 出現
#   "Name or service not known"——正式環境這個域名（psc-jcp-api-internal-domain 這個
#   private zone）只授權給 default VPC，dr-drill-vpc 完全不在授權清單內；就算加進授權，
#   這筆紀錄指到的 10.140.0.126 也是一個只在 default VPC 內部可路由的 PSC consumer
#   endpoint（default VPC 沒有跟 dr-drill-vpc peering），所以真正需要的是幫 DR 另外建
#   一組 PSC endpoint＋獨立 private zone，不是改既有共用設定。已確認 JCP 那邊的 service
#   attachment（psc-jcp-release-api-20260129，在 jubo-care-platform 這個專案）accept list
#   是用 project 授權（static-map-242406），不是限定特定 VPC，DR 另開一個 endpoint
#   不需要對方額外開權限。
# -------------------------------------------------------------------------
log "--- Step 3d: JCP PSC 對接（jcp-release-api） ---"
if gcloud compute addresses describe "${DR_JCP_PSC_NAME}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  log "${DR_JCP_PSC_NAME}（內部 IP）已存在，略過。"
else
  run gcloud compute addresses create "${DR_JCP_PSC_NAME}" \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --subnet="${DR_SUBNET}" \
    --addresses="${DR_JCP_PSC_ADDRESS}"
fi

if gcloud compute forwarding-rules describe "${DR_JCP_PSC_NAME}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  log "${DR_JCP_PSC_NAME}（PSC forwarding rule）已存在，略過。"
else
  run gcloud compute forwarding-rules create "${DR_JCP_PSC_NAME}" \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --network="${DR_VPC}" \
    --address="${DR_JCP_PSC_NAME}" \
    --target-service-attachment="${DR_JCP_SERVICE_ATTACHMENT}"
fi

if gcloud dns managed-zones describe "${DR_JCP_DNS_ZONE}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  log "${DR_JCP_DNS_ZONE}（private zone）已存在，略過。"
else
  run gcloud dns managed-zones create "${DR_JCP_DNS_ZONE}" \
    --project="${PROJECT_ID}" \
    --dns-name="${DR_JCP_DNS_NAME}" \
    --visibility=private \
    --networks="${DR_VPC}" \
    --description="DR 專用，只給 dr-drill-vpc 用，跟 default VPC 的 psc-jcp-api-internal-domain 分開"
fi

EXISTING_JCP_RECORD="$(gcloud dns record-sets list --zone="${DR_JCP_DNS_ZONE}" --project="${PROJECT_ID}" \
  --filter="name=${DR_JCP_RECORD_NAME} AND type=A" --format="value(name)" 2>/dev/null || true)"
if [[ -n "$EXISTING_JCP_RECORD" ]]; then
  log "${DR_JCP_RECORD_NAME} 這筆 A record 已存在，略過。"
else
  run gcloud dns record-sets create "${DR_JCP_RECORD_NAME}" \
    --project="${PROJECT_ID}" \
    --zone="${DR_JCP_DNS_ZONE}" \
    --type=A \
    --ttl=300 \
    --rrdatas="${DR_JCP_PSC_ADDRESS}"
fi

# -------------------------------------------------------------------------
# Step 4：GKE——先幫 pods/services 兩段 secondary range 加到 dr-drill-subnet，
#   再開一條 egress 防火牆放行 control-plane CIDR（dr-drill-vpc 預設 egress 拒絕＋白名單，
#   見 runbook「與住宿1.0演練的關係」一節），最後建 private cluster。
# -------------------------------------------------------------------------
log "--- Step 4: GKE ${DR_CLUSTER} ---"

EXISTING_SECONDARY_RANGES="$(gcloud compute networks subnets describe "${DR_SUBNET}" \
  --region="${REGION}" --project="${PROJECT_ID}" \
  --format="value(secondaryIpRanges[].rangeName)" 2>/dev/null || true)"

if [[ "$EXISTING_SECONDARY_RANGES" == *"${DR_GKE_PODS_RANGE_NAME}"* ]]; then
  log "${DR_SUBNET} 已經有 secondary range ${DR_GKE_PODS_RANGE_NAME}，略過。"
else
  run gcloud compute networks subnets update "${DR_SUBNET}" \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --add-secondary-ranges="${DR_GKE_PODS_RANGE_NAME}=${DR_GKE_PODS_RANGE_CIDR},${DR_GKE_SERVICES_RANGE_NAME}=${DR_GKE_SERVICES_RANGE_CIDR}"
fi

if gcloud compute firewall-rules describe "${DR_MASTER_CIDR_FIREWALL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  log "${DR_MASTER_CIDR_FIREWALL} 已存在，略過。"
else
  # ⚠️ 2026-09-11 實測踩雷：一開始只開 tcp:443，kubectl get/describe/apply 都正常
  # （這些走一般 kube-apiserver 通訊），但 kubectl logs/exec/port-forward 全部卡
  # "No agent available"——這幾個走的是 Konnectivity（control plane 反向連回 node
  # 的通道），node 端要能主動連到 control plane 的 tcp:8132，不是 443，兩個都要開。
  run gcloud compute firewall-rules create "${DR_MASTER_CIDR_FIREWALL}" \
    --project="${PROJECT_ID}" \
    --network="${DR_VPC}" \
    --direction=EGRESS \
    --action=ALLOW \
    --rules=tcp:443,tcp:8132 \
    --destination-ranges="${DR_MASTER_IPV4_CIDR}"
fi

# 見 common.sh 對 DR_GKE_INTERNAL_EGRESS_FIREWALL 的實測踩雷說明：既有的
# dr-drill-allow-egress-internal 沒涵蓋 pods/services range，導致 pod 連 cluster DNS
# 會被 deny-egress-default 擋掉。這條規則要在 cluster 建起來、pod 開始跑之前就先備妥。
#
# ⚠️ 2026-09-11 又補一個目的地：Cloud SQL 的 private IP 落在 PSA 保留的 range
# （dr-drill-psa-range，實測是 10.164.180.0/24，但這是 GCP 自動配的，不是我們自己選的
# 固定值，所以這裡用查詢的，不寫死），一樣不在原本這條規則涵蓋的 pods/services CIDR 內，
# 會被擋掉——症狀是 cloud-sql-proxy 一直印 "dial tcp <PSA range IP>:3307: i/o timeout"，
# app 的 DB health check 因此一直失敗、回 503。這條規則現在包含 3 段目的地：
# pods CIDR、services CIDR、PSA range CIDR。
PSA_RANGE_CIDR="$(gcloud compute addresses describe "${DR_PSA_RANGE_NAME}" --global --project="${PROJECT_ID}" \
  --format="value(address,prefixLength)" 2>/dev/null | awk '{print $1"/"$2}')"
if [[ -z "$PSA_RANGE_CIDR" ]]; then
  log "❌ 查不到 ${DR_PSA_RANGE_NAME} 的實際 CIDR，Step 1 的 PSA peering 可能還沒建好，無法繼續。"
  exit 1
fi
DR_GKE_INTERNAL_EGRESS_DESTINATIONS="${DR_GKE_PODS_RANGE_CIDR},${DR_GKE_SERVICES_RANGE_CIDR},${PSA_RANGE_CIDR}"

if gcloud compute firewall-rules describe "${DR_GKE_INTERNAL_EGRESS_FIREWALL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  EXISTING_DESTINATIONS="$(gcloud compute firewall-rules describe "${DR_GKE_INTERNAL_EGRESS_FIREWALL}" \
    --project="${PROJECT_ID}" --format="value(destinationRanges.list())" 2>/dev/null)"
  if [[ "$EXISTING_DESTINATIONS" == *"${PSA_RANGE_CIDR}"* ]]; then
    log "${DR_GKE_INTERNAL_EGRESS_FIREWALL} 已存在，且已涵蓋 ${PSA_RANGE_CIDR}，略過。"
  else
    log "${DR_GKE_INTERNAL_EGRESS_FIREWALL} 已存在，但沒涵蓋 PSA range（${PSA_RANGE_CIDR}），補上去。"
    run gcloud compute firewall-rules update "${DR_GKE_INTERNAL_EGRESS_FIREWALL}" \
      --project="${PROJECT_ID}" \
      --destination-ranges="${DR_GKE_INTERNAL_EGRESS_DESTINATIONS}"
  fi
else
  run gcloud compute firewall-rules create "${DR_GKE_INTERNAL_EGRESS_FIREWALL}" \
    --project="${PROJECT_ID}" \
    --network="${DR_VPC}" \
    --direction=EGRESS \
    --action=ALLOW \
    --rules=all \
    --destination-ranges="${DR_GKE_INTERNAL_EGRESS_DESTINATIONS}"
fi

if gcloud container clusters describe "${DR_CLUSTER}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  log "${DR_CLUSTER} 已存在，略過建立叢集。"
elif [[ "$GKE_MODE" == "standard" ]]; then
  log "GKE_MODE=standard，建 Standard 模式叢集（比照正式環境 ${RELEASE_CLUSTER} 規格）。"
  run gcloud container clusters create "${DR_CLUSTER}" \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --network="${DR_VPC}" \
    --subnetwork="${DR_SUBNET}" \
    --enable-ip-alias \
    --cluster-secondary-range-name="${DR_GKE_PODS_RANGE_NAME}" \
    --services-secondary-range-name="${DR_GKE_SERVICES_RANGE_NAME}" \
    --enable-private-nodes \
    --master-ipv4-cidr="${DR_MASTER_IPV4_CIDR}" \
    --machine-type="${GKE_MACHINE_TYPE}" \
    --disk-size="${GKE_DISK_SIZE_GB}" \
    --num-nodes=1 \
    --enable-autoscaling \
    --min-nodes="${GKE_MIN_NODES}" \
    --max-nodes="${GKE_MAX_NODES}" \
    --location-policy="${GKE_LOCATION_POLICY}" \
    --service-account="${DR_NODE_SA}" \
    --workload-pool="${PROJECT_ID}.svc.id.goog" \
    --managed-otel-scope=COLLECTION_AND_INSTRUMENTATION_COMPONENTS
else
  log "GKE_MODE=autopilot（預設），建 Autopilot 模式叢集——不用指定 machine type／node pool／autoscaling，GKE 自己管。"
  run gcloud container clusters create-auto "${DR_CLUSTER}" \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --network="${DR_VPC}" \
    --subnetwork="${DR_SUBNET}" \
    --cluster-secondary-range-name="${DR_GKE_PODS_RANGE_NAME}" \
    --services-secondary-range-name="${DR_GKE_SERVICES_RANGE_NAME}" \
    --enable-private-nodes \
    --master-ipv4-cidr="${DR_MASTER_IPV4_CIDR}" \
    --service-account="${DR_NODE_SA}" \
    --managed-otel-scope=COLLECTION_AND_INSTRUMENTATION_COMPONENTS
fi

# 2026-09-11 實測踩雷：正式環境 caring-tw 有 gke-managed-otel 這個 namespace（GKE Managed
# OpenTelemetry Collector），DR cluster 一開始建立時沒帶對應設定，這個 namespace 完全不存在。
# app 的 OpenTelemetry__EndPoint 設定指向 opentelemetry-collector.gke-managed-otel.svc.cluster.local:4317，
# 這幾個服務的 Serilog 只走 OTLP sink（沒有 Console fallback），collector 不存在導致 log 整個消失
# ——不是被防火牆擋、也不是 Cloud Logging 過濾掉，是从源頭就沒有東西可以送，kubectl logs 也是空的。
# 用 --managed-otel-scope 補上去；已經有的 cluster 也直接補一次（cluster 已經有這個 scope 時
# 這個 update 基本是 no-op，不用另外查現況）。
run gcloud container clusters update "${DR_CLUSTER}" \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --managed-otel-scope=COLLECTION_AND_INSTRUMENTATION_COMPONENTS

# 2026-09-09 實測踩雷：這個 cluster 建出來 masterAuthorizedNetworksConfig.enabled 是 true，
# 但 cidrBlocks 是空的——等於沒有任何來源 IP 能連 control plane 的公開端點，kubectl/helm
# 會全部卡在 timeout（`dial tcp <endpoint>:443: i/o timeout`）。這裡自動把「現在執行這支
# script 的機器」的對外 IP 加進白名單，跟既有的 CIDR 合併（不覆蓋掉別人已經加的）。
log "--- Step 4b: 授權目前機器的 IP 存取 GKE control plane ---"
MY_IP="$(detect_public_ip)"
if [[ -z "$MY_IP" ]]; then
  log "❌ 偵測不到目前機器的對外 IP，無法自動授權，請手動執行："
  log "   gcloud container clusters update ${DR_CLUSTER} --project=${PROJECT_ID} --region=${REGION} --enable-master-authorized-networks --master-authorized-networks=<你的IP>/32"
  exit 1
fi
log "偵測到目前機器的對外 IP：${MY_IP}"

EXISTING_MASTER_NETWORKS="$(gcloud container clusters describe "${DR_CLUSTER}" --project="${PROJECT_ID}" --region="${REGION}" \
  --format="json(masterAuthorizedNetworksConfig.cidrBlocks)" 2>/dev/null \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(','.join(b['cidrBlock'] for b in (d.get('masterAuthorizedNetworksConfig') or {}).get('cidrBlocks') or []))" 2>/dev/null || true)"

if [[ ",${EXISTING_MASTER_NETWORKS}," == *",${MY_IP}/32,"* ]]; then
  log "${MY_IP}/32 已經在 master-authorized-networks 白名單內，略過。"
else
  MERGED_MASTER_NETWORKS="${MY_IP}/32"
  if [[ -n "$EXISTING_MASTER_NETWORKS" ]]; then
    MERGED_MASTER_NETWORKS="${EXISTING_MASTER_NETWORKS},${MERGED_MASTER_NETWORKS}"
  fi
  run gcloud container clusters update "${DR_CLUSTER}" \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --enable-master-authorized-networks \
    --master-authorized-networks="${MERGED_MASTER_NETWORKS}"
fi

run gcloud container clusters get-credentials "${DR_CLUSTER}" \
  --project="${PROJECT_ID}" --region="${REGION}"

if [[ "$DRY_RUN" == "0" ]]; then
  check_kubectl_context "gke_${PROJECT_ID}_${REGION}_${DR_CLUSTER}"
fi

# -------------------------------------------------------------------------
# Step 5：先手動把 3 個 CRD 建起來，再單次 helm install 裝 ArgoCD 本體＋全部 apps.applications。
#
# ⚠️ 2026-09-09 實測踩雷，設計已改過一次：原本想用「兩階段 helm install，第一階段用
#   --set-json apps.applications={} 清空」來避免 CRD 剛建好、還沒 Established 就套用
#   Application 物件的 race condition。實際跑發現 --set-json/-f 都只會對 map 做「遞迴合併」，
#   一個空 map（{}）merge 到已經有幾十個 key 的 apps.applications 上，合併結果還是原本那個
#   完整的大 map（合併不會清空既有 key）——所以第一階段其實還是嘗試建出全部 Application 物件，
#   在 CRD 還不存在時整個失敗（"no matches for kind Application ... ensure CRDs are installed
#   first"）。map 這種結構本來就沒辦法透過 --set／-f 覆蓋成空，只能改成不靠 helm release 本身
#   的兩階段安裝，而是：
#     Step 5a：用 `helm template --set argo-cd.crds.install=true --show-only <crds 路徑>` 純本地
#              渲染出 3 個 CRD 的 manifest（不透過任何 release 追蹤），直接 kubectl apply。
#     Step 5b：單次 `helm install`，直接用 git 預設的 crds.install=false（CRD 已經存在，
#              這個 release 本來就不需要、也不應該再管它一次，否則會撞
#              "cannot be imported into the current release"）＋完整的 apps.applications，
#              一次建好 ArgoCD 本體與全部環境的 Application。
# -------------------------------------------------------------------------
log "--- Step 5a: 手動渲染並套用 3 個 ArgoCD CRD ---"

CRD_MANIFEST="$(helm template argocd "${ARGOCD_CHART_PATH}" \
  -f "${ARGOCD_CHART_PATH}/values.yaml" \
  -f "${ARGOCD_OVERRIDES_FILE}" \
  --set "argo-cd.crds.install=true" \
  --show-only 'charts/argo-cd/templates/crds/*')"

if [[ "$DRY_RUN" == "1" ]]; then
  log "[dry-run] kubectl apply --server-side --force-conflicts -f -（helm template 產生的 3 個 CRD manifest，內容略）"
else
  # ⚠️ 2026-09-09 實測踩雷：一般的 client-side `kubectl apply` 會把整份 manifest塞進
  # `kubectl.kubernetes.io/last-applied-configuration` 這個 annotation 裡，
  # `applicationsets.argoproj.io` 這個 CRD 本身的 schema 太大，塞進 annotation 後
  # 超過 K8s annotation 262144 bytes 的硬限制，導致 `apply` 失敗（"Too long"）。
  # 改用 --server-side（server-side apply）：用 managed fields 取代那個 annotation，
  # 不會有這個大小限制，這也是官方 argo-cd chart 文件對這幾個大型 CRD 建議的做法。
  # --force-conflicts 是為了保險：如果之前曾經用 client-side apply 建過（欄位管理者不同），
  # 重跑這裡也不會卡在 field-ownership 衝突。
  echo "$CRD_MANIFEST" | kubectl apply --server-side --force-conflicts -f -
  log "等待 ArgoCD 的 3 個 CRD Established..."
  # ⚠️ 2026-09-09 實測踩雷：把 3 個 CRD 名稱一次傳給同一個 `kubectl wait` 會不穩定，
  # 三個裡有一個 status.conditions 還沒被 populate（暫時是 nil 不是空陣列）時，
  # kubectl 會直接噴 `.status.conditions accessor error: <nil> is of the type <nil>,
  # expected []interface{}` 中止整個 wait，即使其他兩個已經真的 Established。
  # 改成每個 CRD 各自獨立呼叫一次 kubectl wait，各自用自己的 watch／timeout，不會互相干擾。
  for crd in applications.argoproj.io appprojects.argoproj.io applicationsets.argoproj.io; do
    kubectl wait --for=condition=Established --timeout=120s "crd/${crd}"
  done
fi

log "--- Step 5b: 建 argocd namespace ---"
run kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml
if [[ "$DRY_RUN" == "0" ]]; then
  kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
fi

# ArgoCD 要能 clone REPO_URL（private repo）需要一組 repository credential Secret，
# 正式環境是靠 argocd namespace 裡一個 argocd.argoproj.io/secret-type=repository 的 Secret
# （查證過 key 是 type/url/password/project），這個 Secret 本來就不在 git 版控內，
# DR cluster 要另外建一份指向 REPO_URL 的。PAT 一律從 DR_GITHUB_PAT_FILE 讀，不印到 log。
log "--- Step 5c: ArgoCD repository credential（${ARGOCD_REPO_CREDS_SECRET}） ---"
GITHUB_PAT="$(load_github_pat)"
if [[ "$DRY_RUN" == "1" ]]; then
  echo "[dry-run] kubectl create secret generic ${ARGOCD_REPO_CREDS_SECRET} -n ${ARGOCD_NAMESPACE} --from-literal=type=git --from-literal=url=${REPO_URL} --from-literal=project=default --from-literal=password=<PAT，不印出來> --dry-run=client -o yaml | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml"
else
  kubectl create secret generic "${ARGOCD_REPO_CREDS_SECRET}" -n "${ARGOCD_NAMESPACE}" \
    --from-literal=type=git \
    --from-literal=url="${REPO_URL}" \
    --from-literal=project=default \
    --from-literal=password="${GITHUB_PAT}" \
    --dry-run=client -o yaml \
    | kubectl label --local -f - "argocd.argoproj.io/secret-type=repository" -o yaml \
    | kubectl apply -f -
fi
unset GITHUB_PAT

log "--- Step 5d: helm install argocd（單次，CRD 已存在，git 預設 crds.install=false 不變） ---"
# 用 upgrade --install 而不是單純 install：前一次若曾經因為任何原因失敗過，
# 重跑這支 script 才不會卡在「release 名稱已存在」，可以安全地重複執行到成功為止。
HELM_INSTALL_CMD=(helm upgrade --install argocd "${ARGOCD_CHART_PATH}"
  --namespace "${ARGOCD_NAMESPACE}"
  -f "${ARGOCD_CHART_PATH}/values.yaml"
  -f "${ARGOCD_OVERRIDES_FILE}"
  --set-string "apps.global.repoURL=${REPO_URL}")
if [[ -n "$REPO_REVISION" ]]; then
  HELM_INSTALL_CMD+=(--set-string "apps.global.targetRevision=${REPO_REVISION}")
fi
run "${HELM_INSTALL_CMD[@]}"

log "=== Bootstrap 指令跑完 ==="
log "接下來（本 script 不自動做，見 runbook「為什麼故意留這些手動斷點」）："
log "  1. 操作者到 ArgoCD UI／CLI 手動 sync：${RELEASE_APPLICATIONS[*]}"
log "  2. 確認 ${DR_REDIS_VM} 的 redis 真的起得來（見 runbook 的 Redis 段落），不要只看 VM 是否 RUNNING；"
log "     內部 DNS hostname 是 ${DR_REDIS_VM}.${REDIS_ZONE}.c.${PROJECT_ID}.internal，"
log "     記得把這個填進 DR fork repo 的 values_release.yaml 的 Redis.ConnectionString"
log "  3. 需要外部 IP／admin 密碼時："
log "     kubectl -n ${ARGOCD_NAMESPACE} get svc argocd-server"
log "     kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
log "  4. DR 專用 GCLB（URL Map／backend-service／NEG／憑證）、PSC、DNS：本 script 不處理，見 runbook 對應章節"
