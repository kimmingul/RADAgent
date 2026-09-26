unit RADAgent.DebugExceptionWatch;

{ While rad.debug_run or rad.debug_step waits for the debuggee, the IDE's "Debugger Exception
  Notification" dialog would hold the tool, and with it the turn, until someone clicks it. Once
  armed (after the user approved the run or step, right before it starts) the watch answers the
  dialog with its Break button (the process stays stopped where the exception was raised, so the
  call stack can be read) and keeps its message for the tool result. Without a button that is
  clearly Break the dialog is left for the user. There is no ToolsAPI for this dialog; it is found
  by its form class among Screen.Forms, and only while the watch exists. Main thread only. }

interface

uses
  System.Classes, Vcl.ExtCtrls;

type
  TDebugExceptionWatch = class
  private
    FTimer: TTimer;
    FMessage: string;
    procedure Tick(Sender: TObject);
  public
    constructor Create;
    destructor Destroy; override;
    { Starts watching; call right before the approved run or step starts. }
    procedure Arm;
    { The dialog's text ("Project X.exe raised exception class ... with message '...'."), '' when
      none was answered. }
    property Message: string read FMessage;
  end;

implementation

uses
  System.SysUtils, System.StrUtils, Vcl.Controls, Vcl.StdCtrls, Vcl.Forms, Vcl.Menus;

const
  DialogClass = 'TExceptionNotificationDlg';

type
  TControlText = class(TControl);

constructor TDebugExceptionWatch.Create;
begin
  inherited Create;
  { Timer messages are dispatched by the dialog's own modal loop too. }
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := 200;
  FTimer.OnTimer := Tick;
end;

destructor TDebugExceptionWatch.Destroy;
begin
  FTimer.Free;
  inherited Destroy;
end;

procedure TDebugExceptionWatch.Arm;
begin
  FTimer.Enabled := True;
end;

{ The longest text on the dialog that is not a button or a check box is the notification itself.
  The Break button is known by its caption or its component name, not by being the default. }
procedure CollectText(Parent: TWinControl; var Longest: string; var BreakButton: TButton);
var
  Index: Integer;
  Control: TControl;
  Text: string;
begin
  for Index := 0 to Parent.ControlCount - 1 do
  begin
    Control := Parent.Controls[Index];
    if Control is TButton then
    begin
      if TButton(Control).Enabled and (SameText(StripHotkey(TButton(Control).Caption), 'Break') or
        ContainsText(Control.Name, 'Break')) then
        BreakButton := TButton(Control);
    end
    else if not (Control is TCustomCheckBox) then
    begin
      Text := Trim(TControlText(Control).Text);
      if Length(Text) > Length(Longest) then
        Longest := Text;
    end;
    if Control is TWinControl then
      CollectText(TWinControl(Control), Longest, BreakButton);
  end;
end;

procedure TDebugExceptionWatch.Tick(Sender: TObject);
var
  Index: Integer;
  Form: TCustomForm;
  Text: string;
  BreakButton: TButton;
begin
  for Index := Screen.CustomFormCount - 1 downto 0 do
  begin
    Form := Screen.CustomForms[Index];
    if not Form.Visible or not SameText(Form.ClassName, DialogClass) then
      Continue;
    Text := '';
    BreakButton := nil;
    CollectText(Form, Text, BreakButton);
    if BreakButton = nil then
      Exit;
    FMessage := Text;
    BreakButton.Click;
    Exit;
  end;
end;

end.
