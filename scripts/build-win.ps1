# build-win.ps1 — DataViewer-Desktop Windows 构建脚本（手工与 CI 共用）
#
# 用法（PowerShell 5.1+，需已安装 Python 3.12 与 uv）:
#   powershell -ExecutionPolicy Bypass -File build-win.ps1 `
#       -SourceDir C:\path\to\upstream-tree -Version v4.10.1-d1 [-OutputDir C:\out]
#
# 流程: 校验源码 → uv 同步后端依赖 → 前端 npm ci + build →
#       组装绿色目录（backend + frontend/dist + python/ venv + 配置模板 + README）
# 说明: 本机是 Linux dev box，此脚本只写不跑；Windows 验证走 CI（.github/workflows/windows-build.yml）。

param(
    [Parameter(Mandatory=$true)][string]$SourceDir,   # 上游基线 + 补丁 apply 后的源码树
    [Parameter(Mandatory=$true)][string]$Version,     # 如 v4.10.1-d1
    [string]$OutputDir = "$PSScriptRoot\..\build\$Version"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

function Fail([string]$msg) { Write-Host "[build] ERROR: $msg" -ForegroundColor Red; exit 1 }

$SourceDir = (Resolve-Path $SourceDir).Path
if (-not (Test-Path "$SourceDir\backend\main.py")) { Fail "SourceDir 不是有效源码树（缺 backend/main.py）: $SourceDir" }
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) { Fail "uv 未安装（https://docs.astral.sh/uv/）" }

Write-Host "[build] 源码: $SourceDir"
Write-Host "[build] 版本: $Version"
Write-Host "[build] 输出: $OutputDir"

# 1. 后端依赖（Windows venv）
#    uv.lock 可能落后于 pyproject（补丁 0005 拆了可选依赖，dev box 无 uv 无法更新锁），
#    这里显式先 uv lock 再 sync，避免 --frozen 模式报 lockfile out of date。
Write-Host "[build] uv 同步后端依赖..."
Push-Location "$SourceDir\backend"
uv lock
# 默认只装 base 依赖（ray/hf 等 optional extras 不装 = 桌面依赖集）
uv sync
Pop-Location

# 2. 前端构建（同源部署，无域名依赖）
#    dist 是纯静态产物、跨平台通用。CI 的源码包由 dev box 预构建 dist 打入
#    （GitHub runner 上 npm 有 "Exit handler never called!" 环境故障）；
#    dist 已存在且新于源码时直接复用，跳过 npm。
Push-Location "$SourceDir\frontend"
$distFresh = (Test-Path "dist\index.html") -and
             ((Get-Item "dist\index.html").LastWriteTime -gt (Get-Item "package.json").LastWriteTime)
if ($distFresh) {
  Write-Host "[build] dist 已预构建（dev box 打包），跳过 npm"
} else {
  Write-Host "[build] 前端 npm ci + build..."
  npm ci
  if ($LASTEXITCODE -ne 0) { Fail "npm ci 失败: $LASTEXITCODE" }
  npm run build
  if ($LASTEXITCODE -ne 0) { Fail "npm run build 失败: $LASTEXITCODE" }
}
Pop-Location
if (-not (Test-Path "$SourceDir\frontend\dist\index.html")) { Fail "前端构建失败：dist/index.html 不存在" }

# 3. 组装绿色目录
Write-Host "[build] 组装绿色目录..."
if (Test-Path $OutputDir) { Remove-Item $OutputDir -Recurse -Force }
$BackendOut = Join-Path $OutputDir "backend"
$FrontendOut = Join-Path $OutputDir "frontend"
$PythonOut = Join-Path $OutputDir "python"
$LauncherOut = Join-Path $OutputDir "launcher"
New-Item -ItemType Directory -Force -Path $BackendOut, $FrontendOut, $PythonOut, $LauncherOut | Out-Null

# backend 源码（排除 .venv/缓存/测试无关产物）
robocopy "$SourceDir\backend" $BackendOut /E /XD .venv __pycache__ .pytest_cache tests /XF *.pyc uv.lock > $null
if ($LASTEXITCODE -ge 8) { Fail "robocopy backend 失败: $LASTEXITCODE" }

# frontend 只带 dist
robocopy "$SourceDir\frontend\dist" "$FrontendOut\dist" /E > $null
if ($LASTEXITCODE -ge 8) { Fail "robocopy frontend dist 失败: $LASTEXITCODE" }

# python：Windows embeddable Python（自包含、可移植）+ 依赖 site-packages
# 不能用 `robocopy backend\.venv python\`：venv 的 pyvenv.cfg/python.exe 绑定
# runner 的绝对路径（用户机器报 "No Python at C:\hostedtoolcache\..."）。
Write-Host "[build] 组装可移植 Python（embeddable + site-packages）..."
$EmbedZip = Join-Path $env:TEMP "python-3.12.10-embed-amd64.zip"
if (-not (Test-Path $EmbedZip)) {
  Invoke-WebRequest "https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip" -OutFile $EmbedZip
}
Expand-Archive $EmbedZip $PythonOut -Force
# embeddable 默认禁用 site-packages；解注释 `import site`
$PthFile = Get-ChildItem $PythonOut -Filter "python*._pth" | Select-Object -First 1
(Get-Content $PthFile.FullName) -replace '^#import site', 'import site' | Set-Content $PthFile.FullName
# 依赖：把 backend/.venv 的 site-packages（纯文件，cp312 二进制）复制进 embeddable
$SitePkgs = Join-Path $PythonOut "Lib\site-packages"
New-Item -ItemType Directory -Force -Path $SitePkgs | Out-Null
robocopy "$SourceDir\backend\.venv\Lib\site-packages" $SitePkgs /E /NFL /NDL /NJH /NJS > $null
if ($LASTEXITCODE -ge 8) { Fail "robocopy site-packages 失败: $LASTEXITCODE" }

# launcher（M3 托盘启动器）：launcher.py + 可选 icon.ico（无 icon 时 launcher 内存绘制）
Copy-Item "$PSScriptRoot\..\launcher\launcher.py" $LauncherOut -Force
if (Test-Path "$PSScriptRoot\..\launcher\icon.ico") {
  Copy-Item "$PSScriptRoot\..\launcher\icon.ico" $LauncherOut -Force
}
# launcher 依赖 pystray + Pillow：装进 embeddable python 的 site-packages。
# 用 runner 的 setup-python（有 pip，同为 3.12 x64）--target 到 $SitePkgs；
# embeddable python 自带 python 不带 pip，不能直接 pip install。
python -m pip install --target $SitePkgs pystray pillow
if ($LASTEXITCODE -ne 0) { Fail "pip install pystray pillow 失败: $LASTEXITCODE" }

# 4. 配置模板（launcher M3 会实现 secrets.env 生成与 .env 加载；
#    此模板记录桌面版默认：外网能力全关）
@"
# DataViewer-Desktop 绿色包默认配置（launcher 启动时经 DV_SECRETS_FILE 与系统 env 生效）
# 首版禁用（D4/D5/D6）：gateway/datalab/hf/arena/claude/s3/volcengine/scp/ray_quality/traj_viz/workbench
GATEWAY_PUSH_ENABLED=false
DATALAB_ENABLED=false
HF_ENABLED=false
ARENA_ENABLED=false
CLAUDE_ENABLED=false
S3_ENABLED=false
VOLCENGINE_ENABLED=false
SCP_ENABLED=false
QUALITY_RAY_ENABLED=false
TRAJ_VIZ_ENABLED=false
WORKBENCH_ENABLED=false
# 数据目录（默认 %USERPROFILE%\DataViewerData，由 launcher 展开）
# DATA_ROOT=
"@ | Out-File -FilePath (Join-Path $OutputDir "desktop.env.template") -Encoding utf8

# 使用说明：直接用仓库的 docs/README-使用说明.md（不内嵌，避免重编码漂移）
Copy-Item "$PSScriptRoot\..\docs\README-使用说明.md" (Join-Path $OutputDir "README-使用说明.md") -Force

# start.bat（M2 简化版启动脚本：生成 secrets → 起 uvicorn → 开浏览器）
@"
@echo off
REM DataViewer Desktop $Version — M2 simple launcher (M3 replaces it with a pystray launcher)
setlocal
set "APP_DIR=%~dp0"
set "DATA_ROOT=%USERPROFILE%\DataViewerData"
set "CONF_DIR=%LOCALAPPDATA%\DataViewerDesktop"
set "METADATA_DIR=%CONF_DIR%\metadata"
set "LOG_DIR=%CONF_DIR%\logs"
if not exist "%CONF_DIR%" mkdir "%CONF_DIR%"
REM DATA_ROOT is the File Explorer root; shutil.disk_usage needs it to exist
REM (online Linux pre-creates /data; Windows launcher creates it here)
if not exist "%DATA_ROOT%" mkdir "%DATA_ROOT%"
if not exist "%METADATA_DIR%" mkdir "%METADATA_DIR%"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
if not exist "%CONF_DIR%\secrets.env" (
  "%APP_DIR%python\python.exe" -c "import secrets,pathlib; p=pathlib.Path(r'%CONF_DIR%'); p.mkdir(parents=True,exist_ok=True); (p/'secrets.env').write_text('JWT_SECRET_KEY='+secrets.token_hex(32)+chr(10)+'ADMIN_PASSWORD=admin123'+chr(10))"
)
set "DV_SECRETS_FILE=%CONF_DIR%\secrets.env"
REM First release disables external capabilities (D4/D5/D6): all off
set GATEWAY_PUSH_ENABLED=false
set DATALAB_ENABLED=false
set HF_ENABLED=false
set ARENA_ENABLED=false
set CLAUDE_ENABLED=false
set S3_ENABLED=false
set VOLCENGINE_ENABLED=false
set SCP_ENABLED=false
set QUALITY_RAY_ENABLED=false
set TRAJ_VIZ_ENABLED=false
set WORKBENCH_ENABLED=false
set PORT=8888
REM Windows console defaults to cp1252; source has Unicode top-level prints
REM (e.g. pilot.py check mark) that crash — force UTF-8.
set PYTHONUTF8=1
start "" /b "%APP_DIR%python\python.exe" -m uvicorn main:app --app-dir "%APP_DIR%backend" --host 127.0.0.1 --port %PORT%
timeout /t 3 /nobreak >nul
start http://127.0.0.1:%PORT%
echo DataViewer Desktop running at http://127.0.0.1:%PORT%  (closing this window keeps the service running; use stop.bat or Task Manager to stop)
"@ | Out-File -FilePath (Join-Path $OutputDir "start.bat") -Encoding ascii

# 5. 打包 zip
Write-Host "[build] 打包 zip..."
$ZipPath = "$OutputDir.zip"
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
Compress-Archive -Path (Join-Path $OutputDir "*") -DestinationPath $ZipPath

Write-Host "[build] 完成: $ZipPath"
Write-Host "[build] 产物清单:"
Get-ChildItem -Recurse $OutputDir | Select-Object -First 20 | ForEach-Object { Write-Host ("  " + $_.FullName.Replace($OutputDir, "")) }

# robocopy 成功退出码为 0-7（1 = 有文件被复制），PowerShell 会把最后原生命令的
# $LASTEXITCODE 泄漏成脚本进程退出码——显式归零，避免 workflow 误判失败。
exit 0
