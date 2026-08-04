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
  destination = "/secrets/postgres.env"
  perms       = "0644"
  contents    = <<EOT
{{- with secret "secret/data/pollpear/db" -}}
POSTGRES_USER='{{ .Data.data.username }}'
POSTGRES_PASSWORD='{{ .Data.data.password }}'
POSTGRES_DB='{{ .Data.data.database }}'
{{- end }}
EOT
}

exit_after_auth = true
