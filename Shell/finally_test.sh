
#!/bin/bash

# chmod +x /Users/ianchang/Work/new-caring/manifest/Shell/Script/finally_test.sh

# clear && /Users/ianchang/Work/new-caring/manifest/Shell/Script/finally_test.sh

gcloud config set project "static-map-242406"

gcloud auth application-default set-quota-project "static-map-242406"

gcloud container clusters get-credentials caring-tw --region=asia-east1

echo "\n\n"

curl -i -X GET \
'https://new-caring-dev-api.jubo.health/api/v2/function'

echo "\n\n"

curl -i -X GET \
'https://new-caring-qat-api.jubo.health/api/v2/function'

echo "\n\n"

curl -i -X GET \
'https://new-caring-demo-api.jubo.health/api/v2/function'

echo "\n\n"

curl -i -X GET \
'https://new-caring-release-api.jubo.health/api/v2/function'

echo "\n\n"

curl -i -X GET \
'https://new-caring-dev.jubo.health'

echo "\n\n"

curl -i -X GET \
'https://new-caring-qat.jubo.health'

echo "\n\n"

curl -i -X GET \
'https://new-caring-demo.jubo.health'

echo "\n\n"

curl -i -X GET \
'https://new-caring-release.jubo.health'

echo "\n\n"