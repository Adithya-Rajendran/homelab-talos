provider "proxmox" {
  endpoint = var.proxmox_endpoint
  # API token in the form: USER@REALM!TOKENID=SECRET
  # Provide via environment: export TF_VAR_proxmox_api_token='adi@pve!claude=xxxxxxxx'
  api_token = var.proxmox_api_token
  # The Proxmox API is reached through an openresty reverse proxy on 443 with a
  # non-PVE cert; skip TLS verification.
  insecure = true

  # NOTE: no ssh{} block on purpose. SSH (22) and 8006 to the PVE nodes are not
  # reachable from the management host, so this config deliberately uses ONLY API
  # operations: VMs boot an existing ISO and self-install (no qm importdisk / uploads).
}
