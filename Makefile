.PHONY: groups check ddeploy deploy gdeploy secrets help 

.DEFAULT_GOAL := help

AVAILABLE_GROUPS := $(shell nix eval --raw .#nodeGroups)

groups: ## List all deploy groups.
	@echo "Groups: $(AVAILABLE_GROUPS)"

check: ## Check if the flake is valid.
	@bash -c "nix flake check --show-trace --all-systems"

ddeploy: ## Dry deploy.: HOST=$(HOSTNAME)
	@nix run github:serokell/deploy-rs -- \
    --debug-logs \
		--dry-activate \
		.#$(HOST) \
    -- \
    --show-trace

deploy: ## Deploy.: HOST=$(HOSTNAME)
	@nix run github:serokell/deploy-rs -- \
    --debug-logs \
		--auto-rollback true \
		.#$(HOST) \
    -- \
    --show-trace

gdeploy: ## Group deploy.: GROUP=$(GROUP)
	@nix run github:serokell/deploy-rs -- \
    --targets "$$(nix eval --raw .#deployGroups.$(GROUP))" \
    --auto-rollback true

secrets: ## Edit the secrets file
	sops secrets/cluster-secrets.enc.yaml

help: ## Show this help.
	@printf "Usage: make [target]\n\nTARGETS:\n"; grep -F "##" $(MAKEFILE_LIST) | grep -Fv "grep -F" | grep -Fv "printf " | sed -e 's/\\$$//' | sed -e 's/##//' | column -t -s ":" | sed -e 's/^/    /'; printf "\n"
