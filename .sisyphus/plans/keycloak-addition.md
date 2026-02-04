# Keycloak Addition to Homelab

## TL;DR

> **Quick Summary**: Deploy Keycloak 26.5.2 via CloudPirates Helm chart with external PostgreSQL connection to postgresql-18-hl
> 
> **Deliverables**:
> - Keycloak deployment with single instance (1Gi-2Gi memory)
> - External PostgreSQL connection (keycloak database)
> - Ingress at keycloak.identity.josevictor.me with TLS
> - SOPS-encrypted secrets for admin and database credentials
> 
> **Estimated Effort**: Short
> **Parallel Execution**: NO - sequential (bootstrap → secrets → app)
> **Critical Path**: Bootstrap DB → Create secrets → Deploy app

---

## Context

### Original Request
Add Keycloak service (latest version) to homelab cluster with external PostgreSQL and ingress access.

### Interview Summary

**Key Discussions**:
- **Chart Choice**: CloudPirates Helm chart (v0.14.2, Keycloak 26.5.2) - actively maintained, supports external PostgreSQL
- **Instance Count**: Single instance for homelab use
- **Resources**: 1Gi memory request / 2Gi limit (increased from 512Mi due to Java/Quarkus requirements)
- **Database**: Create 'keycloak' database in existing postgresql-18-hl
- **Ingress**: Enable at keycloak.identity.josevictor.me with Cilium + TLS
- **Admin**: admin/admin user setup
- **Verification**: Agent-Executed QA only (no unit tests)

**Research Findings**:
- Bitnami charts went commercial (Aug 2025) - no longer viable
- Codecentric chart outdated (Keycloak 17.x) - not recommended
- CloudPirates chart: latest Keycloak 26.5.2, OCI registry, actively maintained (updated Feb 4, 2026)
- Pattern: Use shared postgres superuser via postgresql-auth secret (standard homelab pattern)

### Metis Review

**Identified Gaps (addressed)**:
- **Memory Risk**: 512Mi may cause OOMKill for Java/Quarkus - increased to 1Gi-2Gi
- **Database User**: Using shared postgres admin (standard pattern) vs dedicated user
- **Image Security**: Must pin container image digest (SHA256)
- **DB Registration**: Must add "keycloak" to config/kubernetes.nix databases.postgres list

---

## Work Objectives

### Core Objective
Deploy Keycloak 26.5.2 using CloudPirates Helm chart with external PostgreSQL connection, ingress, and proper secrets management via SOPS.

### Concrete Deliverables
- `modules/kubenix/apps/keycloak.nix` - Helm app definition
- `modules/kubenix/apps/keycloak-config.enc.nix` - Encrypted secrets
- Updated `config/kubernetes.nix` - Database registration
- Keycloak deployment in `apps` namespace
- Ingress resource for keycloak.identity.josevictor.me

### Definition of Done
- [ ] Keycloak pod ready and running
- [ ] Database connection verified
- [ ] HTTPS endpoint accessible at keycloak.identity.josevictor.me
- [ ] Admin console accessible (HTTP 200)
- [ ] All secrets encrypted via SOPS

### Must Have
- Keycloak 26.5.2 deployment (single instance)
- External PostgreSQL connection (postgresql-18-hl)
- Ingress with Cilium class and TLS
- SOPS-encrypted secrets
- Health checks and probes

### Must NOT Have (Guardrails)
- NO embedded PostgreSQL (use external postgresql-18-hl)
- NO high availability (single instance only)
- NO realm/client configuration (manual via UI)
- NO manual database creation (let bootstrap job do it)
- NO unencrypted secrets (must use SOPS)

---

## Verification Strategy

> **UNIVERSAL RULE: ZERO HUMAN INTERVENTION**
>
> ALL tasks in this plan MUST be verifiable WITHOUT any human action.

### Test Decision
- **Infrastructure exists**: NO (no test framework for Nix/Helm)
- **Automated tests**: NO
- **Framework**: N/A

### Agent-Executed QA Scenarios (MANDATORY)

**All scenarios use Bash with kubectl/curl for verification:**

```
Scenario: Keycloak Pod Ready
  Tool: Bash
  Preconditions: Helm release deployed, keycloak namespace exists
  Steps:
    1. kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak -n apps --timeout=300s
    2. kubectl get pods -n apps -l app.kubernetes.io/name=keycloak
    3. Assert: Pod status is "Running"
  Expected Result: Pod ready and running
  Evidence: kubectl get output captured

Scenario: Keycloak HTTPS Endpoint Accessible
  Tool: Bash (curl)
  Preconditions: Ingress with TLS configured, DNS resolves
  Steps:
    1. curl -f -v --retry 5 --retry-delay 5 https://keycloak.identity.josevictor.me/realms/master
    2. Assert: HTTP status is 200
    3. Assert: response contains "realm":"master"
  Expected Result: HTTPS endpoint returns public realm info
  Evidence: Response body captured

Scenario: Keycloak Admin Console Accessible
  Tool: Bash (curl)
  Preconditions: HTTPS endpoint working
  Steps:
    1. curl -f https://keycloak.identity.josevictor.me/auth/admin/
    2. Assert: HTTP status is 200 or redirects to login
  Expected Result: Admin endpoint accessible
  Evidence: Response captured

Scenario: Database Connection Verified
  Tool: Bash (kubectl logs)
  Preconditions: Keycloak pod running
  Steps:
    1. kubectl logs -n apps -l app.kubernetes.io/name=keycloak --tail=50
    2. grep -i "Connected to database" || grep -i "database" | head -5
    3. Assert: No connection errors in logs
  Expected Result: Database connection successful
  Evidence: Logs captured to file

Scenario: Ingress Status Verified
  Tool: Bash
  Preconditions: Ingress resource created
  Steps:
    1. kubectl get ingress -n apps -l app.kubernetes.io/name=keycloak -o yaml
    2. Assert: HOSTS contains keycloak.identity.josevictor.me
    3. Assert: TLS secret referenced
  Expected Result: Ingress properly configured
  Evidence: Ingress YAML captured
```

**Evidence to Capture**:
- `kubectl get pods` output
- `kubectl get ingress` output  
- `curl` response bodies
- Pod logs (database connection verification)
- All captured to `.sisyphus/evidence/`

---

## Execution Strategy

### Sequential Execution

```
Step 1: Database Registration
└── Update config/kubernetes.nix to add "keycloak" to databases.postgres list

Step 2: Create Encrypted Secrets  
└── Create keycloak-config.enc.nix with DB and admin passwords

Step 3: Create App Definition
└── Create keycloak.nix with Helm chart and configuration

Step 4: Generate Manifests
└── Run make manifests to generate YAML and encrypt secrets

Step 5: Deploy and Verify
└── Flux reconciles, deployment creates pods, QA scenarios verify
```

**Critical Path**: Step 1 → Step 2 → Step 3 → Step 4 → Step 5

---

## TODOs

> Every task MUST have: Recommended Agent Profile + Parallelization info.

- [ ] 1. Update Database Registration

  **What to do**:
  - Edit `config/kubernetes.nix`
  - Add "keycloak" to the `databases.postgres` list
  - This triggers postgresql-18-bootstrap to create 'keycloak' database

  **Must NOT do**:
  - Don't manually create database via kubectl exec
  - Don't modify other database entries

  **Recommended Agent Profile**:
  > Select category + skills based on task domain. Justify each choice.
  - **Category**: `unspecified-low`
    - Reason: Simple configuration change, well-defined pattern
  - **Skills**: [`writing`]
    - `writing`: Configuration file editing with proper Nix syntax

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (Step 1)
  - **Blocks**: Tasks 2, 3, 4, 5
  - **Blocked By**: None (can start immediately)

  **References**:

  **Pattern References**:
  - `config/kubernetes.nix:databases.postgres` - Existing pattern for database registration (add to list)
  - `modules/kubenix/apps/linkwarden.nix:9-15` - Similar app addition pattern

  **Documentation References**:
  - `modules/kubenix/apps/AGENTS.md` - App addition workflow

  **WHY Each Reference Matters**:
  - kubernetes.nix shows exact syntax for adding databases to the list
  - linkwarden.nix shows the app definition pattern to follow

  **Acceptance Criteria**:

  - [ ] `config/kubernetes.nix` modified to add "keycloak" to databases.postgres
  - [ ] `git diff config/kubernetes.nix` shows only "keycloak" addition
  - [ ] `git add config/kubernetes.nix && git status` confirms staging

  **Agent-Executed QA Scenarios**:
  \`\`\`
  Scenario: Database Registration Complete
    Tool: Bash
    Preconditions: config/kubernetes.nix modified
    Steps:
      1. grep -n "keycloak" config/kubernetes.nix
      2. Assert: Line contains "keycloak" in databases.postgres list
      3. cat config/kubernetes.nix | grep -A5 -B5 "databases.postgres"
      4. Assert: keycloak is in the list array
    Expected Result: Database registration verified
    Evidence: grep output captured
  \`\`\`

  **Evidence to Capture**:
  - grep output showing keycloak in databases list
  - git diff output

  **Commit**: YES
  - Message: `feat(kubenix): add keycloak database registration`
  - Files: `config/kubernetes.nix`

- [ ] 2. Create Encrypted Secrets

  **What to do**:
  - Create `modules/kubenix/apps/keycloak-config.enc.nix`
  - Define SOPS-encrypted secrets for:
    - `keycloak_db_password` - Database password (reference postgresql-auth)
    - `keycloak_admin_password` - Admin console password
  - Use `kubenix.lib.secretsFor` for secret references

  **Must NOT do**:
  - Don't hardcode plain text passwords
  - Don't create plain text secrets file

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Standard secrets pattern following existing templates
  - **Skills**: [`writing`]
    - `writing`: SOPS-encrypted configuration with proper structure

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (Step 2)
  - **Blocks**: Tasks 3, 4, 5
  - **Blocked By**: Task 1 (database must exist first)

  **References**:

  **Pattern References**:
  - `modules/kubenix/apps/n8n-enc.enc.nix:1-20` - Secrets structure with kubenix.lib.secretsFor
  - `modules/kubenix/apps/linkwarden.nix:7-12` - Secret reference pattern

  **Secrets Reference**:
  - `postgresql_auth` secret pattern from existing apps

  **WHY Each Reference Matters**:
  - n8n-enc.enc.nix shows exact SOPS structure for secrets
  - linkwarden shows how to reference secrets in app config

  **Acceptance Criteria**:

  - [ ] `modules/kubenix/apps/keycloak-config.enc.nix` created
  - [ ] File contains `keycloak_db_password` reference to postgresql-auth
  - [ ] File contains `keycloak_admin_password` secret
  - [ ] `file modules/kubenix/apps/keycloak-config.enc.nix` confirms SOPS encrypted format

  **Agent-Executed QA Scenarios**:
  \`\`\`
  Scenario: Secrets File Created and Valid
    Tool: Bash
    Preconditions: keycloak-config.enc.nix created
    Steps:
      1. ls -la modules/kubenix/apps/keycloak-config.enc.nix
      2. Assert: File exists and has .enc.nix extension
      3. sops -d modules/kubenix/apps/keycloak-config.enc.nix | head -20
      4. Assert: Decrypted content shows keycloak_db_password key
    Expected Result: Secrets file valid and decryptable
    Evidence: ls and sops output captured
  \`\`\`

  **Evidence to Capture**:
  - File existence check
  - sops decryption output (first 20 lines)

  **Commit**: YES
  - Message: `feat(kubenix): add keycloak secrets configuration`
  - Files: `modules/kubenix/apps/keycloak-config.enc.nix`

- [ ] 3. Create Keycloak App Definition

  **What to do**:
  - Create `modules/kubenix/apps/keycloak.nix`
  - Configure CloudPirates Helm chart (OCI registry)
  - Set external PostgreSQL connection to postgresql-18-hl
  - Configure ingress for keycloak.identity.josevictor.me
  - Set resources (1Gi-2Gi memory, 500m-2000m CPU)
  - Configure health checks and probes
  - Reference encrypted secrets

  **Must NOT do**:
  - Don't use embedded PostgreSQL
  - Don't forget TLS configuration
  - Don't exceed homelab resource limits

  **Recommended Agent Profile**:
  - **Category**: `unspecified-low`
    - Reason: Standard Helm app definition following established patterns
  - **Skills**: [`writing`]
    - `writing`: Nix configuration with kubenix library

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (Step 3)
  - **Blocks**: Tasks 4, 5
  - **Blocked By**: Task 2 (secrets must exist)

  **References**:

  **Pattern References**:
  - `modules/kubenix/apps/n8n.nix:1-80` - Complete Helm app definition structure
  - `modules/kubenix/apps/linkwarden.nix:1-60` - App with external PostgreSQL pattern
  - `modules/kubenix/apps/open-webui.nix:1-70` - OCI chart pattern

  **API/Type References**:
  - kubenix.lib.secretsFor - Secret reference function
  - kubenix.app - App configuration structure

  **External References**:
  - CloudPirates Keycloak chart: `oci://registry-1.docker.io/cloudpirates/keycloak`
  - Chart version: 0.14.2 (Keycloak 26.5.2)
  - Image digest: `sha256:fb31a59deb46f746f2aaa25adc5da39ceccac4fd22d36a519562b0bf02e8df20`

  **WHY Each Reference Matters**:
  - n8n.nix shows complete app definition structure with all options
  - linkwarden shows external PostgreSQL configuration pattern
  - open-webui shows OCI registry pattern for charts

  **Acceptance Criteria**:

  - [ ] `modules/kubenix/apps/keycloak.nix` created with complete configuration
  - [ ] Chart source: `oci://registry-1.docker.io/cloudpirates/keycloak` version `0.14.2`
  - [ ] Database configured: postgresql-18-hl host, keycloak database
  - [ ] Ingress configured: keycloak.identity.josevictor.me with cilium class
  - [ ] Resources: 1Gi-2Gi memory, 500m-2000m CPU
  - [ ] Secrets referenced: keycloak-config.enc.nix

  **Agent-Executed QA Scenarios**:
  \`\`\`
  Scenario: App Definition Syntax Valid
    Tool: Bash
    Preconditions: keycloak.nix created
    Steps:
      1. nix-instantiate --parse modules/kubenix/apps/keycloak.nix > /dev/null
      2. Assert: Exit code 0 (no syntax errors)
      3. nix eval --raw .#kubenix.apps.keycloak.config 2>&1 | head -20
      4. Assert: Configuration evaluates without errors
    Expected Result: Nix syntax valid, configuration parses
    Evidence: nix-instantiate and nix eval output

  Scenario: Configuration Contains Required Keys
    Tool: Bash
    Preconditions: keycloak.nix evaluates successfully
    Steps:
      1. grep -n "postgresql-18-hl" modules/kubenix/apps/keycloak.nix
      2. Assert: Database host configured
      3. grep -n "keycloak.identity.josevictor.me" modules/kubenix/apps/keycloak.nix
      4. Assert: Ingress hostname configured
      5. grep -n "keycloak-config.enc.nix" modules/kubenix/apps/keycloak.nix
      6. Assert: Secrets referenced
    Expected Result: All required configuration present
    Evidence: grep output for each check
  \`\`\`

  **Evidence to Capture**:
  - nix-instantiate output
  - grep output showing key configuration
  - nix eval output (first 20 lines)

  **Commit**: YES
  - Message: `feat(kubenix): add keycloak app deployment`
  - Files: `modules/kubenix/apps/keycloak.nix`

- [ ] 4. Generate Manifests

  **What to do**:
  - Run `make manifests` to generate Kubernetes YAML
  - This runs: gmanifests → vmanifests → emanifests
  - Verifies SOPS encryption
  - Generates final .k8s/ manifests

  **Must NOT do**:
  - Don't manually edit .k8s/*.yaml files
  - Don't skip any stage of the pipeline

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Standard make command, well-defined workflow
  - **Skills**: [`managing-flakes`]
    - `managing-flakes`: Nix flake and manifest generation

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (Step 4)
  - **Blocks**: Task 5 (deployment)
  - **Blocked By**: Task 3 (app definition must exist)

  **References**:

  **Pattern References**:
  - `Makefile:manifests` - Manifest generation pipeline
  - `modules/kubenix/apps/AGENTS.md:manifests` - Pipeline stages explanation

  **Documentation References**:
  - `Makefile` - Full pipeline: gmanifests → vmanifests → emanifests

  **WHY Each Reference Matters**:
  - Makefile shows the exact commands run by `make manifests`
  - AGENTS.md explains what each stage does

  **Acceptance Criteria**:

  - [ ] `make manifests` exits with code 0
  - [ ] `.k8s/` directory contains keycloak-related YAML files
  - [ ] Keycloak secrets encrypted (no plain text)
  - [ ] git status shows modified .k8s/ files

  **Agent-Executed QA Scenarios**:
  \`\`\`
  Scenario: Manifests Generated Successfully
    Tool: Bash
    Preconditions: All config files created
    Steps:
      1. cd /home/josevictor/Workspace/homelab && make manifests
      2. Assert: Exit code 0
      3. ls -la .k8s/ | grep -i keycloak
      4. Assert: Keycloak YAML files generated
      5. head -10 .k8s/keycloak-*.yaml 2>/dev/null || echo "Checking structure..."
    Expected Result: Manifests generated without errors
    Evidence: make output and ls output

  Scenario: Secrets Encrypted
    Tool: Bash
    Preconditions: Manifests generated
    Steps:
      1. grep -r "sops:" .k8s/keycloak*.yaml | head -5
      2. Assert: SOPS metadata present (encrypted)
      3. sops -d .k8s/keycloak-config*.yaml 2>&1 | head -10
      4. Assert: Decrypts successfully (proves encryption works)
    Expected Result: All secrets properly encrypted
    Evidence: grep and sops output

  Scenario: Git Status Updated
    Tool: Bash
    Preconditions: Manifests generated
    Steps:
      1. git status --short .k8s/keycloak* modules/kubenix/apps/keycloak* config/kubernetes.nix
      2. Assert: All relevant files shown as modified/new
      3. git diff --stat config/kubernetes.nix
      4. Assert: Shows database registration change
    Expected Result: Git reflects all changes
    Evidence: git status and diff output
  \`\`\`

  **Evidence to Capture**:
  - make manifests full output
  - ls .k8s/ for keycloak files
  - git status for modified files
  - sops verification output

  **Commit**: YES
  - Message: `feat: add keycloak deployment manifests`
  - Files: `.k8s/keycloak*.yaml` (auto-generated)

- [ ] 5. Deploy and Verify

  **What to do**:
  - Commit and push changes (Flux reconciles)
  - Wait for Keycloak deployment to complete
  - Run all QA verification scenarios
  - Verify pod readiness, ingress, HTTPS, database connection

  **Must NOT do**:
  - Don't force restart pods unnecessarily
  - Don't skip verification steps

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Deployment and verification are straightforward
  - **Skills**: [`kubernetes-tools`]
    - `kubernetes-tools`: kubectl operations, pod verification

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (Step 5 - Final)
  - **Blocks**: None (final task)
  - **Blocked By**: Task 4 (manifests must be generated)

  **References**:

  **Pattern References**:
  - Previous QA scenarios defined in Verification Strategy section
  - Homelab deployment workflow from docs/rules.md

  **External References**:
  - CloudPirates chart verification steps
  - Keycloak health check endpoints

  **WHY Each Reference Matters**:
  - QA scenarios provide exact verification steps
  - rules.md confirms deployment workflow

  **Acceptance Criteria**:

  - [ ] Flux reconciles changes (check: `flux get ks -A`)
  - [ ] Keycloak pod ready: `kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak -n apps --timeout=300s`
  - [ ] HTTPS endpoint: `curl -f https://keycloak.identity.josevictor.me/realms/master` returns HTTP 200
  - [ ] Admin console: `curl -f https://keycloak.identity.josevictor.me/auth/admin/` returns HTTP 200
  - [ ] Database logs: Pod logs show successful database connection
  - [ ] Ingress: `kubectl get ingress -n apps -l app.kubernetes.io/name=keycloak` shows configured host

  **Agent-Executed QA Scenarios**:

  *All scenarios from Verification Strategy section executed here:*
  \`\`\`
  Scenario: Keycloak Pod Ready
    Tool: Bash
    Preconditions: Flux reconciled, deployment created
    Steps:
      1. kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak -n apps --timeout=300s
      2. kubectl get pods -n apps -l app.kubernetes.io/name=keycloak -o wide
      3. Assert: STATUS is "Running"
      4. kubectl describe pod -n apps -l app.kubernetes.io/name=keycloak | tail -20
    Expected Result: Pod running on node, ready condition true
    Evidence: kubectl get and describe output

  Scenario: Keycloak HTTPS Endpoint Accessible
    Tool: Bash
    Preconditions: Pod ready, ingress configured
    Steps:
      1. curl -f -v --retry 5 --retry-delay 5 https://keycloak.identity.josevictor.me/realms/master
      2. Assert: HTTP 200
      3. Assert: JSON contains "realm":"master"
      4. echo "$RESPONSE" > .sisyphus/evidence/keycloak-realm-response.json
    Expected Result: Public realm endpoint returns valid JSON
    Evidence: curl response and saved JSON file

  Scenario: Keycloak Admin Console Accessible
    Tool: Bash
    Preconditions: HTTPS endpoint working
    Steps:
      1. curl -f -s -o /dev/null -w "%{http_code}" https://keycloak.identity.josevictor.me/auth/admin/
      2. Assert: HTTP 200 or redirects (302)
      3. curl -f -L https://keycloak.identity.josevictor.me/auth/admin/ 2>&1 | head -50
    Expected Result: Admin endpoint accessible
    Evidence: HTTP code and response capture

  Scenario: Database Connection Verified
    Tool: Bash
    Preconditions: Pod running
    Steps:
      1. kubectl logs -n apps -l app.kubernetes.io/name=keycloak --tail=100 > .sisyphus/evidence/keycloak-logs.txt
      2. grep -i "Connected to database\|database connection\|Started Keycloak" .sisyphus/evidence/keycloak-logs.txt
      3. Assert: At least one connection-related log line found
      4. grep -i "error\|exception\|failed" .sisyphus/evidence/keycloak-logs.txt | grep -v "No children" | head -5
      5. Assert: No critical errors (allowing benign messages)
    Expected Result: Database connection successful, no errors
    Evidence: Logs saved and grep results

  Scenario: Ingress Status Verified
    Tool: Bash
    Preconditions: Ingress resource exists
    Steps:
      1. kubectl get ingress -n apps -l app.kubernetes.io/name=keycloak -o yaml > .sisyphus/evidence/keycloak-ingress.yaml
      2. cat .sisyphus/evidence/keycloak-ingress.yaml | grep -A2 "hosts:"
      3. Assert: HOSTS contains keycloak.identity.josevictor.me
      4. cat .sisyphus/evidence/keycloak-ingress.yaml | grep -A2 "tls:"
      5. Assert: TLS secret configured
    Expected Result: Ingress properly configured with TLS
    Evidence: Ingress YAML saved and verified
  \`\`\`

  **Evidence to Capture**:
  - kubectl get pods output
  - kubectl get ingress output  
  - curl response (realm endpoint)
  - Pod logs (database connection)
  - All to `.sisyphus/evidence/keycloak-*.{txt,yaml,json}`

  **Commit**: YES (if not already committed in Task 4)
  - Message: `feat: deploy keycloak to homelab`
  - Files: All modified files committed and pushed

---

## Commit Strategy

| After Task | Message | Files | Verification |
|------------|---------|-------|--------------|
| 1 | `feat(kubenix): add keycloak database registration` | config/kubernetes.nix | git diff shows addition |
| 2 | `feat(kubenix): add keycloak secrets configuration` | modules/kubenix/apps/keycloak-config.enc.nix | sops -d verifies |
| 3 | `feat(kubenix): add keycloak app deployment` | modules/kubenix/apps/keycloak.nix | nix-instantiate passes |
| 4 | `feat: add keycloak deployment manifests` | .k8s/keycloak*.yaml | make manifests succeeds |
| 5 | `feat: deploy keycloak to homelab` | All files | All QA scenarios pass |

---

## Success Criteria

### Verification Commands
```bash
# Pod ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=keycloak -n apps --timeout=300s

# HTTPS endpoint
curl -f https://keycloak.identity.josevictor.me/realms/master

# Admin console
curl -f https://keycloak.identity.josevictor.me/auth/admin/

# Database connection
kubectl logs -n apps -l app.kubernetes.io/name=keycloak | grep -i database

# Ingress
kubectl get ingress -n apps -l app.kubernetes.io/name=keycloak
```

### Final Checklist
- [ ] Keycloak pod running (1/1 ready)
- [ ] HTTPS endpoint returns HTTP 200
- [ ] Admin console accessible
- [ ] Database connection logs verified
- [ ] Ingress configured with TLS
- [ ] All secrets encrypted via SOPS
- [ ] All evidence captured to .sisyphus/evidence/
