.PHONY: hostname rebuild clean secrets help 

.DEFAULT_GOAL := help

hostname: ## Print the actual hostanme of the current machine.
	@echo $$HOSTNAME

rebuild: ## Rebuild NixOS configuration.
	sudo nixos-rebuild switch --flake .#$$HOSTNAME

clean: ## Clean up the Nix store.
	nix-collect-garbage -d

secrets: ## Edit the secrets file
	sops secrets/secrets.enc.yaml

help: ## Show this help.
	@printf "Usage: make [target]\n\nTARGETS:\n"; grep -F "##" $(MAKEFILE_LIST) | grep -Fv "grep -F" | grep -Fv "printf " | sed -e 's/\\$$//' | sed -e 's/##//' | column -t -s ":" | sed -e 's/^/    /'; printf "\n"
