unit RADAgent.ChatAttention;

{ Flashes the IDE taskbar button when the chat needs the user and the IDE is in the background. }

interface

procedure RequestAttention;

implementation

uses
  Winapi.Windows, Vcl.Forms;

procedure RequestAttention;
var
  Owner: DWORD;
  Info: FLASHWINFO;
begin
  GetWindowThreadProcessId(GetForegroundWindow, Owner);
  if (Owner = GetCurrentProcessId) or (Application.MainFormHandle = 0) then
    Exit;
  Info := Default(FLASHWINFO);
  Info.cbSize := SizeOf(Info);
  Info.hwnd := Application.MainFormHandle;
  Info.dwFlags := FLASHW_ALL or FLASHW_TIMERNOFG;
  FlashWindowEx(Info);
end;

end.
