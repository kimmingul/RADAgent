unit RADAgent.WebView2Runtime;

{ What the WebView2 host needs from outside the control: WebView2Loader.dll next to the BPL,
  the chat page folder, the user data folder, and the hidden window a browser waits in while its
  control has no window. Main thread only. }

interface

uses
  Winapi.Windows, RADAgent.WebView2Api;

{ <bpl>\RADAgent\chat }
function ChatAssetDir: string;
{ Hidden top-level window. WebView2 refuses HWND_MESSAGE as a parent (ERROR_INVALID_WINDOW_HANDLE). }
function ParkingWindow: HWND;
{ Starts creating the environment; Handler gets it. False with a user-facing Problem when the
  page, the loader or the runtime is missing. }
function StartEnvironment(const Handler: ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler;
  out Problem: string): Boolean;

implementation

uses
  System.SysUtils, RADAgent.Lang;

type
  TCreateEnvironment = function(BrowserExecutableFolder, UserDataFolder: PWideChar;
    const Options: ICoreWebView2EnvironmentOptions;
    const Handler: ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler): HResult; stdcall;

var
  GLoader: HMODULE;
  GParking: HWND;

function ChatAssetDir: string;
begin
  Result := ExtractFilePath(GetModuleName(HInstance)) + 'RADAgent\chat';
end;

function UserDataDir: string;
begin
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('LOCALAPPDATA')) + 'RADAgent\WebView2';
end;

function ParkingWindow: HWND;
begin
  if (GParking = 0) or not IsWindow(GParking) then
    GParking := CreateWindowEx(WS_EX_TOOLWINDOW, 'STATIC', 'RADAgentWebViewParking', WS_POPUP,
      0, 0, 0, 0, 0, 0, HInstance, nil);
  Result := GParking;
end;

function StartEnvironment(const Handler: ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler;
  out Problem: string): Boolean;
var
  LoaderPath: string;
  CreateEnvironment: TCreateEnvironment;
  Hr: HResult;
begin
  Result := False;
  Problem := '';
  if not FileExists(ChatAssetDir + '\chat.html') then
  begin
    Problem := TrF('webview2host.assetMissing', [ChatAssetDir]);
    Exit;
  end;
  if GLoader = 0 then
  begin
    LoaderPath := ExtractFilePath(GetModuleName(HInstance)) + 'RADAgent\WebView2Loader.dll';
    GLoader := SafeLoadLibrary(LoaderPath);
    if GLoader = 0 then
    begin
      Problem := TrF('webview2host.loaderMissing', [LoaderPath]);
      Exit;
    end;
  end;
  @CreateEnvironment := GetProcAddress(GLoader, 'CreateCoreWebView2EnvironmentWithOptions');
  if not Assigned(CreateEnvironment) then
  begin
    Problem := Tr('webview2host.createEnvMissing');
    Exit;
  end;
  ForceDirectories(UserDataDir);
  Hr := CreateEnvironment(nil, PWideChar(UserDataDir), nil, Handler);
  Result := Succeeded(Hr);
  if not Result then
    Problem := TrF('webview2host.runtimeStartFailed', [Hr]);
end;

initialization

finalization
  if GParking <> 0 then
    DestroyWindow(GParking);
  { The runtime keeps browser processes; the loader stays until package unload. }
  if GLoader <> 0 then
    FreeLibrary(GLoader);

end.
