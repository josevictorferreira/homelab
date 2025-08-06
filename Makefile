.PHONY: check deploy rebuild clean secrets help 

.DEFAULT_GOAL := help

HOSTNAME := $(shell hostname)

check: ## Check if the flake is valid.
	@bash -c "nix flake check --show-trace --impure"

deploy: ## Deploy
	@nix run github:serokell/deploy-rs -- --dry-activate .#lab-pi-bk -- --impure

secrets: ## Edit the secrets file
	sops secrets/cluster-secrets.enc.yaml

help: ## Show this help.
	@printf "Usage: make [target]\n\nTARGETS:\n"; grep -F "##" $(MAKEFILE_LIST) | grep -Fv "grep -F" | grep -Fv "printf " | sed -e 's/\\$$//' | sed -e 's/##//' | column -t -s ":" | sed -e 's/^/    /'; printf "\n"
