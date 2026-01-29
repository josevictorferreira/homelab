.PHONY: lgroups check ddeploy deploy gdeploy secrets vmanifests umanifests emanifests gmanifests manifests kubesync wusbiso docker-build docker-login docker-init-repo docker-push lint format backup_postgres restore_postgres help .ensure-hooks

.DEFAULT_GOAL := help

MAKEFLAGS += --no-print-directory

.ensure-hooks:
	@git config core.hooksPath .githooks 2>/dev/null || true

AVAILABLE_NODE_GROUPS = $(shell nix eval --raw .#nodeGroupsList --read-only --quiet)
AVAILABLE_NODES = $(shell nix eval --raw .#nodesList --read-only --quiet)
CONTROL_PLANE_IP = 10.10.10.200
CLUSTER_IP = 10.10.10.250
PORT = 6443
USERNAME = josevictor
REMOTE_KUBECONFIG = /etc/rancher/k3s/k3s.yaml
LOCAL_KUBECONFIG = $(HOME)/.kube/config
CLUSTER_NAME = ze-homelab
MANIFESTS_DIR ?= .k8s
ENC_GLOB := \( -name '*.enc.yaml' -o -name '*.enc.yml' \)
LOCK_FILE ?= manifests.lock
CHECKSUM_DIR  ?= .checksums

# Docker configuration
DOCKER_IMAGE_NAME = docling-serve-rocm
DOCKER_TAG = latest
GITHUB_USER ?= josevictorferreira
DOCKER_REGISTRY = ghcr.io
DOCKER_FULL_IMAGE = $(DOCKER_REGISTRY)/$(GITHUB_USER)/$(DOCKER_IMAGE_NAME):$(DOCKER_TAG)

lgroups: ## List available node groups.
	@printf '%s\n' $(AVAILABLE_NODE_GROUPS)

check: .ensure-hooks ## Check if the flake is valid.
	@bash -c "nix flake check --show-trace --all-systems --impure"

ddeploy: ## Dry deploy host.
	@set -e; \
	SEL="$$(printf '%s\n' $(AVAILABLE_NODES) \
    | tr -d '\r' \
	  | nix run nixpkgs#fzf -- --prompt='host> ' --height=40% --border \
	    --preview 'printf \"%s\n\" {}')"; \
  echo "Deploying host: $$SEL"; \
	nix run github:serokell/deploy-rs -- \
    --debug-logs \
		--dry-activate \
		.#$$SEL \
    -- \
    --impure \
    --show-trace

deploy: ## Deploy host.
	@set -e; \
	SEL="$$(printf '%s\n' $(AVAILABLE_NODES) \
    | tr -d '\r' \
	  | nix run nixpkgs#fzf -- --prompt='host> ' --height=40% --border \
	    --preview 'printf \"%s\n\" {}')"; \
  echo "Deploying host: $$SEL"; \
	nix run github:serokell/deploy-rs -- \
    --debug-logs \
		--auto-rollback true \
		.#$$SEL \
    -- \
    --impure \
    --show-trace

gdeploy: ## Deploy hosts that belong to a group.
	@set -e; \
	SEL="$$(printf '%s\n' $(AVAILABLE_NODE_GROUPS) \
    | tr -d '\r' \
	  | nix run nixpkgs#fzf -- --prompt='host> ' --height=40% --border \
	    --preview 'printf \"%s\n\" {}')"; \
  echo "Deploying group: $$SEL"; \
  targets="$$(nix eval --raw .#deployGroups.$$SEL)"; \
  echo "Targets: $$targets"; \
  make check; \
	eval "nix run github:serokell/deploy-rs -- \
	  --skip-checks \
	  --auto-rollback true \
	  $$targets"

secrets: ## Edit the secrets files.
	@set -e; \
	SEL="$$(find secrets -type f \
	  | nix run nixpkgs#fzf -- --prompt='secret> ' --height=40% --border \
	    --preview 'command -v bat >/dev/null 2>&1 && bat --style=plain --color=always {} || head -n 200 {}')"; \
	test -n "$$SEL" || { echo "No file selected."; exit 1; }; \
	echo "Opening with sops: $$SEL"; \
	sops "$$SEL"

umanifests: ## Restore unchanged *.enc.yaml files to the encrypted version in git, tracking checksums in a single lock file.
	@set -euo pipefail; \
	LOCK_FILE="$(LOCK_FILE)"; \
	touch "$$LOCK_FILE"; \
	tmp="$${LOCK_FILE}.tmp"; \
	: > "$$tmp"; \
	find "$(MANIFESTS_DIR)" -mindepth 2 -type f $(ENC_GLOB) \
	  -not -path '$(MANIFESTS_DIR)/flux-system/*' -print0 | \
	while IFS= read -r -d '' f; do \
	  new_sum=$$(sha256sum "$$f" | cut -d' ' -f1); \
	  old_sum=$$(awk -v p="$$f" 'BEGIN{FS="\t"} $$1==p {print $$2}' "$$LOCK_FILE" || true); \
	  if [ "$$new_sum" = "$$old_sum" ]; then \
	    if git ls-files --error-unmatch "$$f" >/dev/null 2>&1; then \
	      git checkout -- "$$f"; \
	      echo "Restored unchanged (keeping encrypted from git): $$f"; \
	    else \
	      echo "Unchanged (untracked, left plain): $$f"; \
	    fi; \
	  else \
	    echo "Changed: $$f"; \
	  fi; \
	  printf '%s\t%s\n' "$$f" "$$new_sum" >> "$$tmp"; \
	done; \
	mv "$$tmp" "$$LOCK_FILE"

vmanifests: ## Replace secrets in .enc.yaml manifests using vals.
	@set -euo pipefail; \
	find .k8s -mindepth 2 -type f \
	  \( -name '*.enc.yaml' -o -name '*.enc.yml' \) \
	  -not -path '.k8s/flux-system/*' -print0 | \
	while IFS= read -r -d '' f; do \
	  if yq -e 'select(has("sops") and (.sops.mac // "" != ""))' "$$f" >/dev/null 2>&1; then \
	    echo "Skipping (already encrypted): $$f"; \
	  else \
	    echo "Replacing $$f"; \
      nix run nixpkgs#vals -- eval -f "$$f" >  "$$f.tmp"; \
      if [ -s "$$f.tmp" ]; then \
        mv "$$f.tmp" "$$f"; \
        echo "Replaced $$f"; \
      else \
        echo "No replacements made in $$f"; \
        rm -f "$$f.tmp"; \
      fi; \
	  fi; \
  done;

emanifests: ## Encrypt the .enc.yaml manifests using sops.
	@set -euo pipefail; \
	find .k8s -mindepth 2 -type f \
	  \( -name '*.enc.yaml' -o -name '*.enc.yml' \) \
	  -not -path '.k8s/flux-system/*' -print0 | \
	while IFS= read -r -d '' f; do \
	  if yq -e 'select(has("sops") and (.sops.mac // "" != ""))' "$$f" >/dev/null 2>&1; then \
	    echo "Skipping (already encrypted): $$f"; \
	  else \
	    echo "Encrypting $$f"; \
	    nix run nixpkgs#sops -- --encrypt --in-place "$$f"; \
	  fi; \
	done

gmanifests: ## Render k8s manifests generated by kubenix.
	@set -euo pipefail; \
	HOMELAB_REPO_PATH=$(PWD) nix build .#gen-manifests --impure --show-trace; \
	find .k8s -mindepth 1 -maxdepth 1 -type d \
	! \( -name 'flux-system' \) -exec rm -rf {} +; \
	cp -rf result/* .k8s; \
	rm -rf result; \
	find .k8s -type f -exec chmod 0644 {} +; \
	find .k8s -type d -exec chmod 0755 {} +;

manifests: .ensure-hooks ## Fully render k8s manifests, including generating secrets and encrypting them.
	make gmanifests
	make vmanifests
	make umanifests
	make emanifests
	@echo "Done."

kubesync: ## Write kubeconfig from the cluster to kubectl config.
	@set -euo pipefail; \
  kubectl config delete-user "$(USERNAME)" >/dev/null 2>&1 || true; \
	kubectl config delete-cluster "$(CLUSTER_NAME)" >/dev/null 2>&1 || true; \
	kubectl config delete-context "$(CLUSTER_NAME)" >/dev/null 2>&1 || true; \
	tmpdir="$$(mktemp -d)"; \
	tmpkc="$$tmpdir/k3s.yaml"; \
	ssh -4 $(USERNAME)@$(CONTROL_PLANE_IP) "sudo cat $(REMOTE_KUBECONFIG)" > "$$tmpkc"; \
	oldctx="$$(KUBECONFIG="$$tmpkc" kubectl config current-context)"; \
	oldcluster="$$(KUBECONFIG="$$tmpkc" kubectl config view --raw=true -o jsonpath='{.contexts[?(@.name=="'$$oldctx'")].context.cluster}')"; \
	olduser="$$(KUBECONFIG="$$tmpkc" kubectl config view --raw=true -o jsonpath='{.contexts[?(@.name=="'$$oldctx'")].context.user}')"; \
	ca_b64="$$(KUBECONFIG="$$tmpkc" kubectl config view --raw=true -o jsonpath='{.clusters[?(@.name=="'$$oldcluster'")].cluster.certificate-authority-data}')"; \
	clientcrt_b64="$$(KUBECONFIG="$$tmpkc" kubectl config view --raw=true -o jsonpath='{.users[?(@.name=="'$$olduser'")].user.client-certificate-data}')"; \
	clientkey_b64="$$(KUBECONFIG="$$tmpkc" kubectl config view --raw=true -o jsonpath='{.users[?(@.name=="'$$olduser'")].user.client-key-data}')"; \
  echo "$$ca_b64" | base64 -d >"$$tmpdir/ca.crt"; \
  echo "$$clientcrt_b64" | base64 -d >"$$tmpdir/client.crt"; \
  echo "$$clientkey_b64" | base64 -d >"$$tmpdir/client.key"; \
	mkdir -p "$$(dirname "$(LOCAL_KUBECONFIG)")"; \
	[ -f "$(LOCAL_KUBECONFIG)" ] && cp "$(LOCAL_KUBECONFIG)" "$(LOCAL_KUBECONFIG).bak" || true; \
	KUBECONFIG="$(LOCAL_KUBECONFIG)" kubectl config set-cluster "$(CLUSTER_NAME)" --embed-certs=true --server="https://$(CLUSTER_IP):$(PORT)" --certificate-authority="$$tmpdir/ca.crt"; \
  KUBECONFIG="$(LOCAL_KUBECONFIG)" kubectl config set-credentials "$(USERNAME)" --embed-certs=true --client-certificate="$$tmpdir/client.crt" --client-key="$$tmpdir/client.key"; \
	KUBECONFIG="$(LOCAL_KUBECONFIG)" kubectl config set-context "$(CLUSTER_NAME)" --cluster="$(CLUSTER_NAME)" --user="$(USERNAME)"; \
	KUBECONFIG="$(LOCAL_KUBECONFIG)" kubectl config use-context "$(CLUSTER_NAME)" >/dev/null; \
	chmod 600 "$(LOCAL_KUBECONFIG)"; \
	rm -rf "$$tmpdir"; \
	echo "OK: cluster/user/context written → $(LOCAL_KUBECONFIG)";

wusbiso: ## Build the recovery ISO, formats the USB drive and writes the ISO to it.
	@set -euo pipefail; \
  if [ -d result/iso ]; then \
    echo "Recovery ISO already built. Skipping build."; \
  else \
    nix build .#nixosConfigurations.recovery-iso.config.system.build.isoImage; \
    echo "Building recovery ISO..."; \
  fi; \
  ISO="$$(readlink -f result/iso/recovery-iso-*.iso)"; \
  DEV="$(readlink -f /dev/disk/by-id/usb-*)"; \
  echo "Recovery ISO: $$ISO"; \
  if [ -z "$$DEV" ]; then \
    echo "No USB drive found. Please connect a USB drive and try again."; \
    exit 1; \
  fi; \
  sudo sgdisk --zap-all "$$DEV"; \
  sudo wipefs -a "$$DEV"; \
  sudo blkdiscard -f "$$DEV"; \
  sudo dd if="$$ISO" of="$$DEV" bs=4M status=progress conv=fsync; \
  sync; \
  echo "Recovery ISO written to $$DEV"; \
  sudo eject "$DEV" 2>/dev/null || true; \
  echo "Done. You can now boot from the USB drive.";

reconcile: ## Reconcile the kubernetes cluster with the current main branch
	@flux reconcile kustomization flux-system -n flux-system --with-source

events: ## Watch for the latest events in flux kubernetes system
	@flux events --watch

docker-build: ## Build the Docker image using nix-build.
	@echo "Building Docker image $(DOCKER_IMAGE_NAME):$(DOCKER_TAG)..."
	nix-build images/$(DOCKER_IMAGE_NAME).nix && docker load < result
	@echo "Tagging image as $(DOCKER_FULL_IMAGE)..."
	docker tag localhost/$(DOCKER_IMAGE_NAME):$(DOCKER_TAG) $(DOCKER_FULL_IMAGE)
	@echo "Image built and tagged successfully: $(DOCKER_FULL_IMAGE)"

docker-login: ## Login to GitHub Container Registry using GitHub CLI or GITHUB_TOKEN.
	@if [ -n "$(GITHUB_TOKEN)" ]; then \
		echo "Logging in using GITHUB_TOKEN..."; \
		echo $(GITHUB_TOKEN) | docker login $(DOCKER_REGISTRY) -u $(GITHUB_USER) --password-stdin; \
		echo "Successfully authenticated with GITHUB_TOKEN"; \
	elif command -v gh >/dev/null 2>&1; then \
		echo "Logging in using GitHub CLI..."; \
		GH_TOKEN=$$(gh auth token); \
		if [ -n "$$GH_TOKEN" ]; then \
			echo $$GH_TOKEN | docker login $(DOCKER_REGISTRY) -u $(GITHUB_USER) --password-stdin; \
			echo "Successfully authenticated with GitHub CLI"; \
		else \
			echo "GitHub CLI not authenticated. Please run: gh auth login"; \
			exit 1; \
		fi; \
	else \
		echo "Error: Neither GitHub CLI nor GITHUB_TOKEN is available"; \
		echo "Please install GitHub CLI or set GITHUB_TOKEN environment variable"; \
		exit 1; \
	fi

docker-init-repo: ## Initialize the GitHub Container Registry repository.
	@echo "Checking if repository exists..."
	@if command -v gh >/dev/null 2>&1; then \
		if gh api /user/packages/container/$(DOCKER_IMAGE_NAME) >/dev/null 2>&1; then \
			echo "Repository already exists"; \
		else \
			echo "Creating repository using GitHub CLI..."; \
			RESPONSE=$$(gh api --method POST \
				-H "Accept: application/vnd.github.v3+json" \
				/user/packages \
				-f name='$(DOCKER_IMAGE_NAME)' \
				-f package_type='container' \
				-f visibility='public' 2>&1); \
			if [ $$? -eq 0 ]; then \
				echo "Repository created successfully"; \
			else \
				echo "Error creating repository: $$RESPONSE"; \
				echo "Will try to create repository on first push instead"; \
			fi; \
		fi; \
	else \
		echo "Warning: GitHub CLI not available. Repository will be created on first push"; \
	fi

docker-push: docker-build docker-login docker-init-repo ## Build and push the Docker image to GitHub Container Registry.
	@echo "Pushing image to $(DOCKER_FULL_IMAGE)..."
	docker push $(DOCKER_FULL_IMAGE)
	@echo "Image pushed successfully to $(DOCKER_FULL_IMAGE)"
	@echo "Image is now public at: https://$(DOCKER_REGISTRY)/$(GITHUB_USER)/$(DOCKER_IMAGE_NAME)"

lint: ## Lint the nix files.
	@echo "Running nix formatter check..."
	@nix fmt -- --check . || (echo "❌ Some files need formatting. Run 'make format' to fix." && exit 1)
	@echo "✅ All files are properly formatted."

format: ## Format the nix files.
	@echo "Formatting nix files..."
	@nix fmt .
	@echo "✅ Formatting complete."

backup_postgres: ## Create a .sql backup of all postgresql data
	mkdir -p /tmp/backup && pg_dumpall -h 10.10.10.101 -U postgres -f /tmp/backup/full_backup.sql

restore_postgres: ## Restore a .sql backup data to the postgresql
	psql -h 10.10.10.133 -U postgres -f /tmp/backup/full_backup.sql

help: ## Show this help.
	@printf "Usage: make [target]\n\nTARGETS:\n"; grep -F "##" $(MAKEFILE_LIST) | grep -Fv "grep -F" | grep -Fv "printf " | sed -e 's/\\$$//' | sed -e 's/##//' | column -t -s ":" | sed -e 's/^/    /'; printf "\n"
