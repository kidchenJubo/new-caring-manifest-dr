#!/usr/bin/env bash

REGION=asia-east1
HEALTH_CHECK=k8s-health-check-new-caring

create_backend_services()
{
    env=$1
    app=$2

    echo "create backend-services [$app-$env-80]"

    gcloud compute backend-services create $app-$env-80 \
      --protocol=HTTP \
      --load-balancing-scheme=EXTERNAL_MANAGED \
      --health-checks=$HEALTH_CHECK \
      --health-checks-region=$REGION \
      --region=$REGION

    # 將 NEG 加入 backend services
    for zone in a b c; do
      gcloud compute backend-services add-backend $app-$env-80 \
        --network-endpoint-group=$app-$env-80 \
        --network-endpoint-group-zone=$REGION-$zone \
        --balancing-mode=RATE \
        --max-rate-per-endpoint=100 \
        --region=$REGION
    done
}

update_health_check()
{
    echo "update health_check"
    # tcp or http
    #  --request-path=/ 
    gcloud compute health-checks update tcp $HEALTH_CHECK \
      --region=$REGION \
      --use-serving-port \
      --check-interval=5s \
      --timeout=1s \
      --unhealthy-threshold=2 \
      --healthy-threshold=1
}

# update_health_check
# exit

# for env in qat demo; do
for env in release; do
  for app in new-caring-web-page new-caring-web-api; do
      create_backend_services $env $app
  done
done
