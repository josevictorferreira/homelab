.PHONY: check ddeploy deploy gdeploy secrets help 

.DEFAULT_GOAL := help

HOSTNAME := $(shell hostname)

check: ## Check if the flake is valid.
	@bash -c "nix flake check --show-trace"

ddeploy: ## Dry deploy.: HOST=$(HOSTNAME)
	@nix run github:serokell/deploy-rs -- --dry-activate .

deploy: ## Deploy.: HOST=$(HOSTNAME)
	@nix run github:serokell/deploy-rs -- \
		--auto-rollback=true \
		.#$(HOSTNAME)

gdeploy: ## Group deploy.: GROUP=$(GROUP)
	@nix run github:serokell/deploy-rs -- \
    --targets "$$(nix eval --raw .#deployGroups.$(GROUP))" \
    --auto-rollback true

secrets: ## Edit the secrets file
	sops secrets/cluster-secrets.enc.yaml

help: ## Show this help.
	@printf "Usage: make [target]\n\nTARGETS:\n"; grep -F "##" $(MAKEFILE_LIST) | grep -Fv "grep -F" | grep -Fv "printf " | sed -e 's/\\$$//' | sed -e 's/##//' | column -t -s ":" | sed -e 's/^/    /'; printf "\n"
