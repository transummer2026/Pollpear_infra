# Vault agent for the redis-secrets side-car. From secret/pollpear/redis it renders
# redis.conf (requirepass line loaded by redis-server) and a bare password file used
# by the healthcheck. Runs once and exits.
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
  destination = "/secrets/redis.conf"
  perms       = "0644"
  contents    = <<EOT
{{- with secret "secret/data/pollpear/redis" -}}
requirepass {{ .Data.data.password | toJSON }}
{{- end }}
EOT
}

template {
  destination = "/secrets/password"
  perms       = "0644"
  contents    = "{{- with secret \"secret/data/pollpear/redis\" -}}{{ .Data.data.password }}{{- end -}}"
}

exit_after_auth = true
