#!/usr/bin/env bash
# 共用變數與工具函式，被 caring-dr-bootstrap.sh / caring-dr-validate.sh / caring-dr-cleanup.sh 三支 source。
# 細節與決策原因見 runbooks/disaster-recovery.md，這裡只放「要執行什麼」，不重複「為什麼」。
#
# ⚠️ 這三支 script 都還是 Phase 2 草稿，尚未在真實 dr-drill-vpc 跑過完整流程，
#   第一次使用務必先用預設的 dry-run 模式（不加 --execute）過一遍，確認印出來的指令符合預期。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---- 專案／區域（不可變更，見 .claude/gcp-env.md「AI 允許查詢的 GCP Projects」） ----
PROJECT_ID="static-map-242406"
REGION="asia-east1"

# ---- DR 網路（操作者已建好，見 runbooks/disaster-recovery.md「dr-drill-vpc 目前已經備妥的部分」） ----
DR_VPC="dr-drill-vpc"
DR_SUBNET="dr-drill-subnet"
DR_PROXY_SUBNET="dr-drill-proxy-only"
DR_PROXY_SUBNET_CIDR="10.251.0.0/24"

# ---- Cloud SQL ----
RELEASE_SQL_INSTANCE="caring-release-pg"
DR_SQL_INSTANCE="caring-release-pg-dr"
SQL_DATABASE_VERSION="POSTGRES_17"
SQL_TIER="db-custom-4-16384"
SQL_AVAILABILITY_TYPE="REGIONAL"
# 2026-09-09 實測：gcloud 若不帶 --edition 會預設用 ENTERPRISE_PLUS，這個 edition 不接受
# db-custom-N-M 這種傳統 tier 命名（要求 db-perf-optimized-N-*），導致建立失敗。
# 查證過 caring-release-pg 本身是 ENTERPRISE edition，這裡明確指定對齊，維持 db-custom-4-16384 有效。
SQL_EDITION="ENTERPRISE"

# Cloud SQL 走 Private Service Access，需要在 dr-drill-vpc 裡保留一段 IP range 並建立 peering
# （見 runbooks/disaster-recovery.md「dr-drill-vpc 目前沒有 Private Services Access peering」）。
# 這段 range 純粹是 DR 專用，跟正式環境的 cloud-ids-default-ips（10.7.0.0/16）無關，不會撞名。
DR_PSA_RANGE_NAME="dr-drill-psa-range"
DR_PSA_RANGE_PREFIX_LENGTH="24"

# ---- Redis VM ----
# 策略（2026-09-09 跟操作者確認、簡化過一次）：**一律**自己建一台全新、乾淨的 VM
# （`caring-redis-drill`），裝 Docker＋跑一個 docker redis 容器，純粹只為了讓本 repo
# （住宿2.0）的 GKE pods 有 redis 可用——不含 prod 資料、不依賴 samba-drill。
# 不再偵測／沿用住宿1.0 team 的 jubo-mqtt-drill（先前版本會先檢查那台是否存在，
# 現在直接跳過這個判斷，永遠用本 repo 自己的 caring-redis-drill）。
REDIS_ZONE="${REGION}-b"
REDIS_MACHINE_TYPE="e2-medium"

DR_REDIS_VM="caring-redis-drill"
DR_REDIS_IMAGE_FAMILY="debian-12"
DR_REDIS_IMAGE_PROJECT="debian-cloud"

# 本 repo（住宿2.0）GKE pods 需要連到 redis:6379，用獨立 tag／防火牆規則放行 GKE pod range。
DR_REDIS_ACCESS_TAG="caring-jubo-mqtt-access"
DR_REDIS_GKE_FIREWALL="dr-drill-redis-gke-access"

# ---- SQL Server drill VM（CHomeConnection／OldCaringConnection 用，既有資源，不是本 script 建的） ----
# 2026-09-11 實測踩雷：這台 VM（sql-server-drill，10.250.0.193）已經存在，是操作者／住宿1.0
# 團隊事先建好的，本 script 不建立、不刪除，只補它跟 GKE pod 之間缺的那條防火牆
# （見 caring-dr-bootstrap.sh 對應段落與 runbook 的詳細說明）。
DR_SQLSERVER_VM="sql-server-drill"
DR_SQLSERVER_ZONE="${REGION}-b"
DR_SQLSERVER_TAG="sql-server-drill"
DR_SQLSERVER_GKE_FIREWALL="dr-drill-sql-server-gke-access"
DR_SQLSERVER_PORTS="9900-9999"

# ---- JCP PSC 對接（jcp-release-api，2026-09-11 手動建立驗證過後補進 script） ----
# app 呼叫 http://jcp-release-api.jubo.health.internal 走的是 PSC（Private Service Connect），
# 正式環境那筆紀錄／endpoint 只在 default VPC 內有效，dr-drill-vpc 需要自己一組獨立的
# PSC consumer endpoint＋private DNS zone，不能沿用／不能改正式環境那份共用設定
# （細節見 runbooks/disaster-recovery.md）。IP 10.250.0.200 是手動測試時選定、目前已在用的值，
# 落在 dr-drill-subnet（10.250.0.0/24）內，跟現有的 sql-server-drill（.193）等資源不衝突。
DR_JCP_PSC_NAME="dr-drill-psc-jcp-release-api"
DR_JCP_PSC_ADDRESS="10.250.0.200"
DR_JCP_SERVICE_ATTACHMENT="https://www.googleapis.com/compute/v1/projects/jubo-care-platform/regions/asia-east1/serviceAttachments/psc-jcp-release-api-20260129"
DR_JCP_DNS_ZONE="dr-drill-jubo-health-internal"
DR_JCP_DNS_NAME="jubo.health.internal."
DR_JCP_RECORD_NAME="jcp-release-api.jubo.health.internal."

# ---- GKE ----
RELEASE_CLUSTER="caring-tw"
DR_CLUSTER="caring-tw-dr"

# 2026-09-09 跟操作者確認：預設用 Autopilot 模式（不用猜 machine type／node pool／
# autoscaling 怎麼配，GKE 自己管），只有明確設定 GKE_MODE=standard 才走 Standard 模式
# （跟正式環境 caring-tw 一樣的規格，見下面幾個 GKE_* 變數）。
# 用法：GKE_MODE=standard scripts/caring-dr-bootstrap.sh --execute
GKE_MODE="${GKE_MODE:-autopilot}"

# 以下只有 GKE_MODE=standard 時才會用到。
GKE_MACHINE_TYPE="custom-4-8192"
GKE_DISK_SIZE_GB="30"
GKE_MIN_NODES="1"
GKE_MAX_NODES="10"
GKE_LOCATION_POLICY="BALANCED"

# GKE 需要的兩段 secondary range（pods/services），加在 dr-drill-subnet 上。
# 選這兩段是因為跟 dr-drill-subnet（10.250.0.0/24）、dr-drill-proxy-only（10.251.0.0/24）、
# 上面的 PSA range 都不重疊——建立前 bootstrap script 仍會先用唯讀指令查一次現況再決定要不要建立，
# 若操作者已經另外規劃了其他 CIDR，請直接改這裡的變數。
DR_GKE_PODS_RANGE_NAME="dr-drill-gke-pods"
DR_GKE_PODS_RANGE_CIDR="10.252.0.0/16"
DR_GKE_SERVICES_RANGE_NAME="dr-drill-gke-services"
DR_GKE_SERVICES_RANGE_CIDR="10.253.0.0/20"

# ⚠️ 2026-09-09 實測踩雷：dr-drill-vpc 既有的 dr-drill-allow-egress-internal 只放行
# 10.250.0.0/24（主要 subnet）／10.251.0.0/24（proxy-only），沒有涵蓋上面這兩段
# 後來才加的 pods/services range——導致 pod-to-pod、甚至 pod 連 cluster DNS（kube-dns
# ClusterIP，落在 services range）全部被 dr-drill-deny-egress-default 擋掉，
# 症狀是 ArgoCD 出現 `dial udp <kube-dns-ip>:53: i/o timeout` 這類 DNS lookup 失敗。
# 這裡另開一條 egress 規則涵蓋這兩段，不去動既有的 dr-drill-allow-egress-internal
# （那是住宿1.0 team 建的共用規則，不確定改了會不會影響對方）。
DR_GKE_INTERNAL_EGRESS_FIREWALL="dr-drill-allow-egress-gke-pods-services"

# Private cluster 的 control-plane CIDR，必須是沒被用過的 /28。
# 選好之後要在建 cluster 前，先幫這段開一條 egress 防火牆規則（見 bootstrap 的 ensure_master_cidr_egress）。
DR_MASTER_IPV4_CIDR="172.16.10.0/28"
DR_MASTER_CIDR_FIREWALL="dr-drill-allow-egress-gke-master"

# GKE node 使用的 service account——沿用住宿1.0 team 為 4 台 drill VM 建的 dr-drill@，
# 前提是操作者已經補上 artifactregistry.reader（見 runbook「還沒做的前置準備」清單，
# 這件事屬於 gcloud iam 黑名單，這三支 script 都不會、也不能幫你做這一步）。
DR_NODE_SA="dr-drill@${PROJECT_ID}.iam.gserviceaccount.com"

# ---- ArgoCD ----
ARGOCD_NAMESPACE="argocd"
ARGOCD_CHART_PATH="Infrastructure/argocd"
ARGOCD_OVERRIDES_FILE="scripts/caring-dr-argocd-overrides.yaml"

# DR 專用 GitHub fork repo（2026-09-09 操作者已建立＋push 完成）。
# 之後若重建／改用別的 fork repo，把這裡改掉即可，不用再靠 CLI 參數傳——
# 也可用環境變數 REPO_URL 覆蓋，不想改檔案的話執行前 export REPO_URL=... 即可。
REPO_URL="${REPO_URL:-https://github.com/kidchenJubo/new-caring-manifest-dr.git}"
REPO_REVISION="${REPO_REVISION:-main}"

# ArgoCD 要能 clone REPO_URL，需要一組 repository credential（正式環境的 new-caring-manifest
# 是 private repo，ArgoCD 是靠 argocd namespace 裡一個 type=repository 的 Secret 認證的，
# 這個 Secret 本來就不在 git 版控內，DR cluster 需要另外建一份指向 DR fork repo 的）。
# PAT 放在專案下的 .caring-dr/github-token.txt（單行純文字，建議 chmod 600）——
# 這個路徑已經加進 .gitignore（見 .gitignore「DR script 本機用的密鑰檔」），不會被 commit，
# 但仍然是明碼檔案，不要透過其他管道（Slack／email）傳這個檔案本身。
# 路徑可用環境變數 DR_GITHUB_PAT_FILE 覆蓋。
DR_GITHUB_PAT_FILE="${DR_GITHUB_PAT_FILE:-$REPO_ROOT/.caring-dr/github-token.txt}"
ARGOCD_REPO_CREDS_SECRET="argocd-repo-dr-fork"

# 需要靠 DR 還原、且要手動 sync 的 7 個 -release 服務（ArgoCD Application 名稱）。
# ⚠️ 2026-09-09 查證，`new-caring-line-api-release` 目前在正式環境是 OutOfSync/Missing，
#   見 runbooks/disaster-recovery.md「⚠️ release 環境現況」——是否要從這份清單移除，
#   或者先手動 sync 正式環境，需要操作者決定，這裡先照文件原本的 7 個列出。
RELEASE_APPLICATIONS=(
  "new-caring-web-api-release"
  "new-caring-mobile-api-release"
  "new-caring-web-release"
  "new-caring-web-page-release"
  "new-caring-event-consumer-release"
  "caree-notification-release"
  "new-caring-line-api-release"
)

# ---- 共用工具函式 ----

# ---- GCLB backend-service（DR 專用，接上外部 LB 用；目前只涵蓋操作者已開的兩個 -release 服務） ----
# 命名刻意跟 NEG 名稱保持一致（見 5 個 chart 的 templates/service.yaml 裡 -dr-80 NEG 命名說明），
# 一律用 <app>-<env>-dr-80，backend-service 名稱＝NEG 名稱好對應——不沿用正式環境部分服務
# backend-service 名稱不一致的舊慣例（例如 new-caring-web-release 這個正式資源沒有 -80 尾巴，
# 是歷史因素，跟它的 NEG 名稱 new-caring-web-release-80 對不上，DR 這裡不重蹈覆轍）。
DR_BACKEND_HEALTH_CHECK="k8s-health-check-new-caring"   # 沿用正式環境共用的 regional health check，不重複建立
DR_BACKEND_ENV="release"
DR_BACKEND_APPS_DEFAULT=("new-caring-web-api" "new-caring-web")
DR_BACKEND_ZONES=(a b c)

# lb-drill 是住宿1.0team的資源，只在存在時才會嘗試接線（見 caring-dr-backend-add.sh），
# 這裡只放名稱常數，不代表這兩個資源一定存在。可用環境變數覆蓋，方便測試時指到別的 url-map。
DR_LB_URLMAP="${DR_LB_URLMAP:-lb-drill}"
DR_LB_PATH_MATCHER="${DR_LB_PATH_MATCHER:-drill-urlmatcher}"

DRY_RUN=1
for _arg in "$@"; do
  case "$_arg" in
    --execute) DRY_RUN=0 ;;
  esac
done

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

# run <command...>：dry-run 模式只印出指令，--execute 才真的執行。
# 所有會「建立/修改/刪除」雲端或叢集資源的指令都必須透過這個函式呼叫，
# 唯讀的 describe/list/get 可以直接呼叫（不需要 dry-run 保護）。
run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
  else
    log "+ $*"
    "$@"
  fi
}

# confirm <提示文字>：--execute 模式下，執行破壞性操作前要求操作者手動輸入 yes。
confirm() {
  local prompt="$1"
  if [[ "$DRY_RUN" == "1" ]]; then
    return 0
  fi
  read -r -p "$prompt [yes/N] " reply
  if [[ "$reply" != "yes" ]]; then
    log "操作者未輸入 yes，中止。"
    exit 1
  fi
}

# check_gcloud_project：只做唯讀查詢，確認目前 gcloud 有沒有登入、且不依賴 gcloud config 的 project 預設值
# （見 CLAUDE.md／gcp-env.md：所有 gcloud 指令一律明確帶 --project，不依賴預設值）。
check_gcloud_account() {
  local account
  account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -n1)
  if [[ -z "$account" ]]; then
    log "⚠️ gcloud 目前沒有已登入的帳號，請先 gcloud auth login（或 gcloud auth activate-service-account）。"
    exit 1
  fi
  log "目前 gcloud 帳號：$account"
}

# detect_public_ip：偵測目前這台機器的對外 IP（用來加進 GKE master-authorized-networks 白名單），
# 依序試幾個服務，第一個成功的就回傳，全部失敗回傳空字串。
detect_public_ip() {
  local ip svc
  for svc in "https://ifconfig.me" "https://api.ipify.org" "https://icanhazip.com"; do
    ip="$(curl -s --max-time 5 "$svc" 2>/dev/null | tr -d '[:space:]')"
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      echo "$ip"
      return 0
    fi
  done
  echo ""
}

# kubectl_context_matches <expected-context>：唯讀比對，不會 exit，只回傳 true/false，
# 給「context 不符時想繼續往下跑、不想中止整支 script」的呼叫端用（例如 cleanup.sh）。
kubectl_context_matches() {
  local expected="$1"
  local current
  current=$(kubectl config current-context 2>/dev/null || true)
  [[ "$current" == "$expected" ]]
}

# check_kubectl_context <expected-context>：執行任何 kubectl 前，先確認 context 是預期值，不符就停止。
# ⚠️ 這個函式內部呼叫 exit，不是 return——呼叫端用 `check_kubectl_context ... || true`
# 沒辦法讓 script 繼續往下跑，`exit` 會直接結束整個 process，`||` 完全攔不住。
# 想要「不符就跳過、不要中止」的行為，請用上面的 kubectl_context_matches。
check_kubectl_context() {
  local expected="$1"
  local current
  current=$(kubectl config current-context 2>/dev/null || true)
  if [[ "$current" != "$expected" ]]; then
    log "⚠️ kubectl context 目前是 [$current]，預期是 [$expected]。"
    log "  請先執行：gcloud container clusters get-credentials ${expected##*_} --region ${REGION} --project ${PROJECT_ID}"
    exit 1
  fi
}

# load_github_pat：從本機檔案讀 PAT，不接受用參數／環境變數直接傳明碼（避免留在 shell history）。
# 回傳值透過 echo，呼叫端用 pat="$(load_github_pat)" 接。
load_github_pat() {
  if [[ ! -f "$DR_GITHUB_PAT_FILE" ]]; then
    log "❌ 找不到 GitHub PAT 檔案：$DR_GITHUB_PAT_FILE"
    log "   請先把有 REPO_URL（$REPO_URL）讀取權限的 PAT 存成這個檔案（單行純文字，不要有換行），"
    log "   或用 DR_GITHUB_PAT_FILE=<path> 指到你放的位置。"
    exit 1
  fi
  local perm
  perm=$(stat -c "%a" "$DR_GITHUB_PAT_FILE" 2>/dev/null || stat -f "%A" "$DR_GITHUB_PAT_FILE" 2>/dev/null || echo "")
  if [[ -n "$perm" && "$perm" != "600" && "$perm" != "400" ]]; then
    log "⚠️ $DR_GITHUB_PAT_FILE 權限是 $perm，建議 chmod 600 這個檔案。"
  fi
  tr -d '\n' < "$DR_GITHUB_PAT_FILE"
}

# check_github_repo_exists <repo-url>：bootstrap 任何 GCP 資源之前，先確認 DR fork repo 真的存在，
# 用 GitHub API（而不是 git ls-remote）是因為 repo 是 private，anonymous 一定拿到 404，
# 這裡直接用同一組 PAT 打 API 確認「存在且這組 PAT 讀得到」。
check_github_repo_exists() {
  local repo_url="$1" pat owner_repo api_status
  pat="$(load_github_pat)"
  owner_repo="$(echo "$repo_url" | sed -E 's#^https://github.com/##; s#\.git$##')"
  api_status="$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token ${pat}" \
    "https://api.github.com/repos/${owner_repo}")"
  if [[ "$api_status" != "200" ]]; then
    log "❌ 查不到 GitHub repo ${owner_repo}（API 回應 ${api_status}）。"
    log "   請確認：(1) 這個 repo 是否已經建立、(2) REPO_URL 是否正確、(3) ${DR_GITHUB_PAT_FILE} 裡的 PAT 是否有讀取這個 repo 的權限。"
    exit 1
  fi
  log "GitHub repo ${owner_repo} 存在，且目前這組 PAT 讀得到。"
}
