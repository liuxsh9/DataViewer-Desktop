#!/usr/bin/env python3
"""
DataViewer Desktop — system tray launcher (M3).

Runs under the green bundle's embeddable Python via ``pythonw.exe``, which
means there is NO console window and NO usable stdout/stderr on this process.
All diagnostics go through the stdlib ``logging`` module into
%LOCALAPPDATA%\\DataViewerDesktop\\logs\\launcher.log.

What it does (in order):
  1. Ensure CONF_DIR / METADATA_DIR / LOG_DIR / DATA_ROOT exist.
  2. First launch: generate %CONF_DIR%\\secrets.env (random JWT_SECRET_KEY +
     default ADMIN_PASSWORD=admin123).
  3. Build the backend environment: DV_SECRETS_FILE, DATA_ROOT, METADATA_DIR,
     LOG_DIR, PYTHONUTF8=1 and the full set of first-release capability
     kill-switches (D4/D5/D6) — all "false" so no external request is ever
     made from a desktop install.
  4. Allocate a free TCP port on 127.0.0.1 (default 8888, increments until
     one is free).
  5. Start the backend as a child process: ``python.exe -m uvicorn
     main:app --app-dir backend --host 127.0.0.1 --port <port>``.
     * python.exe (NOT pythonw.exe) is used so stdout/stderr can be captured
       into uvicorn.log / uvicorn.err.log.
     * CREATE_NO_WINDOW keeps that child from flashing a console.
  6. Poll http://127.0.0.1:<port>/api/health until ready; on timeout show a
     message box and exit gracefully.
  7. Open the default browser at the health-passing URL, then enter the
     system tray icon loop (blocks until "Quit").

Tray menu (English): Open DataViewer / Open Data Folder / View Logs / Quit.
Quit terminates the uvicorn child (terminate(), then kill() after a grace
period) and stops the tray icon.

Dependencies (extra to the backend's own requirements; install into the
embeddable Python's site-packages, see launcher/README.md):
  - pystray  : cross-platform system tray icon + menu (Win32 backend here).
  - Pillow   : renders the fallback tray icon in memory (rounded square +
               "D"). Without Pillow there would be no icon to show at all.

Requires Python 3.12 (matches the bundled embeddable Python).
Windows-only by design; there is deliberately no sys.platform branching.
"""

import logging
import os
import secrets
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
import webbrowser
from pathlib import Path

# pystray / Pillow are hard dependencies for this launcher (packaging error if
# missing — see launcher/README.md for the pip --target install command).
# Checked at module level so main() can show a message box instead of dying
# silently: pythonw.exe has no console, so an uncaught ImportError would be
# invisible to the user.
try:
    import pystray
    from PIL import Image as _PILImage  # noqa: F401 — verify Pillow present too
except ImportError:
    pystray = None

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

APP_NAME = "DataViewer Desktop"

# Green bundle layout (assembled by build-win.ps1):
#   <bundle>/launcher/launcher.py   <- this file
#   <bundle>/backend/               <- upstream source + desktop patches
#   <bundle>/frontend/dist/         <- built frontend static assets
#   <bundle>/python/                <- embeddable Python 3.12
APP_DIR = Path(__file__).resolve().parent.parent
LAUNCHER_DIR = Path(__file__).resolve().parent
BACKEND_DIR = APP_DIR / "backend"
PYTHON_DIR = APP_DIR / "python"
PYTHON_EXE = PYTHON_DIR / "python.exe"  # child backend process (has stdio)

# Windows-only process-creation flag: give the child no console window.
# subprocess.CREATE_NO_WINDOW exists only on Windows builds of Python; the
# launcher itself is Windows-only (pythonw.exe), so the constant is resolved
# once here instead of sprinkling sys.platform checks through the code.
CREATE_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0x08000000)

# Run-time directory contract (matches build-win.ps1 / start.bat):
#   DATA_ROOT    = %USERPROFILE%\DataViewerData        (File Explorer root)
#   CONF_DIR     = %LOCALAPPDATA%\DataViewerDesktop
#   METADATA_DIR = %CONF_DIR%\metadata
#   LOG_DIR      = %CONF_DIR%\logs
_LOCALAPPDATA = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
_USERPROFILE = Path(os.environ.get("USERPROFILE", Path.home()))
CONF_DIR = _LOCALAPPDATA / "DataViewerDesktop"
METADATA_DIR = CONF_DIR / "metadata"
LOG_DIR = CONF_DIR / "logs"
DATA_ROOT = _USERPROFILE / "DataViewerData"

SECRETS_FILE = CONF_DIR / "secrets.env"
ICON_FILE = LAUNCHER_DIR / "icon.ico"  # optional; fallback is drawn in memory

DEFAULT_PORT = 8888
PORT_SCAN_LIMIT = 100          # try DEFAULT_PORT..DEFAULT_PORT+99
HEALTH_TIMEOUT = 30            # seconds to wait for /api/health
HEALTH_INTERVAL = 0.5          # seconds between health polls
SHUTDOWN_GRACE = 5             # seconds to wait for uvicorn after terminate()

# First release disables every external capability (D4/D5/D6): the backend
# must never attempt an outbound request from a desktop install. Mirrored in
# build-win.ps1's desktop.env.template / start.bat.
CAPABILITY_DISABLES = {
    "GATEWAY_PUSH_ENABLED": "false",
    "DATALAB_ENABLED": "false",
    "HF_ENABLED": "false",
    "ARENA_ENABLED": "false",
    "CLAUDE_ENABLED": "false",
    "S3_ENABLED": "false",
    "VOLCENGINE_ENABLED": "false",
    "SCP_ENABLED": "false",
    "QUALITY_RAY_ENABLED": "false",
    "TRAJ_VIZ_ENABLED": "false",
    "WORKBENCH_ENABLED": "false",
}

logger = logging.getLogger("launcher")

# Backend child process; set in main() and used by the tray callbacks.
uvicorn_proc: subprocess.Popen | None = None
backend_port: int = DEFAULT_PORT


# ---------------------------------------------------------------------------
# Logging (must work with pythonw.exe: no console attached)
# ---------------------------------------------------------------------------

def setup_logging() -> None:
    """Configure file logging; pythonw.exe has no console, so a file is the
    only channel. UTF-8 always (log messages may contain Unicode)."""
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    fmt = logging.Formatter(
        "%(asctime)s %(levelname)s %(name)s: %(message)s", datefmt="%Y-%m-%d %H:%M:%S"
    )
    file_handler = logging.FileHandler(
        LOG_DIR / "launcher.log", encoding="utf-8"
    )
    file_handler.setFormatter(fmt)
    root = logging.getLogger()
    root.setLevel(logging.INFO)
    root.addHandler(file_handler)
    logger.info("Logging initialized: %s", LOG_DIR / "launcher.log")


# ---------------------------------------------------------------------------
# Directory & secret bootstrap
# ---------------------------------------------------------------------------

def ensure_directories() -> None:
    """Create the run-time directories. DATA_ROOT must exist because the
    backend calls shutil.disk_usage() on it at startup (Linux online servers
    pre-create /data; Windows has nothing, so the launcher creates it)."""
    CONF_DIR.mkdir(parents=True, exist_ok=True)
    METADATA_DIR.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    DATA_ROOT.mkdir(parents=True, exist_ok=True)
    logger.info("Directories ready: CONF=%s METADATA=%s LOG=%s DATA_ROOT=%s",
                CONF_DIR, METADATA_DIR, LOG_DIR, DATA_ROOT)


def ensure_secrets() -> None:
    """Generate secrets.env on first launch. Once it exists it is never
    touched again (the backend reads it every start via DV_SECRETS_FILE)."""
    if SECRETS_FILE.exists():
        logger.info("secrets.env already present: %s", SECRETS_FILE)
        return
    SECRETS_FILE.write_text(
        "JWT_SECRET_KEY=" + secrets.token_hex(32) + "\n"
        "ADMIN_PASSWORD=admin123\n",
        encoding="utf-8",
    )
    logger.info("Generated %s with a fresh JWT_SECRET_KEY (default admin password)",
                SECRETS_FILE)


# ---------------------------------------------------------------------------
# Port allocation
# ---------------------------------------------------------------------------

def find_free_port() -> int:
    """Return the first free TCP port on 127.0.0.1 starting at DEFAULT_PORT.
    Bind-and-release has a tiny race window but is the standard approach for
    launchers; a port grabbed in between simply shows up at health-poll time."""
    for port in range(DEFAULT_PORT, DEFAULT_PORT + PORT_SCAN_LIMIT):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            try:
                sock.bind(("127.0.0.1", port))
                return port
            except OSError:
                logger.info("Port %d in use, trying next", port)
    raise RuntimeError(
        f"No free port in range {DEFAULT_PORT}-{DEFAULT_PORT + PORT_SCAN_LIMIT - 1}"
    )


# ---------------------------------------------------------------------------
# Backend process management
# ---------------------------------------------------------------------------

def build_env(port: int) -> dict:
    """Environment for the uvicorn child: the run-time contract plus the
    full capability disable set (D4/D5/D6). PYTHONUTF8=1 is mandatory — the
    Windows console codepage (cp1252) cannot encode the Unicode top-level
    prints in the source (e.g. the pilot.py check mark)."""
    env = os.environ.copy()
    env["DV_SECRETS_FILE"] = str(SECRETS_FILE)
    env["DATA_ROOT"] = str(DATA_ROOT)
    env["METADATA_DIR"] = str(METADATA_DIR)
    env["LOG_DIR"] = str(LOG_DIR)
    env["PYTHONUTF8"] = "1"
    # PORT is informational (uvicorn gets --port explicitly).
    env["PORT"] = str(port)
    env.update(CAPABILITY_DISABLES)
    return env


def start_uvicorn(port: int, env: dict) -> subprocess.Popen:
    """Start ``python.exe -m uvicorn main:app --app-dir backend ...``.

    python.exe rather than pythonw.exe: pythonw detaches stdio (stdout/stderr
    are None and cannot be redirected), and we want uvicorn's output in
    LOG_DIR. CREATE_NO_WINDOW hides the console that python.exe would
    otherwise open — without it the child flashes a black window."""
    # Log files opened in append mode, UTF-8 like everything else.
    stdout_log = open(LOG_DIR / "uvicorn.log", "a", encoding="utf-8")
    stderr_log = open(LOG_DIR / "uvicorn.err.log", "a", encoding="utf-8")

    proc = subprocess.Popen(
        [
            str(PYTHON_EXE),
            "-m", "uvicorn",
            "main:app",
            "--app-dir", str(BACKEND_DIR),
            "--host", "127.0.0.1",
            "--port", str(port),
        ],
        stdout=stdout_log,
        stderr=stderr_log,
        env=env,
        creationflags=CREATE_NO_WINDOW,
    )
    logger.info("uvicorn started: PID=%d python=%s port=%d stdout=%s stderr=%s",
                proc.pid, PYTHON_EXE, port, LOG_DIR / "uvicorn.log",
                LOG_DIR / "uvicorn.err.log")
    return proc


def stop_uvicorn(proc: subprocess.Popen) -> None:
    """Terminate the backend: terminate() first, kill() after a grace period.
    Safe to call on an already-dead process."""
    if proc.poll() is not None:
        logger.info("uvicorn already exited (code=%s)", proc.returncode)
        return
    logger.info("Terminating uvicorn (PID=%d)", proc.pid)
    proc.terminate()
    try:
        proc.wait(timeout=SHUTDOWN_GRACE)
        logger.info("uvicorn exited cleanly (code=%s)", proc.returncode)
    except subprocess.TimeoutExpired:
        logger.warning("uvicorn did not exit in %ds, killing", SHUTDOWN_GRACE)
        proc.kill()
        proc.wait()
        logger.info("uvicorn killed")


def wait_for_health(port: int) -> bool:
    """Poll GET /api/health until 200 or HEALTH_TIMEOUT elapses."""
    url = f"http://127.0.0.1:{port}/api/health"
    deadline = time.monotonic() + HEALTH_TIMEOUT
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=2) as resp:
                if resp.status == 200:
                    logger.info("Backend healthy: %s", url)
                    return True
                logger.info("Health check returned status %d", resp.status)
        except (urllib.error.URLError, urllib.error.HTTPError,
                ConnectionResetError, ConnectionRefusedError, OSError) as exc:
            logger.debug("Health poll not ready: %s", exc)
        time.sleep(HEALTH_INTERVAL)
    return False


# ---------------------------------------------------------------------------
# Error dialog (tkinter ships with the embeddable Python)
# ---------------------------------------------------------------------------

def show_error(title: str, message: str) -> None:
    """Show a modal error box. Under pythonw.exe there is no console, so the
    message box is the only way the user sees the failure. Never raises."""
    try:
        import tkinter as tk
        from tkinter import messagebox
        root = tk.Tk()
        root.withdraw()  # hide the empty root window behind the dialog
        messagebox.showerror(title, message)
        root.destroy()
    except Exception as exc:  # tk unavailable or headless — fall back to log
        logger.error("Could not show message box (%s); message was: %s", exc, message)


# ---------------------------------------------------------------------------
# Tray icon (Pillow fallback drawn in memory — no external image files)
# ---------------------------------------------------------------------------

def load_icon():
    """Return a PIL Image for the tray: launcher/icon.ico if present,
    otherwise a simple 64x64 rounded-square "D" drawn at runtime.

    Pillow is required regardless — pystray needs an Image, and the fallback
    path draws one. Icons are explicitly NOT shipped as binary assets in the
    repo; the fallback keeps the launcher self-contained."""
    from PIL import Image, ImageDraw, ImageFont

    if ICON_FILE.exists():
        try:
            img = Image.open(ICON_FILE)
            logger.info("Using icon.ico: %s", ICON_FILE)
            return img
        except Exception as exc:
            logger.warning("Failed to load icon.ico (%s), falling back to drawn icon", exc)

    logger.info("No icon.ico found, drawing fallback icon in memory")
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    # Rounded-square background (blue, same hue family as the tray text).
    draw.rounded_rectangle((2, 2, 61, 61), radius=12, fill=(0, 103, 192))
    # "D" glyph centered; prefer a system font, fall back to the tiny default.
    font = None
    for name in ("segoeui.ttf", "arial.ttf", "consola.ttf"):
        try:
            font = ImageFont.truetype(name, 36)
            break
        except OSError:
            continue
    if font is None:
        font = ImageFont.load_default()
    bbox = draw.textbbox((0, 0), "D", font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    draw.text(((64 - text_w) / 2, (64 - text_h) / 2 - 1), "D",
              fill=(255, 255, 255), font=font)
    return img


# ---------------------------------------------------------------------------
# Tray menu & callbacks
# ---------------------------------------------------------------------------

def make_tray_menu(icon) -> None:
    """Attach the tray menu. Called from the icon thread setup; callbacks
    fire on pystray's thread, so they must not block (Popen/startfile/urlopen
    are all fine)."""

    def on_open(icon, item):  # noqa: ARG001
        webbrowser.open(f"http://127.0.0.1:{backend_port}")

    def on_data_folder(icon, item):  # noqa: ARG001
        os.startfile(str(DATA_ROOT))

    def on_view_logs(icon, item):  # noqa: ARG001
        os.startfile(str(LOG_DIR))

    def on_quit(icon, item):  # noqa: ARG001
        logger.info("Quit requested from tray menu")
        icon.stop()  # stop() must be called before the process exits
        stop_uvicorn(uvicorn_proc)

    icon.menu = pystray.Menu(
        pystray.MenuItem("Open DataViewer", on_open, default=True),
        pystray.MenuItem("Open Data Folder", on_data_folder),
        pystray.MenuItem("View Logs", on_view_logs),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("Quit", on_quit),
    )


def run_tray(port: int, proc: subprocess.Popen) -> None:
    """Create the tray icon and enter the blocking icon loop (main thread —
    pystray requires icon.run() on the main thread on Windows)."""
    global uvicorn_proc, backend_port
    uvicorn_proc = proc
    backend_port = port

    try:
        image = load_icon()
    except Exception as exc:
        logger.error("Could not create tray icon (%s): %s", type(exc).__name__, exc)
        show_error(
            APP_NAME,
            "Failed to load/create the tray icon.\n\n"
            f"Error: {exc}\n\n"
            "The application will now close.",
        )
        stop_uvicorn(proc)
        sys.exit(1)

    icon = pystray.Icon(APP_NAME, image, APP_NAME)
    make_tray_menu(icon)
    logger.info("Entering tray loop (Quit terminates the backend)")
    icon.run()  # blocks until icon.stop() from the Quit callback
    logger.info("Tray loop exited")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> int:
    setup_logging()
    logger.info("==== DataViewer Desktop launcher starting (python %s) ====",
                sys.version.split()[0])

    if pystray is None:
        # Packaging error: pystray/Pillow not installed into the embeddable
        # Python. Fail loudly and early (before starting the backend).
        logger.error("Missing dependency: pystray / Pillow not importable")
        show_error(
            APP_NAME,
            "Missing required dependency (pystray / Pillow).\n\n"
            "This is a packaging error — reinstall the bundle, or see\n"
            "launcher/README.md for the pip --target install command.",
        )
        return 1

    try:
        ensure_directories()
        ensure_secrets()
        port = find_free_port()
        env = build_env(port)
        proc = start_uvicorn(port, env)
    except Exception as exc:
        logger.exception("Startup failed")
        show_error(APP_NAME, f"Failed to start DataViewer Desktop:\n\n{exc}")
        return 1

    # uvicorn may have exited immediately (bad import, missing dep...).
    if proc.poll() is not None:
        logger.error("uvicorn exited immediately with code=%s", proc.returncode)
        show_error(
            APP_NAME,
            "The DataViewer backend exited immediately.\n\n"
            f"Check the logs in:\n{LOG_DIR}\n\n"
            "The application will now close.",
        )
        return 1

    if not wait_for_health(port):
        logger.error("Backend did not become healthy within %ds", HEALTH_TIMEOUT)
        show_error(
            APP_NAME,
            "DataViewer backend did not respond within "
            f"{HEALTH_TIMEOUT} seconds.\n\n"
            f"Logs: {LOG_DIR}\n"
            f"uvicorn output: {LOG_DIR / 'uvicorn.err.log'}\n\n"
            "The application will now close.",
        )
        stop_uvicorn(proc)
        return 1

    # Backend is up: hand the user a browser tab, then park in the tray.
    webbrowser.open(f"http://127.0.0.1:{port}")
    logger.info("Browser opened at http://127.0.0.1:%d", port)

    run_tray(port, proc)
    logger.info("Launcher exiting cleanly")
    return 0


if __name__ == "__main__":
    sys.exit(main())
