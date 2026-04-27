#!/bin/bash

# chmod +x /Users/ianchang/Work/new-caring/manifest/Shell/Script/service_account_binding.sh

# clear && /Users/ianchang/Work/new-caring/manifest/Shell/Script/service_account_binding.sh

gcloud config set project "static-map-242406"

gcloud auth application-default set-quota-project "static-map-242406"

gcloud container clusters get-credentials caring-tw --region=asia-east1

## Dev
## Qat
## Demo

gcloud iam service-accounts add-iam-policy-binding \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:static-map-242406.svc.id.goog[new-caring-web-api-dev/new-caring-web-api]" \
    n-c-b-a@static-map-242406.iam.gserviceaccount.com

kubectl -n new-caring-web-api-dev annotate --overwrite serviceaccount \
    new-caring-web-api \
    iam.gke.io/gcp-service-account=n-c-b-a@static-map-242406.iam.gserviceaccount.com

gcloud iam service-accounts add-iam-policy-binding \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:static-map-242406.svc.id.goog[new-caring-web-api-dev2/new-caring-web-api]" \
    n-c-b-a@static-map-242406.iam.gserviceaccount.com

kubectl -n new-caring-web-api-dev2 annotate --overwrite serviceaccount \
    new-caring-web-api \
    iam.gke.io/gcp-service-account=n-c-b-a@static-map-242406.iam.gserviceaccount.com

gcloud iam service-accounts add-iam-policy-binding \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:static-map-242406.svc.id.goog[new-caring-web-api-dev3/new-caring-web-api]" \
    n-c-b-a@static-map-242406.iam.gserviceaccount.com

kubectl -n new-caring-web-api-dev3 annotate --overwrite serviceaccount \
    new-caring-web-api \
    iam.gke.io/gcp-service-account=n-c-b-a@static-map-242406.iam.gserviceaccount.com

gcloud iam service-accounts add-iam-policy-binding \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:static-map-242406.svc.id.goog[new-caring-web-api-qat/new-caring-web-api]" \
    n-c-b-a@static-map-242406.iam.gserviceaccount.com

kubectl -n new-caring-web-api-qat annotate --overwrite serviceaccount \
    new-caring-web-api \
    iam.gke.io/gcp-service-account=n-c-b-a@static-map-242406.iam.gserviceaccount.com

gcloud iam service-accounts add-iam-policy-binding \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:static-map-242406.svc.id.goog[new-caring-web-api-demo/new-caring-web-api]" \
    n-c-b-a@static-map-242406.iam.gserviceaccount.com

kubectl -n new-caring-web-api-demo annotate --overwrite serviceaccount \
    new-caring-web-api \
    iam.gke.io/gcp-service-account=n-c-b-a@static-map-242406.iam.gserviceaccount.com

gcloud iam service-accounts add-iam-policy-binding \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:static-map-242406.svc.id.goog[new-caring-event-consumer-dev/caring-event-consumer]" \
    n-c-b-a@static-map-242406.iam.gserviceaccount.com

kubectl -n new-caring-event-consumer-dev annotate --overwrite serviceaccount \
    caring-event-consumer \
    iam.gke.io/gcp-service-account=n-c-b-a@static-map-242406.iam.gserviceaccount.com

gcloud iam service-accounts add-iam-policy-binding \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:static-map-242406.svc.id.goog[new-caring-event-consumer-dev2/caring-event-consumer]" \
    n-c-b-a@static-map-242406.iam.gserviceaccount.com

kubectl -n new-caring-event-consumer-dev2 annotate --overwrite serviceaccount \
    caring-event-consumer \
    iam.gke.io/gcp-service-account=n-c-b-a@static-map-242406.iam.gserviceaccount.com

gcloud iam service-accounts add-iam-policy-binding \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:static-map-242406.svc.id.goog[new-caring-event-consumer-qat/caring-event-consumer]" \
    n-c-b-a@static-map-242406.iam.gserviceaccount.com

kubectl -n new-caring-event-consumer-qat annotate --overwrite serviceaccount \
    caring-event-consumer \
    iam.gke.io/gcp-service-account=n-c-b-a@static-map-242406.iam.gserviceaccount.com

gcloud iam service-accounts add-iam-policy-binding \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:static-map-242406.svc.id.goog[new-caring-event-consumer-demo/caring-event-consumer]" \
    n-c-b-a@static-map-242406.iam.gserviceaccount.com

kubectl -n new-caring-event-consumer-demo annotate --overwrite serviceaccount \
    caring-event-consumer \
    iam.gke.io/gcp-service-account=n-c-b-a@static-map-242406.iam.gserviceaccount.com

gcloud iam service-accounts add-iam-policy-binding \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:static-map-242406.svc.id.goog[new-caring-mobile-api-dev/new-caring-mobile-api]" \
    n-c-b-a@static-map-242406.iam.gserviceaccount.com

kubectl -n new-caring-mobile-api-dev annotate --overwrite serviceaccount \
    new-caring-mobile-api \
    iam.gke.io/gcp-service-account=n-c-b-a@static-map-242406.iam.gserviceaccount.com

gcloud iam service-accounts add-iam-policy-binding \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:static-map-242406.svc.id.goog[new-caring-mobile-api-qat/new-caring-mobile-api]" \
    n-c-b-a@static-map-242406.iam.gserviceaccount.com

kubectl -n new-caring-mobile-api-qat annotate --overwrite serviceaccount \
    new-caring-mobile-api \
    iam.gke.io/gcp-service-account=n-c-b-a@static-map-242406.iam.gserviceaccount.com

gcloud iam service-accounts add-iam-policy-binding \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:static-map-242406.svc.id.goog[new-caring-mobile-api-demo/new-caring-mobile-api]" \
    n-c-b-a@static-map-242406.iam.gserviceaccount.com

kubectl -n new-caring-mobile-api-demo annotate --overwrite serviceaccount \
    new-caring-mobile-api \
    iam.gke.io/gcp-service-account=n-c-b-a@static-map-242406.iam.gserviceaccount.com

# Release

gcloud iam service-accounts add-iam-policy-binding \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:static-map-242406.svc.id.goog[new-caring-web-api-release/new-caring-web-api]" \
    n-c-b-a@static-map-242406.iam.gserviceaccount.com

kubectl -n new-caring-web-api-release annotate --overwrite serviceaccount \
    new-caring-web-api \
    iam.gke.io/gcp-service-account=n-c-b-a@static-map-242406.iam.gserviceaccount.com

gcloud iam service-accounts add-iam-policy-binding \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:static-map-242406.svc.id.goog[new-caring-event-consumer-release/caring-event-consumer]" \
    n-c-b-a@static-map-242406.iam.gserviceaccount.com

kubectl -n new-caring-event-consumer-release annotate --overwrite serviceaccount \
    caring-event-consumer \
    iam.gke.io/gcp-service-account=n-c-b-a@static-map-242406.iam.gserviceaccount.com

gcloud iam service-accounts add-iam-policy-binding \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:static-map-242406.svc.id.goog[new-caring-mobile-api-release/new-caring-mobile-api]" \
    n-c-b-a@static-map-242406.iam.gserviceaccount.com

kubectl -n new-caring-mobile-api-release annotate --overwrite serviceaccount \
    new-caring-mobile-api \
    iam.gke.io/gcp-service-account=n-c-b-a@static-map-242406.iam.gserviceaccount.com

gcloud iam service-accounts add-iam-policy-binding \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:static-map-242406.svc.id.goog[caree-notification-dev/caree-notification]" \
    n-c-b-a@static-map-242406.iam.gserviceaccount.com

kubectl -n caree-notification-dev annotate --overwrite serviceaccount \
    caree-notification \
    iam.gke.io/gcp-service-account=n-c-b-a@static-map-242406.iam.gserviceaccount.com

gcloud iam service-accounts add-iam-policy-binding \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:static-map-242406.svc.id.goog[caree-notification-qat/caree-notification]" \
    n-c-b-a@static-map-242406.iam.gserviceaccount.com

kubectl -n caree-notification-qat annotate --overwrite serviceaccount \
    caree-notification \
    iam.gke.io/gcp-service-account=n-c-b-a@static-map-242406.iam.gserviceaccount.com

gcloud iam service-accounts add-iam-policy-binding \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:static-map-242406.svc.id.goog[caree-notification-demo/caree-notification]" \
    n-c-b-a@static-map-242406.iam.gserviceaccount.com

kubectl -n caree-notification-demo annotate --overwrite serviceaccount \
    caree-notification \
    iam.gke.io/gcp-service-account=n-c-b-a@static-map-242406.iam.gserviceaccount.com

gcloud iam service-accounts add-iam-policy-binding \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:static-map-242406.svc.id.goog[caree-notification-release/caree-notification]" \
    n-c-b-a@static-map-242406.iam.gserviceaccount.com

kubectl -n caree-notification-release annotate --overwrite serviceaccount \
    caree-notification \
    iam.gke.io/gcp-service-account=n-c-b-a@static-map-242406.iam.gserviceaccount.com

# 賦予 JCP pubsub 權限
gcloud projects add-iam-policy-binding jubo-care-platform --member="serviceAccount:n-c-b-a@static-map-242406.iam.gserviceaccount.com" --role="roles/pubsub.subscriber"

