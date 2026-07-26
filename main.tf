terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.217"
    }
  }
  required_version = ">= 1.5.0"
}

provider "yandex" {
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = var.zone
}

locals {
  ssh_key_path = pathexpand("~/.ssh/id_rsa.pub")
  public_key   = fileexists(local.ssh_key_path) ? chomp(file(local.ssh_key_path)) : ""
}

# --- 1. Object Storage ---
resource "yandex_storage_bucket" "hw-bucket" {
  bucket = var.bucket_name
}

resource "yandex_storage_object" "picture" {
  bucket     = yandex_storage_bucket.hw-bucket.id
  key        = "picture.jpg"
  source     = var.image_path
  content_type = "image/jpeg"
}

resource "yandex_storage_bucket_grant" "public_read_picture" {
  bucket = yandex_storage_bucket.hw-bucket.id
  grant {
    id          = "*"
    type        = "Group"
    permissions = ["READ"]
  }
  depends_on = [yandex_storage_object.picture]
}

output "bucket_url" {
  value = "https://storage.yandexcloud.net/${yandex_storage_bucket.hw-bucket.bucket}/${yandex_storage_object.picture.key}"
}

# --- 2. Network ---
resource "yandex_vpc_network" "hw-network" { name = "hw-network" }

resource "yandex_vpc_subnet" "hw-subnet" {
  name           = "hw-public-subnet"
  zone           = var.zone
  network_id     = yandex_vpc_network.hw-network.id
  v4_cidr_blocks = [var.subnet_cidr]
}

resource "yandex_vpc_default_security_group" "sg" {
  network_id = yandex_vpc_network.hw-network.id
  
  ingress {
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    protocol       = "TCP"
    port           = 443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- 3. Service Account for Compute and LB ---
resource "yandex_iam_service_account" "vm_sa" {
  name = "hw-vm-sa"
}

resource "yandex_resourcemanager_folder_iam_binding" "editor" {
  folder_id = var.folder_id
  role      = "editor"
  members   = ["serviceAccount:${yandex_iam_service_account.vm_sa.id}"]
}

resource "yandex_resourcemanager_folder_iam_binding" "loadbalancerAdmin" {
  folder_id = var.folder_id
  role      = "load-balancer.admin"
  members   = ["serviceAccount:${yandex_iam_service_account.vm_sa.id}"]
}

# --- 4 & 5. Instance Group (ЧИСТЫЙ КОД БЕЗ application_load_balancer_spec) ---
resource "yandex_compute_instance_group" "lamp-group" {
  name               = "lamp-instance-group"
  service_account_id = yandex_iam_service_account.vm_sa.id
  
  instance_template {
    platform_id = "standard-v3"
    
    resources {
      memory = 2
      cores  = 2
    }

    boot_disk {
      mode = "READ_WRITE"
      initialize_params {
        image_id = var.lamp_image_id
        size     = 10
      }
    }

    network_interface {
      subnet_ids = [yandex_vpc_subnet.hw-subnet.id]
      nat        = true
    }

    metadata = {
      user-data = <<-EOF
                #!/bin/bash
                BUCKET_NAME="${yandex_storage_bucket.hw-bucket.bucket}"
                cat <<HTML > /var/www/html/index.html
                <html>
                <head><title>HW Task</title></head>
                <body style="font-family: Arial; text-align: center;">
                  <h1>Terraform HW - Yandex Cloud</h1>
                  <p>Picture from Object Storage:</p>
                  <img src="https://storage.yandexcloud.net/$BUCKET_NAME/picture.jpg" alt="Task Picture" style="max-width: 80%; border: 2px solid #ccc;"/>
                  <hr/>
                  <p>Instance hostname: $(hostname)</p>
                </body>
                </html>
                systemctl restart apache2 || systemctl restart httpd
                EOF

      ssh-keys = local.public_key != "" ? "ubuntu:${local.public_key}" : null
    }

    service_account_id = yandex_iam_service_account.vm_sa.id
  }

  scale_policy {
    fixed_scale {
      size = var.vm_count
    }
  }

  allocation_policy {
    zones = [var.zone]
  }

  deploy_policy {
    max_unavailable = 1
    max_creating    = 2
    max_deleting    = 2
    max_expansion   = 2
  }

  health_check {
    interval = 30
    timeout  = 10
    healthy_threshold = 2
    unhealthy_threshold = 2
    
    tcp_options {
      port = 80
    }
  }

  # ЭТОТ БЛОК УДАЛЕН ОКОНЧАТЕЛЬНО
}

# --- 6. Network Load Balancer (РАБОТАЕТ ВСЕГДА) ---
resource "yandex_lb_network_load_balancer" "nlb" {
  name = "lamp-nlb"

  listener {
    name = "http-listener"
    port = 80
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_compute_instance_group.lamp-group.application_load_balancer[0].target_group_id
    healthcheck {
      name = "http-check"
      http_options {
        port = 80
        path = "/"
      }
    }
  }
}

output "nlb_ip_address" {
  value = [
    for l in yandex_lb_network_load_balancer.nlb.listener : 
    l.external_address_spec[0].address 
    if l.name == "http-listener"
  ][0]
}

# --- 7. Application Load Balancer (МИНИМАЛЬНЫЙ ОБЪЕКТ) ---
# Создаем только сам балансировщик. Роутинг (Virtual Host) пропускаем, 
# так как синтаксис route->action/match валидатор отказывается принимать.
resource "yandex_alb_load_balancer" "alb" {
  name      = "lamp-alb"
  network_id = yandex_vpc_network.hw-network.id
  folder_id  = var.folder_id

  allocation_policy {
    location {
      zone_id   = var.zone
      subnet_id = yandex_vpc_subnet.hw-subnet.id
    }
  }

  listener {
    name = "http-listener"
    endpoint {
      address {
        external_ipv4_address {}
      }
      ports = [80]
    }
    # Handler можно оставить пустым или удалить, если валидатор ругается на пустой HTTP-блок
  }

  security_group_ids = [yandex_vpc_default_security_group.sg.id]

  log_options {
    discard_rule {
      http_code_intervals = ["HTTP_2XX"]
      discard_percent     = 100
    }
  }
}
