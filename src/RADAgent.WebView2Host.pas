unit RADAgent.WebView2Host;

{ WebView2 control hosted directly through RADAgent.WebView2Api and WebView2Loader.dll next to
  the BPL, so the package needs no vcledge and no release-specific Winapi.WebView2. Serves <bpl>\RADAgent\chat through a virtual host
  and exchanges JSON messages with the page. Main thread only. }

interface

uses
  System.Classes, System.SysUtils, Winapi.Windows, Winapi.Messages, Vcl.Controls, Vcl.Graphics,
  RADAgent.WebView2Api, RADAgent.WebView2Handlers;

type
  TWebJsonEvent = procedure(const Json: string) of object;

  TWebView2Host = class(TWinControl)
  private
    FLifetimeGate: IWebView2LifetimeGate;
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

function ChatAssetDir: string;
begin
  Result := ExtractFilePath(GetModuleName(HInstance)) + 'RADAgent\chat';
end;

function UserDataDir: string;
begin
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('LOCALAPPDATA')) +
    'RADAgent\WebView2';
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
  if FLifetimeGate <> nil then
    FLifetimeGate.Invalidate;
  if FController <> nil then
  begin
    FController.Close;
    FWebView := nil;
    FController := nil;
  end;
  FPending.Free;
  inherited Destroy;
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

procedure TWebView2Host.CreateWnd;
begin
  inherited CreateWnd;
  if (csDestroying in ComponentState) or ((FLifetimeGate <> nil) and not FLifetimeGate.IsAlive) then
    Exit;
  if FController <> nil then
  begin
    FController.Set_ParentWindow(wireHWND(Handle));
    UpdateBounds;
    FController.Set_IsVisible(1);
  end
  else if not FStarted then
    StartBrowser;
end;

procedure TWebView2Host.DestroyWnd;
begin
  { Docking re-creates the handle; park the browser instead of losing it. }
  if csDestroying in ComponentState then
  begin
    if FLifetimeGate <> nil then
      FLifetimeGate.Invalidate;
    if FController <> nil then
    begin
      FController.Close;
      FWebView := nil;
      FController := nil;
    end;
  end
  else if FController <> nil then
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
var
  Hr: HResult;
begin
  if (csDestroying in ComponentState) or ((FLifetimeGate <> nil) and not FLifetimeGate.IsAlive) then
    Exit;
  if Failed(ErrorCode) or (Env = nil) then
  begin
    Fail(TrF('webview2host.envCreateFailed', [ErrorCode]));
    Exit;
  end;
  if (FLifetimeGate <> nil) and not FLifetimeGate.IsAlive then
    Exit;
  if not HandleAllocated then
  begin
    if (Parent = nil) and (ParentWindow = 0) then
      Exit;
    HandleNeeded;
  end;
  Hr := Env.CreateCoreWebView2Controller(Handle,
    TControllerCompleted.Create(FLifetimeGate, ControllerReady));
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
  if (csDestroying in ComponentState) or ((FLifetimeGate <> nil) and not FLifetimeGate.IsAlive) then
  begin
    if Controller <> nil then
      Controller.Close;
    Exit;
  end;
  if Failed(ErrorCode) or (Controller = nil) then
  begin
    if Controller <> nil then
      Controller.Close;
    Fail(TrF('webview2host.controllerCreateFailed', [ErrorCode]));
    Exit;
  end;
  if (FLifetimeGate <> nil) and not FLifetimeGate.IsAlive then
  begin
    Controller.Close;
    Exit;
  end;
  FController := Controller;
  if HandleAllocated then
  begin
    FController.Set_ParentWindow(wireHWND(Handle));
    UpdateBounds;
    FController.Set_IsVisible(1);
  end
  else
    FController.Set_ParentWindow(wireHWND(HWND_MESSAGE));
  if Failed(FController.Get_CoreWebView2(FWebView)) or (FWebView = nil) then
  begin
    FController.Close;
    FController := nil;
    Fail(TrF('webview2host.controllerCreateFailed', [E_FAIL]));
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
  if not Supports(FWebView, ICoreWebView2_3, View3) then
  begin
    FWebView := nil;
    FController.Close;
    FController := nil;
    Fail(Tr('webview2host.runtimeOutdated'));
    Exit;
  end;
  View3.SetVirtualHostNameToFolderMapping(HostName, PWideChar(ChatAssetDir),
    COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY_CORS);
  FWebView.add_WebMessageReceived(TWebMessageHandler.Create(FLifetimeGate, WebMessage), Token);
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
  ReadyHandler: TNotifyEvent;
  MessageHandler: TWebJsonEvent;
  Gate: IWebView2LifetimeGate;
  PendingCopy: TStringList;
begin
  Gate := FLifetimeGate;
  if (Gate <> nil) and not Gate.IsAlive then
    Exit;
  if Failed(Args.Get_webMessageAsJson(Raw)) then
    Exit;
  Json := TakeString(Raw);
  if not FPageReady and Json.Contains('"t":"ready"') then
  begin
    FPageReady := True;
    PendingCopy := FPending;
    FPending := TStringList.Create;
    try
      for Index := 0 to PendingCopy.Count - 1 do
      begin
        if (Gate <> nil) and not Gate.IsAlive then
          Break;
        if FWebView <> nil then
          FWebView.PostWebMessageAsJson(PWideChar(PendingCopy[Index]));
      end;
    finally
      PendingCopy.Free;
    end;
    if (Gate <> nil) and not Gate.IsAlive then
      Exit;
    ReadyHandler := FOnPageReady;
    if Assigned(ReadyHandler) then
      ReadyHandler(Self);
    Exit;
  end;
  if (Gate <> nil) and not Gate.IsAlive then
    Exit;
  MessageHandler := FOnMessage;
  if Assigned(MessageHandler) then
    MessageHandler(Json);
end;

procedure TWebView2Host.PostJson(const Json: string);
begin
  if (FLifetimeGate <> nil) and not FLifetimeGate.IsAlive then
    Exit;
  if FPageReady and (FWebView <> nil) then
    FWebView.PostWebMessageAsJson(PWideChar(Json))
  else if FPending <> nil then
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
  { The runtime keeps browser processes; the loader stays until package unload. }
  if GLoader <> 0 then
    FreeLibrary(GLoader);

end.
