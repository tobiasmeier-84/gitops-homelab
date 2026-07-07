# ADR-0014: Perimeter protection — CrowdSec over fail2ban

**Status:** Accepted

## Context
Both CrowdSec and fail2ban block abusive IPs based on log analysis in front of internet-facing HAProxy.

## Decision
CrowdSec.

## Reasoning
CrowdSec's primary edge is its community-shared IP reputation database — blocklist decisions are informed by abuse patterns observed across CrowdSec's whole user base, not just this cluster's own logs. fail2ban only ever reacts to what it personally observes, so it can't preemptively block an IP that's already known-bad elsewhere until it misbehaves locally first.

## Consequences
Depends on an external service (CrowdSec's central API) for reputation data, versus fail2ban's fully self-contained model. Acceptable trade for meaningfully better proactive protection.
