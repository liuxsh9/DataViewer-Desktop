# Kickoff — 从这里开始 M0

> 本文件是**交接文档**：用户在新仓里说"按 kickoff 开始工作"（或类似）后，直接执行下面的 M0，不要再问立项相关的问题——它们已在 `docs/plan.md` 拍板。
> 执行完 M0 后，把状态回写本文件与 plan.md，并删除本行提示。

---

## 状态快照（2026-08-19）

- 立项完成。路线 B，决策 ADR D1-D11 已拍板（Q1-Q6 全部按建议落地）；**仅 D6（TrajViz/workbench/labeling worker 首版不打包）待用户确认**——M0 不受其影响，但完成报告里提醒用户一句
- 方案与里程碑见 [docs/plan.md](plan.md) §7：M0 = 脚手架（sync 流程 + CI 骨架 + 上游 pytest 基线）
- 本仓当前 commit：`c646e52`

## M0 任务（按序执行）

### M0-1 基线锁定 + workspace 同步

1. 确认上游基线：`/data/projects/DataViewer` 是本地 git 仓库。优先找 tag `v4.12.0`（`git -C /data/projects/DataViewer tag | tail`）；若无对应 tag，则锁定 `master` 当前 HEAD（本机 2026-08-19 是 `1908ff0`），在 `workspace/` 里留一个 `BASELINE` 文件记录（tag 或 commit + 日期 + 理由）
2. **本地 file:// clone，不走网络**：`git clone file:///data/projects/DataViewer workspace/dataviewer`（clone 只拿已提交内容——上游工作区当前有未提交改动，属预期，不涉及）
3. 写 `scripts/sync-upstream.sh`：参数为基线（tag/commit），流程 = clone/fetch → checkout 基线 → `git am patches/*.patch`（当前补丁栈为空，脚本需支持空栈跳过）→ 打印待验证清单。加 `set -euo pipefail`，所有路径绝对化

验收：`./scripts/sync-upstream.sh <基线>` 从零跑通，workspace 工作树干净。

### M0-2 上游后端 pytest 基线

在 `workspace/dataviewer` 上跑上游后端测试（运行方式按上游既有约定，见本机 memory `backend-test-env-and-db-init-bug`）：

- venv：沿用上游 `dv-venv2`（若已存在）或新建
- `PYTHONPATH=backend`、`METADATA_DIR` 指向临时目录、bootstrap annotations（上游 tests 有 fixture 约定，按仓库 README/既有脚本对齐）
- 记录结果：总用例数 / 通过数 / 已知失败（上游既有失败要区分出来，不能算 M0 的锅）

验收：全量测试能跑起来，通过率与上游现状一致（有既存失败就记录在案，不修）。

### M0-3 前端 build 冒烟

`cd workspace/dataviewer/frontend && npm ci && npm run build`（本地 node 版本注意，按上游 README）。验收：dist 产出、无构建错误。

### M0-4 CI 骨架

在 `ci/` 放一个 GitHub Actions 占位 workflow（`ci/linux-pytest.yml`）：checkout 上游基线 → apply patches（暂空）→ pytest（先单 job 最简版，python 版本按上游 `>=3.12`）。本机无 GitHub 环境，**只写文件不执行**，标注"待 D7（M4）决定流水线前为占位"。

### M0-5 回写与收尾

1. `docs/plan.md` §7 里程碑表加一列"状态"：M0 → 完成（含日期与验收结果摘要）
2. 本文件状态快照更新为"M0 完成"，M0 任务段可精简保留
3. 提交本仓（commit message 惯例见仓库历史）
4. 向用户报告：M0 结果 + M1 的前置 spike（Linux 强制 spawn 全量 pytest，见 plan.md §8 风险表第一行）建议立刻启动

## 关键环境事实与坑（务必遵守）

- **本机是 Linux dev box，无 Windows**；Windows 相关脚本（.ps1）只写不跑，属预期
- **Bash 工具的 cwd 每次调用后会重置回 `/data/projects/DataViewer`**——所有命令显式 `cd` 或绝对路径，不要在会话中依赖 cwd 记忆
- 本仓 git identity 已配（`l00653114`），无需再配
- 上游 backend 测试若报 `api.auth` 缺 PyJWT/bcrypt，按 memory 里既有方式安装；`service.sh restart` 在本机会中止（无 uv/systemd 部署），**不要**用它
- 上游内存里有大量运维教训（fork 池、cgroup、路径坑），涉及 dataset-stats / files.py 时先查 memory 再动手
- 讨论结论回写 `docs/plan.md` 的 ADR 表，这是本仓唯一真相源（见 `CLAUDE.md`）
