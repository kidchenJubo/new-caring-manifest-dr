
#!/bin/bash

# chmod +x /Users/ianchang/Work/new-caring/manifest/Shell/Script/kubectl_rollout_restart_dev.sh

# clear && /Users/ianchang/Work/new-caring/manifest/Shell/Script/kubectl_rollout_restart_dev.sh

gcloud config set project "static-map-242406"

gcloud auth application-default set-quota-project "static-map-242406"

gcloud container clusters get-credentials caring-tw --region=asia-east1

kubectl rollout restart deployment new-caring-web-api -n new-caring-web-api-dev
kubectl rollout restart deployment new-caring-web-api -n new-caring-web-api-qat
kubectl rollout restart deployment new-caring-web-api -n new-caring-web-api-demo

kubectl rollout restart deployment caring-event-consumer -n new-caring-event-consumer-dev
kubectl rollout restart deployment caring-event-consumer -n new-caring-event-consumer-qat
kubectl rollout restart deployment caring-event-consumer -n new-caring-event-consumer-qat