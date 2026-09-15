# Custom CNPG image: postgresql-cnpg

**Source:** `oci-images/postgresql-cnpg/Containerfile`
**Base:** `ghcr.io/tensorchord/cloudnative-vectorchord:18.6-1.1.1@sha256:c7672bc011351a587cc292a94aac7eeebb593ed2e120077bd9c9944c9467db93`
(PostgreSQL 18.6, vchord 1.1.1, vector 0.8.6, contrib, barman-cloud, uid 26) + `postgresql-18-postgis-3` 3.6.4 from PGDG.

## Current release

| Tag | Remote manifest digest | Built |
|---|---|---|
| `ghcr.io/josevictorferreira/postgresql-cnpg:18.6-vchord1.1.1-postgis3` | `sha256:5b3c66d10a39ff0c4a70f4908fc1e8c1c4d4f2a03f517cb5d7dec39b44eacea2` | 2026-09-15 |

The package is private on GHCR; the `databases` namespace pulls it with `ghcr-registry-secret`.
Referenced from `modules/kubenix/databases/_postgresql-lib.nix`.

## Build and push

```bash
cd oci-images/postgresql-cnpg
podman build --no-cache -t localhost/postgresql-cnpg:<tag> -f Containerfile .
podman rmi ghcr.io/josevictorferreira/postgresql-cnpg:<tag> 2>/dev/null   # never push a stale cached GHCR tag
podman tag localhost/postgresql-cnpg:<tag> ghcr.io/josevictorferreira/postgresql-cnpg:<tag>
podman push --format oci ghcr.io/josevictorferreira/postgresql-cnpg:<tag>
nix run nixpkgs#skopeo -- inspect --format '{{.Digest}}' docker://ghcr.io/josevictorferreira/postgresql-cnpg:<tag>
```
GHCR pushes can hit a "secondary rate limit"; wait a few minutes and retry. Always verify with `set -o pipefail`, a `| tail` hides the failure.

## Verification performed (2026-09-15, Phase 2 gate)

- `id -u` = 26; `postgres`, `pg_basebackup`, `pg_dump`, `pg_restore`, `barman-cloud-*` present.
- `initdb` + `shared_preload_libraries='vchord.so'`, then `CREATE EXTENSION` for
  vector, vchord, postgis, pg_trgm, unaccent, cube, earthdistance, uuid-ossp, pgcrypto: all OK.
  Versions: vchord 1.1.1, vector 0.8.6, postgis 3.6.4, pg_trgm 1.6, pgcrypto 1.4, cube 1.5, earthdistance 1.2, unaccent 1.1, uuid-ossp 1.1.
- The image has no docker-entrypoint (`ENTRYPOINT=[] CMD=[bash]`): the official `postgres` env vars
  (`POSTGRES_HOST_AUTH_METHOD`, `PGDATA`) do nothing. For scratch use run `initdb` yourself, e.g.
  `--user 26 --entrypoint '' sh -c 'initdb -U postgres --auth=trust -D /tmp/pgdata && exec postgres -D /tmp/pgdata'`.
  Give the container `--shm-size=1g` or larger, otherwise parallel index builds fail with
  "could not resize shared memory segment".
