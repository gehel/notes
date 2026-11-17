# Changelog

Every change to the Mealie deployment, in order, with the evidence that it worked. Newest at
the bottom. See [README.md](README.md) for the current state.

## 2026-11-03 — area created, nothing deployed

Wrote the manifests and the setup procedure. Nothing exists at Infomaniak yet: no project,
cluster, DNS record or certificate. Nothing has been applied to a cluster, so nothing is
verified against a running system.

Versions picked (latest stable that day, from the GitHub releases API): Mealie v3.30.0
(2026-10-31), Traefik Helm chart 42.3.0 (2026-11-03, Traefik v3.7.17), cert-manager v1.21.3
(2026-10-23). The registries themselves (ghcr.io, quay.io) were blocked from the sandbox, so
the image and OCI chart pulls are untested.

Checked in upstream source rather than assumed:

- Mealie's entrypoint (`docker/entry.sh` at v3.30.0) skips its usermod/chown/gosu step when
  started directly as `$PUID` (911 by default), so `runAsUser: 911` works without root. All of
  Mealie's writes go under `/app/data` (`mealie/core/settings/directories.py`).
- Mealie's default admin (`changeme@example.com` / `MyPassword`) is hard-coded
  (`_DEFAULT_EMAIL`/`_DEFAULT_PASSWORD`, private settings), hence the split between `k8s/app/`
  and `k8s/`.
- Traefik v3.7.17: an Ingress's router takes TLS only from annotations, not from
  `spec.tls` (`pkg/provider/kubernetes/ingress/kubernetes.go`); the redirect middleware
  passes the request through when the target URL equals the request URL
  (`pkg/middlewares/redirect/redirect.go`). The entrypoint-wide redirect's router gets
  priority `MaxInt-1` (`pkg/config/static/entrypoints.go`), which would win over
  cert-manager's challenge router.
- cert-manager v1.21.3's HTTP-01 solver pods are non-root, RuntimeDefault seccomp, no
  capabilities (`pkg/issuer/acme/http/pod.go`), so they pass the `mealie` namespace's
  `restricted` Pod Security level.
