# ============================================================
#  进阶: 将右键菜单升级为中文完整版 (v4 防占用版)
#  自动查找同目录 DLL 与资源树(同级目录优先, 回退「中文升级源文件」子目录)
#  前提: 已运行过「安装补丁.cmd」(HKLM CLSID修复就位)
#  v4改进: 全盘扫描找出占用DLL的真实进程并结束 /
#          改名腾位兜底(Windows允许重命名被占用的DLL) /
#          保留v3的重试+SHA256校验+出错不闪退 /
#          源文件路径灵活: 同级目录或子目录均可, wpsufd缺失时跳过不报错
# ============================================================
$ErrorActionPreference = 'Stop'
function Pause-Exit([int]$c) { Read-Host '回车退出' | Out-Null; exit $c }

# 枚举加载了指定DLL的进程(受保护系统进程读不到模块表,自动忽略)
function Get-DllLockers([string]$path) {
  $found = @()
  foreach ($proc in Get-Process) {
    try {
      foreach ($m in $proc.Modules) {
        if ($m.FileName -and ($m.FileName -ieq $path)) { $found += $proc; break }
      }
    } catch { }
  }
  return ,$found
}

try {
  if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
  }
  $base = Split-Path $PSCommandPath

  # --- 定位源DLL: 优先脚本同级目录, 回退到「中文升级源文件」子目录 ---
  $dllSource = $null
  foreach ($cand in @(
    (Join-Path $base 'kwpspdfshellext64.dll'),
    (Join-Path $base '中文升级源文件\kwpspdfshellext64.dll')
  )) {
    if (Test-Path -LiteralPath $cand) { $dllSource = $cand; break }
  }
  if (-not $dllSource) { Write-Host '[错误] 未找到 kwpspdfshellext64.dll, 请放在脚本同级目录或「中文升级源文件」子目录中' -ForegroundColor Red; Pause-Exit 1 }

  # --- 定位资源树: 同级目录优先, 子目录回退, 找不到则跳过(仅替换DLL也可用) ---
  $resSource = $null
  foreach ($cand in @(
    (Join-Path $base 'wpsufd'),
    (Join-Path $base '中文升级源文件\wpsufd')
  )) {
    if (Test-Path -LiteralPath $cand) { $resSource = $cand; break }
  }
  if (-not $resSource) { Write-Host '[提示] 未找到 wpsufd 资源目录, 将跳过资源树部署(仅替换DLL)' -ForegroundColor Yellow }

  # --- 定位安装目录: 优先读HKLM CLSID(最可靠), 失败再扫描 ---
  $o6 = $null
  $inproc = (Get-ItemProperty -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\{8FE8AC65-EE7F-4C29-AF72-D2BACB633558}\InprocServer32' -ErrorAction SilentlyContinue).'(default)'
  if ($inproc) {
    $p = $inproc.Trim('"')
    if (Test-Path -LiteralPath $p) { $o6 = Split-Path $p }
  }
  if (-not $o6) {
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
  }
  if (-not $o6) {
    Get-ChildItem 'C:\Program Files (x86)\Kingsoft\Kingsoft PDF' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      $cand = Join-Path $_.FullName 'office6'
      if (Test-Path (Join-Path $cand 'kwpspdfshellext64.dll')) { $o6 = $cand }
    }
  }
  if (-not $o6) { Write-Host '[错误] 未找到金山PDF。请先运行安装补丁.cmd确认软件已装。' -ForegroundColor Red; Pause-Exit 1 }
  $dllTarget = Join-Path $o6 'kwpspdfshellext64.dll'
  Write-Host ("目标: " + $dllTarget)

  # --- 清场: 关闭已知宿主 ---
  Stop-Process -Name wpspdf,wps -Force -ErrorAction SilentlyContinue
  Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
  Start-Sleep 2
  # 清理上次运行遗留的改名备份
  $bakDefault = "$dllTarget.locked_bak"
  if ((Test-Path -LiteralPath $bakDefault) -and (Test-Path -LiteralPath $dllTarget)) {
    Remove-Item -LiteralPath $bakDefault -Force -ErrorAction SilentlyContinue
  }

  # --- DLL替换: 每轮先动态清占用 -> 复制 -> SHA256校验, 共5轮 ---
  $srcHash = (Get-FileHash -LiteralPath $dllSource).Hash
  $ok = $false
  for ($i = 1; $i -le 5; $i++) {
    foreach ($lk in (Get-DllLockers $dllTarget)) {
      $skipList = @('system','idle','registry','smss','csrss','wininit','services','lsass','winlogon','svchost','dwm')
      if ($skipList -contains $lk.ProcessName.ToLower()) {
        Write-Host ("[跳过] 核心系统进程 " + $lk.ProcessName + "(PID " + $lk.Id + ") 占用中, 不结束") -ForegroundColor Yellow
        continue
      }
      Write-Host ("[占用] 结束进程: " + $lk.ProcessName + " (PID " + $lk.Id + ")")
      Stop-Process -Id $lk.Id -Force -ErrorAction SilentlyContinue
    }
    try {
      Copy-Item -LiteralPath $dllSource -Destination $dllTarget -Force
      if ((Get-FileHash -LiteralPath $dllTarget).Hash -eq $srcHash) { $ok = $true; break }
      Write-Host "[重试 $i] 校验不符" -ForegroundColor Yellow
    } catch { Write-Host ("[重试 $i] 仍被占用: " + $_.Exception.Message) -ForegroundColor Yellow }
    Start-Sleep 1
  }

  # --- 兜底: 改名腾位法(被占用的DLL同样允许改名, 旧句柄继续指向旧名, 新名字空出来写入) ---
  if (-not $ok) {
    Write-Host '[兜底] 多次重试后仍被占用, 改用改名腾位法...' -ForegroundColor Cyan
    $bak = "$dllTarget.locked_bak"
    Move-Item -LiteralPath $dllTarget -Destination $bak -Force
    try {
      Copy-Item -LiteralPath $dllSource -Destination $dllTarget -Force
      if ((Get-FileHash -LiteralPath $dllTarget).Hash -ne $srcHash) { throw '校验不符' }
      $ok = $true
    } catch {
      Move-Item -LiteralPath $bak -Destination $dllTarget -Force -ErrorAction SilentlyContinue
      throw ("写入失败已还原原状: " + $_.Exception.Message)
    }
    try { Remove-Item -LiteralPath $bak -Force -ErrorAction Stop } catch {
      Write-Host ("[提示] 旧版残留 " + $bak + " 因占用暂未删除, 重启后可手动删除(不影响使用)") -ForegroundColor Yellow
    }
  }
  if (-not $ok) { throw '未知错误: 替换未完成' }
  Write-Host ('[OK] 扩展DLL已更新为: ' + (Get-Item -LiteralPath $dllTarget).VersionInfo.FileVersion)

  # --- 资源树: 复制"内容"而非整个文件夹(避免嵌套成wpsufd\wpsufd) ---
  if ($resSource) {
    $resRoot = Join-Path $env:APPDATA 'kingsoft\wpsufd'
    New-Item -ItemType Directory -Force -Path $resRoot | Out-Null
    Copy-Item -Path (Join-Path $resSource '*') -Destination $resRoot -Recurse -Force
    Write-Host '[OK] 中文资源树已部署'
  }

  Start-Process explorer.exe
  Start-Sleep 2
  if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
  Write-Host ''
  Write-Host '[完成] 右键 PDF 应显示中文完整原版菜单。' -ForegroundColor Green
} catch {
  Write-Host ('[出错] ' + $_.Exception.Message) -ForegroundColor Red
  Pause-Exit 1
}
Read-Host '回车退出'
