unit RADAgent.DockKeeper;

{ The IDE swaps desktops (Default Layout <-> Debug Layout) when a debug session starts or ends,
  and a desktop that never contained the chat hides it. If the chat was showing just before the
  switch, show it again. }

interface

uses
  System.SysUtils;

procedure InstallDockKeeper(const IsShowing: TFunc<Boolean>; const ShowChat: TProc);
procedure RemoveDockKeeper;
{ Shows the chat window if it is hidden (e.g. before an approval card). }
procedure RevealChat;

implementation

uses
  System.Classes, Winapi.Windows, Vcl.ExtCtrls, ToolsAPI;

const
  { Desktop loading finishes within this window after the process event. }
  SwitchWindowMs = 6000;

type
  TDebugWatch = class(TNotifierObject, IOTADebuggerNotifier)
  public
    procedure ProcessCreated(const Process: IOTAProcess);
    procedure ProcessDestroyed(const Process: IOTAProcess);
    procedure BreakpointAdded(const Breakpoint: IOTABreakpoint);
    procedure BreakpointDeleted(const Breakpoint: IOTABreakpoint);
  end;

  TKeeper = class
  private
    FTimer: TTimer;
    FIsShowing: TFunc<Boolean>;
    FShowChat: TProc;
    FWasShowing: Boolean;
    FSwitchTick: UInt64;
    procedure Tick(Sender: TObject);
  public
    constructor Create(const IsShowing: TFunc<Boolean>; const ShowChat: TProc);
    destructor Destroy; override;
    procedure DesktopSwitching;
  end;

var
  GKeeper: TKeeper;
  GWatchIndex: Integer = -1;

procedure TDebugWatch.ProcessCreated(const Process: IOTAProcess);
begin
  if GKeeper <> nil then
    GKeeper.DesktopSwitching;
end;

procedure TDebugWatch.ProcessDestroyed(const Process: IOTAProcess);
begin
  if GKeeper <> nil then
    GKeeper.DesktopSwitching;
end;

procedure TDebugWatch.BreakpointAdded(const Breakpoint: IOTABreakpoint);
begin
end;

procedure TDebugWatch.BreakpointDeleted(const Breakpoint: IOTABreakpoint);
begin
end;

constructor TKeeper.Create(const IsShowing: TFunc<Boolean>; const ShowChat: TProc);
begin
  inherited Create;
  FIsShowing := IsShowing;
  FShowChat := ShowChat;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 500;
  FTimer.OnTimer := Tick;
end;

destructor TKeeper.Destroy;
begin
  FTimer.Free;
  inherited Destroy;
end;

procedure TKeeper.DesktopSwitching;
begin
  { Remember the state from before the switch; the timer samples it until then. }
  FSwitchTick := GetTickCount64;
end;

procedure TKeeper.Tick(Sender: TObject);
var
  Showing: Boolean;
begin
  Showing := FIsShowing();
  if (FSwitchTick <> 0) and (GetTickCount64 - FSwitchTick < SwitchWindowMs) then
  begin
    if FWasShowing and not Showing then
      FShowChat();
    Exit;
  end;
  FSwitchTick := 0;
  FWasShowing := Showing;
end;

procedure InstallDockKeeper(const IsShowing: TFunc<Boolean>; const ShowChat: TProc);
var
  Debugger: IOTADebuggerServices;
begin
  if GKeeper <> nil then
    Exit;
  GKeeper := TKeeper.Create(IsShowing, ShowChat);
  if Supports(BorlandIDEServices, IOTADebuggerServices, Debugger) then
    GWatchIndex := Debugger.AddNotifier(TDebugWatch.Create);
end;

procedure RevealChat;
begin
  if (GKeeper <> nil) and not GKeeper.FIsShowing() then
    GKeeper.FShowChat();
end;

procedure RemoveDockKeeper;
var
  Debugger: IOTADebuggerServices;
begin
  if (GWatchIndex >= 0) and Supports(BorlandIDEServices, IOTADebuggerServices, Debugger) then
    Debugger.RemoveNotifier(GWatchIndex);
  GWatchIndex := -1;
  FreeAndNil(GKeeper);
end;

end.
