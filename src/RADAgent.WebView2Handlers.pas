unit RADAgent.WebView2Handlers;

{ COM callback objects for WebView2. Each forwards to a method of the host control. }

interface

uses
  Winapi.Windows, RADAgent.WebView2Api;

type
  TEnvironmentReadyProc = procedure(ErrorCode: HResult; const Env: ICoreWebView2Environment) of object;
  TControllerReadyProc = procedure(ErrorCode: HResult; const Controller: ICoreWebView2Controller) of object;
  TWebMessageProc = procedure(const Args: ICoreWebView2WebMessageReceivedEventArgs) of object;

  TEnvironmentCompleted = class(TInterfacedObject, ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler)
  private
    FProc: TEnvironmentReadyProc;
  public
    constructor Create(const Proc: TEnvironmentReadyProc);
    function Invoke(ErrorCode: HResult; const Value: ICoreWebView2Environment): HResult; stdcall;
  end;

  TControllerCompleted = class(TInterfacedObject, ICoreWebView2CreateCoreWebView2ControllerCompletedHandler)
  private
    FProc: TControllerReadyProc;
  public
    constructor Create(const Proc: TControllerReadyProc);
    function Invoke(ErrorCode: HResult; const Value: ICoreWebView2Controller): HResult; stdcall;
  end;

  TWebMessageHandler = class(TInterfacedObject, ICoreWebView2WebMessageReceivedEventHandler)
  private
    FProc: TWebMessageProc;
  public
    constructor Create(const Proc: TWebMessageProc);
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

implementation

uses
  System.SysUtils, Winapi.ActiveX;

constructor TEnvironmentCompleted.Create(const Proc: TEnvironmentReadyProc);
begin
  inherited Create;
  FProc := Proc;
end;

function TEnvironmentCompleted.Invoke(ErrorCode: HResult; const Value: ICoreWebView2Environment): HResult;
begin
  FProc(ErrorCode, Value);
  Result := S_OK;
end;

constructor TControllerCompleted.Create(const Proc: TControllerReadyProc);
begin
  inherited Create;
  FProc := Proc;
end;

function TControllerCompleted.Invoke(ErrorCode: HResult; const Value: ICoreWebView2Controller): HResult;
begin
  FProc(ErrorCode, Value);
  Result := S_OK;
end;

constructor TWebMessageHandler.Create(const Proc: TWebMessageProc);
begin
  inherited Create;
  FProc := Proc;
end;

function TWebMessageHandler.Invoke(const Sender: ICoreWebView2;
  const Args: ICoreWebView2WebMessageReceivedEventArgs): HResult;
begin
  FProc(Args);
  Result := S_OK;
end;

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
  Uri := Raw;
  CoTaskMemFree(Raw);
  if not Uri.StartsWith(FPrefix, True) then
    Args.Set_Cancel(1);
end;

function TNewWindowBlocker.Invoke(const Sender: ICoreWebView2;
  const Args: ICoreWebView2NewWindowRequestedEventArgs): HResult;
begin
  Args.Set_Handled(1);
  Result := S_OK;
end;

end.
