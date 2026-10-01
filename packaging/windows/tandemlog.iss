; Stable identity and per-user destination preserve upgrades and external user data.
#ifndef AppVersion
  #error AppVersion must come from pubspec.yaml
#endif
#ifndef BundleDir
  #error BundleDir must contain the complete Flutter release bundle
#endif
#ifndef OutputDir
  #error OutputDir must be supplied
#endif
#ifndef MinRuntimeMinor
  #error MinRuntimeMinor must match the actual MSVC compiler
#endif
#ifndef MinRuntimeBuild
  #error MinRuntimeBuild must match the actual MSVC compiler
#endif
[Setup]
AppId=com.reddraggone9.tandemlog
AppName=Tandemlog
AppVersion={#AppVersion}
AppPublisher=reddraggone9
DefaultDirName={localappdata}\Programs\Tandemlog
DefaultGroupName=Tandemlog
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=tandemlog-windows-x64-unsigned-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\tandemlog.exe
CloseApplications=yes
RestartApplications=no
[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\Tandemlog"; Filename: "{app}\tandemlog.exe"
[Run]
Filename: "{app}\tandemlog.exe"; Description: "Launch Tandemlog"; Flags: nowait postinstall skipifsilent
; No UninstallDelete section: profile/cache/canonical folders belong to the user.

[Code]
function RuntimeFileCompatible(const Name: String): Boolean;
var
  MS, LS, Major, Minor, Build: Cardinal;
begin
  Result := False;
  if not GetVersionNumbers(ExpandConstant('{sysnative}\') + Name, MS, LS) then Exit;
  Major := MS shr 16;
  Minor := MS and $FFFF;
  Build := LS shr 16;
  Result := (Major > 14) or ((Major = 14) and
    ((Minor > {#MinRuntimeMinor}) or
    ((Minor = {#MinRuntimeMinor}) and (Build >= {#MinRuntimeBuild}))));
end;

function InitializeSetup(): Boolean;
var
  Installed: Cardinal;
begin
  Result := RegQueryDWordValue(HKLM64,
    'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', Installed);
  if Result then Result := Installed = 1;
  if Result then Result := RuntimeFileCompatible('msvcp140.dll') and
    RuntimeFileCompatible('vcruntime140.dll') and RuntimeFileCompatible('vcruntime140_1.dll');
  if not Result then
    SuppressibleMsgBox('Tandemlog needs the Microsoft Visual C++ x64 runtime (14.{#MinRuntimeMinor}.{#MinRuntimeBuild} or newer). ' +
      'No Tandemlog files have been installed. Install or update the official Microsoft runtime, then run this installer again.' + #13#10#13#10 + 'https://aka.ms/vc14/vc_redist.x64.exe' + #13#10 +
      'The Microsoft installer may require administrator permission.', mbError, MB_OK, IDOK);
end;
