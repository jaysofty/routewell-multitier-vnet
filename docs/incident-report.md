# Incident Report — PostgreSQL Database Provisioning and Connectivity

**Incident ID:** RW-INC-001  
**Project:** RouteWell Multi-Tier VNet Infrastructure  
**Date:** 26 July 2026  
**Severity:** Medium — infrastructure validation blocked  
**Status:** Resolved

## 1. Incident Summary

During validation of the RouteWell multi-tier infrastructure, the Application VM could reach the Database VM on TCP port 5432, but the expected PostgreSQL service and authentication path were not initially correctly configured.

Investigation identified related issues: PostgreSQL was initially absent, a temporary `nc` listener occupied port 5432, PostgreSQL initially appeared on port 5433, PostgreSQL initially listened only on localhost, the required `routewell_app` role did not exist, and database password authentication initially failed.

## 2. Impact

The Database tier was not initially ready to support the intended Application-to-Database communication. This prevented the infrastructure milestone from being conclusively validated.

## 3. Detection

The issue was detected during database connectivity validation. A TCP connection to port 5432 succeeded, but process inspection showed that `nc`, rather than PostgreSQL, owned the listening socket.

## 4. Investigation Timeline

### Phase 1 — Port reachability

Application VM:

```text
Connection to 10.10.0.132 5432 port [tcp/postgresql] succeeded!
```

Initial interpretation: network path was reachable.

Further investigation showed the DB VM had:

```text
LISTEN 0 1 0.0.0.0:5432 ... users:(("nc",...))
```

Conclusion: the TCP test was reaching a temporary listener, not PostgreSQL.

### Phase 2 — PostgreSQL installation

The DB VM did not have PostgreSQL installed. PostgreSQL 14 and postgresql-contrib were installed and the service was enabled.

### Phase 3 — Port correction

After installation, `pg_lsclusters` initially showed PostgreSQL 14 main online on port 5433. Port 5432 was still occupied by the temporary listener. After the listener was cleared and PostgreSQL was configured correctly, the cluster was confirmed online on port 5432.

### Phase 4 — Remote listening configuration

PostgreSQL initially listened only on:

```text
127.0.0.1:5432
```

The service was configured to accept remote TCP connections required by the Application subnet.

### Phase 5 — Authentication failure

The first password-authenticated connection failed:

```text
FATAL: password authentication failed for user "routewell_app"
```

An attempt to alter the password revealed:

```text
ERROR: role "routewell_app" does not exist
```

### Phase 6 — Database objects created

The missing role was created, followed by the database:

```text
CREATE ROLE
CREATE DATABASE
```

The database was created with `routewell_app` as its owner.

### Phase 7 — Credential correction

The password was explicitly reset. The final authenticated test succeeded:

```text
current_user  | current_database
---------------+------------------
routewell_app | routewell_db
```

## 5. Root Cause

The root cause was incomplete Database VM configuration. VM provisioning created the compute resource, but PostgreSQL installation, service configuration, database object creation and credential configuration had not yet been completed.

A secondary diagnostic complication was the temporary `nc` listener on port 5432, which made a basic TCP connectivity test appear successful before PostgreSQL itself was operational.

## 6. Corrective Actions

- Installed PostgreSQL 14.
- Cleared the temporary port 5432 listener.
- Ensured PostgreSQL cluster `14/main` was online on port 5432.
- Configured PostgreSQL to accept connections from the Application subnet.
- Added the required `pg_hba.conf` authentication rule.
- Created `routewell_app`.
- Created `routewell_db` owned by `routewell_app`.
- Reset the database password.
- Validated authenticated PostgreSQL access.
- Validated Application-to-Database TCP connectivity.
- Validated Web-to-Database denial through Azure Network Watcher.

## 7. Final Validation

The incident was considered resolved when all of the following were true:

- PostgreSQL cluster online on 5432.
- PostgreSQL listening on the DB VM network interface.
- App VM successfully reaches DB VM on 5432.
- Web VM traffic to DB VM is denied.
- `routewell_app` exists.
- `routewell_db` exists and is owned by `routewell_app`.
- Authenticated query returns `routewell_app` and `routewell_db`.

## 8. Lessons Learned

1. Validate the service owner of a listening port, not only the port itself.
2. Separate network reachability tests from service-level tests.
3. Separate service availability from authentication validation.
4. Define an acceptance checklist early so troubleshooting stops once requirements are demonstrably satisfied.
5. Avoid exposing database passwords in screenshots, shell history or committed documentation.

## 9. Preventive Actions

- Add automated service-owner checks to future validation scripts.
- Include PostgreSQL installation and database initialization as explicit provisioning steps.
- Add an idempotent database initialization script that checks whether the role and database already exist.
- Use secure secret management for production credentials.
- Capture validation evidence immediately after each major milestone.

## 10. Final Status

**RESOLVED**

The PostgreSQL provisioning and connectivity incident was resolved. The RouteWell infrastructure milestone subsequently passed final validation.
