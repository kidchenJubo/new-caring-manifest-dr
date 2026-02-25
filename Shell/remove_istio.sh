# 1. 移除 Gateway (如果有裝)
helm uninstall istio-ingress -n istio-system

# 2. 移除 Istiod (Control Plane)
helm uninstall istiod -n istio-system

# 3. 移除 Istio Base (CRDs 與基礎配置)
helm uninstall istio-base -n istio-system

# 4. 刪除 Namespace
kubectl delete namespace istio-system

# 刪除 CRD
kubectl get crd | grep 'istio.io' | awk '{print $1}' | xargs kubectl delete crd

# Istio 移除後，原本帶有 istio-injection=enabled 標籤的 Namespace 必須清除，否則之後重啟 Pod 會因為找不到 Istio 控制面而啟動失敗

# 查看有哪些 Namespace 啟用了注入
kubectl get namespace -L istio-injection

# 移除標籤 (以 argocd 為例)
kubectl label namespace argocd istio-injection-

# 刪除 webhook
kubectl delete validatingwebhookconfiguration istiod-default-validator
kubectl delete mutatingwebhookconfiguration istio-sidecar-injector
