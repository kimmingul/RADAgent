unit RADAgent.WebView2Handlers;

{ COM callback objects for WebView2. Each forwards to a method of the host control
  if the lifetime gate is still alive. }

interface

uses
  Winapi.Windows, RADAgent.WebView2Api;

type
  IWebView2LifetimeGate = interface
    ['{69A4C63E-5DE0-449D-9F77-9EBFB672322E}']
    function IsAlive: Boolean;
    procedure Invalidate;
  end;

  TWebView2LifetimeGate = class(TInterfacedObject, IWebView2LifetimeGate)
  private
    FAlive: Boolean;
  public
    constructor Create;
    function IsAlive: Boolean;
    procedure Invalidate;
  end;

  TEnvironmentReadyProc = procedure(ErrorCode: HResult; const Env: ICoreWebView2Environment) of object;
  TControllerReadyProc = procedure(ErrorCode: HResult; const Controller: ICoreWebView2Controller) of object;
  TWebMessageProc = procedure(const Args: ICoreWebView2WebMessageReceivedEventArgs) of object;

  TEnvironmentCompleted = class(TInterfacedObject, ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler)
  private
    FGate: IWebView2LifetimeGate;
    FProc: TEnvironmentReadyProc;
  public
    constructor Create(const Gate: IWebView2LifetimeGate; const Proc: TEnvironmentReadyProc);
    function Invoke(ErrorCode: HResult; const Value: ICoreWebView2Environment): HResult; stdcall;
  end;

  TControllerCompleted = class(TInterfacedObject, ICoreWebView2CreateCoreWebView2ControllerCompletedHandler)
  private
    FGate: IWebView2LifetimeGate;
    FProc: TControllerReadyProc;
  public
    constructor Create(const Gate: IWebView2LifetimeGate; const Proc: TControllerReadyProc);
    function Invoke(ErrorCode: HResult; const Value: ICoreWebView2Controller): HResult; stdcall;
  end;

  TWebMessageHandler = class(TInterfacedObject, ICoreWebView2WebMessageReceivedEventHandler)
  private
    FGate: IWebView2LifetimeGate;
    FProc: TWebMessageProc;
  public
    constructor Create(const Gate: IWebView2LifetimeGate; const Proc: TWebMessageProc);
    function Invoke(const Sender: ICoreWebView2;
      const Args: ICoreWebView2WebMessageReceivedEventArgs): HResult; stdcall;
  end;

  { Cancels every navigation that leaves the chat page origin. }
  TNavigationGuard = class(TInterfacedObject, ICoreWebView2NavigationStartingEventHandler)
  private
    FPrefix: string;
  public
    constructor Create(const Prefix: string);
    function Invoke(const Sender: ICoreWebView2;
      const Args: ICoreWebView2NavigationStartingEventArgs): HResult; stdcall;
  end;

  TNewWindowBlocker = class(TInterfacedObject, ICoreWebView2NewWindowRequestedEventHandler)
  public
    function Invoke(const Sender: ICoreWebView2;
      const Args: ICoreWebView2NewWindowRequestedEventArgs): HResult; stdcall;
  end;

function TakeString(Value: PWideChar): string;

implementation

uses
  System.SysUtils, Winapi.ActiveX;

function TakeString(Value: PWideChar): string;
begin
  Result := Value;
  CoTaskMemFree(Value);
end;

{ TWebView2LifetimeGate }

constructor TWebView2LifetimeGate.Create;
begin
  inherited Create;
  FAlive := True;
end;

function TWebView2LifetimeGate.IsAlive: Boolean;
begin
  Result := FAlive;
end;

procedure TWebView2LifetimeGate.Invalidate;
begin
  FAlive := False;
end;

{ TEnvironmentCompleted }

constructor TEnvironmentCompleted.Create(const Gate: IWebView2LifetimeGate; const Proc: TEnvironmentReadyProc);
begin
  inherited Create;
  FGate := Gate;
  FProc := Proc;
end;

function TEnvironmentCompleted.Invoke(ErrorCode: HResult; const Value: ICoreWebView2Environment): HResult;
begin
  if (FGate <> nil) and FGate.IsAlive then
    FProc(ErrorCode, Value);
  Result := S_OK;
end;

{ TControllerCompleted }

constructor TControllerCompleted.Create(const Gate: IWebView2LifetimeGate; const Proc: TControllerReadyProc);
begin
  inherited Create;
  FGate := Gate;
  FProc := Proc;
end;

function TControllerCompleted.Invoke(ErrorCode: HResult; const Value: ICoreWebView2Controller): HResult;
begin
  if (FGate <> nil) and FGate.IsAlive then
    FProc(ErrorCode, Value)
  else if Value <> nil then
    Value.Close;
  Result := S_OK;
end;

{ TWebMessageHandler }

constructor TWebMessageHandler.Create(const Gate: IWebView2LifetimeGate; const Proc: TWebMessageProc);
begin
  inherited Create;
  FGate := Gate;
  FProc := Proc;
end;

function TWebMessageHandler.Invoke(const Sender: ICoreWebView2;
  const Args: ICoreWebView2WebMessageReceivedEventArgs): HResult;
begin
  if (FGate <> nil) and FGate.IsAlive then
    FProc(Args);
  Result := S_OK;
end;

{ TNavigationGuard }

constructor TNavigationGuard.Create(const Prefix: string);
begin
  inherited Create;
  FPrefix := Prefix;
end;

function TNavigationGuard.Invoke(const Sender: ICoreWebView2;
  const Args: ICoreWebView2NavigationStartingEventArgs): HResult;
var
  Raw: PWideChar;
  Uri: string;
begin
  Result := S_OK;
  if Failed(Args.Get_uri(Raw)) then
    Exit;
  Uri := TakeString(Raw);
  if not Uri.StartsWith(FPrefix, True) then
    Args.Set_Cancel(1);
end;

{ TNewWindowBlocker }

function TNewWindowBlocker.Invoke(const Sender: ICoreWebView2;
  const Args: ICoreWebView2NewWindowRequestedEventArgs): HResult;
begin
  Args.Set_Handled(1);
  Result := S_OK;
end;

end.
