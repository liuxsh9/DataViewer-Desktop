# build-win.ps1 — DataViewer-Desktop Windows 构建脚本（手工与 CI 共用）
#
# 用法（PowerShell 5.1+，需已安装 Python 3.12 与 uv）:
#   powershell -ExecutionPolicy Bypass -File build-win.ps1 `
#       -SourceDir C:\path\to\upstream-tree -Version v4.13.0-d1 [-OutputDir C:\out]
#
# 流程: 校验源码 → uv 同步后端依赖 → 前端 npm ci + build →
#       组装绿色目录（backend + frontend/dist + python/ venv + 配置模板 + README）
# 说明: 本机是 Linux dev box，此脚本只写不跑；Windows 验证走 CI（.github/workflows/windows-build.yml）。

param(
    [Parameter(Mandatory=$true)][string]$SourceDir,   # 上游基线 + 补丁 apply 后的源码树
    [Parameter(Mandatory=$true)][string]$Version,     # 如 v4.13.0-d1
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
Write-Host "[build] 前端 npm ci + build..."
Push-Location "$SourceDir\frontend"
npm ci
npm run build
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
robocopy "$SourceDir\backend" $BackendOut /E /XD .venv __pycache__ tests /XF *.pyc uv.lock > $null
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

启动: 解压后运行 start.bat（M3 提供）或:
  .\python\python.exe -m uvicorn main:app --app-dir backend --port 8888
然后浏览器打开 http://127.0.0.1:8888

配置: 见 desktop.env.template（launcher 自动加载）
数据: %USERPROFILE%\DataViewerData（DATA_ROOT），元数据/日志在 %LOCALAPPDATA%\DataViewerDesktop
"@ | Out-File -FilePath (Join-Path $OutputDir "README-使用说明.md") -Encoding utf8

# 5. 打包 zip
Write-Host "[build] 打包 zip..."
$ZipPath = "$OutputDir.zip"
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
Compress-Archive -Path (Join-Path $OutputDir "*") -DestinationPath $ZipPath

Write-Host "[build] 完成: $ZipPath"
Write-Host "[build] 产物清单:"
Get-ChildItem -Recurse $OutputDir | Select-Object -First 20 | ForEach-Object { Write-Host ("  " + $_.FullName.Replace($OutputDir, "")) }
