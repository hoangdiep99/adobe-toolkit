<#
 Build-Exe.ps1 - Dong goi CA 2 BAN:
   1. dist\AdobeToolkit.exe       (Ban cu ps2exe - giu lai theo yeu cau)
   2. dist\AdobeToolkit_Clean.exe (Ban chuan Native C# .NET + Authenticode Digital Signature - than thien Antivirus/Bitdefender)
#>
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$dist = Join-Path $here 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null

# 1. Tao script gop (bundle) co BOM UTF-8
$psm1 = [IO.File]::ReadAllText((Join-Path $here 'AdobeToolkit.psm1'), [Text.Encoding]::UTF8)
$psm1Clean = [regex]::Replace($psm1, '(?ms)^Export-ModuleMember\b.*$', '')
$gui = [IO.File]::ReadAllText((Join-Path $here 'AdobeToolkit.GUI.ps1'), [Text.Encoding]::UTF8)
$bundlePath = Join-Path $here 'AdobeToolkit.Bundled.ps1'
$combined = $psm1Clean + "`r`n# ==================== GUI ====================`r`n" + $gui
[IO.File]::WriteAllText($bundlePath, $combined, (New-Object Text.UTF8Encoding($true)))

$icoPath = Join-Path $here 'app.ico'

# ==============================================================================
# BAN 1: Ban cu (ps2exe) -> dist\AdobeToolkit.exe (Giu lai theo yeu cau)
# ==============================================================================
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
$ps2exeParams = @{
    inputFile    = $bundlePath
    outputFile   = $outExe
    noConsole    = $true
    requireAdmin = $true
    title        = 'Adobe Toolkit'
    description  = 'Adobe Toolkit - Chan doan & Sua loi Adobe'
    company      = 'Adobe Toolkit'
    product      = 'Adobe Toolkit'
    version      = '0.5.0.0'
}
if (Test-Path -LiteralPath $icoPath) { $ps2exeParams['iconFile'] = $icoPath }
Invoke-ps2exe @ps2exeParams
Remove-Item -LiteralPath (Join-Path $dist 'AdobeToolkit.old.exe') -Force -ErrorAction SilentlyContinue

# ==============================================================================
# BAN 2: Ban chuan sach Native C# (.NET Framework csc.exe + Manifest + Authenticode Sign)
#        -> dist\AdobeToolkit_Clean.exe (Khong dung ps2exe stub, khong goi Add-Type dong)
# ==============================================================================
$cleanExe = Join-Path $dist 'AdobeToolkit_Clean.exe'
if (Test-Path -LiteralPath $cleanExe) {
    try { Remove-Item -LiteralPath $cleanExe -Force -ErrorAction Stop } catch { }
}

# Nen GZip script bundle thanh resource nhi phan
$payloadGz = Join-Path $here 'AdobeToolkit.Payload.gz'
$rawBytes  = [Text.Encoding]::UTF8.GetBytes($combined)
$fsOut = [IO.File]::Create($payloadGz)
$gzOut = New-Object IO.Compression.GZipStream($fsOut, [IO.Compression.CompressionMode]::Compress)
$gzOut.Write($rawBytes, 0, $rawBytes.Length)
$gzOut.Dispose()
$fsOut.Dispose()

# Tao file manifest UAC requireAdministrator + Windows 10/11 DPI compatibility
$manifestPath = Join-Path $here 'app.manifest'
$manifestXml = @'
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="0.5.0.0" name="HoangDiep.AdobeToolkit.Clean"/>
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v2">
    <security>
      <requestedPrivileges xmlns="urn:schemas-microsoft-com:asm.v3">
        <requestedExecutionLevel level="requireAdministrator" uiAccess="false" />
      </requestedPrivileges>
    </security>
  </trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}" />
    </application>
  </compatibility>
</assembly>
'@
[IO.File]::WriteAllText($manifestPath, $manifestXml, [Text.Encoding]::UTF8)

$csHostPath = Join-Path $here 'NativeHost.cs'
if (-not (Test-Path -LiteralPath $csHostPath)) {
    Copy-Item -LiteralPath 'C:\Users\DiepPC\.gemini\antigravity\brain\20ae9543-79e9-444b-8e22-c570ea7f3fd2\scratch\NativeHost.cs' -Destination $csHostPath -Force
}

$csc = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
$smaDll = ([psobject].Assembly).Location

$cscArgs = @(
    '/nologo',
    '/target:winexe',
    '/optimize+',
    '/platform:anycpu',
    "/out:$cleanExe",
    "/win32icon:$icoPath",
    "/win32manifest:$manifestPath",
    "/resource:$payloadGz,AdobeToolkit.Payload.gz",
    "/reference:$smaDll",
    '/reference:System.dll',
    '/reference:System.Core.dll',
    '/reference:System.Drawing.dll',
    '/reference:System.Windows.Forms.dll',
    $csHostPath
)
& $csc @cscArgs
if ($LASTEXITCODE -ne 0) { throw "Native C# compilation failed with exit code $LASTEXITCODE" }

# Ky chu ky so Authenticode (Code Signing) cho ca 2 file EXE
try {
    $cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -eq 'CN=Adobe Toolkit Official Publisher' } |
        Select-Object -First 1
    if (-not $cert) {
        $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject 'CN=Adobe Toolkit Official Publisher' -CertStoreLocation 'Cert:\CurrentUser\My' -NotAfter (Get-Date).AddYears(5)
    }
    if ($cert) {
        Set-AuthenticodeSignature -FilePath $cleanExe -Certificate $cert -HashAlgorithm SHA256 | Out-Null
        Set-AuthenticodeSignature -FilePath $outExe   -Certificate $cert -HashAlgorithm SHA256 | Out-Null
        Write-Host "Signed Authenticode SHA256 on both EXEs (Thumbprint: $($cert.Thumbprint))"
    }
} catch {
    Write-Warning "Could not sign EXE: $($_.Exception.Message)"
}

# Don file tam
Remove-Item -LiteralPath $bundlePath, $payloadGz, $manifestPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $dist 'AdobeToolkit.psm1') -Force -ErrorAction SilentlyContinue

Write-Host "Built BOTH executables successfully:"
Write-Host "  1. Classic (ps2exe): $outExe"
Write-Host "  2. Clean Native C#:  $cleanExe"
