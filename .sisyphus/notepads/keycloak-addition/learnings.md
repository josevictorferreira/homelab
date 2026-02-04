# Keycloak Addition Learnings

## Task 1: Database Registration ✅
- Added "keycloak" to `config/kubernetes.nix` databases.postgres list
- This triggers postgresql-18-bootstrap job to create 'keycloak' database
- Pattern: Simple list addition, no other changes needed

## Task 2: Encrypted Secrets ✅
- Created `modules/kubenix/apps/keycloak-config.enc.nix`
- Uses `kubenix.lib.secretsFor` for secret references
- DB_PASSWORD references `postgresql_admin_password`
- KEYCLOAK_ADMIN_PASSWORD is new secret for admin user

## Pattern: Database Registration
```nix
databases = {
  postgres = [
    "linkwarden"
    "openwebui"
    "n8n"
    "immich"
    "valoris_production"
    "valoris_production_queue"
    "keycloak"  # NEW - triggers bootstrap job
  ];
};
```

## Pattern: SOPS Secrets (from n8n-enc.enc.nix)
```nix
{ kubenix, homelab, ... }:

let
  namespace = homelab.kubernetes.namespaces.applications;
in
{
  kubernetes = {
    resources = {
      secrets."keycloak-env" = {
        metadata = {
          namespace = namespace;
        };
        stringData = {
          "DB_PASSWORD" = kubenix.lib.secretsFor "postgresql_admin_password";
          "KEYCLOAK_ADMIN_PASSWORD" = kubenix.lib.secretsFor "keycloak_admin_password";
        };
      };
    };
  };
}
```

## Pattern: External PostgreSQL (from linkwarden.nix)
```nix
postgresql.enabled = false;  # Disable embedded

# Then configure external connection in the app values
```
