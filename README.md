# FleetDM on Kubernetes

Local environment for learning and testing [FleetDM](https://fleetdm.com/) — an open-source platform for managing and monitoring devices via osquery.

Deploys FleetDM, MySQL, Redis, and an osquery agent to a local Kind cluster with a single command. The initial setup (admin account, enroll secret, TLS, database migrations) is fully automated.

## Prerequisites

- [mise](https://mise.jdx.dev/) (installs helm, kubectl, kind)
- Docker

```bash
mise install
```

## Quick Start

```bash
make cluster   # Create a Kind cluster
make install   # Deploy FleetDM + MySQL + Redis + osquery agent
```

To install from the published chart repo instead of the local source:

```bash
make install CHART_SOURCE=remote
```

Fleet UI is available at https://localhost:8080 immediately after install (self-signed certificate). Log in with:

- **Email:** `admin@example.com`
- **Password:** `admin123#pass`

An osquery agent is automatically deployed and enrolled. It will appear under **Hosts** in the Fleet UI within a couple of minutes.

## Teardown

```bash
make uninstall   # Remove the Helm release and delete the Kind cluster
```

## Verification

Check that all pods are running:

```bash
kubectl get pods -n fleetdm
```

Expected output:

| Pod | Status |
|-----|--------|
| `fleet-*` | Running |
| `fleet-migration-*` | Completed |
| `fleetdm-mysql-0` | Running |
| `fleetdm-redis-master-0` | Running |
| `fleetdm-osquery-agent-*` | Running |

Check Fleet health:

```bash
kubectl run curl --image=curlimages/curl --rm -i --restart=Never -n fleetdm -- \
  curl -sk https://fleetdm-service:8080/healthz
```

Check MySQL connectivity:

```bash
kubectl exec -n fleetdm fleetdm-mysql-0 -- \
  mysqladmin ping -ufleet -pfleet
```

Check Redis connectivity:

```bash
kubectl exec -n fleetdm fleetdm-redis-master-0 -- \
  redis-cli ping
```

## Architecture

This project uses a standalone Helm chart (`charts/fleetdm/`) with Fleet templates inlined from the [official Fleet Helm chart](https://github.com/fleetdm/fleet/tree/main/charts/fleet) (v6.8.0), simplified for local Kind deployment. MySQL and Redis are included as Bitnami subcharts.

TODO: Bitnami recently changed their licensing and distribution model. Consider alternatives such as [KubeDB](https://kubedb.com/) for managing MySQL and Redis on Kubernetes.

```
charts/fleetdm/
  Chart.yaml                              # Direct mysql/redis dependencies
  values.yaml                             # Flat config: fleet, database, cache, osquery, setup
  templates/
    _helpers.tpl                          # Template helpers (from fleet chart)
    deployment.yaml                       # Fleet server deployment (simplified from fleet chart)
    service.yaml                          # Fleet service with NodePort (from fleet chart)
    sa.yaml                               # ServiceAccount for fleet (from fleet chart)
    rbac.yaml                             # Role/RoleBinding for secret access (from fleet chart)
    job-migration.yaml                    # DB migration job (simplified from fleet chart)
    secret-tls.yaml                       # Self-signed TLS cert (used by Fleet and osquery)
    secret-enroll.yaml                    # Placeholder enroll secret (replaced by setup hook)
    rbac-setup.yaml                       # ServiceAccount/Role/RoleBinding for the setup job
    job-setup.yaml                        # Post-install hook: admin account + enroll secret
    deployment-osquery-agent.yaml         # osquery agent that auto-enrolls into Fleet
```

On `make install`:

1. **MySQL and Redis** start as StatefulSets
2. **Self-signed TLS cert** is generated and shared between Fleet and osquery
3. **`fleet prepare db`** runs as a migration Job to initialize the schema
4. **Fleet server** starts with TLS and connects to MySQL/Redis
5. **osquery agent** starts and retries enrollment (placeholder secret is replaced after setup)
6. **Setup hook** calls `/api/v1/setup` to create the admin account, generates a random enroll secret, registers it with Fleet, and updates the Kubernetes Secret
7. **osquery enrolls** once the real enroll secret propagates (~1 min)
