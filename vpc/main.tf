terraform {
  backend "gcs" {
    bucket  = "tfc-sip-01-tfstate"
    prefix  = "vault/primary-vpc"
  }
}


provider "google" {
  project = var.project_id
  region  = var.region
}

module "test_vpc_module" {
  source       = "terraform-google-modules/network/google"
  version      = "~> 3.2.0"
  project_id   = var.project_id
  network_name = var.network_name

  subnets = [
    {
      subnet_name   = "primary-subnet-01"
      subnet_ip     = "10.10.11.0/27"
      subnet_region = var.region
    },
    {
      subnet_name   = "dr-subnet-01"
      subnet_ip     = "10.10.21.0/27"
      subnet_region = "us-central1"
    }
  ]
}

#NAT router
resource "google_compute_router" "vault_router" {
  name    = "primary-vault-router"
  project = var.project_id
  region  = var.region
  network = module.test_vpc_module.network_name
}

resource "google_compute_router" "dr_vault_router" {
  name    = "dr-vault-router"
  project = var.project_id
  region  = "us-central1"
  network = module.test_vpc_module.network_name
}

# NAT service
resource "google_compute_router_nat" "vault_nat" {
  name    = "primary-vault-nat-1"
  project = var.project_id
  router  = google_compute_router.vault_router.name
  region  = var.region

  nat_ip_allocate_option = "AUTO_ONLY"

  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

resource "google_compute_router_nat" "dr_vault_nat" {
  name    = "primary-vault-nat-1"
  project = var.project_id
  router  = google_compute_router.dr_vault_router.name
  region  = "us-central1"

  nat_ip_allocate_option = "AUTO_ONLY"

  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
