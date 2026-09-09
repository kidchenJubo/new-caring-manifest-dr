#!/usr/bin/env bash
# 在 7 個 -release 服務都手動 sync 完之後執行，驗證 pod／ArgoCD 健康狀況，
# 並且針對 caring-redis-drill 額外做連線測試（這是本 repo/住宿2.0 特有的驗證重點，
# 不能只看住宿1.0 那邊「nginx 容器正常」的驗證就假設 redis 也沒問題，原因見
# runbooks/disaster-recovery.md「Cloud SQL／Redis 怎麼獨立重建」一節）。
#
# TLS／GCLB／PSC／DNS 這幾塊目前先不展開自動化驗證（操作者指示先不處理這部分），
# 這裡只印出需要人工確認的提醒清單。
#
# ⚠️ Phase 2 草稿，尚未實際跑過。
#
# 用法：scripts/caring-dr-validate.sh [--execute]
#   不加 --execute：只做唯讀檢查＋印出會建立的除錯用 pod 指令，不會真的建立任何東西。
#   加 --execute：唯讀檢查 + 實際建立一個一次性 debug pod 測試 caring-redis-drill:6379 連線，測完自動清掉。

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
# shellcheck source=./caring-dr-common.sh
source "scripts/caring-dr-common.sh" "$@"

log "=== Caring DR Validate ==="

if [[ "$DRY_RUN" == "0" ]]; then
  check_kubectl_context "gke_${PROJECT_ID}_${REGION}_${DR_CLUSTER}"
fi

# -------------------------------------------------------------------------
# 1. ArgoCD Application 的 Sync／Health 狀態
# -------------------------------------------------------------------------
log "--- 1. ArgoCD Application 狀態 ---"
FAILED=0
for app in "${RELEASE_APPLICATIONS[@]}"; do
  status="$(kubectl get application "$app" -n "${ARGOCD_NAMESPACE}" \
    -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || echo "NotFound/NotFound")"
  if [[ "$status" != "Synced/Healthy" ]]; then
    log "  ✗ ${app}: ${status}"
    FAILED=1
  else
    log "  ✓ ${app}: ${status}"
  fi
done
if [[ "$FAILED" == "1" ]]; then
  log "⚠️ 有服務未達 Synced/Healthy，建議先處理完再往下驗證。"
fi

# -------------------------------------------------------------------------
# 2. 對應 namespace 的 Pod 是否都 Running
# -------------------------------------------------------------------------
log "--- 2. Pod 狀態 ---"
for app in "${RELEASE_APPLICATIONS[@]}"; do
  ns="$app"
  log "  namespace=$ns"
  kubectl get pod -n "$ns" 2>&1 | sed 's/^/    /'
done

# -------------------------------------------------------------------------
# 3. Cloud SQL DR instance 狀態
# -------------------------------------------------------------------------
log "--- 3. Cloud SQL ${DR_SQL_INSTANCE} ---"
gcloud sql instances describe "${DR_SQL_INSTANCE}" --project="${PROJECT_ID}" \
  --format="table(name,state,settings.tier,settings.availabilityType)" 2>&1 | sed 's/^/  /'

# -------------------------------------------------------------------------
# 4. Redis（${DR_REDIS_VM}）：VM 狀態＋redis 實際連線測試（這一步是本 repo 特有的重點，
#    住宿1.0 team 的驗證腳本不會幫你測這個）
# -------------------------------------------------------------------------
log "--- 4. Redis VM ${DR_REDIS_VM} ---"
if ! gcloud compute instances describe "${DR_REDIS_VM}" --zone="${REDIS_ZONE}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  log "  ⚠️ ${DR_REDIS_VM} 不存在，略過 redis 檢查——bootstrap 可能還沒跑完 Step 3。"
else
  gcloud compute instances describe "${DR_REDIS_VM}" --zone="${REDIS_ZONE}" --project="${PROJECT_ID}" \
    --format="table(name,status,networkInterfaces[0].networkIP)" 2>&1 | sed 's/^/  /'

  REDIS_INTERNAL_IP="$(gcloud compute instances describe "${DR_REDIS_VM}" --zone="${REDIS_ZONE}" \
    --project="${PROJECT_ID}" --format="value(networkInterfaces[0].networkIP)" 2>/dev/null || true)"

  if [[ -z "$REDIS_INTERNAL_IP" ]]; then
    log "  ⚠️ 查不到 ${DR_REDIS_VM} 的內部 IP，可能 VM 還沒建好，略過 redis 連線測試。"
  else
    log "  將從 DR cluster 建立一次性 debug pod，測試連到 ${REDIS_INTERNAL_IP}:6379。"
    DEBUG_POD="dr-validate-redis-check"
    DEBUG_CMD=(kubectl run "${DEBUG_POD}" --rm -i --restart=Never
      --image=redis:7-alpine --namespace=default
      --command -- redis-cli -h "${REDIS_INTERNAL_IP}" -p 6379 ping)
    if [[ "$DRY_RUN" == "1" ]]; then
      printf '[dry-run]'; printf ' %q' "${DEBUG_CMD[@]}"; printf '\n'
    else
      log "+ ${DEBUG_CMD[*]}"
      if "${DEBUG_CMD[@]}" 2>&1 | tee /dev/stderr | grep -q PONG; then
        log "  ✓ redis-cli PING 回應 PONG，${DR_REDIS_VM} 的 redis 正常。"
      else
        log "  ✗ redis-cli PING 沒有回應 PONG——檢查 docker 容器是否起來，也可能是 ${DR_REDIS_GKE_FIREWALL} 防火牆規則／${DR_REDIS_ACCESS_TAG} tag 沒加上。"
      fi
    fi
  fi
fi

# -------------------------------------------------------------------------
# 5. TLS／GCLB／PSC／DNS：先不自動化，只列提醒清單
# -------------------------------------------------------------------------
log "--- 5. 需要人工確認的項目（暫不自動化，見 runbook 對應章節） ---"
cat <<'EOF' >&2
  [ ] DR 專用 GCLB（URL Map／backend-service／NEG／健康檢查）是否建好、backend 是否 HEALTHY
  [ ] TLS 憑證：sso-release-dr/mobile-api-dr 沿用 caringcm2026-all；jcp-release-api-caring-dr.jubo.health 另外確認
  [ ] PSC：psc-jcp-release-api／jcp2-prod 對應方向是否需要在 dr-drill-vpc 重建，對面 project 是否配合
  [ ] DNS：-dr 網域是否已指向 DR 專用 GCLB 的外部 IP
EOF

log "=== Validate 跑完 ==="
