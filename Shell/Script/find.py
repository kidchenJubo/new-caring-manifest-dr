# clear && python3 /Users/ianchang/Work/new-caring/manifest/Shell/Script/find.py

import os

# 根目錄
root_dir = "/Users/ianchang/Work/new-caring/manifest"

file_dir = f"{root_dir}/Infrastructure/istio/templates"

# 輸出的 shell 檔案
# 輸出的 shell 檔案
output_file = f"{root_dir}/Shell/Script/istio_apply_all.sh"

yaml_files = []

# 遞迴尋找所有 .yaml 檔案
for dirpath, _, filenames in os.walk(file_dir):
    for filename in filenames:
        if filename.endswith(".yaml"):
            filepath = os.path.join(dirpath, filename)
            yaml_files.append(filepath)

# 照路徑排序
yaml_files.sort()

# 輸出成 .sh
with open(output_file, "w", encoding="utf-8") as f:
    f.write("#!/bin/bash\n\n")
    f.write(f"# chmod +x {output_file}\n\n")
    f.write(f"# clear && {output_file}\n\n")
    f.write(f"gcloud config set project \"static-map-242406\"\n\n")
    f.write(
        f"gcloud auth application-default set-quota-project \"static-map-242406\"\n\n")
    f.write(
        f"gcloud container clusters get-credentials caring-tw --region=asia-east1\n\n")
    for filepath in yaml_files:
        f.write(f"kubectl apply -f {filepath}\n")

print(f"✅ 已產生 {output_file}，共 {len(yaml_files)} 個 yaml 檔")
