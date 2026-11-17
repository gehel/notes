# Mealie on Infomaniak Kubernetes

Self-hosting [Mealie](https://mealie.io) (recipe manager, meal planner, shopping lists) for the
family on Infomaniak's managed Kubernetes. Started 2026-11-03. Read this first: it holds the
current status, the decisions and their reasons, the setup procedure, and links everything
else. Every change gets logged in [changelog.md](changelog.md) as it happens.

## Status

**2026-11-03: manifests written, nothing created at Infomaniak yet.** No Public Cloud project,
cluster, DNS record or certificate exists. Next step: "Setup" below, from step 1. None of the
manifests has been applied to a real cluster yet, so treat the first run as a test of them.

## Architecture

```
browser ──HTTPS──> mealie.ledcom.fr (A record at Gandi)
                     │
                     ▼
        Octavia load balancer (public IP)       ← created by Traefik's Service type=LoadBalancer
                     │
   ┌─────────────────┼──── Kubernetes cluster (Infomaniak, shared control plane, 1 node) ───┐
   │                 ▼                                                                      │
   │  ns traefik:   Traefik ── TLS cert from Secret mealie-tls (cert-manager, Let's Encrypt) │
   │                 │   (only Traefik may reach Mealie: NetworkPolicy)                     │
   │                 ▼                                                                      │
   │  ns mealie:    Service mealie:80 ──> Pod mealie:9000 (1 replica, uid 911)              │
   │                                         │                                              │
   │                                         ▼                                              │
   │                                   PVC mealie-data 5Gi (Cinder block volume)            │
   │                                   /app/data: SQLite DB, images, backups                │
   └────────────────────────────────────────────────────────────────────────────────────────┘
```

## Layout

- `cluster/` — cluster-wide pieces, installed once: Helm values for Traefik and cert-manager,
  and the Let's Encrypt `ClusterIssuer`.
- `k8s/` — Mealie, as a kustomization. `k8s/app/` is the app alone (namespace, settings,
  volume, Deployment, Service, NetworkPolicy); `k8s/` adds its public exposure (Ingress and
  HTTP→HTTPS redirect). Settings are in [`k8s/app/mealie.env`](k8s/app/mealie.env).

The kubeconfig never goes in this repo: it lives in `~/.kube/infomaniak.yaml`.

## Decisions

| Decision | Why |
| --- | --- |
| Infomaniak managed Kubernetes, **shared (free) control plane** | Guillaume's call: Kubernetes at Infomaniak. The shared plan has no SLA (one API server replica) but no control-plane fee either: only the node, volume, load balancer and IP are billed. More than enough for a family app. |
| **One node, 2 vCPU / 4 GB** | Mealie wants up to ~1 GB, plus Traefik, cert-manager and the cluster's own agents (Cilium, CSI). 2 GB would be tight. |
| **SQLite** on a block volume, not Postgres | Upstream recommends SQLite for 1–20 users. Its NAS warning is about network *file systems*; a Cinder volume is a block device mounted by one node, so locking works. One fewer service to run and back up. |
| **One replica, `Recreate`** | Follows from SQLite + a ReadWriteOnce volume. A few seconds of downtime per upgrade is fine. |
| **Traefik** as ingress controller | ingress-nginx was retired in March 2026. Traefik is the usual replacement and handles plain `Ingress` objects. |
| **cert-manager**, HTTP-01 | Certificates as Secrets, independent of the ingress controller; HTTP-01 needs no Gandi token in the cluster. |
| Redirect per Ingress, not per entrypoint | An entrypoint-wide redirect would break the HTTP-01 challenge. Details in `k8s/middleware.yaml`. |
| Hostname **`mealie.ledcom.fr`** | Default pick, on the existing Gandi zone. To change it, edit `k8s/ingress.yaml` (twice) and `BASE_URL` in `k8s/app/mealie.env`. |
| Mealie runs as **uid 911, non-root**, namespace at Pod Security `restricted` | The image's entrypoint supports it (it skips its root-only steps when already started as the target uid). |
| **Public on the internet**, sign-up off | The family uses it from phones, including at the shop. Accounts only by invitation. |
| Versions pinned: Mealie **v3.30.0**, Traefik chart **42.3.0** (Traefik v3.7.17), cert-manager **v1.21.3** | Latest stable on 2026-11-03. Bump deliberately, see "Operations". |

## Setup

Run from `home/mealie/`. Log each step's outcome in `changelog.md`.

### 0. Tools

`kubectl` and `helm` on the laptop (e.g. `sudo snap install kubectl --classic` and
`sudo snap install helm --classic`), then add them to `home/install.md`.

### 1. Cluster

1. Infomaniak Manager → Public Cloud: create a project if there is none.
2. In the project, Kubernetes Service → new cluster: **shared** control plane, one node pool
   with **one node of 2 vCPU / 4 GB**, in a **single availability zone** (a block volume
   can only attach to a node in its own zone).
3. Download the kubeconfig to `~/.kube/infomaniak.yaml`, `chmod 600` it, then
   `export KUBECONFIG=~/.kube/infomaniak.yaml`.
4. Check, and record in the changelog:
   ```
   kubectl version
   kubectl get nodes -o wide
   kubectl get storageclass       # which one is "(default)"? Must be block storage (Cinder).
   ```
   If no class is marked default, set `storageClassName` in `k8s/app/pvc.yaml`.

### 2. Traefik and cert-manager

```
helm install traefik oci://ghcr.io/traefik/helm/traefik --version 42.3.0 \
  --namespace traefik --create-namespace -f cluster/traefik-values.yaml
kubectl -n traefik get svc traefik -w        # wait for EXTERNAL-IP (the Octavia LB)

helm install cert-manager oci://quay.io/jetstack/charts/cert-manager --version v1.21.3 \
  --namespace cert-manager --create-namespace -f cluster/cert-manager-values.yaml
kubectl -n cert-manager rollout status deploy/cert-manager-webhook
kubectl apply -f cluster/cluster-issuer.yaml
kubectl get clusterissuer letsencrypt        # READY True
```

Record the load balancer's public IP below and in the changelog.

### 3. DNS

At Gandi, in `ledcom.fr`: `mealie  300  IN  A  <EXTERNAL-IP>`. Check with
`dig +short mealie.ledcom.fr`; it must return the load balancer's IP before step 5, or the
HTTP-01 challenge fails.

### 4. Mealie, not exposed yet

On first start Mealie creates an admin **`changeme@example.com` / `MyPassword`**, and this
can't be configured. As soon as the certificate is issued, the hostname is public in the
Certificate Transparency logs, which scanners watch. So change that account **before**
creating the Ingress:

```
kubectl apply -k k8s/app/
kubectl -n mealie rollout status deploy/mealie --timeout=5m
kubectl -n mealie port-forward svc/mealie 9925:80
```

At http://localhost:9925, log in with the defaults, then change the admin's email and set a
strong password. Check `/admin/site-settings` for warnings. Stop the port-forward.

### 5. Exposure

```
kubectl apply -k k8s/
kubectl -n mealie get certificate mealie-tls -w           # READY True, usually under 2 min
curl -sI http://mealie.ledcom.fr/ | head -3                # 301 to https://
curl -s https://mealie.ledcom.fr/api/app/about             # "version":"v3.30.0"
```

If the certificate stays not-Ready: `kubectl -n mealie describe challenge` says why
(usually DNS not propagated yet, or port 80 not reaching Traefik).

### 6. Protect the data volume

By default, deleting the PVC (or the namespace) deletes the Cinder volume. Make the volume
survive that:

```
kubectl patch pv "$(kubectl -n mealie get pvc mealie-data -o jsonpath='{.spec.volumeName}')" \
  -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

### 7. Checks

- The NetworkPolicy holds. From another namespace, this must **time out**:
  `kubectl run np-test --rm -it --restart=Never --image=curlimages/curl:8.11.1 -- curl -m 5 http://mealie.mealie/api/app/about`
- Invite France: Admin → Users → invitation link.

## Operations

- **Apply changes:** `kubectl apply -k k8s/`. Editing `mealie.env` restarts the pod by itself
  (the ConfigMap name carries a hash).
- **Upgrading Mealie:** read the release notes of every version in between (upstream insists,
  some releases need manual steps). Admin → Backups → create one and download it. Bump the
  tag in `k8s/app/deployment.yaml`, apply, check `/api/app/about`. Log it.
- **Upgrading Traefik or cert-manager:** `helm upgrade <release> <same oci:// URL> --version
  <new> -n <ns> -f cluster/<values>`. Read the chart's release notes first: Traefik chart
  majors regularly rename values.
- **Node replacements** (Infomaniak Kubernetes upgrades, node pool changes) restart Mealie:
  a short outage, expected. The volume follows the pod as long as the new node is in the
  same zone.
- **Never** `kubectl delete -k k8s/` or `kubectl delete ns mealie` (deletes the data, unless
  step 6 was done, and even then the volume needs manual re-binding). **Never** `helm
  uninstall traefik` without planning a DNS change: deleting its Service releases the load
  balancer's public IP, and the next one will differ.

## Open items

1. **No off-cluster backup.** Everything is on one Cinder volume (3 Ceph replicas, but no
   protection against deletion or corruption). Needed before Mealie holds anything not also
   in this repo. Candidates: a CronJob that triggers Mealie's own backup through its API and
   copies the zip to Infomaniak Object Storage (S3), or Cinder volume backups.
2. **Cost not checked.** Infomaniak's price page renders prices client-side, so no figures
   here. Estimate one node (2 vCPU / 4 GB), a 5 GB volume, one load balancer and one public
   IP in the Manager's estimator, and record the result.
3. **Unverified Infomaniak details**, to check on the first run: the default StorageClass; a
   `LoadBalancer` Service working without provider annotations; Cilium enforcing
   NetworkPolicy (step 7). Also unverified from the sandbox (registries blocked): the OCI chart
   locations and the image tag. GitHub shows the releases exist.
4. **`HOST_IP=*`** in `mealie.env`: narrow it to the cluster's pod CIDR once known.
5. **Relation to KitchenOwl** (`home/cooking/`): not decided. Mealie's planner stores the
   meal type (lunch/dinner/side) and notes, which KitchenOwl's doesn't. That's why
   `home/cooking/planning.md` keeps the lunch/dinner split. Moving `scripts/kitchenowl.py`'s
   role to Mealie's API is a separate decision.

## Hard-won lessons

*(None yet.)*
