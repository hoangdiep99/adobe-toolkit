<#
 Build-Exe.ps1 - Gop AdobeToolkit.psm1 + AdobeToolkit.GUI.ps1 + app.ico thanh 1 file AdobeToolkit.exe DUY NHAT.
 Khong can file .psm1 di kem khi gui cho khach.
#>
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$dist = Join-Path $here 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null

# 1. Tao script gop (bundle) co BOM UTF-8
$psm1 = [IO.File]::ReadAllText((Join-Path $here 'AdobeToolkit.psm1'), [Text.Encoding]::UTF8)
# Bo dong Export-ModuleMember o cuoi module vi da gop chung 1 script
$psm1Clean = [regex]::Replace($psm1, '(?ms)^Export-ModuleMember\b.*$', '')

$gui = [IO.File]::ReadAllText((Join-Path $here 'AdobeToolkit.GUI.ps1'), [Text.Encoding]::UTF8)
$bundlePath = Join-Path $here 'AdobeToolkit.Bundled.ps1'
$combined = $psm1Clean + "`r`n# ==================== GUI ====================`r`n" + $gui
[IO.File]::WriteAllText($bundlePath, $combined, (New-Object Text.UTF8Encoding($true)))

if (-not (Get-Module -ListAvailable ps2exe)) { Install-Module ps2exe -Scope CurrentUser -Force }
Import-Module ps2exe

$outExe = Join-Path $dist 'AdobeToolkit.exe'
if (Test-Path -LiteralPath $outExe) {
    try { Remove-Item -LiteralPath $outExe -Force -ErrorAction Stop }
    catch {
        $oldExe = Join-Path $dist 'AdobeToolkit.old.exe'
        Remove-Item -LiteralPath $oldExe -Force -ErrorAction SilentlyContinue
        Rename-Item -LiteralPath $outExe -NewName 'AdobeToolkit.old.exe' -Force
    }
}
$icoPath = Join-Path $here 'app.ico'
$ps2exeParams = @{
    inputFile    = $bundlePath
    outputFile   = $outExe
    noConsole    = $true
    requireAdmin = $true
    title        = 'Adobe Toolkit'
    description  = 'Adobe Toolkit - Chan doan & Sua loi Adobe'
    company      = 'Adobe Toolkit'
    product      = 'Adobe Toolkit'
    version      = '0.3.0.0'
}
if (Test-Path -LiteralPath $icoPath) {
    $ps2exeParams['iconFile'] = $icoPath
}
Invoke-ps2exe @ps2exeParams

Remove-Item -LiteralPath $bundlePath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $dist 'AdobeToolkit.psm1') -Force -ErrorAction SilentlyContinue

Write-Host "Built standalone single-file EXE with icon: $outExe"
