provider "google" {
  project = "citybot-webtool"
  region  = "us-central1" 
}

# SERVICE ACCOUNT DATA 
data "google_service_account" "sa_terraform_local" {
  account_id   = "sa-terraform-local"
}

# VPC AND NETWORKING
data "google_compute_network" "vpc" {
  name                    = "custom"
}

data "google_compute_subnetwork" "ci_subnet" {
  name          = "ci-subnet"
  region        = "us-central1"
}


# COMPUTE ENGINE
resource "google_compute_instance" "ci_server" {
  name         = "ci-server"
  machine_type = "e2-medium"
  zone    = "us-central1-c"
  tags = ["private"]
  
  labels = {
    "app" = "webtool"
    "env" = "prod"
  }

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2004-lts"
    }
  }

  network_interface {
    subnetwork = data.google_compute_subnetwork.ci_subnet.id
    # INFO: For private instance, omit access_config block
    # access_config {
    #   network_tier = "STANDARD"  
    # } 
  }

  # INFO: Instance must be stopped for updating service account
  # allow_stopping_for_update = true 
  # desired_status = "RUNNING"

  service_account {
    email  = data.google_service_account.sa_terraform_local.email
    scopes = ["cloud-platform"]
  }

  # TODO: STORE EXTERNAL IP IN PROJECT METADATA (FOR SERVICE DISCOVERY)
  # NOT REQUIRED IF USING CLOUD FILE STORE 

  metadata_startup_script = <<-EOF
    #!/bin/bash
    sudo apt-get update

    curl -fsSL https://deb.nodesource.com/setup_19.x | sudo -E bash - &&\
    sudo apt-get install -y nodejs
    node --version

    echo "Current directory:"
    pwd
    echo "Who am i?"
    whoami
    echo "GCloud account used"
    gcloud config list

    ssh-keyscan github.com | tee -a /root/.ssh/known_hosts
    gcloud secrets versions access 1 --secret="github-ssh" --out-file="/root/.ssh/id_rsa"

    git config --global user.name "Sanjay-George"
    git config --global user.email "sanjaygeorge16@gmail.com"
    git clone git@github.com:Sanjay-George/WebTool.git
    
    cd WebTool
    npm install 
    
    cd ui
    npm install
    npm run build

    # TODO: Copy files to file store
  EOF
}

# FIREWALL RULES
resource "google_compute_firewall" "ci_ingress" {
  name    = "ci-ingress"
  network = data.google_compute_network.vpc.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ## SSH, HTTP and HTTPS traffic
    ports    = ["22", "80", "443"] 
  }

  source_ranges = [ "0.0.0.0/0" ]

  # Firewall will be attached to all instances with specified network tag. 
  # If not specified, firewall is applied to all instances in the network
  target_tags = ["private"]
}


