terraform {
  required_providers {
    vault = {
      source = "hashicorp/vault"
      #version = "3.6.0"
    }
  }
}

provider "vault" {
      
# Configuration options
}

resource "vault_mount" "kv-v2" {
  #depends_on = [vault_namespace.finance]
  #provider = vault.finance
  path = "kv-v2"
  type = "kv-v2"
}

# Generic Secret example

resource "vault_generic_secret" "example" {
   path = "kv-v2/foo"

   data_json = <<EOT
   {
      "foo":   "bar",
      "pizza": "cheese"
   }
   EOT
   }

# Policy creation example

resource "vault_policy" "example" {
  name = "dev-team"

  policy = <<EOT
  path "kv-v2kv/my_app" {
    capabilities = ["update"]
  }
  EOT
  }

# Namespace creation example

resource "vault_namespace" "prod-ns" {
  path = "prod"
}

# Raft snapshot auto file

resource "vault_raft_snapshot_agent_config" "gcs_backups" {
  name             = "gcp-backup"
  interval_seconds = 60
  retain           = 7
  path_prefix      = "vault/snapshots/"
  google_gcs_bucket = "vault-raft-snapshot"
  storage_type     = "google-gcs"

# this can be set as an environment variable

#  google_service_account_key = <<EOT  
#{
#  "type": "service_account",
#  "project_id": "tfc-sip-01",
#  "private_key_id": "695f73d95d67f2f915fdec3b0d8abb56e0a28cfc",
#  "private_key": "<private key of sa account>"
#  "client_email": "vault-raft-snapshot@tfc-sip-01.iam.gserviceaccount.com",
#  "client_id": "114432024117330266662",
#  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
#  "token_uri": "https://oauth2.googleapis.com/token",
#  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
#  "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/vault-raft-snapshot%40tfc-sip-01.iam.gserviceaccount.com"
#}
#EOT
}



resource "vault_raft_snapshot_agent_config" "local_backups" {
  name             = "local"
  interval_seconds = 86400 # 24h
  retain           = 7
  path_prefix      = "/opt/vault/snapshots/"
  storage_type     = "local"

  # Storage Type Configuration
  local_max_space = 10000000
}

# Audit Example
resource "vault_audit" "prod-audit" {
  type = "file"

  options = {
    file_path = "/opt/vault/audit"
  }
}

