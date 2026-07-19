terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.217"
    }
  }
}

provider "yandex" {
  folder_id = var.folder_id
  zone      = var.zone_public 
}

# Создаем пустую сеть VPC
resource "yandex_vpc_network" "main" {
  name = "network-task-1"
}

# Публичная подсеть
resource "yandex_vpc_subnet" "public" {
  name           = "public"
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = ["192.168.10.0/24"]
  zone           = var.zone_public
}

# Приватная подсеть с привязкой таблицы маршрутов
resource "yandex_vpc_subnet" "private" {
  name           = "private"
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = ["192.168.20.0/24"]
  zone           = var.zone_private
  route_table_id = yandex_vpc_route_table.private_to_nat.id

  lifecycle {
    ignore_changes = [route_table_id]
  }
}

# Таблица маршрутизации для приватной сети (указываем IP NAT-инстанса)
resource "yandex_vpc_route_table" "private_to_nat" {
  network_id = yandex_vpc_network.main.id

  static_route {
    destination_prefix = "0.0.0.0/0"
    next_hop_address   = yandex_compute_instance.nat-instance.network_interface.0.ip_address
  }
}
