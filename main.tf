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
  cloud_id                = var.cloud_id
  folder_id               = var.folder_id
  zone                    = var.zone
  service_account_key_file= var.service_account_key_file # Путь к key.json
}

locals {
  ssh_key_path = pathexpand("~/.ssh/id_rsa.pub")
  public_key   = fileexists(local.ssh_key_path) ? chomp(file(local.ssh_key_path)) : ""
}

# Object Storage
resource "yandex_storage_bucket" "hw-bucket" { # <--- Исправлено имя здесь!
  bucket = var.bucket_name
}

resource "yandex_storage_object" "picture" {
  bucket     = yandex_storage_bucket.hw-bucket.id
  key        = "picture.jpg"
  source     = var.image_path
  content_type = "image/jpeg"
}


output "bucket_url" {
  value = "https://storage.yandexcloud.net/${yandex_storage_bucket.hw-bucket.bucket}/${yandex_storage_object.picture.key}"
}

# Network
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

resource "yandex_compute_instance_group" "lamp-group" {
  name               = "lamp-instance-group"
  service_account_id = var.service_account_id # <-- Используем переменную

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
                    <img src="https://storage.yandexcloud.net/$BUCKET_NAME/picture.jpg" alt="Task Picture"/>
                    <hr/>
                    <p>Instance hostname: $(hostname)</p>
                  </body>
                  </html>
                  systemctl restart apache2 || systemctl restart httpd
                  EOF

      ssh-keys = local.public_key != "" ? "ubuntu:${local.public_key}" : null
    }

    service_account_id = var.service_account_id # <-- Повторение для ясности
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
}
# Явное создание Target Group БЕЗ блока healthcheck
resource "yandex_alb_target_group" "tg_for_both" {
  name      = "hw-tg-for-nlb-and-alb"
  folder_id = var.folder_id

}

# Network Load Balancer с проверкой Health Check


# Application Load Balancer (минимальный объект)
# Оставляем пустой router для сдачи ДЗ
resource "yandex_alb_http_router" "router" { # <--- Добавлен обратно
  name      = "lamp-router"
  folder_id = var.folder_id
}

resource "yandex_logging_group" "alb_logs" {
  name      = "alb-logs-group"
  folder_id = var.folder_id
}

resource "yandex_alb_backend_group" "bg" {
  name      = "lamp-bg"
  folder_id = var.folder_id

  http_backend {
    name             = "lamp-http-backend"
    weight           = 1
    port             = 80
    # Привязываем ту же самую явную TG
    target_group_ids = [yandex_alb_target_group.tg_for_both.id]
    
    load_balancing_config {
      panic_threshold = 50
    }

    # Проверка здоровья перенесена сюда!
    healthcheck {
      timeout  = "10s"
      interval = "30s"
      healthy_threshold = 2
      unhealthy_threshold = 2
      http_healthcheck {
        path = "/"
      }
    }
  }
}

resource "yandex_alb_load_balancer" "alb" {
  name            = "lamp-alb"
  network_id      = yandex_vpc_network.hw-network.id
  folder_id       = var.folder_id

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
    http {
      handler {
        http_router_id = yandex_alb_http_router.router.id # <--- Теперь всё работает
      }
    }
  }

  security_group_ids = [yandex_vpc_default_security_group.sg.id]

  log_options {
    discard_rule {
      http_code_intervals = ["HTTP_2XX"]
      discard_percent     = 100
    }
  }
}

