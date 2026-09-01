# Vault agent for the grafana-secrets side-car. Renders Grafana's admin user and
# password from secret/pollpear/grafana into the shared secrets volume (read via
# GF_SECURITY_ADMIN_*__FILE). Runs once and exits.
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
  destination = "/secrets/admin_user"
  perms       = "0644"
  contents    = "{{- with secret \"secret/data/pollpear/grafana\" -}}{{ .Data.data.admin_user }}{{- end -}}"
}

template {
  destination = "/secrets/admin_password"
  perms       = "0644"
  contents    = "{{- with secret \"secret/data/pollpear/grafana\" -}}{{ .Data.data.admin_password }}{{- end -}}"
}

exit_after_auth = true
