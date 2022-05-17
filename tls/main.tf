terraform {
  backend "gcs" {
    bucket  = "tfc-sip-01-tfstate"
    prefix  = "vault/primary-tls"
  }
}


provider "google" {
  project = var.project_id
  region  = var.region
}

# Generate a private key so you can create a CA cert with it.
resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Create a CA cert with the private key you just generated.
resource "tls_self_signed_cert" "ca" {
  key_algorithm   = tls_private_key.ca.algorithm
  private_key_pem = tls_private_key.ca.private_key_pem

  subject {
    common_name = "primary-vault.server.com"
  }

  validity_period_hours = 720 # 30 days

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]

  is_ca_certificate = true

  # provisioner "local-exec" {
  #   command = "echo '${tls_self_signed_cert.ca.cert_pem}' > ./vault-ca.pem"
  # }
}

# Generate another private key. This one will be used
# To create the certs on your Vault nodes
resource "tls_private_key" "server" {
  algorithm = "RSA"
  rsa_bits  = 2048

  # provisioner "local-exec" {
  #   command = "echo '${tls_private_key.server.private_key_pem}' > ./vault-key.pem"
  # }
}

resource "tls_cert_request" "server" {
  key_algorithm   = tls_private_key.server.algorithm
  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    common_name = "primary-vault.server.com"
  }

  dns_names = [
    var.shared_san,
    "localhost",
    "primary-vault.server.com",
    "dr-vault.server.com",
  ]

  ip_addresses = [
    "127.0.0.1",
    "10.10.11.1",
    "10.10.11.2",
    "10.10.11.3",
    "10.10.11.4",
    "10.10.11.5",
    "10.10.11.6",
    "10.10.11.7",
    "10.10.11.8",
    "10.10.11.9",
    "10.10.11.10",
    "10.10.11.11",
    "10.10.11.12",
    "10.10.11.13",
    "10.10.11.14",
    "10.10.11.15",
    "10.10.11.16",
    "10.10.11.17",
    "10.10.11.18",
    "10.10.11.19",
    "10.10.11.20",
    "10.10.11.21",
    "10.10.11.22",
    "10.10.11.23",
    "10.10.11.24",
    "10.10.11.25",
    "10.10.11.26",
    "10.10.11.27",
    "10.10.11.28",
    "10.10.11.29",
    "10.10.11.30",
    "10.10.21.1",
    "10.10.21.2",
    "10.10.21.3",
    "10.10.21.4",
    "10.10.21.5",
    "10.10.21.6",
    "10.10.21.7",
    "10.10.21.8",
    "10.10.21.9",
    "10.10.21.10",
    "10.10.21.11",
    "10.10.21.12",
    "10.10.21.13",
    "10.10.21.14",
    "10.10.21.15",
    "10.10.21.16",
    "10.10.21.17",
    "10.10.21.18",
    "10.10.21.19",
    "10.10.21.20",
    "10.10.21.21",
    "10.10.21.22",
    "10.10.21.23",
    "10.10.21.24",
    "10.10.21.25",
    "10.10.21.26",
    "10.10.21.27",
    "10.10.21.28",
    "10.10.21.29",
    "10.10.21.30",
  ]
}

resource "tls_locally_signed_cert" "server" {
  cert_request_pem   = tls_cert_request.server.cert_request_pem
  ca_key_algorithm   = tls_private_key.ca.algorithm
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 720 # 30 days

  allowed_uses = [
    "client_auth",
    "digital_signature",
    "key_agreement",
    "key_encipherment",
    "server_auth",
  ]

  # provisioner "local-exec" {
  #   command = "echo '${tls_locally_signed_cert.server.cert_pem}' > ./vault-crt.pem"
  # }
}

locals {
  tls_data = {
    vault_ca   = base64encode(tls_self_signed_cert.ca.cert_pem)
    vault_cert = base64encode(tls_locally_signed_cert.server.cert_pem)
    vault_pk   = base64encode(tls_private_key.server.private_key_pem)
  }
}

locals {
  secret = jsonencode(local.tls_data)
}

resource "google_compute_region_ssl_certificate" "main" {
  region      = var.region
  certificate = "${tls_locally_signed_cert.server.cert_pem}\n${tls_self_signed_cert.ca.cert_pem}"
  private_key = tls_private_key.server.private_key_pem

  description = "The regional SSL certificate of the private load balancer for Vault."
  name_prefix = "vault-primary-"

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_secret_manager_secret" "secret_tls" {
  secret_id = var.tls_secret_id

  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "secret_version_basic" {
  secret = google_secret_manager_secret.secret_tls.id

  secret_data = local.secret
}
