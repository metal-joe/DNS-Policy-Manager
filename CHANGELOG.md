# Changelog

All notable changes to this project. Format based on [Keep a Changelog](https://keepachangelog.com).
Newest version first.

## [1.4] - 2026-06-11
### Changed
- Modernized UI: dark theme with rounded corners, hover effects on buttons and
  table rows, more whitespace, blue accent color. Functionality unchanged.

## [1.3] - 2026-06-11
### Added
- "Edit policy": change a policy's target IP, processing order and name.
  Renaming is done by recreating under the new name and removing the old one
  (DNS policies cannot be renamed directly). Subnet and FQDN conditions are
  intentionally locked to avoid side effects on other policies.

## [1.2] - 2026-06-10
### Added
- "Replicate to other DCs": clones a complete policy unit
  (client subnet + zone scope + A record(s) + policy) idempotently to one or
  more target DCs. Compensates for the fact that policies and subnets do not
  replicate automatically. Source DC is excluded; an error on one target DC
  does not stop the others.
### Fixed
- Auto-naming aligned to a third-octet convention
  (`Subnet-VLAN10`, `Scope-Bein20`) instead of the leg IP's last octet.

## [1.1] - 2026-06-10
### Added
- Grew from a read-only dashboard into a full manager.
- "New policy" wizard: creates client subnet, zone scope, A record and policy
  in one step. Input validation (CIDR, IPv4), confirmation, reuse of existing
  subnets/scopes.
- Enable/disable and delete actions, each with a confirmation dialog. Deleting
  a policy keeps its subnet and scope.
### Fixed
- Clean record display: only A/AAAA/CNAME records are shown; the technical
  NS/SOA entries of each scope are hidden (affects display and export).

## [1.0] - 2026-06-10
### Added
- First version: read-only dashboard.
- Displays query resolution policies, client subnets and zone scopes, queries
  multiple DCs in one run, text export. Read-only.

## Planned
- Selectable naming scheme.
- Cross-DC consistency check (which DCs are missing a given policy).
- Built-in resolution simulation (test query per subnet).
