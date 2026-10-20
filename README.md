# Pollpear_infra

The deployment: Docker Compose orchestration, the nginx edge with its WAF, TLS, the
datastores, and the observability stack. Everything needed to turn the Pollpear services
into a running, monitored system.

Part of **[Pollpear](https://github.com/transummer2026/Pollpear)**, a real-time collaborative polling platform.

## What it brings up

| Layer | Components |
| :--- | :--- |
| Edge | nginx with **ModSecurity** (OWASP CRS) as WAF, TLS via Certbot / Let's Encrypt |
| Data | PostgreSQL, Redis, **Garage** (S3-compatible object storage) |
| Secrets | HashiCorp Vault, one AppRole per service |
| Observability | Prometheus, Grafana, Alertmanager, with node, cAdvisor, postgres and redis exporters |

## Compose files

`compose.yml` holds the shared definition; `compose.dev.yml` and `compose.prod.yml`
layer the environment on top, and `compose.monitor.yml` (with its `.dev` variant) adds
the observability stack. They are composed together by the superproject's Makefile
rather than run directly.

## Scripts

`scripts/` carries the startup and operational steps: `ensure-certs.sh` (TLS
provisioning), `migrate.sh` (Prisma migrations), `garage-init.sh` (bucket and key
setup), `deploy.sh`, `fclean.sh`, and the three entrypoints that let containers
authenticate to Vault (`vault-agent-entrypoint.sh`, `vault-approle-entrypoint.sh`,
`waf-env-entrypoint.sh`).

Per-service configuration lives in `nginx/`, `postgres/`, `redis/`, `garage/`,
`prometheus/`, `grafana/`, `alertmanager/` and `vault-agent/`.
`RoadMap_deploy.md` tracks the deployment plan.

## Running it

This repository is not run on its own — the superproject composes it:

```sh
git clone --recursive https://github.com/transummer2026/Pollpear.git
cd Pollpear && make up_prod
```

Full setup instructions live in the [superproject README](https://github.com/transummer2026/Pollpear#readme).
