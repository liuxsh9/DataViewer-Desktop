# DataViewer-Desktop 项目约定

DataViewer 的单机 Windows 版产品化仓。方案全貌见 `docs/plan.md`，本文件是给 Claude Code 的工作约定。

## 核心原则

- **单一代码库**：业务代码只存在于上游 `/data/projects/DataViewer`。本仓不直接修改 `workspace/` 里 checkout 出来的业务代码 —— 一切适配改动先写成 `patches/` 下的补丁，稳定后 PR 回主仓（目标：`patches/` 归零）
- **平台抽象，不是 if-else 补丁**：适配必须保证 Linux 线上行为不变；凡是"探测 + 环境变量开关"能表达的，不写平台分支
- 讨论结论一律回写到 `docs/plan.md` 的 ADR 表（§0）与开放问题表（§9），保持"唯一计划文档"是最新真相源
- 文档语言：中文；代码与 UI 文本：英文（与上游一致）
- 上游事实引用带 `file:line`；上游代码盘查结论若失效（上游重构），先复核再引用

## 环境事实

- 本机是 **Linux dev box，无 Windows**。Windows 验证走 CI（windows-latest）或远程 Windows 机；`scripts/` 下的 .ps1 脚本在 Linux 上无法运行，属预期
- 上游后端测试运行方式（venv、PYTHONPATH、METADATA_DIR 等）见 DataViewer 主仓的既有约定与本机 memory
- 上游当前版本基线：v4.10.1（git tag，2026-08-20 重锁；上游版本线已收敛到 4.10.x，"anchor v4.10.0 — unify code versions" 后发布 v4.10.1，此前 4.11-4.13 的 commit message 版本号作废）

## 工作流

- 同步上游：`scripts/sync-upstream.sh <tag>` → workspace/ 内 apply patches → 跑上游 pytest
- 新增适配改动：在 workspace/ 里改 → `git format-patch` 生成补丁进 `patches/` → 提交本仓
- 上游功能裁剪只动"开关 + 入口"，不删业务代码
