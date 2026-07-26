terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.115"
    }
  }
  required_version = ">= 1.5.0"
}

provider "yandex" {
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = var.zone
  
  # Рекомендуемый способ аутентификации — через статический ключ доступа
  auth = "authorized_key"
  authorized_key {
    # Ключ можно сохранить в переменную окружения YC_SA_KEY_FILE или указать путь здесь
    // key_file = "~/.ssh/ycsa_key.json" 
  }
}

# 1. Создание бакета и загрузка файла
resource "yandex_storage_bucket" "hw-bucket" {
  bucket = var.bucket_name
  acl    = "public-read"
}

resource "yandex_storage_object" "picture" {
  bucket = yandex_storage_bucket.hw-bucket.id
  key    = "picture.jpg"
  source = var.image_path
  content_type = "image/jpeg"
  depends_on = [yandex_storage_bucket.hw-bucket]
}

# 2. Сеть и подсеть для ВМ
resource "yandex_vpc_network" "hw-network" {
  name = "hw-network"
}

resource "yandex_vpc_subnet" "hw-subnet" {
  name           = "hw-public-subnet"
  zone           = var.zone
  network_id     = yandex_vpc_network.hw-network.id
  v4_cidr_blocks = [var.subnet_cidr]
}

# 3. Шаблон ВМ (LAMP + user_data)
resource "yandex_compute_instance_template" "lamp-template" {
  name                = "lamp-group-template"
  platform_id         = "standard-v3"
  machine_type        = "s2.micro"
  service_account_id  = yandex_iam_service_account.vm_sa.id

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = var.lamp_image_id
      size     = 10
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.hw-subnet.id
    nat       = true
  }

  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}" # Замените пользователя (ubuntu/debian/centos) при необходимости
    user-data = <<-EOF
              #!/bin/bash
              IMG_URL="https://storage.yandexcloud.net/${yandex_storage_bucket.hw-bucket.bucket}/picture.jpg"
              cat <<HTML > /var/www/html/index.html
              <html>
              <head><title>HW Task</title></head>
              <body style="font-family: Arial; text-align: center;">
                <h1>Terraform HW - Yandex Cloud</h1>
                <p>Picture from Object Storage:</p>
                <img src="${IMG_URL}" alt="Task Picture" style="max-width: 80%; border: 2px solid #ccc;"/>
                <hr/>
                <p>Instance hostname: $(hostname)</p>
              </body>
              </html>
              systemctl restart apache2 || systemctl restart httpd
              EOF
  }
}

# 4. Группа ВМ (Instance Group)
resource "yandex_compute_instance_group" "lamp-group" {
  name               = "lamp-instance-group"
  service_account_id = yandex_iam_service_group_binding.saig-binding.service_account_id
  instance_template {
    platform_id = "standard-v3"
    resources {
      cores  = 2
      memory = 2
    }
    boot_disk {
      mode = "READ_WRITE"
      initialize_params {
        image_id = var.lamp_image_id
        size     = 10
      }
    }
    network_interface {
      network_id = yandex_vpc_network.hw-network.id
      subnet_ids = [yandex_vpc_subnet.hw-subnet.id]
      nat        = true
    }
    metadata = yandex_compute_instance_template.lamp-template.metadata
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
    max_expansion   = 2
    max_deleting    = 2
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

  load_balancer {
    target_group_name = "lamp-tg"
  }

  depends_on = [
    yandex_resourcemanager_folder_iam_binding.editor,
    yandex_resourcemanager_folder_iam_binding.loadbalancerAdmin
  ]
}

# 5. Сетевой балансировщик (NLB) для проверки работоспособности
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
    target_group_id = yandex_compute_instance_group.lamp-group.load_balancer[0].target_group_id
    healthcheck {
      name = "http-check"
      http_options {
        port = 80
        path = "/"
      }
    }
  }
}

# Ресурсы для Application Load Balancer (ALB)

# Лог-группа для ALB
resource "yandex_logging_group" "alb_logs" {
  name = "alb-logs-group"
}

# HTTP Router
resource "yandex_alb_http_router" "router" {
  name = "lamp-router"
}

# Virtual Host
resource "yandex_alb_virtual_host" "vh" {
  name           = "lamp-host"
  http_router_id = yandex_alb_http_router.router.id
  route {
    name = "route-to-tg"
    http_route {
      match {
        prefix = "/"
      }
      route_action {
        backend_group_id = yandex_alb_backend_group.bg.id
        timeout          = "60s"
      }
    }
  }
}

# Backend Group, привязанная к Target Group от Instance Group
resource "yandex_alb_backend_group" "bg" {
  name = "lamp-bg"

  http_backend {
    name             = "lamp-http-backend"
    weight           = 1
    port             = 80
    target_group_ids = [yandex_compute_instance_group.lamp-group.load_balancer[0].target_group_id]
    load_balancing_config {
      panic_threshold = 50
    }
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

# Собственно ALB
resource "yandex_alb_load_balancer" "alb" {
  name               = "lamp-alb"
  network_id         = yandex_vpc_network.hw-network.id
  security_group_ids = [yandex_vpc_default_security_group.sg.id] # Привязка к SG

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
        external_ipv4_address {
        }
      }
      ports = [80]
    }
    http {
      handler {
        http_router_id = yandex_alb_http_router.router.id
      }
    }
  }

  log_options {
    discard_rule {
      http_code_intervals = ["HTTP_2XX"]
      discard_percent     = 100
    }
  }

  logging {
    group_id = yandex_logging_group.alb_logs.id
    discard_rule {
      http_code_intervals = ["HTTP_2XX"]
      discard_percent     = 100
    }
  }
}

# Сервисный аккаунт для ресурсов (ВМ, IG, ALB)
resource "yandex_iam_service_account" "vm_sa" {
  name = "hw-vm-sa"
}

# Права для Service Account (запуск ВМ, запись в бакет, управление LB)
resource "yandex_resourcemanager_folder_iam_binding" "editor" {
  folder_id = var.folder_id
  role      = "editor"
  members   = [
    "serviceAccount:${yandex_iam_service_account.vm_sa.id}"
  ]
}

resource "yandex_resourcemanager_folder_iam_binding" "loadbalancerAdmin" {
  folder_id = var.folder_id
  role      = "load-balancer.admin"
  members   = [
    "serviceAccount:${yandex_iam_service_account.vm_sa.id}"
  ]
}

# Доступ к бакету для чтения (публичный доступ мы дали на уровне ACL, но SA нужен для внутренних операций если потребуется)
resource "yandex_storage_object_acl" "picture-acl" {
  bucket = yandex_storage_bucket.hw-bucket.id
  object = yandex_storage_object.picture.id
  access_control_policy {
    grants {
      permission = "FULL_CONTROL"
      grantee_type = "Group"
      grantee_id = "allUsers"
    }
  }
  depends_on = [yandex_storage_object.picture]
}

# Default Security Group для разрешения трафика до ALB/NLB
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
