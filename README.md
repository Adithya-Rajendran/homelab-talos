# talos-proxmox-gitops

A 3-node **Talos Linux** Kubernetes cluster on **Proxmox**, provisioned with **OpenTofu** and
**talhelper**, and managed end-to-end by **GitOps (Argo CD)** — both the cluster lifecycle
(Talos / Kubernetes versions + machine config) *and* the in-cluster platform are driven by editing
files in this repo.

Built to mirror an existing RKE2 cluster: **Cilium** (kube-proxy replacement + Gateway API + L2
LoadBalancer), **cert-manager**, with secrets via **Sealed Secrets**.

## Architecture

| | |
|---|---|
| Nodes | 3× control-plane + schedulable (hyperconverged), `10.20.0.70/.71/.72` |
| Control-plane VIP | `10.20.0.79` (Talos shared L2 VIP) → `https://10.20.0.79:6443` |
| Talos / Kubernetes | `v1.13.5` / `v1.36.2` (pinned in [`talos/talenv.yaml`](talos/talenv.yaml)) |
| CNI | Cilium `1.19.5`, `kubeProxyReplacement=true`, Gateway API, KubePrism `:7445` |
| Pod / Service CIDR | `10.244.0.0/16` / `10.96.0.0/12` (non-overlapping with RKE2) |
| LoadBalancer IPs | Cilium L2, pool `10.20.0.224/28` (RKE2 uses `.240/.250`) |
| GitOps | Argo CD `v3.4.4` (app-of-apps) |
| Secrets | Talos PKI → SOPS+age (talhelper); in-cluster → Sealed Secrets |

### Two layers, one repo
- **OS / Kubernetes lifecycle** — `tofu/` (VMs) + `talos/` (machineconfig via talhelper). Upgrades
  are a git diff in `talos/talenv.yaml` followed by a `talhelper` command (humans/CI run it; Argo
  does **not** reboot nodes).
- **In-cluster platform** — `kubernetes/` reconciled by Argo CD. Component upgrades are a git diff;
  Argo syncs automatically.

### etcd latency design
etcd's data dir (`/var/lib/etcd`) is fixed and lives on the `EPHEMERAL` (`/var`) volume. Talos 1.13
removed `machine.disks`, so the supported way to give etcd a fast/dedicated disk is to pin the
`EPHEMERAL` volume to a second disk via a `VolumeConfig` diskSelector
([`talos/patches/etcd-on-dedicated-disk.yaml`](talos/patches/etcd-on-dedicated-disk.yaml)). That disk
(`sdb`) is tuned in Proxmox for low fsync latency: dedicated `virtio-scsi-single` controller +
`iothread`, `cache=none`, `aio=io_uring`, on local NVMe ([`tofu/vms.tf`](tofu/vms.tf)).

## Directory layout
```
tofu/                 OpenTofu (bpg/proxmox): the 3 VMs (API-only, ISO self-install)
talos/
  talenv.yaml         ← EDIT to upgrade Talos / Kubernetes
  talconfig.yaml      talhelper cluster definition
  talsecret.sops.yaml cluster PKI (SOPS+age encrypted)
  patches/            cni-none / kube-proxy-off / etcd-disk / dns+ntp+kubeprism
kubernetes/
  bootstrap/          one-time, pre-Argo: cilium-values.yaml, argocd/ install
  argocd/             AppProject + root app-of-apps + per-component Applications
  apps/               manifests the Applications point at (network, cert-manager, sealed-secrets)
```

## Prerequisites
- `mise install` (pins all CLIs — see [`.mise.toml`](.mise.toml)).
- A Proxmox API token with VM/Datastore/SDN rights; export it (never commit):
  `export TF_VAR_proxmox_api_token='adi@pve!claude=<secret>'`
- The SOPS age private key at `~/.config/sops/age/keys.txt` (back it up offline — it is the root of
  trust for the Talos secrets).
- The Talos `metal` ISO (built via the Image Factory schematic in `talos/schematic.yaml`) present on
  the `TrueNAS` ISO storage as `talos-v1.13.5-metal-amd64.iso`.

## Bootstrap (from zero)
```bash
mise install

# 1. VMs (creates + boots the 3 VMs; they DHCP into Talos maintenance mode)
cd tofu && tofu init && tofu apply && cd ..

# 2. Talos config + bootstrap
cd talos
talhelper genconfig                       # renders ./clusterconfig (gitignored)
# apply each rendered config to that node's *maintenance-mode DHCP IP* (one-time, --insecure)
talosctl apply-config --insecure -n <dhcp-ip-1> -f clusterconfig/talos-homelab-talos-cp-01.yaml
talosctl apply-config --insecure -n <dhcp-ip-2> -f clusterconfig/talos-homelab-talos-cp-02.yaml
talosctl apply-config --insecure -n <dhcp-ip-3> -f clusterconfig/talos-homelab-talos-cp-03.yaml
export TALOSCONFIG=$PWD/clusterconfig/talosconfig
talosctl bootstrap -n 10.20.0.70 -e 10.20.0.70           # ONCE, single node
talosctl kubeconfig -n 10.20.0.70 -e 10.20.0.70 ../kubeconfig -f
cd ..
export KUBECONFIG=$PWD/kubeconfig

# 3. CNI (nodes are NotReady until this runs)
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml
kubectl apply --server-side -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.5.1/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml
helm repo add cilium https://helm.cilium.io && helm repo update
helm install cilium cilium/cilium --version 1.19.5 -n kube-system -f kubernetes/bootstrap/cilium-values.yaml

# 4. Argo CD + hand off to GitOps
kubectl apply -k kubernetes/bootstrap/argocd --server-side
kubectl apply -f kubernetes/argocd/project.yaml
kubectl apply -f kubernetes/argocd/root-app.yaml      # app-of-apps: Argo now manages everything
```

## Upgrade-by-git (the whole point)
- **Talos or Kubernetes version**: edit `talos/talenv.yaml` → commit → then run:
  ```bash
  cd talos && talhelper genconfig
  talhelper gencommand upgrade --extra-flags --preserve     # Talos OS, ONE node at a time
  talhelper gencommand upgrade-k8s                          # Kubernetes
  ```
  Wait for `talosctl health` / etcd quorum **between each node**. Argo does not do this — git is the
  desired-state record; a human/CI runs the command.
- **In-cluster component** (Cilium, cert-manager, …): bump the chart version / values in
  `kubernetes/argocd/apps/*` or `kubernetes/bootstrap/cilium-values.yaml` → commit → Argo auto-syncs.
- **VM shape** (cores/RAM/disk/new node): edit `tofu/` → `tofu apply`.
- **Renovate** opens PRs for charts, images, Actions, and Talos/k8s versions; OS-level bumps are
  gated behind manual approval (they reboot nodes).

## Secrets
- **Talos PKI**: `talos/talsecret.sops.yaml`, SOPS+age. Only encrypted material is committed.
- **In-cluster**: `kubeseal` → commit `SealedSecret` CRs; the controller decrypts in-cluster.

## Notes
- This repo intentionally contains internal RFC1918 IPs and a homelab hostname (portfolio repo). No
  credentials are committed — the API token, age private key, kubeconfig, talosconfig, and rendered
  machineconfigs are all gitignored.
