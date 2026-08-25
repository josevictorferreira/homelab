# OCI free-tier ARM instance (lab-oci-bk) and its network, as a terranix module.
#
# Renders to config.tf.json; tofu must run from this directory so it picks up
# the gitignored terraform.tfvars and the provider lock file. Use `make tf`.
{ config, lib, ... }:

let
  inherit (lib) tfRef;

  # Resource/data handles. Calling one yields a terraform reference string,
  # e.g. `vcn "id"` -> "${oci_core_vcn.homelab.id}", so typos fail at eval time.
  vcn = config.resource.oci_core_vcn.homelab;
  igw = config.resource.oci_core_internet_gateway.homelab;
  seclist = config.resource.oci_core_security_list.homelab;
  subnet = config.resource.oci_core_subnet.public;
  instance = config.resource.oci_core_instance.lab_oci_bk;

  availabilityDomains = config.data.oci_identity_availability_domains.ads;
  ubuntuArm = config.data.oci_core_images.ubuntu_arm;

  # Everything is created in the root compartment.
  tenancy = tfRef "var.tenancy_ocid";
in
{
  terraform.required_providers.oci = {
    source = "oracle/oci";
    version = "~> 6.0";
  };

  # Auth comes from ~/.oci/config (profile DEFAULT); no credentials in this repo.
  provider.oci.config_file_profile = "DEFAULT";

  variable = {
    tenancy_ocid = {
      description = "Tenancy OCID (root compartment); everything is created in it";
      type = "string";
    };

    admin_cidr = {
      description = "CIDR allowed to SSH during bootstrap (home IP /32)";
      type = "string";
    };

    allow_public_ssh = {
      description = "Keep public port 22 open; set false once Tailscale SSH works";
      type = "bool";
      default = true;
    };

    ssh_public_key_path = {
      description = "SSH public key installed on the bootstrap Ubuntu image";
      type = "string";
      default = "~/.ssh/id_ed25519.pub";
    };

    budget_alert_email = {
      description = "Recipient of the budget alert that fires on any real spend";
      type = "string";
    };
  };

  data = {
    oci_identity_availability_domains.ads.compartment_id = tenancy;

    oci_core_images.ubuntu_arm = {
      compartment_id = tenancy;
      operating_system = "Canonical Ubuntu";
      operating_system_version = "24.04";
      shape = "VM.Standard.A1.Flex";
      sort_by = "TIMECREATED";
      sort_order = "DESC";
    };
  };

  resource = {
    # --- Cost guardrails ---
    # lab-oci-bk uses the whole Always Free allowance (4 OCPU / 24 GB A1,
    # 200 GB block storage), so anything else in the tenancy is billed. The
    # quota makes such allocations fail at the API instead; the budget emails
    # if a charge shows up anyway. Existing resources are never affected.
    oci_limits_quota.free_tier_only = {
      compartment_id = tenancy;
      name = "free-tier-only";
      description = "Hard-cap the tenancy to the Always Free allowance";
      statements = [
        "zero compute-core quotas in tenancy"
        "zero compute-memory quotas in tenancy"
        "set compute-core quota standard-a1-core-count to 4 in tenancy"
        "set compute-memory quota standard-a1-memory-count to 24 in tenancy"
        "set block-storage quota total-storage-gb to 200 in tenancy"
        "zero database quotas in tenancy"
        "zero load-balancer quotas in tenancy"
        "zero filesystem quotas in tenancy"
      ];
    };

    oci_budget_budget.zero_spend = {
      compartment_id = tenancy;
      display_name = "zero-spend";
      description = "Everything here must be Always Free";
      amount = 5; # BRL; alert threshold below is 1% of this
      reset_period = "MONTHLY";
      target_type = "COMPARTMENT";
      targets = [ tenancy ];
    };

    oci_budget_alert_rule.zero_spend = {
      budget_id = tfRef "oci_budget_budget.zero_spend.id";
      display_name = "any-spend";
      type = "ACTUAL";
      threshold = 1;
      threshold_type = "PERCENTAGE";
      recipients = tfRef "var.budget_alert_email";
      message = "OCI tenancy incurred a real charge; only Always Free resources are expected.";
    };

    # --- Network ---

    oci_core_vcn.homelab = {
      compartment_id = tenancy;
      display_name = "homelab-vcn";
      cidr_blocks = [ "10.20.0.0/16" ];
      dns_label = "homelab";
    };

    oci_core_internet_gateway.homelab = {
      compartment_id = tenancy;
      vcn_id = vcn "id";
      display_name = "homelab-igw";
    };

    oci_core_default_route_table.homelab = {
      manage_default_resource_id = vcn "default_route_table_id";

      route_rules = [
        {
          destination = "0.0.0.0/0";
          network_entity_id = igw "id";
        }
      ];
    };

    oci_core_security_list.homelab = {
      compartment_id = tenancy;
      vcn_id = vcn "id";
      display_name = "homelab-seclist";

      # SSH, only from home — remove this rule once Tailscale SSH is confirmed
      # working. Kept as a terraform-time conditional so the toggle stays a
      # `-var`/tfvars knob rather than a rebuild.
      dynamic.ingress_security_rules = {
        for_each = tfRef "var.allow_public_ssh ? [1] : []";
        content = {
          protocol = "6"; # TCP
          source = tfRef "var.admin_cidr";
          tcp_options = [
            {
              min = 22;
              max = 22;
            }
          ];
        };
      };

      ingress_security_rules = [
        # Tailscale direct connections (avoids DERP relaying).
        {
          protocol = "17"; # UDP
          source = "0.0.0.0/0";
          udp_options = [
            {
              min = 41641;
              max = 41641;
            }
          ];
        }
        # Path MTU discovery.
        {
          protocol = "1"; # ICMP
          source = "0.0.0.0/0";
          icmp_options = [
            {
              type = 3;
              code = 4;
            }
          ];
        }
      ];

      egress_security_rules = [
        {
          protocol = "all";
          destination = "0.0.0.0/0";
        }
      ];
    };

    oci_core_subnet.public = {
      compartment_id = tenancy;
      vcn_id = vcn "id";
      display_name = "homelab-public";
      cidr_block = "10.20.0.0/24";
      dns_label = "pub";
      security_list_ids = [ (seclist "id") ];
    };

    # --- Instance ---

    oci_core_instance.lab_oci_bk = {
      compartment_id = tenancy;
      availability_domain = availabilityDomains "availability_domains[0].name";
      display_name = "lab-oci-bk";
      shape = "VM.Standard.A1.Flex";

      shape_config = [
        {
          ocpus = 4;
          memory_in_gbs = 24;
        }
      ];

      source_details = [
        {
          source_type = "image";
          source_id = ubuntuArm "images[0].id";
          boot_volume_size_in_gbs = 200;
        }
      ];

      create_vnic_details = [
        {
          subnet_id = subnet "id";
          assign_public_ip = true;
          hostname_label = "lab-oci-bk";
        }
      ];

      metadata.ssh_authorized_keys = tfRef "file(var.ssh_public_key_path)";

      # The Ubuntu image is only a beachhead for nixos-anywhere; a new image
      # release must not trigger a destroy/recreate of the NixOS install.
      # ignore_changes takes bare attribute names, not interpolations.
      lifecycle = [
        { ignore_changes = [ "source_details" "metadata" ]; }
      ];
    };
  };

  output = {
    public_ip.value = instance "public_ip";
    image_used.value = ubuntuArm "images[0].display_name";
  };
}
