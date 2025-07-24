GREEN=\033[0;32m
CYAN=\033[0;36m
BOLD=\033[1m
RESET=\033[0m
GIT_BASE_ADDRESS := git@github.com:josevictorferreira
DEFAULT_ENV := homelab
APPS_NAMESPACE := self-hosted
TARGETS := $(shell grep -E '^[a-zA-Z0-9_-]+:.*?# .*$$' $(MAKEFILE_LIST) | cut -d: -f1)

.PHONY: $(TARGETS)
.DEFAULT_GOAL := help

SUBTRESS := \
  nix=$(GIT_BASE_ADDRESS)/nix-config-homelab.git@main

subtree_clean_check: ## Check if the git working tree is clean.
	@if ! git diff --quiet || ! git diff --cached --quiet; then \
		echo -e "❌ Git working tree is dirty. Please commit or stash your changes."; \
		exit 1; \
	else \
		echo -e "✅ Git working tree is clean.\n"; \
	fi

subtree_sync: subtree_clean_check ## Add or sync subtrees to the config directory.
	@for entry in $(SUBTRESS); do \
		name=$$(echo $$entry | cut -d= -f1); \
		repo=$$(echo $$entry | cut -d= -f2 | cut -d@ -f1,2); \
		branch=$$(echo $$entry | cut -d@ -f3); \
		echo -e "$(GREEN)--- 🔁 SYNC $$name ---$(RESET)"; \
		if [ ! -d "config/$$name" ]; then \
			echo -e "$(CYAN) Adding $$repo -> config/$$name (branch: $$branch)$(RESET)"; \
			git subtree add --prefix=config/$$name $$repo $$branch --squash; \
		else \
			echo -e "$(CYAN) Pulling from $$repo (branch: $$branch)$(RESET)"; \
			git subtree pull --prefix=config/$$name $$repo $$branch --squash || true; \
			echo -e "$(CYAN) Pushing config/$$name to $$repo (branch: $$branch)$(RESET)"; \
			git subtree push --prefix=config/$$name $$repo $$branch || true; \
		fi; \
		echo -e "✅ $(GREEN)DONE.$(RESET)\n"; \
	done

apply: ## Apply helmfile.: REL=<release_name>
	helmfile -e $(DEFAULT_ENV) -l name=$(REL) apply

applyd: ## Apply helmfile with debug.: REL=<release_name>
	helmfile -e $(DEFAULT_ENV) -l name=$(REL) apply --debug

applyf: ## Apply helmfile with force.: REL=<release_name>
	helmfile -e $(DEFAULT_ENV) -l name=$(REL) --force apply

sync: ## Sync helmfile.
	helmfile -e $(DEFAULT_ENV) sync

syncd: ## Sync helmfile with debug.
	helmfile -e $(DEFAULT_ENV) sync --debug

list: ## List helmfile available releases.
	helmfile -e $(DEFAULT_ENV) list

secrets: ## Edit project secrets.
	sops environments/$(DEFAULT_ENV)/secrets.enc.yaml

list_manifests_default: ## List all manifests in default namespace.
	kubectl api-resources --verbs=list --namespaced -o name | xargs -n 1 kubectl get --namespace defaul

gen_erlang_cookie: ## Randomly generate an erlang cookie.
	openssl rand -hex 16

gen_secret: ## Randomly generate a secret.
	openssl rand -base64 32

remove_ingress: ## Remove ingress namespace.
	sudo kubectl get namespace ingress -o json | jq '.spec.finalizers=[]' | kubectl replace --raw "/api/v1/namespaces/ingress/finalize" -f

monitor: ## Open monitoring dashboard.
	k9s -n $(APPS_NAMESPACE) -c pods

listen_prometheus: ## Listen to prometheus
	kubectl --context $(DEFAULT_ENV) -n monitoring port-forward svc/prometheus-prometheus 9090:9090

logs: ## Show logs for a pod.: REL=<pod_name>
	kubectl logs -n $(APPS_NAMESPACE) -l "app.kubernetes.io/name=$(REL)" --since=3m --tail=100

help: ## Show this help.
	@printf "Usage: make [target]\n\nTARGETS:\n"; grep -F "##" $(MAKEFILE_LIST) | grep -Fv "grep -F" | grep -Fv "printf " | sed -e 's/\\$$//' | sed -e 's/##//' | column -t -s ":" | sed -e 's/^/    /'; printf "\n"
