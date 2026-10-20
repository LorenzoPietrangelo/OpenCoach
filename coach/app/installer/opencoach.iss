; Installer di Open Coach per Windows (Inno Setup 6).
;
; Prima: flutter build windows --release, con Tor copiato in windows\tor.
; Poi:   iscc /DVersione=1.0.0 installer\opencoach.iss
;
; L'installazione è per il solo utente e non chiede i privilegi di
; amministratore. Disinstallare lascia i dati del coach in %APPDATA%\OpenCoach:
; contengono identità, atleti e allenamenti, e si cancellano solo a mano.

#ifndef Versione
  #define Versione "1.0.0"
#endif

[Setup]
AppId={{00BC614F-0F5A-4E32-9AD4-815229F396E6}
AppName=Open Coach
AppVersion={#Versione}
AppPublisher=Open Coach
DefaultDirName={autopf}\Open Coach
DefaultGroupName=Open Coach
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\build\installer
OutputBaseFilename=OpenCoach-{#Versione}-windows-x64
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\OpenCoach.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Il programma resta nell'area di notifica: va chiuso prima di aggiornarlo.
CloseApplications=yes

[Languages]
Name: "italiano"; MessagesFile: "compiler:Languages\Italian.isl"

[Tasks]
Name: "desktop"; Description: "{cm:CreateDesktopIcon}"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Open Coach"; Filename: "{app}\OpenCoach.exe"
Name: "{autodesktop}\Open Coach"; Filename: "{app}\OpenCoach.exe"; Tasks: desktop

[Registry]
; L'avvio automatico lo attiva il programma (§9.1); alla disinstallazione
; la voce va tolta, altrimenti Windows cercherebbe un programma che non c'è.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "Open Coach"; ValueType: none; Flags: uninsdeletevalue dontcreatekey

[Run]
Filename: "{app}\OpenCoach.exe"; Description: "{cm:LaunchProgram,Open Coach}"; Flags: nowait postinstall skipifsilent
