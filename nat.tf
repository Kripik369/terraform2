data "yandex_compute_image" "nat_base" {
  image_id = var.nat_image_id
}

resource "yandex_compute_instance" "nat-instance" {
  name        = "nat-instance"
  platform_id = "standard-v3"
  zone        = var.zone_public
  hostname    = "nat-instance"

  resources {
    cores  = 2
    memory = 2
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.nat_base.id
      size     = 20
      type     = "network-hdd"
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.public.id
    ip_address         = "192.168.10.254"
    nat                = false
    security_group_ids = [yandex_vpc_security_group.nat_sg.id]
  }

  metadata = {
    user-data = <<-EOF
              #cloud-config
              write_files:
                - path: /etc/sysctl.d/99-custom.conf
                  content: |
                    net.ipv4.ip_forward=1
                    net.ipv4.conf.all.rp_filter=0
                    net.ipv4.conf.default.rp_filter=0
              runcmd:
                - [ sysctl, -p, /etc/sysctl.d/99-custom.conf ]
                - [ iptables, -t, nat, -A, POSTROUTING, -o, eth0, "-j", MASQUERADE ]
                - [ iptables, -A, FORWARD, -m, conntrack, "--ctstate", RELATED,ESTABLISHED, "-j", ACCEPT ]
                - [ iptables, -A, FORWARD, -s, 192.168.20.0/24, "-j", ACCEPT ]
              EOF
  }
}

# Security Group для NAT (разрешить маскировку трафика)
resource "yandex_vpc_security_group" "nat_sg" {
  name        = "nat-sg"
  network_id  = yandex_vpc_network.main.id

  egress {
    protocol       = "ICMP" 
    description    = "Allow all outbound"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    port           = 22
    description    = "SSH for management"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "ICMP" 
    description    = "Allow traffic from private subnet"
    v4_cidr_blocks = ["192.168.20.0/24"]
  }
}
