{{/*
  安全加載外部 JSON 文件生成 dockerconfig
*/}}
{{- define "dockerconfigjson" -}}
{{- $credential := .Files.Get "secrets/gar-key.json" | trim -}}
{
  "auths": {
    "{{ .Values.imagePullSecrets.registry }}": {
      "username": "_json_key",
      "password": {{ $credential | mustToJson }},
      "email": "not-used@example.com"
    }
  }
}
{{- end -}}