unit RADAgent.AgentSettings;

{ RADAgent's own options under the IDE registry key (HKCU\...\RADAgent). They never touch
  omp config files. }

interface

type
  TChatShow = (csThinking, csToolInput, csToolOutput, csTodos, csSubagents, csRetries, csNotices);
  TChatShows = set of TChatShow;

const
  AllChatShows = [Low(TChatShow)..High(TChatShow)];
  { Keys the chat page uses for each kind (chat.js "display" message). }
  ChatShowKeys: array[TChatShow] of string = ('thinking', 'toolInput', 'toolOutput', 'todos',
    'subagents', 'retries', 'notices');
  DefaultFontSize = 13;

function ChatShowCaption(Show: TChatShow): string;
function ChatShowCaptions(Show: TChatShow): string;

function ChatShows: TChatShows;
procedure SetChatShows(Value: TChatShows);
function HighContrastEnabled: Boolean;
procedure SetHighContrast(Value: Boolean);
function ChatFontSize: Integer;
procedure SetChatFontSize(Value: Integer);
{ A Windows notification when a turn ends while the IDE is in the background (on by default). }
function TurnNotifications: Boolean;
procedure SetTurnNotifications(Value: Boolean);
{ omp.exe chosen by the user; '' means search PATH. }
function OmpPathOverride: string;
procedure SetOmpPathOverride(const Value: string);
{ The omp to start: the override or the one found on PATH. }
function OmpCommand: string;
{ Per project (<project>\.omp\radagent-ide.json, not the omp --config): whether omp may edit
  form files as text through rad.form_text_edit ("auto") or only use the designer ("designer"). }
function FormTextAllowed(const ProjectDir: string): Boolean;
procedure SetFormTextAllowed(const ProjectDir: string; Value: Boolean);
{ Same file: fixed UI must be built in the form designer ("designer", the default) or may also be
  created in code ("free"). }
function DesignerUiRequired(const ProjectDir: string): Boolean;
procedure SetDesignerUiRequired(const ProjectDir: string; Value: Boolean);
{ clangd.exe (or its folder) for C++Builder projects; '' means search PATH. }
function ClangdPath: string;
procedure SetClangdPath(const Value: string);
{ Extra command line arguments appended after --mode rpc. }
function OmpExtraArgs: string;
procedure SetOmpExtraArgs(const Value: string);
{ omp works (thinks, plans, briefs subagents) in English and answers in the user's language. }
function EnglishWork: Boolean;
procedure SetEnglishWork(Value: Boolean);
{ Language code of the user interface ('' = the system language); see RADAgent.Lang. }
function LanguageCode: string;
procedure SetLanguageCode(const Value: string);
{ omp version that last passed RADAgent's compatibility check (RADAgent.OmpProbe). }
function CheckedOmpVersion: string;
procedure SetCheckedOmpVersion(const Value: string);

implementation

uses
  System.SysUtils, System.Variants, System.Win.Registry, System.IOUtils, System.JSON, Winapi.Windows, ToolsAPI,
  RADAgent.Options, RADAgent.Lang;

function OptionKey: string;
var
  Services: IOTAServices;
begin
  if Supports(BorlandIDEServices, IOTAServices, Services) then
    Result := Services.GetBaseRegistryKey + '\RADAgent'
  else
    Result := 'Software\RADAgent';
end;

function ReadValue(const Name: string; const Default: Variant): Variant;
var
  Reg: TRegistry;
begin
  Result := Default;
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly(OptionKey) and Reg.ValueExists(Name) then
      case Reg.GetDataType(Name) of
        rdInteger: Result := Reg.ReadInteger(Name);
        rdString, rdExpandString: Result := Reg.ReadString(Name);
      end;
  finally
    Reg.Free;
  end;
end;

procedure WriteValue(const Name: string; const Value: Variant);
var
  Reg: TRegistry;
begin
  Reg := TRegistry.Create(KEY_WRITE);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKey(OptionKey, True) then
      if VarIsStr(Value) then
        Reg.WriteString(Name, Value)
      else
        Reg.WriteInteger(Name, Value);
  finally
    Reg.Free;
  end;
end;

function ChatShows: TChatShows;
var
  Bits: Integer;
  Show: TChatShow;
begin
  Bits := ReadValue('ChatShows', -1);
  Result := [];
  for Show := Low(TChatShow) to High(TChatShow) do
    if Bits and (1 shl Ord(Show)) <> 0 then
      Include(Result, Show);
end;

procedure SetChatShows(Value: TChatShows);
var
  Bits: Integer;
  Show: TChatShow;
begin
  Bits := 0;
  for Show in Value do
    Bits := Bits or (1 shl Ord(Show));
  WriteValue('ChatShows', Bits);
end;

function ChatShowCaption(Show: TChatShow): string;
begin
  case Show of
    csThinking: Result := Tr('agentsettings.showThinking');
    csToolInput: Result := Tr('agentsettings.showToolInput');
    csToolOutput: Result := Tr('agentsettings.showToolOutput');
    csTodos: Result := Tr('agentsettings.showTodos');
    csSubagents: Result := Tr('agentsettings.showSubagents');
    csRetries: Result := Tr('agentsettings.showRetries');
    csNotices: Result := Tr('agentsettings.showNotices');
  else
    Result := '';
  end;
end;

function ChatShowCaptions(Show: TChatShow): string;
begin
  Result := ChatShowCaption(Show);
end;

function HighContrastEnabled: Boolean;
begin
  Result := Integer(ReadValue('HighContrast', 0)) <> 0;
end;

procedure SetHighContrast(Value: Boolean);
begin
  WriteValue('HighContrast', Ord(Value));
end;

function ChatFontSize: Integer;
begin
  Result := ReadValue('FontSize', DefaultFontSize);
  if (Result < 9) or (Result > 24) then
    Result := DefaultFontSize;
end;

procedure SetChatFontSize(Value: Integer);
begin
  WriteValue('FontSize', Value);
end;

function TurnNotifications: Boolean;
begin
  Result := Integer(ReadValue('TurnNotify', 1)) <> 0;
end;

procedure SetTurnNotifications(Value: Boolean);
begin
  WriteValue('TurnNotify', Ord(Value));
end;

function OmpPathOverride: string;
begin
  Result := Trim(string(ReadValue('OmpPath', '')));
end;

procedure SetOmpPathOverride(const Value: string);
begin
  WriteValue('OmpPath', Trim(Value));
end;

function OmpCommand: string;
begin
  Result := OmpPathOverride;
  if Result = '' then
    Result := OmpExecutable;
end;

function IdeSettingsFile(const ProjectDir: string): string;
begin
  Result := TPath.Combine(TPath.Combine(ProjectDir, '.omp'), 'radagent-ide.json');
end;

function ReadIdeSetting(const ProjectDir, Key, Default: string): string;
var
  Root: TJSONValue;
begin
  Result := Default;
  if (ProjectDir = '') or not FileExists(IdeSettingsFile(ProjectDir)) then
    Exit;
  Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(IdeSettingsFile(ProjectDir), TEncoding.UTF8));
  try
    if Root is TJSONObject then
      Result := TJSONObject(Root).GetValue<string>(Key, Default);
  finally
    Root.Free;
  end;
end;

{ Keeps the other keys; the default value is not stored, and an empty file goes away. }
procedure WriteIdeSetting(const ProjectDir, Key, Value, Default: string);
var
  Root: TJSONValue;
  Obj: TJSONObject;
begin
  if ProjectDir = '' then
    Exit;
  Root := nil;
  if FileExists(IdeSettingsFile(ProjectDir)) then
    Root := TJSONObject.ParseJSONValue(TFile.ReadAllText(IdeSettingsFile(ProjectDir), TEncoding.UTF8));
  if not (Root is TJSONObject) then
  begin
    Root.Free;
    Root := TJSONObject.Create;
  end;
  Obj := TJSONObject(Root);
  try
    Obj.RemovePair(Key).Free;
    if Value <> Default then
      Obj.AddPair(Key, Value);
    if Obj.Count = 0 then
      System.SysUtils.DeleteFile(IdeSettingsFile(ProjectDir))
    else
    begin
      ForceDirectories(ExtractFileDir(IdeSettingsFile(ProjectDir)));
      TFile.WriteAllText(IdeSettingsFile(ProjectDir), Obj.ToJSON, TEncoding.UTF8);
    end;
  finally
    Obj.Free;
  end;
end;

function FormTextAllowed(const ProjectDir: string): Boolean;
begin
  Result := ReadIdeSetting(ProjectDir, 'formEditing', 'auto') <> 'designer';
end;

procedure SetFormTextAllowed(const ProjectDir: string; Value: Boolean);
const
  Values: array[Boolean] of string = ('designer', 'auto');
begin
  WriteIdeSetting(ProjectDir, 'formEditing', Values[Value], 'auto');
end;

function DesignerUiRequired(const ProjectDir: string): Boolean;
begin
  Result := ReadIdeSetting(ProjectDir, 'uiBuilding', 'designer') <> 'free';
end;

procedure SetDesignerUiRequired(const ProjectDir: string; Value: Boolean);
const
  Values: array[Boolean] of string = ('free', 'designer');
begin
  WriteIdeSetting(ProjectDir, 'uiBuilding', Values[Value], 'designer');
end;

function ClangdPath: string;
begin
  Result := Trim(string(ReadValue('ClangdPath', '')));
end;

procedure SetClangdPath(const Value: string);
begin
  WriteValue('ClangdPath', Trim(Value));
end;

function OmpExtraArgs: string;
begin
  Result := Trim(string(ReadValue('OmpArgs', '')));
end;

procedure SetOmpExtraArgs(const Value: string);
begin
  WriteValue('OmpArgs', Trim(Value));
end;

function EnglishWork: Boolean;
begin
  Result := Integer(ReadValue('EnglishWork', 0)) <> 0;
end;

procedure SetEnglishWork(Value: Boolean);
begin
  WriteValue('EnglishWork', Ord(Value));
end;

function LanguageCode: string;
begin
  Result := Trim(string(ReadValue('Language', '')));
end;

procedure SetLanguageCode(const Value: string);
begin
  WriteValue('Language', Value);
  SelectLanguage(Value);
end;

function CheckedOmpVersion: string;
begin
  Result := Trim(string(ReadValue('OmpCheckedVersion', '')));
end;

procedure SetCheckedOmpVersion(const Value: string);
begin
  WriteValue('OmpCheckedVersion', Value);
end;


initialization
  LanguageSetting := LanguageCode;

end.
