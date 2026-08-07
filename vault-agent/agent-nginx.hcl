vault {
  address = "http://vault:8200"
}

auto_auth {
  method "approle" {
    config = {
      role_id_file_path                   = "/tmp/role_id"
      secret_id_file_path                 = "/tmp/secret_id"
      remove_secret_id_file_after_reading = false
    }
  }
}

template {
  destination = "/secrets/htpasswd"
  perms       = "0644"
  contents    = "{{- with secret \"secret/data/pollpear/nginx\" -}}{{ .Data.data.htpasswd }}{{- end -}}"
}

template {
  destination = "/secrets/auth.conf"
  perms       = "0644"
  contents    = <<EOT
{{- with secret "secret/data/pollpear/nginx" -}}
{{- if eq .Data.data.auth "off" }}
auth_basic off;
{{- else }}
auth_basic           "{{ .Data.data.auth }}";
auth_basic_user_file /secrets/htpasswd;
{{- end }}
{{- end }}
EOT
}

exit_after_auth = true
