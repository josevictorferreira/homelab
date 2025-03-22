.DEFAULT_GOAL := help

sync: ## Sync helmfile
	helmfile --environment homeserver sync

syncd: ## Sync helmfile with debug
	helmfile --environment homeserver sync --debug

secrets: ## Edit project secrets
	sops environments/homeserver/secrets.enc.yaml

list_manifests_default: ## List all manifests in default namespace
	kubectl api-resources --verbs=list --namespaced -o name | xargs -n 1 kubectl get --namespace defaul

gen_erlang_cookie: ## UTILITY: Randomly generate an erlang cookie
	openssl rand -hex 16

gen_secret: ## UTILITY: Randomly generate a secret
	openssl rand -base64 32

remove_ingress: ## Remove ingress namespace
	sudo kubectl get namespace ingress -o json | jq '.spec.finalizers=[]' | kubectl replace --raw "/api/v1/namespaces/ingress/finalize" -f

monitor: ## Open monitoring dashboard
	k9s -n self-hosted -c pods

listen_prometheus: ## Listen to prometheus
	kubectl --context homeserver -n monitoring port-forward svc/prometheus-prometheus 9090:9090

help: ## Show this help.
	@printf "Usage: make [target]\n\nTARGETS:\n"; grep -F "##" $(MAKEFILE_LIST) | grep -Fv "grep -F" | grep -Fv "printf " | sed -e 's/\\$$//' | sed -e 's/##//' | column -t -s ":" | sed -e 's/^/    /'; printf "\n"
