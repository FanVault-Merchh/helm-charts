# FanVault Helm Charts

Production-ready Helm deployment system for the **FanVault** MERN microservices e-commerce platform.

---

## 📋 Prerequisites

| Requirement | Notes |
|---|---|
| Helm ≥ 3.12 | `helm version` to verify |
| kubectl configured | Pointing to your cluster |
| ArgoCD installed | In the `argocd` namespace |
| MongoDB (bitnami) | Already deployed in `db` namespace |
| RabbitMQ (bitnami) | Already deployed in `db` namespace |
| kgateway | Installed via Helm; GatewayClass `kgateway` available |
| Namespaces created | `backend` and `frontend` must exist |

Create the required namespaces if not already present:

```bash
kubectl create namespace backend
kubectl create namespace frontend
kubectl create namespace db   # only if not created by MongoDB/RabbitMQ Helm
```

Label namespaces so NetworkPolicy selectors work correctly:

```bash
kubectl label namespace db kubernetes.io/metadata.name=db --overwrite
kubectl label namespace kgateway-system kubernetes.io/metadata.name=kgateway-system --overwrite
kubectl label namespace backend kubernetes.io/metadata.name=backend --overwrite
kubectl label namespace frontend kubernetes.io/metadata.name=frontend --overwrite
```

---

## 📁 Folder Structure

```
helm-charts/
├── microservice-base/          # Single reusable base chart
│   ├── Chart.yaml              # Chart metadata
│   ├── values.yaml             # Default values (overridden per-service)
│   └── templates/
│       ├── _helpers.tpl        # Shared Helm helper functions (labels, names)
│       ├── deployment.yaml     # Generic Deployment with probes, securityContext
│       ├── service.yaml        # ClusterIP Service
│       ├── configmap.yaml      # Non-sensitive env vars
│       ├── secret.yaml         # Sensitive env vars (base64 via Helm b64enc)
│       ├── networkpolicy.yaml  # Zero-trust default-deny NetworkPolicy
│       ├── gateway.yaml        # kgateway Gateway resource (conditional)
│       └── httproute.yaml      # Gateway API HTTPRoutes (conditional)
│
└── environments/               # Per-service override values
    ├── gateway-values.yaml     # ← Deploy FIRST: Gateway + all HTTPRoutes
    ├── auth-service-values.yaml
    ├── user-service-values.yaml
    ├── product-service-values.yaml
    ├── order-service-values.yaml
    ├── email-service-values.yaml
    └── frontend-values.yaml
```

---

## 🚀 Local Helm Usage

> Run all commands from the `helm-charts/` directory.

### Step 1 — Deploy the Gateway (once)

```bash
helm install gateway ./microservice-base \
  -f environments/gateway-values.yaml \
  -n backend
```

### Step 2 — Deploy Backend Services

```bash
helm install auth    ./microservice-base -f environments/auth-service-values.yaml    -n backend
helm install user    ./microservice-base -f environments/user-service-values.yaml    -n backend
helm install product ./microservice-base -f environments/product-service-values.yaml -n backend
helm install order   ./microservice-base -f environments/order-service-values.yaml   -n backend
helm install email   ./microservice-base -f environments/email-service-values.yaml   -n backend
```

### Step 3 — Deploy Frontend

```bash
helm install frontend ./microservice-base \
  -f environments/frontend-values.yaml \
  -n frontend
```

### Upgrading a Service

```bash
helm upgrade auth ./microservice-base -f environments/auth-service-values.yaml -n backend
```

### Uninstalling

```bash
helm uninstall auth -n backend
```

### Dry-run / Template Preview

```bash
helm template auth ./microservice-base -f environments/auth-service-values.yaml | less
```

---

## 🔁 ArgoCD Setup

### Installing ArgoCD (if not already done)

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### Creating an Application per Service

Create one `Application` resource per service. Example for **auth-service**:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: fanvault-auth
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<your-org>/<your-repo>.git
    targetRevision: main
    path: helm-charts/microservice-base
    helm:
      valueFiles:
        - ../environments/auth-service-values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: backend
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Repeat for each service, changing `name`, `valueFiles`, and `namespace` accordingly.  
For the **frontend**, set `namespace: frontend`.  
For the **gateway**, set `name: fanvault-gateway` and use `gateway-values.yaml`.

### Image Tag Updates

To update an image tag without editing values files, use the ArgoCD Image Updater or patch via CLI:

```bash
# Force ArgoCD to use a specific image tag at sync time
argocd app set fanvault-auth -p image.tag=v1.2.3

# Or update the values file and push to Git — ArgoCD auto-syncs on push
```

### Sync All Applications

```bash
argocd app sync fanvault-auth fanvault-user fanvault-product fanvault-order fanvault-email fanvault-frontend
```

---

## 📦 Deployment Order

To avoid dependency issues, deploy in this order:

```
1. Gateway         →  helm install gateway   (fanvault-gateway ArgoCD app)
2. email-service   →  helm install email     (no DB deps, only RabbitMQ consumer)
3. auth-service    →  helm install auth
4. user-service    →  helm install user
5. product-service →  helm install product
6. order-service   →  helm install order     (depends on email-service)
7. frontend        →  helm install frontend  (depends on all backend services)
```

---

## 🔒 Security Notes

### MongoDB & RabbitMQ are External Dependencies

This Helm chart does **NOT** deploy MongoDB or RabbitMQ.  
They are pre-existing Bitnami deployments in the `db` namespace accessible at:

- `mongodb.db.svc.cluster.local:27017`
- `rabbitmq.db.svc.cluster.local:5672`

### Secrets in Production

The current values files contain **plain-text secrets** for convenience during development.  
In production, replace the `secret:` block values with references to a secrets manager:

- **Sealed Secrets** (Bitnami) — encrypt secrets committed to Git
- **External Secrets Operator** — sync from Vault / AWS Secrets Manager / GCP Secret Manager
- **ArgoCD Vault Plugin** — inject secrets at sync time from HashiCorp Vault

Example with Sealed Secrets:

```bash
kubeseal --format yaml < secret.yaml > sealed-secret.yaml
```

### NetworkPolicy

All services use a **zero-trust default-deny** NetworkPolicy.  
Allowed traffic:

| Source | Destination | Port |
|---|---|---|
| kgateway-system pods | Service pods | containerPort |
| Same namespace pods | Service pods | containerPort |
| Service pods | db namespace | 27017 (MongoDB) |
| Service pods | db namespace | 5672 (RabbitMQ) |
| Service pods | kube-dns | 53 UDP/TCP |
