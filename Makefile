.PHONY: lgroups check ddeploy deploy gdeploy secrets manifests kubesync wusbiso docker-build docker-login docker-init-repo docker-push lint format backup-postgres restore-postgres reconcile events backup-rgw backup-etcd backup-verify images images-outdated images-check help

.DEFAULT_GOAL := help

MAKEFLAGS += --no-print-directory

lgroups: ## List available node groups.
	@nix run .#lgroups

check: ## Check if the flake is valid.
	@nix run .#check

ddeploy: ## Dry deploy host.
	@nix run .#run_ddeploy

deploy: ## Deploy host.
	@nix run .#run_deploy

gdeploy: ## Deploy hosts that belong to a group.
	@nix run .#run_gdeploy

secrets: ## Edit the secrets files.
	@nix run .#secrets

manifests: ## Fully render k8s manifests, including generating secrets and encrypting them.
	@nix run .#manifests

kubesync: ## Write kubeconfig from the cluster to kubectl config.
	@nix run .#kubesync

wusbiso: ## Build the recovery ISO, formats the USB drive and writes the ISO to it.
	@nix run .#wusbiso

reconcile: ## Reconcile the kubernetes cluster with the current main branch.
	@nix run .#reconcile

events: ## Watch for the latest events in flux kubernetes system.
	@nix run .#events

docker-build: ## Build the Docker image using nix-build.
	@nix run .#docker-build

docker-login: ## Login to GitHub Container Registry using GitHub CLI or GITHUB_TOKEN.
	@nix run .#docker-login

docker-init-repo: ## Initialize the GitHub Container Registry repository.
	@nix run .#docker-init-repo

docker-push: ## Build and push the Docker image to GitHub Container Registry.
	@nix run .#docker-push

lint: ## Lint the nix files.
	@nix run .#lint

format: ## Format the nix files.
	@nix run .#format

backup-postgres: ## Create a .sql backup of all postgresql data.
	@nix run .#backup-postgres

restore-postgres: ## Restore a .sql backup data to the postgresql.
	@nix run .#restore-postgres

backup-rgw: ## Trigger ad-hoc RGW→MinIO mirror job.
	@kubectl create job --from=cronjob/rgw-mirror -n applications rgw-mirror-manual-$$(date +%s) && echo "Job created. Watch: kubectl get jobs -n applications -w"

backup-etcd: ## Trigger ad-hoc etcd snapshot offload on all control-plane nodes.
	@for host in lab-alpha-cp lab-beta-cp lab-delta-cp; do echo "=== $$host ===" && ssh root@$$host systemctl start k3s-etcd-offload && ssh root@$$host journalctl -u k3s-etcd-offload --no-pager -n 20; done

backup-verify: ## Verify backup health: RGW mirror + etcd offload + postgres + velero.
	@echo "=== RGW Mirror (last 3 jobs) ===" && kubectl get jobs -n applications -l job-name -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[0].type,AGE:.metadata.creationTimestamp' --sort-by=.metadata.creationTimestamp 2>/dev/null | grep rgw-mirror | tail -3; \
	echo "=== MinIO RGW bucket ===" && ssh root@lab-pi-bk "mc ls pi/homelab-backup-rgw/ 2>/dev/null | head -10"; \
	echo "=== MinIO etcd snapshots ===" && ssh root@lab-pi-bk "mc ls pi/homelab-backup-etcd/ 2>/dev/null"; \
	echo "=== Postgres backup ===" && ssh root@lab-pi-bk "mc ls pi/homelab-backup-postgres/ 2>/dev/null | tail -3"; \
	echo "=== Velero BSL ===" && kubectl get bsl -n velero 2>/dev/null; \
	echo "=== Done ==="

images: ## List all container images used in kubenix.
	@./scripts/kubenix-image-updater scan

images-outdated: ## Show container images with available updates.
	@./scripts/kubenix-image-updater outdated

images-check: ## Check specific image for updates. Usage: make images-check IMAGE=ghcr.io/immich-app/immich-server:v2.5.2
	@if [ -z "$(IMAGE)" ]; then \
		echo "Usage: make images-check IMAGE=<image-ref>"; \
		echo "Example: make images-check IMAGE=ghcr.io/immich-app/immich-server:v2.5.2"; \
		exit 1; \
	fi
	@./scripts/kubenix-image-updater check "$(IMAGE)" --with-digest

help: ## Show this help.
	@printf "Usage: make [target]\n\nTARGETS:\n"; grep -F "##" $(MAKEFILE_LIST) | grep -Fv "grep -F" | grep -Fv "printf " | sed -e 's/\\$$//' | sed -e 's/##//' | column -t -s ":" | sed -e 's/^/    /'; printf "\n"
