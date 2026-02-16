.PHONY: lgroups check ddeploy deploy gdeploy secrets manifests kubesync wusbiso docker-build docker-login docker-init-repo docker-push lint format backup-postgres restore-postgres reconcile events help

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

help: ## Show this help.
	@printf "Usage: make [target]\n\nTARGETS:\n"; grep -F "##" $(MAKEFILE_LIST) | grep -Fv "grep -F" | grep -Fv "printf " | sed -e 's/\\$$//' | sed -e 's/##//' | column -t -s ":" | sed -e 's/^/    /'; printf "\n"
