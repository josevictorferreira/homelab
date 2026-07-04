# OIDC-capable services inventory

## OIDC Provider
- **Keycloak** at `identity.josevictor.me`
  - Realm: `homelab`
  - Realm: `valoris` (Valoris app)
  - Chart: CloudPirates Keycloak 26.5.2
  - External DB: PostgreSQL-18

## Already Configured with OIDC

| Service | OIDC Setup |
|--------|------------|
| **Keycloak** | Itself as the IdP |
| **Home Assistant** | `hass-oidc-auth` custom component -> Keycloak `homelab` realm; roles `homeassistant` / `homeassistantadmin` |
| **Hermes Agent Dashboard** | `HERMES_DASHBOARD_OIDC_*` env vars -> Keycloak; currently runs `--insecure` |
| **Valoris** | Keycloak `valoris` realm; Rails uses `KEYCLOAK_*` env vars for auth |
| **Oratoria** | Uses `oidc-client-ts`; likely front-end OIDC via Keycloak |
| **Grafana** | `auth.generic_oauth` -> Keycloak `homelab` realm; client `grafana`; role mapping `grafana-admin` -> Admin |
| **OpenClaw** | Uses OpenAI Codex OAuth (not Keycloak) |

## Services with Native OIDC/OAuth Support - Not Currently Wired to Keycloak

- **immich** - OIDC
- **open-webui** - OAuth/OIDC
- **readeck** - OIDC
- **sftpgo** - OIDC
- **tuwunel** - OIDC capable
- **uptime-kuma** - OIDC (2.x)
- **prowlarr / radarr / sonarr / lidarr / readarr** - OIDC/auth proxies
- **n8n** - OAuth2 for credentials + user auth
- **Synapse (matrix)** - Supports OIDC registration/login, but currently not wired

## Services Without Native OIDC Support

- **searxng**, **glance**, **ntfy**, **hindsight**
- **qbittorrent** - WebAPI auth only, no OIDC
- **omniroute**, **router9**, **homelab-bridge**, **lightpanda**, **degoog**, **cloakbrowser**, **qui**, **personal-finance-dashboard** - unknown/unsupported

## Architecture Note

There is no **forward-auth proxy** deployed (`oauth2-proxy`, `Authelia`, `Authentik`, Traefik forward auth). Ingress uses **Cilium Ingress Controller**, which has no built-in OIDC/auth middleware. So OIDC support depends on each app natively supporting it.
