# 3x Talos VMs, one per Proxmox node. API-only (no SSH): each VM boots the Talos ISO
# and self-installs to /dev/sda from the pinned Image Factory installer (set in talconfig).
#
# etcd latency tuning (Proxmox side), paired with the EPHEMERAL-on-sdb VolumeConfig:
#   - scsi_hardware = virtio-scsi-single  -> a dedicated controller + iothread PER disk
#   - iothread = true, cache = none, aio = io_uring  -> direct, low-latency fsync
#   - disks on local NVMe (local-lvm); discard + ssd for thin TRIM
resource "proxmox_virtual_environment_vm" "talos" {
  for_each = var.nodes

  name      = each.key
  vm_id     = each.value.vmid
  node_name = each.value.pve_node
  pool_id   = var.proxmox_pool
  tags      = ["talos", "k8s", "gitops"]

  machine         = "q35"
  bios            = "ovmf"
  scsi_hardware   = "virtio-scsi-single"
  on_boot         = true
  started         = true
  stop_on_destroy = true

  agent {
    enabled = true # qemu-guest-agent is baked into the Image Factory image
  }

  operating_system {
    type = "l26"
  }

  cpu {
    cores = var.vm_cores
    type  = "host" # identical MS-01 hardware; expose full CPU features
  }

  memory {
    dedicated = var.vm_memory
    floating  = 0 # disable ballooning (Talos has no balloon driver)
  }

  efi_disk {
    datastore_id      = var.vm_datastore
    type              = "4m"
    pre_enrolled_keys = false
    file_format       = "raw"
  }

  # sda — Talos system disk (install target)
  disk {
    datastore_id = var.vm_datastore
    interface    = "scsi0"
    size         = var.system_disk_gb
    iothread     = true
    cache        = "none"
    aio          = "io_uring"
    discard      = "on"
    ssd          = true
    file_format  = "raw"
  }

  # sdb — dedicated disk for the EPHEMERAL volume (/var, incl. /var/lib/etcd)
  disk {
    datastore_id = var.vm_datastore
    interface    = "scsi1"
    size         = var.etcd_disk_gb
    iothread     = true
    cache        = "none"
    aio          = "io_uring"
    discard      = "on"
    ssd          = true
    file_format  = "raw"
  }

  cdrom {
    file_id   = var.talos_iso
    interface = "ide3"
  }

  # Disk first, ISO as fallback: first boot (empty disk) falls through to the installer;
  # subsequent boots run from the installed system. No manual ISO eject needed.
  boot_order = ["scsi0", "ide3"]

  # net0 — primary (VLAN 20 / Access): node IP + control-plane VIP + default route
  network_device {
    bridge      = var.vm_bridge
    model       = "virtio"
    mac_address = each.value.mac
  }

  # net1 — storage (VLAN 100 / Ceph): reaches the Ceph mons (10.100.0.11/.12/.13)
  network_device {
    bridge      = var.ceph_bridge
    model       = "virtio"
    mac_address = each.value.ceph_mac
  }

  serial_device {} # socket (required; Talos console + early-boot logs)

  vga {
    type = "serial0"
  }

  lifecycle {
    # Talos manages the disk after install; don't let re-applies churn the CD/agent.
    ignore_changes = [cdrom]
  }
}
