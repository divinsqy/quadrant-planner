#define MyAppName "象限计划"
#define MyAppVersion "1.0.0"
#define MyAppExeName "quadrant_planner.exe"

[Setup]
AppId={{2D2891D9-9135-4A9B-A5DD-969DFE37E5BE}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher=Divins
DefaultDirName={localappdata}\Programs\Quadrant Planner
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
OutputDir=..\..\dist\windows
OutputBaseFilename=QuadrantPlanner-Setup-{#MyAppVersion}-win-x64
UninstallDisplayIcon={app}\{#MyAppExeName}

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加选项："; Flags: unchecked

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动 {#MyAppName}"; Flags: nowait postinstall skipifsilent
