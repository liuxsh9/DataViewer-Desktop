#!/usr/bin/env bash
# sync-upstream.sh — 拉取 DataViewer 上游指定基线到 workspace/ 并应用补丁栈
#
# 用法: ./scripts/sync-upstream.sh <基线>
#   基线 = git tag 或 commit SHA（上游目前无 tag，本机基线见 workspace/BASELINE）
#
# 流程: clone/fetch → checkout 基线 → git am patches/*.patch（空栈自动跳过）→ 打印待验证清单
# 注意: 上游工作区未提交改动不会被同步（file:// clone 只拿已提交内容），属预期。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE_DIR="$REPO_ROOT/workspace"
WORKTREE_DIR="$WORKSPACE_DIR/dataviewer"
PATCHES_DIR="$REPO_ROOT/patches"
# 可经环境变量覆盖（如 CI 里换成 https 地址）
UPSTREAM_URL="${UPSTREAM_URL:-file:///data/projects/DataViewer}"

if [[ $# -lt 1 ]]; then
  echo "用法: $0 <基线(tag|commit)>" >&2
  echo "  当前本机锁定基线见 $WORKSPACE_DIR/BASELINE" >&2
  exit 1
fi
BASELINE="$1"

# 1. clone 或 fetch（本地 file:// clone，不走网络）
if [[ -d "$WORKTREE_DIR/.git" ]]; then
  echo "[sync] fetch 上游: $UPSTREAM_URL"
  # --force: 上游 tag 会移动/回退（如版本线收敛），本地同名 tag 直接覆盖
  git -C "$WORKTREE_DIR" fetch --tags --force "$UPSTREAM_URL"
else
  echo "[sync] clone 上游: $UPSTREAM_URL"
  mkdir -p "$WORKSPACE_DIR"
  git clone "$UPSTREAM_URL" "$WORKTREE_DIR"
fi

# 2. checkout 基线（丢弃工作树已有改动/补丁提交，保证幂等）
#    先清理可能残留的 git am 中断状态
git -C "$WORKTREE_DIR" am --abort >/dev/null 2>&1 || true
echo "[sync] checkout 基线: $BASELINE"
git -C "$WORKTREE_DIR" checkout --force "$BASELINE"
# 全新 clone 没有 identity，git am 会失败——补一个本地兜底（补丁作者信息
# 由 patch 自带，这里只是 committer）
if [[ -z "$(git -C "$WORKTREE_DIR" config user.name)" ]]; then
  git -C "$WORKTREE_DIR" config user.name "DataViewer-Desktop Sync"
  git -C "$WORKTREE_DIR" config user.email "sync@dataviewer-desktop.local"
fi

# 3. apply 补丁栈（空栈跳过）
shopt -s nullglob
PATCH_FILES=("$PATCHES_DIR"/*.patch)
if [[ ${#PATCH_FILES[@]} -eq 0 ]]; then
  echo "[sync] patches/: 空栈，跳过 git am"
else
  echo "[sync] 应用补丁 ${#PATCH_FILES[@]} 个: ${PATCH_FILES[*]}"
  git -C "$WORKTREE_DIR" am "${PATCH_FILES[@]}"
fi

# 4. 打印待验证清单
HEAD="$(git -C "$WORKTREE_DIR" rev-parse --short HEAD)"
echo
echo "[sync] 完成。工作树: $WORKTREE_DIR @ $HEAD"
echo "待验证清单:"
echo "  1. 后端全量 pytest（运行方式见 memory: backend-test-env-and-db-init-bug）"
echo "  2. 前端构建冒烟: cd $WORKTREE_DIR/frontend && npm ci && npm run build"
