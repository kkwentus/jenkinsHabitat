terraform {
  required_version = "> 0.11.0"
}

provider "aws" {
  profile                 = "${var.aws_profile}"
  shared_credentials_file = "~/.aws/credentials"
  region                  = "${var.aws_region}"
}

resource "random_id" "jenkins_hab_id" {
  byte_length = 4
}

resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"

  tags {
    Name = "${var.aws_key_pair_name}_${random_id.jenkins_hab_id.hex}_jenkins_hab"
  }
}

resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.default.id}"
}

resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.default.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.default.id}"
}

resource "aws_subnet" "default" {
  vpc_id                  = "${aws_vpc.default.id}"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

////////////////////////////////
// Firewalls

resource "aws_security_group" "jenkins-hab" {
  name        = "${var.aws_key_pair_name}-${random_id.jenkins_hab_id.hex}-jenkins-hab"
  description = "jenkins hab demo security group"
  vpc_id      = "${aws_vpc.default.id}"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9631
    to_port     = 9631
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9638
    to_port     = 9638
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9631
    to_port     = 9631
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 9638
    to_port     = 9638
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    X-Contact     = "${var.aws_key_pair_name} <maintainer@example.com>"
    X-Application = "jenkins-hab"
    X-ManagedBy   = "Terraform"
  }
}


////////////////////////////////
// Instances

data "aws_ami" "centos" {
  most_recent = true
  owners      = ["446539779517"]

  filter {
    name   = "name"
    values = ["chef-highperf-centos7-*"]
  }
}

resource "aws_instance" "jenkins-hab" {
  connection {
    user        = "${var.aws_ami_user}"
    private_key = "${file("${var.aws_key_pair_file}")}"
  }

  ami                         = "${var.aws_ami_id == "" ? data.aws_ami.centos.id : var.aws_ami_id}"
  instance_type               = "${var.aws_instance_type}"
  key_name                    = "${var.aws_key_pair_name}"
  subnet_id                   = "${aws_subnet.default.id}"
  vpc_security_group_ids      = ["${aws_security_group.jenkins-hab.id}"]
  associate_public_ip_address = true

  tags {
    Name          = "${var.aws_key_pair_name}_${random_id.jenkins_hab_id.hex}_jenkins_hab"
    X-Dept        = "${var.tag_dept}"
    X-Customer    = "${var.tag_customer}"
    X-Project     = "${var.tag_project}"
    X-Application = "${var.tag_application}"
    X-Contact     = "${var.tag_contact}"
    X-TTL         = "${var.tag_ttl}"
  }

  provisioner "file" {
    content     = "${data.template_file.install_hab.rendered}"
    destination = "/tmp/install_hab.sh"
  }

  provisioner "file" {
    content     = "${data.template_file.sup_service.rendered}"
    destination = "/home/${var.aws_ami_user}/hab-sup.service"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo groupadd hab",
      "sudo adduser hab -g hab",
      "chmod +x /tmp/install_hab.sh",
      "sudo /tmp/install_hab.sh",
      "sudo mv /home/${var.aws_ami_user}/hab-sup.service /etc/systemd/system/hab-sup.service",
      "sudo systemctl daemon-reload",
      "sudo systemctl start hab-sup",
      "sudo systemctl enable hab-sup",
      "sleep 15",
      "sudo hab svc load ${var.habitat_origin}/${var.habitat_package} --group ${var.group} --channel ${var.release_channel} --strategy ${var.update_strategy}"
    ]
  }
}

////////////////////////////////
// Templates


data "template_file" "jenkins_toml" {
  template = "${file("${path.module}/templates/jenkins_toml.tpl")}"

  vars {
    username = "${var.jenkins_admin_username}"
    password = "${var.jenkins_admin_password}"
  }
}


data "template_file" "sup_service" {
  template = "${file("${path.module}/templates/hab-sup.service")}"

  vars {
    flags = "--auto-update"
  }
}

data "template_file" "install_hab" {
  template = "${file("${path.module}/templates/install-hab.sh")}"
}
