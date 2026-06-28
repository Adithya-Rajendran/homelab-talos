# Non-secret values (safe to commit). The API token is NOT here — it is passed via
# the environment:  export TF_VAR_proxmox_api_token='adi@pve!claude=<secret>'
proxmox_endpoint = "https://proxmox.adithya-rajendran.com"
proxmox_pool     = "adi"
talos_iso        = "TrueNAS:iso/talos-v1.13.5-metal-amd64.iso"
vm_datastore     = "local-lvm"
vm_bridge        = "Access"
vm_cores         = 8
vm_memory        = 16384
system_disk_gb   = 20
etcd_disk_gb     = 180
