output "public_ip" {
  value = oci_core_instance.lab_oci_bk.public_ip
}

output "image_used" {
  value = data.oci_core_images.ubuntu_arm.images[0].display_name
}
