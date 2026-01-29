# Variables

locals {
  domain       = "byungjun-test.shop"
  managed_zone = "byungjun-test-shop"
  bucket_name  = "private-cdn-test"
  zone         = "asia-northeast3-a"
}

terraform {
  required_providers {
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0"
    }
  }
}

# Private GCS bucket

resource "google_storage_bucket" "cdn_bucket" {
  name          = local.bucket_name
  location      = "US"
  storage_class = "MULTI_REGIONAL"
  force_destroy = true

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = false
  }
}

# IP and certificate (will take minutes to hours to provision)

resource "google_compute_global_address" "cdn_ip" {
  name         = "cdn-ip"
  ip_version   = "IPV4"
  address_type = "EXTERNAL"
}

resource "google_dns_record_set" "cdn_dns_record" {
  name         = "${local.domain}."
  managed_zone = local.managed_zone
  rrdatas = [
    google_compute_global_address.cdn_ip.address
  ]
  ttl  = 300
  type = "A"
}

resource "google_compute_managed_ssl_certificate" "cdn_certificate" {
  name = "cdn-certificate"

  managed {
    domains = [
      local.domain,
    ]
  }
}

# Self-signed certificate for testing (self-managed TLS used by LB)
resource "tls_private_key" "lb_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "lb_cert" {
  key_algorithm   = tls_private_key.lb_key.algorithm
  private_key_pem = tls_private_key.lb_key.private_key_pem

  subjects = [
    {
      common_name  = local.domain
      organization = "Test"
    }
  ]

  validity_period_hours = 8760
  early_renewal_hours   = 168
}

resource "google_compute_ssl_certificate" "self_managed_cert" {
  name        = "self-managed-cert"
  certificate = tls_self_signed_cert.lb_cert.cert_pem
  private_key = tls_private_key.lb_key.private_key_pem
}

# Load Balancer

resource "google_compute_health_check" "web_hc" {
  name = "web-health-check"

  http_health_check {
    request_path = "/"
    port         = 80
  }
}

resource "google_compute_firewall" "allow_http" {
  name    = "allow-http"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_instance" "web" {
  name         = "web-vm"
  machine_type = "e2-micro"
  zone         = local.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
      size  = 10
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y nginx
    cat > /var/www/html/index.html <<'HTML'
    <html>
    <head><title>byungjun-test.shop</title></head>
    <body>
      <h1>Hello from byungjun-test.shop</h1>
      <p>Test page served from VM.</p>
    </body>
    </html>
    HTML
    systemctl restart nginx
  EOF
}

resource "google_compute_instance_group" "web_ig" {
  name  = "web-instance-group"
  zone  = local.zone
  instances = [
    google_compute_instance.web.self_link,
  ]
}

resource "google_compute_backend_service" "cdn_backend_service" {
  name                  = "cdn-backend-service"
  description           = "Backend service for instance group (test)"
  load_balancing_scheme = "EXTERNAL"
  protocol              = "HTTP"
  enable_cdn            = false

  backend {
    group = google_compute_instance_group.web_ig.self_link
  }

  health_checks = [google_compute_health_check.web_hc.self_link]

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

resource "google_compute_url_map" "cdn_lb" {
  name            = "cdn-lb"
  description     = "Load Balancer to redirect requests to bucket backend"
  default_service = google_compute_backend_service.cdn_backend_service.id
}

resource "google_compute_target_https_proxy" "cdn_https_proxy" {
  name             = "cdn-https-proxy"
  url_map          = google_compute_url_map.cdn_lb.self_link
  ssl_certificates = [google_compute_managed_ssl_certificate.cdn_certificate.self_link]
}

resource "google_compute_global_forwarding_rule" "cdn_https_forwarding_rule" {
  name                  = "cdn-https-forwarding-rule"
  target                = google_compute_target_https_proxy.cdn_https_proxy.self_link
  ip_address            = google_compute_global_address.cdn_ip.address
  load_balancing_scheme = "EXTERNAL"
  port_range            = "443"
}

# Partial load balancer for https redirects

resource "google_compute_url_map" "cdn_lb_https_redirect" {
  name        = "cdn-lb-https-redirect"
  description = "Partial Load Balancer for HTTPS Redirects"

  default_url_redirect {
    https_redirect = true
    strip_query    = false
  }
}

resource "google_compute_target_http_proxy" "cdn_http_proxy" {
  name    = "cdn-http-proxy"
  url_map = google_compute_url_map.cdn_lb_https_redirect.id
}

resource "google_compute_global_forwarding_rule" "cdn_http_forwarding_rule" {
  name                  = "cdn-http-forwarding-rule"
  target                = google_compute_target_http_proxy.cdn_http_proxy.id
  ip_address            = google_compute_global_address.cdn_ip.id
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
}

# Service Account

resource "google_service_account" "cdn_bucket_service_account" {
  account_id   = "cdn-service-account"
  display_name = "CDN Service Account"
}

resource "google_storage_bucket_iam_member" "cdn_bucket_object_reader" {
  bucket = google_storage_bucket.cdn_bucket.name
  role   = "roles/storage.legacyObjectReader"
  member = "serviceAccount:${google_service_account.cdn_bucket_service_account.email}"
}

resource "google_storage_hmac_key" "cdn_hmac_key" {
  service_account_email = google_service_account.cdn_bucket_service_account.email
}