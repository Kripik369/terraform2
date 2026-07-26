output "bucket_url" {
  value = "https://storage.yandexcloud.net/${yandex_storage_bucket.hw-bucket.bucket}/${yandex_storage_object.picture.key}"
}

output "nlb_ip_address" {
  value = yandex_lb_network_load_balancer.nlb.listener[0].external_address_spec[0].address
}

output "alb_ip_address" {
  value = yandex_alb_load_balancer.alb.listener[0].endpoint[0].address[0].external_ipv4_address[0].address
}

output "vm_external_ips" {
  value = [for vm in yandex_compute_instance_group.lamp-group.instances : vm.network_interface[0].nat_ip_address]
}
