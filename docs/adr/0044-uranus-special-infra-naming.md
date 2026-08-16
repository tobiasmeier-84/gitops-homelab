# ADR-0044: Uranus moons for "special infrastructure" VMs

**Status:** Accepted

## Context
Titan/Neptune moons already cover the general VM tier and the gateway
(HAProxy) tier respectively. Mars moons (Phobos, Deimos) were reserved
for a genuine security-boundary component (see ADR-0045). A new,
distinct need emerged: internal DNS + filtering VMs, which are neither
general-purpose compute nor a security gateway, but standalone
"special infrastructure" that doesn't cleanly fit an existing tier.

Jupiter was considered but rejected — it's already reserved (ADR-0035)
for `proto.solsys.dev` prototype workloads, a workload-tier meaning
distinct from this VM-tier need. Reusing the same planet for two
unrelated meanings would blur the "one planet, one meaning" pattern
that's held cleanly so far.

## Decision
Uranus's moons name this new "special infrastructure" VM tier —
standalone infrastructure VMs that are neither general compute nor a
gateway/security boundary. First use: `titania` and `oberon` (Uranus's
two largest, most prominent moons) for the internal DNS + filtering
pair (CoreDNS + Pi-hole, see ADR-0046).

## Reasoning
Genuinely unclaimed elsewhere in the scheme, with real headroom (27
known moons) for future infrastructure VMs of this kind. No attempt is
made to force a deeper thematic justification the way Neptune's
"outermost planet = gateway" reasoning worked — this is a pragmatic
choice (next clean, unclaimed planet with sufficient room), not a
lore-driven one, and that's fine; not every tier needs a poetic reason.

## Consequences
- Future standalone infrastructure VMs (neither general compute nor a
  security gateway) should draw from Uranus's remaining moons
  (Umbriel, Ariel, Miranda, and 22 others) rather than opening a new
  planet.