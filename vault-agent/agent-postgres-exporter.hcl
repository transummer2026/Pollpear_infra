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
  destination = "/secrets/pg_user"
  perms       = "0644"
  contents    = "{{- with secret \"secret/data/pollpear/db\" -}}{{ .Data.data.username }}{{- end -}}"
}

template {
  destination = "/secrets/pg_pass"
  perms       = "0644"
  contents    = "{{- with secret \"secret/data/pollpear/db\" -}}{{ .Data.data.password }}{{- end -}}"
}

template {
  destination = "/secrets/pg_uri"
  perms       = "0644"
  contents    = "{{- with secret \"secret/data/pollpear/db\" -}}postgres:5432/{{ .Data.data.database }}?sslmode=disable{{- end -}}"
}

exit_after_auth = true
