# DataViewer Desktop 使用说明

DataViewer Desktop 是 DataViewer 的单机 Windows 版：本地启动服务、本地浏览器打开，
数据全部保存在本机，不依赖任何内网或外网服务。

## 安装

两种方式任选其一：

- **绿色包**（`DataViewer-Desktop-<版本>-win64.zip`）：解压到任意目录（建议路径不含中文与空格），
  进入解压后的目录双击 `start.bat` 即可（简单场景），更完整的体验建议装安装器。
- **安装器**（`DataViewerDesktopSetup-<版本>.exe`）：双击安装，按向导完成。
  安装目录为 `%LOCALAPPDATA%\Programs\DataViewerDesktop`（当前用户专用，无需管理员权限）。

## 启动

- 安装后双击桌面或开始菜单的 **DataViewer Desktop** 快捷方式；
- 程序无窗口，只在**系统托盘**（任务栏右下角）显示图标；
- 首次启动会自动完成初始化，然后自动打开浏览器页面
  （地址 `http://127.0.0.1:8888`；若 8888 端口被占用会自动改用其他端口）；
- 托盘图标右键菜单：

| 菜单项 | 作用 |
|---|---|
| Open DataViewer | 重新打开浏览器页面 |
| Open Data Folder | 打开数据目录（File Explorer） |
| View Logs | 打开日志目录 |
| Quit | 退出程序（同时停止后台服务） |

> 注意：关闭浏览器页面**不会**停止程序，后台服务仍在运行，请用托盘的 **Quit** 退出。

## 登录

- 账号：`admin`；初始密码：`admin123`（首次启动自动生成，见
  `%LOCALAPPDATA%\DataViewerDesktop\secrets.env`）。
- **首次登录后请立即修改密码**（页面右上角用户菜单）。
- 登录后浏览器会记住登录状态（"记住我"），下次打开免登录。

## 数据放在哪里

- **数据目录（File Explorer 根）**：`%USERPROFILE%\DataViewerData`
  （即 `C:\Users\<你的用户名>\DataViewerData`）。
  浏览文件时把 JSONL 等文件放进这个目录即可在页面里看到。
- **盘符浏览**：File Explorer 顶部可切换根目录，直接浏览 `C:\`、`D:\` 等全部盘符
  （含 USB/移动盘），并对文件进行查看、上传、下载、删除、移动等操作。
- **程序数据**（元数据库、密钥、日志）：`%LOCALAPPDATA%\DataViewerDesktop`
  （即 `C:\Users\<你的用户名>\AppData\Local\DataViewerDesktop`）。

## 日志位置

- 启动器日志：`%LOCALAPPDATA%\DataViewerDesktop\logs\launcher.log`
- 后端服务日志：`%LOCALAPPDATA%\DataViewerDesktop\logs\uvicorn.log` 与 `uvicorn.err.log`
- 托盘菜单 **View Logs** 可直接打开日志目录。

遇到问题请把整个 `logs` 目录打包反馈。

## 卸载

- 控制面板 → 程序和功能 → 卸载 **DataViewer Desktop**（或用安装器自带的卸载程序）。
- **卸载不会删除你的数据**：`%USERPROFILE%\DataViewerData`（你的文件）与
  `%LOCALAPPDATA%\DataViewerDesktop`（元数据、密钥、日志）都会保留。
  如需彻底清除，卸载后手动删除这两个目录即可。
- 绿色包方式：直接删除解压目录即可，无残留。

## 已知限制（首版）

- **外网能力全部不可用**：Gateway 推送/拉取、Datalab 一键质检、HF 下载、
  Arena 导入、Ask Claude、S3、Volcengine、SCP、Traj-Viz、Workbench 等入口均已隐藏或返回"不可用"。
- **PanguML / ML1.5 校验不可用**（依赖 workbench 组件，首版未打包）。
- Convert to ATIF / Validate ATIF 等**本地格式转换与校验可用**。
- 数据集统计（dataset-stats）多进程使用 Windows spawn 方式，**首次统计任务启动稍慢**属正常；
  token 计数在无 gigatoken 时自动回退到 sentencepiece，速度会明显变慢，属预期。
- 使用系统**默认浏览器**打开页面；暂不支持更换内置浏览器。
- 端口自动分配：默认 8888，被占用时自动递增查找。

## 常见问题

- **双击快捷方式没反应**：查看 `%LOCALAPPDATA%\DataViewerDesktop\logs\launcher.log`
  是否有报错；也可能是 8888~8987 端口全部被占用（概率极低）。
- **改了端口后浏览器打不开**：用托盘菜单 **Open DataViewer** 重新打开（launcher 会自动用当前端口）。
- **忘记密码**：删除 `%LOCALAPPDATA%\DataViewerDesktop\secrets.env` 后重启程序，
  密码会重置为 `admin123`（注意：同时会更换 JWT 密钥，已登录的页面需要重新登录）。
