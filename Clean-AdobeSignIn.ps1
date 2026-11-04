<#
 Clean-AdobeSignIn.ps1 - clears stale Adobe sign-in state that the official
 Creative Cloud Cleaner Tool leaves behind. Does NOT touch license files and
 does NOT bypass licensing: you simply sign in again afterwards.

 Default = dry run (lists only). Add -Apply to actually change things.
 Close Lightroom, Photoshop and Creative Cloud (incl. tray icon) first.
#>
param([switch]$Apply)

$ErrorActionPreference = 'Stop'
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = Join-Path $env:USERPROFILE "Desktop\AdobeSignInBackup-$stamp"

# 1. Processes that would lock / rewrite the state
$procs = Get-Process | Where-Object { $_.Name -match '^(Lightroom|Photoshop|Creative Cloud|CCXProcess|CoreSync|AdobeIPCBroker|Adobe Desktop Service|AGSService|node)$' -and $_.Path -like '*Adobe*' }
Write-Host "`n[1] Adobe processes running: $($procs.Count)"
$procs | ForEach-Object { Write-Host "    $($_.Name)" }

# 2. Folders holding cached IMS sign-in / device state (moved to backup, not deleted)
$folders = @(
  "$env:LOCALAPPDATA\Adobe\OOBE",
  "$env:APPDATA\Adobe\OOBE",
  "$env:LOCALAPPDATA\Adobe\Lightroom\Caches"
) | Where-Object { Test-Path $_ }
Write-Host "`n[2] Folders to move to backup:"
$folders | ForEach-Object { Write-Host "    $_" }

# 3. Credential Manager entries (cleaner tool never removes these)
$creds = cmdkey /list | Select-String 'Target:\s*(?:LegacyGeneric:target=)?(.+)$' |
  ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() } |
  Where-Object { $_ -match 'Adobe|ims_device_token|device_token|ACCC' }
Write-Host "`n[3] Credential Manager entries: $($creds.Count)"
$creds | ForEach-Object { Write-Host "    $_" }

if (-not $Apply) {
  Write-Host "`nDRY RUN - nothing changed. Re-run with -Apply to proceed." -ForegroundColor Yellow
  return
}

if ($procs) { throw 'Close Adobe apps first (see list above), then re-run.' }

New-Item -ItemType Directory -Path $backup | Out-Null
$creds | Set-Content (Join-Path $backup 'credential-names.txt')

foreach ($f in $folders) {
  $dest = Join-Path $backup (($f -replace '[:\\]', '_'))
  Move-Item -LiteralPath $f -Destination $dest
  Write-Host "moved  $f"
}
foreach ($c in $creds) {
  cmdkey /delete:"$c" | Out-Null
  cmdkey /delete:"LegacyGeneric:target=$c" 2>$null | Out-Null
  Write-Host "removed credential $c"
}
Write-Host "`nDone. Backup: $backup`nNow open Creative Cloud, sign in again, then open Lightroom Classic." -ForegroundColor Green
