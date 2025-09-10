# Jubo New Caring Manifest Microservices

```bash
gcloud config set project "static-map-242406"

gcloud auth application-default set-quota-project "static-map-242406"

gcloud container clusters get-credentials caring-tw --region=asia-east1
```

## Dev
## Qat
## Demo

```bash
gcloud iam service-accounts add-iam-policy-binding \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:static-map-242406.svc.id.goog[new-caring-web-api-dev/new-caring-web-api]" \
    n-c-b-a@static-map-242406.iam.gserviceaccount.com

kubectl -n new-caring-web-api-dev annotate --overwrite serviceaccount \
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
```

## Release

```bash
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
```