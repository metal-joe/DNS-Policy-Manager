# DNS-GUI

A graphical management tool for **Windows DNS Server Query Resolution Policies**, written in PowerShell + WPF.

The built-in Windows DNS Manager (`dnsmgmt.msc`) cannot display or edit DNS policies at all. If you use DNS policies — for example to give clients in different subnets different answers for the same hostname — you are otherwise limited to raw PowerShell commands. **DNS-GUI** brings that management into a usable graphical interface.

> The user interface is in German. The code, comments and this documentation are structured so that the tool is easy to adapt.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1-blue) ![Platform](https://img.shields.io/badge/platform-Windows%20Server-lightgrey) ![License](https://img.shields.io/badge/license-MIT-green)

---

## Why this exists

A common scenario: a **multi-homed server** (one IP per network segment) is registered in DNS with several A records under the same name. Clients receive *all* of those IPs and may try to connect to one that is not reachable from their segment, causing timeouts (e.g. printing hangs at "connecting").

DNS Query Resolution Policies solve this: each client subnet is answered with only the IP reachable from it. But the policy machinery (client subnets, zone scopes, query resolution policies) is invisible in the DNS Manager and tedious to manage by hand. This tool makes it practical.

## Features

- **View** all query resolution policies, client subnets and zone scopes — across multiple DCs at once.
- **Create** a complete policy in one step via a wizard (client subnet + zone scope + A record + policy).
- **Edit** an existing policy: target IP, processing order, rename.
- **Enable / disable** and **delete** policies, with confirmation dialogs.
- **Replicate to other DCs** — clones a complete policy unit to additional DCs (policies do *not* replicate on their own).
- **Export** the current state as a text report (configuration record).
- Dark, modern UI.

## Requirements

- **Windows PowerShell 5.1** (the script avoids PS7-only and `??`/ternary syntax for maximum compatibility; the `DnsServer` module is most reliable under 5.1).
- The **`DnsServer`** PowerShell module — present on a Domain Controller, otherwise install RSAT:
  ```powershell
  Add-WindowsCapability -Online -Name 'Rsat.Dns.Tools~~~~0.0.1.0'
  ```
- Run on a Domain Controller (or a machine with RSAT-DNS and rights to the target DC).

## Usage

```powershell
powershell -ExecutionPolicy Bypass -File .\DNS-GUI.ps1
```

<img width="1217" height="728" alt="dns-policy-manager" src="https://github.com/user-attachments/assets/1a344ea4-74b4-4b2c-97cc-ed2500d62ae1" />

1. Enter one or more DCs (comma-separated) and the DNS zone, then **Laden** (Load).
2. Browse the three tabs: policies, client subnets, zone scopes & records.
3. Use the action bar to create, edit, toggle, delete or replicate policies, or export a report.

Write actions apply to the **first DC** in the list. See [`CHANGELOG.md`](CHANGELOG.md) for the version history.

## Key concepts (and gotchas)

- **Zone scopes + A records replicate** via AD integration to all DCs.
- **Client subnets and policies do NOT replicate** — they are local DNS server configuration and must exist on every DC that clients query. That is what *Replicate to other DCs* is for.
- The **source IP as it arrives at the DC** decides whether a policy matches. If NAT sits between client and DC (e.g. a WLAN controller or a routing firewall interface), the arriving IP may differ from the client's local IP — bind the policy's client subnet to the address that actually arrives.
- Multi-NIC DCs: multiple IPs on the same physical DC share one DNS service — one policy there covers requests via any of its interfaces. Separate DCs each need their own copy.

## Safety

This tool writes to production DNS. Recommended: try each action once against a **throwaway test policy** (create → edit → replicate to one DC → delete) and verify with *Load* before using it on real segments. As with any DNS change: do one, verify, then roll out.

All values shown in examples (`example.local`, `srv-app`, `192.168.10.0/24`, …) are placeholders — replace them with your own.

## License

MIT — see [`LICENSE`](LICENSE).

## Disclaimer

Provided as-is, without warranty. You are responsible for testing in your own environment before production use. Not affiliated with or endorsed by Microsoft.
