
resource "yandex_compute_instance" "private-vm" {
  name        = "private-vm"
  platform_id = "standard-v3"
  zone        = var.zone_private

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.lts.id
      size     = 20
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.private.id
    nat       = false
  }

  metadata = {
    ssh-keys = "${var.vm_username}:${file("~/.ssh/id_ed25519.pub")}"
  }
}
