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
  destination = "/secrets/redis-password"
  perms       = "0644"
  contents    = <<EOT
{{- with secret "secret/data/pollpear/redis" -}}
{"redis://redis:6379":{{ .Data.data.password | toJSON }}}
{{- end }}
EOT
}

exit_after_auth = true
