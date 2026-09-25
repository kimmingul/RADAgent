unit RADAgent.ChatUsage;

{ The usage panel of the composer's context ring: context window use and this session's tokens
  (get_session_stats), and the plan limits of the current model's provider ("omp usage --json",
  run off the main thread, kept for a minute). Main thread only, except the CLI call. }

interface

{ The ring was clicked: sends what is known now and asks omp for the rest. }
procedure RequestUsage;
{ The get_session_stats reply RequestUsage waits for; True when handled. }
function HandleUsageResponse(const Line: string): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.JSON, Winapi.Windows, RADAgent.ChatSession,
  RADAgent.OmpCli, RADAgent.AgentSettings, RADAgent.SessionData, RADAgent.UsageReport, RADAgent.RpcResponses,
  RADAgent.ChatCommand, RADAgent.IdeContext, RADAgent.Lang;

const
  CacheMs = 60000;

var
  GStatsPending: Boolean;
  GStats: TJSONObject;
  { Plan limits of GProvider; GLimitsAt = 0 while they are being read. }
  GProvider, GUsageJson, GError: string;
  GLimitsAt: UInt64;
  GReader: TThread;
  GLoading: Boolean;

function ProviderName(const Id: string): string;
var
  Provider: TLoginProvider;
begin
  Result := Id;
  for Provider in ChatSession.Catalog.LoginProviders do
    if SameText(Provider.Id, Id) then
      Exit(Provider.Name);
end;

procedure Send;
var
  Obj, Limits: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('t', 'usage');
    if GStats <> nil then
      Obj.AddPair('stats', TJSONObject(GStats.Clone));
    Obj.AddPair('provider', ProviderName(GProvider));
    Obj.AddPair('loading', TJSONBool.Create(GLoading));
    Obj.AddPair('error', GError);
    Limits := nil;
    if GUsageJson <> '' then
      Limits := UsageLimits(GUsageJson, GProvider);
    if Limits <> nil then
      Obj.AddPair('limits', Limits);
    ChatSession.PostToView(Obj.ToJSON);
  finally
    Obj.Free;
  end;
end;

procedure ReadLimits(const Provider: string);
var
  Executable, Dir: string;
begin
  if (GReader <> nil) and not GReader.Finished then
    Exit;
  FreeAndNil(GReader);
  GLoading := True;
  Executable := OmpCommand;
  Dir := ExcludeTrailingPathDelimiter(ActiveProjectDir);
  if Dir = '' then
    Dir := GetCurrentDir;
  GReader := TThread.CreateAnonymousThread(
    procedure
    var
      Json: string;
    begin
      Json := RunOmp(Executable, 'usage --json --provider ' + Provider, Dir, 30000);
      TThread.Queue(TThread.Current,
        procedure
        begin
          GLoading := False;
          if Provider <> GProvider then
            Exit;
          GUsageJson := Json;
          GLimitsAt := GetTickCount64;
          GError := '';
          if Json = '' then
            GError := Tr('chatusage.noReport');
          Send;
        end);
    end);
  GReader.FreeOnTerminate := False;
  GReader.Start;
end;

procedure RequestUsage;
var
  Provider: string;
begin
  Provider := ChatSession.State.Provider;
  if Provider <> GProvider then
  begin
    GProvider := Provider;
    GUsageJson := '';
    GLimitsAt := 0;
    GError := '';
  end;
  if (Provider <> '') and ((GLimitsAt = 0) or (GetTickCount64 - GLimitsAt > CacheMs)) then
    ReadLimits(Provider);
  if ChatSession.Connected then
  begin
    GStatsPending := True;
    ChatSession.SendCommand('get_session_stats', BuildIdTypeFrame('req', 'get_session_stats'));
  end;
  Send;
end;

function HandleUsageResponse(const Line: string): Boolean;
var
  Ok: Boolean;
begin
  Result := GStatsPending and (ResponseOf(Line, Ok) = 'get_session_stats');
  if not Result then
    Exit;
  GStatsPending := False;
  FreeAndNil(GStats);
  if Ok then
    GStats := ResponseDataClone(Line);
  Send;
end;

initialization

finalization
  { The CLI call ends within its timeout; its reply must not run after the package is gone. }
  if GReader <> nil then
  begin
    GReader.WaitFor;
    TThread.RemoveQueuedEvents(GReader);
    GReader.Free;
  end;
  GStats.Free;

end.
