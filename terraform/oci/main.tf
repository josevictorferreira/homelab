terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }
}

# Auth comes from ~/.oci/config (profile DEFAULT); no credentials in this repo.
provider "oci" {
  config_file_profile = "DEFAULT"
}

# --- Network ---

resource "oci_core_vcn" "homelab" {
  compartment_id = var.tenancy_ocid
  display_name   = "homelab-vcn"
  cidr_blocks    = ["10.20.0.0/16"]
  dns_label      = "homelab"
}

resource "oci_core_internet_gateway" "homelab" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.homelab.id
  display_name   = "homelab-igw"
}

resource "oci_core_default_route_table" "homelab" {
  manage_default_resource_id = oci_core_vcn.homelab.default_route_table_id

  route_rules {
    destination       = "0.0.0.0/0"
    network_entity_id = oci_core_internet_gateway.homelab.id
  }
}

resource "oci_core_security_list" "homelab" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.homelab.id
  display_name   = "homelab-seclist"

  # SSH, only from home — remove this rule once Tailscale SSH is confirmed working.
  dynamic "ingress_security_rules" {
    for_each = var.allow_public_ssh ? [1] : []
    content {
      protocol = "6" # TCP
      source   = var.admin_cidr
      tcp_options {
        min = 22
        max = 22
      }
    }
  }

  # Tailscale direct connections (avoids DERP relaying).
  ingress_security_rules {
    protocol = "17" # UDP
    source   = "0.0.0.0/0"
    udp_options {
      min = 41641
      max = 41641
    }
  }

  # Path MTU discovery.
  ingress_security_rules {
    protocol = "1" # ICMP
    source   = "0.0.0.0/0"
    icmp_options {
      type = 3
      code = 4
    }
  }

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_subnet" "public" {
  compartment_id    = var.tenancy_ocid
  vcn_id            = oci_core_vcn.homelab.id
  display_name      = "homelab-public"
  cidr_block        = "10.20.0.0/24"
  dns_label         = "pub"
  security_list_ids = [oci_core_security_list.homelab.id]
}

# --- Instance ---

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "ubuntu_arm" {
  compartment_id           = var.tenancy_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_instance" "lab_oci_bk" {
  compartment_id      = var.tenancy_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "lab-oci-bk"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = 4
    memory_in_gbs = 24
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_arm.images[0].id
    boot_volume_size_in_gbs = 200
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
    hostname_label   = "lab-oci-bk"
  }

  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key_path)
  }

  # The Ubuntu image is only a beachhead for nixos-anywhere; a new image
  # release must not trigger a destroy/recreate of the NixOS install.
  lifecycle {
    ignore_changes = [source_details, metadata]
  }
}
