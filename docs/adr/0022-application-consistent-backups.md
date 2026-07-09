# ADR-0022: Application-consistent backups for database volumes

**Status:** Accepted

## Context
Longhorn snapshots (used in the backup pipeline, ADR-0005) are crash-consistent, not application-consistent. For Nextcloud's database volume specifically, a snapshot taken mid-write captures a state equivalent to an unclean shutdown — recoverable via the database's own write-ahead log in most cases, but not a guaranteed-clean state.

## Decision
Use Longhorn's pre/post-snapshot hook mechanism for the database PVC specifically: briefly freeze/flush the database (e.g. via a `FLUSH TABLES WITH READ LOCK` equivalent, or the database's own hot-backup mechanism) immediately before the snapshot, then release immediately after.

## Reasoning
This is a small addition to the existing backup pipeline (ADR-0005/0006) that upgrades the guarantee specifically for the one volume where "probably fine" isn't good enough — the database is the hardest-to-regenerate piece of Nextcloud's data.

## Consequences
Adds a brief write-lock window during each backup run for the database volume. Negligible at this workload's scale; general file storage volumes (e.g. Nextcloud's file data) remain crash-consistent-only, which is fine since file writes don't have the same multi-statement-transaction consistency requirement.