# ADR-0031: Network segmentation — VLAN design

**Status:** Accepted

## Context
All prior design work assumed a flat network. Before any host provisioning begins, traffic classes identified across earlier decisions (Proxmox management, Kubernetes cluster traffic, Longhorn storage replication, client-facing ingress, backup/DDNS egress) need physical/logical isolation from each other and from the existing home LAN.

## Decision
Six VLANs, enforced via a Cisco RV320 (firewall/routing) and HPE 1920/1950 managed switches (802.1Q trunking):

| VLAN ID | Name | Purpose | IP range | NIC mapping |
|---|---|---|---|---|
| 1 (untagged) | HOME | Existing home LAN, family devices, existing k3s study cluster | existing range | — |
| 10 | MGMT | Proxmox Corosync, host SSH/web UI, Ansible access | 10.10.10.0/24 | 1G onboard |
| 20 | CLUSTER | Kubernetes node-to-node (CNI overlay, API server) | 10.10.20.0/24 | 10G port 2 |
| 30 | STORAGE | Longhorn replica sync only | 10.10.30.0/24 | 10G port 1 |
| 40 | DMZ-INGRESS | HAProxy ↔ ingress-nginx; the only VLAN with internet exposure | 10.10.40.0/24 | 1G (PCIe x1) #1 |
| 50 | EGRESS | Backup CronJob, DDNS updater — outbound only | 10.10.50.0/24 | 1G (PCIe x1) #2 |

Firewall policy: traffic only crosses a VLAN boundary where a specific, named reason exists, and never in a direction that lets a less-trusted zone reach a more-trusted one uninvited. Notably: STORAGE is fully isolated (no routing in or out); DMZ-INGRESS may only reach nodes' ingress port (80/443), nothing else; DMZ-INGRESS can never initiate into HOME, MGMT, CLUSTER, or STORAGE; EGRESS accepts no inbound connections from anywhere.

## Reasoning
Designing segmentation before any host provisioning avoids retrofitting VLANs onto already-running infrastructure, and confines the internet-exposed attack surface (DMZ-INGRESS) to the smallest possible blast radius — a compromised HAProxy/ingress-nginx path cannot reach management, cluster, or storage traffic.

## Consequences
Each RKE2 node requires interfaces on 4 VLANs (MGMT, CLUSTER, STORAGE, DMZ-INGRESS); EGRESS traffic may ride an existing interface via routing rather than requiring a 5th physical/tagged interface per node.

## Addendum: Static addressing, no DHCP on tagged VLANs
All tagged VLANs (10/20/30/40/50) use static IP assignment only, defined via OpenTofu/cloud-init and tracked in Ansible inventory — no DHCP server runs on these segments. Only VLAN 1 (HOME) retains DHCP, for its existing use case of arbitrary, unpredictable client devices. Each node's default route (0.0.0.0/0) is carried exclusively by its EGRESS interface; all other interfaces (MGMT, CLUSTER, STORAGE, DMZ-INGRESS) carry only local-subnet routes, with no gateway configured, to prevent asymmetric routing across the multiple NICs/VLANs each node participates in.