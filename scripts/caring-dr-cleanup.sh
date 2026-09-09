#!/usr/bin/env bash
# 演練全部驗證完成後，刪掉這次 bootstrap 建立的資源。依賴順序：
#   先刪 argocd-server 的 LoadBalancer Service（回收雲端 forwarding rule，避免孤兒資源）
#   → 刪 GKE cluster → 刪 Cloud SQL DR instance → 刪 Redis VM
#   → （預設保留，見下方）本 script 建立的防火牆規則
#   → （預設保留，需 --purge-network）dr-drill-subnet 的 secondary ranges／PSA peering／PSA range
#
# dr-drill-vpc／dr-drill-subnet／dr-drill-proxy-only／dr-drill-nat 本身不是本 script 建立的
# （操作者預先建好、住宿1.0 team 也共用），這個 script 永遠不會刪這幾個。
#
# Redis VM（caring-redis-drill）完全是本 script 自己建立、不含任何 prod 資料，直接刪掉。
#
# ⚠️ 2026-09-09 跟操作者確認：本 script 建立的防火牆規則（下方三條）一律不刪，
# 即使是本 script 自己建的也一樣——這幾條規則只影響 dr-drill-vpc 內部（不影響其他
# VPC／正式環境），留著風險低，且省下下次重跑演練時要重建防火牆的步驟。
#
# TLS／GCLB／PSC／DNS 這幾塊本次 bootstrap 沒有自動建立（操作者指示先不處理），
# 這裡也不處理對應的刪除，只在最後列提醒。
#
# ⚠️ Phase 2 草稿，尚未實際跑過。
#
# 用法：
#   scripts/caring-dr-cleanup.sh [--purge-network] [--execute]
#     不加 --execute：只列出會刪什麼，不會真的刪。
#     --purge-network：連同 secondary ranges／PSA peering／PSA range 一起刪（預設保留，
#       因為重建這幾個比重建 compute 資源麻煩，且不像 VM/cluster 一樣持續計費）。
#       不影響防火牆規則——防火牆規則無論如何都不會被這個 script 刪除。

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=./caring-dr-common.sh
source "scripts/caring-dr-common.sh" "$@"

PURGE_NETWORK=0
for arg in "$@"; do
  case "$arg" in
    --purge-network) PURGE_NETWORK=1 ;;
    --execute) ;;
    *) log "未知參數：$arg"; exit 1 ;;
  esac
done

log "=== Caring DR Cleanup ==="
log "DRY_RUN=$DRY_RUN　PURGE_NETWORK=$PURGE_NETWORK"

log "以下資源將被刪除："
log "  - GKE cluster: ${DR_CLUSTER}"
log "  - Cloud SQL instance: ${DR_SQL_INSTANCE}"
log "  - Redis VM: ${DR_REDIS_VM}"
if [[ "$PURGE_NETWORK" == "1" ]]; then
  log "  - （--purge-network）dr-drill-subnet 的 secondary ranges：${DR_GKE_PODS_RANGE_NAME}, ${DR_GKE_SERVICES_RANGE_NAME}"
  log "  - （--purge-network）PSA peering／range：${DR_PSA_RANGE_NAME}"
fi
log "不會刪除："
log "  - dr-drill-vpc／dr-drill-subnet／dr-drill-proxy-only／dr-drill-nat（不是本 script 建立的共用資源）"
log "  - 防火牆規則: ${DR_MASTER_CIDR_FIREWALL}, ${DR_GKE_INTERNAL_EGRESS_FIREWALL}, ${DR_REDIS_GKE_FIREWALL}（操作者指示保留，只影響 dr-drill-vpc，風險低）"

confirm "確定要開始刪除以上資源嗎？"

# -------------------------------------------------------------------------
# 1. argocd-server 若曝露成 LoadBalancer，先刪這個 Service 回收雲端 forwarding rule／外部 IP，
#    避免叢集刪掉後留下孤兒資源（見 runbook「為什麼故意留這些手動斷點」一節提醒）。
# -------------------------------------------------------------------------
log "--- 1. 刪除 argocd-server LoadBalancer Service ---"
if [[ "$DRY_RUN" == "1" ]]; then
  run kubectl delete svc argocd-server -n "${ARGOCD_NAMESPACE}" --ignore-not-found
elif kubectl_context_matches "gke_${PROJECT_ID}_${REGION}_${DR_CLUSTER}"; then
  run kubectl delete svc argocd-server -n "${ARGOCD_NAMESPACE}" --ignore-not-found
else
  log "  kubectl context 對不上 ${DR_CLUSTER}（cluster 可能已經不存在，或還沒切過 context），略過這步，繼續刪其他資源。"
fi

# -------------------------------------------------------------------------
# 2. GKE cluster——先唯讀檢查是否存在，不存在就略過，避免對著已經不在的資源送出
#    delete 指令（GCP 對不存在的資源，視呼叫者權限不同，有時回 PERMISSION_DENIED
#    而不是 NOT_FOUND，直接送 delete 容易看到誤導性的錯誤訊息）。下面幾個資源同樣邏輯。
# -------------------------------------------------------------------------
log "--- 2. GKE cluster ${DR_CLUSTER} ---"
if gcloud container clusters describe "${DR_CLUSTER}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  run gcloud container clusters delete "${DR_CLUSTER}" \
    --project="${PROJECT_ID}" --region="${REGION}" --quiet
else
  log "  ${DR_CLUSTER} 不存在，略過。"
fi

# -------------------------------------------------------------------------
# 3. Cloud SQL DR instance
# -------------------------------------------------------------------------
log "--- 3. Cloud SQL ${DR_SQL_INSTANCE} ---"
if gcloud sql instances describe "${DR_SQL_INSTANCE}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  run gcloud sql instances delete "${DR_SQL_INSTANCE}" \
    --project="${PROJECT_ID}" --quiet
else
  log "  ${DR_SQL_INSTANCE} 不存在，略過。"
fi

# -------------------------------------------------------------------------
# 4. Redis：caring-redis-drill 完全是本 script 自建，直接刪
# -------------------------------------------------------------------------
log "--- 4. Redis VM ${DR_REDIS_VM} ---"
if gcloud compute instances describe "${DR_REDIS_VM}" --zone="${REDIS_ZONE}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  run gcloud compute instances delete "${DR_REDIS_VM}" \
    --project="${PROJECT_ID}" --zone="${REDIS_ZONE}" --quiet
else
  log "  ${DR_REDIS_VM} 不存在，略過。"
fi

# -------------------------------------------------------------------------
# 5. 防火牆規則——2026-09-09 跟操作者確認：先不刪，即使是本 script 自己建的也一樣。
#    這幾條規則只影響 dr-drill-vpc 內部（不影響其他 VPC／正式環境），留著風險低，
#    且能省下下次重跑演練時重建防火牆規則的步驟。
# -------------------------------------------------------------------------
log "--- 5. 防火牆規則：略過，保留 ${DR_MASTER_CIDR_FIREWALL}／${DR_GKE_INTERNAL_EGRESS_FIREWALL}／${DR_REDIS_GKE_FIREWALL}（只影響 dr-drill-vpc，風險低，操作者指示先留著） ---"

# -------------------------------------------------------------------------
# 6.（選擇性）secondary ranges／PSA peering／PSA range
# -------------------------------------------------------------------------
if [[ "$PURGE_NETWORK" == "1" ]]; then
  log "--- 6. secondary ranges／PSA peering／range（--purge-network） ---"

  EXISTING_SECONDARY_RANGES="$(gcloud compute networks subnets describe "${DR_SUBNET}" \
    --region="${REGION}" --project="${PROJECT_ID}" \
    --format="value(secondaryIpRanges[].rangeName)" 2>/dev/null || true)"
  if [[ "$EXISTING_SECONDARY_RANGES" == *"${DR_GKE_PODS_RANGE_NAME}"* ]]; then
    run gcloud compute networks subnets update "${DR_SUBNET}" \
      --project="${PROJECT_ID}" --region="${REGION}" \
      --remove-secondary-ranges="${DR_GKE_PODS_RANGE_NAME},${DR_GKE_SERVICES_RANGE_NAME}"
  else
    log "  ${DR_SUBNET} 沒有 ${DR_GKE_PODS_RANGE_NAME} 這個 secondary range，略過。"
  fi

  if gcloud services vpc-peerings list --project="${PROJECT_ID}" --network="${DR_VPC}" \
    --format="value(peering)" 2>/dev/null | grep -q "servicenetworking-googleapis-com"; then
    run gcloud services vpc-peerings delete \
      --project="${PROJECT_ID}" \
      --service=servicenetworking.googleapis.com \
      --network="${DR_VPC}" --quiet
  else
    log "  ${DR_VPC} 沒有 servicenetworking.googleapis.com 的 vpc-peering，略過。"
  fi

  if gcloud compute addresses describe "${DR_PSA_RANGE_NAME}" --global --project="${PROJECT_ID}" >/dev/null 2>&1; then
    run gcloud compute addresses delete "${DR_PSA_RANGE_NAME}" \
      --project="${PROJECT_ID}" --global --quiet
  else
    log "  ${DR_PSA_RANGE_NAME} 不存在，略過。"
  fi
else
  log "--- 6. 略過（未帶 --purge-network，保留 secondary ranges／PSA peering／range） ---"
fi

log "=== Cleanup 指令跑完 ==="
log "仍需人工確認（本 script 不處理，操作者指示先不展開這幾塊的自動化）："
log "  [ ] DR 專用 GCLB（URL Map／backend-service／NEG／憑證／forwarding rule）是否有殘留"
log "  [ ] -dr 的 DNS 記錄是否需要移除"
log "  [ ] 若 DR 專用 target-https-proxy 有引用正式環境的 caringcm2026-all 憑證，"
log "      務必先刪掉這個 target-proxy，否則會卡住正式環境之後要輪替這張憑證"
