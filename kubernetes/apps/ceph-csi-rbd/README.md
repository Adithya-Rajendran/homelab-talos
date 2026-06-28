# ceph-csi-rbd cephx credential

The `ceph-csi-rbd` Application (../../argocd/apps/ceph-csi-rbd.yaml) deploys the CSI driver +
the default `ceph-rbd` StorageClass, but it does **not** carry the Ceph credential. That is supplied
here as a **SealedSecret** (`csi-rbd-secret.sealedsecret.yaml`) so the plaintext cephx key never
lives in git — only the Talos cluster's sealed-secrets controller can decrypt it.

The SealedSecret contains `userID` + `userKey` for a cephx client with access to the `kubernetes`
RBD pool on the external Proxmox Ceph cluster (mons `10.100.0.11/.12/.13`).

## Regenerate / rotate
```bash
# Best practice: a DEDICATED cephx user (run on a Proxmox/Ceph node):
#   ceph auth get-or-create client.talos mon 'profile rbd' osd 'profile rbd pool=kubernetes'
# Then seal its id/key against THIS cluster's controller:
kubectl create secret generic csi-rbd-secret -n ceph-csi-rbd \
  --from-literal=userID=talos --from-literal=userKey='<key>' \
  --dry-run=client -o yaml \
| kubeseal --controller-name sealed-secrets-controller --controller-namespace kube-system \
    --format yaml > csi-rbd-secret.sealedsecret.yaml
git add -A && git commit -m "rotate ceph cephx secret" && git push   # Argo applies it
```
