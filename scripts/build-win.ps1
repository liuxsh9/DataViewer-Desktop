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
New-Item -ItemType Directory -Force -Path $BackendOut, $FrontendOut, $PythonOut | Out-Null

# backend 源码（排除 .venv/缓存/测试无关产物）
robocopy "$SourceDir\backend" $BackendOut /E /XD .venv __pycache__ .pytest_cache tests /XF *.pyc uv.lock > $null
if ($LASTEXITCODE -ge 8) { Fail "robocopy backend 失败: $LASTEXITCODE" }

# frontend 只带 dist
robocopy "$SourceDir\frontend\dist" "$FrontendOut\dist" /E > $null
if ($LASTEXITCODE -ge 8) { Fail "robocopy frontend dist 失败: $LASTEXITCODE" }

# python venv（backend/.venv 复制为绿色目录的 python/）
robocopy "$SourceDir\backend\.venv" $PythonOut /E > $null
if ($LASTEXITCODE -ge 8) { Fail "robocopy venv 失败: $LASTEXITCODE" }

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

@"
DataViewer Desktop $Version (绿色包)

启动: 双击 start.bat（M2 简化版；M3 由 pystray 托盘启动器取代）
然后浏览器自动打开 http://127.0.0.1:8888
（手动: .\python\Scripts\python.exe -m uvicorn main:app --app-dir backend --port 8888）

首次启动: start.bat 自动生成 %LOCALAPPDATA%\DataViewerDesktop\secrets.env
（JWT_SECRET_KEY 随机生成；ADMIN_PASSWORD 默认 admin123，登录后请修改）

配置: 见 desktop.env.template；外网能力首版默认全关（D4/D5/D6）
数据: %USERPROFILE%\DataViewerData（DATA_ROOT），元数据/日志在 %LOCALAPPDATA%\DataViewerDesktop
"@ | Out-File -FilePath (Join-Path $OutputDir "README-使用说明.md") -Encoding utf8

# start.bat（M2 简化版启动脚本：生成 secrets → 起 uvicorn → 开浏览器）
@"
@echo off
REM DataViewer Desktop $Version — M2 简化版启动脚本（M3 由 pystray launcher 取代）
setlocal
set "APP_DIR=%~dp0"
set "DATA_ROOT=%USERPROFILE%\DataViewerData"
set "CONF_DIR=%LOCALAPPDATA%\DataViewerDesktop"
set "METADATA_DIR=%CONF_DIR%\metadata"
set "LOG_DIR=%CONF_DIR%\logs"
if not exist "%CONF_DIR%" mkdir "%CONF_DIR%"
if not exist "%CONF_DIR%\secrets.env" (
  "%APP_DIR%python\Scripts\python.exe" -c "import secrets,pathlib; p=pathlib.Path(r'%CONF_DIR%'); p.mkdir(parents=True,exist_ok=True); (p/'secrets.env').write_text('JWT_SECRET_KEY='+secrets.token_hex(32)+chr(10)+'ADMIN_PASSWORD=admin123'+chr(10))"
)
set "DV_SECRETS_FILE=%CONF_DIR%\secrets.env"
REM 首版禁用（D4/D5/D6）：外网能力全关
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
REM Windows 控制台默认 cp1252，源码有 Unicode 顶层 print 会崩（如 pilot.py ✓）
set PYTHONUTF8=1
start "" /b "%APP_DIR%python\Scripts\python.exe" -m uvicorn main:app --app-dir "%APP_DIR%backend" --host 127.0.0.1 --port %PORT%
timeout /t 3 /nobreak >nul
start http://127.0.0.1:%PORT%
echo DataViewer Desktop 已启动: http://127.0.0.1:%PORT% （关闭本窗口不会停服务；任务管理器结束 python 或运行 stop.bat）
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
