# Kickoff — M0 与 M1 已执行完毕，交接给 M2

---

## 状态快照（2026-08-20，M1 完成、M2 启动中）

- **D6 已拍板（2026-08-20）：禁用**（TrajViz/workbench/labeling worker 首版不打包）。M1 的实施（开关 + gate）即最终形态，无需改动；SampleBrowser "Score Traj" 经核实走 data_versions 本地打分，不受影响（D14 已澄清）。
- **D7 已拍板（2026-08-20）：GitHub Actions windows-latest**（用户"能走 actions 就走 actions"）。已产出：`scripts/build-win.ps1`（构建）、`scripts/make-source-bundle.sh`（dev box 打包上游源码，实测 6.6M）、`.github/workflows/windows-build.yml`（pytest → build → 冒烟 → artifact）。**已激活（2026-08-20）**：本仓已推 GitHub（liuxsh9/DataViewer-Desktop，gh CLI per-repo credential）；源码包已上传 `<版本>-src` release；触发方式：`gh workflow run windows-build.yml -f version=<版本>`。
- **M2 状态**：Windows CI 骨架就位，等待 repo 上传后首跑；真机冒烟 = 下载 artifact 绿色包在你的 Windows 机器解压验证。

- **M0 完成**（详见 plan.md §7 状态列）：sync 流程 + pytest 基线 + CI 骨架。
- **基线**：**v4.10.1（git tag，2026-08-20 重锁）**。演进过程：上游最初无 tag（曾临时锁 v4.13.0=cc71d62），同日上游"anchor v4.10.0 — unify code versions"收敛版本线并发布 v4.10.1——用户最初"收敛到 4.10.0"的意图与此吻合。15 个补丁已 rebase 并在 tag 上重放验证（fork/spawn 1008/1/2）。
- **M1 主体完成**：9 个补丁已入 `patches/`（0001-0009，见 patches/README.md）。重放验证（干净树 apply 全部补丁）：
  - 后端 pytest：fork **921 passed / 1 failed / 2 skipped**；spawn **921 passed / 1 failed / 2 skipped**。唯一失败 = `test_report_panguml_shape`（workbench :8120 离线，环境性既存问题，非补丁引入）。
  - 前端：`npm ci && npm run build` 通过。
- **遗留事项**（M2 中处理）：uv.lock 失配（build-win.ps1 已内置 `uv lock` 步骤处理）；`patches/` 上游化节奏（D10，M4）。
- **下一步（M2 Windows 冒烟）**：激活 windows-build.yml（见状态快照的前置）→ CI 首跑 → 真机解压冒烟（浏览/JSONL/聚合/转换/校验/dataset-stats 小任务；外网功能不可见）。

## M0 执行记录（留档）

| 任务 | 结果 |
|------|------|
| M0-1 基线锁定 + workspace 同步 | ✅ 无 tag → 锁 commit；`scripts/sync-upstream.sh` 双路径幂等；M1 期间补了全新 clone 的 git identity 兜底（git am 必需） |
| M0-2 后端 pytest 基线 | ✅ v4.12.0 时 875/876；v4.13.0 基线复核 882/883。memory 中的 annotations db-init bug 在 v4.12.0 已修复 |
| M0-3 前端 build 冒烟 | ✅ node v24；npm ci + build 通过 |
| M0-4 CI 骨架 | ✅ `.github/workflows/linux-pytest.yml` 占位（D7 拍板后与 windows-build 一并激活） |
| M0-5 回写收尾 | ✅ plan.md §7 状态列、kickoff 快照、提交 14e4d57 |

## M1 执行记录（留档）

| 补丁 | 内容 | 验收 |
|------|------|------|
| 0001 | `utils/process_context.py` + 9 处 mp 入口接线（`DV_MP_START_METHOD`） | fork/spawn 全量 882/1，spawn 零额外失败 |
| 0002 | config 平台层：`DV_SECRETS_FILE` 加载优先级 + capability 开关注册表 + 路径助手 | 888/1 + 6 新用例 |
| 0003 | `/data` 拼接 → `resolve_abs_path`/`strip_data_root`（7 文件）+ zip arcname as_posix | fork 全量绿 |
| 0004 | `_available_memory_mb` psutil 分支 + load_avg 容错（修 AttributeError 坑） | 5 新用例 |
| 0005 | ray/huggingface_hub → optional extra、transformers 移除、延迟/容忍导入 | 零顶层 ray import；uv.lock 待补 |
| 0006 | `GET /api/capabilities` + `require_capability` | 4 新用例 |
| 0007 | 外部服务 API 强制开关（router 级 gate + scp 服务守卫 + 残留点收尾） | 10 新用例 |
| 0008 | Windows 文件语义双平台用例（16 个） | Linux 14 过 2 skip |
| 0009 | 前端 `CapabilitiesContext` + 全部入口 gate（兜底全 true） | build 绿 |

## M2 真机冒烟清单（Windows 机器，artifact 下载后执行）

1. 下载 GitHub Actions artifact（`DataViewer-Desktop-<版本>-win64` 的 zip），解压到本地（路径含中文/空格应无碍，若异常换纯 ASCII 路径并记录）
2. 双击 `start.bat` → 浏览器自动打开 http://127.0.0.1:8888 → 用 `admin` / `admin123` 登录（首次运行自动生成 secrets.env；登录后请修改密码）
3. 核心链路逐项过：
   - 文件浏览：`%USERPROFILE%\DataViewerData` 下放几个 jsonl 文件，File Explorer 可见
   - JSONL 查看：打开一个 jsonl（含中文内容）正常渲染
   - 聚合：对多文件做一次聚合
   - 格式转换/校验：Convert to ATIF/PanguML（本地，可用）；Validate ATIF（本地，可用）
   - dataset-stats：对小文件集跑一个统计任务（token 计数走 sentencepiece fallback 或 gigatoken，速度差异属预期）
4. 外网功能不可见：File Explorer 无 MindForge Push/Pull、S3、Upload from Server、Validation（datalab）、Ask Claude、Pipeline、Traj-Viz、Arena 入口；`GET http://127.0.0.1:8888/api/capabilities` 返回 11 项全 false
5. 已知限制（首版预期行为）：PanguML/ML1.5 校验不可用（workbench 未打包，入口已隐藏）；多进程用 spawn，首次统计任务启动稍慢属正常
6. 记录异常：任何 500/白屏/入口残留截图 + `%LOCALAPPDATA%\DataViewerDesktop\logs` 日志，回传给我修

## 关键环境事实与坑（M2 继续适用）

- **本机是 Linux dev box，无 Windows**；.ps1 脚本只写不跑，Windows 验证走构建机/CI（D7）。
- **Bash 工具的 cwd 每次调用后会重置**——所有命令显式 `cd` 或绝对路径。
- 后端测试配方：系统 python3（pytest 9.1.1）+ `PYTHONPATH=/data/projects/DataViewer/backend/.venv/lib/python3.12/site-packages`，从 clone 的 `backend/` 目录跑；`METADATA_DIR`/`DATA_ROOT` 指向临时目录隔离；spawn 验证加 `DV_MP_START_METHOD=spawn`。
- 上游无 tag、版本以 commit message 标注；同步基线先核对上游 HEAD。
- `service.sh restart` 在本机会中止，不要用。
- 讨论结论回写 `docs/plan.md` ADR 表（唯一真相源）。
