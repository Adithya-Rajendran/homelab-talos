output "nodes" {
  description = "Talos node name -> static IP / vmid / pve node."
  value = {
    for k, v in var.nodes : k => {
      ip       = v.ip
      vmid     = v.vmid
      pve_node = v.pve_node
    }
  }
}

output "vm_ids" {
  description = "Created Proxmox VM ids."
  value       = [for vm in proxmox_virtual_environment_vm.talos : vm.vm_id]
}

output "controlplane_vip" {
  value = "10.20.0.79"
}
