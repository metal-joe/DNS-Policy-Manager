# DNS-GUI

*🇬🇧 English · [🇩🇪 Deutsch](README.md)*

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
- **Bulk import** from CSV — create many policies at once (e.g. a whole set of VLANs). Comma- and semicolon-delimited files are both detected; invalid rows are skipped and reported in a summary. Optional preview and a built-in template.
- **Edit** an existing policy: target IP, processing order, rename.
- **Enable / disable** and **delete** policies, with confirmation dialogs.
- **Replicate to other DCs** — manually chosen target DCs.
- **Replicate to all DCs** — discovers every DC in the domain automatically (excluding the source) and clones the unit there (policies do *not* replicate on their own).
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

1. Enter one or more DCs (comma-separated) and the DNS zone, then **Laden** (Load).
2. Browse the three tabs: policies, client subnets, zone scopes & records.
3. Use the action bar to create, edit, toggle, delete or replicate policies, or export a report.

Write actions apply to the **first DC** in the list. See [`CHANGELOG.md`](CHANGELOG.md) for the version history.

### Bulk import via CSV

**Export sample CSV** writes a template to fill in. Format:

```csv
Servername,Subnetz,ZielBeinIP,SubnetzName,ScopeName,PolicyName
srv-app,192.168.30.0/24,192.168.20.14,,,
srv-app,192.168.31.0/24,192.168.20.14,,,
```

`Servername`, `Subnetz` (CIDR) and `ZielBeinIP` are required. The three name columns are optional — left blank, names are auto-generated. Comma or semicolon delimiters are both accepted. On import you choose whether to write to the first DC or all DCs; an (optional) preview lists everything before writing.

> Column headers are German (matching the UI): `Servername`, `Subnetz`, `ZielBeinIP`, `SubnetzName`, `ScopeName`, `PolicyName`. Header matching is case-insensitive and also accepts a few aliases (e.g. `Server`, `Subnet`, `CIDR`).

## Key concepts (and gotchas)

- **Zone scopes + A records replicate** via AD integration to all DCs.
- **Client subnets and policies do NOT replicate** — they are local DNS server configuration and must exist on every DC that clients query. That is what *Replicate to other DCs* is for.
- The **source IP as it arrives at the DC** decides whether a policy matches. If NAT sits between client and DC (e.g. a WLAN controller or a routing firewall interface), the arriving IP may differ from the client's local IP — bind the policy's client subnet to the address that actually arrives.
- Multi-NIC DCs: multiple IPs on the same physical DC share one DNS service — one policy there covers requests via any of its interfaces. Separate DCs each need their own copy.

## Verifying a policy actually works

A policy can look correct in the GUI and still not take effect — usually because the request reaches the DC with a different source IP (NAT), or because the client asked a DC that doesn't have the policy. Verify on both sides.

### On the DC

Confirm the policy, its client subnet and the scope record are present and enabled:

```powershell
# Policy exists and is enabled?
Get-DnsServerQueryResolutionPolicy -ZoneName "example.local" -Name "Pol-VLAN10-srv-app" |
  Format-List Name, ProcessingOrder, IsEnabled, Action, Criteria, Content

# Client subnet has the expected CIDR?
Get-DnsServerClientSubnet -Name "Subnet-VLAN10"

# Scope contains only the intended (reachable) leg?
Get-DnsServerResourceRecord -ZoneName "example.local" -ZoneScope "Scope-Bein20" -RRType A
```

If you run several DCs, repeat this on each one — policies and client subnets do **not** replicate (see *Key concepts*). The GUI's multi-DC view makes the gaps obvious: a policy showing on one DC but not another means that DC still needs it.

### From a client in the target segment (the real test)

This is the test that matters, because it proves the policy fires for the source IP that actually arrives at the DC. Run it on a client **inside the VLAN/segment the policy is meant for**:

```powershell
# Clear any cached answer first
ipconfig /flushdns

# Ask the DC directly and check which IP comes back
Resolve-DnsName srv-app.example.local -Server 192.168.20.15 -Type A
```

Expected result: **only the single leg** reachable from that segment — not the full list of all legs. If you still get every IP, the policy isn't matching for this client.

Quick reachability check for the returned IP (should succeed from this segment):

```powershell
Test-NetConnection -ComputerName 192.168.20.14 -Port 445   # 445 = SMB; use the port your service needs
```

### If the client still gets all IPs

- **Wrong DC asked.** The client queried a DC without this policy. Confirm which DNS server it uses (`Get-DnsClientServerAddress`) and make sure the policy exists there.
- **NAT in the path.** The request reaches the DC with a translated source IP (common with WLAN controllers or routing firewalls), so it doesn't match the client subnet. Find the IP that actually arrives and bind the policy to that:
  ```powershell
  # On the DC: briefly enable DNS debug logging, run one lookup from the client, then check the source IP
  Set-DnsServerDiagnostics -EnableLoggingToFile $true -LogFilePath "C:\Temp\dnsdebug.log" `
    -Queries $true -Answers $true -ReceivePackets $true -UdpPackets $true -TcpPackets $true -SendPackets $true
  # ... trigger one lookup on the client (ipconfig /flushdns; Resolve-DnsName ...) ...
  Select-String -Path "C:\Temp\dnsdebug.log" -Pattern "srv-app" | Select-Object -Last 5
  Set-DnsServerDiagnostics -EnableLoggingToFile $false   # turn it off again
  ```
  The source IP shown in the matching log line is the address the policy's client subnet must contain.
- **Stale cache.** Run `ipconfig /flushdns` on the client and retry.

## Safety

This tool writes to production DNS. Recommended: try each action once against a **throwaway test policy** (create → edit → replicate to one DC → delete) and verify with *Load* before using it on real segments. As with any DNS change: do one, verify, then roll out.

All values shown in examples (`example.local`, `srv-app`, `192.168.10.0/24`, …) are placeholders — replace them with your own.

## License

MIT — see [`LICENSE`](LICENSE).

## Disclaimer

Provided as-is, without warranty. You are responsible for testing in your own environment before production use. Not affiliated with or endorsed by Microsoft.
