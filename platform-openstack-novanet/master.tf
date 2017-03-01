resource "openstack_compute_instance_v2" "master_node" {
  count           = "${var.master_count}"
  name            = "master_node_${count.index}"
  image_id        = "${var.image_id}"
  flavor_id       = "${var.flavor_id}"
  key_pair        = "${openstack_compute_keypair_v2.k8s_keypair.name}"
  security_groups = ["${openstack_compute_secgroup_v2.k8s_master_group.name}"]

  metadata {
    role = "master"
  }

  user_data    = "${ignition_config.master.*.rendered[count.index]}"
  config_drive = false
}

resource "openstack_compute_secgroup_v2" "k8s_master_group" {
  name        = "k8s_master_group"
  description = "security group for k8s masters: SSH and https"

  rule {
    from_port   = 22
    to_port     = 22
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }

  rule {
    from_port   = 443
    to_port     = 443
    ip_protocol = "tcp"
    cidr        = "0.0.0.0/0"
  }

  rule {
    from_port   = -1
    to_port     = -1
    ip_protocol = "icmp"
    cidr        = "0.0.0.0/0"
  }
}

resource "null_resource" "copy_assets" {
  # Changes to any instance of the cluster requires re-provisioning
  triggers {
    cluster_instance_ids = "${join(" ", openstack_compute_instance_v2.master_node.*.id)}"
  }

  # Bootstrap script can run on any instance of the cluster
  # So we just choose the first in this case
  connection {
    user        = "core"
    private_key = "${tls_private_key.core.private_key_pem}"
    host        = "${element(openstack_compute_instance_v2.master_node.*.access_ip_v4, 0)}"
  }

  provisioner "file" {
    source      = "${path.cwd}/assets"
    destination = "/home/core/assets"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mv /home/core/assets /opt/bootkube/",
      "sudo chmod a+x /opt/bootkube/assets/bootkube-start",
      "sudo systemctl start bootkube",
    ]
  }
}