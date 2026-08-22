; DataViewer Desktop — Inno Setup installer (M3 productization)
;
; Installs the green bundle produced by scripts/build-win.ps1 (the
; "<version>/" directory) into a per-user location and registers an
; uninstaller plus Start Menu / desktop shortcuts.
;
; Why {localappdata}\Programs\DataViewerDesktop (per-user) instead of
; {userpf}\DataViewerDesktop:
;   - No admin rights / UAC prompt needed on install or uninstall.
;   - Fits a single-admin desktop tool that never touches machine-wide state.
;   - Keeps user data (%USERPROFILE%\DataViewerData) and app state
;     (%LOCALAPPDATA%\DataViewerDesktop) clearly outside {app}, so the
;     uninstaller provably never deletes them (D8: uninstall keeps data).
;
; Build (ISCC.exe comes with Inno Setup 6):
;   iscc /dBuildDir="..\build\v4.10.1-d1" installer\dataviewer-desktop.iss
; Output: installer\Output\DataViewerDesktopSetup-<version>.exe
;
; Launcher entry point:
;   {app}\python\pythonw.exe {app}\launcher\launcher.py
; pythonw.exe => no console window; the launcher draws its own tray icon.

#ifndef BuildDir
  ; Default: one level up from the repo root is the build output dir used by
  ; build-win.ps1 (its -OutputDir default is <repo>\build\<version>).
  #define BuildDir "..\build\v4.10.1-d1"
  #pragma message "BuildDir not defined, using default: " + BuildDir
#endif

#ifndef AppVersion
  ; Keep in sync with the -d version being built (e.g. v4.10.1-d1).
  #define AppVersion "4.10.1-d1"
#endif

#define AppName "DataViewer Desktop"
#define AppPublisher "DataViewer"
#define AppExePythonw "{app}\python\pythonw.exe"
#define AppLauncher "{app}\launcher\launcher.py"

; Custom icon for shortcuts: launcher\icon.ico if it exists in this repo,
; otherwise fall back to the default installer icon (also fine — the tray
; icon itself is drawn in memory by the launcher and never depends on it).
#define IconFile "..\launcher\icon.ico"
#define HasCustomIcon FileExists(IconFile)

[Setup]
AppId={{9D4E2F1A-5B6C-4A7E-9C0D-D8E7F6A5B4C3}}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\Programs\DataViewerDesktop
DisableProgramGroupPage=yes
; Per-user install: no admin rights, no UAC prompt.
PrivilegesRequired=lowest
; x64 only (the bundle ships 64-bit embeddable Python).
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
; Shortcuts.
DefaultGroupName={#AppName}
#if HasCustomIcon
SetupIconFile={#IconFile}
UninstallDisplayIcon={#IconFile}
#endif
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
OutputDir=Output
OutputBaseFilename=DataViewerDesktopSetup-{#AppVersion}
; Data preservation contract (D8): the uninstaller only ever removes files
; under {app}. %USERPROFILE%\DataViewerData and %LOCALAPPDATA%\DataViewerDesktop
; are outside {app} and therefore untouched — no extra guards needed.
CloseApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
; The whole green bundle: backend sources, frontend/dist, python (embeddable
; Python + site-packages), launcher, desktop.env.template, README.
; NOTE: start.bat is included for manual fallback but is no longer the entry
; point (M3): shortcuts launch pythonw.exe + launcher.py.
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
; Start Menu + desktop shortcuts -> pythonw.exe launcher.py (no console).
; Icon: the bundle's launcher\icon.ico if the build shipped one; if it is
; missing the shortcut simply falls back to the default Windows icon
; (ISCC does not require the file to exist — the launcher's own tray icon
; is drawn in memory and never depends on this file).
Name: "{group}\{#AppName}"; Filename: "{#AppExePythonw}"; Parameters: "{#AppLauncher}"; WorkingDir: "{app}"; IconFilename: "{app}\launcher\icon.ico"; Comment: "Start DataViewer Desktop"
Name: "{userdesktop}\{#AppName}"; Filename: "{#AppExePythonw}"; Parameters: "{#AppLauncher}"; WorkingDir: "{app}"; IconFilename: "{app}\launcher\icon.ico"; Comment: "Start DataViewer Desktop"; Tasks: desktopicon

[Run]
; Offer to start the app right after a successful install.
Filename: "{#AppExePythonw}"; Parameters: "{#AppLauncher}"; WorkingDir: "{app}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Nothing outside {app} is deleted. This section exists only to be explicit
; about the contract: no entries -> %USERPROFILE%\DataViewerData (user data)
; and %LOCALAPPDATA%\DataViewerDesktop (secrets, metadata, logs) survive
; uninstall by design (D8). Users who want them gone can delete the folders
; manually after uninstalling.
; (If Inno Setup ever warns the bundle dir is non-empty after uninstall, add:
; Type: filesandordirs; Name: "{app}\*"   and   Type: dirifempty; Name: "{app}")
