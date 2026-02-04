# Draft: Keycloak Addition to Homelab

## Requirements (confirmed)
- Add Keycloak service using CloudPirates Helm chart
- Single instance (1 pod)
- Enable ingress access (HTTPS URL)
- Create new database in existing postgresql-18

## Research Findings

### CloudPirates Keycloak Chart ✅ HIGHLY VIABLE

**Chart Details:**
- **Version:** 0.14.2 (latest)
- **Keycloak:** 26.5.2 (current stable)
- **Last Updated:** February 4, 2026 (hours ago - actively maintained)
- **Repository:** cloudpirates-io/helm-charts (1,888+ commits, 418 stars)
- **Security:** Signed charts, non-root containers, read-only filesystem

**Installation (OCI Registry):**
```bash
helm install keycloak oci://registry-1.docker.io/cloudpirates/keycloak --version 0.14.2
```

**External PostgreSQL Configuration:**
```yaml
postgres:
  enabled: false  # Disable embedded

database:
  type: postgres
  host: "postgresql-18-hl"
  port: 5432
  name: "keycloak"
  existingSecret: "keycloak-db-credentials"
```

### Existing Homelab Patterns

**PostgreSQL Connection:**
- Host: `postgresql-18-hl` (existing in kube-system)
- Database: `keycloak_db` (to be created)
- Secret pattern: `kubenix.lib.secretsFor "keycloak_db_password"`

**App Structure (kubenix/apps/):**
- App definition: `modules/kubenix/apps/keycloak.nix`
- Secrets: `modules/kubenix/apps/keycloak-config.enc.nix`
- Pattern follows: n8n, linkwarden, open-webui

**Secrets Required:**
- `keycloak_db_password` - Database password
- `keycloak_admin_password` - Admin console password
- Optional: SMTP for password resets

## Configuration Decisions

### Chart Configuration
```nix
{ config, lib, ... }:

{
  kubenix.app = {
    name = "keycloak";
    namespace = "keycloak";
    
    chart = {
      source = "oci://registry-1.docker.io/cloudpirates/keycloak";
      version = "0.14.2";
    };
    
    values = {
      # Database (external postgresql-18)
      postgres.enabled = false;
      database.type = "postgres";
      database.host = "postgresql-18-hl";
      database.port = 5432;
      database.name = "keycloak";
      database.existingSecret = "keycloak-db-credentials";
      
      # Keycloak settings
      keycloak.hostname = "keycloak.${config.homelab.domain}";
      keycloak.production = true;
      
      # Ingress (Cilium)
      ingress.enabled = true;
      ingress.className = "cilium";
      ingress.hosts = [{
        host = "keycloak.${config.homelab.domain}";
        paths = [{ path = "/"; pathType = "Prefix" }];
      }];
      ingress.tls = [{
        secretName = "keycloak-tls";
        hosts = ["keycloak.${config.homelab.domain}"];
      }];
      
      # Resources (single instance)
      resources.requests.cpu = "500m";
      resources.requests.memory = "1Gi";
      resources.limits.cpu = "2000m";
      resources.limits.memory = "2Gi";
      
      # Health checks
      livenessProbe.enabled = true;
      readinessProbe.enabled = true;
    };
  };
}
```

## Open Questions

1. **Domain name**: What is your actual homelab domain? (e.g., `home.arpa`, `lan`, custom?)

2. **Resources**:
   - CPU/Memory limits acceptable? (500m-2000m, 1Gi-2Gi)
   - Need autoscaling?

3. **Admin username**: Default is `admin`. Change to something else?

4. **Features**:
   - Need SMTP for password resets?
   - Need realm import (themes, custom settings)?
   - Enable metrics endpoint for Prometheus?

5. **Secrets**: Which secret names do you prefer?
   - `keycloak_db_password` (database)
   - `keycloak_admin_password` (admin console)
   - Or custom names?

## Scope Boundaries
- IN: Keycloak 26.5.2 deployment with external PostgreSQL
- IN: Ingress configuration with TLS
- IN: Admin user setup
- IN: Secrets via SOPS
- OUT: Realm/client configuration (manual via UI)
- OUT: SMTP configuration (unless requested)
- OUT: High availability (single instance)

3. **Resource Requirements**:
   - CPU/Memory limits?
   - Replica count (HA or single instance)?

4. **Features**:
   - Need themes/customization?
   - Need SMTP configuration for password resets?
   - Need to connect to existing realm configurations?

5. **Database Configuration**:
   - Create new database? (keycloak_db)
   - Database username/password secrets needed?

6. **Ingress**:
   - Domain: keycloak.{domain}?
   - HTTPS only (TLS)?

## Scope Boundaries
- IN: Keycloak deployment with PostgreSQL connection
- IN: Basic admin user setup
- IN: Ingress configuration
- OUT: Realm/client configuration (manual via UI)
- OUT: High availability (unless requested)
