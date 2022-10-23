provider "google" {
  project = "citybot-webtool"
  region  = "us-central1"
  zone    = "us-central1-c"
}

## SERVICE ACCOUNT DATA 
data "google_service_account" "sa_terraform_local" {
  account_id   = "sa-terraform-local"
}


# COMPUTE ENGINE
resource "google_compute_instance" "ci_server" {
  name         = "ci-server"
  machine_type = "e2-medium"
  # Update to medium for CI server. vite build will run out of memory on e2-micro
  # machine_type = "e2-medium" 

  tags = ["private", "ci"]

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
    subnetwork = google_compute_subnetwork.private.id

    # INFO: For private instance, omit access_config block
    # access_config {
    #   network_tier = "STANDARD"
    # }

    access_config {
      network_tier = "STANDARD"  
    } 

  }

  # INFO: Instance must be stopped for updating service account
  # allow_stopping_for_update = true 
  # desired_status = "RUNNING"

  service_account {
    email  = data.google_service_account.sa_terraform_local.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    sudo apt-get update
    sudo apt-get -y install apache2

    curl -fsSL https://deb.nodesource.com/setup_19.x | sudo -E bash - &&\
    sudo apt-get install -y nodejs
    node --version

    # sudo ssh-keyscan github.com | sudo tee -a /root/.ssh/known_hosts
    ssh-keyscan github.com | tee -a .ssh/known_hosts
    # sudo gcloud secrets versions access 1 --secret="github-ssh" --out-file="/root/.ssh/id_rsa"
    gcloud secrets versions access 1 --secret="github-ssh" --out-file=".ssh/id_rsa"
    git config --global user.name "Sanjay-George"
    git config --global user.email "sanjaygeorge16@gmail.com"
    # sudo git clone git@github.com:Sanjay-George/WebTool.git
    git clone git@github.com:Sanjay-George/WebTool.git
    
    cd WebTool
    # sudo npm install 
    npm install 
    
    cd ui
    # sudo npm install
    npm install
    # time taking process
    # nohup npm run build
    # sudo npm run build
    npm run build

    # TODO: remove this
    cd ..
    node server.js 

    rm /var/www/html/index.html
    cat > /var/www/html/index.html << INNEREOF
    <!DOCTYPE html>
    <html>
      <body>
        <h1>Hello from CI server</h1>
        <p>hostname</p>
      </body>
    </html>
    INNEREOF
    sed -i "s/hostname/terraform-instance-1/" /var/www/html/index.html
    sed -i "1s/$/ terraform-instance-1/" /etc/hosts

  EOF
 
}




# VPC AND NETWORKING

resource "google_compute_network" "vpc" {
  name                    = "custom"
  auto_create_subnetworks = "false"
}

resource "google_compute_subnetwork" "private" {
  name          = "private-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = "us-central1"
  network       = google_compute_network.vpc.id
  description = "Private subnet for the CI server and all of web servers"
  private_ip_google_access = true
}


# FIREWALL RULES

resource "google_compute_firewall" "private_ingress" {
  name    = "private-ingress"
  network = google_compute_network.vpc.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443", "8080", "3000", "1000-2000"]  
    ## TODO: separate out allow rules for CI and other servers
  }

  source_ranges = [ "0.0.0.0/0" ]

  # Firewall will be attached to all instances with specified network tag. 
  # If not specified, firewall is applied to all instances in the network
  target_tags = ["private"]
}

resource "google_compute_firewall" "all_egress" {
  name    = "all-egress"
  network = google_compute_network.vpc.name
  direction = "EGRESS"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
  }
  target_tags = ["private", "public"]
}

