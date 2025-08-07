# New Caring Manifest Microservices

```bash
gcloud config set project "static-map-242406"

gcloud auth application-default set-quota-project "static-map-242406"

gcloud container clusters get-credentials caring-release --region=asia-east1

gcloud iam service-accounts add-iam-policy-binding \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:static-map-242406.svc.id.goog[new-caring-web-api-release/new-caring-web-api]" \
    n-c-b-a@static-map-242406.iam.gserviceaccount.com

kubectl -n new-caring-web-api-release annotate --overwrite serviceaccount \
    new-caring-web-api \
    iam.gke.io/gcp-service-account=n-c-b-a@static-map-242406.iam.gserviceaccount.com
```