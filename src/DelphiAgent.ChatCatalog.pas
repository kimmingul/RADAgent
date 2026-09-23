unit DelphiAgent.ChatCatalog;

{ What the running omp offers for the settings window: models, thinking levels and login
  providers, refreshed from command responses. Version bumps on every update. No VCL. }

interface

uses
  DelphiAgent.RpcResponses;

type
  TSendCommand = procedure(const FrameType, Frame: string) of object;

  TChatCatalog = class
  private
    FModels, FLevels: TArray<string>;
    FProviders: TArray<TLoginProvider>;
    FVersion: Integer;
    FPendingLogin: string;
  public
    procedure Request(const Send: TSendCommand);
    { True when Line was one of the catalog responses. }
    function Accept(const Line: string): Boolean;
    procedure Touch;
    { omp runs one login at a time and answers nothing else until it ends; '' clears it. }
    procedure SetPendingLogin(const ProviderName: string);
    property Models: TArray<string> read FModels;
    property ThinkingLevels: TArray<string> read FLevels;
    property LoginProviders: TArray<TLoginProvider> read FProviders;
    property Version: Integer read FVersion;
    { Provider name of the login omp is still running, or ''. }
    property PendingLogin: string read FPendingLogin;
  end;

implementation

uses
  System.JSON, DelphiAgent.ChatCommand, DelphiAgent.RpcJson;

procedure TChatCatalog.Request(const Send: TSendCommand);
begin
  Send('get_available_models', BuildIdTypeFrame('req', 'get_available_models'));
  Send('get_available_thinking_levels', BuildIdTypeFrame('req', 'get_available_thinking_levels'));
  Send('get_login_providers', BuildIdTypeFrame('req', 'get_login_providers'));
  Send('get_state', BuildIdTypeFrame('req', 'get_state'));
end;

{ Success or failure: either way the login is over. }
function IsLoginResponse(const Line: string): Boolean;
var
  Root: TJSONObject;
begin
  Root := JsonObject(Line);
  try
    Result := (JsonStr(Root, 'type') = 'response') and (JsonStr(Root, 'command') = 'login');
  finally
    Root.Free;
  end;
end;

function TChatCatalog.Accept(const Line: string): Boolean;
var
  Names: TArray<string>;
  Providers: TArray<TLoginProvider>;
begin
  Result := True;
  if (FPendingLogin <> '') and IsLoginResponse(Line) then
  begin
    FPendingLogin := '';
    Touch;
  end;
  if ParseModelList(Line, Names) then
    FModels := Names
  else if ParseThinkingLevels(Line, Names) then
    FLevels := Names
  else if ParseLoginProviders(Line, Providers) then
    FProviders := Providers
  else
    Exit(False);
  Touch;
end;

procedure TChatCatalog.SetPendingLogin(const ProviderName: string);
begin
  FPendingLogin := ProviderName;
  Touch;
end;

procedure TChatCatalog.Touch;
begin
  Inc(FVersion);
end;

end.
