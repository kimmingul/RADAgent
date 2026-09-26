unit RADAgent.WebView2Host;

{ WebView2 control hosted directly through RADAgent.WebView2Api and WebView2Loader.dll next to
  the BPL, so the package needs no vcledge and no release-specific Winapi.WebView2. Serves
  <bpl>\RADAgent\chat through a virtual host and exchanges JSON messages with the page.
  Docking, pinning and layout changes re-create the control's window: the browser is parked in a
  hidden window meanwhile and put back, so the page stays as it is. Should that fail (the browser
  window died with its old parent), a new browser loads the page again and PageLoads counts up so
  the owner can show the chat again. Main thread only. }

interface

uses
  System.Classes, System.SysUtils, Winapi.Windows, Winapi.Messages, Vcl.Controls, Vcl.Graphics,
  RADAgent.WebView2Api, RADAgent.WebView2Handlers;

type
  TWebJsonEvent = procedure(const Json: string) of object;

  TWebView2Host = class(TWinControl)
  private
    FLifetimeGate: IWebView2LifetimeGate;
    FEnvironment: ICoreWebView2Environment;
    FController: ICoreWebView2Controller;
    FWebView: ICoreWebView2;
    FPending: TStringList;
    FPageReady: Boolean;
    FStarted: Boolean;
    FLoads: Integer;
    FProblem: string;
    FBackColor: TColor;
    FOnMessage: TWebJsonEvent;
    FOnPageReady: TNotifyEvent;
    FOnFailed: TNotifyEvent;
    function Alive: Boolean;
    procedure Fail(const Problem: string);
    procedure StartBrowser;
    procedure CreateController;
    procedure DropController;
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
    { Times the page was loaded: above 1 it is a fresh page that has to be shown the chat again. }
    property PageLoads: Integer read FLoads;
    property Problem: string read FProblem;
    property OnMessage: TWebJsonEvent read FOnMessage write FOnMessage;
    property OnPageReady: TNotifyEvent read FOnPageReady write FOnPageReady;
    property OnFailed: TNotifyEvent read FOnFailed write FOnFailed;
  end;

function ChatAssetDir: string;

implementation

uses
  System.IOUtils, Winapi.ActiveX, RADAgent.Lang;

const
  HostName = 'radagent.local';
  PageUrl = 'https://' + HostName + '/chat.html';

type
  TCreateEnvironment = function(BrowserExecutableFolder, UserDataFolder: PWideChar;
    const Options: ICoreWebView2EnvironmentOptions;
    const Handler: ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler): HResult; stdcall;

var
  GLoader: HMODULE;
  { Hidden top-level window the browser waits in while the control has no window. WebView2
    refuses HWND_MESSAGE as a parent (ERROR_INVALID_WINDOW_HANDLE). }
  GParking: HWND;

function ParkingWindow: HWND;
begin
  if (GParking = 0) or not IsWindow(GParking) then
    GParking := CreateWindowEx(WS_EX_TOOLWINDOW, 'STATIC', 'RADAgentWebViewParking', WS_POPUP,
      0, 0, 0, 0, 0, 0, HInstance, nil);
  Result := GParking;
end;

function ChatAssetDir: string;
begin
  Result := ExtractFilePath(GetModuleName(HInstance)) + 'RADAgent\chat';
end;

function UserDataDir: string;
begin
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('LOCALAPPDATA')) + 'RADAgent\WebView2';
end;

constructor TWebView2Host.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLifetimeGate := TWebView2LifetimeGate.Create;
  FPending := TStringList.Create;
  FBackColor := clBlack;
  TabStop := True;
end;

destructor TWebView2Host.Destroy;
begin
  FLifetimeGate.Invalidate;
  DropController;
  FEnvironment := nil;
  FPending.Free;
  inherited Destroy;
end;

function TWebView2Host.Alive: Boolean;
begin
  Result := FLifetimeGate.IsAlive and not (csDestroying in ComponentState);
end;

procedure TWebView2Host.Fail(const Problem: string);
var
  Handler: TNotifyEvent;
begin
  FProblem := Problem;
  Handler := FOnFailed;
  if Assigned(Handler) then
    Handler(Self);
end;

procedure TWebView2Host.DropController;
begin
  FWebView := nil;
  if FController <> nil then
    FController.Close;
  FController := nil;
  FPageReady := False;
end;

procedure TWebView2Host.CreateWnd;
begin
  inherited CreateWnd;
  if not Alive then
    Exit;
  if FController <> nil then
  begin
    if Succeeded(FController.Set_ParentWindow(wireHWND(Handle))) then
    begin
      UpdateBounds;
      FController.Set_IsVisible(1);
      Exit;
    end;
    { The browser window is gone: start a new one in the same environment. }
    DropController;
    CreateController;
  end
  else if not FStarted then
    StartBrowser;
end;

procedure TWebView2Host.DestroyWnd;
begin
  if csDestroying in ComponentState then
  begin
    FLifetimeGate.Invalidate;
    DropController;
  end
  else if FController <> nil then
  begin
    FController.Set_IsVisible(0);
    if Failed(FController.Set_ParentWindow(wireHWND(ParkingWindow))) then
      DropController;
  end;
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
    Fail(TrF('webview2host.assetMissing', [ChatAssetDir]));
    Exit;
  end;
  if GLoader = 0 then
  begin
    LoaderPath := ExtractFilePath(GetModuleName(HInstance)) + 'RADAgent\WebView2Loader.dll';
    GLoader := SafeLoadLibrary(LoaderPath);
    if GLoader = 0 then
    begin
      Fail(TrF('webview2host.loaderMissing', [LoaderPath]));
      Exit;
    end;
  end;
  @CreateEnvironment := GetProcAddress(GLoader, 'CreateCoreWebView2EnvironmentWithOptions');
  if not Assigned(CreateEnvironment) then
  begin
    Fail(Tr('webview2host.createEnvMissing'));
    Exit;
  end;
  ForceDirectories(UserDataDir);
  Hr := CreateEnvironment(nil, PWideChar(UserDataDir), nil,
    TEnvironmentCompleted.Create(FLifetimeGate, EnvironmentReady));
  if Failed(Hr) then
    Fail(TrF('webview2host.runtimeStartFailed', [Hr]));
end;

procedure TWebView2Host.EnvironmentReady(ErrorCode: HResult; const Env: ICoreWebView2Environment);
begin
  if not Alive then
    Exit;
  if Failed(ErrorCode) or (Env = nil) then
  begin
    Fail(TrF('webview2host.envCreateFailed', [ErrorCode]));
    Exit;
  end;
  FEnvironment := Env;
  CreateController;
end;

procedure TWebView2Host.CreateController;
var
  Hr: HResult;
begin
  if (FEnvironment = nil) or not HandleAllocated then
    Exit;
  Hr := FEnvironment.CreateCoreWebView2Controller(Handle, TControllerCompleted.Create(FLifetimeGate, ControllerReady));
  if Failed(Hr) then
    Fail(TrF('webview2host.controllerCreateFailed', [Hr]));
end;

procedure TWebView2Host.ControllerReady(ErrorCode: HResult; const Controller: ICoreWebView2Controller);
var
  Settings: ICoreWebView2Settings;
  Settings3: ICoreWebView2Settings3;
  View3: ICoreWebView2_3;
  Token: EventRegistrationToken;
begin
  if not Alive or Failed(ErrorCode) or (Controller = nil) or (FController <> nil) then
  begin
    if Controller <> nil then
      Controller.Close;
    if Alive and (FController = nil) then
      Fail(TrF('webview2host.controllerCreateFailed', [ErrorCode]));
    Exit;
  end;
  FController := Controller;
  if HandleAllocated then
    FController.Set_ParentWindow(wireHWND(Handle))
  else
    FController.Set_ParentWindow(wireHWND(ParkingWindow));
  if Failed(FController.Get_CoreWebView2(FWebView)) or (FWebView = nil) or
    not Supports(FWebView, ICoreWebView2_3, View3) then
  begin
    DropController;
    Fail(Tr('webview2host.runtimeOutdated'));
    Exit;
  end;
  ApplyBackColor;
  if Succeeded(FWebView.Get_Settings(Settings)) and (Settings <> nil) then
  begin
    Settings.Set_AreDevToolsEnabled(0);
    Settings.Set_IsStatusBarEnabled(0);
    Settings.Set_AreHostObjectsAllowed(0);
    if Supports(Settings, ICoreWebView2Settings3, Settings3) then
      Settings3.Set_AreBrowserAcceleratorKeysEnabled(0);
  end;
  View3.SetVirtualHostNameToFolderMapping(HostName, PWideChar(ChatAssetDir),
    COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY_CORS);
  FWebView.add_WebMessageReceived(TWebMessageHandler.Create(FLifetimeGate, WebMessage), Token);
  FWebView.add_NavigationStarting(TNavigationGuard.Create('https://' + HostName + '/'), Token);
  FWebView.add_NewWindowRequested(TNewWindowBlocker.Create, Token);
  UpdateBounds;
  FController.Set_IsVisible(Ord(HandleAllocated));
  Inc(FLoads);
  FWebView.Navigate(PageUrl);
end;

procedure TWebView2Host.WebMessage(const Args: ICoreWebView2WebMessageReceivedEventArgs);
var
  Raw: PWideChar;
  Json: string;
  Pending: TStringList;
  Index: Integer;
  ReadyHandler: TNotifyEvent;
  MessageHandler: TWebJsonEvent;
begin
  if not Alive or Failed(Args.Get_webMessageAsJson(Raw)) then
    Exit;
  Json := TakeString(Raw);
  if not FPageReady and Json.Contains('"t":"ready"') then
  begin
    FPageReady := True;
    Pending := FPending;
    FPending := TStringList.Create;
    try
      { A reloaded page gets the whole chat again from the owner; the queue only held part of it. }
      if FLoads = 1 then
        for Index := 0 to Pending.Count - 1 do
          if Alive and (FWebView <> nil) then
            FWebView.PostWebMessageAsJson(PWideChar(Pending[Index]));
    finally
      Pending.Free;
    end;
    ReadyHandler := FOnPageReady;
    if Alive and Assigned(ReadyHandler) then
      ReadyHandler(Self);
    Exit;
  end;
  MessageHandler := FOnMessage;
  if Assigned(MessageHandler) then
    MessageHandler(Json);
end;

procedure TWebView2Host.PostJson(const Json: string);
begin
  if not FLifetimeGate.IsAlive then
    Exit;
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
  Value: COREWEBVIEW2_COLOR;
begin
  if not Supports(FController, ICoreWebView2Controller2, Controller2) then
    Exit;
  Value.A := 255;
  Value.R := GetRValue(ColorToRGB(FBackColor));
  Value.G := GetGValue(ColorToRGB(FBackColor));
  Value.B := GetBValue(ColorToRGB(FBackColor));
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
  if GParking <> 0 then
    DestroyWindow(GParking);
  { The runtime keeps browser processes; the loader stays until package unload. }
  if GLoader <> 0 then
    FreeLibrary(GLoader);

end.
