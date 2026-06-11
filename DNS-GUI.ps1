<#
.SYNOPSIS
    DNS Policy Manager - GUI fuer Windows DNS Query Resolution Policies.

.DESCRIPTION
    Verwaltet DNS Server Query Resolution Policies ueber eine grafische
    Oberflaeche - gedacht vor allem fuer den Fall, dass ein multi-homed Server
    (mehrere A-Records, ein Bein je Segment) je nach Quell-Subnetz nur das
    erreichbare Bein zurueckgeben soll.

    Kann mehrere DCs gleichzeitig abfragen (Policies replizieren nicht, daher
    ist der Vergleich ueber DCs hinweg wichtig), Policies/Subnetze/Scopes
    anzeigen, neue Policies assistiert anlegen, bestehende bearbeiten,
    aktivieren/deaktivieren, loeschen, auf weitere DCs uebertragen und den
    Stand als Textreport exportieren. Schreibende Aktionen laufen ueber
    Bestaetigungsdialoge und werden in der Statusleiste protokolliert.

.NOTES
    Benoetigt das Modul "DnsServer" (auf einem DC vorhanden, sonst RSAT-DNS)
    und DNS-Admin-Rechte auf dem Ziel-DC. Getestet unter Windows PowerShell 5.1.
#>

#Requires -Version 5.1

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

if (-not (Get-Module -ListAvailable -Name DnsServer)) {
    [System.Windows.MessageBox]::Show(
        "Das PowerShell-Modul 'DnsServer' ist nicht verfuegbar.`n`n" +
        "Bitte auf einem DC ausfuehren oder RSAT-DNS-Tools installieren:`n" +
        "Add-WindowsCapability -Online -Name 'Rsat.Dns.Tools~~~~0.0.1.0'",
        "DNS Policy Manager - Fehler", "OK", "Error") | Out-Null
    return
}
Import-Module DnsServer -ErrorAction SilentlyContinue

# --- Hauptfenster ---
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="DNS Policy Manager" Height="780" Width="1240"
        WindowStartupLocation="CenterScreen" Background="#1A1A1C"
        FontFamily="Segoe UI" UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
    <Window.Resources>
        <!-- Farbpalette (Dark) -->
        <SolidColorBrush x:Key="BgBase"      Color="#1A1A1C"/>
        <SolidColorBrush x:Key="BgPanel"     Color="#242427"/>
        <SolidColorBrush x:Key="BgElevated"  Color="#2D2D31"/>
        <SolidColorBrush x:Key="BgInput"     Color="#1F1F22"/>
        <SolidColorBrush x:Key="Stroke"      Color="#3A3A3F"/>
        <SolidColorBrush x:Key="TextPrimary" Color="#F2F2F3"/>
        <SolidColorBrush x:Key="TextMuted"   Color="#9A9AA2"/>
        <SolidColorBrush x:Key="Accent"      Color="#3B82F6"/>
        <SolidColorBrush x:Key="AccentHover" Color="#60A5FA"/>
        <SolidColorBrush x:Key="RowAlt"      Color="#202023"/>
        <SolidColorBrush x:Key="SelRow"      Color="#1E3A52"/>

        <!-- Primaer-Button mit Hover -->
        <Style x:Key="PrimaryButton" TargetType="Button">
            <Setter Property="Background" Value="{StaticResource Accent}"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Padding" Value="16,9"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Margin" Value="0,0,8,0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="b" Property="Background" Value="{StaticResource AccentHover}"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="b" Property="Opacity" Value="0.85"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Sekundaer-Button (gedeckt) -->
        <Style x:Key="GreyButton" TargetType="Button" BasedOn="{StaticResource PrimaryButton}">
            <Setter Property="Background" Value="{StaticResource BgElevated}"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimary}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="8"
                                BorderBrush="{StaticResource Stroke}" BorderThickness="1" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="b" Property="Background" Value="#383840"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="b" Property="Opacity" Value="0.85"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- TextBox modern -->
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="{StaticResource BgInput}"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimary}"/>
            <Setter Property="CaretBrush" Value="{StaticResource TextPrimary}"/>
            <Setter Property="BorderBrush" Value="{StaticResource Stroke}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="6"
                                BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                            <ScrollViewer x:Name="PART_ContentHost" Margin="8,0" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter TargetName="b" Property="BorderBrush" Value="{StaticResource Accent}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Foreground" Value="{StaticResource TextMuted}"/>
                                <Setter TargetName="b" Property="Background" Value="#202023"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Labels -->
        <Style x:Key="FieldLabel" TargetType="TextBlock">
            <Setter Property="Foreground" Value="{StaticResource TextMuted}"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
        </Style>

        <!-- DataGrid modern -->
        <Style TargetType="DataGrid">
            <Setter Property="AutoGenerateColumns" Value="False"/>
            <Setter Property="IsReadOnly" Value="True"/>
            <Setter Property="HeadersVisibility" Value="Column"/>
            <Setter Property="GridLinesVisibility" Value="None"/>
            <Setter Property="BorderBrush" Value="{StaticResource Stroke}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="RowBackground" Value="{StaticResource BgPanel}"/>
            <Setter Property="AlternatingRowBackground" Value="{StaticResource RowAlt}"/>
            <Setter Property="Background" Value="{StaticResource BgPanel}"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimary}"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="RowHeight" Value="36"/>
            <Setter Property="SelectionMode" Value="Single"/>
            <Setter Property="VerticalGridLinesBrush" Value="Transparent"/>
            <Setter Property="HorizontalGridLinesBrush" Value="#2E2E33"/>
        </Style>
        <Style TargetType="DataGridColumnHeader">
            <Setter Property="Background" Value="{StaticResource BgBase}"/>
            <Setter Property="Foreground" Value="{StaticResource TextMuted}"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="FontSize" Value="11.5"/>
            <Setter Property="Padding" Value="12,10"/>
            <Setter Property="BorderThickness" Value="0,0,0,1"/>
            <Setter Property="BorderBrush" Value="{StaticResource Stroke}"/>
        </Style>
        <Style TargetType="DataGridRow">
            <Setter Property="Foreground" Value="{StaticResource TextPrimary}"/>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="{StaticResource SelRow}"/>
                </Trigger>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#2A2A2E"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style TargetType="DataGridCell">
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="12,0"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="DataGridCell">
                        <Border Background="Transparent" Padding="{TemplateBinding Padding}" VerticalAlignment="Stretch">
                            <ContentPresenter VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- TabControl / TabItem modern -->
        <Style TargetType="TabControl">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
        </Style>
        <Style TargetType="TabItem">
            <Setter Property="Foreground" Value="{StaticResource TextMuted}"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border x:Name="b" Background="Transparent" Padding="16,9" Margin="0,0,4,0" CornerRadius="8,8,0,0">
                            <ContentPresenter ContentSource="Header" HorizontalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="b" Property="Background" Value="{StaticResource BgPanel}"/>
                                <Setter Property="Foreground" Value="{StaticResource TextPrimary}"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Foreground" Value="{StaticResource TextPrimary}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Kopf -->
        <Border Grid.Row="0" Background="{StaticResource BgBase}" Padding="24,18">
            <StackPanel Orientation="Horizontal">
                <Border Width="4" Background="{StaticResource Accent}" CornerRadius="2" Margin="0,0,16,0"/>
                <StackPanel VerticalAlignment="Center">
                    <TextBlock Text="DNS Policy Manager" Foreground="{StaticResource TextPrimary}" FontSize="22" FontWeight="Bold"/>
                    <TextBlock Text="GUI fuer Windows DNS Query Resolution Policies  ·  Ansehen &amp; Bearbeiten"
                               Foreground="{StaticResource TextMuted}" FontSize="12.5" Margin="0,2,0,0"/>
                </StackPanel>
            </StackPanel>
        </Border>

        <!-- Steuerleiste -->
        <Border Grid.Row="1" Background="{StaticResource BgPanel}" Padding="24,16" BorderBrush="{StaticResource Stroke}" BorderThickness="0,0,0,1">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                <TextBlock Text="DC(s)" Style="{StaticResource FieldLabel}" Margin="0,0,10,0"/>
                <TextBox x:Name="TxtDCs" Width="340" Height="34" Padding="6,0"
                         ToolTip="Ein oder mehrere DCs, durch Komma getrennt. Schreibaktionen wirken auf den ersten/Ziel-DC."/>
                <TextBlock Text="Zone" Style="{StaticResource FieldLabel}" Margin="18,0,10,0"/>
                <TextBox x:Name="TxtZone" Width="180" Height="34" Padding="6,0" Text="example.local"/>
                <Button x:Name="BtnLoad" Content="Laden" Style="{StaticResource PrimaryButton}" Margin="18,0,0,0"/>
                <Button x:Name="BtnExport" Content="Export" Style="{StaticResource GreyButton}"/>
            </StackPanel>
        </Border>

        <!-- Tabs -->
        <TabControl Grid.Row="2" Margin="24,16,24,8" Background="Transparent" BorderThickness="0">
            <TabItem Header="Query Resolution Policies">
                <Border Background="{StaticResource BgPanel}" CornerRadius="0,10,10,10">
                <DataGrid x:Name="GridPolicies" Margin="0">
                    <DataGrid.Columns>
                        <DataGridTextColumn Header="DC" Binding="{Binding DC}" Width="140"/>
                        <DataGridTextColumn Header="Policy-Name" Binding="{Binding Name}" Width="190"/>
                        <DataGridTextColumn Header="Reihenf." Binding="{Binding ProcessingOrder}" Width="75"/>
                        <DataGridTextColumn Header="Aktiv" Binding="{Binding Enabled}" Width="55"/>
                        <DataGridTextColumn Header="Aktion" Binding="{Binding Action}" Width="65"/>
                        <DataGridTextColumn Header="Subnetz" Binding="{Binding Subnet}" Width="180"/>
                        <DataGridTextColumn Header="FQDN" Binding="{Binding Fqdn}" Width="*"/>
                        <DataGridTextColumn Header="Ziel-Scope" Binding="{Binding ScopeName}" Width="130"/>
                    </DataGrid.Columns>
                </DataGrid>
                </Border>
            </TabItem>
            <TabItem Header="Client-Subnetze">
                <Border Background="{StaticResource BgPanel}" CornerRadius="0,10,10,10">
                <DataGrid x:Name="GridSubnets" Margin="0">
                    <DataGrid.Columns>
                        <DataGridTextColumn Header="DC" Binding="{Binding DC}" Width="140"/>
                        <DataGridTextColumn Header="Name" Binding="{Binding Name}" Width="220"/>
                        <DataGridTextColumn Header="IPv4-Subnetz(e)" Binding="{Binding IPv4}" Width="*"/>
                        <DataGridTextColumn Header="IPv6-Subnetz(e)" Binding="{Binding IPv6}" Width="240"/>
                    </DataGrid.Columns>
                </DataGrid>
                </Border>
            </TabItem>
            <TabItem Header="Zone-Scopes &amp; A-Records">
                <Border Background="{StaticResource BgPanel}" CornerRadius="0,10,10,10">
                <DataGrid x:Name="GridScopes" Margin="0">
                    <DataGrid.Columns>
                        <DataGridTextColumn Header="DC" Binding="{Binding DC}" Width="140"/>
                        <DataGridTextColumn Header="Zone" Binding="{Binding Zone}" Width="160"/>
                        <DataGridTextColumn Header="Scope" Binding="{Binding Scope}" Width="180"/>
                        <DataGridTextColumn Header="Record" Binding="{Binding Record}" Width="150"/>
                        <DataGridTextColumn Header="Typ" Binding="{Binding Type}" Width="60"/>
                        <DataGridTextColumn Header="Daten" Binding="{Binding Data}" Width="*"/>
                    </DataGrid.Columns>
                </DataGrid>
                </Border>
            </TabItem>
        </TabControl>

        <!-- Aktionsleiste (schreibend) -->
        <Border Grid.Row="3" Background="{StaticResource BgPanel}" Padding="24,14" BorderBrush="{StaticResource Stroke}" BorderThickness="0,1,0,1">
            <StackPanel Orientation="Horizontal">
                <Border Width="3" Background="{StaticResource Accent}" CornerRadius="2" Margin="0,2,12,2"/>
                <Button x:Name="BtnNew" Content="Neue Policy" Style="{StaticResource PrimaryButton}"/>
                <Button x:Name="BtnEdit" Content="Bearbeiten" Style="{StaticResource GreyButton}"/>
                <Button x:Name="BtnReplicate" Content="Auf weitere DCs uebertragen" Style="{StaticResource GreyButton}"/>
                <Button x:Name="BtnToggle" Content="Aktiv / Inaktiv" Style="{StaticResource GreyButton}"/>
                <Button x:Name="BtnDelete" Content="Loeschen" Style="{StaticResource GreyButton}"/>
            </StackPanel>
        </Border>

        <!-- Status -->
        <Border Grid.Row="4" Background="{StaticResource BgBase}" Padding="24,10">
            <TextBlock x:Name="TxtStatus" Text="Bereit. DC(s) eingeben und Laden klicken."
                       Foreground="{StaticResource TextMuted}" FontSize="12" TextWrapping="Wrap"/>
        </Border>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$TxtDCs      = $window.FindName("TxtDCs")
$TxtZone     = $window.FindName("TxtZone")
$BtnLoad     = $window.FindName("BtnLoad")
$BtnExport   = $window.FindName("BtnExport")
$BtnNew      = $window.FindName("BtnNew")
$BtnEdit     = $window.FindName("BtnEdit")
$BtnReplicate= $window.FindName("BtnReplicate")
$BtnToggle   = $window.FindName("BtnToggle")
$BtnDelete   = $window.FindName("BtnDelete")
$GridPolicies= $window.FindName("GridPolicies")
$GridSubnets = $window.FindName("GridSubnets")
$GridScopes  = $window.FindName("GridScopes")
$TxtStatus   = $window.FindName("TxtStatus")

$TxtDCs.Text = $env:COMPUTERNAME

$script:dataPolicies = @()
$script:dataSubnets  = @()
$script:dataScopes   = @()

function Set-Status([string]$msg) {
    $TxtStatus.Text = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg
}

function Get-TargetDC {
    $dcInput = $TxtDCs.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($dcInput)) { return $env:COMPUTERNAME }
    return (($dcInput -split '[,;]')[0]).Trim()
}

function Get-CriteriaValue {
    param($Policy, [string]$Type)
    try {
        $c = $Policy.Criteria | Where-Object { $_.CriteriaType -eq $Type }
        if ($c) { return ($c.Criteria -join '; ') }
    } catch {}
    return ""
}

# Laedt Policies/Subnetze/Scopes von den angegebenen DCs
function Load-Data {
    $zone = $TxtZone.Text.Trim()
    $dcInput = $TxtDCs.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($dcInput)) { $dcInput = $env:COMPUTERNAME }
    $dcs = $dcInput -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }

    Set-Status "Lade von: $($dcs -join ', ') ..."
    $window.Dispatcher.Invoke([action]{}, "Render")

    $polList = New-Object System.Collections.ArrayList
    $subList = New-Object System.Collections.ArrayList
    $scpList = New-Object System.Collections.ArrayList
    $errors  = @()

    foreach ($dc in $dcs) {
        try {
            $policies = Get-DnsServerQueryResolutionPolicy -ComputerName $dc -ZoneName $zone -ErrorAction Stop
            foreach ($p in $policies) {
                $scopeName = ""
                try { $scopeName = ($p.Content | ForEach-Object { $_.ScopeName }) -join ', ' } catch {}
                [void]$polList.Add([PSCustomObject]@{
                    DC=$dc; Name=$p.Name; ProcessingOrder=$p.ProcessingOrder
                    Enabled= if ($p.IsEnabled) {"Ja"} else {"Nein"}
                    Action=$p.Action
                    Subnet=(Get-CriteriaValue $p 'ClientSubnet')
                    Fqdn=(Get-CriteriaValue $p 'Fqdn')
                    ScopeName=$scopeName })
            }
        } catch { $errors += "Policies @ $dc : $($_.Exception.Message)" }

        try {
            $subnets = Get-DnsServerClientSubnet -ComputerName $dc -ErrorAction Stop
            foreach ($s in $subnets) {
                [void]$subList.Add([PSCustomObject]@{
                    DC=$dc; Name=$s.Name
                    IPv4=($s.IPV4Subnet -join ', ')
                    IPv6=($s.IPV6Subnet -join ', ') })
            }
        } catch { $errors += "Subnetze @ $dc : $($_.Exception.Message)" }

        try {
            $scopes = Get-DnsServerZoneScope -ComputerName $dc -ZoneName $zone -ErrorAction Stop
            foreach ($sc in $scopes) {
                $scName = $sc.ZoneScope
                if ($scName -eq $zone) { continue }
                try {
                    $recs = Get-DnsServerResourceRecord -ComputerName $dc -ZoneName $zone -ZoneScope $scName -ErrorAction Stop
                    # Nur A/AAAA/CNAME zeigen - NS/SOA der Scopes sind Rauschen
                    $recs = $recs | Where-Object { $_.RecordType -in @('A','AAAA','CNAME') }
                    if (-not $recs) {
                        [void]$scpList.Add([PSCustomObject]@{
                            DC=$dc; Zone=$zone; Scope=$scName; Record="(keine A/AAAA/CNAME)"; Type=""; Data="" })
                    }
                    foreach ($r in $recs) {
                        $data = switch ($r.RecordType) {
                            'A'     { [string]$r.RecordData.IPv4Address }
                            'AAAA'  { [string]$r.RecordData.IPv6Address }
                            'CNAME' { [string]$r.RecordData.HostNameAlias }
                            default { "" }
                        }
                        [void]$scpList.Add([PSCustomObject]@{
                            DC=$dc; Zone=$zone; Scope=$scName; Record=$r.HostName; Type=$r.RecordType; Data=$data })
                    }
                } catch {
                    [void]$scpList.Add([PSCustomObject]@{
                        DC=$dc; Zone=$zone; Scope=$scName; Record="(Lesefehler)"; Type=""; Data=$_.Exception.Message })
                }
            }
        } catch { $errors += "Scopes @ $dc : $($_.Exception.Message)" }
    }

    $GridPolicies.ItemsSource = $polList
    $GridSubnets.ItemsSource  = $subList
    $GridScopes.ItemsSource   = $scpList
    $script:dataPolicies = $polList
    $script:dataSubnets  = $subList
    $script:dataScopes   = $scpList

    $msg = "Geladen: $($polList.Count) Policies, $($subList.Count) Subnetze, $($scpList.Count) Scope-Records ($($dcs.Count) DC)."
    if ($errors.Count -gt 0) { $msg += "  HINWEIS: " + ($errors -join ' || ') }
    Set-Status $msg
}

function Export-Data {
    if ($script:dataPolicies.Count -eq 0 -and $script:dataScopes.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Keine Daten geladen.","Export","OK","Information") | Out-Null
        return
    }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = "Textdatei (*.txt)|*.txt"
    $dlg.FileName = "DNS-Policy-Report_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').txt"
    if ($dlg.ShowDialog() -eq $true) {
        $sb = New-Object System.Text.StringBuilder
        [void]$sb.AppendLine("=== DNS Policy Report ===")
        [void]$sb.AppendLine("Erstellt: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')")
        [void]$sb.AppendLine("Zone: $($TxtZone.Text)   DC(s): $($TxtDCs.Text)")
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("--- QUERY RESOLUTION POLICIES ---")
        [void]$sb.AppendLine(($script:dataPolicies | Format-Table -AutoSize | Out-String))
        [void]$sb.AppendLine("--- CLIENT-SUBNETZE ---")
        [void]$sb.AppendLine(($script:dataSubnets | Format-Table -AutoSize | Out-String))
        [void]$sb.AppendLine("--- ZONE-SCOPES & A-RECORDS ---")
        [void]$sb.AppendLine(($script:dataScopes | Format-Table -AutoSize | Out-String))
        $sb.ToString() | Out-File -FilePath $dlg.FileName -Encoding UTF8
        Set-Status "Report exportiert: $($dlg.FileName)"
    }
}

# Assistent: legt Subnetz, Scope, Record und Policy in einem Rutsch an
function Show-NewPolicyDialog {
    $targetDC = Get-TargetDC
    $zone = $TxtZone.Text.Trim()

[xml]$dlgXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Neue DNS-Policy anlegen" Height="560" Width="560"
        WindowStartupLocation="CenterScreen" Background="#1A1A1C" ResizeMode="NoResize">
    <Window.Resources>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#1F1F22"/>
            <Setter Property="Foreground" Value="#F2F2F3"/>
            <Setter Property="CaretBrush" Value="#F2F2F3"/>
            <Setter Property="BorderBrush" Value="#3A3A3F"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="6"
                                BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                            <ScrollViewer x:Name="PART_ContentHost" Margin="8,0" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter TargetName="b" Property="BorderBrush" Value="#3B82F6"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Foreground" Value="#9A9AA2"/>
                                <Setter TargetName="b" Property="Background" Value="#202023"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid Margin="0">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Border Grid.Row="0" Background="#242427" Padding="16,12">
            <StackPanel Orientation="Horizontal">
                <Border Width="5" Background="#3B82F6" Margin="0,0,10,0"/>
                <TextBlock Text="Neue Policy fuer multi-homed Server" Foreground="White" FontSize="15" FontWeight="Bold" VerticalAlignment="Center"/>
            </StackPanel>
        </Border>
        <StackPanel Grid.Row="1" Margin="20,16">
            <TextBlock Text="Ziel-DC:" FontWeight="SemiBold" Foreground="#9A9AA2"/>
            <TextBox x:Name="DlgDC" Height="26" Margin="0,2,0,10" IsEnabled="False"/>

            <TextBlock Text="Servername (FQDN-Teil, z.B. srv-app):" FontWeight="SemiBold" Foreground="#9A9AA2"/>
            <TextBox x:Name="DlgServer" Height="26" Margin="0,2,0,10"/>

            <TextBlock Text="Client-Subnetz (CIDR, z.B. 192.168.10.0/24):" FontWeight="SemiBold" Foreground="#9A9AA2"/>
            <TextBox x:Name="DlgSubnet" Height="26" Margin="0,2,0,10"/>

            <TextBlock Text="Ziel-Bein-IP (erreichbares Server-Bein, z.B. 192.168.20.14):" FontWeight="SemiBold" Foreground="#9A9AA2"/>
            <TextBox x:Name="DlgBeinIP" Height="26" Margin="0,2,0,10"/>

            <TextBlock Text="Eindeutige Namen (werden automatisch vorgeschlagen):" FontWeight="SemiBold" Foreground="#9A9AA2" Margin="0,4,0,0"/>
            <Grid Margin="0,2,0,0">
                <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <TextBlock Text="Subnetz-Name: " Grid.Column="0" VerticalAlignment="Center" Foreground="#9A9AA2"/>
                <TextBox x:Name="DlgSubnetName" Grid.Column="1" Height="24"/>
            </Grid>
            <Grid Margin="0,4,0,0">
                <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <TextBlock Text="Scope-Name:   " Grid.Column="0" VerticalAlignment="Center" Foreground="#9A9AA2"/>
                <TextBox x:Name="DlgScopeName" Grid.Column="1" Height="24"/>
            </Grid>
            <Grid Margin="0,4,0,0">
                <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <TextBlock Text="Policy-Name:  " Grid.Column="0" VerticalAlignment="Center" Foreground="#9A9AA2"/>
                <TextBox x:Name="DlgPolicyName" Grid.Column="1" Height="24"/>
            </Grid>

            <TextBlock x:Name="DlgInfo" Text="" Foreground="#3B82F6" TextWrapping="Wrap" Margin="0,10,0,0" FontSize="11"/>
        </StackPanel>
        <Border Grid.Row="2" Background="#242427" Padding="16,12" BorderBrush="#3A3A3F" BorderThickness="0,1,0,0">
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                <Button x:Name="DlgOk" Content="Anlegen" Width="110" Height="32" Background="#3B82F6" Foreground="White" BorderThickness="0" FontWeight="SemiBold" Cursor="Hand" Margin="0,0,8,0"/>
                <Button x:Name="DlgCancel" Content="Abbrechen" Width="110" Height="32" Background="#2D2D31" Foreground="White" BorderThickness="0" Cursor="Hand"/>
            </StackPanel>
        </Border>
    </Grid>
</Window>
"@
    $dr = New-Object System.Xml.XmlNodeReader $dlgXaml
    $dlg = [Windows.Markup.XamlReader]::Load($dr)

    $DlgDC        = $dlg.FindName("DlgDC")
    $DlgServer    = $dlg.FindName("DlgServer")
    $DlgSubnet    = $dlg.FindName("DlgSubnet")
    $DlgBeinIP    = $dlg.FindName("DlgBeinIP")
    $DlgSubnetName= $dlg.FindName("DlgSubnetName")
    $DlgScopeName = $dlg.FindName("DlgScopeName")
    $DlgPolicyName= $dlg.FindName("DlgPolicyName")
    $DlgInfo      = $dlg.FindName("DlgInfo")
    $DlgOk        = $dlg.FindName("DlgOk")
    $DlgCancel    = $dlg.FindName("DlgCancel")

    $DlgDC.Text = $targetDC

    # Konvention (an Bestand angelehnt):
    #   Subnetz-Kuerzel = 3. Oktett des Client-Subnetzes  (192.168.10.0/24 -> "10")
    #   Scope          = Scope-Bein<3. Oktett der Bein-IP> (192.168.20.14   -> "Scope-Bein20")
    #   Policy         = Pol-VLAN<Kuerzel>-<server>        (-> "Pol-VLAN10-srv-app")
    # Hinweis: Das echte VLAN-Kuerzel kennt nur der Admin; hier wird das
    # 3. Oktett als praktischer Default genutzt und ist frei editierbar.
    $updateNames = {
        $srv  = $DlgServer.Text.Trim()
        $sub  = $DlgSubnet.Text.Trim()
        $bein = $DlgBeinIP.Text.Trim()

        $subTag = ""
        if ($sub -match '^\d{1,3}\.\d{1,3}\.(\d{1,3})\.') { $subTag = $matches[1] }
        $beinTag = ""
        if ($bein -match '^\d{1,3}\.\d{1,3}\.(\d{1,3})\.') { $beinTag = $matches[1] }

        if ($srv -and $subTag) {
            if (-not $DlgSubnetName.Text -or $DlgSubnetName.Tag -eq 'auto') {
                $DlgSubnetName.Text = "Subnet-VLAN$subTag"; $DlgSubnetName.Tag='auto' }
            if (-not $DlgPolicyName.Text -or $DlgPolicyName.Tag -eq 'auto') {
                $DlgPolicyName.Text = "Pol-VLAN$subTag-$srv"; $DlgPolicyName.Tag='auto' }
        }
        if ($beinTag -and (-not $DlgScopeName.Text -or $DlgScopeName.Tag -eq 'auto')) {
            $DlgScopeName.Text = "Scope-Bein$beinTag"; $DlgScopeName.Tag='auto'
        }
    }
    $DlgServer.Add_TextChanged($updateNames)
    $DlgSubnet.Add_TextChanged($updateNames)
    $DlgBeinIP.Add_TextChanged($updateNames)
    $DlgSubnetName.Add_GotKeyboardFocus({ $DlgSubnetName.Tag='' })
    $DlgScopeName.Add_GotKeyboardFocus({ $DlgScopeName.Tag='' })
    $DlgPolicyName.Add_GotKeyboardFocus({ $DlgPolicyName.Tag='' })

    $DlgCancel.Add_Click({ $dlg.DialogResult = $false; $dlg.Close() })

    $DlgOk.Add_Click({
        $srv = $DlgServer.Text.Trim()
        $sub = $DlgSubnet.Text.Trim()
        $bein= $DlgBeinIP.Text.Trim()
        $snN = $DlgSubnetName.Text.Trim()
        $scN = $DlgScopeName.Text.Trim()
        $poN = $DlgPolicyName.Text.Trim()

            if (-not $srv) { $DlgInfo.Text = "Servername fehlt."; return }
        if ($sub -notmatch '^\d{1,3}(\.\d{1,3}){3}/\d{1,2}$') { $DlgInfo.Text = "Subnetz muss CIDR sein, z.B. 192.168.10.0/24"; return }
        if ($bein -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { $DlgInfo.Text = "Bein-IP ist keine gueltige IPv4-Adresse."; return }
        if (-not $snN -or -not $scN -or -not $poN) { $DlgInfo.Text = "Namen duerfen nicht leer sein."; return }
        $fqdn = "$srv.$zone"

        $confirm = [System.Windows.MessageBox]::Show(
            "Folgendes wird auf '$targetDC' angelegt:`n`n" +
            "Client-Subnetz : $snN = $sub`n" +
            "Zone-Scope     : $scN`n" +
            "A-Record       : $srv -> $bein  (im Scope)`n" +
            "Policy         : $poN`n" +
            "  Bedingung    : Subnetz $snN  UND  FQDN = $fqdn`n" +
            "  -> Scope     : $scN`n`n" +
            "Hinweis: Existierende Subnetze/Scopes werden wiederverwendet.`nFortfahren?",
            "Anlegen bestaetigen", "YesNo", "Question")
        if ($confirm -ne 'Yes') { return }

        $log = @()
        try {
            $existSub = Get-DnsServerClientSubnet -ComputerName $targetDC -Name $snN -ErrorAction SilentlyContinue
            if (-not $existSub) {
                Add-DnsServerClientSubnet -ComputerName $targetDC -Name $snN -IPv4Subnet $sub -ErrorAction Stop
                $log += "Subnetz '$snN' angelegt."
            } else { $log += "Subnetz '$snN' existierte bereits (wiederverwendet)." }

            $existScope = Get-DnsServerZoneScope -ComputerName $targetDC -ZoneName $zone -Name $scN -ErrorAction SilentlyContinue
            if (-not $existScope) {
                Add-DnsServerZoneScope -ComputerName $targetDC -ZoneName $zone -Name $scN -ErrorAction Stop
                $log += "Scope '$scN' angelegt."
            } else { $log += "Scope '$scN' existierte bereits (wiederverwendet)." }

            $existRec = Get-DnsServerResourceRecord -ComputerName $targetDC -ZoneName $zone -ZoneScope $scN -Name $srv -RRType A -ErrorAction SilentlyContinue
            if (-not $existRec) {
                Add-DnsServerResourceRecord -ComputerName $targetDC -ZoneName $zone -A -Name $srv -IPv4Address $bein -ZoneScope $scN -ErrorAction Stop
                $log += "A-Record '$srv -> $bein' im Scope angelegt."
            } else { $log += "A-Record fuer '$srv' im Scope existierte bereits." }

            Add-DnsServerQueryResolutionPolicy -ComputerName $targetDC -Name $poN -Action ALLOW `
                -ClientSubnet "EQ,$snN" -ZoneScope "$scN,1" -ZoneName $zone -Fqdn "EQ,$fqdn" -ErrorAction Stop
            $log += "Policy '$poN' angelegt."

            $dlg.DialogResult = $true
            $dlg.Tag = ($log -join "`n")
            $dlg.Close()
        } catch {
            $DlgInfo.Text = "FEHLER: $($_.Exception.Message)`n`nBereits ausgefuehrt:`n" + ($log -join "`n")
        }
    })

    $res = $dlg.ShowDialog()
    if ($res -eq $true) {
        Set-Status ("Neue Policy angelegt: " + ($dlg.Tag -replace "`n", " | "))
        Load-Data
    }
}

function Toggle-Policy {
    $sel = $GridPolicies.SelectedItem
    if (-not $sel) {
        [System.Windows.MessageBox]::Show("Bitte zuerst eine Policy in der Tabelle auswaehlen.","Hinweis","OK","Information") | Out-Null
        return
    }
    $dc = $sel.DC; $name = $sel.Name; $zone = $TxtZone.Text.Trim()
    $newState = if ($sel.Enabled -eq "Ja") { $false } else { $true }
    $stateText = if ($newState) { "AKTIVIEREN" } else { "DEAKTIVIEREN" }
    $confirm = [System.Windows.MessageBox]::Show(
        "Policy '$name' auf '$dc' wirklich $stateText`?","Bestaetigen","YesNo","Question")
    if ($confirm -ne 'Yes') { return }
    try {
        Set-DnsServerQueryResolutionPolicy -ComputerName $dc -ZoneName $zone -Name $name -State ($(if($newState){'Enable'}else{'Disable'})) -ErrorAction Stop
        Set-Status "Policy '$name' auf '$dc' wurde ge$($stateText.ToLower())."
        Load-Data
    } catch {
        [System.Windows.MessageBox]::Show("Fehler: $($_.Exception.Message)","Fehler","OK","Error") | Out-Null
    }
}

function Delete-Policy {
    $sel = $GridPolicies.SelectedItem
    if (-not $sel) {
        [System.Windows.MessageBox]::Show("Bitte zuerst eine Policy in der Tabelle auswaehlen.","Hinweis","OK","Information") | Out-Null
        return
    }
    $dc = $sel.DC; $name = $sel.Name; $zone = $TxtZone.Text.Trim()
    $confirm = [System.Windows.MessageBox]::Show(
        "Policy '$name' auf '$dc' wirklich LOESCHEN?`n`n" +
        "Hinweis: Das zugehoerige Client-Subnetz und der Zone-Scope bleiben " +
        "erhalten (koennten von anderen Policies genutzt werden) und werden " +
        "NICHT mitgeloescht.","LOESCHEN bestaetigen","YesNo","Warning")
    if ($confirm -ne 'Yes') { return }
    try {
        Remove-DnsServerQueryResolutionPolicy -ComputerName $dc -ZoneName $zone -Name $name -Force -ErrorAction Stop
        Set-Status "Policy '$name' auf '$dc' geloescht. (Subnetz/Scope blieben erhalten.)"
        Load-Data
    } catch {
        [System.Windows.MessageBox]::Show("Fehler: $($_.Exception.Message)","Fehler","OK","Error") | Out-Null
    }
}

# Klont eine komplette Policy-Einheit auf weitere DCs (Policies replizieren nicht von selbst)
function Replicate-Policy {
    $sel = $GridPolicies.SelectedItem
    if (-not $sel) {
        [System.Windows.MessageBox]::Show("Bitte zuerst eine Policy in der Tabelle auswaehlen.","Hinweis","OK","Information") | Out-Null
        return
    }
    $srcDC = $sel.DC
    $polName = $sel.Name
    $zone = $TxtZone.Text.Trim()

    Set-Status "Lese Quell-Policy '$polName' von '$srcDC' vollstaendig aus ..."
    $window.Dispatcher.Invoke([action]{}, "Render")

    try {
        $pol = Get-DnsServerQueryResolutionPolicy -ComputerName $srcDC -ZoneName $zone -Name $polName -ErrorAction Stop
    } catch {
        [System.Windows.MessageBox]::Show("Quell-Policy konnte nicht gelesen werden:`n$($_.Exception.Message)","Fehler","OK","Error") | Out-Null
        return
    }

    $subnetCrit = (Get-CriteriaValue $pol 'ClientSubnet')   # z.B. "EQ,Subnet-VLAN68"
    $fqdnCrit   = (Get-CriteriaValue $pol 'Fqdn')           # z.B. "EQ,srv-app.example.local."
    $scopeName  = ""
    try { $scopeName = ($pol.Content | ForEach-Object { $_.ScopeName }) -join ',' } catch {}
    $subnetName = ($subnetCrit -replace '^EQ,','').Trim()
    $fqdnValue  = ($fqdnCrit   -replace '^EQ,','').Trim()

    if (-not $subnetName -or -not $scopeName) {
        [System.Windows.MessageBox]::Show("Quell-Policy hat keine eindeutige Subnetz-/Scope-Zuordnung. Abbruch.","Fehler","OK","Error") | Out-Null
        return
    }

    try {
        $srcSubnet = Get-DnsServerClientSubnet -ComputerName $srcDC -Name $subnetName -ErrorAction Stop
        $cidr = ($srcSubnet.IPV4Subnet -join ',')
    } catch {
        [System.Windows.MessageBox]::Show("Subnetz-Definition '$subnetName' konnte nicht gelesen werden:`n$($_.Exception.Message)","Fehler","OK","Error") | Out-Null
        return
    }

    $records = @()
    try {
        $recs = Get-DnsServerResourceRecord -ComputerName $srcDC -ZoneName $zone -ZoneScope $scopeName -RRType A -ErrorAction Stop
        foreach ($r in $recs) {
            $records += [PSCustomObject]@{ Name=$r.HostName; IP=[string]$r.RecordData.IPv4Address }
        }
    } catch {
        [System.Windows.MessageBox]::Show("A-Records im Scope '$scopeName' konnten nicht gelesen werden:`n$($_.Exception.Message)","Fehler","OK","Error") | Out-Null
        return
    }
    if ($records.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Im Quell-Scope '$scopeName' wurden keine A-Records gefunden. Abbruch.","Fehler","OK","Error") | Out-Null
        return
    }

    $recSummary = ($records | ForEach-Object { "$($_.Name) -> $($_.IP)" }) -join ", "
    $targetInput = Show-InputDialog -Title "Auf weitere DCs uebertragen" `
        -Prompt ("Quell-Policy '$polName' von '$srcDC':`n`n" +
                 "  Subnetz : $subnetName = $cidr`n" +
                 "  Scope   : $scopeName`n" +
                 "  Record  : $recSummary`n" +
                 "  FQDN    : $fqdnValue`n`n" +
                 "Ziel-DC(s) eingeben (durch Komma getrennt):") `
        -Default ""
    if ([string]::IsNullOrWhiteSpace($targetInput)) { return }

    $targets = $targetInput -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne $srcDC }
    if ($targets.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Keine gueltigen Ziel-DCs (Quell-DC wird ausgeschlossen).","Hinweis","OK","Information") | Out-Null
        return
    }

    $confirm = [System.Windows.MessageBox]::Show(
        "Die komplette Einheit wird auf folgende DC(s) uebertragen:`n`n  $($targets -join "`n  ")`n`n" +
        "Pro Ziel-DC werden angelegt (falls noch nicht vorhanden):`n" +
        "  - Client-Subnetz $subnetName`n  - Zone-Scope $scopeName`n  - A-Record(s)`n  - Policy $polName`n`nFortfahren?",
        "Uebertragung bestaetigen","YesNo","Question")
    if ($confirm -ne 'Yes') { return }

    $resultLog = @()
    foreach ($dc in $targets) {
        $steps = @()
        try {
            $ex = Get-DnsServerClientSubnet -ComputerName $dc -Name $subnetName -ErrorAction SilentlyContinue
            if (-not $ex) {
                Add-DnsServerClientSubnet -ComputerName $dc -Name $subnetName -IPv4Subnet $cidr -ErrorAction Stop
                $steps += "Subnetz+"
            } else { $steps += "Subnetz=" }

            $ex = Get-DnsServerZoneScope -ComputerName $dc -ZoneName $zone -Name $scopeName -ErrorAction SilentlyContinue
            if (-not $ex) {
                Add-DnsServerZoneScope -ComputerName $dc -ZoneName $zone -Name $scopeName -ErrorAction Stop
                $steps += "Scope+"
            } else { $steps += "Scope=" }

            foreach ($rec in $records) {
                $exR = Get-DnsServerResourceRecord -ComputerName $dc -ZoneName $zone -ZoneScope $scopeName -Name $rec.Name -RRType A -ErrorAction SilentlyContinue
                if (-not $exR) {
                    Add-DnsServerResourceRecord -ComputerName $dc -ZoneName $zone -A -Name $rec.Name -IPv4Address $rec.IP -ZoneScope $scopeName -ErrorAction Stop
                    $steps += "Rec($($rec.IP))+"
                } else { $steps += "Rec($($rec.IP))=" }
            }

            $exP = Get-DnsServerQueryResolutionPolicy -ComputerName $dc -ZoneName $zone -Name $polName -ErrorAction SilentlyContinue
            if (-not $exP) {
                Add-DnsServerQueryResolutionPolicy -ComputerName $dc -Name $polName -Action ALLOW `
                    -ClientSubnet "EQ,$subnetName" -ZoneScope "$scopeName,1" -ZoneName $zone -Fqdn "EQ,$fqdnValue" -ErrorAction Stop
                $steps += "Policy+"
            } else { $steps += "Policy(existiert)" }

            $resultLog += "OK $dc : $($steps -join ' ')"
        } catch {
            $resultLog += "FEHLER $dc : $($_.Exception.Message)  [bis: $($steps -join ' ')]"
        }
    }

    [System.Windows.MessageBox]::Show(($resultLog -join "`n"), "Ergebnis der Uebertragung", "OK", "Information") | Out-Null
    Set-Status ("Uebertragung abgeschlossen: " + ($resultLog -join "  |  "))
    Load-Data
}

# Generischer Eingabedialog
function Show-InputDialog {
    param([string]$Title, [string]$Prompt, [string]$Default = "")
[xml]$ix = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$Title" Height="340" Width="520" WindowStartupLocation="CenterScreen"
        Background="#1A1A1C" ResizeMode="NoResize">
    <Window.Resources>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#1F1F22"/>
            <Setter Property="Foreground" Value="#F2F2F3"/>
            <Setter Property="CaretBrush" Value="#F2F2F3"/>
            <Setter Property="BorderBrush" Value="#3A3A3F"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="6"
                                BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                            <ScrollViewer x:Name="PART_ContentHost" Margin="8,0" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter TargetName="b" Property="BorderBrush" Value="#3B82F6"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Foreground" Value="#9A9AA2"/>
                                <Setter TargetName="b" Property="Background" Value="#202023"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid>
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <Border Grid.Row="0" Background="#242427" Padding="16,12">
            <StackPanel Orientation="Horizontal">
                <Border Width="5" Background="#3B82F6" Margin="0,0,10,0"/>
                <TextBlock Text="$Title" Foreground="White" FontSize="15" FontWeight="Bold" VerticalAlignment="Center"/>
            </StackPanel>
        </Border>
        <StackPanel Grid.Row="1" Margin="18,14">
            <TextBlock x:Name="IxPrompt" TextWrapping="Wrap" Foreground="#9A9AA2" FontSize="12" Margin="0,0,0,10"/>
            <TextBox x:Name="IxInput" Height="28" VerticalContentAlignment="Center" Padding="6,0"/>
        </StackPanel>
        <Border Grid.Row="2" Background="#242427" Padding="16,12" BorderBrush="#3A3A3F" BorderThickness="0,1,0,0">
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                <Button x:Name="IxOk" Content="OK" Width="100" Height="30" Background="#3B82F6" Foreground="White" BorderThickness="0" FontWeight="SemiBold" Cursor="Hand" Margin="0,0,8,0"/>
                <Button x:Name="IxCancel" Content="Abbrechen" Width="100" Height="30" Background="#2D2D31" Foreground="White" BorderThickness="0" Cursor="Hand"/>
            </StackPanel>
        </Border>
    </Grid>
</Window>
"@
    $ir = New-Object System.Xml.XmlNodeReader $ix
    $iw = [Windows.Markup.XamlReader]::Load($ir)
    $IxPrompt = $iw.FindName("IxPrompt")
    $IxInput  = $iw.FindName("IxInput")
    $IxOk     = $iw.FindName("IxOk")
    $IxCancel = $iw.FindName("IxCancel")
    $IxPrompt.Text = $Prompt
    $IxInput.Text  = $Default
    $script:ixResult = $null
    $IxOk.Add_Click({ $script:ixResult = $IxInput.Text; $iw.Close() })
    $IxCancel.Add_Click({ $script:ixResult = $null; $iw.Close() })
    $IxInput.Add_KeyDown({ if ($_.Key -eq 'Return') { $script:ixResult = $IxInput.Text; $iw.Close() } })
    $iw.ShowDialog() | Out-Null
    return $script:ixResult
}

# Bearbeitet Ziel-IP, ProcessingOrder und Name einer bestehenden Policy
function Edit-Policy {
    $sel = $GridPolicies.SelectedItem
    if (-not $sel) {
        [System.Windows.MessageBox]::Show("Bitte zuerst eine Policy in der Tabelle auswaehlen.","Hinweis","OK","Information") | Out-Null
        return
    }
    $dc = $sel.DC
    $polName = $sel.Name
    $zone = $TxtZone.Text.Trim()

    try {
        $pol = Get-DnsServerQueryResolutionPolicy -ComputerName $dc -ZoneName $zone -Name $polName -ErrorAction Stop
    } catch {
        [System.Windows.MessageBox]::Show("Policy konnte nicht gelesen werden:`n$($_.Exception.Message)","Fehler","OK","Error") | Out-Null
        return
    }
    $subnetName = ((Get-CriteriaValue $pol 'ClientSubnet') -replace '^EQ,','').Trim()
    $fqdnValue  = ((Get-CriteriaValue $pol 'Fqdn') -replace '^EQ,','').Trim()
    $scopeName  = ""
    try { $scopeName = ($pol.Content | ForEach-Object { $_.ScopeName }) -join ',' } catch {}
    $curOrder   = $pol.ProcessingOrder

    $curIP = ""
    $recName = ""
    try {
        $recs = Get-DnsServerResourceRecord -ComputerName $dc -ZoneName $zone -ZoneScope $scopeName -RRType A -ErrorAction Stop
        if ($recs) {
            $first = $recs | Select-Object -First 1
            $curIP = [string]$first.RecordData.IPv4Address
            $recName = $first.HostName
        }
    } catch {}

[xml]$ex = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Policy bearbeiten" Height="560" Width="560"
        WindowStartupLocation="CenterScreen" Background="#1A1A1C" ResizeMode="NoResize">
    <Window.Resources>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#1F1F22"/>
            <Setter Property="Foreground" Value="#F2F2F3"/>
            <Setter Property="CaretBrush" Value="#F2F2F3"/>
            <Setter Property="BorderBrush" Value="#3A3A3F"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="6"
                                BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
                            <ScrollViewer x:Name="PART_ContentHost" Margin="8,0" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter TargetName="b" Property="BorderBrush" Value="#3B82F6"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Foreground" Value="#9A9AA2"/>
                                <Setter TargetName="b" Property="Background" Value="#202023"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid>
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <Border Grid.Row="0" Background="#242427" Padding="16,12">
            <StackPanel Orientation="Horizontal">
                <Border Width="5" Background="#3B82F6" Margin="0,0,10,0"/>
                <TextBlock Text="Bestehende Policy bearbeiten" Foreground="White" FontSize="15" FontWeight="Bold" VerticalAlignment="Center"/>
            </StackPanel>
        </Border>
        <StackPanel Grid.Row="1" Margin="20,16">
            <TextBlock Text="Ziel-DC / Scope (nicht aenderbar):" FontWeight="SemiBold" Foreground="#9A9AA2"/>
            <TextBox x:Name="ExInfo" Height="26" Margin="0,2,0,4" IsEnabled="False"/>
            <TextBlock Text="Subnetz- und FQDN-Bedingung bleiben unveraendert." FontStyle="Italic" Foreground="#9A9AA2" FontSize="11" Margin="0,0,0,12"/>

            <TextBlock Text="Policy-Name (Umbenennen legt die Policy unter neuem Namen neu an):" FontWeight="SemiBold" Foreground="#9A9AA2"/>
            <TextBox x:Name="ExName" Height="26" Margin="0,2,0,12"/>

            <TextBlock Text="Ziel-Bein-IP (A-Record im Scope):" FontWeight="SemiBold" Foreground="#9A9AA2"/>
            <TextBox x:Name="ExIP" Height="26" Margin="0,2,0,12"/>

            <TextBlock Text="Verarbeitungsreihenfolge (ProcessingOrder):" FontWeight="SemiBold" Foreground="#9A9AA2"/>
            <TextBox x:Name="ExOrder" Height="26" Margin="0,2,0,12" Width="120" HorizontalAlignment="Left"/>

            <TextBlock x:Name="ExMsg" Text="" Foreground="#3B82F6" TextWrapping="Wrap" FontSize="11"/>
        </StackPanel>
        <Border Grid.Row="2" Background="#242427" Padding="16,12" BorderBrush="#3A3A3F" BorderThickness="0,1,0,0">
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                <Button x:Name="ExOk" Content="Speichern" Width="120" Height="32" Background="#3B82F6" Foreground="White" BorderThickness="0" FontWeight="SemiBold" Cursor="Hand" Margin="0,0,8,0"/>
                <Button x:Name="ExCancel" Content="Abbrechen" Width="110" Height="32" Background="#2D2D31" Foreground="White" BorderThickness="0" Cursor="Hand"/>
            </StackPanel>
        </Border>
    </Grid>
</Window>
"@
    $er = New-Object System.Xml.XmlNodeReader $ex
    $ew = [Windows.Markup.XamlReader]::Load($er)
    $ExInfo  = $ew.FindName("ExInfo")
    $ExName  = $ew.FindName("ExName")
    $ExIP    = $ew.FindName("ExIP")
    $ExOrder = $ew.FindName("ExOrder")
    $ExMsg   = $ew.FindName("ExMsg")
    $ExOk    = $ew.FindName("ExOk")
    $ExCancel= $ew.FindName("ExCancel")

    $ExInfo.Text  = "DC: $dc   |   Scope: $scopeName   |   Subnetz: $subnetName"
    $ExName.Text  = $polName
    $ExIP.Text    = $curIP
    $ExOrder.Text = [string]$curOrder

    $ExCancel.Add_Click({ $ew.DialogResult = $false; $ew.Close() })

    $ExOk.Add_Click({
        $newName  = $ExName.Text.Trim()
        $newIP    = $ExIP.Text.Trim()
        $newOrder = $ExOrder.Text.Trim()

        if (-not $newName) { $ExMsg.Text = "Policy-Name darf nicht leer sein."; return }
        if ($newIP -and $newIP -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { $ExMsg.Text = "Ziel-Bein-IP ist keine gueltige IPv4-Adresse."; return }
        if ($newOrder -and $newOrder -notmatch '^\d+$') { $ExMsg.Text = "ProcessingOrder muss eine Zahl sein."; return }

        $changes = @()
        if ($newIP -and $newIP -ne $curIP) { $changes += "Ziel-IP: $curIP -> $newIP" }
        if ($newOrder -and [int]$newOrder -ne [int]$curOrder) { $changes += "Reihenfolge: $curOrder -> $newOrder" }
        if ($newName -ne $polName) { $changes += "Name: $polName -> $newName (Neuanlage + Loeschen der alten)" }
        if ($changes.Count -eq 0) { $ExMsg.Text = "Keine Aenderungen erkannt."; return }

        $confirm = [System.Windows.MessageBox]::Show(
            "Folgende Aenderungen auf '$dc' anwenden?`n`n  " + ($changes -join "`n  ") + "`n`nFortfahren?",
            "Aenderungen bestaetigen","YesNo","Question")
        if ($confirm -ne 'Yes') { return }

        $log = @()
        try {
            if ($newIP -and $newIP -ne $curIP -and $scopeName -and $recName) {
                $oldRec = Get-DnsServerResourceRecord -ComputerName $dc -ZoneName $zone -ZoneScope $scopeName -Name $recName -RRType A -ErrorAction Stop
                Add-DnsServerResourceRecord -ComputerName $dc -ZoneName $zone -A -Name $recName -IPv4Address $newIP -ZoneScope $scopeName -ErrorAction Stop
                foreach ($o in $oldRec) {
                    Remove-DnsServerResourceRecord -ComputerName $dc -ZoneName $zone -ZoneScope $scopeName -InputObject $o -Force -ErrorAction Stop
                }
                $log += "Ziel-IP geaendert auf $newIP."
            }

            if ($newOrder -and [int]$newOrder -ne [int]$curOrder) {
                Set-DnsServerQueryResolutionPolicy -ComputerName $dc -ZoneName $zone -Name $polName -ProcessingOrder ([uint32]$newOrder) -ErrorAction Stop
                $log += "Reihenfolge gesetzt auf $newOrder."
            }

            if ($newName -ne $polName) {
                $orderForNew = if ($newOrder) { [uint32]$newOrder } else { [uint32]$curOrder }
                Add-DnsServerQueryResolutionPolicy -ComputerName $dc -Name $newName -Action ALLOW `
                    -ClientSubnet "EQ,$subnetName" -ZoneScope "$scopeName,1" -ZoneName $zone -Fqdn "EQ,$fqdnValue" `
                    -ProcessingOrder $orderForNew -ErrorAction Stop
                Remove-DnsServerQueryResolutionPolicy -ComputerName $dc -ZoneName $zone -Name $polName -Force -ErrorAction Stop
                $log += "Umbenannt zu '$newName'."
            }

            $ew.DialogResult = $true
            $ew.Tag = ($log -join " | ")
            $ew.Close()
        } catch {
            $ExMsg.Text = "FEHLER: $($_.Exception.Message)`nBereits ausgefuehrt: " + ($log -join " | ")
        }
    })

    $res = $ew.ShowDialog()
    if ($res -eq $true) {
        Set-Status ("Policy bearbeitet: " + $ew.Tag)
        Load-Data
    }
}

$BtnLoad.Add_Click({ Load-Data })
$BtnExport.Add_Click({ Export-Data })
$BtnNew.Add_Click({ Show-NewPolicyDialog })
$BtnEdit.Add_Click({ Edit-Policy })
$BtnReplicate.Add_Click({ Replicate-Policy })
$BtnToggle.Add_Click({ Toggle-Policy })
$BtnDelete.Add_Click({ Delete-Policy })
$TxtDCs.Add_KeyDown({ if ($_.Key -eq 'Return') { Load-Data } })
$TxtZone.Add_KeyDown({ if ($_.Key -eq 'Return') { Load-Data } })

$window.ShowDialog() | Out-Null