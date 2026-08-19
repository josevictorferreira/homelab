variable "tenancy_ocid" {
  description = "Tenancy OCID (root compartment); everything is created in it"
  type        = string
}

variable "admin_cidr" {
  description = "CIDR allowed to SSH during bootstrap (home IP /32)"
  type        = string
}

variable "allow_public_ssh" {
  description = "Keep public port 22 open; set false once Tailscale SSH works"
  type        = bool
  default     = true
}

variable "ssh_public_key_path" {
  description = "SSH public key installed on the bootstrap Ubuntu image"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
