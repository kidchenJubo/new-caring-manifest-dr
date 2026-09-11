#!/usr/bin/env bash
# 建立／補齊 DR 環境的 GCLB backend-service，並把對應 NEG 掛上去。
#
# 背景：本 repo 的 Helm chart 只負責讓 GKE NEG controller 建出 NEG（見 templates/service.yaml
# 的 cloud.google.com/neg 註解），backend-service 本身跟 GCLB url-map 的串接一律是操作者手動
# 執行（對齊正式環境 Shell/create_lb_backend_services.sh 的既有慣例），這支 script 就是
# DR 版本的等價操作，差別只在名稱一律加 -dr 字尾避免跟正式環境撞名。
#
# 用法：
#   scripts/caring-dr-backend-add.sh                          # 預設兩個服務：new-caring-web-api, new-caring-web
#   scripts/caring-dr-backend-add.sh --app new-caring-web-page # 指定單一或多個服務（可重複帶 --app）
#   scripts/caring-dr-backend-add.sh --execute                # 預設是 dry-run，加這個才真的執行
#
# 這支 script 是 idempotent：backend-service／NEG 掛載都會先查現況再決定要不要建立，
# 已經存在／已經掛好的直接略過，不會重複建立或報錯。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/caring-dr-common.sh" "$@"

APPS=()
for ((i = 1; i <= $#; i++)); do
  arg="${!i}"
  if [[ "$arg" == "--app" ]]; then
    j=$((i + 1))
    if [[ $j -gt $# ]]; then
      log "❌ --app 後面缺參數值。"
      exit 1
    fi
    APPS+=("${!j}")
  fi
done
if [[ ${#APPS[@]} -eq 0 ]]; then
  APPS=("${DR_BACKEND_APPS_DEFAULT[@]}")
fi

log "=== caring-dr-backend-add：${APPS[*]}（env=${DR_BACKEND_ENV}） ==="
check_gcloud_account

# lb-drill 是住宿1.0team自己的資源，不是本 repo／本 script 管的，演練結束後對方可能會把它砍掉
# （連同 forwarding-rule／target-proxy 一起）。這裡只做唯讀檢查＋警告，不會阻擋 backend-service
# 本身的建立——這兩件事沒有強依賴關係，backend-service 沒有 lb-drill 也能先建好、放著，
# 只是在 lb-drill 重建＋route rule 重新貼上去之前不會有任何流量進來。
if ! gcloud compute url-maps describe "${DR_LB_URLMAP}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  log "⚠️ 查不到 ${DR_LB_URLMAP} 這個 url-map（住宿1.0 的資源，演練結束後可能已經被對方刪掉）。"
  log "   這支 script 還是會繼續建立／補齊 backend-service，但要注意：在 ${DR_LB_URLMAP} 重建、"
  log "   且 ${DR_LB_PATH_MATCHER} 的 route rule 重新貼上 -dr-80 這幾個 backend-service 之前，"
  log "   不會有任何流量能連進來，見 runbooks/disaster-recovery.md「lb-drill url-map 接線」一節。"
fi

if ! gcloud compute health-checks describe "${DR_BACKEND_HEALTH_CHECK}" \
  --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  log "❌ 查不到共用 health check ${DR_BACKEND_HEALTH_CHECK}（region ${REGION}），無法建立 backend-service。"
  log "   這是正式環境本來就有的共用資源，理論上不需要另外建，請確認名稱／region 是否正確。"
  exit 1
fi

for app in "${APPS[@]}"; do
  bs_name="${app}-${DR_BACKEND_ENV}-dr-80"
  neg_name="${bs_name}"

  log "--- ${app} → backend-service ${bs_name} ---"

  if gcloud compute backend-services describe "${bs_name}" \
    --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    log "${bs_name} 已存在，略過建立。"
  else
    run gcloud compute backend-services create "${bs_name}" \
      --project="${PROJECT_ID}" \
      --region="${REGION}" \
      --protocol=HTTP \
      --load-balancing-scheme=EXTERNAL_MANAGED \
      --health-checks="${DR_BACKEND_HEALTH_CHECK}" \
      --health-checks-region="${REGION}"
  fi

  existing_groups=""
  if [[ "$DRY_RUN" == "0" ]]; then
    # 2026-09-11 實測踩雷：gcloud 的 value() formatter 對多個結果是用分號 `;` 接在同一行，
    # 不是換行——原本用 `grep "...$"`（行尾錨點）比對，導致同一行裡除了最後一個 zone 以外
    # 都比對不到，誤判成「還沒掛」而重複 add-backend，噴 Duplicate network endpoint groups
    # 的錯誤。這裡先把 `;` 轉成換行，讓每個 zone 各自一行，行尾錨點才會正確生效。
    existing_groups="$(gcloud compute backend-services describe "${bs_name}" \
      --project="${PROJECT_ID}" --region="${REGION}" \
      --format="value(backends[].group)" 2>/dev/null | tr ';' '\n' || true)"
  fi

  for zone in "${DR_BACKEND_ZONES[@]}"; do
    full_zone="${REGION}-${zone}"

    if ! gcloud compute network-endpoint-groups describe "${neg_name}" \
      --zone="${full_zone}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
      log "  ${full_zone}：查不到 NEG ${neg_name}，略過這個 zone（GKE NEG controller 可能還沒建出來，或這個服務根本沒跑在這個 zone）。"
      continue
    fi

    if [[ -n "$existing_groups" ]] && echo "$existing_groups" | grep -q "zones/${full_zone}/networkEndpointGroups/${neg_name}$"; then
      log "  ${full_zone}：${neg_name} 已掛在 ${bs_name} 上，略過。"
      continue
    fi

    run gcloud compute backend-services add-backend "${bs_name}" \
      --project="${PROJECT_ID}" \
      --region="${REGION}" \
      --network-endpoint-group="${neg_name}" \
      --network-endpoint-group-zone="${full_zone}" \
      --balancing-mode=RATE \
      --max-rate-per-endpoint=100
  done
done

# -------------------------------------------------------------------------
# 補齊 lb-drill 的 route rule
#   2026-09-11 使用者確認：這幾個服務在演練中用的端點（priority／path）是固定的，不會變，
#   可以自動化，不用每次手動貼——這跟稍早「lb-drill 接線只需要給設定內容、之後不會再動」
#   的判斷相反，是因為後來實測發現 lb-drill 本身會在住宿1.0team自己的演練結束後被砍掉，
#   下次演練還要重建，並不是真的「一次性」。
#   只在 lb-drill 存在時才動手（上面已經檢查過、印過警告），且只更新／新增這裡列出的
#   固定 priority（2/3/5），完全不碰 asp(1)／static(4) 這兩條既有規則。
# -------------------------------------------------------------------------
declare -A DR_LB_ROUTE_PRIORITY=(
  [new-caring-web-api]=2
  [new-caring-web-page]=3
  [new-caring-web]=5
)
declare -A DR_LB_ROUTE_DESCRIPTION=(
  [new-caring-web-api]="web-api"
  [new-caring-web-page]="web-page"
  [new-caring-web]="others"
)
declare -A DR_LB_ROUTE_MATCH=(
  [new-caring-web-api]='{"pathTemplateMatch":"/api/**"}'
  [new-caring-web-page]='{"prefixMatch":"/v2/"}'
  [new-caring-web]='{"pathTemplateMatch":"/**"}'
)

if ! gcloud compute url-maps describe "${DR_LB_URLMAP}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  log "${DR_LB_URLMAP} 不存在，略過 route rule 這一步（backend-service 已經備妥，等 ${DR_LB_URLMAP} 重建後重跑這支 script 即可自動補上）。"
else
  log "--- 補齊 ${DR_LB_URLMAP}／${DR_LB_PATH_MATCHER} 的 route rule ---"
  URLMAP_JSON="$(gcloud compute url-maps describe "${DR_LB_URLMAP}" --region="${REGION}" --project="${PROJECT_ID}" --format=json)"
  UPDATED_JSON="$URLMAP_JSON"
  ROUTES_CHANGED=0

  for app in "${APPS[@]}"; do
    if [[ -z "${DR_LB_ROUTE_PRIORITY[$app]:-}" ]]; then
      log "  ${app} 沒有預先定義的 route rule 對應（priority／match），略過（新服務要先在 script 裡補上對應規則才能自動接線）。"
      continue
    fi

    bs_name="${app}-${DR_BACKEND_ENV}-dr-80"
    priority="${DR_LB_ROUTE_PRIORITY[$app]}"
    description="${DR_LB_ROUTE_DESCRIPTION[$app]}"
    match_json="${DR_LB_ROUTE_MATCH[$app]}"
    service_url="https://www.googleapis.com/compute/v1/projects/${PROJECT_ID}/regions/${REGION}/backendServices/${bs_name}"

    existing_rule="$(echo "$UPDATED_JSON" | jq --arg pm "${DR_LB_PATH_MATCHER}" --argjson prio "$priority" \
      '[.pathMatchers[]? | select(.name==$pm) | .routeRules[]? | select(.priority==$prio)] | first')"

    if [[ "$existing_rule" != "null" ]]; then
      existing_service="$(echo "$existing_rule" | jq -r '.service')"
      if [[ "$existing_service" == "$service_url" ]]; then
        log "  priority ${priority}（${description}）已經指到 ${bs_name}，略過。"
        continue
      else
        log "  priority ${priority}（${description}）目前指到別的 backend-service（${existing_service##*/}），更新成 ${bs_name}。"
        UPDATED_JSON="$(echo "$UPDATED_JSON" | jq --arg pm "${DR_LB_PATH_MATCHER}" --argjson prio "$priority" --arg svc "$service_url" '
          (.pathMatchers[] | select(.name==$pm) | .routeRules[] | select(.priority==$prio) | .service) = $svc
        ')"
        ROUTES_CHANGED=1
      fi
    else
      log "  補上 route rule：${description}（priority ${priority}） → ${bs_name}"
      UPDATED_JSON="$(echo "$UPDATED_JSON" | jq --arg pm "${DR_LB_PATH_MATCHER}" --argjson prio "$priority" \
        --arg desc "$description" --argjson match "$match_json" --arg svc "$service_url" '
        (.pathMatchers[] | select(.name==$pm) | .routeRules) += [{description: $desc, priority: $prio, matchRules: [$match], service: $svc}]
      ')"
      ROUTES_CHANGED=1
    fi
  done

  if [[ "$ROUTES_CHANGED" == "1" ]]; then
    TMP_URLMAP_FILE="$(mktemp)"
    # describe --format=json 帶了幾個 import 不接受的唯讀欄位（creationTimestamp／kind／
    # selfLink／id／region），實測過 import 會直接因為 additionalProperties 驗證失敗，
    # 這裡先用 jq 濾掉再寫檔。
    echo "$UPDATED_JSON" | jq 'del(.creationTimestamp, .kind, .selfLink, .id, .region)' > "$TMP_URLMAP_FILE"
    run gcloud compute url-maps import "${DR_LB_URLMAP}" \
      --project="${PROJECT_ID}" \
      --region="${REGION}" \
      --source="${TMP_URLMAP_FILE}" \
      --quiet
    rm -f "$TMP_URLMAP_FILE"
  else
    log "  ${DR_LB_URLMAP} 不需要更新（route rule 都已經是最新的）。"
  fi
fi

log "完成。backend-service／lb-drill route rule（存在的話）都已經處理完。若之後新增本 script"
log "尚未定義 route rule 對應的服務，記得在 DR_LB_ROUTE_PRIORITY／DR_LB_ROUTE_DESCRIPTION／DR_LB_ROUTE_MATCH"
log "補上對應項目，否則只會建 backend-service，不會自動接進 lb-drill。"
