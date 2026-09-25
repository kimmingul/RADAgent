; RADAgent setup (Inno Setup 6). Built by scripts\package.ps1, which stages the signed BPLs under
; PayloadDir\<BDS version>\<Win32|Win64>\ and passes AppVersion, PayloadDir, OutputDir and, when
; signing, Sign=1 with the SignTool "nanum".
;
; Per-user install (no administrator rights): files go to %LOCALAPPDATA%\Programs\RADAgent and
; each chosen IDE gets the package in HKCU\Software\Embarcadero\BDS\<version>\Known Packages
; (Known Packages x64 for the 64-bit IDE of RAD Studio 13).

#ifndef AppVersion
  #define AppVersion "1.0.0.0"
#endif
#ifndef PayloadDir
  #define PayloadDir "..\artifacts\package\payload"
#endif
#ifndef OutputDir
  #define OutputDir "..\dist"
#endif

#define Publisher "Nanum Space Co., Ltd."
#define Description "RADAgent - an agentic coding assistant for Delphi, powered by oh-my-pi"

; Which packages this setup carries: only the releases staged by package.ps1.
#define Has370w32 FileExists(PayloadDir + "\37.0\Win32\RADAgent370.bpl")
#define Has370w64 FileExists(PayloadDir + "\37.0\Win64\RADAgent370.bpl")
#define Has290w32 FileExists(PayloadDir + "\23.0\Win32\RADAgent290.bpl")
#define Has280w32 FileExists(PayloadDir + "\22.0\Win32\RADAgent280.bpl")
#define Has270w32 FileExists(PayloadDir + "\21.0\Win32\RADAgent270.bpl")
#if !Has370w32 && !Has370w64 && !Has290w32 && !Has280w32 && !Has270w32
  #error No staged package under PayloadDir. Run scripts\package.ps1.
#endif

[Setup]
AppId={{8E4B2C1D-6A3F-4B7E-9C2D-1F5A7E3B9D40}
AppName=RADAgent
AppVersion={#AppVersion}
AppVerName=RADAgent {#AppVersion}
AppPublisher={#Publisher}
AppCopyright=Copyright (C) 2026 {#Publisher}
AppComments={#Description}
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#Publisher}
VersionInfoDescription=RADAgent Setup
VersionInfoProductName=RADAgent
VersionInfoProductVersion={#AppVersion}
DefaultDirName={autopf}\RADAgent
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
DisableReadyMemo=no
OutputDir={#OutputDir}
OutputBaseFilename=RADAgent-Setup-{#AppVersion}
SetupIconFile=..\resources\RADAgent.ico
UninstallDisplayIcon={app}\RADAgent.ico
UninstallDisplayName=RADAgent
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ShowLanguageDialog=auto
LanguageDetectionMethod=uilanguage
CloseApplications=no
#ifdef Sign
SignTool=nanum
SignedUninstaller=yes
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"
Name: "japanese"; MessagesFile: "compiler:Languages\Japanese.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[CustomMessages]
english.Ide32=32-bit IDE
english.Ide64=64-bit IDE
english.NoIde=No supported RAD Studio was found on this PC (13 Florence, 12 Athens, 11 Alexandria or 10.4 Sydney that this setup carries).
english.CloseIde=RAD Studio is running. Close every RAD Studio window, then click Next.
english.CloseIdeUninstall=RAD Studio is running. Close every RAD Studio window and run the uninstaller again.
english.OpenOmp=Open the oh-my-pi (omp) install page (omp was not found; RADAgent needs it)
english.OpenWebView2=Open the Microsoft Edge WebView2 Runtime page (not found; without it the chat is plain text)
english.DeleteSettings=Also delete RADAgent settings and data (IDE settings, side-question notes, downloaded clangd, chat browser data)?
english.TypeCustom=Custom
english.ComponentsLabel=RAD Studio IDEs to add RADAgent to:
korean.Ide32=32비트 IDE
korean.Ide64=64비트 IDE
korean.NoIde=이 PC에서 지원하는 RAD Studio를 찾지 못했습니다(이 설치 파일이 담은 13 Florence, 12 Athens, 11 Alexandria, 10.4 Sydney).
korean.CloseIde=RAD Studio가 실행 중입니다. RAD Studio 창을 모두 닫은 뒤 다음을 누르세요.
korean.CloseIdeUninstall=RAD Studio가 실행 중입니다. RAD Studio 창을 모두 닫고 제거를 다시 실행하세요.
korean.OpenOmp=oh-my-pi(omp) 설치 페이지 열기 (omp를 찾지 못했습니다. RADAgent에 필요합니다)
korean.OpenWebView2=Microsoft Edge WebView2 런타임 페이지 열기 (없으면 채팅이 글자 화면으로 보입니다)
korean.DeleteSettings=RADAgent 설정과 데이터(IDE 설정, 곁가지 질문 메모, 받은 clangd, 채팅 브라우저 데이터)도 지울까요?
korean.TypeCustom=사용자 지정
korean.ComponentsLabel=RADAgent를 추가할 RAD Studio IDE:
japanese.Ide32=32 ビット IDE
japanese.Ide64=64 ビット IDE
japanese.NoIde=この PC で対応する RAD Studio が見つかりません (このセットアップに含まれる 13 Florence、12 Athens、11 Alexandria、10.4 Sydney)。
japanese.CloseIde=RAD Studio が実行中です。RAD Studio のウィンドウをすべて閉じてから [次へ] をクリックしてください。
japanese.CloseIdeUninstall=RAD Studio が実行中です。RAD Studio のウィンドウをすべて閉じてから、アンインストールをもう一度実行してください。
japanese.OpenOmp=oh-my-pi (omp) のインストール ページを開く (omp が見つかりません。RADAgent に必要です)
japanese.OpenWebView2=Microsoft Edge WebView2 ランタイムのページを開く (ない場合、チャットはテキスト表示になります)
japanese.DeleteSettings=RADAgent の設定とデータ (IDE 設定、サイド質問のメモ、ダウンロードした clangd、チャットのブラウザー データ) も削除しますか?
japanese.TypeCustom=カスタム
japanese.ComponentsLabel=RADAgent を追加する RAD Studio IDE:
german.Ide32=32-Bit-IDE
german.Ide64=64-Bit-IDE
german.NoIde=Auf diesem PC wurde kein unterstütztes RAD Studio gefunden (13 Florence, 12 Athens, 11 Alexandria oder 10.4 Sydney, die dieses Setup enthält).
german.CloseIde=RAD Studio läuft. Schließen Sie alle RAD Studio-Fenster und klicken Sie dann auf Weiter.
german.CloseIdeUninstall=RAD Studio läuft. Schließen Sie alle RAD Studio-Fenster und starten Sie die Deinstallation erneut.
german.OpenOmp=Installationsseite von oh-my-pi (omp) öffnen (omp wurde nicht gefunden; RADAgent benötigt es)
german.OpenWebView2=Seite der Microsoft Edge WebView2-Laufzeit öffnen (nicht gefunden; ohne sie zeigt der Chat nur Text)
german.DeleteSettings=Auch die Einstellungen und Daten von RADAgent löschen (IDE-Einstellungen, Notizen zu Nebenfragen, heruntergeladenes clangd, Browserdaten des Chats)?
german.TypeCustom=Benutzerdefiniert
german.ComponentsLabel=RAD Studio-IDEs, denen RADAgent hinzugefügt wird:
french.Ide32=EDI 32 bits
french.Ide64=EDI 64 bits
french.NoIde=Aucun RAD Studio pris en charge n'a été trouvé sur ce PC (13 Florence, 12 Athens, 11 Alexandria ou 10.4 Sydney que contient ce programme d'installation).
french.CloseIde=RAD Studio est en cours d'exécution. Fermez toutes les fenêtres de RAD Studio, puis cliquez sur Suivant.
french.CloseIdeUninstall=RAD Studio est en cours d'exécution. Fermez toutes les fenêtres de RAD Studio et relancez la désinstallation.
french.OpenOmp=Ouvrir la page d'installation d'oh-my-pi (omp) (introuvable ; RADAgent en a besoin)
french.OpenWebView2=Ouvrir la page du runtime Microsoft Edge WebView2 (introuvable ; sans lui, le chat s'affiche en texte)
french.DeleteSettings=Supprimer aussi les paramètres et données de RADAgent (paramètres de l'EDI, notes des questions annexes, clangd téléchargé, données du navigateur du chat) ?
french.TypeCustom=Personnalisée
french.ComponentsLabel=EDI RAD Studio auxquels ajouter RADAgent :

[Types]
Name: "custom"; Description: "{cm:TypeCustom}"; Flags: iscustom

[Components]
#if Has370w64
Name: "rs370w64"; Description: "RAD Studio 13 Florence - {cm:Ide64}"; Types: custom; Check: IdeInstalled('37.0', True)
#endif
#if Has370w32
Name: "rs370w32"; Description: "RAD Studio 13 Florence - {cm:Ide32}"; Types: custom; Check: IdeInstalled('37.0', False)
#endif
#if Has290w32
Name: "rs290w32"; Description: "RAD Studio 12 Athens - {cm:Ide32}"; Types: custom; Check: IdeInstalled('23.0', False)
#endif
#if Has280w32
Name: "rs280w32"; Description: "RAD Studio 11 Alexandria - {cm:Ide32}"; Types: custom; Check: IdeInstalled('22.0', False)
#endif
#if Has270w32
Name: "rs270w32"; Description: "RAD Studio 10.4 Sydney - {cm:Ide32}"; Types: custom; Check: IdeInstalled('21.0', False)
#endif

[Files]
Source: "..\resources\RADAgent.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "THIRD-PARTY-NOTICES.txt"; DestDir: "{app}"; Flags: ignoreversion
#if Has370w64
Source: "{#PayloadDir}\37.0\Win64\*"; DestDir: "{app}\37.0\Win64"; Flags: ignoreversion recursesubdirs; Components: rs370w64
#endif
#if Has370w32
Source: "{#PayloadDir}\37.0\Win32\*"; DestDir: "{app}\37.0\Win32"; Flags: ignoreversion recursesubdirs; Components: rs370w32
#endif
#if Has290w32
Source: "{#PayloadDir}\23.0\Win32\*"; DestDir: "{app}\23.0\Win32"; Flags: ignoreversion recursesubdirs; Components: rs290w32
#endif
#if Has280w32
Source: "{#PayloadDir}\22.0\Win32\*"; DestDir: "{app}\22.0\Win32"; Flags: ignoreversion recursesubdirs; Components: rs280w32
#endif
#if Has270w32
Source: "{#PayloadDir}\21.0\Win32\*"; DestDir: "{app}\21.0\Win32"; Flags: ignoreversion recursesubdirs; Components: rs270w32
#endif

; Known Packages: value name = BPL path, data = description. A disabled entry for the same path
; would keep the IDE from loading it, so that one goes.
[Registry]
#if Has370w64
Root: HKCU; Subkey: "Software\Embarcadero\BDS\37.0\Known Packages x64"; ValueType: string; ValueName: "{app}\37.0\Win64\RADAgent370.bpl"; ValueData: "{#Description}"; Flags: uninsdeletevalue; Components: rs370w64
Root: HKCU; Subkey: "Software\Embarcadero\BDS\37.0\Disabled Packages x64"; ValueType: none; ValueName: "{app}\37.0\Win64\RADAgent370.bpl"; Flags: deletevalue; Components: rs370w64
#endif
#if Has370w32
Root: HKCU; Subkey: "Software\Embarcadero\BDS\37.0\Known Packages"; ValueType: string; ValueName: "{app}\37.0\Win32\RADAgent370.bpl"; ValueData: "{#Description}"; Flags: uninsdeletevalue; Components: rs370w32
Root: HKCU; Subkey: "Software\Embarcadero\BDS\37.0\Disabled Packages"; ValueType: none; ValueName: "{app}\37.0\Win32\RADAgent370.bpl"; Flags: deletevalue; Components: rs370w32
#endif
#if Has290w32
Root: HKCU; Subkey: "Software\Embarcadero\BDS\23.0\Known Packages"; ValueType: string; ValueName: "{app}\23.0\Win32\RADAgent290.bpl"; ValueData: "{#Description}"; Flags: uninsdeletevalue; Components: rs290w32
Root: HKCU; Subkey: "Software\Embarcadero\BDS\23.0\Disabled Packages"; ValueType: none; ValueName: "{app}\23.0\Win32\RADAgent290.bpl"; Flags: deletevalue; Components: rs290w32
#endif
#if Has280w32
Root: HKCU; Subkey: "Software\Embarcadero\BDS\22.0\Known Packages"; ValueType: string; ValueName: "{app}\22.0\Win32\RADAgent280.bpl"; ValueData: "{#Description}"; Flags: uninsdeletevalue; Components: rs280w32
Root: HKCU; Subkey: "Software\Embarcadero\BDS\22.0\Disabled Packages"; ValueType: none; ValueName: "{app}\22.0\Win32\RADAgent280.bpl"; Flags: deletevalue; Components: rs280w32
#endif
#if Has270w32
Root: HKCU; Subkey: "Software\Embarcadero\BDS\21.0\Known Packages"; ValueType: string; ValueName: "{app}\21.0\Win32\RADAgent270.bpl"; ValueData: "{#Description}"; Flags: uninsdeletevalue; Components: rs270w32
Root: HKCU; Subkey: "Software\Embarcadero\BDS\21.0\Disabled Packages"; ValueType: none; ValueName: "{app}\21.0\Win32\RADAgent270.bpl"; Flags: deletevalue; Components: rs270w32
#endif

[Run]
Filename: "https://github.com/can1357/oh-my-pi"; Description: "{cm:OpenOmp}"; Flags: postinstall shellexec skipifsilent; Check: OmpMissing
Filename: "https://developer.microsoft.com/microsoft-edge/webview2/"; Description: "{cm:OpenWebView2}"; Flags: postinstall shellexec skipifsilent unchecked; Check: WebView2Missing

[Code]
const
  WebView2Client = 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';

function IdeRoot(const Version: String): String;
begin
  if not RegQueryStringValue(HKLM32, 'SOFTWARE\Embarcadero\BDS\' + Version, 'RootDir', Result) then
    Result := '';
end;

{ The IDE of that bitness is installed: bin\bds.exe, or bin64\bds.exe for the 64-bit IDE. }
function IdeInstalled(const Version: String; Win64: Boolean): Boolean;
var
  Root: String;
begin
  Root := IdeRoot(Version);
  if Root = '' then
    Result := False
  else if Win64 then
    Result := FileExists(AddBackslash(Root) + 'bin64\bds.exe')
  else
    Result := FileExists(AddBackslash(Root) + 'bin\bds.exe');
end;

function AnyTarget: Boolean;
begin
  Result := False;
#if Has370w64
  Result := Result or IdeInstalled('37.0', True);
#endif
#if Has370w32
  Result := Result or IdeInstalled('37.0', False);
#endif
#if Has290w32
  Result := Result or IdeInstalled('23.0', False);
#endif
#if Has280w32
  Result := Result or IdeInstalled('22.0', False);
#endif
#if Has270w32
  Result := Result or IdeInstalled('21.0', False);
#endif
end;

{ The RAD Studio main window (both bitnesses and every release use this class). }
function IdeRunning: Boolean;
begin
  Result := FindWindowByClassName('TAppBuilder') <> 0;
end;

function OmpMissing: Boolean;
begin
  Result := not FileExists(ExpandConstant('{localappdata}\omp\omp.exe')) and
    (FileSearch('omp.exe', GetEnv('PATH')) = '');
end;

function WebView2Missing: Boolean;
var
  Version: String;
begin
  if not RegQueryStringValue(HKLM32, WebView2Client, 'pv', Version) then
    if not RegQueryStringValue(HKCU, WebView2Client, 'pv', Version) then
      Version := '';
  Result := (Version = '') or (Version = '0.0.0.0');
end;

function InitializeSetup: Boolean;
begin
  Result := AnyTarget;
  if not Result then
    SuppressibleMsgBox(CustomMessage('NoIde'), mbError, MB_OK, IDOK);
end;

procedure InitializeWizard;
begin
  WizardForm.SelectComponentsLabel.Caption := CustomMessage('ComponentsLabel');
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  if IdeRunning then
    Result := CustomMessage('CloseIde')
  else
    Result := '';
end;

{ Two packages with the same name cannot load together: drop other registrations of this file
  name (an older install elsewhere, or a developer build). }
procedure KeepOnlyOurs(const Key, BplPath: String);
var
  Names: TArrayOfString;
  Index: Integer;
begin
  if not RegGetValueNames(HKCU, Key, Names) then
    Exit;
  for Index := 0 to GetArrayLength(Names) - 1 do
    if (CompareText(ExtractFileName(Names[Index]), ExtractFileName(BplPath)) = 0) and
      (CompareText(Names[Index], BplPath) <> 0) then
      RegDeleteValue(HKCU, Key, Names[Index]);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep <> ssPostInstall then
    Exit;
#if Has370w64
  if WizardIsComponentSelected('rs370w64') then
    KeepOnlyOurs('Software\Embarcadero\BDS\37.0\Known Packages x64', ExpandConstant('{app}\37.0\Win64\RADAgent370.bpl'));
#endif
#if Has370w32
  if WizardIsComponentSelected('rs370w32') then
    KeepOnlyOurs('Software\Embarcadero\BDS\37.0\Known Packages', ExpandConstant('{app}\37.0\Win32\RADAgent370.bpl'));
#endif
#if Has290w32
  if WizardIsComponentSelected('rs290w32') then
    KeepOnlyOurs('Software\Embarcadero\BDS\23.0\Known Packages', ExpandConstant('{app}\23.0\Win32\RADAgent290.bpl'));
#endif
#if Has280w32
  if WizardIsComponentSelected('rs280w32') then
    KeepOnlyOurs('Software\Embarcadero\BDS\22.0\Known Packages', ExpandConstant('{app}\22.0\Win32\RADAgent280.bpl'));
#endif
#if Has270w32
  if WizardIsComponentSelected('rs270w32') then
    KeepOnlyOurs('Software\Embarcadero\BDS\21.0\Known Packages', ExpandConstant('{app}\21.0\Win32\RADAgent270.bpl'));
#endif
end;

function InitializeUninstall: Boolean;
begin
  Result := not IdeRunning;
  if not Result then
    SuppressibleMsgBox(CustomMessage('CloseIdeUninstall'), mbError, MB_OK, IDOK);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep <> usPostUninstall) or UninstallSilent then
    Exit;
  if MsgBox(CustomMessage('DeleteSettings'), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) <> IDYES then
    Exit;
  RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Embarcadero\BDS\37.0\RADAgent');
  RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Embarcadero\BDS\23.0\RADAgent');
  RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Embarcadero\BDS\22.0\RADAgent');
  RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Embarcadero\BDS\21.0\RADAgent');
  DelTree(ExpandConstant('{localappdata}\RADAgent'), True, True, True);
end;
