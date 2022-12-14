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
  }

  service_account {
    email  = data.google_service_account.sa_terraform_local.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = <<-EOF
    #! /bin/bash
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

    # COPY FILES FROM CLOUD STORE
    STORE_ROOT=gs://web-tool-build-files
    gsutil -m cp -r $STORE_ROOT/ ./
    cd web-tool-build-files/
    npm ci
    node server.js
    EOF

}
# INFO: npm clean install : https://docs.npmjs.com/cli/v8/commands/npm-ci

# HEALTH CHECK
resource "google_compute_health_check" "autohealing" {
  name                = "webserver-autohealing-check"
  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  tcp_health_check {
    port = "3000"
  }
}

# INSTANCE GROUP (create from instance template)
resource "google_compute_region_instance_group_manager" "webserver" {
  name = "webserver-instance-group"

  base_instance_name = "webserver"
  region             = "us-east1"

  version {
    instance_template = google_compute_instance_template.webserver_template.id
  }

  auto_healing_policies {
    health_check      = google_compute_health_check.autohealing.id
    initial_delay_sec = 300
  }

  named_port {
    name = "webserver-port-80"
    port = 80
  }

  named_port {
    name = "webserver-port-3000"
    port = 3000
  }
}

# AUTOSCALER (attach to the instance group manager)
resource "google_compute_region_autoscaler" "webserver_autoscaler" {
  name   = "webserver-autoscaler"
  region = "us-east1"
  target = google_compute_region_instance_group_manager.webserver.id

  autoscaling_policy {
    max_replicas    = 6 # TODO: Check quota? (Max IP address = 4, but external I think)
    min_replicas    = 3
    cooldown_period = 120

    cpu_utilization {
      target = 0.6
    }
  }
}

# HTTP LOAD BALANCER 

# forwarding rule (front end)
resource "google_compute_global_forwarding_rule" "webserver" {
  name   = "webserver-forwarding-rule"
  target = google_compute_target_http_proxy.webserver.id
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  # ip_address            = google_compute_global_address.default.id
}

# http proxy
resource "google_compute_target_http_proxy" "webserver" {
  name = "webserver-target-http-proxy"
  url_map = google_compute_url_map.webserver.id
}

# url map
resource "google_compute_url_map" "webserver" {
  name = "webserver-url-map"
  default_service = google_compute_backend_service.webserver.id
}

# backend service with custom request and response headers
resource "google_compute_backend_service" "webserver" {
  name = "webserver-backend-service"

  backend {
    group           = google_compute_region_instance_group_manager.webserver.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
    max_utilization = 0.8
  }

  # provider                = google-beta
  protocol = "HTTP"
  # Named ports -> https://cloud.google.com/load-balancing/docs/backend-service?&_ga=2.50422249.-1703985230.1665679367#named_ports
  # INFO: The named port must be specified in the instance group.
  port_name               = "webserver-port-3000"
  load_balancing_scheme   = "EXTERNAL"
  timeout_sec             = 10
  enable_cdn              = false
  custom_request_headers  = ["X-Client-Geo-Location: {client_region_subdivision}, {client_city}"]
  custom_response_headers = ["X-Cache-Hit: {cdn_cache_status}"]

  # TODO: Are health checks required on both instnace groups and LB?
  health_checks = [google_compute_health_check.autohealing.id]
}


# FIREWALL
resource "google_compute_firewall" "webserver_ingress" {
  name    = "webserver-ingress"
  network = data.google_compute_network.vpc.name

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443", "3000"]
  }
  source_ranges = ["0.0.0.0/0"] # TODO: change this to load balancer IP 
  target_tags   = ["webserver"]
}

resource "google_compute_firewall" "allow_health_checks" {
  name    = "webserver-health-checks"
  network = data.google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["3000"]
  }
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["webserver"]
}
