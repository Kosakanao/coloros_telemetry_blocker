# 部署到手机（开发用）
#
#   .\deploy.ps1                       # 同步文件到已安装的模块目录（不重启）
#   .\deploy.ps1 -Zip                  # 打包后走 ksud 安装（需重启）
#   .\deploy.ps1 -Device 192.168.1.5:5555
#   .\deploy.ps1 -AdbPath "C:\platform-tools\adb.exe"
#
# 注意 system/etc/hosts 的 inode：直接 cp / push 会换 inode，导致当前开机的
# magic mount 变成孤儿（cat 正常、ping 解析到真实 IP）。所以这里先把文件
# 推到 /data/local/tmp，再用 cat > 原地覆盖。

param(
    [switch]$Zip,
    [string]$Device,
    [string]$AdbPath
)

$ErrorActionPreference = "Stop"

$root = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$mod  = "/data/adb/modules/coloros_telemetry_blocker"

# ---- 找 adb ----------------------------------------------------------------
if (-not $AdbPath) {
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) {
        $AdbPath = $cmd.Source
    } else {
        $candidates = @()
        if ($env:ANDROID_HOME)     { $candidates += (Join-Path $env:ANDROID_HOME     "platform-tools\adb.exe") }
        if ($env:ANDROID_SDK_ROOT) { $candidates += (Join-Path $env:ANDROID_SDK_ROOT "platform-tools\adb.exe") }
        $candidates += (Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe")
        $candidates += "C:\platform-tools\adb.exe"
        $AdbPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
}
if (-not $AdbPath -or -not (Test-Path $AdbPath)) {
    throw "找不到 adb，请用 -AdbPath <路径> 指定，或把它加进 PATH。"
}

$serialArgs = @()
if ($Device) { $serialArgs = @("-s", $Device) }

function Adb { & $AdbPath @serialArgs @args }
function Sh  { Adb shell su -c ($args -join " ") }

Write-Host "adb: $AdbPath" -ForegroundColor DarkGray

# ---- 安装 zip --------------------------------------------------------------
if ($Zip) {
    python (Join-Path $root "build.py")
    $zip = Get-ChildItem (Join-Path $root "dist\*.zip") | Sort-Object LastWriteTime | Select-Object -Last 1
    Write-Host "安装 $($zip.Name) ..."
    Adb push $zip.FullName /data/local/tmp/ctb.zip 2>&1 | Out-Null
    Sh "ksud module install /data/local/tmp/ctb.zip"
    Sh "rm -f /data/local/tmp/ctb.zip"
    Write-Host "安装完成，重启生效" -ForegroundColor Yellow
    exit 0
}

# ---- 同步文件 --------------------------------------------------------------
$files = @(
    @{ local = "module.prop";        remote = "$mod/module.prop" },
    @{ local = "customize.sh";       remote = "$mod/customize.sh" },
    @{ local = "README.md";          remote = "$mod/README.md" },
    @{ local = "webroot\index.html"; remote = "$mod/webroot/index.html" }
)

Sh "mkdir -p $mod/webroot" | Out-Null

foreach ($f in $files) {
    Adb push (Join-Path $root $f.local) /data/local/tmp/.ctb_push 2>&1 | Out-Null
    Sh "cp /data/local/tmp/.ctb_push $($f.remote)"
    Write-Host "  -> $($f.remote)"
}

# hosts：保留 inode
Adb push (Join-Path $root "system\etc\hosts") /data/local/tmp/.ctb_hosts 2>&1 | Out-Null
Sh "cat /data/local/tmp/.ctb_hosts > $mod/system/etc/hosts"
Write-Host "  -> $mod/system/etc/hosts (原地覆盖)"

Sh "chmod 755 $mod/customize.sh; chmod 644 $mod/module.prop $mod/README.md $mod/system/etc/hosts $mod/webroot/index.html"
Sh "chcon u:object_r:system_file:s0 $mod/system/etc/hosts"
Sh "rm -f /data/local/tmp/.ctb_push /data/local/tmp/.ctb_hosts"

Write-Host "`n同步完成。打开 模块管理器 → ColorOS Telemetry Blocker → 长按卡片" -ForegroundColor Green
