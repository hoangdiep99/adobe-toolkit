<#
 AdobeToolkit.GUI.ps1 - Giao dien tieng Viet (Chong do / Async Runspace + DoubleBuffered + Custom Icon)
 Chay: powershell -ExecutionPolicy Bypass -File .\AdobeToolkit.GUI.ps1
 Khong thay doi gi cho den khi nguoi dung tick chon VA xac nhan.
#>
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
if (-not (Get-Command Initialize-Session -ErrorAction SilentlyContinue)) {
    Import-Module (Join-Path $here 'AdobeToolkit.psm1') -Force
}

$script:here = $here
$script:session = Initialize-Session
$script:cleanerExe = $null
foreach ($c in @((Join-Path $here 'AdobeCreativeCloudCleanerTool.exe'),
                 (Join-Path $env:USERPROFILE 'Downloads\AdobeCreativeCloudCleanerTool.exe'),
                 (Join-Path $env:USERPROFILE 'Downloads\Programs\AdobeCreativeCloudCleanerTool.exe'),
                 (Join-Path $env:USERPROFILE 'Desktop\AdobeCreativeCloudCleanerTool.exe'))) {
    if (Test-Path $c) { $script:cleanerExe = $c; break }
}

# ---- Chuan bi script nen cho Background Runspace (chong do UI 100%)
$script:CoreFnNames = @(
    'Write-Log', 'Get-AdobeBusyProcesses', 'Stop-AdobeProcesses', 'Get-InstalledAdobe',
    'Get-AdobeMainBinaries', 'Get-AdobeFirewallBlockRules', 'Test-ImsTcpFast',
    'Get-TamperedAdobeFiles', 'Get-Diagnostics', 'Get-SignInFolders',
    'Get-AdobeCredentialTargets', 'Initialize-Win32Cred', 'ConvertFrom-AppInfoName', 'Get-FriendlyAppName',
    'Get-SignInGroups', 'Get-ProdInstallListXml', 'Get-EmbeddedLeftoverCatalog', 'Get-TokenMap', 'Test-SafeToRemove',
    'Get-SharedComponentPatterns', 'Test-InUse', 'Test-SafeRegistryKey',
    'Get-LeftoverTargets', 'Get-IntegrityIssues', 'Get-BackupSessions', 'Save-BackupRecord', 'Invoke-ManualBackup'
)
$script:CoreInitScript = "Set-StrictMode -Version 2; `$script:LogFile = `$null;`r`n" + (
    ($script:CoreFnNames | ForEach-Object {
        $cmd = Get-Command $_ -CommandType Function -ErrorAction SilentlyContinue
        if ($cmd) { "function $($cmd.Name) {`r`n$($cmd.Definition)`r`n}" }
    }) -join "`r`n"
)

# ---- bang mau / font
$cNav    = [Drawing.Color]::FromArgb(24, 33, 51)
$cNavSel = [Drawing.Color]::FromArgb(45, 62, 95)
$cAccent = [Drawing.Color]::FromArgb(37, 99, 235)
$cDanger = [Drawing.Color]::FromArgb(185, 28, 28)
$cBg     = [Drawing.Color]::FromArgb(245, 247, 250)
$cOk     = [Drawing.Color]::FromArgb(22, 128, 61)
$cWarn   = [Drawing.Color]::FromArgb(194, 98, 0)
$cMuted  = [Drawing.Color]::FromArgb(107, 114, 128)
$fUi     = New-Object Drawing.Font('Segoe UI', 10)
$fTitle  = New-Object Drawing.Font('Segoe UI Semibold', 16)
$fBrand  = New-Object Drawing.Font('Segoe UI Semibold', 14)
$fSub    = New-Object Drawing.Font('Segoe UI', 9)
$fMono   = New-Object Drawing.Font('Consolas', 9)

function Enable-DoubleBuffer($ctrl) {
    try {
        $prop = $ctrl.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance,NonPublic')
        if ($prop) { $prop.SetValue($ctrl, $true, $null) }
    } catch { }
}

$form = New-Object Windows.Forms.Form
$form.Text = 'Adobe Toolkit - Chẩn đoán & Sửa lỗi Adobe'
$form.Size = New-Object Drawing.Size(1060, 720); $form.MinimumSize = New-Object Drawing.Size(940, 620)
$form.StartPosition = 'CenterScreen'; $form.Font = $fUi; $form.BackColor = $cBg
Enable-DoubleBuffer $form

# ---- Tai icon cua app (tu file app.ico hoac tu chinh file EXE dang chay)
$script:appIcon = $null
try {
    $icoFile = Join-Path $here 'app.ico'
    if (Test-Path -LiteralPath $icoFile) {
        $script:appIcon = New-Object System.Drawing.Icon($icoFile, 64, 64)
    } else {
        $exePath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ($exePath -and (Test-Path -LiteralPath $exePath)) {
            $script:appIcon = [System.Drawing.Icon]::ExtractAssociatedIcon($exePath)
        }
    }
    if ($script:appIcon) { $form.Icon = $script:appIcon }
} catch { }

# ---- nhat ky + thanh tien trinh chong do (duoi cung)
$logPanel = New-Object Windows.Forms.Panel; $logPanel.Dock = 'Bottom'; $logPanel.Height = 138; $logPanel.Padding = '12,4,12,10'
$progBar = New-Object Windows.Forms.ProgressBar
$progBar.Dock = 'Top'; $progBar.Height = 6; $progBar.Style = 'Marquee'; $progBar.MarqueeAnimationSpeed = 25; $progBar.Visible = $false
$logBox = New-Object Windows.Forms.TextBox
$logBox.Multiline = $true; $logBox.ReadOnly = $true; $logBox.ScrollBars = 'Vertical'; $logBox.Dock = 'Fill'
$logBox.Font = $fMono; $logBox.BackColor = [Drawing.Color]::White; $logBox.BorderStyle = 'FixedSingle'
$logCap = New-Object Windows.Forms.Label; $logCap.Dock = 'Top'; $logCap.Height = 20; $logCap.ForeColor = $cMuted; $logCap.Font = $fSub
$logCap.Text = "Nhật ký & Sao lưu: $($script:session)"
$logPanel.Controls.Add($logBox)
$logPanel.Controls.Add($progBar)
$logPanel.Controls.Add($logCap)

# ---- thanh dieu huong (trai) kem Logo
$nav = New-Object Windows.Forms.Panel; $nav.Dock = 'Left'; $nav.Width = 225; $nav.BackColor = $cNav
$brandHeader = New-Object Windows.Forms.Panel; $brandHeader.Dock = 'Top'; $brandHeader.Height = 84
if ($script:appIcon) {
    $picLogo = New-Object Windows.Forms.PictureBox
    $picLogo.Left = 16; $picLogo.Top = 18; $picLogo.Width = 46; $picLogo.Height = 46
    $picLogo.SizeMode = 'Zoom'
    try { $picLogo.Image = $script:appIcon.ToBitmap() } catch { }
    $brandHeader.Controls.Add($picLogo)
}
$brand = New-Object Windows.Forms.Label; $brand.Text = "Adobe`r`nToolkit"; $brand.ForeColor = 'White'
$brand.Font = $fBrand; $brand.Left = $(if ($script:appIcon) { 72 } else { 18 }); $brand.Top = 15; $brand.Width = 140; $brand.Height = 56
$brandHeader.Controls.Add($brand)
$nav.Controls.Add($brandHeader)

# ---- nut dong nhanh tien trinh Adobe o duoi thanh dieu huong
$btnKillNav = New-Object Windows.Forms.Button
$btnKillNav.Text = '⏹ Đóng tiến trình Adobe'; $btnKillNav.Dock = 'Bottom'; $btnKillNav.Height = 44
$btnKillNav.FlatStyle = 'Flat'; $btnKillNav.FlatAppearance.BorderSize = 0
$btnKillNav.BackColor = $cDanger; $btnKillNav.ForeColor = 'White'; $btnKillNav.Cursor = 'Hand'; $btnKillNav.Font = $fUi
$nav.Controls.Add($btnKillNav)

# ---- khu noi dung
$content = New-Object Windows.Forms.Panel; $content.Dock = 'Fill'; $content.Padding = '20,16,20,6'
Enable-DoubleBuffer $content

$form.Controls.Add($content); $form.Controls.Add($logPanel); $form.Controls.Add($nav)

function Say([string]$m) { $logBox.AppendText("$(Get-Date -Format 'HH:mm:ss')  $m`r`n"); Write-Log $m }
function Ask([string]$text) { [Windows.Forms.MessageBox]::Show($text, 'Xác nhận', 'YesNo', 'Warning') -eq 'Yes' }
function Info([string]$text, [string]$title = 'Adobe Toolkit') { [void][Windows.Forms.MessageBox]::Show($text, $title, 'OK', 'Information') }
function Fail([string]$text) { Say "LỖI: $text"; [void][Windows.Forms.MessageBox]::Show($text, 'Lỗi', 'OK', 'Error') }

# ---- Bo dieu phoi tac vu chay ngam (Background Runspace - Chong do giao dien)
$script:bgJob = $null
$script:bgTimer = New-Object Windows.Forms.Timer
$script:bgTimer.Interval = 50
$script:bgTimer.Add_Tick({
    if (-not $script:bgJob) { $script:bgTimer.Stop(); return }
    if (-not $script:bgJob.Handle.IsCompleted) { return }
    $job = $script:bgJob
    $script:bgJob = $null
    $script:bgTimer.Stop()
    $progBar.Visible = $false
    $logCap.Text = "Nhật ký & Sao lưu: $($script:session)"
    if ($job.Button) { $job.Button.Enabled = $true }
    try {
        $res = $job.PS.EndInvoke($job.Handle)
        $errs = @($job.PS.Streams.Error)
        if ($errs.Count -gt 0 -and (-not $res -or $res.Count -eq 0)) {
            Fail $errs[0].Exception.Message
        } else {
            & $job.OnSuccess $res
        }
    } catch {
        Fail $_.Exception.Message
    } finally {
        try { $job.PS.Dispose() } catch { }
    }
})

function Start-AsyncScan {
    param(
        [Parameter(Mandatory)][string]$CommandText,
        [hashtable]$Arguments = @{},
        [Parameter(Mandatory)][scriptblock]$OnSuccess,
        $TriggerButton = $null,
        [string]$StatusText = 'Đang quét ngầm (giao diện vẫn thao tác bình thường)...'
    )
    if ($script:bgJob) {
        Say 'Đang có một tác vụ quét chạy ngầm, vui lòng đợi vài giây...'
        return
    }
    if ($TriggerButton) { $TriggerButton.Enabled = $false }
    $progBar.Visible = $true
    $logCap.Text = "⏳ $StatusText"
    $ps = [powershell]::Create()
    [void]$ps.AddScript($script:CoreInitScript + "`r`n" + $CommandText)
    foreach ($k in $Arguments.Keys) { $ps.Runspace.SessionStateProxy.SetVariable($k, $Arguments[$k]) }
    $handle = $ps.BeginInvoke()
    $script:bgJob = [pscustomobject]@{
        PS        = $ps
        Handle    = $handle
        OnSuccess = $OnSuccess
        Button    = $TriggerButton
    }
    $script:bgTimer.Start()
}

$form.Add_FormClosing({
    $script:bgTimer.Stop()
    if ($script:bgJob) {
        try { $script:bgJob.PS.Stop(); $script:bgJob.PS.Dispose() } catch { }
        $script:bgJob = $null
    }
})

function Invoke-KillAdobeUi {
    $running = @(Get-AdobeBusyProcesses | Select-Object -ExpandProperty Name -Unique)
    if (-not $running.Count) {
        Say 'Không có tiến trình Adobe nào đang chạy.'
        Info 'Hiện không có tiến trình Adobe nào đang mở.'
        return
    }
    if (-not (Ask ("Đóng tất cả tiến trình Adobe đang mở?`n`n- " + ($running -join "`n- ")))) { return }
    $stopped = @(Stop-AdobeProcesses)
    Say ("Đã đóng tiến trình Adobe: " + $(if ($stopped.Count) { $stopped -join ', ' } else { 'Hoàn tất' }))
    Info ("Đã đóng: " + ($stopped -join ', '))
}
$btnKillNav.Add_Click({ Invoke-KillAdobeUi })

function New-Page([string]$title, [string]$subtitle) {
    $p = New-Object Windows.Forms.Panel; $p.Dock = 'Fill'; $p.Visible = $false
    Enable-DoubleBuffer $p
    $h = New-Object Windows.Forms.Label; $h.Text = $title; $h.Font = $fTitle; $h.Left = 0; $h.Top = 0; $h.AutoSize = $true
    $s = New-Object Windows.Forms.Label; $s.Text = $subtitle; $s.Font = $fSub; $s.ForeColor = $cMuted
    $s.Left = 2; $s.Top = 40; $s.Width = 760; $s.Height = 36
    $p.Controls.AddRange(@($h, $s)); $content.Controls.Add($p); $p
}
function New-Btn($parent, [string]$text, [int]$x, [int]$w, [bool]$primary = $false) {
    $b = New-Object Windows.Forms.Button; $b.Text = $text; $b.Left = $x; $b.Top = 82; $b.Width = $w; $b.Height = 34
    $b.FlatStyle = 'Flat'; $b.Cursor = 'Hand'; $b.FlatAppearance.BorderSize = 1
    if ($primary) { $b.BackColor = $cAccent; $b.ForeColor = 'White'; $b.FlatAppearance.BorderColor = $cAccent }
    else { $b.BackColor = 'White'; $b.ForeColor = [Drawing.Color]::FromArgb(31, 41, 55); $b.FlatAppearance.BorderColor = [Drawing.Color]::FromArgb(209, 213, 219) }
    $parent.Controls.Add($b); $b
}
function New-List($parent, $columns) {
    $l = New-Object Windows.Forms.ListView
    $l.View = 'Details'; $l.FullRowSelect = $true; $l.GridLines = $false; $l.HideSelection = $false
    $l.Left = 0; $l.Top = 128; $l.Width = $parent.Width; $l.Height = $parent.Height - 134
    $l.Anchor = 'Top,Left,Right,Bottom'; $l.BorderStyle = 'FixedSingle'; $l.BackColor = 'White'
    Enable-DoubleBuffer $l
    foreach ($c in $columns) { [void]$l.Columns.Add($c[0], $c[1]) }
    $parent.Controls.Add($l); $l
}

$pages = @{}; $navBtns = @{}
function Show-Page([string]$key) {
    foreach ($k in $pages.Keys) { $pages[$k].Visible = ($k -eq $key); $navBtns[$k].BackColor = $(if ($k -eq $key) { $cNavSel } else { $cNav }) }
}
function Add-Nav([string]$key, [string]$text, [int]$top) {
    $b = New-Object Windows.Forms.Button; $b.Text = "   $text"; $b.TextAlign = 'MiddleLeft'
    $b.Left = 0; $b.Top = $top; $b.Width = 225; $b.Height = 46; $b.FlatStyle = 'Flat'; $b.FlatAppearance.BorderSize = 0
    $b.ForeColor = 'White'; $b.BackColor = $cNav; $b.Cursor = 'Hand'; $b.Font = $fUi
    $b.Add_Click({ Show-Page $this.Tag }); $b.Tag = $key
    $nav.Controls.Add($b); $navBtns[$key] = $b
}
Add-Nav 'diag'  '1.  Chẩn đoán máy'         92
Add-Nav 'sign'  '2.  Sửa lỗi đăng nhập'     138
Add-Nav 'orig'  '3.  Khôi phục nguyên bản'  184
Add-Nav 'left'  '4.  Dọn dữ liệu còn sót'   230
Add-Nav 'undo'  '5.  Hoàn tác / Sao lưu'    276

# ===================================================== Trang 1: chan doan
$p1 = New-Page 'Chẩn đoán máy' 'Kiểm tra giờ máy, file hosts, tường lửa, chữ ký số file Adobe (.bak/patch) và token đăng nhập. Chạy ngầm không đơ máy.'
$pages['diag'] = $p1
$btnDiag = New-Btn $p1 'Chạy chẩn đoán' 0 150 $true
$btnSave = New-Btn $p1 'Lưu báo cáo (JSON)' 160 175
$btnKill1 = New-Btn $p1 'Đóng tiến trình Adobe' 345 185
$list1 = New-List $p1 @(@('Hạng mục', 235), @('Kết quả', 120), @('Chi tiết', 440))
$script:diag = $null

function Add-Row($l, [string[]]$cells, $color) {
    $it = New-Object Windows.Forms.ListViewItem($cells[0]); [void]$it.SubItems.Add($cells[1]); [void]$it.SubItems.Add($cells[2])
    $it.SubItems[1].ForeColor = $color; $it.UseItemStyleForSubItems = $false; [void]$l.Items.Add($it)
}
$btnDiag.Add_Click({
    Say 'Đang chạy chẩn đoán ngầm...'
    Start-AsyncScan -CommandText 'Get-Diagnostics' -TriggerButton $btnDiag -StatusText 'Đang kiểm tra hệ thống, chữ ký số và kết nối Adobe...' -OnSuccess {
        param($res)
        $d = $res | Select-Object -First 1
        $script:diag = $d
        $list1.BeginUpdate()
        try {
            $list1.Items.Clear()
            Add-Row $list1 @('Hệ điều hành', 'Thông tin', [string]$d.OS) $cMuted
            Add-Row $list1 @('Giờ máy / múi giờ', 'Thông tin', "$($d.Time)  ($($d.TimeZone))") $cMuted
            Add-Row $list1 @('Quyền quản trị', $(if ($d.IsAdmin) { '✔ Có' } else { '⚠ Không' }), $(if ($d.IsAdmin) { '' } else { 'Chạy bằng quyền Admin để dọn thư mục trong Program Files.' })) $(if ($d.IsAdmin) { $cOk } else { $cWarn })
            $hn = @($d.HostsAdobeEntries).Count
            Add-Row $list1 @('File hosts chặn Adobe', $(if ($hn) { '⚠ Có' } else { '✔ Không' }), $(if ($hn) { ($d.HostsAdobeEntries -join ' | ') } else { 'Không có dòng nào liên quan Adobe.' })) $(if ($hn) { $cWarn } else { $cOk })
            $fwn = @($d.FirewallBlocks).Count
            Add-Row $list1 @('Tường lửa chặn Adobe', $(if ($fwn) { "⚠ $fwn rule" } else { '✔ Không' }), $(if ($fwn) { ($d.FirewallBlocks -join ' | ') } else { 'Không có rule chặn kết nối.' })) $(if ($fwn) { $cWarn } else { $cOk })
            Add-Row $list1 @('Proxy hệ thống', $(if ($d.WinHttpProxy -eq 'direct') { '✔ Trực tiếp' } else { '⚠ Có proxy' }), [string]$d.WinHttpProxy) $(if ($d.WinHttpProxy -eq 'direct') { $cOk } else { $cWarn })
            Add-Row $list1 @('Kết nối máy chủ đăng nhập Adobe', $(if ($d.ImsReachable) { '✔ Được' } else { '⚠ Không' }), 'ims-na1.adobelogin.com : 443') $(if ($d.ImsReachable) { $cOk } else { $cWarn })
            $pn = @($d.AdobeProcesses).Count
            Add-Row $list1 @('App Adobe đang mở', $(if ($pn) { '⚠ Có' } else { '✔ Không' }), $(if ($pn) { ($d.AdobeProcesses -join ', ') } else { '' })) $(if ($pn) { $cWarn } else { $cOk })
            $tn = @($d.TamperedFiles).Count
            Add-Row $list1 @('File Adobe bị sửa / patch', $(if ($tn) { "⚠ $tn file" } else { '✔ Nguyên vẹn' }), $(if ($tn) { 'Xem mục 3. Khôi phục nguyên bản để xử lý' } else { 'Chữ ký số Adobe hợp lệ, không có file .bak.' })) $(if ($tn) { $cWarn } else { $cOk })
            foreach ($tf in @($d.TamperedFiles)) { Add-Row $list1 @('  ↳ Chi tiết file can thiệp', '⚠ Đã sửa/bak', [string]$tf) $cWarn }
            Add-Row $list1 @('Mục đăng nhập Adobe (Credential)', 'Thông tin', "$($d.CredentialEntries) mục ($(@($d.DeviceTokens).Count) device_token)") $cMuted
            Add-Row $list1 @('Tài khoản lưu trong OOBE (GUID)', 'Thông tin', $(if (@($d.OobeAccountGuids).Count) { ($d.OobeAccountGuids -join ', ') } else { 'Trống' })) $cMuted
            foreach ($a in @($d.InstalledAdobe)) { Add-Row $list1 @('Đã cài', 'Thông tin', [string]$a) $cMuted }
        } finally {
            $list1.EndUpdate()
        }
        Say 'Chẩn đoán xong.'
    }
})
$btnSave.Add_Click({
    if ($script:diag) {
        $f = Export-Report -Diagnostics $script:diag -Directory $script:here
        Say "Đã lưu báo cáo: $f"; Info "Đã lưu báo cáo:`n$f`n`nGửi file này cho kỹ thuật viên nếu cần."
        return
    }
    Say 'Đang lấy dữ liệu chẩn đoán để lưu báo cáo...'
    Start-AsyncScan -CommandText 'Get-Diagnostics' -TriggerButton $btnSave -StatusText 'Đang thu thập thông tin báo cáo...' -OnSuccess {
        param($res)
        $script:diag = $res | Select-Object -First 1
        $f = Export-Report -Diagnostics $script:diag -Directory $script:here
        Say "Đã lưu báo cáo: $f"; Info "Đã lưu báo cáo:`n$f`n`nGửi file này cho kỹ thuật viên nếu cần."
    }
})
$btnKill1.Add_Click({ Invoke-KillAdobeUi })

# ===================================================== Trang 2: sua dang nhap (theo tung app)
$p2 = New-Page 'Sửa lỗi đăng nhập' 'Tích chọn app cần làm sạch. Chỉ các app được chọn bị đăng xuất, có sao lưu. Hãy đóng các tiến trình Adobe trước khi dọn.'
$pages['sign'] = $p2
$btnScan2  = New-Btn $p2 'Quét' 0 90 $true
$btnLr     = New-Btn $p2 'Chỉ Lightroom' 100 130
$btnAll    = New-Btn $p2 'Chọn tất cả' 240 120
$btnNone   = New-Btn $p2 'Bỏ chọn' 370 100
$btnApply2 = New-Btn $p2 'Dọn app đã chọn' 480 170; $btnApply2.Enabled = $false

$apps = New-List $p2 @(@('Ứng dụng', 230), @('Mục đăng nhập', 115), @('Thư mục', 75), @('Ảnh hưởng', 370))
$apps.CheckBoxes = $true; $apps.Height = 168; $apps.Anchor = 'Top,Left,Right'

$dcap = New-Object Windows.Forms.Label; $dcap.Left = 0; $dcap.Top = 304; $dcap.Width = 600; $dcap.Height = 20; $dcap.Font = $fSub; $dcap.ForeColor = $cMuted
$dcap.Text = 'Chi tiết các mục sẽ bị dọn (theo app đã tích):'; $p2.Controls.Add($dcap)
$detail = New-List $p2 @(@('Loại', 100), @('Mục', 700))
$detail.Top = 326; $detail.Height = $p2.Height - 332; $detail.Anchor = 'Top,Left,Right,Bottom'
$script:groups = @(); $script:busyScan = $false

function Get-GroupNote($g) {
    if ($g.Shared)               { return 'Đăng xuất TẤT CẢ app Adobe (thông tin tài khoản chung)' }
    if ($g.Key -eq 'accc')       { return 'Chỉ là bộ nhớ đệm Adobe Stock / plugin, thường không liên quan lỗi đăng nhập' }
    if ($g.Key -eq 'other')      { return 'Các mục Adobe khác' }
    if ($g.Name -eq 'Creative Cloud') { return 'Đăng nhập của app Creative Cloud (OOBE + dữ liệu đăng nhập)' }
    return 'Chỉ đăng xuất app này'
}
function Update-Detail {
    if ($script:busyScan) { return }
    $detail.BeginUpdate()
    try {
        $detail.Items.Clear()
        $n = 0
        foreach ($it in $apps.CheckedItems) {
            $n++; $g = $it.Tag
            foreach ($f in $g.Folders)     { $r = New-Object Windows.Forms.ListViewItem('Thư mục');  [void]$r.SubItems.Add($f); [void]$detail.Items.Add($r) }
            foreach ($c in $g.Credentials) { $r = New-Object Windows.Forms.ListViewItem('Đăng nhập'); [void]$r.SubItems.Add($c); [void]$detail.Items.Add($r) }
        }
        $btnApply2.Enabled = $n -gt 0
    } finally {
        $detail.EndUpdate()
    }
}
function Set-AppChecks([scriptblock]$rule) {
    $script:busyScan = $true
    $apps.BeginUpdate()
    try {
        foreach ($it in $apps.Items) { $it.Checked = [bool](& $rule $it.Tag) }
    } finally {
        $apps.EndUpdate()
        $script:busyScan = $false
    }
    Update-Detail
}
$btnScan2.Add_Click({
    Start-AsyncScan -CommandText 'Get-SignInGroups' -TriggerButton $btnScan2 -StatusText 'Đang quét danh sách đăng nhập Adobe...' -OnSuccess {
        param($res)
        $script:groups = @($res)
        $script:busyScan = $true
        $apps.BeginUpdate()
        try {
            $apps.Items.Clear()
            foreach ($g in $script:groups) {
                $it = New-Object Windows.Forms.ListViewItem([string]$g.Name)
                [void]$it.SubItems.Add([string]@($g.Credentials).Count); [void]$it.SubItems.Add([string]@($g.Folders).Count); [void]$it.SubItems.Add((Get-GroupNote $g))
                $it.Tag = $g; if ($g.Shared) { $it.ForeColor = $cWarn }
                [void]$apps.Items.Add($it)
            }
        } finally {
            $apps.EndUpdate()
            $script:busyScan = $false
        }
        Update-Detail
        Say ("Quét đăng nhập: {0} app/nhóm." -f $script:groups.Count)
    }
})
$apps.Add_ItemChecked({ Update-Detail })
$btnLr.Add_Click({ Set-AppChecks { param($g) $g.Key -eq 'app:LightroomClassic' } })
$btnAll.Add_Click({ Set-AppChecks { param($g) $true } })
$btnNone.Add_Click({ Set-AppChecks { param($g) $false } })
$btnApply2.Add_Click({
    $sel = @($apps.CheckedItems | ForEach-Object { $_.Tag })
    if (-not $sel.Count) { Info 'Chưa chọn app nào.'; return }
    $names = ($sel | ForEach-Object { $_.Name }) -join ', '
    $warn = if (@($sel | Where-Object Shared).Count) { "CẢNH BÁO: bạn đã chọn thông tin tài khoản chung, TẤT CẢ app Adobe sẽ bị đăng xuất.`n`n" } else { '' }
    if (-not (Ask "${warn}Sẽ làm sạch đăng nhập của:`n$names`n`nThư mục được chuyển vào sao lưu, mục đăng nhập sẽ bị xoá. Sau đó cần đăng nhập Adobe lại. Tiếp tục?")) { return }
    try {
        $res = Invoke-SignInGroups -Groups $sel -SessionDir $script:session -Apply
        Say "Hoàn tất ($names): $($res.Credentials.Count) mục đăng nhập, $($res.Folders.Count) thư mục. Sao lưu: $($res.Backup)"
        $script:busyScan = $true; $apps.Items.Clear(); $detail.Items.Clear(); $script:busyScan = $false; $btnApply2.Enabled = $false
        Info "Hoàn tất.`n`nMở Creative Cloud, đăng nhập lại, rồi mở app cần dùng.`nSao lưu: $($res.Backup)"
    } catch { Fail $_.Exception.Message }
})

# ===================================================== Trang 3: khoi phuc nguyen ban (khử patch .bak / hosts / firewall)
$pOrig = New-Page 'Khôi phục nguyên bản (Khử Patch & Mở chặn mạng)' 'Tự động trả lại file .bak gốc có chữ ký số của Adobe, xoá dòng chặn Adobe trong file hosts và tắt rule tường lửa chặn kết nối.'
$pages['orig'] = $pOrig
$btnScanOrig  = New-Btn $pOrig 'Quét dấu vết Patch / Chặn' 0 210 $true
$btnApplyOrig = New-Btn $pOrig 'Khôi phục mục đã chọn' 222 190; $btnApplyOrig.Enabled = $false
$listOrig = New-List $pOrig @(@('Hạng mục', 145), @('Đối tượng', 360), @('Hành động / Ghi chú', 310))
$listOrig.CheckBoxes = $true
$script:origIssues = @()

$btnScanOrig.Add_Click({
    Start-AsyncScan -CommandText 'Get-IntegrityIssues' -TriggerButton $btnScanOrig -StatusText 'Đang kiểm tra chữ ký số file .bak, hosts và tường lửa...' -OnSuccess {
        param($res)
        $script:origIssues = @($res)
        $listOrig.BeginUpdate()
        try {
            $listOrig.Items.Clear()
            foreach ($iss in $script:origIssues) {
                $it = New-Object Windows.Forms.ListViewItem([string]$iss.Label)
                [void]$it.SubItems.Add([string]$iss.Display); [void]$it.SubItems.Add([string]$iss.Note)
                $it.Tag = $iss; $it.UseItemStyleForSubItems = $true
                if ($iss.CanFix) { $it.ForeColor = $cWarn; $it.Checked = $true }
                else { $it.ForeColor = $cMuted; $it.Checked = $false }
                [void]$listOrig.Items.Add($it)
            }
        } finally {
            $listOrig.EndUpdate()
        }
        $fixableCount = @($script:origIssues | Where-Object CanFix).Count
        $btnApplyOrig.Enabled = $fixableCount -gt 0
        Say ("Quét nguyên bản: {0} phát hiện ({1} mục có thể khôi phục tự động)." -f $script:origIssues.Count, $fixableCount)
        if (-not $script:origIssues.Count) { Info 'Không phát hiện file .bak, dòng chặn hosts hay rule tường lửa chặn Adobe nào.' }
    }
})
$listOrig.Add_ItemCheck({
    param($s, $e)
    if ($e.NewValue -eq 'Checked' -and (-not $listOrig.Items[$e.Index].Tag.CanFix)) { $e.NewValue = 'Unchecked' }
})
$btnApplyOrig.Add_Click({
    $picked = @($listOrig.CheckedItems | ForEach-Object { $_.Tag } | Where-Object { $_.CanFix })
    if (-not $picked.Count) { Info 'Chưa chọn mục nào có thể khôi phục tự động.'; return }
    if (-not (Ask "Khôi phục $($picked.Count) mục đã chọn về nguyên bản (file gốc .bak / hosts / tường lửa)?`n`nTrạng thái hiện tại sẽ được sao lưu để có thể hoàn tác.")) { return }
    try {
        $done = Invoke-IntegrityRepair -Items $picked -SessionDir $script:session -Apply
        Say "Đã khôi phục $($done.Count) mục về nguyên bản. Sao lưu tại: $($script:session)"
        $listOrig.Items.Clear(); $btnApplyOrig.Enabled = $false
        Info "Đã khôi phục $($done.Count) mục về nguyên bản.`nSao lưu tại: $($script:session)"
    } catch { Fail $_.Exception.Message }
})

# ===================================================== Trang 4: don du lieu con sot
$p3 = New-Page 'Dọn dữ liệu còn sót (nâng cao)' 'Đối chiếu với danh sách 588 sản phẩm Adobe tích hợp sẵn. Mục thuộc app đang cài được đánh dấu "ĐANG DÙNG" và khoá bảo vệ.'
$pages['left'] = $p3
$btnScan3  = New-Btn $p3 'Quét' 0 100 $true
$btnApply3 = New-Btn $p3 'Dọn mục đã chọn' 112 170; $btnApply3.Enabled = $false
$list3 = New-List $p3 @(@('Trạng thái', 120), @('Loại', 80), @('Đường dẫn', 610))
$list3.CheckBoxes = $true
$script:targets = @()
$btnScan3.Add_Click({
    Start-AsyncScan -CommandText 'Get-LeftoverTargets' -TriggerButton $btnScan3 -StatusText 'Đang đối chiếu 588 sản phẩm Adobe tích hợp sẵn (chạy ngầm)...' -OnSuccess {        param($res)
        $script:targets = @($res)
        $list3.BeginUpdate()
        try {
            $list3.Items.Clear()
            foreach ($t in ($script:targets | Sort-Object InUse, Kind, Path)) {
                $it = New-Object Windows.Forms.ListViewItem($(if ($t.InUse) { 'ĐANG DÙNG' } else { 'Còn sót' }))
                [void]$it.SubItems.Add($(if ($t.Kind -eq 'Folder') { 'Thư mục' } else { 'Registry' })); [void]$it.SubItems.Add([string]$t.Path)
                $it.Tag = $t; $it.UseItemStyleForSubItems = $true
                if ($t.InUse) { $it.ForeColor = $cMuted } else { $it.ForeColor = $cWarn; $it.Checked = $true }
                [void]$list3.Items.Add($it)
            }
        } finally {
            $list3.EndUpdate()
        }
        $btnApply3.Enabled = $list3.Items.Count -gt 0
        Say ("Quét dữ liệu sót: {0} mục, {1} đang dùng (được bảo vệ)." -f $script:targets.Count, @($script:targets | Where-Object InUse).Count)
    }
})
$list3.Add_ItemCheck({ param($s, $e) if ($e.NewValue -eq 'Checked' -and $list3.Items[$e.Index].Tag.InUse) { $e.NewValue = 'Unchecked' } })
$btnApply3.Add_Click({
    $picked = @($list3.CheckedItems | ForEach-Object { $_.Tag } | Where-Object { -not $_.InUse })
    if (-not $picked.Count) { Info 'Chưa chọn mục nào.'; return }
    if (-not (Ask "Chuyển $($picked.Count) mục vào thư mục sao lưu?`nKhóa registry sẽ được xuất ra file .reg trước khi xoá.")) { return }
    try {
        $null = Invoke-LeftoverClean -Targets $picked -SessionDir $script:session -Apply
        Say "Hoàn tất. Sao lưu trong: $($script:session)"; $list3.Items.Clear(); $btnApply3.Enabled = $false
        Info "Hoàn tất.`nSao lưu: $($script:session)"
    } catch { Fail $_.Exception.Message }
})

# ===================================================== Trang 5: hoan tac / sao luu
$pUndo = New-Page 'Hoàn tác / Sao lưu' 'Xem lại các phiên sao lưu trước đó và khôi phục lại thư mục OOBE, cache, registry hoặc cấu hình tường lửa chỉ với 1 nút bấm.'
$pages['undo'] = $pUndo
$btnCreateBk   = New-Btn $pUndo 'Tạo bản sao lưu ngay' 0 180 $true
$btnScanUndo   = New-Btn $pUndo 'Làm mới danh sách' 190 155
$btnRestore    = New-Btn $pUndo 'Khôi phục phiên đã chọn' 355 195; $btnRestore.Enabled = $false
$btnOpenFolder = New-Btn $pUndo 'Mở thư mục sao lưu' 560 165

$listUndo = New-List $pUndo @(@('Phiên sao lưu', 165), @('Thời gian', 165), @('Số mục', 80), @('Tóm tắt nội dung', 380))
$listUndo.Height = 165; $listUndo.Anchor = 'Top,Left,Right'

$ucap = New-Object Windows.Forms.Label; $ucap.Left = 0; $ucap.Top = 300; $ucap.Width = 600; $ucap.Height = 20; $ucap.Font = $fSub; $ucap.ForeColor = $cMuted
$ucap.Text = 'Chi tiết các mục trong phiên sao lưu đang chọn:'; $pUndo.Controls.Add($ucap)
$listUndoDetail = New-List $pUndo @(@('Loại', 130), @('Đường dẫn gốc / Đối tượng', 670))
$listUndoDetail.Top = 322; $listUndoDetail.Height = $pUndo.Height - 328; $listUndoDetail.Anchor = 'Top,Left,Right,Bottom'

function Refresh-UndoList {
    $listUndoDetail.Items.Clear(); $btnRestore.Enabled = $false
    Start-AsyncScan -CommandText 'Get-BackupSessions' -TriggerButton $btnScanUndo -StatusText 'Đang đọc danh sách các phiên sao lưu...' -OnSuccess {
        param($res)
        $sessions = @($res)
        $listUndo.BeginUpdate()
        try {
            $listUndo.Items.Clear()
            foreach ($s in $sessions) {
                $it = New-Object Windows.Forms.ListViewItem([string]$s.Id)
                [void]$it.SubItems.Add([string]$s.Time); [void]$it.SubItems.Add([string]$s.Count); [void]$it.SubItems.Add([string]$s.Summary)
                $it.Tag = $s; [void]$listUndo.Items.Add($it)
            }
        } finally {
            $listUndo.EndUpdate()
        }
        Say ("Danh sách sao lưu: {0} phiên có dữ liệu." -f $sessions.Count)
    }
}
$btnCreateBk.Add_Click({
    Say 'Đang tạo bản sao lưu trạng thái Adobe hiện tại...'
    Start-AsyncScan -CommandText 'Invoke-ManualBackup' -TriggerButton $btnCreateBk -StatusText 'Đang sao lưu OOBE, cấu hình Lightroom, Registry Adobe và file hosts...' -OnSuccess {
        param($res)
        $bkDir = $res | Select-Object -First 1
        Say "Đã tạo bản sao lưu thủ công tại: $bkDir"
        Refresh-UndoList
        Info "Đã tạo bản sao lưu thành công!`n`nThư mục: $bkDir"
    }
})
$btnScanUndo.Add_Click({ Refresh-UndoList })
$listUndo.Add_SelectedIndexChanged({
    $listUndoDetail.BeginUpdate()
    try {
        $listUndoDetail.Items.Clear()
        if ($listUndo.SelectedItems.Count -eq 0) { $btnRestore.Enabled = $false; return }
        $s = $listUndo.SelectedItems[0].Tag
        $btnRestore.Enabled = $true
        foreach ($e in $s.Entries) {
            $r = New-Object Windows.Forms.ListViewItem([string]$e.Kind)
            [void]$r.SubItems.Add([string]$e.Source)
            [void]$listUndoDetail.Items.Add($r)
        }
    } finally {
        $listUndoDetail.EndUpdate()
    }
})
$btnRestore.Add_Click({
    if ($listUndo.SelectedItems.Count -eq 0) { return }
    $s = $listUndo.SelectedItems[0].Tag
    if (-not (Ask "Khôi phục $($s.Count) mục từ phiên sao lưu $($s.Id) ($($s.Summary)) về vị trí ban đầu?")) { return }
    try {
        $n = Restore-BackupSession -BackupSession $s
        Say "Đã hoàn tác $n mục từ phiên $($s.Id)."
        Refresh-UndoList
        Info "Đã khôi phục $n mục từ phiên $($s.Id)."
    } catch { Fail $_.Exception.Message }
})
$btnOpenFolder.Add_Click({
    $root = Join-Path $env:ProgramData 'AdobeToolkit'
    if ($listUndo.SelectedItems.Count -gt 0) { $root = $listUndo.SelectedItems[0].Tag.Path }
    if (Test-Path -LiteralPath $root) { Start-Process explorer.exe -ArgumentList "`"$root`"" }
})

Show-Page 'diag'
Say "Sẵn sàng. Thư mục phiên làm việc: $($script:session)"
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Say 'Lưu ý: chưa có quyền Admin - một số thư mục trong Program Files có thể không dọn được.'
}
[void]$form.ShowDialog()
