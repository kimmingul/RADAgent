unit RADAgent.ChatAttention;

{ Getting the user back when the chat needs them and the IDE is in the background: a flashing
  taskbar button, and for a finished turn a Windows notification (a notification-area balloon,
  which Windows shows as a toast; clicking it brings the IDE forward). Main thread only. }

interface

procedure RequestAttention;
{ Shows Text as a notification titled RAD Agent, only when the IDE is in the background. }
procedure NotifyInBackground(const Text: string);

implementation

uses
  System.SysUtils, System.Classes, Winapi.Windows, Winapi.Messages, Winapi.ShellAPI, Vcl.Forms,
  Vcl.ExtCtrls;

const
  IconId = 1;
  CallbackMessage = WM_USER + 1;
  NIN_BALLOONUSERCLICK = WM_USER + 5;
  { The icon stays long enough for the toast, then leaves the notification area. }
  KeepIconMs = 20000;

type
  TNotifier = class
  private
    FWindow: HWND;
    FTimer: TTimer;
    FShown: Boolean;
    procedure WndProc(var Msg: TMessage);
    procedure Expire(Sender: TObject);
    procedure RemoveIcon;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Show(const Text: string);
  end;

var
  GNotifier: TNotifier;

function IdeInBackground: Boolean;
var
  Owner: DWORD;
begin
  GetWindowThreadProcessId(GetForegroundWindow, Owner);
  Result := (Owner <> GetCurrentProcessId) and (Application.MainFormHandle <> 0);
end;

procedure RequestAttention;
var
  Info: FLASHWINFO;
begin
  if not IdeInBackground then
    Exit;
  Info := Default(FLASHWINFO);
  Info.cbSize := SizeOf(Info);
  Info.hwnd := Application.MainFormHandle;
  Info.dwFlags := FLASHW_ALL or FLASHW_TIMERNOFG;
  FlashWindowEx(Info);
end;

constructor TNotifier.Create;
begin
  inherited Create;
  FWindow := AllocateHWnd(WndProc);
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := KeepIconMs;
  FTimer.OnTimer := Expire;
end;

destructor TNotifier.Destroy;
begin
  RemoveIcon;
  FTimer.Free;
  DeallocateHWnd(FWindow);
  inherited Destroy;
end;

procedure TNotifier.RemoveIcon;
var
  Data: TNotifyIconData;
begin
  FTimer.Enabled := False;
  if not FShown then
    Exit;
  Data := Default(TNotifyIconData);
  Data.cbSize := SizeOf(Data);
  Data.Wnd := FWindow;
  Data.uID := IconId;
  Shell_NotifyIcon(NIM_DELETE, @Data);
  FShown := False;
end;

procedure TNotifier.Expire(Sender: TObject);
begin
  RemoveIcon;
end;

procedure TNotifier.WndProc(var Msg: TMessage);
begin
  if (Msg.Msg = CallbackMessage) and (LoWord(Msg.LParam) = NIN_BALLOONUSERCLICK) then
  begin
    if IsIconic(Application.MainFormHandle) then
      ShowWindow(Application.MainFormHandle, SW_RESTORE);
    SetForegroundWindow(Application.MainFormHandle);
    RemoveIcon;
  end
  else
    Msg.Result := DefWindowProc(FWindow, Msg.Msg, Msg.WParam, Msg.LParam);
end;

procedure TNotifier.Show(const Text: string);
var
  Data: TNotifyIconData;
begin
  Data := Default(TNotifyIconData);
  Data.cbSize := SizeOf(Data);
  Data.Wnd := FWindow;
  Data.uID := IconId;
  Data.uFlags := NIF_ICON or NIF_TIP or NIF_MESSAGE or NIF_INFO;
  Data.uCallbackMessage := CallbackMessage;
  Data.hIcon := Application.Icon.Handle;
  StrPLCopy(Data.szTip, 'RAD Agent', Length(Data.szTip) - 1);
  StrPLCopy(Data.szInfoTitle, 'RAD Agent', Length(Data.szInfoTitle) - 1);
  StrPLCopy(Data.szInfo, Text, Length(Data.szInfo) - 1);
  Data.dwInfoFlags := NIIF_INFO;
  if FShown then
    Shell_NotifyIcon(NIM_MODIFY, @Data)
  else
    FShown := Shell_NotifyIcon(NIM_ADD, @Data);
  FTimer.Enabled := False;
  FTimer.Enabled := FShown;
end;

procedure NotifyInBackground(const Text: string);
begin
  if not IdeInBackground then
    Exit;
  if GNotifier = nil then
    GNotifier := TNotifier.Create;
  GNotifier.Show(Text);
end;

initialization

finalization
  FreeAndNil(GNotifier);

end.
