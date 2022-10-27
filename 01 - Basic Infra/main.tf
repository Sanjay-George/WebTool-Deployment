provider "google" {
  project = "citybot-webtool"
  region  = "us-central1"
#   zone    = "us-central1-c"
}

## SERVICE ACCOUNT DATA 
data "google_service_account" "sa_terraform_local" {
  account_id   = "sa-terraform-local"
}

# VPC AND NETWORKING
resource "google_compute_network" "vpc" {
  name                    = "custom"
  auto_create_subnetworks = "false"
}

# SUBNET FOR CI SERVER
resource "google_compute_subnetwork" "ci_subnet" {
  name          = "ci-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = "us-central1"
  network       = google_compute_network.vpc.id
  description = "Private subnet for the CI server"
  private_ip_google_access = true
}

# SUBNET FOR WEB SERVERS AND LB
resource "google_compute_subnetwork" "webserver_subnet" {
  name          = "webserver-subnet"
  ip_cidr_range = "10.0.5.0/24"
  region        = "us-east1"
  network       = google_compute_network.vpc.id
  description = "Private subnet for all web servers (instance groups)"
  private_ip_google_access = true
}

# FIREWALL RULES
resource "google_compute_firewall" "all_egress" {
  name    = "all-egress"
  network = google_compute_network.vpc.name
  direction = "EGRESS"

  allow {
    protocol = "icmp"
    # INFO: Leave out port to allow all ports
  }

  allow {
    protocol = "tcp"
  }
  target_tags = ["private", "public"]
}

