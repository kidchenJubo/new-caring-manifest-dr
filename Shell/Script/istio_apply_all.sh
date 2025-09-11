#!/bin/bash

# chmod +x /Users/ianchang/Work/new-caring/manifest/Shell/Script/istio_apply_all.sh

# clear && /Users/ianchang/Work/new-caring/manifest/Shell/Script/istio_apply_all.sh

gcloud config set project "static-map-242406"

gcloud auth application-default set-quota-project "static-map-242406"

gcloud container clusters get-credentials caring-tw --region=asia-east1

kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/authorization/policy/external/authorization-policy-external-allow-private-ips-demo.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/authorization/policy/external/authorization-policy-external-allow-private-ips-dev.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/authorization/policy/external/authorization-policy-external-allow-private-ips-qat.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/authorization/policy/external/authorization-policy-external-allow-private-ips-release.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/authorization/policy/external/authorization-policy-external-allow-public-access-demo.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/authorization/policy/external/authorization-policy-external-allow-public-access-dev.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/authorization/policy/external/authorization-policy-external-allow-public-access-qat.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/authorization/policy/external/authorization-policy-external-allow-public-access-release.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/certificate/jubo-health-certificate.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/destination/rule/googleapi.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/envoy/filter/external/ingress-403-result-page-demo.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/envoy/filter/external/ingress-403-result-page-dev.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/envoy/filter/external/ingress-403-result-page-qat.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/envoy/filter/external/ingress-403-result-page-release.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/envoy/filter/external/ingress-404-result-page-demo.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/envoy/filter/external/ingress-404-result-page-dev.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/envoy/filter/external/ingress-404-result-page-qat.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/envoy/filter/external/ingress-404-result-page-release.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/envoy/filter/external/ingress-500-result-page-demo.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/envoy/filter/external/ingress-500-result-page-dev.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/envoy/filter/external/ingress-500-result-page-qat.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/envoy/filter/external/ingress-500-result-page-release.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/envoy/filter/external/xff-trust-cloudflare-demo.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/envoy/filter/external/xff-trust-cloudflare-dev.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/envoy/filter/external/xff-trust-cloudflare-qat.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/envoy/filter/external/xff-trust-cloudflare-release.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/gateway/external/infra-gateway-external-demo.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/gateway/external/infra-gateway-external-dev.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/gateway/external/infra-gateway-external-qat.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/gateway/external/infra-gateway-external-release.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/gateway/internal/infra-gateway-internal-demo.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/gateway/internal/infra-gateway-internal-dev.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/gateway/internal/infra-gateway-internal-qat.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/gateway/internal/infra-gateway-internal-release.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/gateway/neg/infra-gateway-neg-dev.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/gateway/neg/infra-gateway-neg-release.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/service/entry/googleapi.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Infrastructure/argocd/argocd.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Backend/Api/Internal/new-caring-web-api-internal-demo.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Backend/Api/Internal/new-caring-web-api-internal-dev.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Backend/Api/Internal/new-caring-web-api-internal-qat.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Backend/Api/Internal/new-caring-web-api-internal-release.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Backend/Api/Neg/new-caring-web-api-internal-demo.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Backend/Api/Neg/new-caring-web-api-internal-dev.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Backend/Api/Neg/new-caring-web-api-internal-qat.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Backend/Api/Neg/new-caring-web-api-internal-release.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Backend/Api/Storage/new-caring-web-api-storage-demo.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Backend/Api/Storage/new-caring-web-api-storage-dev.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Backend/Api/Storage/new-caring-web-api-storage-qat.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Backend/Api/Storage/new-caring-web-api-storage-release.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Backend/Api/new-caring-web-api-demo.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Backend/Api/new-caring-web-api-dev.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Backend/Api/new-caring-web-api-qat.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Backend/Api/new-caring-web-api-release.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Frontend/Page/Internal/new-caring-web-page-internal-demo.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Frontend/Page/Internal/new-caring-web-page-internal-dev.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Frontend/Page/Internal/new-caring-web-page-internal-qat.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Frontend/Page/Internal/new-caring-web-page-internal-release.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Frontend/Page/Neg/new-caring-web-page-internal-demo.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Frontend/Page/Neg/new-caring-web-page-internal-dev.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Frontend/Page/Neg/new-caring-web-page-internal-qat.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Frontend/Page/Neg/new-caring-web-page-internal-release.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Frontend/Page/new-caring-web-page-demo.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Frontend/Page/new-caring-web-page-dev.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Frontend/Page/new-caring-web-page-qat.yaml
kubectl apply -f /Users/ianchang/Work/new-caring/manifest/Infrastructure/istio/templates/virtual/service/Microservices/Caring/Frontend/Page/new-caring-web-page-release.yaml
