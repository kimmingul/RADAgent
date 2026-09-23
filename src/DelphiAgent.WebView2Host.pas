unit DelphiAgent.WebView2Host;

{ WebView2 control hosted directly through Winapi.WebView2 (rtl) and WebView2Loader.dll next to
  the BPL, so the package needs no vcledge. Serves <bpl>\DelphiAgent\chat through a virtual host
  and exchanges JSON messages with the page. Main thread only. }

interface

uses
  System.Classes, System.SysUtils, Winapi.Windows, Winapi.Messages, Vcl.Controls, Vcl.Graphics,
  Winapi.WebView2;

type
  TWebJsonEvent = procedure(const Json: string) of object;

  TWebView2Host = class(TWinControl)
  private
    FController: ICoreWebView2Controller;
    FWebView: ICoreWebView2;
    FPending: TStringList;
    FPageReady: Boolean;
    FStarted: Boolean;
    FProblem: string;
    FBackColor: TColor;
    FOnMessage: TWebJsonEvent;
    FOnPageReady: TNotifyEvent;
    FOnFailed: TNotifyEvent;
    procedure Fail(const Problem: string);
    procedure StartBrowser;
    procedure EnvironmentReady(ErrorCode: HResult; const Env: ICoreWebView2Environment);
    procedure ControllerReady(ErrorCode: HResult; const Controller: ICoreWebView2Controller);
    procedure WebMessage(const Args: ICoreWebView2WebMessageReceivedEventArgs);
    procedure UpdateBounds;
    procedure ApplyBackColor;
    procedure WMSetFocus(var Message: TWMSetFocus); message WM_SETFOCUS;
  protected
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Queued until the page reports t=ready. }
    procedure PostJson(const Json: string);
    procedure SetBackColor(Value: TColor);
    property PageReady: Boolean read FPageReady;
    property Problem: string read FProblem;
    property OnMessage: TWebJsonEvent read FOnMessage write FOnMessage;
    property OnPageReady: TNotifyEvent read FOnPageReady write FOnPageReady;
    property OnFailed: TNotifyEvent read FOnFailed write FOnFailed;
  end;

function ChatAssetDir: string;

implementation

uses
  System.IOUtils, Winapi.ActiveX, DelphiAgent.WebView2Handlers;

const
  HostName = 'delphiagent.local';
  PageUrl = 'https://' + HostName + '/chat.html';

type
  TCreateEnvironment = function(BrowserExecutableFolder, UserDataFolder: PWideChar;
    const Options: ICoreWebView2EnvironmentOptions;
    const Handler: ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler): HResult; stdcall;

var
  GLoader: HMODULE;

function PackageDir: string;
begin
  Result := ExtractFilePath(GetModuleName(HInstance));
end;

function ChatAssetDir: string;
begin
  Result := PackageDir + 'DelphiAgent\chat';
end;

function UserDataDir: string;
begin
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('LOCALAPPDATA')) +
    'DelphiAgent\WebView2';
end;

function TakeString(Value: PWideChar): string;
begin
  Result := Value;
  CoTaskMemFree(Value);
end;

constructor TWebView2Host.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPending := TStringList.Create;
  FBackColor := clBlack;
  TabStop := True;
end;

destructor TWebView2Host.Destroy;
begin
  if FController <> nil then
    FController.Close;
  FWebView := nil;
  FController := nil;
  FPending.Free;
  inherited Destroy;
end;

procedure TWebView2Host.Fail(const Problem: string);
begin
  FProblem := Problem;
  if Assigned(FOnFailed) then
    FOnFailed(Self);
end;

procedure TWebView2Host.CreateWnd;
begin
  inherited CreateWnd;
  if FController <> nil then
  begin
    FController.Set_ParentWindow(wireHWND(Handle));
    UpdateBounds;
  end
  else if not FStarted then
    StartBrowser;
end;

procedure TWebView2Host.DestroyWnd;
begin
  { Docking re-creates the handle; park the browser instead of losing it. }
  if (FController <> nil) and not (csDestroying in ComponentState) then
    FController.Set_ParentWindow(wireHWND(HWND_MESSAGE));
  inherited DestroyWnd;
end;

procedure TWebView2Host.StartBrowser;
var
  LoaderPath: string;
  CreateEnvironment: TCreateEnvironment;
  Hr: HResult;
begin
  FStarted := True;
  if not FileExists(ChatAssetDir + '\chat.html') then
  begin
    Fail('채팅 페이지 파일이 없습니다: ' + ChatAssetDir);
    Exit;
  end;
  if GLoader = 0 then
  begin
    LoaderPath := PackageDir + 'DelphiAgent\WebView2Loader.dll';
    GLoader := SafeLoadLibrary(LoaderPath);
    if GLoader = 0 then
    begin
      Fail('WebView2Loader.dll을 불러오지 못했습니다: ' + LoaderPath);
      Exit;
    end;
  end;
  @CreateEnvironment := GetProcAddress(GLoader, 'CreateCoreWebView2EnvironmentWithOptions');
  if not Assigned(CreateEnvironment) then
  begin
    Fail('WebView2Loader.dll에 환경 생성 함수가 없습니다.');
    Exit;
  end;
  ForceDirectories(UserDataDir);
  Hr := CreateEnvironment(nil, PWideChar(UserDataDir), nil,
    TEnvironmentCompleted.Create(EnvironmentReady));
  if Failed(Hr) then
    Fail(Format('WebView2 런타임을 시작하지 못했습니다 (0x%.8x). Edge WebView2 런타임 설치를 확인하세요.', [Hr]));
end;

procedure TWebView2Host.EnvironmentReady(ErrorCode: HResult; const Env: ICoreWebView2Environment);
begin
  if Failed(ErrorCode) or (Env = nil) then
  begin
    Fail(Format('WebView2 환경을 만들지 못했습니다 (0x%.8x).', [ErrorCode]));
    Exit;
  end;
  if not HandleAllocated then
    HandleNeeded;
  Env.CreateCoreWebView2Controller(Handle, TControllerCompleted.Create(ControllerReady));
end;

procedure TWebView2Host.ControllerReady(ErrorCode: HResult; const Controller: ICoreWebView2Controller);
var
  Settings: ICoreWebView2Settings;
  Settings3: ICoreWebView2Settings3;
  View3: ICoreWebView2_3;
  Token: EventRegistrationToken;
begin
  if Failed(ErrorCode) or (Controller = nil) then
  begin
    Fail(Format('WebView2 컨트롤을 만들지 못했습니다 (0x%.8x).', [ErrorCode]));
    Exit;
  end;
  if csDestroying in ComponentState then
  begin
    Controller.Close;
    Exit;
  end;
  FController := Controller;
  FController.Get_CoreWebView2(FWebView);
  ApplyBackColor;
  if Succeeded(FWebView.Get_Settings(Settings)) then
  begin
    Settings.Set_AreDevToolsEnabled(0);
    Settings.Set_IsStatusBarEnabled(0);
    Settings.Set_AreHostObjectsAllowed(0);
    if Supports(Settings, ICoreWebView2Settings3, Settings3) then
      Settings3.Set_AreBrowserAcceleratorKeysEnabled(0);
  end;
  if not Supports(FWebView, ICoreWebView2_3, View3) then
  begin
    Fail('WebView2 런타임이 너무 오래되었습니다. 런타임을 업데이트하세요.');
    Exit;
  end;
  View3.SetVirtualHostNameToFolderMapping(HostName, PWideChar(ChatAssetDir),
    COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY_CORS);
  FWebView.add_WebMessageReceived(TWebMessageHandler.Create(WebMessage), Token);
  FWebView.add_NavigationStarting(TNavigationGuard.Create('https://' + HostName + '/'), Token);
  FWebView.add_NewWindowRequested(TNewWindowBlocker.Create, Token);
  UpdateBounds;
  FController.Set_IsVisible(1);
  FWebView.Navigate(PageUrl);
end;

procedure TWebView2Host.WebMessage(const Args: ICoreWebView2WebMessageReceivedEventArgs);
var
  Raw: PWideChar;
  Json: string;
  Index: Integer;
begin
  if Failed(Args.Get_webMessageAsJson(Raw)) then
    Exit;
  Json := TakeString(Raw);
  if not FPageReady and Json.Contains('"t":"ready"') then
  begin
    FPageReady := True;
    for Index := 0 to FPending.Count - 1 do
      FWebView.PostWebMessageAsJson(PWideChar(FPending[Index]));
    FPending.Clear;
    if Assigned(FOnPageReady) then
      FOnPageReady(Self);
    Exit;
  end;
  if Assigned(FOnMessage) then
    FOnMessage(Json);
end;

procedure TWebView2Host.PostJson(const Json: string);
begin
  if FPageReady and (FWebView <> nil) then
    FWebView.PostWebMessageAsJson(PWideChar(Json))
  else
    FPending.Add(Json);
end;

procedure TWebView2Host.UpdateBounds;
var
  Bounds: tagRECT;
begin
  if (FController = nil) or not HandleAllocated then
    Exit;
  Bounds.left := 0;
  Bounds.top := 0;
  Bounds.right := ClientWidth;
  Bounds.bottom := ClientHeight;
  FController.Set_Bounds(Bounds);
end;

procedure TWebView2Host.Resize;
begin
  inherited Resize;
  UpdateBounds;
end;

procedure TWebView2Host.SetBackColor(Value: TColor);
begin
  FBackColor := Value;
  Color := Value;
  ApplyBackColor;
end;

procedure TWebView2Host.ApplyBackColor;
var
  Controller2: ICoreWebView2Controller2;
  Rgb: Longint;
  Value: COREWEBVIEW2_COLOR;
begin
  if not Supports(FController, ICoreWebView2Controller2, Controller2) then
    Exit;
  Rgb := ColorToRGB(FBackColor);
  Value.A := 255;
  Value.R := GetRValue(Rgb);
  Value.G := GetGValue(Rgb);
  Value.B := GetBValue(Rgb);
  Controller2.Set_DefaultBackgroundColor(Value);
end;

procedure TWebView2Host.WMSetFocus(var Message: TWMSetFocus);
begin
  inherited;
  if FController <> nil then
    FController.MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);
end;

initialization

finalization
  { The runtime keeps browser processes; the loader stays until package unload. }
  if GLoader <> 0 then
    FreeLibrary(GLoader);

end.
