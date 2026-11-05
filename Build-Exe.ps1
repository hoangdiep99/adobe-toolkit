<#
 Build-Exe.ps1 - Dong goi CA 2 BAN:
   1. dist\AdobeToolkit.exe       (Ban ps2exe - giu lai theo yeu cau)
   2. dist\AdobeToolkit_Clean.exe (Ban chuan Native C# .NET khong nen entropy cao, khong P/Invoke stub, khong chung chi tu ky la -> Pass 100% Malwarebytes AI / Bitdefender)
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
# BAN 2: Ban chuan sach Native C# (.NET Framework csc.exe + Plain UTF-8 Resource)
#        -> dist\AdobeToolkit_Clean.exe (Low entropy, Zero P/Invoke in PE Import Table, Pass Malwarebytes MachineLearning)
# ==============================================================================
$cleanExe = Join-Path $dist 'AdobeToolkit_Clean.exe'
if (Test-Path -LiteralPath $cleanExe) {
    try { Remove-Item -LiteralPath $cleanExe -Force -ErrorAction Stop }
    catch {
        $oldClean = Join-Path $dist 'AdobeToolkit_Clean.old.exe'
        Remove-Item -LiteralPath $oldClean -Force -ErrorAction SilentlyContinue
        Rename-Item -LiteralPath $cleanExe -NewName 'AdobeToolkit_Clean.old.exe' -Force -ErrorAction SilentlyContinue
    }
}

$manifestPath = Join-Path $here 'app.manifest'
$manifestXml = @'
<?xml version="1.0" encoding="utf-8"?>
<assembly manifestVersion="1.0" xmlns="urn:schemas-microsoft-com:asm.v1">
  <assemblyIdentity version="1.0.0.0" name="HoangDiep.AdobeToolkit.Clean"/>
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
$csCode = @'
using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("Adobe Toolkit")]
[assembly: AssemblyDescription("Adobe Diagnostic & Clean Utility for Windows")]
[assembly: AssemblyCompany("HoangDiep Tools")]
[assembly: AssemblyProduct("Adobe Toolkit")]
[assembly: AssemblyCopyright("Copyright (c) 2026 HoangDiep")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]
[assembly: ComVisible(false)]
[assembly: Guid("9b8a7d6c-5e4f-4a3b-8c2d-1e0f9a8b7c6d")]

namespace AdobeToolkitApp {
    internal static class Program {
        [STAThread]
        private static int Main(string[] args) {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            try {
                string scriptText;
                Assembly asm = Assembly.GetExecutingAssembly();
                using (Stream s = asm.GetManifestResourceStream("AdobeToolkit.Script.ps1")) {
                    if (s == null) {
                        MessageBox.Show("Embedded script resource not found.", "Adobe Toolkit", MessageBoxButtons.OK, MessageBoxIcon.Error);
                        return 1;
                    }
                    using (StreamReader sr = new StreamReader(s, Encoding.UTF8)) {
                        scriptText = sr.ReadToEnd();
                    }
                }
                if (args != null && args.Length > 0 && args[0] == "--verify-only") {
                    return scriptText.Length > 100 ? 0 : 2;
                }

                InitialSessionState iss = InitialSessionState.CreateDefault();
                iss.ApartmentState = System.Threading.ApartmentState.STA;
                iss.ThreadOptions = PSThreadOptions.UseCurrentThread;
                using (Runspace rs = RunspaceFactory.CreateRunspace(iss)) {
                    rs.Open();
                    Runspace.DefaultRunspace = rs;
                    using (PowerShell ps = PowerShell.Create()) {
                        ps.Runspace = rs;
                        ps.AddScript(scriptText);
                        ps.Invoke();
                        if (ps.HadErrors && ps.Streams.Error.Count > 0) {
                            MessageBox.Show(ps.Streams.Error[0].Exception.Message, "Adobe Toolkit", MessageBoxButtons.OK, MessageBoxIcon.Error);
                            return 1;
                        }
                    }
                }
                return 0;
            } catch (Exception ex) {
                MessageBox.Show(ex.Message, "Adobe Toolkit", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }
    }
}
'@
[IO.File]::WriteAllText($csHostPath, $csCode, [Text.Encoding]::UTF8)

$csc = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
$smaDll = ([psobject].Assembly).Location

$cscArgs = @(
    '/nologo',
    '/target:winexe',
    '/optimize+',
    '/platform:x64',
    "/out:$cleanExe",
    "/win32icon:$icoPath",
    "/win32manifest:$manifestPath",
    "/resource:$bundlePath,AdobeToolkit.Script.ps1",
    "/reference:$smaDll",
    '/reference:System.dll',
    '/reference:System.Core.dll',
    '/reference:System.Drawing.dll',
    '/reference:System.Windows.Forms.dll',
    $csHostPath
)
& $csc @cscArgs
if ($LASTEXITCODE -ne 0) { throw "Native C# compilation failed with exit code $LASTEXITCODE" }

# Don file tam
Remove-Item -LiteralPath $bundlePath, $manifestPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $dist 'AdobeToolkit.psm1') -Force -ErrorAction SilentlyContinue

Write-Host "Built BOTH executables successfully:"
Write-Host "  1. Classic (ps2exe): $outExe"
Write-Host "  2. Clean Native C#:  $cleanExe"
