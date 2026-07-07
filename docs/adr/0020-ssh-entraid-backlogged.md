# ADR-0020: SSH access via Entra ID — backlogged

**Status:** Accepted risk (backlogged)

## Context
SSH access to the Proxmox hosts and RKE2 node VMs currently uses key-based authentication (see the SSH key setup and KeePass backup already in place). Integrating SSH with Entra ID SSO would require standing up dedicated infrastructure — e.g. Smallstep step-ca issuing short-lived SSH certificates via an OIDC provisioner, or a platform like Teleport.

## Decision
Defer SSH-to-Entra-ID integration. Continue with key-based SSH access for now.

## Reasoning
SSO's main value for SSH access — centralized user lifecycle management and audit logging across multiple people — matters most with multiple admins or frequent access changes. This is a single-operator environment with well-managed SSH keys (generated properly, backed up securely). The operational cost of running and securing a new CA or access-proxy platform isn't currently justified by the benefit.

## Consequences
SSH access remains a separate credential domain from the rest of the platform's Entra ID-integrated services. Revisit if a second administrator is added, if centralized audit logging of SSH access becomes a real requirement, or if this becomes specifically desired as a portfolio talking point independent of home-lab necessity.