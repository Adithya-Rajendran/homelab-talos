terraform {
  required_version = ">= 1.9"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111"
    }
  }

  # Local state by default. For durability/portfolio you can switch to an encrypted
  # remote backend (e.g. S3/MinIO). State contains no secrets here (token via env var),
  # but it does record VM details — keep it out of git (see .gitignore).
}
