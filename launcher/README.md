# launcher/ — 托盘启动器（开发者 / 打包者说明）

`launcher.py` 是 M3 的 pystray 托盘启动器，取代 M2 的 `start.bat` 成为绿色包的正式入口。
它负责：初始化目录与 secrets → 设置后端环境变量（D4/D5/D6 全关）→ 分配空闲端口 →
起 uvicorn 子进程 → 健康检查 → 打开浏览器 → 常驻托盘（Quit 时终止后端）。

## 运行方式（关键点）

- 由 **`python\pythonw.exe`** 启动：`python\pythonw.exe launcher\launcher.py`
- **无控制台窗口**靠的就是 `pythonw.exe`（GUI 子系统，不创建 console）。
  因此本进程**没有可用 stdout/stderr**——launcher 内全部用 stdlib `logging` 写
  `%LOCALAPPDATA%\DataViewerDesktop\logs\launcher.log`，**不要加顶层 `print`**。
- uvicorn 子进程则故意用 **`python.exe`**（非 pythonw）：pythonw 会剥离 stdio，
  stdout/stderr 无法重定向到 `uvicorn.log` / `uvicorn.err.log`；
  配合 `CREATE_NO_WINDOW` 标志（launcher.py 内 `CREATE_NO_WINDOW` 常量）子进程不会闪现控制台窗口。
- pystray 要求 `icon.run()` 在**主线程**运行——launcher 先完成全部启动逻辑再进入托盘循环，符合此约束。

## 依赖

launcher 依赖两个额外包（后端依赖之外的）：

| 包 | 用途 | 为什么必需 |
|---|---|---|
| `pystray` | 系统托盘图标 + 菜单 | 托盘交互的唯一实现（Win32 backend） |
| `Pillow` | 在内存中绘制 fallback 图标 | 托盘图标必须是 PIL Image；无外部图片文件 |

两包都是**硬依赖**：launcher.py 模块级 import 失败时会弹错误框提示（不会静默崩溃）。

## 打进 embeddable Python

绿色包的 `python/` 是 Windows embeddable Python（`Lib/site-packages` 已由
build-win.ps1 从后端 venv 拷入）。launcher 依赖需要追加安装：

```powershell
pip install --target <包目录>\python\Lib\site-packages pystray pillow
```

在 build-win.ps1 中就是（在步骤 3 组装 `python/` 之后执行）：

```powershell
& "$PythonOut\python.exe" -m pip install --target $SitePkgs pystray pillow
```

> embeddable Python 默认不带 pip；如构建机无 pip，可
> `curl https://bootstrap.pypa.io/get-pip.py | python.exe -` 先装 pip，
> 或改用 `uv pip install --target`（构建机已有 uv）。

## build-win.ps1 需要补的步骤（精确清单）

1. **拷贝 launcher 文件**进绿色包（组装阶段，`start.bat` 生成之前/之后均可）：

   ```powershell
   New-Item -ItemType Directory -Force -Path (Join-Path $OutputDir "launcher") | Out-Null
   Copy-Item "$PSScriptRoot\..\launcher\launcher.py"  (Join-Path $OutputDir "launcher\launcher.py")
   # icon.ico 若存在则一并拷入（不存在时 launcher 用内存绘制图标，不影响功能）
   if (Test-Path "$PSScriptRoot\..\launcher\icon.ico") {
     Copy-Item "$PSScriptRoot\..\launcher\icon.ico" (Join-Path $OutputDir "launcher\icon.ico")
   }
   ```

2. **安装 launcher 依赖**（见上节）：把 `pystray pillow` 装进
   `<包>\python\Lib\site-packages`。

3. **README-使用说明.md 改用仓库版**：删除脚本内嵌的模板生成逻辑，改为拷贝
   `docs/README-使用说明.md` 进包（`Copy-Item "$PSScriptRoot\..\docs\README-使用说明.md" $OutputDir`）。
   注意编码：文件是 UTF-8，`Copy-Item` 原样拷贝即可（不要用 `Out-File` 重编码）。

4. **start.bat 降级为手动兜底**（可保留可删除）：正式入口是
   `python\pythonw.exe launcher\launcher.py`。建议 start.bat 文案改为提示
   "请使用安装器快捷方式或托盘启动器"，或直接删除。

5. **Inno Setup 打包**（若需要安装器）：用
   `iscc /dBuildDir="<包目录>" /dAppVersion=<版本> installer\dataviewer-desktop.iss`，
   产物在 `installer\Output\`。

## icon.ico（可选）

launcher 不依赖任何外部图片：没有 `launcher/icon.ico` 时会在内存里画一个
64×64 圆角方块 + "D" 的托盘图标。若想要正式图标，在 `launcher/` 下生成一份
`icon.ico`（多尺寸 16/32/48/64 最佳），例如：

```python
# 在装有 Pillow 的环境执行（如 dev box 或构建机）
from PIL import Image, ImageDraw, ImageFont

img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
d.rounded_rectangle((2, 2, 61, 61), radius=12, fill=(0, 103, 192))
d.text((22, 12), "D", fill=(255, 255, 255), font=ImageFont.truetype("segoeui.ttf", 36))
img.save("launcher/icon.ico", format="ICO", sizes=[(16, 16), (32, 32), (48, 48), (64, 64)])
```

同时被安装器用于快捷方式图标（`[Icons]` 里引用 `{app}\launcher\icon.ico`；
文件缺失时快捷方式自动回退默认图标，不影响安装）。

## 开发环境（Linux dev box）验证

本机无 Windows，launcher 只写不跑。可做的最低限度检查：

- `python3 -m py_compile launcher/launcher.py`（语法）
- 人工核对 Windows 语义：`os.startfile`（仅 Windows）、`subprocess.CREATE_NO_WINDOW`
  （仅 Windows 存在，launcher 已用 `getattr` 兼容以便本机 lint）、路径分隔符、pythonw 无 stdout。

完整验证走 Windows CI / 真机：起服 → 登录 → 托盘菜单四项 → Quit 后进程退出、
`logs/` 下 launcher.log / uvicorn.log 齐全。

## 目录/环境契约（与 build-win.ps1、start.bat 一致，勿改）

- `DATA_ROOT=%USERPROFILE%\DataViewerData`；`CONF_DIR=%LOCALAPPDATA%\DataViewerDesktop`
- `METADATA_DIR=%CONF_DIR%\metadata`；`LOG_DIR=%CONF_DIR%\logs`
- 首启生成 `%CONF_DIR%\secrets.env`（`JWT_SECRET_KEY` 随机 + `ADMIN_PASSWORD=admin123`），
  经 `DV_SECRETS_FILE` 指向
- D4/D5/D6 外网能力 11 个开关全 `false`；`PYTHONUTF8=1`
- 端口：默认 8888，被占自动递增（最多扫描 100 个）
