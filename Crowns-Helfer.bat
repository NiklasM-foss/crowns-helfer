@echo off
setlocal
title Crowns ^& Cannons - Helfer
rem Doppelklick: einrichten, der Helfer sitzt danach in der Taskleiste. "Crowns-Helfer.bat jetzt": einmal abgleichen mit Ausgabe.
rem "Crowns-Helfer.bat entfernen": Helfer, Autostart und Dateien wieder löschen.
powershell -NoProfile -ExecutionPolicy Bypass -Command "$c=[IO.File]::ReadAllText('%~f0'); $c=$c.Substring($c.LastIndexOf('#'+'#PS##')+6); & ([scriptblock]::Create($c)) -Selbst '%~f0' -Modus '%~1'"
echo.
if /i not "%~1"=="auto" if /i not "%~1"=="tray" pause
exit /b
##PS##
param([string]$Selbst, [string]$Modus, [string]$Quelle = 'https://editor.niklasmetzger.de/pack/crowns.json', [string]$Wurzel = '', [string]$Downloads = '', [switch]$Test)
$ErrorActionPreference = 'Stop'
# Nur für Tests: Liste, Instanz-Ordner und Downloads umlenken (werden an den Abgleich vererbt)
if ($env:CROWNS_HELFER_QUELLE) { $Quelle = $env:CROWNS_HELFER_QUELLE }
if ($env:CROWNS_HELFER_WURZEL -and -not $Wurzel) { $Wurzel = $env:CROWNS_HELFER_WURZEL }
if ($env:CROWNS_HELFER_DOWNLOADS -and -not $Downloads) { $Downloads = $env:CROWNS_HELFER_DOWNLOADS }
$Ordner = Join-Path $env:LOCALAPPDATA 'CrownsHelfer'
$Aufgabe = 'Crowns & Cannons Helfer'
$Auto = ($Modus -eq 'auto') -or ($Modus -eq 'tray')
$Log = Join-Path $Ordner 'helfer.log'
$Ua = @{ 'User-Agent' = 'crowns-helfer/1.0.0' }
$Erlaubt = '^(mods|resourcepacks|datapacks|shaderpacks|kubejs)/'
New-Item -ItemType Directory -Force -Path $Ordner | Out-Null
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Schreib([string]$t) {
    if (-not $Auto) { Write-Host $t }
    Add-Content -LiteralPath $Log -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $t) -Encoding UTF8
}

function PfadOk([string]$p) {
    return ($p -match $Erlaubt) -and ($p -notmatch '(^|/)\.\.?(/|$)') -and ($p -notmatch '[:\\]') -and ($p.Length -lt 300)
}

function Hash512([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA512).Hash.ToLower() }

# ---- Einstellungen ----
$EinstDatei = Join-Path $Ordner 'einstellungen.json'
$StatusDatei = Join-Path $Ordner 'status.json'
$Skript = Join-Path $Ordner 'helfer.ps1'
$TrayVbs = Join-Path $Ordner 'tray.vbs'
$RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
function Einst { try { return (Get-Content -LiteralPath $EinstDatei -Raw | ConvertFrom-Json) } catch { return [pscustomobject]@{ autoUpdate = $true; autostart = $true } } }
function EinstSpeichern($e) { $e | ConvertTo-Json | Set-Content -LiteralPath $EinstDatei -Encoding UTF8 }
function Autostart([bool]$an) {
    if ($an) { Set-ItemProperty -Path $RunKey -Name 'CrownsHelfer' -Value ('wscript.exe "' + $TrayVbs + '"') }
    else { Remove-ItemProperty -Path $RunKey -Name 'CrownsHelfer' -ErrorAction SilentlyContinue }
}
function TrayStoppen {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*CrownsHelfer*helfer.ps1*-Modus tray*' -and $_.ProcessId -ne $PID } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

# ---- Entfernen ----
if ($Modus -eq 'entfernen') {
    TrayStoppen
    Autostart $false
    try { Unregister-ScheduledTask -TaskName $Aufgabe -Confirm:$false -ErrorAction Stop } catch { }
    Remove-Item -LiteralPath $Ordner -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host 'Crowns-Helfer ist entfernt. Die Dateien in deinen Instanzen bleiben, wie sie sind.'
    return
}

# ---- Einrichten (Doppelklick auf die .bat) ----
if ($Modus -eq '' -and $Selbst -and -not $Test) {
    $roh = [IO.File]::ReadAllText($Selbst)
    [IO.File]::WriteAllText($Skript, $roh.Substring($roh.LastIndexOf('#' + '#PS##') + 6), (New-Object Text.UTF8Encoding($true)))
    Copy-Item -LiteralPath $Selbst -Destination (Join-Path $Ordner 'Crowns-Helfer.bat') -Force -ErrorAction SilentlyContinue
    Set-Content -LiteralPath $TrayVbs -Encoding ASCII -Value ('CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""' + $Skript + '"" -Modus tray", 0, False')
    try { Unregister-ScheduledTask -TaskName $Aufgabe -Confirm:$false -ErrorAction Stop } catch { }  # alte Fassung
    $e = Einst
    if (-not (Test-Path -LiteralPath $EinstDatei)) { EinstSpeichern $e }
    Autostart ([bool]$e.autostart)
    TrayStoppen
    Start-Process -FilePath 'wscript.exe' -ArgumentList ('"' + $TrayVbs + '"')
    Write-Host ''
    Write-Host 'Crowns & Cannons Helfer ist eingerichtet.'
    Write-Host 'Er sitzt jetzt unten rechts in der Taskleiste (Krone). Rechtsklick: Status, Jetzt aktualisieren,'
    Write-Host 'automatische Updates und Autostart an/aus, Beenden. Eigene Dateien werden nie angefasst.'
    return
}

# ---- Taskleisten-App ----
if ($Modus -eq 'tray') {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $mutex = New-Object Threading.Mutex($false, 'Local\CrownsHelferTray')
    if (-not $mutex.WaitOne(0)) { return }
    [Windows.Forms.Application]::EnableVisualStyles()
    $png = [Convert]::FromBase64String('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')
    $bmp = New-Object Drawing.Bitmap((New-Object IO.MemoryStream(, $png)))
    $icon = [Drawing.Icon]::FromHandle($bmp.GetHicon())
    $script:proc = $null
    $script:letzterStatus = ''
    $script:nächster = (Get-Date).AddSeconds(5)
    $script:dlNeu = $false
    $script:cfVorher = [bool](Get-Process -Name CurseForge -ErrorAction SilentlyContinue)
    $script:fenster = $null

    $ni = New-Object Windows.Forms.NotifyIcon
    $ni.Icon = $icon
    $ni.Text = 'Crowns & Cannons Helfer'
    $ni.Visible = $true

    function Status { try { return (Get-Content -LiteralPath $StatusDatei -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null } }

    function Abgleich {
        if ($script:proc -and -not $script:proc.HasExited) { return }
        $script:proc = Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -PassThru `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + $Skript + '"'), '-Modus', 'auto')
        $ni.Text = 'Crowns & Cannons Helfer: aktualisiert ...'
        $miJetzt.Enabled = $false
    }

    function StatusFenster {
        if ($script:fenster -and -not $script:fenster.IsDisposed) { $script:fenster.Close() }
        $s = Status
        $f = New-Object Windows.Forms.Form
        $f.Text = 'Crowns & Cannons Helfer'
        $f.Icon = $icon
        $f.Width = 620; $f.StartPosition = 'CenterScreen'; $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false
        $y = 14
        function Zeile([string]$t, [bool]$fett = $false) {
            $l = New-Object Windows.Forms.Label
            $l.Text = $t; $l.AutoSize = $false; $l.SetBounds(16, $script:yy, 580, 22)
            if ($fett) { $l.Font = New-Object Drawing.Font($l.Font, [Drawing.FontStyle]::Bold) }
            $f.Controls.Add($l); $script:yy += 24
        }
        $script:yy = $y
        if (-not $s) { Zeile 'Noch kein Abgleich gelaufen.' $true }
        else {
            Zeile ('Pack-Version ' + $s.packVersion + ', letzter Abgleich ' + $s.zeit) $true
            foreach ($i in $s.instanzen) { Zeile ('  ' + $i.name + ': ' + $i.neu + ' neu, ' + $i.weg + ' entfernt' + $(if ($i.jvmOffen) { ', Java-Argument wartet (CurseForge schließen)' } else { '' })) }
            if ($s.fehler) { Zeile ('Fehler: ' + $s.fehler) }
            if ($s.manuell -and $s.manuell.Count -gt 0) {
                $script:yy += 6
                Zeile 'Bitte selbst herunterladen (der Helfer legt die Datei dann automatisch ab):' $true
                foreach ($m in $s.manuell) {
                    $l = New-Object Windows.Forms.LinkLabel
                    $l.Text = ($m.name + '  (' + $m.ordner + ')'); $l.Tag = $m.seite; $l.SetBounds(28, $script:yy, 560, 22)
                    $l.Add_LinkClicked({ param($q, $e) if ($q.Tag) { Start-Process $q.Tag } })
                    $f.Controls.Add($l); $script:yy += 24
                }
            } else { Zeile 'Alles aktuell.' }
        }
        $e = Einst
        Zeile ('Automatische Updates: ' + $(if ($e.autoUpdate) { 'an (alle 15 Minuten)' } else { 'aus' }) + ', Autostart: ' + $(if ($e.autostart) { 'an' } else { 'aus' }))
        $b1 = New-Object Windows.Forms.Button; $b1.Text = 'Jetzt aktualisieren'; $b1.SetBounds(16, $script:yy + 8, 150, 30)
        $b1.Add_Click({ Abgleich; $this.FindForm().Close() })
        $b2 = New-Object Windows.Forms.Button; $b2.Text = 'Protokoll'; $b2.SetBounds(176, $script:yy + 8, 110, 30)
        $b2.Add_Click({ Start-Process notepad.exe -ArgumentList ('"' + $Log + '"') })
        $b3 = New-Object Windows.Forms.Button; $b3.Text = 'Schließen'; $b3.SetBounds(476, $script:yy + 8, 110, 30)
        $b3.Add_Click({ $this.FindForm().Close() })
        $f.Controls.AddRange(@($b1, $b2, $b3))
        $f.ClientSize = New-Object Drawing.Size(610, ($script:yy + 50))
        $script:fenster = $f
        $f.Show(); $f.Activate()
    }

    $menu = New-Object Windows.Forms.ContextMenuStrip
    $miStatus = $menu.Items.Add('Status anzeigen'); $miStatus.Font = New-Object Drawing.Font($miStatus.Font, [Drawing.FontStyle]::Bold)
    $miJetzt = $menu.Items.Add('Jetzt aktualisieren')
    [void]$menu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    $miAuto = New-Object Windows.Forms.ToolStripMenuItem('Automatisch aktualisieren'); $miAuto.CheckOnClick = $true
    $miStart = New-Object Windows.Forms.ToolStripMenuItem('Mit Windows starten'); $miStart.CheckOnClick = $true
    [void]$menu.Items.Add($miAuto); [void]$menu.Items.Add($miStart)
    [void]$menu.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    $miLog = $menu.Items.Add('Protokoll öffnen')
    $miEnde = $menu.Items.Add('Beenden')
    $e0 = Einst; $miAuto.Checked = [bool]$e0.autoUpdate; $miStart.Checked = [bool]$e0.autostart
    $ni.ContextMenuStrip = $menu

    $miStatus.Add_Click({ StatusFenster })
    $ni.Add_DoubleClick({ StatusFenster })
    $miJetzt.Add_Click({ Abgleich })
    $miAuto.Add_CheckedChanged({ $e = Einst; $e.autoUpdate = $miAuto.Checked; EinstSpeichern $e; if ($miAuto.Checked) { $script:nächster = Get-Date } })
    $miStart.Add_CheckedChanged({ $e = Einst; $e.autostart = $miStart.Checked; EinstSpeichern $e; Autostart $miStart.Checked })
    $miLog.Add_Click({ Start-Process notepad.exe -ArgumentList ('"' + $Log + '"') })
    $miEnde.Add_Click({ $ni.Visible = $false; [Windows.Forms.Application]::Exit() })

    # Neue Dateien im Downloads-Ordner: sofort abgleichen, wenn etwas von Hand zu holen war
    $dlPfad = $Downloads
    if (-not $dlPfad) { try { $dlPfad = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path } catch { } }
    if (-not $dlPfad) { $dlPfad = Join-Path $env:USERPROFILE 'Downloads' }
    if (Test-Path -LiteralPath $dlPfad) {
        $fsw = New-Object IO.FileSystemWatcher($dlPfad)
        $fsw.IncludeSubdirectories = $false
        $fsw.EnableRaisingEvents = $true
        Register-ObjectEvent -InputObject $fsw -EventName Created -SourceIdentifier 'CrownsDl' | Out-Null
        Register-ObjectEvent -InputObject $fsw -EventName Renamed -SourceIdentifier 'CrownsDl2' | Out-Null
    }

    $timer = New-Object Windows.Forms.Timer
    $timer.Interval = 4000
    $timer.Add_Tick({
        # Abgleich fertig: Status auswerten
        if ($script:proc -and $script:proc.HasExited) {
            $script:proc = $null
            $miJetzt.Enabled = $true
            $s = Status
            if ($s) {
                $n = 0; foreach ($i in $s.instanzen) { $n += [int]$i.neu }
                $ni.Text = ('Crowns & Cannons Helfer: Pack ' + $s.packVersion + ', ' + $(if ($s.manuell.Count) { [string]$s.manuell.Count + ' Datei(en) selbst laden' } else { 'aktuell' }))
                if ($n -gt 0) { $ni.ShowBalloonTip(5000, 'Crowns & Cannons', ([string]$n + ' Datei(en) aktualisiert.'), 'Info') }
                $sig = (($s.manuell | ForEach-Object { $_.name }) -join ',')
                if ($sig -and $sig -ne $script:letzterStatus) { $ni.ShowBalloonTip(8000, 'Crowns & Cannons', 'Bitte Dateien selbst herunterladen. Klick hier für die Links.', 'Warning') }
                $script:letzterStatus = $sig
            }
        }
        # Downloads beobachten
        if (Get-Event -SourceIdentifier 'CrownsDl' -ErrorAction SilentlyContinue) { Remove-Event -SourceIdentifier 'CrownsDl'; $script:dlNeu = $true }
        if (Get-Event -SourceIdentifier 'CrownsDl2' -ErrorAction SilentlyContinue) { Remove-Event -SourceIdentifier 'CrownsDl2'; $script:dlNeu = $true }
        if ($script:dlNeu -and $script:letzterStatus) { $script:dlNeu = $false; Abgleich }
        $script:dlNeu = $false
        # CurseForge geschlossen: Java-Argument kann jetzt gesetzt werden
        $cf = [bool](Get-Process -Name CurseForge -ErrorAction SilentlyContinue)
        if ($script:cfVorher -and -not $cf) { $s = Status; if ($s -and ($s.instanzen | Where-Object { $_.jvmOffen })) { Abgleich } }
        $script:cfVorher = $cf
        # Regelmäßig abgleichen
        if ($miAuto.Checked -and (Get-Date) -ge $script:nächster) { $script:nächster = (Get-Date).AddMinutes(15); Abgleich }
    })
    $ni.Add_BalloonTipClicked({ StatusFenster })
    $timer.Start()
    [Windows.Forms.Application]::Run()
    $ni.Dispose()
    return
}

# ---- Liste holen ----
$cache = Join-Path $Ordner 'crowns.json'
$pack = $null
try {
    if ($Quelle -match '^https?://') { $roh = (Invoke-WebRequest -UseBasicParsing -Uri $Quelle -TimeoutSec 20 -Headers $Ua).Content }
    else { $roh = [IO.File]::ReadAllText($Quelle) }
    $pack = $roh | ConvertFrom-Json
    [IO.File]::WriteAllText($cache, $roh)
} catch {
    if (Test-Path -LiteralPath $cache) { $pack = [IO.File]::ReadAllText($cache) | ConvertFrom-Json; Schreib ('Liste nicht erreichbar, nehme die zuletzt geladene (' + $_.Exception.Message + ')') }
    else { Schreib ('Liste nicht erreichbar und noch keine gespeichert: ' + $_.Exception.Message); return }
}
$basis = if ($Quelle -match '^(https?://[^/]+)') { $Matches[1] } else { '' }

# ---- Instanzen finden ----
$roots = New-Object System.Collections.Generic.List[string]
if ($Wurzel) { $roots.Add($Wurzel) } else {
    $storage = Join-Path $env:APPDATA 'CurseForge\storage.json'
    if (Test-Path -LiteralPath $storage) {
        try {
            $s = Get-Content -LiteralPath $storage -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($s.'minecraft-settings') {
                $mc = $s.'minecraft-settings' | ConvertFrom-Json
                if ($mc.minecraftRoot) { $roots.Add((Join-Path $mc.minecraftRoot 'Instances')); $roots.Add((Join-Path $mc.minecraftRoot 'minecraft\Instances')) }
            }
        } catch { }
    }
    $roots.Add('C:\curseforge\Instances')
    $roots.Add((Join-Path $env:USERPROFILE 'curseforge\minecraft\Instances'))
    $roots.Add((Join-Path $env:USERPROFILE 'Documents\curseforge\minecraft\Instances'))
}
$instanzen = @()
foreach ($r in ($roots | Select-Object -Unique)) {
    if (-not (Test-Path -LiteralPath $r)) { continue }
    foreach ($d in (Get-ChildItem -LiteralPath $r -Directory)) {
        $j = Join-Path $d.FullName 'minecraftinstance.json'
        if (-not (Test-Path -LiteralPath $j)) { continue }
        $name = $d.Name
        try { $n = (Get-Content -LiteralPath $j -Raw -Encoding UTF8 | ConvertFrom-Json).name; if ($n) { $name = $n } } catch { }
        foreach ($p in $pack.instanzen) { if ($name.StartsWith($p) -or $d.Name.StartsWith($p)) { $instanzen += [pscustomobject]@{ Ordner = $d.FullName; Datei = $j; Name = $name }; break } }
    }
}
if ($instanzen.Count -eq 0) { Schreib 'Keine Crowns-&-Cannons-Instanz gefunden.'; return }

# ---- Downloads-Ordner (für Dateien, die man selbst herunterladen muss) ----
if (-not $Downloads) {
    try { $Downloads = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path } catch { }
    if (-not $Downloads) { $Downloads = Join-Path $env:USERPROFILE 'Downloads' }
}
function AusDownloads($d) {
    if (-not (Test-Path -LiteralPath $Downloads)) { return $null }
    foreach ($f in (Get-ChildItem -LiteralPath $Downloads -File -ErrorAction SilentlyContinue)) {
        if ($d.groesse -and $f.Length -ne [int64]$d.groesse) { continue }
        if ((Hash512 $f.FullName) -eq $d.sha512.ToLower()) { return $f.FullName }
    }
    return $null
}

$cfLaeuft = (-not $Test) -and [bool](Get-Process -Name CurseForge -ErrorAction SilentlyContinue)
$manuell = @{}
$statusInst = @()

foreach ($i in $instanzen) {
    Schreib ('Instanz: ' + $i.Name + ' (Pack-Version ' + $pack.version + ')')
    $neu = 0; $weg = 0
    foreach ($d in $pack.dateien) {
        if (-not (PfadOk $d.pfad)) { continue }
        $ziel = Join-Path $i.Ordner ($d.pfad -replace '/', '\')
        $ok = (Test-Path -LiteralPath $ziel) -and ((Hash512 $ziel) -eq $d.sha512.ToLower())
        if (-not $ok) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ziel) | Out-Null
            $tmp = Join-Path $Ordner 'download.tmp'
            foreach ($q in $d.quellen) {
                $url = if ($q.StartsWith('/')) { $basis + $q } else { $q }
                try {
                    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $tmp -TimeoutSec 300 -Headers $Ua
                    if ((Hash512 $tmp) -ne $d.sha512.ToLower()) { throw 'Prüfsumme stimmt nicht' }
                    Move-Item -LiteralPath $tmp -Destination $ziel -Force
                    $ok = $true; $neu++
                    Schreib ('  neu: ' + $d.pfad)
                    break
                } catch {
                    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                    Schreib ('  ' + $d.pfad + ': Quelle fehlgeschlagen (' + $_.Exception.Message + ')')
                }
            }
            if (-not $ok) {
                $dl = AusDownloads $d
                if ($dl) { Move-Item -LiteralPath $dl -Destination $ziel -Force; $ok = $true; $neu++; Schreib ('  aus Downloads übernommen: ' + $d.pfad) }
                else { $manuell[$d.sha512] = $d }
            }
        }
        if ($ok) {
            foreach ($a in $d.alt) {
                if (-not (PfadOk $a) -or $a -eq $d.pfad) { continue }
                $altPfad = Join-Path $i.Ordner ($a -replace '/', '\')
                if (Test-Path -LiteralPath $altPfad) {
                    try { Remove-Item -LiteralPath $altPfad -Force; $weg++; Schreib ('  alte Version entfernt: ' + $a) }
                    catch { Schreib ('  ' + $a + ' ist gerade gesperrt (Spiel offen?), nächster Versuch später') }
                }
            }
        }
    }
    Schreib ('  ' + $neu + ' neu, ' + $weg + ' entfernt')
    $si = [pscustomobject]@{ name = $i.Name; neu = $neu; weg = $weg; jvmOffen = $false }
    $statusInst += $si

    # ---- Java-Argumente (nur wenn die CurseForge-App zu ist, sonst überschreibt sie es beim Beenden) ----
    if (-not $pack.jvm -or $pack.jvm.Count -eq 0) { continue }
    $inst = Get-Content -LiteralPath $i.Datei -Raw -Encoding UTF8 | ConvertFrom-Json
    $altArgs = [string]$inst.javaArgsOverride
    $fehlt = @($pack.jvm | Where-Object { -not (($altArgs -split '\s+') -contains $_) })
    if ($fehlt.Count -eq 0) { continue }
    if ($cfLaeuft) { $si.jvmOffen = $true; Schreib '  Java-Argument fehlt, CurseForge ist offen: wird gesetzt, sobald die App geschlossen ist'; continue }
    $neuArgs = (($altArgs.Trim() + ' ' + ($fehlt -join ' ')).Trim())
    $bytes = [IO.File]::ReadAllBytes($i.Datei)
    $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $text = [IO.File]::ReadAllText($i.Datei)
    $wert = '"javaArgsOverride": ' + ($neuArgs | ConvertTo-Json)
    $rx = [regex]'"javaArgsOverride"\s*:\s*(null|"(?:[^"\\]|\\.)*")'
    if ($rx.IsMatch($text)) { $text = $rx.Replace($text, $wert.Replace('$', '$$'), 1) }
    else { $text = $text -replace '^\s*\{', ('{' + "`r`n  " + $wert.Replace('$', '$$') + ',') }
    Copy-Item -LiteralPath $i.Datei -Destination ($i.Datei + '.bak') -Force
    [IO.File]::WriteAllText($i.Datei, $text, (New-Object Text.UTF8Encoding($bom)))
    try { $null = [IO.File]::ReadAllText($i.Datei) | ConvertFrom-Json; Schreib ('  Java-Argument gesetzt: ' + $neuArgs) }
    catch { Copy-Item -LiteralPath ($i.Datei + '.bak') -Destination $i.Datei -Force; Schreib '  Java-Argument: Datei wäre kaputt gegangen, alte Fassung wiederhergestellt' }
}

# ---- Status für die Taskleisten-App ----
$st = [pscustomobject]@{
    zeit = (Get-Date -Format 'dd.MM.yyyy HH:mm'); packVersion = $pack.version; instanzen = @($statusInst); fehler = ''
    manuell = @($manuell.Values | ForEach-Object { [pscustomobject]@{ name = $_.name; seite = $_.seite; ordner = $_.pfad.Split('/')[0] } })
}
$st | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Ordner 'status.json') -Encoding UTF8

# ---- Dateien, die man selbst herunterladen muss: Fenster mit Links (nur bei "jetzt", sonst zeigt es die Taskleisten-App) ----
if ($manuell.Count -gt 0 -and -not $Test -and -not $Auto) {
    $hinweis = Join-Path $Ordner 'hinweis.json'
    $zuletzt = 0
    try { $zuletzt = [int64](Get-Content -LiteralPath $hinweis -Raw | ConvertFrom-Json).zeit } catch { }
    $jetzt = [int64]([DateTimeOffset]::Now.ToUnixTimeSeconds())
    if (-not $Auto -or ($jetzt - $zuletzt) -gt 6 * 3600) {
        @{ zeit = $jetzt } | ConvertTo-Json | Set-Content -LiteralPath $hinweis -Encoding UTF8
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        $form = New-Object Windows.Forms.Form
        $form.Text = 'Crowns & Cannons: bitte herunterladen'
        $form.Width = 640; $form.Height = 180 + 34 * [Math]::Min($manuell.Count, 12); $form.StartPosition = 'CenterScreen'; $form.TopMost = $true
        $lbl = New-Object Windows.Forms.Label
        $lbl.Text = "Diese Dateien darf der Helfer nicht selbst laden. Klick auf den Link, lade die Datei herunter (in deinen Downloads-Ordner) und lass dieses Fenster offen: der Helfer legt sie automatisch an die richtige Stelle."
        $lbl.SetBounds(12, 10, 600, 50)
        $form.Controls.Add($lbl)
        $y = 64
        $zeilen = @{}
        foreach ($d in $manuell.Values) {
            $l = New-Object Windows.Forms.LinkLabel
            $l.Text = ($d.name + '  (' + $d.pfad.Split('/')[0] + ')')
            $l.Tag = $d.seite
            $l.SetBounds(16, $y, 590, 24)
            $l.Add_LinkClicked({ param($s, $e) if ($s.Tag) { Start-Process $s.Tag } })
            $form.Controls.Add($l)
            $zeilen[$d.sha512] = $l
            $y += 34
        }
        $timer = New-Object Windows.Forms.Timer
        $timer.Interval = 3000
        $timer.Add_Tick({
            foreach ($k in @($manuell.Keys)) {
                $d = $manuell[$k]
                $dl = AusDownloads $d
                if (-not $dl) { continue }
                foreach ($i in $instanzen) {
                    $ziel = Join-Path $i.Ordner ($d.pfad -replace '/', '\')
                    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ziel) | Out-Null
                    Copy-Item -LiteralPath $dl -Destination $ziel -Force
                }
                Remove-Item -LiteralPath $dl -Force -ErrorAction SilentlyContinue
                Schreib ('  aus Downloads übernommen: ' + $d.pfad)
                $zeilen[$k].Text = ('erledigt: ' + $d.name); $zeilen[$k].LinkArea = New-Object Windows.Forms.LinkArea(0, 0)
                $manuell.Remove($k)
            }
            if ($manuell.Count -eq 0) { $timer.Stop(); $form.Close() }
        })
        $timer.Start()
        [void]$form.ShowDialog()
    }
}

try { $z = Get-Content -LiteralPath $Log -Encoding UTF8; if ($z.Count -gt 800) { $z | Select-Object -Last 400 | Set-Content -LiteralPath $Log -Encoding UTF8 } } catch { }
if (-not $Auto) { Write-Host ''; Write-Host 'Fertig. Protokoll:' $Log }
