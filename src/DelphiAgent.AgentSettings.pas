unit DelphiAgent.AgentSettings;

{ DelphiAgent's own options under the IDE registry key (HKCU\...\DelphiAgent). They never touch
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
  ChatShowCaptions: array[TChatShow] of string = ('생각 내용', '도구 입력(모델이 쓰는 코드·명령)',
    '도구 실행 중 출력', '작업 목록', '하위 에이전트 진행', '재시도·모델 대체', 'omp 알림');
  DefaultFontSize = 13;

function ChatShows: TChatShows;
procedure SetChatShows(Value: TChatShows);
function HighContrastEnabled: Boolean;
procedure SetHighContrast(Value: Boolean);
function ChatFontSize: Integer;
procedure SetChatFontSize(Value: Integer);
{ omp.exe chosen by the user; '' means search PATH. }
function OmpPathOverride: string;
procedure SetOmpPathOverride(const Value: string);
{ The omp to start: the override or the one found on PATH. }
function OmpCommand: string;
{ Extra command line arguments appended after --mode rpc. }
function OmpExtraArgs: string;
procedure SetOmpExtraArgs(const Value: string);
{ omp works (thinks, plans, briefs subagents) in English and answers in the user's language. }
function EnglishWork: Boolean;
procedure SetEnglishWork(Value: Boolean);
{ omp version that last passed DelphiAgent's compatibility check (DelphiAgent.OmpProbe). }
function CheckedOmpVersion: string;
procedure SetCheckedOmpVersion(const Value: string);

implementation

uses
  System.SysUtils, System.Variants, System.Win.Registry, Winapi.Windows, ToolsAPI,
  DelphiAgent.Options;

function OptionKey: string;
var
  Services: IOTAServices;
begin
  if Supports(BorlandIDEServices, IOTAServices, Services) then
    Result := Services.GetBaseRegistryKey + '\DelphiAgent'
  else
    Result := 'Software\DelphiAgent';
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

function CheckedOmpVersion: string;
begin
  Result := Trim(string(ReadValue('OmpCheckedVersion', '')));
end;

procedure SetCheckedOmpVersion(const Value: string);
begin
  WriteValue('OmpCheckedVersion', Value);
end;


end.
