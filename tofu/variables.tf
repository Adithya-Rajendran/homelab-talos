variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox API endpoint (https, via the reverse proxy on 443)."
}

variable "proxmox_api_token" {
  type        = string
  description = "Proxmox API token: USER@REALM!TOKENID=SECRET. Set via TF_VAR_proxmox_api_token."
  sensitive   = true
}

variable "proxmox_pool" {
  type        = string
  description = "Resource pool the token has VM.Allocate on."
  default     = "adi"
}

variable "talos_iso" {
  type        = string
  description = "Volume id of the Talos metal ISO already present on shared storage."
  default     = "TrueNAS:iso/talos-v1.13.5-metal-amd64.iso"
}

variable "vm_datastore" {
  type        = string
  description = "Datastore for VM disks (local NVMe lvm-thin for low etcd latency)."
  default     = "local-lvm"
}

variable "vm_bridge" {
  type        = string
  description = "Network bridge / SDN vnet for the VM NIC (Access vnet = VLAN 20 = 10.20.0.0/24)."
  default     = "Access"
}

variable "vm_cores" {
  type    = number
  default = 8
}

variable "vm_memory" {
  type        = number
  description = "Memory in MiB (ballooning disabled)."
  default     = 16384
}

variable "system_disk_gb" {
  type        = number
  description = "Talos system disk (sda): BOOT/EFI/META/STATE. EPHEMERAL is NOT placed here."
  default     = 20
}

variable "etcd_disk_gb" {
  type        = number
  description = "Dedicated disk (sdb) hosting the EPHEMERAL volume (/var incl. /var/lib/etcd)."
  default     = 180
}

# One VM per Proxmox node. Total per node = system_disk_gb + etcd_disk_gb (<= 200G).
variable "nodes" {
  type = map(object({
    vmid     = number
    pve_node = string
    ip       = string
  }))
  default = {
    "talos-cp-01" = { vmid = 110, pve_node = "more-stork", ip = "10.20.0.70" }
    "talos-cp-02" = { vmid = 111, pve_node = "light-tuna", ip = "10.20.0.71" }
    "talos-cp-03" = { vmid = 112, pve_node = "rapid-kit", ip = "10.20.0.72" }
  }
}
