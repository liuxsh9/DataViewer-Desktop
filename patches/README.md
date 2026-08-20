# 补丁栈（对上游 DataViewer 的适配补丁）

按编号顺序 apply（`scripts/sync-upstream.sh` 自动执行 `git am patches/*.patch`）。
基线：**v4.10.1（git tag）**（2026-08-20 重锁；上游版本线收敛到 4.10.x 后发布，此前 4.11-4.13 的 commit message 版本号已作废）。

| # | 补丁 | 对应 plan.md | 内容 | 状态 |
|---|------|-------------|------|------|
| 0001 | unify-multiprocessing-context | §4.2 | `utils/process_context.py` + 9 处 mp 入口接线（`DV_MP_START_METHOD`，Windows→spawn） | ✅ Linux fork/spawn 全量绿 |
| 0002 | platform-config-layer | §4.1/4.5/4.6 | `DV_SECRETS_FILE` 加载优先级、capability 开关 + `CAPABILITIES` 注册表、`resolve_abs_path`/`strip_data_root` | ✅ |
| 0003 | converge-data-path-joins | §4.1 | 7 文件 `/data` 拼接 → DATA_ROOT 助手；zip arcname `as_posix()`；files.py scp 路由 gate（与 0007 配套） | ✅ |
| 0004 | windows-memory-probe | §4.3 | `_available_memory_mb` psutil 分支、`system_monitor` load_avg 容错 | ✅ |
| 0005 | split-optional-deps | §4.4 | ray/huggingface_hub → optional extra、transformers 移除、延迟/容忍导入 | ✅（uv.lock 未更新，见下） |
| 0006 | capabilities-endpoint | §4.5 | `GET /api/capabilities` + `require_capability` 助手 | ✅ |
| 0007 | capability-kill-switches | §4.7 | 外部服务 API 强制开关（s3/trajlens/claude/hf/arena/distillation/validation/trajectory + scp 服务守卫） | ✅ |
| 0008 | windows-file-semantics-tests | §4.8 | 16 个双平台文件语义用例（Linux 14 过 2 skip） | ✅ |
| 0009 | frontend-capability-gating | §4.5 | `CapabilitiesContext` + 全部功能入口 gate（兜底全 true = 上游行为不变） | ✅ build 绿 |
| 0010 | windows-unix-module-guards | §4.8 实测 | fcntl/pty/termios 容忍导入（Windows 无 flock → 单机锁 no-op；claude terminal 入口 503） | ✅ Linux 921/1/2；Windows CI 首跑暴露后修复 |
| 0011 | declare-cryptography-base-dep | §4.4 补漏 | `cryptography` 显式声明为 base 依赖（原靠 ray[default] 传递满足，拆分后 Windows 闭包缺失） | ✅ base 闭包模拟（python3 -S + pip --target）：零缺失、918 全收集 |
| 0012 | writeback-lock-tests-platform | §4.8 | 测试文件去掉未用 `import fcntl`；flock 语义用例 win32 skipif（锁为文档化 no-op） | ✅ Linux 55 passed |

## 注意事项

- **0003 审查注记（保留未改的 `/data` 出现点）**：`api/validation.py:96-98` 是用户输入 legacy 方言归一化、
  `api/data_versions.py:370-377` 是 DB legacy 绝对路径的 URL 前缀剥除、`claude_chat.py`/`ask_claude.py` 的
  `startswith('/data/')` 是 legacy 输入标记（拼接本已 DATA_ROOT 化）、`aggregation_journal.py:42-48` 是
  root==/data 时的 legacy 等价分支（有注释）、`config_management.py:225` 是配置导出字符串值——均换 helper
  会改变行为，按"不顺手改别的"原则保留；纯注释/docstring 一律不动。

- **uv.lock 失配（0005 引入）**：pyproject 已改但 uv.lock 未动（本机无 uv）。CI/构建机需
  `uv sync`（非 `--frozen`）或补跑一次 `uv lock` 后提交新锁。
- **验证矩阵**（2026-08-20，补丁栈完整 apply 后）：fork 921 passed / 1 failed / 2 skipped、
  spawn 921 passed / 1 failed / 2 skipped。唯一失败 = `test_report_panguml_shape`，
  依赖本机 workbench :8120 在线，属环境性既存失败（上游同环境复现），非补丁引入。
- **上游化节奏（D10）**：每个补丁验证稳定后 PR 回主仓，合入后从本目录删除 → 目标归零。
- 新增/改动测试文件会随补丁一起 apply，属预期（平台无关化 + 新能力测试）。
