.DEFAULT_GOAL := help

setup: ## Setup the services, expects parameter service=service_name
	@echo "Setting up $(service)"
ifeq ($(service),metallb)
	helm upgrade --install metallb-system --kube-context homeserver --create-namespace --namespace metallb-system --values k8s/metallb/values.yaml k8s/metallb
else ifeq ($(service),pihole)
	helm upgrade --install pihole --kube-context homeserver --create-namespace -n production --values pihole/production.yaml pihole
else ifeq ($(service),filebrowser)
	helm upgrade --install filebrowser --kube-context homeserver --create-namespace -n production --values filebrowser/production.yaml filebrowser
else ifeq ($(service),qbittorrent)
	helm upgrade --install qbittorrent --kube-context homeserver --create-namespace -n production --values qbittorrent/values.yaml qbittorrent
else ifeq ($(service),prometheus)
	helm upgrade --install prometheus --kube-context homeserver --create-namespace -n monitoring --values k8s/monitoring/kube-prometheus-stack/production.yaml k8s/monitoring/kube-prometheus-stack/
else ifeq ($(service),readarr)
	helm upgrade --install readarr --kube-context homeserver --create-namespace -n production --values readarr/production.yaml readarr
else
	@echo "Service not found."
endif

delete: ## Delete the services, expects parameter service=service_name
	@echo "Deleting $(service)"
ifeq ($(service),metallb)
	helm delete metallb-system --kube-context homeserver -n metallb-system
else ifeq ($(service),pihole)
	helm delete pihole --kube-context homeserver -n production
else ifeq ($(service),filebrowser)
	helm delete filebrowser --kube-context homeserver -n production
else ifeq ($(service),qbittorrent)
	helm delete qbittorrent --kube-context homeserver -n production
else ifeq ($(service),prometheus)
	helm delete prometheus --kube-context homeserver -n monitoring
else ifeq ($(service),readarr)
	helm delete readarr --kube-context homeserver -n production
else
	@echo "Service not found."
endif

services: ## List services available to setup
	@echo "Services Available:"
	@echo "  - metallb"
	@echo "  - pihole"
	@echo "  - filebrowser"
	@echo "  - qbittorrent"
	@echo "  - prometheus"
	@echo "  - readarr"

sync:
	helmfile --environment homeserver sync

syncd:
	helmfile --environment homeserver sync --debug

help: ## Show this help.
	@printf "Usage: make [target]\n\nTARGETS:\n"; grep -F "##" $(MAKEFILE_LIST) | grep -Fv "grep -F" | grep -Fv "printf " | sed -e 's/\\$$//' | sed -e 's/##//' | column -t -s ":" | sed -e 's/^/    /'; printf "\n"
