# Vault agent for the frontend build side-car (frontend-secrets). Authenticates via
# AppRole and renders the runtime config.json (gateway URL) into the front-dist
# volume that nginx serves. Runs once and exits.
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
  destination = "/secrets/config.json"
  perms       = "0644"
  contents    = "{{- with secret \"secret/data/pollpear/app\" -}}{\"gateway_url\":{{ .Data.data.gateway_url | toJSON }}}{{- end -}}"
}

exit_after_auth = true
