# TAK Server — Kubernetes Manifests

Kubernetes manifests for deploying [TAK Server](https://github.com/TAK-Product-Center/Server) — the open-source Cursor-on-Target (CoT) messaging and geospatial awareness server used by the TAK ecosystem (ATAK, WinTAK, iTAK).

---

## Architecture

TAK Server is a **microservices application** consisting of four components that must start in order:

```
PostgreSQL/PostGIS  ←  Schema Manager (Job, runs once)
        ↓
  Config Service   (Spring profile: config)  — Ignite configuration hub
        ↓
Messaging Service  (Spring profile: messaging)  — CoT routing engine
        ↓
   API Service     (Spring profile: api)  — REST API + WebSocket + Admin UI
```

---

## Files

| File | Description |
|------|-------------|
| `00-namespace.yaml` | `tak-server` namespace |
| `01-secrets.yaml` | Database credentials (replace placeholders!) |
| `02-configmap.yaml` | `CoreConfig.xml`, `TAKIgniteConfig.xml`, DB init SQL |
| `03-postgres.yaml` | PostgreSQL 15 + PostGIS 3.3 StatefulSet + Service |
| `04-shared-resources.yaml` | PVCs for certs/logs, ServiceAccount, RBAC for Ignite |
| `05-schemamanager-job.yaml` | One-time DB migration Job |
| `06-config-deployment.yaml` | Config microservice Deployment + headless Ignite Service |
| `07-messaging-deployment.yaml` | Messaging microservice Deployment + LoadBalancer Service |
| `08-api-deployment.yaml` | API microservice Deployment + ClusterIP Service |
| `09-ingress.yaml` | NGINX Ingress (SSL passthrough) for API and Admin UI |
| `10-hpa-networkpolicy.yaml` | HorizontalPodAutoscalers + NetworkPolicies |
| `kustomization.yaml` | Kustomize entry point |

---

## Prerequisites

1. **Kubernetes cluster** — 1.26+ recommended
2. **kubectl** configured for your cluster
3. **NGINX Ingress Controller** with `--enable-ssl-passthrough`:
   ```bash
   helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
     --set controller.extraArgs.enable-ssl-passthrough=true
   ```
4. **Metrics Server** (for HPA):
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
   ```
5. **TAK Server container image** — Build from source or obtain from tak.gov.  
   Update image references in files `05`–`08` (search for `ghcr.io/tak-product-center`).
6. **ReadWriteMany StorageClass** — Required for the `tak-certs-pvc` and `tak-logs-pvc` PVCs (e.g. NFS, CephFS, AWS EFS). Update `storageClassName` in `04-shared-resources.yaml` and `03-postgres.yaml`.

---

## Quick Start

### 1. Update secrets

Edit `01-secrets.yaml` and replace the default base64-encoded passwords:
```bash
echo -n 'YourSecurePassword' | base64
```

### 2. Update domain names

Edit `09-ingress.yaml` and replace `tak.example.com` / `tak-admin.example.com` with your domain.

### 3. Update StorageClass

Edit `storageClassName` in `03-postgres.yaml` and `04-shared-resources.yaml` to match your cluster.

### 4. Update image references

Replace `ghcr.io/tak-product-center/takserver-core:latest` in deployments `06`–`08` with your actual image.

### 5. Generate TLS certificates

TAK Server requires a PKI with a Certificate Authority, server certificate, and client certificates.  
Use the scripts in `utils/misc/certs` from the TAK Server source repo, or follow Appendix B of the TAK Server Configuration Guide.

Load your generated certs into the `tak-certs-pvc` PVC (e.g. via an init Job or `kubectl cp`).

### 6. Deploy

```bash
# Apply everything via Kustomize
kubectl apply -k .

# OR apply individually in order:
kubectl apply -f 00-namespace.yaml
kubectl apply -f 01-secrets.yaml
kubectl apply -f 02-configmap.yaml
kubectl apply -f 03-postgres.yaml
kubectl apply -f 04-shared-resources.yaml

# Wait for PostgreSQL to be ready
kubectl wait --for=condition=ready pod -l app=tak-postgres -n tak-server --timeout=120s

# Run schema migration
kubectl apply -f 05-schemamanager-job.yaml
kubectl wait --for=condition=complete job/tak-schemamanager -n tak-server --timeout=300s

# Deploy microservices
kubectl apply -f 06-config-deployment.yaml
kubectl apply -f 07-messaging-deployment.yaml
kubectl apply -f 08-api-deployment.yaml
kubectl apply -f 09-ingress.yaml
kubectl apply -f 10-hpa-networkpolicy.yaml
```

---

## Ports Reference

| Port | Protocol | Service | Description |
|------|----------|---------|-------------|
| 5432 | TCP | tak-postgres | PostgreSQL |
| 8080 | TCP | tak-api | HTTP (redirect) |
| 8087 | TCP/UDP | tak-messaging | CoT TCP/UDP (anonymous) |
| 8089 | TCP | tak-messaging | CoT TLS (certificate auth) |
| 8443 | TCP | tak-api | HTTPS API + WSS |
| 8444 | TCP | tak-api | HTTPS Admin UI |
| 47100 | TCP | internal | Apache Ignite data exchange |
| 47500 | TCP | internal | Apache Ignite discovery |

---

## Accessing the Services

**Swagger API docs:**
```
https://tak.example.com/swagger-ui.html
```

**Admin UI:**
```
https://tak-admin.example.com/
```

**CoT clients** (ATAK, WinTAK, iTAK) connect to the LoadBalancer IP/hostname on port `8087` (TCP/UDP) or `8089` (TLS).

---

## Upgrading TAK Server

1. Update the image tag in deployment files `06`–`08`.
2. Re-run the schema manager Job:
   ```bash
   kubectl delete job tak-schemamanager -n tak-server
   kubectl apply -f 05-schemamanager-job.yaml
   kubectl wait --for=condition=complete job/tak-schemamanager -n tak-server --timeout=300s
   ```
3. Perform a rolling update:
   ```bash
   kubectl rollout restart deployment/tak-config deployment/tak-messaging deployment/tak-api -n tak-server
   ```

---

## Notes

- **Secrets management**: For production, replace the plain Secrets with [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets), [External Secrets Operator](https://external-secrets.io/), or [HashiCorp Vault](https://www.vaultproject.io/).
- **HA clustering**: Scaling Messaging or API beyond 1 replica requires the Ignite cluster to be properly configured and an RWX StorageClass for shared cert/log volumes.
- **TAK Server images**: Official images are distributed via [tak.gov](https://tak.gov) and the [DoD Platform One Iron Bank](https://ironbank.dso.mil/). You must build from source or obtain an official image — no public image registry is maintained.
