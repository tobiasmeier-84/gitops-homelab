# ADR-0033: Network device configuration — out of IaC scope

**Status:** Accepted

## Context
Neither the Cisco RV320 nor the HPE 1920/1950 switches expose a practical Terraform/Ansible-friendly automation API, unlike every other layer of this platform.

## Decision
Configure these devices manually via their web GUIs. Do not attempt to track their configuration in git, even as a non-automated backup/export.

## Reasoning
The effort of maintaining exported config backups for hardware that can't be re-applied via automation anyway doesn't proportionately add to the "reconstructable from git" principle — without an API to apply it, a committed config export is closer to documentation than infrastructure-as-code, and the VLAN design itself (ADR-0031) is already fully documented in this repo, which captures the intent even without the exact device-specific config.

## Consequences
Rebuilding these two devices from scratch after a failure requires manually reconstructing their configuration from ADR-0031's design tables rather than replaying a saved config file. This is an explicitly accepted gap in the platform's overall reconstructability claim (see ADR-0023's DR runbook, which should note this exception).