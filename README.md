# DNS-GUI

*🇩🇪 Deutsch · [🇬🇧 English](README.en.md)*

Ein grafisches Verwaltungswerkzeug für **DNS Query Resolution Policies** des Windows-DNS-Servers, geschrieben in PowerShell + WPF.

Der mitgelieferte Windows-DNS-Manager (`dnsmgmt.msc`) kann DNS-Policies weder anzeigen noch bearbeiten. Wer Policies einsetzt — etwa um Clients in verschiedenen Subnetzen unterschiedliche Antworten für denselben Hostnamen zu geben — ist sonst auf reine PowerShell-Befehle angewiesen. **DNS-GUI** bringt diese Verwaltung in eine bedienbare grafische Oberfläche.

> Die Oberfläche ist auf Deutsch. Code und Kommentare sind so gehalten, dass sich das Tool leicht anpassen lässt.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1-blue) ![Platform](https://img.shields.io/badge/platform-Windows%20Server-lightgrey) ![License](https://img.shields.io/badge/license-MIT-green)

---

## Wozu das Ganze

Ein häufiges Szenario: Ein **multi-homed Server** (eine IP je Netzsegment) ist im DNS mit mehreren A-Records unter demselben Namen registriert. Clients bekommen *alle* diese IPs und versuchen unter Umständen, eine Adresse anzusprechen, die aus ihrem Segment gar nicht erreichbar ist — das führt zu Zeitüberschreitungen (z. B. hängt der Druckdialog bei „Verbindung wird hergestellt").

DNS Query Resolution Policies lösen das: Jedes Client-Subnetz erhält nur die für es erreichbare IP. Die dafür nötigen Bausteine (Client-Subnetze, Zone-Scopes, Query Resolution Policies) sind im DNS-Manager aber unsichtbar und von Hand mühsam zu pflegen. Dieses Tool macht das praktikabel.

## Funktionen

- **Anzeigen** aller Query Resolution Policies, Client-Subnetze und Zone-Scopes — auch über mehrere DCs gleichzeitig.
- **Anlegen** einer kompletten Policy in einem Schritt per Assistent (Client-Subnetz + Zone-Scope + A-Record + Policy).
- **Bulk-Import** aus CSV — viele Policies auf einmal anlegen (z. B. ein ganzes Set an VLANs). Komma- und semikolongetrennte Dateien werden erkannt; ungültige Zeilen werden übersprungen und in einer Bilanz gemeldet. Mit abschaltbarer Vorschau und mitgelieferter Vorlage.
- **Bearbeiten** einer bestehenden Policy: Ziel-IP, Verarbeitungsreihenfolge, Umbenennen.
- **Aktivieren / Deaktivieren** und **Löschen** von Policies, jeweils mit Sicherheitsabfrage.
- **Auf weitere DCs übertragen** — manuell gewählte Ziel-DCs.
- **Auf alle DCs übertragen** — ermittelt alle DCs der Domäne automatisch (Quell-DC ausgenommen) und klont die Einheit dorthin (Policies replizieren nicht von selbst).
- **Export** des aktuellen Stands als Textreport (Konfigurationsnachweis).
- Dunkle, moderne Oberfläche.

## Voraussetzungen

- **Windows PowerShell 5.1** (das Skript vermeidet PS7-spezifische sowie `??`-/ternäre Syntax für maximale Kompatibilität; das `DnsServer`-Modul läuft unter 5.1 am zuverlässigsten).
- Das PowerShell-Modul **`DnsServer`** — auf einem Domänencontroller vorhanden, sonst per RSAT nachinstallieren:
  ```powershell
  Add-WindowsCapability -Online -Name 'Rsat.Dns.Tools~~~~0.0.1.0'
  ```
- Ausführung auf einem Domänencontroller (oder einer Maschine mit RSAT-DNS und Rechten am Ziel-DC).

## Verwendung

```powershell
powershell -ExecutionPolicy Bypass -File .\DNS-GUI.ps1
```

1. Einen oder mehrere DCs (durch Komma getrennt) und die DNS-Zone eingeben, dann **Laden**.
2. Die drei Reiter durchsehen: Policies, Client-Subnetze, Zone-Scopes & Records.
3. Über die Aktionsleiste Policies anlegen, bearbeiten, umschalten, löschen oder übertragen — oder einen Report exportieren.

Schreibende Aktionen wirken auf den **ersten DC** in der Liste. Den Versionsverlauf findest du in [`CHANGELOG.md`](CHANGELOG.md).

### Bulk-Import per CSV

Über **CSV-Vorlage** schreibt das Tool eine Beispieldatei zum Ausfüllen. Format:

```csv
Servername,Subnetz,ZielBeinIP,SubnetzName,ScopeName,PolicyName
srv-app,192.168.30.0/24,192.168.20.14,,,
srv-app,192.168.31.0/24,192.168.20.14,,,
```

Pflichtspalten sind `Servername`, `Subnetz` (CIDR) und `ZielBeinIP`. Die drei Namensspalten sind optional — bleiben sie leer, werden die Namen automatisch erzeugt. Komma oder Semikolon als Trennzeichen werden beide akzeptiert. Beim Import wählst du, ob auf den ersten DC oder auf alle DCs geschrieben wird; eine (abschaltbare) Vorschau zeigt alles vor dem Schreiben.

## Wichtige Konzepte (und Stolpersteine)

- **Zone-Scopes + A-Records replizieren** über die AD-Integration auf alle DCs.
- **Client-Subnetze und Policies replizieren NICHT** — sie sind lokale Konfiguration des jeweiligen DNS-Servers und müssen auf jedem DC vorhanden sein, den Clients abfragen. Genau dafür gibt es *Auf weitere DCs übertragen*.
- Maßgeblich ist die **Quell-IP, mit der die Anfrage am DC ankommt**. Liegt NAT zwischen Client und DC (z. B. ein WLAN-Controller oder ein routendes Firewall-Interface), kann die ankommende IP von der lokalen Client-IP abweichen — dann muss das Client-Subnetz der Policy auf die tatsächlich ankommende Adresse zeigen.
- Multi-NIC-DCs: Mehrere IPs auf demselben physischen DC teilen sich einen DNS-Dienst — eine Policy dort gilt für Anfragen über jedes seiner Interfaces. Separate DCs brauchen jeweils eine eigene Kopie.

## Prüfen, ob eine Policy wirklich greift

Eine Policy kann in der GUI korrekt aussehen und trotzdem nicht wirken — meist, weil die Anfrage mit einer anderen Quell-IP am DC ankommt (NAT) oder weil der Client einen DC ohne die Policy gefragt hat. Daher auf beiden Seiten prüfen.

### Auf dem DC

Bestätigen, dass Policy, Client-Subnetz und Scope-Record vorhanden und aktiviert sind:

```powershell
# Policy vorhanden und aktiviert?
Get-DnsServerQueryResolutionPolicy -ZoneName "example.local" -Name "Pol-VLAN10-srv-app" |
  Format-List Name, ProcessingOrder, IsEnabled, Action, Criteria, Content

# Client-Subnetz mit dem erwarteten CIDR?
Get-DnsServerClientSubnet -Name "Subnet-VLAN10"

# Scope enthält nur das gewünschte (erreichbare) Bein?
Get-DnsServerResourceRecord -ZoneName "example.local" -ZoneScope "Scope-Bein20" -RRType A
```

Bei mehreren DCs auf jedem wiederholen — Policies und Client-Subnetze replizieren **nicht** (siehe *Wichtige Konzepte*). Die Mehr-DC-Ansicht des Tools macht Lücken sichtbar: Erscheint eine Policy auf einem DC, auf einem anderen aber nicht, fehlt sie dort noch.

### Von einem Client im Zielsegment (der eigentliche Test)

Das ist der entscheidende Test, denn er beweist, dass die Policy für die Quell-IP greift, die tatsächlich am DC ankommt. Auf einem Client **innerhalb des VLANs/Segments ausführen, für das die Policy gedacht ist**:

```powershell
# Zuerst zwischengespeicherte Antwort verwerfen
ipconfig /flushdns

# Den DC direkt fragen und prüfen, welche IP zurückkommt
Resolve-DnsName srv-app.example.local -Server 192.168.20.15 -Type A
```

Erwartetes Ergebnis: **nur das eine** aus diesem Segment erreichbare Bein — nicht die vollständige Liste aller Beine. Kommen weiterhin alle IPs zurück, greift die Policy für diesen Client nicht.

Schnelle Erreichbarkeitsprobe für die zurückgegebene IP (sollte aus diesem Segment klappen):

```powershell
Test-NetConnection -ComputerName 192.168.20.14 -Port 445   # 445 = SMB; den Port nehmen, den der Dienst braucht
```

### Wenn der Client weiterhin alle IPs bekommt

- **Falscher DC gefragt.** Der Client hat einen DC ohne diese Policy abgefragt. Prüfen, welchen DNS-Server er nutzt (`Get-DnsClientServerAddress`), und sicherstellen, dass die Policy dort existiert.
- **NAT im Pfad.** Die Anfrage kommt mit einer übersetzten Quell-IP am DC an (häufig bei WLAN-Controllern oder routenden Firewalls) und passt deshalb nicht aufs Client-Subnetz. Die tatsächlich ankommende IP ermitteln und die Policy darauf binden:
  ```powershell
  # Auf dem DC: kurz DNS-Debug-Logging aktivieren, eine Auflösung vom Client auslösen, dann Quell-IP prüfen
  Set-DnsServerDiagnostics -EnableLoggingToFile $true -LogFilePath "C:\Temp\dnsdebug.log" `
    -Queries $true -Answers $true -ReceivePackets $true -UdpPackets $true -TcpPackets $true -SendPackets $true
  # ... auf dem Client eine Auflösung auslösen (ipconfig /flushdns; Resolve-DnsName ...) ...
  Select-String -Path "C:\Temp\dnsdebug.log" -Pattern "srv-app" | Select-Object -Last 5
  Set-DnsServerDiagnostics -EnableLoggingToFile $false   # danach wieder ausschalten
  ```
  Die in der passenden Log-Zeile gezeigte Quell-IP ist die Adresse, die das Client-Subnetz der Policy enthalten muss.
- **Veralteter Cache.** Auf dem Client `ipconfig /flushdns` ausführen und erneut testen.

## Sicherheit

Das Tool schreibt in produktives DNS. Empfehlung: Jede Aktion einmal mit einer **unkritischen Test-Policy** durchspielen (Anlegen → Bearbeiten → auf einen DC übertragen → Löschen) und mit *Laden* prüfen, bevor sie auf echte Segmente angewandt wird. Grundsatz wie bei jeder DNS-Änderung: erst eine, verifizieren, dann ausrollen.

Alle in Beispielen gezeigten Werte (`example.local`, `srv-app`, `192.168.10.0/24`, …) sind Platzhalter — durch eigene ersetzen.

## Lizenz

MIT — siehe [`LICENSE`](LICENSE).

## Haftungsausschluss

Bereitgestellt „wie besehen", ohne Gewähr. Die Verantwortung für das Testen in der eigenen Umgebung vor dem Produktiveinsatz liegt bei dir. Nicht mit Microsoft verbunden oder von Microsoft unterstützt.
