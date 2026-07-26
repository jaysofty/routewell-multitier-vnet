# RouteWell Phase 0 — Infrastructure Design

**Project:** RouteWell Multi-Tier VNet Infrastructure  
**Date:** 26 July 2026  
**Status:** Design baseline for the validated infrastructure milestone

## 1. Objective

Design and provision a segmented Azure network for a three-tier workload consisting of Web, Application and Database tiers.

The infrastructure milestone proves that the network architecture, security boundaries, VM placement and PostgreSQL connectivity work correctly. Application deployment is outside this milestone.

## 2. Target Architecture

```text
Internet
   |
   | TCP 80/443
   v
Web Tier
10.10.0.0/27
routewell-web-vm
Public IP: Web only
   |
   | TCP 8080
   v
Application Tier
10.10.0.64/26
routewell-app-vm
Private IP only
   |
   | TCP 5432
   v
Database Tier
10.10.0.128/28
routewell-db-vm
Private IP only
```

## 3. Addressing Plan

| Component | CIDR / IP |
|---|---|
| VNet | 10.10.0.0/16 |
| Web subnet | 10.10.0.0/27 |
| Reserved range | 10.10.0.32/27 |
| App subnet | 10.10.0.64/26 |
| DB subnet | 10.10.0.128/28 |

Observed final VM addresses:

- Web: 10.10.0.4, public IP 20.164.45.57
- App: 10.10.0.68
- DB: 10.10.0.132

## 4. Security Design

- Only the Web VM has a public IP.
- Application and Database VMs use private IP addresses.
- The DB NSG allows TCP 5432 from the Application subnet.
- Other VNet inbound traffic to the DB tier is denied.
- Direct Web-to-Database traffic must be denied.
- Administrative access is performed through Azure CLI Run Command for this milestone.

## 5. Acceptance Criteria

1. Three VMs are provisioned in the intended subnets.
2. Only the Web VM has a public IP.
3. App-to-DB traffic on TCP 5432 is allowed.
4. Web-to-DB traffic is denied.
5. PostgreSQL is online on port 5432.
6. `routewell_app` exists.
7. `routewell_db` exists and is owned by `routewell_app`.
8. Authenticated PostgreSQL access succeeds.
9. Evidence is captured with screenshots.

## 6. Final Validation Status

All acceptance criteria above were successfully validated on 26 July 2026.
