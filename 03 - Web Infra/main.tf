provider "google" {
  project = "citybot-webtool"
  region  = "us-central1"
}

# SERVICE ACCOUNT DATA 
data "google_service_account" "sa_terraform_local" {
  account_id = "sa-terraform-local"
}

# VPC AND NETWORKING
data "google_compute_network" "vpc" {
  name = "custom"
}

data "google_compute_subnetwork" "webserver_subnet" {
  name   = "webserver-subnet"
  region = "us-east1"
}

# INSTANCE TEMPLATE FOR WEB SERVERS
resource "google_compute_instance_template" "webserver_template" {
  name         = "webserver-template"
  description  = "This template is used to create web server instances."
  machine_type = "e2-micro"

  tags = ["webserver"]
  labels = {
    "app" = "webtool"
    "env" = "prod"
  }

  disk {
    source_image = "debian-cloud/debian-11"
    auto_delete  = true
    boot         = true
  }

  network_interface {
    # INFO: Since we specify subnet, this instance template can be used to
    #     create instance groups only in this subnet
    subnetwork = data.google_compute_subnetwork.webserver_subnet.id
    # TODO: Check if specifying subnet can be avoided for non-default network. 
    # network = data.google_compute_network.vpc.id

    # INFO: Creating ephemeral external IP for health probe to hit the server
    # TODO: Set up cloud NAT / router 
    # access_config {
    # }

  }

  service_account {
    email  = data.google_service_account.sa_terraform_local.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = <<-EOF
    #! /bin/bash
    NAME=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/name)
    ZONE=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone | sed 's@.*/@@')
    sudo apt-get update
    sudo apt-get install -y stress apache2
    sudo systemctl start apache2
    cat <<INNEREOF> /var/www/html/index.html
    <html>
        <head>
            <title> Managed Bowties </title>
        </head>
        <style>
    h1 {
    text-align: center;
    font-size: 50px;
    }
    h2 {
    text-align: center;
    font-size: 40px;
    }
    h3 {
    text-align: right;
    }
    </style>
        <body style="font-family: sans-serif"></body>
        <body>
            <h1>Aaaand.... Success!</h1>
            <h2>MACHINE NAME <span style="color: #3BA959">$NAME</span> DATACENTER <span style="color: #5383EC">$ZONE</span></h2>
            <section id="photos">
                <p style="text-align:center;"><img src="https://storage.googleapis.com/tony-bowtie-pics/managing-bowties.svg" alt="Managing Bowties"></p>
            </section>
        </body>
    </html>
    INNEREOF
    EOF

}

# HEALTH CHECK
resource "google_compute_health_check" "autohealing" {
  name                = "webserver-autohealing-check"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  tcp_health_check {
    port = "80"
  }
}

# INSTANCE GROUP (create from instance template)
resource "google_compute_region_instance_group_manager" "webserver" {
  name = "webserver-instance-group"

  base_instance_name         = "webserver"
  region                     = "us-east1"

  version {
    instance_template = google_compute_instance_template.webserver_template.id
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.autohealing.id
    initial_delay_sec = 300
  }
}

# AUTOSCALER (attach to the instance group manager)
resource "google_compute_region_autoscaler" "webserver_autoscaler" {
  name   = "webserver-autoscaler"
  region = "us-east1"
  target = google_compute_region_instance_group_manager.webserver.id

  autoscaling_policy {
    max_replicas    = 6     # TODO: Check quota? (Max IP address = 4, but external I think)
    min_replicas    = 3
    cooldown_period = 120 

    cpu_utilization {
      target = 0.6
    }
  }
}

# HTTP LOAD BALANCER 





# FIREWALL
resource "google_compute_firewall" "webserver_ingress" {
  name    = "webserver-ingress"
  network = data.google_compute_network.vpc.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443"]
  }
  source_ranges = ["0.0.0.0/0"]  # TODO: change this to load balancer IP 
  target_tags   = ["webserver"]
}

resource "google_compute_firewall" "allow_health_checks" {
  name    = "webserver-health-checks"
  network = data.google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  source_ranges = ["35.191.0.0/16","130.211.0.0/22"]
  target_tags   = ["webserver"]
}
