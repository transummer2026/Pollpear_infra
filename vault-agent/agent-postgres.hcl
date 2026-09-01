# Vault agent for the postgres-secrets side-car. From secret/pollpear/db it renders
# the Postgres superuser, password, and database name into the shared secrets volume
# (read via POSTGRES_*_FILE at init). Runs once and exits.
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
  destination = "/secrets/postgres_user"
  perms       = "0644"
  contents    = "{{- with secret \"secret/data/pollpear/db\" -}}{{ .Data.data.username }}{{- end -}}"
}

template {
  destination = "/secrets/postgres_password"
  perms       = "0644"
  contents    = "{{- with secret \"secret/data/pollpear/db\" -}}{{ .Data.data.password }}{{- end -}}"
}

template {
  destination = "/secrets/postgres_db"
  perms       = "0644"
  contents    = "{{- with secret \"secret/data/pollpear/db\" -}}{{ .Data.data.database }}{{- end -}}"
}

exit_after_auth = true
