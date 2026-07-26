variable "folder_id" {
  description = "ID каталога в Yandex Cloud"
  type        = string
}

variable "cloud_id" {
  description = "ID облака"
  type        = string
}

variable "zone" {
  description = "Зона доступности"
  type        = string
  default     = "ru-central1-a"
}

variable "bucket_name" {
  description = "Имя бакета Object Storage (должно быть уникальным глобально)"
  type        = string
}

variable "image_path" {
  description = "Путь к локальной картинке"
  type        = string
  default     = "img/picture.jpg"
}

variable "lamp_image_id" {
  description = "Image ID для LAMP стека из задания"
  type        = string
  default     = "fd827b91d99psvq5fjit"
}

variable "vm_count" {
  description = "Количество ВМ в группе"
  type        = number
  default     = 3
}

variable "network_cidr" {
  description = "CIDR для внутренней сети"
  type        = string
  default     = "10.1.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR для публичной подсети"
  type        = string
  default     = "10.1.1.0/24"
}
