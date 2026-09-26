unit RADAgent.DebugExceptionWatch;

{ While rad.debug_run or rad.debug_step waits for the debuggee, the IDE's "Debugger Exception
  Notification" dialog would hold the tool, and with it the turn, until someone clicks it. The
  watch answers it with its default button (Break: the process stays stopped where the exception
  was raised, so the call stack can be read) and keeps its message for the tool result. There is
  no ToolsAPI for this dialog; it is found by its form class among Screen.Forms, and only while
  the watch exists. Main thread only. }

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
    { The dialog's text ("Project X.exe raised exception class ... with message '...'."), '' when
      none appeared. }
    property Message: string read FMessage;
  end;

implementation

uses
  System.SysUtils, Vcl.Controls, Vcl.StdCtrls, Vcl.Forms;

const
  DialogClass = 'TExceptionNotificationDlg';

type
  TControlText = class(TControl);

constructor TDebugExceptionWatch.Create;
begin
  inherited Create;
  { Timer messages are dispatched by the dialog's own modal loop too. }
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 200;
  FTimer.OnTimer := Tick;
end;

destructor TDebugExceptionWatch.Destroy;
begin
  FTimer.Free;
  inherited Destroy;
end;

{ The longest text on the dialog that is not a button or a check box: the notification itself. }
procedure CollectText(Parent: TWinControl; var Longest: string; var DefaultButton: TButton);
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
      if TButton(Control).Default and TButton(Control).Enabled then
        DefaultButton := TButton(Control);
    end
    else if not (Control is TCustomCheckBox) then
    begin
      Text := Trim(TControlText(Control).Text);
      if Length(Text) > Length(Longest) then
        Longest := Text;
    end;
    if Control is TWinControl then
      CollectText(TWinControl(Control), Longest, DefaultButton);
  end;
end;

procedure TDebugExceptionWatch.Tick(Sender: TObject);
var
  Index: Integer;
  Form: TCustomForm;
  Text: string;
  DefaultButton: TButton;
begin
  for Index := Screen.CustomFormCount - 1 downto 0 do
  begin
    Form := Screen.CustomForms[Index];
    if not Form.Visible or not SameText(Form.ClassName, DialogClass) then
      Continue;
    Text := '';
    DefaultButton := nil;
    CollectText(Form, Text, DefaultButton);
    if Text <> '' then
      FMessage := Text;
    if DefaultButton <> nil then
      DefaultButton.Click
    else
      Form.ModalResult := mrOk;
    Exit;
  end;
end;

end.
