
output "public_ips_jenkins-hab" {
  value = "${aws_instance.jenkins-hab.public_ip}"
}
