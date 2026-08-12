# ADR-0040: RKE2 ServiceLB + Traefik LoadBalancer exposure

**Status:** Accepted

## Context
RKE2 v1.36+ switched its default ingress controller from ingress-nginx (retired upstream March 2026) to Traefik. Getting a working, externally-reachable Traefik endpoint on bare-metal RKE2 required resolving four separate, non-obvious issues, none well-documented together in one place.

## Findings, in the order they were discovered

1. **RKE2 does not enable ServiceLB (klipper-lb) by default** — unlike k3s, where it's automatic. This is a deliberate RKE2 design choice (targets environments expecting a real cloud-provider LB or MetalLB). Without `enable-servicelb: true` in `config.yaml`, any `LoadBalancer`-type Service sits permanently at `EXTERNAL-IP: <pending>`, with no error indicating why.

2. **The Traefik chart's `service.type` key moved to `service.spec.type`** in the packaged v40.1.003 chart — a breaking change from older chart versions (and from the general upstream Traefik chart examples found in most current documentation). Confirmed by extracting the actual chart tarball and reading its real `values.yaml` directly, since online examples were for an older, differently-structured version.

3. **`node-ip` and `node-external-ip` are separate, distinct settings.** We deliberately set `node-ip` to each node's CLUSTER-VLAN address (correct, for internal pod/etcd traffic) — but ServiceLB uses `node-ip` for its `EXTERNAL-IP` reporting by default too, meaning external LoadBalancer traffic silently tried to advertise via CLUSTER instead of DMZ-INGRESS. Fix: explicitly set `node-external-ip` to each node's DMZ-INGRESS address, keeping the two traffic paths correctly separated.

4. **Traefik's own chart defaults to claiming `hostPort: 80`/`443` directly** — colliding with `svclb`'s own identical `hostPort: 80`/`443` claim on the same node, since both mechanisms assume they're the only thing binding those ports. Fix: explicitly nil out Traefik's `ports.web.hostPort`/`ports.websecure.hostPort` in the `HelmChartConfig`, leaving `svclb`'s DNAT-based proxying as the sole mechanism actually claiming host ports.

## Final working configuration

`ansible/roles/rke2/templates/config-*.yaml.j2`:
```yaml
node-ip: <CLUSTER VLAN address>
node-external-ip: <DMZ-INGRESS VLAN address>
enable-servicelb: true
```

`ansible/roles/rke2/templates/rke2-traefik-config.yaml.j2`, deployed by `ansible/roles/rke2/tasks/main.yml` to `/var/lib/rancher/rke2/server/manifests/rke2-traefik-config.yaml` on the first server node:
```yaml
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-traefik
  namespace: kube-system
spec:
  valuesContent: |-
    service:
      spec:
        type: LoadBalancer
    ports:
      web:
        hostPort: null
      websecure:
        hostPort: null
```

This is applied automatically on every `ansible-playbook site.yml --limit rke2_nodes` run — a full cluster rebuild reproduces this fix without any manual step.

## Other things learned along the way

- A `LoadBalancer` Service's `EXTERNAL-IP` list can lag behind individual nodes' actual address changes — a forced restart of the `svclb-*` pods (`kubectl delete pods -l app=<actual-label>`, note the label includes a hash suffix, check with `--show-labels` first) can be needed to force reconciliation rather than waiting indefinitely.
- `curl` from a host genuinely on the same subnet as the target is the only reliable way to isolate a VLAN/firewall-crossing question from an application-layer question — testing from an unrelated network (e.g. general LAN) conflates the two and produces an ambiguous result either way.
- RKE2's containerd socket is at `/run/k3s/containerd/containerd.sock`, not the generic default `crictl` assumes — needs `--runtime-endpoint`/`--image-endpoint` flags explicitly.

## klipper-lb's real limitation, and when it would actually matter

klipper-lb (RKE2's ServiceLB) doesn't use an IP pool at all — unlike MetalLB, it has no allocation step or CRD to configure. It simply reuses each node's existing real IP and claims a `hostPort` directly on it (visible in `EXTERNAL-IP` showing the actual node addresses, not separately-allocated virtual ones). This means **only one `LoadBalancer`-type Service can cleanly claim a given port across the cluster** — a second Service wanting port 80/443 would collide exactly the way Traefik and svclb collided with each other during initial setup (see above).

Our architecture never hits this limitation, because by design there's only ever **one** `LoadBalancer` Service in the cluster — Traefik's own. Every application gets a plain `ClusterIP` Service plus its own `Ingress`/`IngressRoute` that Traefik reads and routes to at the HTTP layer, rather than requesting its own `LoadBalancer` Service. The "single ingress point, everything else routes through it" pattern and klipper-lb's node-IP-reuse model are a good structural fit for each other, not a coincidence.

**Worked example — Plex** (a planned future workload): Plex's local network discovery (DLNA/SSDP) is UDP broadcast, LAN-only, and irrelevant to remote/internet access regardless of ingress design. Actual remote access is just HTTPS to a web UI — fits the existing `ClusterIP` + `Ingress` pattern with zero architectural changes, same as Nextcloud or Harbor. Plex's own "Custom server access URLs" setting should be pointed at the public hostname, with its built-in UPnP/auto-remote-access disabled, since that mechanism assumes direct internet exposure and conflicts with being reverse-proxied.

**The actual trigger for needing MetalLB instead**: a workload requiring a genuinely non-HTTP protocol exposed directly to the internet, which Traefik cannot proxy at the HTTP layer (e.g. a raw TCP/UDP service like a game server or VPN endpoint that clients connect to directly, not via a browser/HTTP client). Not currently needed by anything planned.

## Consequences
- All four fixes are fully automated via the Ansible `rke2` role — a cluster rebuild from scratch reproduces this configuration without any manual step, closing the gap that would otherwise exist between "documented" and "actually reconstructable from git."
- klipper-lb is sufficient for the current and foreseeable workload set (see above); MetalLB adoption is deferred until a concrete non-HTTP, directly-internet-facing workload actually requires it.

## Addendum: HAProxy health check needed adjustment too

Even after the ingress chain worked correctly, HAProxy's default health check
(`option httpchk GET /`, implicitly expecting only 2xx/3xx) treated Traefik's
correct `404` response (no routes configured yet) as an unhealthy backend —
`Layer7 wrong status, code: 404`. Fixed with `http-check expect status
200-499`, deliberately distinguishing "server is broken" (connection
refused/timeout/5xx) from "server is fine, nothing's routed here yet" (4xx).
Traefik's dedicated `/ping` health endpoint would be the textbook-correct
target, but it's only exposed on Traefik's internal admin port (8080),
not on the LoadBalancer Service — exposing that port externally just for
a cleaner health check was judged not worth the security trade-off.