<#
 AdobeToolkit.psm1 - core logic (no UI).
 Everything is DRY-RUN unless -Apply is passed. Nothing here touches license
 files or bypasses licensing; it only clears stale local state so the user can
 sign in again.
#>
Set-StrictMode -Version 2
$script:LogFile = $null

function Initialize-Session {
    param([string]$Root = (Join-Path $env:ProgramData 'AdobeToolkit'))
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dir = Join-Path $Root $stamp
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $script:LogFile = Join-Path $dir 'toolkit.log'
    Write-Log "Session started. User=$env:USERNAME Machine=$env:COMPUTERNAME"
    return $dir
}

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 }
    Write-Verbose $line
}

function Get-AdobeBusyProcesses {
    # Only processes that run from Adobe's own install folders count. This tool itself (and the
    # always-on AdobeNotificationClient Store app) must never be treated as "Adobe is open".
    $roots = @("${env:ProgramFiles}\Adobe\", "${env:ProgramFiles(x86)}\Adobe\",
               "${env:ProgramFiles}\Common Files\Adobe\", "${env:ProgramFiles(x86)}\Common Files\Adobe\")
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $path = $null; try { $path = $_.Path } catch { }
        if (-not $path -or $_.Id -eq $PID -or $_.Name -eq 'AdobeNotificationClient') { return $false }
        foreach ($r in $roots) { if ($path.StartsWith($r, [StringComparison]::OrdinalIgnoreCase)) { return $true } }
        $false
    }
}

function Get-InstalledAdobe {
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                   'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*') {
        foreach ($i in (Get-ItemProperty $k -ErrorAction SilentlyContinue)) {
            $p = $i.PSObject.Properties
            if ($p['Publisher'] -and $p['DisplayName'] -and $i.Publisher -match 'Adobe') {
                [pscustomobject]@{ Name = $i.DisplayName; Version = $(if ($p['DisplayVersion']) { $i.DisplayVersion } else { '' }) }
            }
        }
    }
}

# ---------------------------------------------------------------- diagnostics
function Get-AdobeMainBinaries {
    # Only check actual main Adobe executables and known patch target DLLs (10x faster than checking 60+ helper EXEs)
    $pf = ${env:ProgramFiles}; $cf86 = ${env:ProgramFiles(x86)}
    $targetNames = @(
        'Lightroom.exe', 'Photoshop.exe', 'Illustrator.exe', 'Adobe Bridge.exe',
        'Adobe Premiere Pro.exe', 'AfterFX.exe', 'Adobe Media Encoder.exe',
        'InDesign.exe', 'Acrobat.exe', 'Adobe Desktop Service.exe',
        'RuntimeInstaller.dll', 'dvaappsupport.dll', 'SweetPeaSupport.dll',
        'Registration.dll', 'AppsPanelBL.dll'
    )
    $patterns = @(
        "$pf\Adobe\*\*.exe",
        "$pf\Adobe\*\Support Files\Contents\Windows\*.exe",
        "$pf\Adobe\*\Required\DynamicLinkMediaServer\RuntimeInstaller.dll",
        "$pf\Adobe\*\dlms\*.dll",
        "$cf86\Common Files\Adobe\Adobe Desktop Common\ADS\*.exe",
        "$cf86\Common Files\Adobe\Adobe Desktop Common\AppsPanel\*.dll"
    )
    Get-ChildItem -Path $patterns -ErrorAction SilentlyContinue | Where-Object { $targetNames -contains $_.Name }
}

function Get-AdobeFirewallBlockRules {
    # Uses HNetCfg.FwPolicy2 COM (~0.4s) instead of slow CIM Get-NetFirewallRule (~7s)
    $out = New-Object System.Collections.Generic.List[object]
    try {
        $fw = New-Object -ComObject HNetCfg.FwPolicy2
        foreach ($r in $fw.Rules) {
            if ($r.Enabled -and $r.Action -eq 0 -and $r.Name -match 'Adobe|Lightroom|Photoshop|Illustrator|Premiere|AfterFX|CCX|Creative|GenP|Unlicensed') {
                $dir = if ($r.Direction -eq 1) { 'Inbound' } else { 'Outbound' }
                $out.Add([pscustomobject]@{
                    Name      = [string]$r.Name
                    Direction = $dir
                    Display   = ("{0} ({1})" -f $r.Name, $dir)
                })
            }
        }
    } catch { }
    $out.ToArray()
}

function Test-ImsTcpFast {
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $ar = $tcp.BeginConnect('ims-na1.adobelogin.com', 443, $null, $null)
        return ($ar.AsyncWaitHandle.WaitOne(1800, $false) -and $tcp.Connected)
    } catch {
        return $false
    } finally {
        try { $tcp.Close() } catch { }
    }
}

function Get-TamperedAdobeFiles {
    $pf = ${env:ProgramFiles}; $cf86 = ${env:ProgramFiles(x86)}
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($f in (Get-AdobeMainBinaries)) {
        $sig = Get-AuthenticodeSignature $f.FullName -ErrorAction SilentlyContinue
        if ($sig -and $sig.Status -eq 'HashMismatch') {
            $out.Add("HashMismatch: $($f.FullName)")
        }
    }
    $baks = Get-ChildItem -Path "$pf\Adobe\*\*.bak", "$pf\Adobe\*\dlms\*.bak", "$cf86\Common Files\Adobe\Adobe Desktop Common\*\*.bak" -ErrorAction SilentlyContinue
    foreach ($b in $baks) {
        $out.Add("Backup(.bak): $($b.FullName)")
    }
    @($out | Sort-Object -Unique)
}

function Get-Diagnostics {
    $r = [ordered]@{}
    $r.Time        = (Get-Date).ToString('s')
    $r.TimeZone    = (Get-TimeZone).Id
    $r.OS          = (Get-CimInstance Win32_OperatingSystem).Caption
    $r.IsAdmin     = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    $hosts = Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" -ErrorAction SilentlyContinue |
        Where-Object { $_ -and $_ -notmatch '^\s*#' -and $_ -match 'adobe|adobelogin|adobe\.io|adobe\.com|typekit|behance' }
    $r.HostsAdobeEntries = @($hosts)

    $proxy = (netsh winhttp show proxy) -join ' '
    $r.WinHttpProxy = if ($proxy -match 'Direct access') { 'direct' } else { $proxy.Trim() }

    $r.FirewallBlocks = @(Get-AdobeFirewallBlockRules | ForEach-Object { $_.Display } | Sort-Object -Unique)

    $r.AdobeProcesses = @(Get-AdobeBusyProcesses | Select-Object -ExpandProperty Name -Unique)

    $svcs = Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'Adobe|AGMService|AGSService' -or $_.DisplayName -match 'Adobe' } |
        ForEach-Object { '{0}={1} ({2})' -f $_.Name, $_.Status, $_.StartType }
    $r.AdobeServices = @($svcs)

    $r.InstalledAdobe = @(Get-InstalledAdobe | ForEach-Object { ('{0} {1}' -f $_.Name, $_.Version).Trim() } | Sort-Object -Unique)

    $r.TamperedFiles = @(Get-TamperedAdobeFiles)

    $allCreds = @(Get-AdobeCredentialTargets)
    $r.CredentialEntries = $allCreds.Count
    $r.DeviceTokens = @($allCreds | Where-Object { $_ -match 'device_token' })
    $r.CredentialGroups = @(Get-SignInGroups | ForEach-Object {
        [pscustomobject]@{
            App         = $_.Name
            Shared      = $_.Shared
            Credentials = $_.Credentials.Count
            Folders     = $_.Folders.Count
        }
    })

    $guids = Get-ChildItem "$env:LOCALAPPDATA\Adobe\OOBE\com.adobe.acc.*.prefs" -ErrorAction SilentlyContinue |
        ForEach-Object { if ($_.Name -match '^com\.adobe\.acc\.(?:[a-z]+\.)?([0-9A-F]{20,})\.prefs$') { $Matches[1] } } |
        Sort-Object -Unique
    $r.OobeAccountGuids = @($guids)

    $r.StateFolders = @(Get-SignInFolders | ForEach-Object { $_ })
    $r.LicensingFolders = @('C:\ProgramData\Adobe\SLStore', 'C:\ProgramData\Adobe\SLCache') | Where-Object { Test-Path -LiteralPath $_ }

    $r.ImsReachable = Test-ImsTcpFast
    [pscustomobject]$r
}

function Export-Report {
    param([Parameter(Mandatory)]$Diagnostics, [Parameter(Mandatory)][string]$Directory)
    $json = Join-Path $Directory 'report.json'
    $Diagnostics | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $json -Encoding UTF8
    Write-Log "Report written: $json"
    $json
}

# ------------------------------------------------------------ sign-in state
function Get-SignInFolders {
    @("$env:LOCALAPPDATA\Adobe\OOBE", "$env:APPDATA\Adobe\OOBE",
      "$env:LOCALAPPDATA\Adobe\Lightroom\Caches") | Where-Object { Test-Path -LiteralPath $_ }
}

function Get-AdobeCredentialTargets {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in (cmdkey /list)) {
        if ($line -match 'Target:\s*(?:LegacyGeneric:target=)?(.+)$') {
            $t = $Matches[1].Trim()
            if ($t -match '^(Adobe |ACCC\.|Adobe Lightroom|Adobe Photoshop|.*ims_device_token)') { $out.Add($t) }
        }
    }
    $out | Sort-Object -Unique
}

function Invoke-SignInClean {
    [CmdletBinding()]
    param([string]$SessionDir, [switch]$Apply)
    $busy = Get-AdobeBusyProcesses
    if ($busy) { throw 'Adobe apps are running. Close them (including the Creative Cloud tray icon) first.' }

    $folders = @(Get-SignInFolders); $creds = @(Get-AdobeCredentialTargets)
    Write-Log ("Sign-in clean: {0} folders, {1} credentials. Apply={2}" -f $folders.Count, $creds.Count, [bool]$Apply)
    if (-not $Apply) { return [pscustomobject]@{ Folders = $folders; Credentials = $creds; Applied = $false } }

    $bk = Join-Path $SessionDir 'backup'; New-Item -ItemType Directory -Force -Path $bk | Out-Null
    $creds | Set-Content (Join-Path $bk 'credential-names.txt') -Encoding UTF8
    foreach ($f in $folders) {
        $dest = Join-Path $bk (($f -replace '[:\\]', '_'))
        Move-Item -LiteralPath $f -Destination $dest -Force
        Save-BackupRecord -SessionDir $SessionDir -Kind 'Folder' -Source $f -BackupPath $dest
        Write-Log "Moved $f -> $dest"
    }
    foreach ($c in $creds) {
        cmdkey /delete:"$c" 2>$null | Out-Null
        cmdkey /delete:"LegacyGeneric:target=$c" 2>$null | Out-Null
        Write-Log "Removed credential: $c"
    }
    [pscustomobject]@{ Folders = $folders; Credentials = $creds; Applied = $true; Backup = $bk }
}

# --------------------------------------------- leftovers from Adobe's own list
function Get-ProdInstallListXml {
    <# Reads ProdInstallList.xml out of a genuine AdobeCreativeCloudCleanerTool.exe
       (the file is Adobe's, so we never ship it - we read the user's copy). #>
    param([Parameter(Mandatory)][string]$CleanerExe)
    $bytes = [IO.File]::ReadAllBytes($CleanerExe)
    $name  = [Text.Encoding]::ASCII.GetBytes('ACToolMain.exe')
    $start = -1
    for ($i = 0; $i -lt $bytes.Length - 40; $i++) {
        if ($bytes[$i] -eq 0x50 -and $bytes[$i+1] -eq 0x4B -and $bytes[$i+2] -eq 3 -and $bytes[$i+3] -eq 4) {
            $ok = $true; for ($j = 0; $j -lt $name.Length; $j++) { if ($bytes[$i+30+$j] -ne $name[$j]) { $ok = $false; break } }
            if ($ok) { $start = $i; break }
        }
    }
    if ($start -lt 0) { throw 'Embedded Adobe payload not found - is this the official Cleaner Tool?' }
    $eocd = -1
    for ($i = $bytes.Length - 22; $i -gt $start; $i--) {
        if ($bytes[$i] -eq 0x50 -and $bytes[$i+1] -eq 0x4B -and $bytes[$i+2] -eq 5 -and $bytes[$i+3] -eq 6) { $eocd = $i; break }
    }
    if ($eocd -lt 0) { throw 'ZIP end record not found.' }
    $len = ($eocd + 22) - $start
    Add-Type -AssemblyName System.IO.Compression
    $ms  = New-Object IO.MemoryStream(, ([byte[]]$bytes[$start..($start + $len - 1)]))
    $zip = New-Object IO.Compression.ZipArchive($ms)
    try {
        $e = $zip.GetEntry('ProdInstallList.xml'); if (-not $e) { throw 'ProdInstallList.xml missing.' }
        $sr = New-Object IO.StreamReader($e.Open()); $sr.ReadToEnd()
    } finally { $zip.Dispose() }
}

function Get-TokenMap {
    $pf = ${env:ProgramFiles}; $pf86 = ${env:ProgramFiles(x86)}
    @{
        '[AdobeProgramFiles_x64]' = "$pf\Adobe";           '[AdobeProgramFiles]' = "$pf86\Adobe"
        '[AdobeCommon_x64]'       = "$pf\Common Files\Adobe"; '[AdobeCommon]'     = "$pf86\Common Files\Adobe"
        '[Common]'                = "$pf86\Common Files"
        '[SharedApplicationData]' = $env:ProgramData;      '[SharedDocuments]'   = "$env:PUBLIC\Documents"
        '[UserLocalAppData]'      = $env:LOCALAPPDATA;     '[UserRoamingAppData]' = $env:APPDATA
        '[UserDocuments]'         = [Environment]::GetFolderPath('MyDocuments')
    }
}

function Test-SafeToRemove {
    # Guard rail: only paths that sit INSIDE an Adobe-specific location may be removed.
    param([string]$Path)
    $p = ([IO.Path]::GetFullPath($Path)).TrimEnd('\')
    $allowedRoots = @("${env:ProgramFiles}\Adobe", "${env:ProgramFiles(x86)}\Adobe",
        "${env:ProgramFiles}\Common Files\Adobe", "${env:ProgramFiles(x86)}\Common Files\Adobe",
        "$env:ProgramData\Adobe", "$env:LOCALAPPDATA\Adobe", "$env:APPDATA\Adobe",
        "$env:LOCALAPPDATA\Temp\Adobe", "$env:LOCALAPPDATA\Temp\CreativeCloud")
    foreach ($r in $allowedRoots) {
        $root = $r.TrimEnd('\')
        if ($p.Length -gt $root.Length -and $p.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    $false
}

function Get-SharedComponentPatterns {
    # Shared Adobe pieces that every installed Adobe app relies on; never "leftover" while any app exists.
    'Creative Cloud', 'CEP', 'Startup Scripts', 'Scripting Dictionaries', 'CoreSync', 'Keyfiles',
    'NotificationManager', 'Extensions', 'Adobe Desktop Common', 'OOBE', 'AdobeGCClient', 'ACPL', 'Adobe Sync'
}

function Test-InUse {
    <# True when a path/key still belongs to something that is installed right now. #>
    param([string]$Text, $Installed)
    if (-not @($Installed).Count) { return $false }
    foreach ($s in Get-SharedComponentPatterns) { if ($Text -match [regex]::Escape($s)) { return $true } }
    foreach ($a in $Installed) {
        # "Adobe Photoshop 2025" -> match "Photoshop 2025" ; "Lightroom Classic" -> "Lightroom"
        $key = ($a.Name -replace '^Adobe\s+', '' -replace '\s+\d+(\.\d+)*$', '').Trim()
        $short = ($key -split '\s+')[0]
        if ($key.Length -gt 3 -and $Text -match [regex]::Escape($key)) { return $true }
        if ($short.Length -gt 4 -and $Text -match ('\\' + [regex]::Escape($short) + '(\b|$)')) { return $true }
    }
    $false
}

function Test-SafeRegistryKey {
    # Only Adobe-specific per-user locations. Anything else in Adobe's list (e.g. HKCU\Control Panel\Desktop) is ignored.
    param([string]$Key)
    $Key -match '^HKCU\\Software\\Adobe\\' -or
    $Key -match '^HKCU\\Software\\Classes\\(\.adobe[^\\]*|Adobe[^\\]*)(\\|$)' -or
    $Key -match '^HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run\\Adobe[^\\]*$'
}

function Get-EmbeddedLeftoverCatalog {
    $b64 = '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'
    $bytes = [Convert]::FromBase64String($b64)
    $ms = New-Object IO.MemoryStream(, $bytes)
    $gz = New-Object IO.Compression.GZipStream($ms, [IO.Compression.CompressionMode]::Decompress)
    $sr = New-Object IO.StreamReader($gz, [Text.Encoding]::UTF8)
    try {
        return ($sr.ReadToEnd() | ConvertFrom-Json)
    } finally {
        $sr.Dispose(); $gz.Dispose(); $ms.Dispose()
    }
}

function Get-LeftoverTargets {
    <# Returns objects: Kind (Folder|Registry), Path, InUse. Uses embedded 588-product catalog by default, or an external CleanerExe if specified. #>
    param([string]$CleanerExe = '')
    $map = Get-TokenMap
    $installed = @(Get-InstalledAdobe)
    if ($CleanerExe -and (Test-Path -LiteralPath $CleanerExe)) {
        $xml = Get-ProdInstallListXml $CleanerExe
        $folders = [regex]::Matches($xml, '<folder>([^<]+)</folder>') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        $regs    = [regex]::Matches($xml, '<reg>([^<]+)</reg>')       | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
    } else {
        $cat = Get-EmbeddedLeftoverCatalog
        $folders = @($cat.Folders)
        $regs    = @($cat.Regs)
    }
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($f in $folders) {
        $s = $f; foreach ($k in $map.Keys) { $s = $s.Replace($k, $map[$k]) }
        $s = $s.Replace('/', '\').TrimEnd('\')
        if ($s -match '\[\w+\]') { continue }
        if ((Test-Path -LiteralPath $s) -and (Test-SafeToRemove $s)) {
            $out.Add([pscustomobject]@{ Kind = 'Folder'; Path = $s; InUse = (Test-InUse $s $installed) })
        }
    }
    foreach ($r in $regs) {
        if (-not (Test-SafeRegistryKey $r)) { continue }
        if (Test-Path -LiteralPath ('Registry::HKEY_CURRENT_USER\' + $r.Substring(5)) -ErrorAction SilentlyContinue) {
            $out.Add([pscustomobject]@{ Kind = 'Registry'; Path = $r; InUse = (Test-InUse $r $installed) })
        }
    }
    $out.ToArray()
}

function Invoke-LeftoverClean {
    <# Removes ONLY the targets passed in (the caller/GUI decides which). Folders are moved to the backup
       directory, registry keys are exported to .reg first. Targets that are InUse are refused. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Targets, [string]$SessionDir, [switch]$Apply, [switch]$IncludeInUse)
    $todo = @($Targets | Where-Object { $IncludeInUse -or -not $_.InUse })
    Write-Log ("Leftover clean: {0} selected, {1} skipped as in-use. Apply={2}" -f $todo.Count, (@($Targets).Count - $todo.Count), [bool]$Apply)
    if (-not $Apply) { return $todo }
    if (Get-AdobeBusyProcesses) { throw 'Adobe apps are running. Close them first.' }

    $bk = Join-Path $SessionDir 'backup-leftovers'; New-Item -ItemType Directory -Force -Path $bk | Out-Null
    $n = 0
    foreach ($t in $todo) {
        $n++
        if ($t.Kind -eq 'Registry') {
            if (-not (Test-SafeRegistryKey $t.Path)) { Write-Log "Refused registry key: $($t.Path)" 'WARN'; continue }
            $file = Join-Path $bk ('reg{0:D4}.reg' -f $n)
            $sub  = 'HKCU\' + $t.Path.Substring(5)
            reg export $sub $file /y 2>$null | Out-Null
            if (Test-Path $file) { reg delete $sub /f 2>$null | Out-Null; Save-BackupRecord -SessionDir $SessionDir -Kind 'Reg' -Source $($t.Path) -BackupPath $file; Write-Log "Deleted $($t.Path) (backup $file)" }
            else { Write-Log "Export failed, left in place: $($t.Path)" 'WARN' }
        } else {
            if (-not (Test-SafeToRemove $t.Path)) { Write-Log "Refused folder: $($t.Path)" 'WARN'; continue }
            $dest = Join-Path $bk ('dir{0:D4}' -f $n)
            try { Move-Item -LiteralPath $t.Path -Destination $dest -Force; Save-BackupRecord -SessionDir $SessionDir -Kind 'Folder' -Source $t.Path -BackupPath $dest; Write-Log "Moved $($t.Path) -> $dest" }
            catch { Write-Log "Could not move $($t.Path): $($_.Exception.Message)" 'WARN' }
        }
    }
    $todo
}

# ------------------------------------------------ per-app grouping of sign-in state
function ConvertFrom-AppInfoName {
    # "Adobe App Info (TGlnaHRyb29t...)(Part3)" -> raw app id such as "LightroomClassic"
    param([string]$Target)
    if ($Target -match '^Adobe App Info \(([A-Za-z0-9_\-]+)\)\(Part\d+\)$') {
        $b = $Matches[1].Replace('-', '+').Replace('_', '/')
        while ($b.Length % 4) { $b += '=' }
        try { $s = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)) } catch { return $null }
        if ($s -match '^(.*?)\d*\{\}') { return $Matches[1] }
    }
    $null
}

function Get-FriendlyAppName {
    param([string]$Raw)
    switch ($Raw) {
        'LightroomClassic' { 'Lightroom Classic' }
        'Lightroom'        { 'Lightroom Classic' }
        'Photoshop'        { 'Photoshop' }
        'CCXProcess'       { 'Creative Cloud' }
        'MediaEncoder'     { 'Media Encoder' }
        default            { ($Raw -creplace '([a-z])([A-Z])', '$1 $2') }
    }
}

function Get-SignInGroups {
    <# Groups sign-in folders and Credential Manager entries per Adobe app.
       Each group: Key, Name, Shared, Credentials[], Folders[].
       Shared=$true marks account-wide data: cleaning it signs out EVERY Adobe app. #>
    $groups = @{}
    $add = {
        param($key, $name, $shared)
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = [pscustomobject]@{ Key = $key; Name = $name; Shared = $shared
                Credentials = (New-Object System.Collections.Generic.List[string])
                Folders     = (New-Object System.Collections.Generic.List[string]) }
        }
        $groups[$key]
    }
    $appKey = {
        param($raw)
        $n = Get-FriendlyAppName $raw
        'app:' + ($n -replace '\s', '')
    }
    foreach ($c in Get-AdobeCredentialTargets) {
        $raw = ConvertFrom-AppInfoName $c
        if ($raw) { $n = Get-FriendlyAppName $raw; (& $add (& $appKey $raw) $n $false).Credentials.Add($c); continue }
        if ($c -match '^Adobe Lightroom:')  { (& $add 'app:LightroomClassic' 'Lightroom Classic' $false).Credentials.Add($c); continue }
        if ($c -match '^Adobe Photoshop:')  { (& $add 'app:Photoshop' 'Photoshop' $false).Credentials.Add($c); continue }
        if ($c -match '^Adobe User')        { (& $add 'shared' 'Shared Adobe account info' $true).Credentials.Add($c); continue }
        if ($c -match '^ACCC\.')            { (& $add 'accc' 'Adobe Stock / plugin cache' $false).Credentials.Add($c); continue }
        (& $add 'other' 'Other Adobe entries' $false).Credentials.Add($c)
    }
    foreach ($f in Get-SignInFolders) {
        if ($f -like '*\Lightroom\Caches') { (& $add 'app:LightroomClassic' 'Lightroom Classic' $false).Folders.Add($f) }
        else                               { (& $add 'app:CreativeCloud' 'Creative Cloud' $false).Folders.Add($f) }   # OOBE
    }
    $order = { if ($_.Key -eq 'shared') { 3 } elseif ($_.Key -eq 'other') { 2 } elseif ($_.Key -eq 'accc') { 1 } else { 0 } }
    @($groups.Values | Sort-Object @{ Expression = $order }, Name)
}

function Invoke-SignInGroups {
    <# Cleans exactly the groups passed in. Folders are moved to the backup, credential names are saved first. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Groups, [string]$SessionDir, [switch]$Apply)
    $creds = @($Groups | ForEach-Object { $_.Credentials } | ForEach-Object { $_ })
    $dirs  = @($Groups | ForEach-Object { $_.Folders } | ForEach-Object { $_ })
    Write-Log ("Sign-in groups: {0}. {1} credentials, {2} folders. Apply={3}" -f (($Groups | ForEach-Object { $_.Name }) -join ', '), $creds.Count, $dirs.Count, [bool]$Apply)
    if (-not $Apply) { return [pscustomobject]@{ Credentials = $creds; Folders = $dirs; Applied = $false } }
    if (Get-AdobeBusyProcesses) { throw 'Adobe apps are running. Close them first.' }
    $bk = Join-Path $SessionDir 'backup'; New-Item -ItemType Directory -Force -Path $bk | Out-Null
    $creds | Set-Content (Join-Path $bk 'credential-names.txt') -Encoding UTF8
    foreach ($f in $dirs) {
        Move-Item -LiteralPath $f -Destination (Join-Path $bk ($f -replace '[:\\]', '_')) -Force
        Write-Log "Moved $f"
    }
    foreach ($c in $creds) {
        cmdkey /delete:"$c" 2>$null | Out-Null
        cmdkey /delete:"LegacyGeneric:target=$c" 2>$null | Out-Null
        Write-Log "Removed credential: $c"
    }
    [pscustomobject]@{ Credentials = $creds; Folders = $dirs; Applied = $true; Backup = $bk }
}


function Stop-AdobeProcesses {
    <# Closes all running Adobe processes (and stops Adobe services that lock files). #>
    $procs = @(Get-AdobeBusyProcesses)
    $names = @($procs | Select-Object -ExpandProperty Name -Unique)
    foreach ($p in $procs) {
        try {
            Stop-Process -Id $p.Id -Force -ErrorAction Stop
            Write-Log "Stopped process: $($p.Name) (PID $($p.Id))"
        } catch {
            Write-Log "Could not stop $($p.Name) (PID $($p.Id)): $($_.Exception.Message)" 'WARN'
        }
    }
    Start-Sleep -Milliseconds 400
    return $names
}

function Save-BackupRecord {
    param(
        [Parameter(Mandatory)][string]$SessionDir,
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][string]$Source,
        [string]$BackupPath = ''
    )
    $manifestPath = Join-Path $SessionDir 'restore-manifest.json'
    $list = New-Object System.Collections.Generic.List[object]
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $raw = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($item in @($raw)) { if ($item) { $list.Add($item) } }
        } catch { }
    }
    $list.Add([pscustomobject]@{
        Time       = (Get-Date).ToString('s')
        Kind       = $Kind
        Source     = $Source
        BackupPath = $BackupPath
    })
    $list.ToArray() | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
}

function Get-IntegrityIssues {
    <# Scans for restorable .bak files, patched binaries without .bak, hosts blocks, and firewall blocks. #>
    $pf = ${env:ProgramFiles}; $cf86 = ${env:ProgramFiles(x86)}
    $issues = New-Object System.Collections.Generic.List[object]

    # 1. Check .bak files created by patchers
    $bakPatterns = @(
        "$pf\Adobe\*\*.bak",
        "$pf\Adobe\*\dlms\*.bak",
        "$pf\Adobe\*\Required\DynamicLinkMediaServer\*.bak",
        "$cf86\Common Files\Adobe\Adobe Desktop Common\*\*.bak"
    )
    $bakMap = @{}
    foreach ($b in (Get-ChildItem -Path $bakPatterns -ErrorAction SilentlyContinue)) {
        $orig = $b.FullName.Substring(0, $b.FullName.Length - 4)
        $bakMap[$orig.ToLowerInvariant()] = $b.FullName
        $sig = Get-AuthenticodeSignature $b.FullName -ErrorAction SilentlyContinue
        $valid = ($sig -and $sig.Status -eq 'Valid')
        $issues.Add([pscustomobject]@{
            Kind    = 'BakFile'
            CanFix  = $true
            Label   = 'File gốc (.bak)'
            Display = $orig
            Target  = $orig
            BakPath = $b.FullName
            Note    = $(if ($valid) { 'File .bak có chữ ký Adobe hợp lệ -> Khôi phục về nguyên bản' } else { 'Khôi phục file .bak về vị trí gốc' })
        })
    }

    # 2. Check HashMismatch binaries that do NOT have a .bak file
    foreach ($f in (Get-AdobeMainBinaries)) {
        if ($bakMap.ContainsKey($f.FullName.ToLowerInvariant())) { continue }
        $sig = Get-AuthenticodeSignature $f.FullName -ErrorAction SilentlyContinue
        if ($sig -and $sig.Status -eq 'HashMismatch') {
            $issues.Add([pscustomobject]@{
                Kind    = 'PatchedNoBak'
                CanFix  = $false
                Label   = 'Đã patch (thiếu .bak)'
                Display = $f.FullName
                Target  = $f.FullName
                BakPath = ''
                Note    = 'Mất chữ ký số và không còn file .bak -> Cần gỡ/cài lại app này qua Creative Cloud'
            })
        }
    }

    # 3. Check hosts file for Adobe entries
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    $hostsLines = @(Get-Content $hostsPath -ErrorAction SilentlyContinue |
        Where-Object { $_ -and $_ -notmatch '^\s*#' -and $_ -match 'adobe|adobelogin|adobe\.io|adobe\.com|typekit|behance' })
    if ($hostsLines.Count -gt 0) {
        $issues.Add([pscustomobject]@{
            Kind    = 'HostsBlock'
            CanFix  = $true
            Label   = 'Chặn file hosts'
            Display = "$hostsPath ($($hostsLines.Count) dòng chặn Adobe)"
            Target  = $hostsPath
            BakPath = ''
            Note    = "Xoá $($hostsLines.Count) dòng chặn máy chủ Adobe (có sao lưu file hosts)"
        })
    }

    # 4. Check Windows Firewall enabled Block rules targeting Adobe (fast COM)
    foreach ($r in (Get-AdobeFirewallBlockRules)) {
        $issues.Add([pscustomobject]@{
            Kind    = 'FirewallBlock'
            CanFix  = $true
            Label   = 'Tường lửa chặn'
            Display = $r.Display
            Target  = $r.Name
            BakPath = ''
            Note    = 'Tắt rule chặn kết nối trong Windows Firewall (có thể hoàn tác)'
        })
    }

    $issues.ToArray()
}

function Invoke-IntegrityRepair {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Items, [string]$SessionDir, [switch]$Apply)
    $todo = @($Items | Where-Object { $_.CanFix })
    Write-Log ("Integrity repair: {0} selected fixable items. Apply={1}" -f $todo.Count, [bool]$Apply)
    if (-not $Apply) { return $todo }
    if (Get-AdobeBusyProcesses) { throw 'Các app Adobe đang mở. Hãy bấm "Đóng tiến trình Adobe" trước khi khôi phục.' }

    $bk = Join-Path $SessionDir 'backup-integrity'; New-Item -ItemType Directory -Force -Path $bk | Out-Null
    $n = 0
    foreach ($it in $todo) {
        $n++
        switch ($it.Kind) {
            'BakFile' {
                if (Test-Path -LiteralPath $it.BakPath) {
                    if (Test-Path -LiteralPath $it.Target) {
                        $patchedCopy = Join-Path $bk ("patched_{0:D4}_{1}" -f $n, (Split-Path $it.Target -Leaf))
                        Copy-Item -LiteralPath $it.Target -Destination $patchedCopy -Force
                        Save-BackupRecord -SessionDir $SessionDir -Kind 'FileOverwrite' -Source $it.Target -BackupPath $patchedCopy
                    }
                    Copy-Item -LiteralPath $it.BakPath -Destination $it.Target -Force
                    Remove-Item -LiteralPath $it.BakPath -Force -ErrorAction SilentlyContinue
                    Write-Log "Restored original from .bak: $($it.Target)"
                }
            }
            'HostsBlock' {
                $hostsCopy = Join-Path $bk "hosts_$n.bak"
                Copy-Item -LiteralPath $it.Target -Destination $hostsCopy -Force
                Save-BackupRecord -SessionDir $SessionDir -Kind 'FileOverwrite' -Source $it.Target -BackupPath $hostsCopy
                $cleanLines = Get-Content -LiteralPath $it.Target | Where-Object {
                    $_ -match '^\s*#' -or $_ -notmatch 'adobe|adobelogin|adobe\.io|adobe\.com|typekit|behance'
                }
                Set-Content -LiteralPath $it.Target -Value $cleanLines -Encoding ASCII
                Write-Log "Cleaned Adobe block lines from hosts file"
            }
            'FirewallBlock' {
                $fw = New-Object -ComObject HNetCfg.FwPolicy2; foreach($rule in $fw.Rules){ if($rule.Name -eq $it.Target -and $rule.Action -eq 0){ $rule.Enabled = $false } }
                Save-BackupRecord -SessionDir $SessionDir -Kind 'FirewallDisable' -Source $it.Target -BackupPath $it.Display
                Write-Log "Disabled firewall block rule: $($it.Display) ($($it.Target))"
            }
        }
    }
    return $todo
}

function Get-BackupSessions {
    param([string]$Root = (Join-Path $env:ProgramData 'AdobeToolkit'))
    if (-not (Test-Path -LiteralPath $Root)) { return @() }
    $out = New-Object System.Collections.Generic.List[object]
    $dirs = Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
    foreach ($d in $dirs) {
        $manifestPath = Join-Path $d.FullName 'restore-manifest.json'
        $entries = New-Object System.Collections.Generic.List[object]
        if (Test-Path -LiteralPath $manifestPath) {
            try {
                $raw = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach ($e in @($raw)) { if ($e) { $entries.Add($e) } }
            } catch { }
        } else {
            # Fallback discovery for older backup folders without restore-manifest.json
            $bk1 = Join-Path $d.FullName 'backup'
            if (Test-Path -LiteralPath $bk1) {
                foreach ($sub in (Get-ChildItem -LiteralPath $bk1 -Directory -ErrorAction SilentlyContinue)) {
                    if ($sub.Name -match '^([A-Za-z])__(.+)$') {
                        $orig = "$($Matches[1]):\" + ($Matches[2] -replace '_', '\')
                        $entries.Add([pscustomobject]@{ Time = $d.CreationTime.ToString('s'); Kind = 'Folder'; Source = $orig; BackupPath = $sub.FullName })
                    }
                }
            }
            $bk2 = Join-Path $d.FullName 'backup-leftovers'
            if (Test-Path -LiteralPath $bk2) {
                foreach ($reg in (Get-ChildItem -LiteralPath $bk2 -Filter 'reg*.reg' -ErrorAction SilentlyContinue)) {
                    $entries.Add([pscustomobject]@{ Time = $d.CreationTime.ToString('s'); Kind = 'Reg'; Source = $reg.Name; BackupPath = $reg.FullName })
                }
            }
        }
        if ($entries.Count -gt 0) {
            $fCount  = @($entries | Where-Object { $_.Kind -in @('Folder', 'FolderCopy') }).Count
            $rCount  = @($entries | Where-Object { $_.Kind -eq 'Reg' }).Count
            $oCount  = @($entries | Where-Object { $_.Kind -notin @('Folder', 'Reg') }).Count
            $parts = @()
            if ($fCount) { $parts += "$fCount thư mục" }
            if ($rCount) { $parts += "$rCount registry" }
            if ($oCount) { $parts += "$oCount mục hệ thống/tường lửa" }
            $out.Add([pscustomobject]@{
                Id      = $d.Name
                Time    = $d.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')
                Path    = $d.FullName
                Count   = $entries.Count
                Summary = ($parts -join ', ')
                Entries = $entries.ToArray()
            })
        }
    }
    $out.ToArray()
}

function Restore-BackupSession {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$BackupSession)
    if (Get-AdobeBusyProcesses) { throw 'Các app Adobe đang mở. Hãy bấm "Đóng tiến trình Adobe" trước khi hoàn tác.' }
    $restored = 0
    foreach ($e in $BackupSession.Entries) {
        try {
            switch ($e.Kind) {
                'Folder' {
                    if (Test-Path -LiteralPath $e.BackupPath) {
                        $parent = Split-Path -Parent $e.Source
                        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
                        if (Test-Path -LiteralPath $e.Source) { Remove-Item -LiteralPath $e.Source -Recurse -Force }
                        Move-Item -LiteralPath $e.BackupPath -Destination $e.Source -Force
                        Write-Log "Restored folder: $($e.Source)"
                        $restored++
                    }
                }
                'FolderCopy' {
                    if (Test-Path -LiteralPath $e.BackupPath) {
                        $parent = Split-Path -Parent $e.Source
                        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
                        if (Test-Path -LiteralPath $e.Source) { Remove-Item -LiteralPath $e.Source -Recurse -Force }
                        Copy-Item -LiteralPath $e.BackupPath -Destination $e.Source -Recurse -Force
                        Write-Log "Restored snapshot folder: $($e.Source)"
                        $restored++
                    }
                }
                'Reg' {
                    if (Test-Path -LiteralPath $e.BackupPath) {
                        reg import $e.BackupPath 2>$null | Out-Null
                        Write-Log "Imported registry backup: $($e.BackupPath)"
                        $restored++
                    }
                }
                'FileOverwrite' {
                    if (Test-Path -LiteralPath $e.BackupPath) {
                        Copy-Item -LiteralPath $e.BackupPath -Destination $e.Source -Force
                        Write-Log "Restored file: $($e.Source)"
                        $restored++
                    }
                }
                'FirewallDisable' {
                    $fw = New-Object -ComObject HNetCfg.FwPolicy2; foreach($rule in $fw.Rules){ if($rule.Name -eq $e.Source -and $rule.Action -eq 0){ $rule.Enabled = $true } }
                    Write-Log "Re-enabled firewall rule: $($e.Source)"
                    $restored++
                }
            }
        } catch {
            Write-Log "Restore error on $($e.Source): $($_.Exception.Message)" 'WARN'
        }
    }
    $manifestPath = Join-Path $BackupSession.Path 'restore-manifest.json'
    if (Test-Path -LiteralPath $manifestPath) {
        Rename-Item -LiteralPath $manifestPath -NewName ("restored-" + (Get-Date -Format 'HHmmss') + "-manifest.json") -Force -ErrorAction SilentlyContinue
    }
    return $restored
}

function Invoke-ManualBackup {
    <# Creates a non-destructive snapshot backup of current Adobe OOBE state, Lightroom preferences, HKCU\Software\Adobe registry, and hosts file. #>
    param([string]$Root = (Join-Path $env:ProgramData 'AdobeToolkit'))
    $stamp = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-manual'
    $dir = Join-Path $Root $stamp
    $bk  = Join-Path $dir 'snapshot'
    New-Item -ItemType Directory -Force -Path $bk | Out-Null

    # 1. Copy OOBE and Lightroom Preferences/Caches (non-destructive copy!)
    $folders = @(
        "$env:LOCALAPPDATA\Adobe\OOBE",
        "$env:APPDATA\Adobe\OOBE",
        "$env:APPDATA\Adobe\Lightroom\Preferences"
    ) | Where-Object { Test-Path -LiteralPath $_ }
    foreach ($f in $folders) {
        $dest = Join-Path $bk ($f -replace '[:\\]', '_')
        Copy-Item -LiteralPath $f -Destination $dest -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $dest) {
            Save-BackupRecord -SessionDir $dir -Kind 'FolderCopy' -Source $f -BackupPath $dest
            Write-Log "Snapshot copied folder: $f -> $dest"
        }
    }

    # 2. Export HKCU\Software\Adobe registry
    if (Test-Path 'Registry::HKEY_CURRENT_USER\Software\Adobe') {
        $regFile = Join-Path $bk 'HKCU_Software_Adobe.reg'
        reg export 'HKCU\Software\Adobe' $regFile /y 2>$null | Out-Null
        if (Test-Path -LiteralPath $regFile) {
            Save-BackupRecord -SessionDir $dir -Kind 'Reg' -Source 'HKCU\Software\Adobe' -BackupPath $regFile
            Write-Log "Snapshot exported HKCU\Software\Adobe -> $regFile"
        }
    }

    # 3. Backup hosts file
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    if (Test-Path -LiteralPath $hostsPath) {
        $hostsCopy = Join-Path $bk 'hosts.bak'
        Copy-Item -LiteralPath $hostsPath -Destination $hostsCopy -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $hostsCopy) {
            Save-BackupRecord -SessionDir $dir -Kind 'FileOverwrite' -Source $hostsPath -BackupPath $hostsCopy
        }
    }

    # 4. Save list of current Adobe Credential Manager targets for reference
    @(Get-AdobeCredentialTargets) | Set-Content (Join-Path $bk 'credential-names.txt') -Encoding UTF8
    return $dir
}

Export-ModuleMember -Function *