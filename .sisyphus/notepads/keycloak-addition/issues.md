# Keycloak Addition - Issues Encountered

## Blocker: SHA256 Hash Mismatch

### Problem
All attempts to generate Kubernetes manifests for Keycloak have failed with hash mismatch errors.

### Attempts Made
1. **CloudPirates OCI chart**
   - Chart: oci://registry-1.docker.io/cloudpirates/keycloak
   - Version: 0.14.2 (Keycloak 26.5.2)
   - Result: Hash mismatch

2. **Codecentric HTTP chart** 
   - Chart: https://codecentric.github.io/helm-charts/keycloak
   - Version: 18.10.0 (Keycloak 17.0.1)
   - Result: Hash mismatch

3. **nix-prefetch-url**
   - Attempted: HTTP and OCI URLs
   - Result: Doesn't work for chart URLs (returns HTML)

### Root Cause Analysis
The kubenix library requires exact SHA256 hashes for Helm chart downloads. Standard hash tools don't work correctly:
- `sha256sum` on downloaded tarball gives hex hash
- `nix-prefetch-url` returns HTML/content instead of hash
- Base64 conversion doesn't match what kubenix expects

### Files Already Created
- ✅ `config/kubernetes.nix` - Added "keycloak" to databases.postgres list
- ✅ `modules/kubenix/apps/keycloak-config.enc.nix` - Encrypted secrets
- ✅ `modules/kubenix/apps/keycloak.nix` - App definition (codecentric chart)

### Next Steps Needed
1. Get correct SHA256 hash for codecentric chart
2. Run `make manifests` successfully
3. Commit and push changes
4. Verify deployment with QA scenarios

### Potential Solutions
1. Use existing working kubenix chart hash as template reference
2. Contact kubenix maintainers for hash verification
3. Try manual Helm chart fetch with different tools
4. Use Official Keycloak Operator YAML directly
