# RouteWell Multi-Tier Azure Infrastructure

Infrastructure project demonstrating the deployment and validation of a secure multi-tier network architecture on Microsoft Azure using Infrastructure as Code and Azure CLI.

## Overview

This project provisions and validates a multi-tier Azure environment consisting of separate web, application, and database virtual machines connected through an Azure Virtual Network.

The primary goal is to demonstrate practical cloud infrastructure and networking skills, including:

* Azure Virtual Networks and subnets
* Network Security Groups (NSGs)
* Virtual machine provisioning
* Private network communication
* PostgreSQL database deployment
* Network traffic validation
* Infrastructure troubleshooting
* Infrastructure documentation

The infrastructure was designed so that the application tier can communicate with the database tier over a private IP address while restricting unauthorized traffic between network tiers.

## Architecture

```text
                         Internet
                            |
                            |
                    Public IP Address
                            |
                     ┌──────────────┐
                     │  Web VM      │
                     │  10.10.0.4   │
                     └──────┬───────┘
                            |
                     Azure VNet
                     10.10.0.0/24
                            |
              ┌─────────────┴─────────────┐
              |                           |
       ┌──────▼───────┐            ┌──────▼───────┐
       │   App VM     │            │    DB VM     │
       │ 10.10.0.68   │───────────▶│ 10.10.0.132  │
       │              │   TCP 5432 │ PostgreSQL   │
       └──────────────┘            └──────────────┘
        App Subnet                   DB Subnet
        10.10.0.64/26               10.10.0.128/26
```

## Infrastructure Components

| Component             | Purpose                                      |
| --------------------- | -------------------------------------------- |
| Azure Resource Group  | Contains all project resources               |
| Azure Virtual Network | Provides private network connectivity        |
| Web VM                | Represents the public-facing web tier        |
| App VM                | Represents the application tier              |
| DB VM                 | Hosts the PostgreSQL database                |
| NSGs                  | Control inbound and outbound network traffic |
| PostgreSQL            | Database service running on the DB VM        |

## Network Configuration

The infrastructure uses private IP communication between the application and database tiers.

### Virtual Machines

| VM                 | Private IP    | Role             |
| ------------------ | ------------- | ---------------- |
| `routewell-web-vm` | `10.10.0.4`   | Web tier         |
| `routewell-app-vm` | `10.10.0.68`  | Application tier |
| `routewell-db-vm`  | `10.10.0.132` | Database tier    |

The web VM has a public IP for external access, while the application and database communication is performed using private IP addresses.

## Network Security

The database subnet is protected by an NSG that allows PostgreSQL traffic from the application subnet:

```text
Allow-PostgreSQL-From-App
Source:      10.10.0.64/26
Protocol:    TCP
Destination: Port 5432
Action:      Allow
Priority:    100
```

Other VNet traffic is restricted by:

```text
Deny-Other-VNet-Traffic
Source:      VirtualNetwork
Protocol:    Any
Action:      Deny
Priority:    200
```

This demonstrates a basic tiered network security model where database access is explicitly permitted from the application subnet.

## Validation

The infrastructure was validated using Azure Network Watcher and Azure VM Run Command.

### Application-to-Database Connectivity

The application VM successfully connected to PostgreSQL on the database VM:

```text
Connection to 10.10.0.132 5432 port [tcp/postgresql] succeeded!
```

### Network Security Validation

Traffic from the application VM to the database VM was allowed:

```text
Access    RuleName
Allow     defaultSecurityRules/AllowVnetInBound
```

Traffic from the web VM to the database VM was denied:

```text
Access    RuleName
Deny      securityRules/Deny-Other-VNet-Traffic
```

This confirms that the NSG rules are enforcing the intended network segmentation.

### PostgreSQL Validation

PostgreSQL was confirmed to be running on port `5432`:

```text
14  main  5432  online
```

The database user and database were also validated:

```text
User:     routewell_app
Database: routewell_db
Owner:    routewell_app
```

An authenticated PostgreSQL connection was successfully established:

```text
current_user  | current_database
---------------+-----------------
routewell_app | routewell_db
```

## Project Documentation

Detailed project documentation is available in the `docs` directory.

* `phase-0-design.md` — Initial infrastructure design and architecture
* `incident-report.md` — PostgreSQL deployment incident, investigation, and resolution
* `Routewell_Infrastructure_From_Scratch_Runbook.docx` — Step-by-step infrastructure deployment and validation guide
* `Routewell_Milestones_and_Errors.docx` — Project milestones, errors encountered, troubleshooting, and resolutions

## Key Learning Outcomes

This project provided practical experience with:

* Designing a multi-tier Azure network
* Creating and managing Azure resources
* Working with private IP addressing
* Configuring subnet-level network security
* Using NSGs to control traffic
* Deploying PostgreSQL on an Azure VM
* Troubleshooting network connectivity
* Diagnosing service configuration issues
* Validating infrastructure using Azure Network Watcher
* Using Azure VM Run Command for remote administration
* Documenting infrastructure incidents and resolutions

## Technologies Used

* Microsoft Azure
* Azure CLI
* Azure Virtual Machines
* Azure Virtual Network
* Azure Subnets
* Network Security Groups
* Azure Network Watcher
* PostgreSQL
* Linux
* Bash
* Infrastructure as Code

## Project Status

**Infrastructure provisioning and validation: Complete**

The final infrastructure validation confirms that:

* The Azure VNet and subnets are operational.
* The virtual machines are provisioned and reachable within the private network.
* PostgreSQL is running on the database VM.
* The application VM can connect to PostgreSQL over the private network.
* Unauthorized web-to-database traffic is denied by the NSG.
* The PostgreSQL database and application user are configured successfully.

## Author

**Adekunle Abowaba**

Cloud & DevOps Engineering Journey
