# Vault agent for the nginx-secrets side-car. From secret/pollpear/nginx it renders
# the htpasswd file and auth.conf (basic-auth realm, or "auth_basic off"); from
# secret/pollpear/waf it renders waf.env (ModSecurity/CRS tuning sourced by the
# nginx entrypoint). Runs once and exits.
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

# Emit "auth_basic off;" when the secret's auth field is "off", otherwise a realm
# plus the htpasswd file rendered above.
template {
  destination = "/secrets/auth.conf"
  perms       = "0644"
  contents    = <<EOT
{{- with secret "secret/data/pollpear/nginx" -}}
{{- if eq .Data.data.auth "off" }}
auth_basic off;
{{- else }}
auth_basic           {{ .Data.data.auth | toJSON }};
auth_basic_user_file /secrets/htpasswd;
{{- end }}
{{- end }}
EOT
}

# Flatten every key under secret/pollpear/waf into KEY="value" env lines.
template {
  destination = "/secrets/waf.env"
  perms       = "0600"
  contents    = <<EOT
{{- with secret "secret/data/pollpear/waf" -}}
{{- range $k, $v := .Data.data }}
{{ $k }}={{ $v | toJSON }}
{{- end }}
{{- end }}
EOT
}

exit_after_auth = true
