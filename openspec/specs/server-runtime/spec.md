# server-runtime Specification

## Purpose

Provide a reproducible MyGO server that operators can configure, provision, migrate, start, and stop without losing forum data.

## Requirements

### Requirement: Reproducible MyGO build
The backend SHALL implement domain and application behavior in MyGO and provide documented generation, build, and test commands using the local MyGO compiler. Generated Go SHALL be reproducible from source, and handwritten Go SHALL be limited to necessary infrastructure adapters.

#### Scenario: Build from a clean checkout
- **WHEN** a developer follows the documented commands with the declared toolchain and dependencies
- **THEN** the MyGO sources generate successfully and the server builds without manually editing generated files

### Requirement: Explicit configuration and provisioning
The server SHALL load configured site identities, canonical HTTPS origins, database connection settings, and runtime limits. Operators SHALL be able to provision sites, site administrator accounts, and explicitly scoped deployment superadministrator assignments. Invalid or conflicting site configuration SHALL fail before serving traffic, without logging credentials or private keys.

#### Scenario: Conflicting domains
- **WHEN** two configured sites claim the same normalized routing domain
- **THEN** startup fails with an actionable configuration error

#### Scenario: Provision an initial administrator
- **WHEN** an operator provisions an administrator for a configured site
- **THEN** the account authenticates only at that site and receives only that site's administrative permissions

#### Scenario: Provision explicit superadministrator authority
- **WHEN** an operator explicitly grants a deployment superadministrator role to an authenticated administrative identity
- **THEN** deployment-wide administration is available through that role without sharing ordinary account authentication across sites

### Requirement: Non-destructive migrations and startup
Schema changes SHALL run through explicit versioned migrations. Normal startup SHALL NOT clear tables, seed demo content, or implicitly recreate accounts. The server SHALL refuse an incompatible schema with an actionable error.

#### Scenario: Restart with existing data
- **WHEN** the server restarts against a compatible populated database
- **THEN** existing accounts, posts, subscriptions, and queued deliveries remain intact

### Requirement: Observable lifecycle
The server SHALL expose liveness and readiness checks, bounded HTTP handling, graceful shutdown, and structured operational events for failed reception and delivery. Readiness SHALL reflect database availability and schema compatibility, and operational logs SHALL omit authentication secrets, private keys, and local-only or member-readable content bodies. Elevated management events SHALL retain acting identity and scope in access-controlled audit records.

#### Scenario: Shutdown during delivery
- **WHEN** an operator stops the server while a delivery is in progress
- **THEN** the server stops accepting new work and unfinished delivery remains recoverable after restart

