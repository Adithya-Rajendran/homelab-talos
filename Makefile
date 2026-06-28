# Convenience wrappers around the bootstrap + upgrade flows. See README.md for the full story.
# Requires: mise install; TF_VAR_proxmox_api_token exported; SOPS age key in place.
SHELL := /bin/bash
KUBECONFIG ?= $(CURDIR)/kubeconfig
TALOSCONFIG ?= $(CURDIR)/talos/clusterconfig/talosconfig
export KUBECONFIG TALOSCONFIG

.PHONY: help
help: ## Show targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n",$$1,$$2}'

## ---- Layer 1: VMs ----
.PHONY: vms vms-plan vms-destroy
vms-plan: ## tofu plan the VMs
	cd tofu && tofu init -input=false && tofu plan
vms: ## tofu apply the VMs
	cd tofu && tofu init -input=false && tofu apply -auto-approve
vms-destroy: ## tofu destroy the VMs (DANGER)
	cd tofu && tofu destroy

## ---- Layer 1: Talos ----
.PHONY: talos-secret talos-config talos-bootstrap talos-kubeconfig talos-upgrade k8s-upgrade health
talos-secret: ## generate + SOPS-encrypt the cluster secret (run once)
	cd talos && talhelper gensecret > talsecret.sops.yaml && sops -e -i talsecret.sops.yaml
talos-config: ## render machineconfigs into talos/clusterconfig (gitignored)
	cd talos && talhelper genconfig
talos-bootstrap: ## bootstrap etcd on cp-01 (run ONCE)
	cd talos && talosctl bootstrap -n 10.20.0.70 -e 10.20.0.70
talos-kubeconfig: ## fetch the cluster kubeconfig
	cd talos && talosctl kubeconfig -n 10.20.0.70 -e 10.20.0.70 ../kubeconfig -f
talos-upgrade: talos-config ## upgrade Talos OS (edit talenv.yaml first). ONE node at a time.
	cd talos && talhelper gencommand upgrade
k8s-upgrade: talos-config ## upgrade Kubernetes (edit talenv.yaml first)
	cd talos && talhelper gencommand upgrade-k8s
health: ## talos health
	cd talos && talosctl health

## ---- Layer 2: GitOps ----
.PHONY: cilium gateway-crds argocd root
gateway-crds: ## install Gateway API CRDs (pre-Cilium)
	kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml
	kubectl apply --server-side -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.5.1/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml
cilium: gateway-crds ## bootstrap Cilium (pre-Argo)
	helm repo add cilium https://helm.cilium.io && helm repo update cilium
	helm upgrade --install cilium cilium/cilium --version 1.19.5 -n kube-system -f kubernetes/bootstrap/cilium-values.yaml
argocd: ## install Argo CD
	kubectl apply -k kubernetes/bootstrap/argocd --server-side
root: ## apply the project + app-of-apps (hand off to GitOps)
	kubectl apply -f kubernetes/argocd/project.yaml
	kubectl apply -f kubernetes/argocd/root-app.yaml
