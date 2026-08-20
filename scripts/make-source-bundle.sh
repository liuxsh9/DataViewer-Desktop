#!/usr/bin/env bash
# make-source-bundle.sh — 在 dev box 打包「上游基线 + 补丁栈」源码，供 Windows CI 使用
#
# 用法: ./scripts/make-source-bundle.sh [<基线>] [<版本号>]
# 背景: 上游内网 CodeHub 对 GitHub runner 不可达（D7 已定 GitHub Actions），
#       CI 的 Windows job 通过源码包拿到补丁 apply 后的完整树。
# 产物: workspace/source-<version>.tar.gz（不含 .git / node_modules / .venv）
# 使用: 上传到 GitHub release asset（或任意可下载 URL），workflow_dispatch 时
#       把下载地址填给 ci/windows-build.yml 的 source_archive_url 输入。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE="${1:-cc71d62}"
VERSION="${2:-v4.13.0-d1}"

# 1. 同步（clone/fetch → checkout 基线 → apply patches）
"$REPO_ROOT/scripts/sync-upstream.sh" "$BASELINE"

# 2. 打包（排除 .git 与前端 node_modules；venv 由 CI 在 Windows 上自己 uv sync）
WORKTREE="$REPO_ROOT/workspace/dataviewer"
OUT="$REPO_ROOT/workspace/source-$VERSION.tar.gz"
echo "[bundle] 打包 $WORKTREE -> $OUT"
tar czf "$OUT" -C "$WORKTREE" \
  --exclude=.git --exclude=frontend/node_modules --exclude='*.pyc' --exclude=__pycache__ \
  .

echo "[bundle] 完成: $OUT ($(du -h "$OUT" | cut -f1))"
cat <<EOF
上传指引:
  1. 在 GitHub 仓库建 release（或上传到任意可下载 URL）
  2. 手动触发 ci/windows-build.yml，source_archive_url 填下载地址
  3. 产物: 绿色包 zip（artifact 可下载，Windows 真机解压冒烟）
EOF
