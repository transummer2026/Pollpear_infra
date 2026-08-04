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
  destination = "/secrets/rpc_secret"
  perms       = "0600"
  contents    = "{{- with secret \"secret/data/pollpear/garage\" -}}{{ .Data.data.rpc_secret }}{{- end -}}"
}

template {
  destination = "/secrets/admin_token"
  perms       = "0600"
  contents    = "{{- with secret \"secret/data/pollpear/garage\" -}}{{ .Data.data.admin_token }}{{- end -}}"
}

exit_after_auth = true
