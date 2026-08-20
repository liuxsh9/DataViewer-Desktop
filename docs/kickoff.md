# Kickoff — M0 执行完毕，M1 进行中

---

## 状态快照（2026-08-20，M1 进行中）

- **M0 完成**。结果摘要见 [docs/plan.md](plan.md) §7 里程碑表"状态"列。
- **基线已随上游 HEAD 更新**：v4.13.0 = commit `cc71d62`（上游无 tag；用户口头提到的"4.10.0"经查证与仓库不符，已确认跟随 master HEAD）。pytest 基线复核 **882/883**（唯一失败同前：workbench 离线既存问题）。
- **M1 进行中**（2026-08-20 启动）：前置 spike = Linux 强制 spawn 全量 pytest，随后按 plan.md §4 顺序推进 4.1-4.8。
- 立项决策不变：D1-D11 已拍板，**仅 D6（TrajViz/workbench/labeling worker 首版不打包）仍待用户确认**——M1 按 D6 提案方向（首版禁用）先行实施，开关可逆，最终以用户拍板为准。

## M0 执行记录（已完成，留档）

| 任务 | 结果 |
|------|------|
| M0-1 基线锁定 + workspace 同步 | ✅ 无 tag → 锁 `1d2b0df`（v4.12.0）；`scripts/sync-upstream.sh` 首次 clone + 二次 fetch 路径均跑通；`git am` 空栈跳过逻辑就绪 |
| M0-2 后端 pytest 基线 | ✅ 876 收集全过（无 import 错误）；875 过 / 1 既存失败；运行方式沿用 memory `backend-test-env-and-db-init-bug`（系统 python3 + 上游 backend/.venv site-packages，METADATA_DIR/DATA_ROOT 隔离）。**该 memory 中的 annotations db-init bug 在 v4.12.0 已修复**（CREATE 已含 reviewed_by 且迁移顺序已纠正） |
| M0-3 前端 build 冒烟 | ✅ node v24.1.0；`npm ci && npm run build` 成功，dist/assets + index.html 产出（仅 chunk 体积 warning） |
| M0-4 CI 骨架 | ✅ `ci/linux-pytest.yml`：checkout 上游基线 → apply patches（空栈跳过）→ uv sync → pytest（python 3.12，单 job）；上游内网 CodeHub URL 在 GitHub runner 不可达，已注释标注，待 D7 落地时替换 |
| M0-5 回写收尾 | ✅ plan.md §7 加状态列、本文件快照更新、提交 |

## 关键环境事实与坑（M1 继续适用）

- **本机是 Linux dev box，无 Windows**；Windows 相关脚本（.ps1）只写不跑，属预期
- **Bash 工具的 cwd 每次调用后会重置回 `/data/projects/DataViewer`**——所有命令显式 `cd` 或绝对路径，不要在会话中依赖 cwd 记忆
- 上游 backend 测试：系统 `python3`（3.12.3，带 pytest 9.1.1）+ `PYTHONPATH=/data/projects/DataViewer/backend/.venv/lib/python3.12/site-packages`，从 clone 的 `backend/` 目录跑（`python3 -m` 使 flat 包可解析）；`METADATA_DIR`/`DATA_ROOT` 指向临时目录隔离
- 上游工作区有未提交改动（dataset-stats 相关）——file:// clone 只同步已提交内容，属预期
- 上游测试无 pytest-asyncio/timeout 依赖，系统 pytest 直接可跑
- `service.sh restart` 在本机会中止（无 uv/systemd 部署路径问题），不要用它
- 上游内存里有大量运维教训（fork 池、cgroup、路径坑），涉及 dataset-stats / files.py 时先查 memory 再动手
- 讨论结论回写 `docs/plan.md` 的 ADR 表，这是本仓唯一真相源（见 `CLAUDE.md`）
