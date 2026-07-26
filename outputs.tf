output "alb_dns_name" {
  description = "FQDN балансировщика ALB"
  value       = yandex_alb_load_balancer.alb.listener[0].endpoint[0].address[0].external_ipv4_address[0].address
}

output "vm_external_ips" {
  value = [for vm in yandex_compute_instance_group.lamp-group.instances : vm.network_interface[0].nat_ip_address]
}
