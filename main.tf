terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.217"
    }
  }
}


provider "yandex" {
  zone      = "ru-central1-a"
  folder_id = "b1gkmictp27f0rq4fjg4"
}

resource "yandex_kms_symmetric_key" "bucket_key" {
  name              = "bucket-encryption-key"
  default_algorithm = "AES_256"
}
resource "yandex_storage_bucket" "encrypted_bucket" {
  bucket     = "my-tf-encrypted-bucket-andrey-2607"
  folder_id  = "b1gkmictp27f0rq4fjg4" # Явно указываем ID из вашего yc config list

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        kms_master_key_id = yandex_kms_symmetric_key.bucket_key.id
        sse_algorithm     = "aws:kms"
      }
    }
  }
}
