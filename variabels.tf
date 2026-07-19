variable "folder_id" {
  description = "ID каталога в Yandex Cloud"
  type        = string
}

variable "zone_public" {
  description = "Зона доступности для публичной подсети"
  type        = string
  default     = "ru-central1-a"
}

variable "zone_private" {
  description = "Зона доступности для приватной подсети"
  type        = string
  default     = "ru-central1-a"
}

variable "nat_image_id" {
  description = "Image ID для NAT-инстанса"
  type        = string
  default     = "fd80mrhj8fl2oe87o4e1"
}

variable "vm_username" {
  description = "Имя пользователя для подключения к VM"
  type        = string
  default     = "ubuntu"
}
