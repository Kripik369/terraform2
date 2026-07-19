output "public_vm_external_ip" {
  value = yandex_compute_instance.public-vm.network_interface.0.nat_ip_address
  description = "Публичный IP для входа в bastion-хост"
}

output "private_vm_internal_ip" {
  value = yandex_compute_instance.private-vm.network_interface.0.ip_address
  description = "Внутренний IP приватной машины"
}

output "nat_instance_internal_ip" {
  value = yandex_compute_instance.nat-instance.network_interface.0.ip_address
  description = "Внутренний IP NAT-инстанса"
}
