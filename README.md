# DataViewer Desktop

DataViewer 的**单机 Windows 版**（路线 B：原生绿色包 + 托盘启动器）。

- **上游**：`/data/projects/DataViewer`（业务代码唯一来源，单一代码库共同演进）
- **本仓定位**：产品化/打包层 —— 适配补丁栈、Windows 启动器、安装器、CI、文档
- **方案文档**：[docs/plan.md](docs/plan.md)（唯一计划文档，讨论结论回写到其中的 ADR 表）

## 当前状态

**立项完成，进入 M0（脚手架）**（2026-08-19）。Q1-Q6 已拍板（ADR D1-D11，仅 D6 待确认）。

> **开工入口**：[docs/kickoff.md](docs/kickoff.md) —— 在本仓对 Claude 说"按 kickoff 开始工作"即可执行 M0。

## 目录

| 路径 | 说明 |
|------|------|
| `docs/plan.md` | 实现方案与总体计划（含决策记录、适配清单、里程碑） |
| `patches/` | 对上游的适配补丁栈（目标：全部上游化后归零） |
| `scripts/` | 同步/构建脚本（sync-upstream.sh、build-win.ps1） |
| `launcher/` | Windows 托盘启动器（pystray） |
| `installer/` | Inno Setup 安装脚本 |
| `.github/workflows/` | 流水线定义（linux-pytest / windows-build） |
| `workspace/` | [gitignore] 上游工作树（clone + 补丁应用，不提交） |

## 关键决策速览

- 不用 PyInstaller 单 exe；产物 = 绿色 zip + Inno Setup 安装器
- 业务代码不 fork：适配改动以 patch 形式迭代，最终提交回 DataViewer 主仓
- 首版禁用：ray、datalab、HF、arena、claude API（及待确认的 Gateway/S3/volcengine/scp）
- 版本号：`<上游tag>-d<N>`（如 `v4.10.1-d1`）
