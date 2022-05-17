terraform {
  backend "gcs" {
    bucket  = "tfc-sip-01-tfstate"
    prefix  = "vault/primary02"
  }
}

provider "google" {
  project = "tfc-sip-01"
  region  = "us-west1"
}

provider "google-beta" {
  project = "tfc-sip-01"
  region  = "us-west1"
}

data "google_compute_subnetwork" "vault-network-primary" {
  name   = "primary-subnet-01"
  region = "us-west1"
}

module "vault-ent-primary" {
  source               = "hashicorp/vault-ent-starter/gcp"
  #source               = "./modules/vault-starter"
  version              = "0.1.2"

  # The shared DNS SAN of the TLS certs being used
  leader_tls_servername  = "primary-vault.server.com"
  #Your GCP project ID
  project_id             = "tfc-sip-01"
  # Prefix for uniquely identifying GCP resources
  resource_name_prefix   = "primary"
  # Self link of the subnetwork you wish to deploy into
  #subnetwork             = "https://www.googleapis.com/compute/v1/projects/tfc-sip-01/regions/us-west1/subnetworks/subnet-01"
  subnetwork             = data.google_compute_subnetwork.vault-network-primary.self_link
  #reserve subnet range
  reserve_subnet_range   = "10.1.0.0/16"
  # Name of the SSL Certificate to be used for Vault LB
  ssl_certificate_name   = "vault-primary-20220513213251761400000001"
  # Secret id/name given to the google secret manager secret
  tls_secret_id          = "terraform_example_module_vault_tls_secret"
  # Path to Vault Enterprise license file
  vault_license_filepath = "/Users/csnow/git/vault-sip/vault-gke/tls/vault-enterprise.hclic"
  # Vault Version
  #vault_version          = "1.10.2-1"
  vault_version          = "1.10.2"
  #disk_source_image    = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2004-lts"
  vm_disk_source_image    = "rhel-8-v20220406"
  # Node Count 	
  node_count		= 3
  # User Data script
  user_supplied_userdata_path = "install_vault.sh.tpl"
}
