# DataViewer Desktop — 单机 Windows 版实现方案与总体计划

> 状态：草案 v0.1（待讨论）
> 上游：`/data/projects/DataViewer`（单一代码库，本仓不做业务代码 fork）
> 目标平台：Windows 10/11 x64
> 定稿日期：2026-08-19

---

## 0. 决策记录（ADR 摘要）

| # | 决策 | 内容 | 状态 |
|---|------|------|------|
| D1 | 项目名 | **DataViewer-Desktop** | 已定（Claude 定名） |
| D2 | 技术路线 | **路线 B**：原生 Windows 绿色包（嵌入式 Python venv + 内嵌前端）+ 托盘启动器 + Inno Setup 安装器。不用 PyInstaller 单 exe（体积会因 pandas/numpy/pyarrow 膨胀到 2GB+，且多进程 spawn 与冻结包兼容性差） | 已定 |
| D3 | 代码模型 | **单一代码库**：业务代码只存在于 DataViewer 主仓；本仓是产品化/打包层（补丁栈 + 启动器 + 安装器 + CI + 文档）。适配改动以 patch 形式在本仓迭代，**最终目标提交回主仓** | 已定 |
| D4 | 首版功能裁剪 | 禁用：**ray（分布式质检）、datalab 一键质检、HF 下载、arena 导入、claude API/CLI**。代码保留、后端开关关闭、前端入口隐藏 | 已定 |
| D5 | Gateway/S3/volcengine/scp | 同属外网能力，建议首版一并禁用（待确认，见开放问题 Q1） | 待确认 |
| D6 | TrajViz / workbench / labeling worker | 首版不打包、入口禁用；作为后续可选组件（P2 再评估） | 待确认 |

---

## 1. 目标与非目标

### 目标
- DataViewer 的单机 Windows 工具：安装即用，双击启动，本地浏览器打开
- 数据全部落在本机用户目录，不依赖任何内网服务
- 与在线版**同一个代码库、同一批测试**持续演进：上游每次发布，桌面版跟随出包
- 核心能力保真：文件浏览、JSONL 查看、聚合、格式转换/校验、dataset-stats（按本机内存自动降级）、token 计数、API Token 上传下载等

### 非目标（首版）
- 多用户/权限体系（保留单管理员 + 可选免密直入）
- GPU 加速、超大数据集（> 本机内存）的统计任务
- PyInstaller 单 exe、代码混淆、防逆向
- Windows Server / ARM64

---

## 2. 事实基础（2026-08-19 对 DataViewer 主仓的盘查结论）

结论先行：**后端已是"易单机化"的形态**，Linux 耦合面小且多数已有降级设计。

| # | 事实 | 出处 | 对单机化的影响 |
|---|------|------|----------------|
| F1 | 后端自带前端托管：`frontend/dist` 挂为 `StaticFiles(html=True)` | `backend/main.py:321-323` | nginx 非必需，单进程即完整系统 ✅ |
| F2 | 配置全部环境变量化（DATA_ROOT / METADATA_DIR / LOG_DIR / 各 feature kill switch） | `backend/config.py` | 单机版 = 换一套 .env + 关开关 ✅ |
| F3 | `/proc/meminfo` 读取已有 `OSError → 0 → 跳过检查` 兜底 | `backend/services/dataset_stats/engine.py:37-46` | Windows 自然降级，零改动 ✅ |
| F4 | cgroup 仅存在于注释（systemd 部署层保护），代码无 cgroup 操作 | `engine.py:79-81` | 单机版靠 `DS_STATS_MIN_FREE_MB` 内存守卫即可 ✅ |
| F5 | token 计数双引擎：gigatoken（Rust）→ sentencepiece fallback，语义等价 | `backend/services/dataset_stats/tokenizer.py:18-85` | gigatoken 若无 Windows wheel，自动回退（慢 20-40×，功能无损）✅ |
| F6 | `main.py` 已有 `if __name__ == "__main__"` guard | `backend/main.py:325` | spawn 多进程的硬前提 ✅ |
| F7 | **`/data` 硬编码路径拼接约 20 处**（绕过 DATA_ROOT） | `database/models.py`、`database/model_manager.py`、`api/metadata.py`、`api/validation.py`、`services/aggregation_journal.py` 等 | 需收敛，主仓技术债，顺手清理 ⚠️ |
| F8 | dataset-stats 常驻 `ProcessPoolExecutor` 按 **fork 语义**设计 | `engine.py`（常驻池、fork 继承 sqlite fd 的注释） | 需显式 spawn 分支 + Windows 验证 ⚠️ |
| F9 | **ray 顶层 `import ray`**（`quality_ray_workers.py:9`），经 `quality_job_runner` 进入启动链 | `backend/services/quality_ray_workers.py` | 启动即硬依赖，需改可选延迟导入 ⚠️ |
| F10 | **transformers 全库零引用**（pyproject 里白装） | grep 无命中 | 可直接移除，省 ~1GB ⚠️→✅ |
| F11 | huggingface_hub 仅 1 个文件使用 | `backend/services/hf_download_manager.py` | 随 HF 禁用拆出 ⚠️ |
| F12 | 前端**无 VITE_ 功能开关机制**（仅 vite.config 读 `VITE_DATAVIEWER_DOMAIN`） | `frontend/vite.config.js` | 需要设计统一的"能力端点"来隐藏禁用功能入口 ⚠️ |
| F13 | 外部服务全部可选：Gateway、datalab、arena、volcengine、S3、claude CLI | `config.py` + `.env.example` | 关闭后前端入口需同步隐藏 ⚠️ |
| F14 | subprocess 依赖外部命令：scp 命令（`scp_download_manager.py`）、claude CLI（`utils/claude_subprocess.py`） | grep | Windows 无 scp → 首版禁用入口 ⚠️ |

---

## 3. 目标形态

### 3.1 运行时架构

```
┌─────────────────────────── Windows PC ───────────────────────────┐
│                                                                   │
│  用户双击桌面图标                                                 │
│        │                                                          │
│        ▼                                                          │
│  ┌─────────────────────────────────────────────────────────┐     │
│  │  launcher.exe (pystray 托盘，与后端共用 Python 运行时)    │     │
│  │  • 分配空闲端口 → 启动 uvicorn (127.0.0.1)                │     │
│  │  • 等端口就绪 → 默认浏览器打开 http://127.0.0.1:<port>    │     │
│  │  • 托盘菜单：打开页面 / 查看日志 / 打开数据目录 / 退出      │     │
│  │  • 首次启动：生成 JWT_SECRET_KEY、初始化 admin 密码        │     │
│  └──────────────┬──────────────────────────────────────────┘     │
│                 ▼ 子进程                                          │
│  ┌─────────────────────────────────────────────────────────┐     │
│  │  uvicorn → FastAPI（DataViewer 上游代码 + 适配补丁）       │     │
│  │  • StaticFiles 内嵌 frontend/dist（无 nginx）             │     │
│  │  • 外网功能全部禁用（不发任何外网请求）                     │     │
│  │  • dataset-stats 按本机内存自适应 workers                 │     │
│  └───────────────┬─────────────────────────────────────────┘     │
│                  │                                                │
│   %LOCALAPPDATA%\DataViewerDesktop\   ← METADATA_DIR / LOG_DIR    │
│     metadata/（sqlite：文件索引、任务、token 偏好）                │
│     secrets.env（JWT_SECRET_KEY 等，首次启动生成）                 │
│     logs/                                                         │
│                                                                   │
│   %USERPROFILE%\DataViewerData\      ← DATA_ROOT（File Explorer 根）│
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

### 3.2 产物形态（两个）

1. **绿色包**（zip）：`DataViewer-Desktop-v4.12.0-d1-win64.zip` — 解压即用，`start.bat` / 托盘 exe
2. **安装器**（Inno Setup，免费）：`DataViewerDesktopSetup-v4.12.0-d1.exe` — 开始菜单/桌面快捷方式、卸载、可选开机自启

绿色目录内容：

```
DataViewerDesktop/
├── DataViewerDesktop.exe      # pystray 启动器（单文件 Python 脚本打包）
├── backend/                   # DataViewer backend 源码（上游 tag + 补丁）
│   └── services/dataset_stats/tokenizer.model   # 已随仓 vendored ✅
├── frontend/dist/             # 构建产物（同源，无域名依赖）
├── python/                    # 嵌入式/venv Python 3.12 + uv 同步的依赖
├── data/                      # 首次运行创建（DB、日志、密钥）
└── docs/README-使用说明.md
```

---

## 4. 后端适配改造清单（提交回 DataViewer 主仓的部分）

> 原则：**平台抽象，不是 if-else 补丁**。每项改造必须保证 Linux 线上行为不变，验收 = 上游全量 pytest + 新增 Windows CI 用例。

### 4.1 路径收敛：`/data` 硬编码 → `DATA_ROOT`（F7）

- **涉及**：`database/models.py`（3 处）、`database/model_manager.py`（4 处）、`api/metadata.py`（3 处）、`api/validation.py`、`services/aggregation_journal.py`、`api/files.py`（safe_path 双拼问题，见上游 memory）
- **方案**：统一 `config.py` 导出 `resolve_abs_path(rel)` / `strip_data_root(abs)` 两个助手，全部替换 `f"/data/{p}"` 拼接；语义 = "DATA_ROOT 是 File Explorer 的根，DB 存相对路径"
- **验收**：上游 pytest 全绿；Windows 上 `DATA_ROOT=C:\Users\x\DataViewerData` 冒烟通过

### 4.2 多进程模型：显式 start method + spawn 兼容（F8）

- **涉及**：`dataset_stats/engine.py`（常驻池）、`services/jsonl_quality_checker.py`、`quality_processor.py`、`parquet_conversion_manager.py`、`api/filter_tasks.py`（逐个盘点）
- **方案**：
  - 建 `utils/process_context.py`：`get_context()` 返回 `multiprocessing.get_context("fork" | "spawn")`，按 `sys.platform` + 环境变量 `DV_MP_START_METHOD`（默认 Linux=fork / Windows=spawn，允许 Linux 强制 spawn 用于 CI 预验证）
  - spawn 下 worker 需 pickle 入口 + 模块级 import 纪律（现有"连接纪律"注释表明代码已朝此方向收敛）
  - `engine.py` 常驻池 fork 语义保留，spawn 分支单独验证（spawn 无 fd 继承问题，DB 锁风险反而更低）
- **验收**：Linux fork 性能不变；**Linux 强制 spawn 全量 pytest 通过**（M1 的核心风险前置验证）；Windows CI 过

### 4.3 内存探测：Windows 分支（F3 补强）

- `_available_memory_mb()` 增加非 Linux 分支：`psutil.virtual_memory().available`
- 涉及：`engine.py:37-46`、`services/system_monitor.py`（load_avg 在 Windows 为 []，需前端容错，盘点）
- 验收：Windows 上 workers 自动降级逻辑生效

### 4.4 依赖拆分（F9/F10/F11）

| 依赖 | 现状 | 方案 | 省体积 |
|------|------|------|--------|
| `ray[default]` | 硬依赖 + 顶层 import | 移入 optional extra；`quality_ray_workers` 延迟导入 + `QUALITY_RAY_ENABLED` 开关 | ~1GB |
| `transformers` | 硬依赖、零引用 | 直接从依赖表移除 | ~1GB |
| `huggingface_hub` | 硬依赖、1 文件用 | 移入 optional extra（随 HF 禁用） | ~100MB |
| `gigatoken` | 硬依赖（内部 Rust 包） | 保留声明但 import 容错（`tokenizer.py:60` 已 try）；无 Windows wheel 时自动 sentencepiece fallback | — |
| `opencc` / `pyarrow` / `sentencepiece` / `pandas` / `numpy` | 硬依赖 | 均有官方 Windows wheel，保留 | — |
| `uvicorn[standard]` | uvloop Linux only | Windows 自动回退 asyncio，保留 | — |

- 验收：`uv sync --extra none`（新 profiles 方案）在 Windows 上可启动全量 API；上游 Linux 全量依赖行为不变

### 4.5 能力端点与前端入口隐藏（F12/F13）

- **方案**：
  - 后端新增 `GET /api/capabilities`：按 env 开关汇总 `{gateway, datalab, hf, arena, claude, s3, volcengine, ray_quality, traj_viz, workbench, ...}`（`config.py` 已有各开关，加一个汇总注册表）
  - 前端在 `main.jsx` 启动时 fetch 一次，注入 context/全局常量；File Explorer 右键菜单、actions 栏、I/O 工具栏、菜单项统一 gate（注意 CLAUDE.md 约定：File Explorer 入口分散多处，必须全部同步）
- 验收：禁用项在前端**不可见**；上游开启状态 UI 不变

### 4.6 单机认证与初始化

- 首次启动（启动器）：生成 `JWT_SECRET_KEY`、初始化 admin 账号（`ADMIN_PASSWORD` 已有默认），写入 `%LOCALAPPDATA%\DataViewerDesktop\secrets.env`
- 后端启动时加载该文件（`config.py` 增加加载优先级：系统 env > secrets.env > 默认）
- 登录页保留但记忆登录（单机版体验）；是否"免密直入"见 Q4
- 验收：解压 → 双击 → 直接可登录使用，无手工配置

### 4.7 subprocess 外部命令降级（F14）

- scp 下载：首版禁用入口（paramiko 替代列为 P2）
- claude CLI 系列（ask_claude/claude_chat/claude_terminal）：首版禁用入口
- 验收：禁用后相关按钮消失、API 返回明确"单机版不可用"

### 4.8 Windows 文件语义回归测试

- 用例组（新增到上游 `backend/tests/`，双平台 CI 跑）：
  - Unicode/中文文件名、emoji 文件名、长路径（`\\?\` 前缀策略）
  - 大小写不敏感路径查找（DB 索引与 `Path` 比较的坑）
  - 文件锁语义（Windows 下打开中的文件不可删，`shutil`/`os.replace` 差异）
  - 路径分隔符混用（`\` vs `/`）、盘符相对路径
  - zip 解压中文文件名（zipfile 编码坑）
- 验收：新增用例在 Linux + Windows CI 双绿

---

## 5. 本仓结构

```
DataViewer-Desktop/
├── README.md                  # 项目定位、快速导航
├── CLAUDE.md                  # 本仓工作约定（AI 协作规范）
├── docs/
│   └── plan.md                # 本方案（唯一计划文档，讨论结论回写 ADR 表）
├── patches/                   # 对上游的适配补丁栈（编号 + 说明，目标：归零）
│   └── 0001-... 0002-...
├── scripts/
│   ├── sync-upstream.sh       # 拉取上游指定 tag → apply patches → 本地 pytest
│   └── build-win.ps1          # Windows 构建脚本（CI 与手工共用）
├── launcher/                  # pystray 托盘启动器源码
├── installer/                 # Inno Setup 脚本（.iss）
├── ci/                        # GitHub Actions / 内部流水线定义
└── workspace/                 # [gitignore] 上游 clone + 打补丁后的工作树（不提交）
```

### 补丁工作流（D3 的落地）

```
sync-upstream.sh:
  1. git clone/fetch DataViewer 到 workspace/，checkout 指定 tag（如 v4.12.0）
  2. git am patches/*.patch（失败则进入人工 rebase 模式）
  3. 后端 pytest + 前端 build 冒烟
  4. 通过后打 tag：<上游tag>-d<N>（如 v4.12.0-d1，d = desktop patch level）
```

- **补丁上游化**：每轮验证稳定后，逐个 PR 回 DataViewer 主仓；合入后从 `patches/` 删除 → 理想终态 patches 目录为空，桌面版 = 主仓 tag + 打包层
- 版本规则：上游版本号原样继承 + `-d<N>` 后缀，可追溯来源

---

## 6. 构建与发布流水线

### 6.1 构建步骤（Windows 环境，CI 或构建机）

```
1. checkout DataViewer @ tag → apply patches
2. uv sync（Windows lockfile，仅桌面版依赖集）
3. cd frontend && npm ci && npm run build
   （独立构建 env：VITE_DATAVIEWER_DOMAIN 置空/127.0.0.1 — 同源部署）
4. 组装绿色目录（backend 源码 + dist + venv + 启动器）
5. Inno Setup 打包 → 产物：setup exe + 绿色 zip
6. 冒烟测试（脚本化）：起服 → 登录 → 浏览 → JSONL 查看 → dataset-stats 小任务
```

### 6.2 CI 分层

| 层 | 环境 | 内容 | 频率 |
|----|------|------|------|
| 适配验证 | Linux（现有） | 上游全量 pytest + **强制 spawn 模式**重跑 | 每个补丁 |
| Windows 验证 | windows-latest | 桌面版依赖集 pytest + 冒烟 + 打包 | 每次上游 tag / PR |
| 发布 | windows-latest | 出 zip + exe 产物 | 上游 release 后 |

构建机选型（内部 Windows 机 vs GitHub Actions）见 Q2。

---

## 7. 里程碑

| 阶段 | 内容 | 验收标准 | 估计 |
|------|------|----------|------|
| **M0 脚手架** | 本仓结构、sync-upstream 流程、CI 骨架、workspace 同步到 v4.12.0 跑通上游 pytest | Linux 上 patch 流程端到端可用 | 0.5-1 周 |
| **M1 适配补丁**（核心风险） | 4.1 路径收敛 → 4.2 spawn → 4.3 内存 → 4.4 依赖拆分 → 4.5 capability → 4.6 认证 → 4.7 降级 | 上游 pytest 全绿 + Linux spawn 模式全绿 + Windows CI pytest 绿 | 2-3 周 |
| **M2 Windows 冒烟** | 绿色包在 Windows 真机跑通核心链路 | 浏览/JSONL/聚合/格式转换/dataset-stats 小任务全过；外网功能不可见 | 1-2 周 |
| **M3 产品化** | pystray 启动器、Inno Setup、使用说明、日志收集 | 双击安装 → 一键使用；卸载干净 | 1 周 |
| **M4 持续演进** | 上游 tag 跟随机制、双平台 CI 常态化、补丁上游化节奏 | 每次上游 release 一周内出对应 -d 包 | 持续 |

**总体估计：6-8 周出首个可分发版本**，最大风险集中在 M1（spawn 序列化 + capability 前端改造面）。

---

## 8. 风险与对策

| 风险 | 影响 | 对策 | 状态 |
|------|------|------|------|
| spawn 多进程序列化坑（uvicorn 父进程 + ProcessPoolExecutor） | M1 延期 | M0 结束即做 Linux 强制 spawn 全量验证 spike；池入口全部模块级函数化 | 前置验证 |
| gigatoken 无 Windows wheel | 统计慢 20-40× | sentencepiece fallback 已内建；同时评估内部编译 Windows wheel | 有兜底 |
| capability 前端改造面大（File Explorer 入口分散） | UI 改动多 | 先做入口盘点清单，统一 gate 组件，一处注册 | 提前盘点 |
| 个人 PC 内存（16-32GB）跑不动大统计 | 体验差 | 已有自适应 workers + 内存守卫；文档注明建议配置 | 有兜底 |
| 依赖裁剪误伤功能（import 图未完全盘点） | 启动失败 | M1 每拆一个依赖重跑全量 pytest + import 扫描脚本 | 流程保证 |
| 内网环境构建 Windows 产物 | 流水线难落地 | Q2 拍板：GitHub Actions windows runner 或内部 Windows 机 + 本地脚本 | 待确认 |

---

## 9. 开放问题（拍板项）

| # | 问题 | 选项 | 我的建议 |
|---|------|------|----------|
| Q1 | Gateway / S3 / volcengine / scp 首版是否随 D4 一并禁用？ | 禁用 / Gateway 保留（内网单机也有推 Gateway 场景） | 首版全部禁用，代码保留，开关随时可开 |
| Q2 | Windows 构建环境 | GitHub Actions windows-latest / 内部 Windows 构建机 / 开发机手工脚本 | 先手工脚本跑通 M2，再决定流水线 |
| Q3 | 数据目录默认位置 | `%USERPROFILE%\DataViewerData` / 安装目录内 `data\` / 首次启动让用户选 | 用户目录（卸载不丢数据） |
| Q4 | 单机登录体验 | 保留 admin 登录页（记忆登录）/ 免密直入（首次进管理员） | 保留登录页 + 记住我（改动最小） |
| Q5 | 补丁 vs 直接改主仓 | 本仓 patches/ 迭代、稳定后 PR / 直接在主仓开分支开发（本仓只做打包） | 先 patches（主仓迭代节奏不受影响），M4 转直改 |
| Q6 | 绿色包是否内嵌浏览器 | 默认浏览器打开 / 捆绑 Chromium（体积 +200MB，体验闭环） | 首版用默认浏览器 |
