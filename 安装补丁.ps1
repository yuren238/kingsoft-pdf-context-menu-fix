# ============================================================
#  金山PDF 11.x 右键菜单修复补丁 v3
#  根因: Win11 24H2/25H2 不再解析用户级(HKCU)COM注册,
#        而金山安装器恰好把扩展CLSID只写在HKCU。
#  修法: 将CLSID补注册到机器级(HKLM)。原版菜单立即恢复。
# ============================================================
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
  exit
}
$ErrorActionPreference = 'Stop'
Write-Host '== 金山PDF 右键菜单修复补丁 v3 ==' -ForegroundColor Cyan

$clsid = '{8FE8AC65-EE7F-4C29-AF72-D2BACB633558}'

# --- 定位安装目录 ---
$o6 = $null
foreach ($uk in @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall','HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')) {
  foreach ($k in Get-ChildItem $uk -ErrorAction SilentlyContinue) {
    $dn = (Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).DisplayName
    if ($dn -match '金山PDF|Kingsoft PDF|WPS PDF') {
      $loc = (Get-ItemProperty $k.PSPath).InstallLocation
      if ($loc -and (Test-Path (Join-Path $loc 'office6\kwpspdfshellext64.dll'))) { $o6 = Join-Path $loc 'office6'; break }
    }
  }
  if ($o6) { break }
}
if (-not $o6) {
  Get-ChildItem 'C:\Program Files (x86)\Kingsoft\Kingsoft PDF' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $cand = Join-Path $_.FullName 'office6'
    if (Test-Path (Join-Path $cand 'kwpspdfshellext64.dll')) { $o6 = $cand }
  }
}
if (-not $o6) { Write-Host '[错误] 未找到金山PDF安装目录。' -ForegroundColor Red; Read-Host '回车退出'; exit 1 }
$dll = Join-Path $o6 'kwpspdfshellext64.dll'
Write-Host ("定位到扩展DLL: " + $dll)

# --- 核心修复: CLSID 补注册到 HKLM ---
$k = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey('SOFTWARE\Classes\CLSID\' + $clsid + '\InprocServer32')
$k.SetValue('', ('"' + $dll + '"'), [Microsoft.Win32.RegistryValueKind]::String)
$k.SetValue('ThreadingModel', 'Apartment', [Microsoft.Win32.RegistryValueKind]::String)
$k.Close()
Write-Host '[OK] CLSID 已补注册到 HKLM(机器级)' -ForegroundColor Green

# --- 兜底: 若右键处理器键不存在则补一个(HKLM) ---
$handlerExists = $false
foreach ($r in @('HKLM:\SOFTWARE\Classes','HKCU:\Software\Classes')) {
  foreach ($rp in @('*\shellex\ContextMenuHandlers','Directory\shellex\ContextMenuHandlers')) {
    $p = Join-Path $r $rp
    if (Test-Path -LiteralPath $p) {
      foreach ($kk in Get-ChildItem -LiteralPath $p -ErrorAction SilentlyContinue) {
        if ((Get-ItemProperty -LiteralPath $kk.PSPath -ErrorAction SilentlyContinue).'(default)' -eq $clsid) { $handlerExists = $true }
      }
    }
  }
}
if (-not $handlerExists) {
  $hk = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey('SOFTWARE\Classes\*\shellex\ContextMenuHandlers\KWPSPDFShellext')
  $hk.SetValue('', $clsid); $hk.Close()
  Write-Host '[OK] 处理器键缺失, 已补建 HKLM 唯一键'
} else {
  Write-Host '[OK] 处理器键已存在, 无需处理'
}

Write-Host ''
Write-Host '[全部完成]' -ForegroundColor Green
if ((Read-Host '立即重启资源管理器使菜单恢复? (Y/N)') -eq 'Y') {
  Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
  Start-Sleep 2
  if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
}
Read-Host '回车退出'
