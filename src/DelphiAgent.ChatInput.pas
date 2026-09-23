unit DelphiAgent.ChatInput;

{ Multi-line prompt box. Enter sends, Shift+Enter breaks the line, Up/Down on the first/last line
  walk the sent history, and a leading "/" opens the slash command list. }

interface

uses
  System.Classes, System.SysUtils, Winapi.Windows, Winapi.Messages, Vcl.Controls, Vcl.StdCtrls,
  DelphiAgent.RpcResponses;

type
  TSubmitEvent = procedure(const Text: string) of object;

  TChatInput = class(TMemo)
  private
    FHistory: TStringList;
    FHistoryIndex: Integer;
    FDraft: string;
    FCommands: TArray<TSlashCommand>;
    FPopup: TListBox;
    FOnSubmit: TSubmitEvent;
    FOnHeightWanted: TNotifyEvent;
    procedure UpdatePopup;
    procedure AcceptPopup;
    procedure HidePopup;
    function PopupVisible: Boolean;
    function CaretLine: Integer;
    procedure Recall(Delta: Integer);
    procedure PopupClick(Sender: TObject);
    procedure CMExit(var Message: TCMExit); message CM_EXIT;
    procedure CNKeyDown(var Message: TWMKeyDown); message CN_KEYDOWN;
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyPress(var Key: Char); override;
    procedure Change; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetCommands(const Commands: TArray<TSlashCommand>);
    { Lines the box wants to show (1..8) for the host layout. }
    function WantedLines: Integer;
    property OnSubmit: TSubmitEvent read FOnSubmit write FOnSubmit;
    property OnHeightWanted: TNotifyEvent read FOnHeightWanted write FOnHeightWanted;
  end;

implementation

uses
  System.Math;

const
  MaxHistory = 100;
  MaxPopupRows = 8;

constructor TChatInput.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHistory := TStringList.Create;
  FHistoryIndex := -1;
  { Enter must reach KeyDown instead of the form's default button; KeyPress eats the #13. }
  WantReturns := True;
  ScrollBars := ssVertical;
  WordWrap := True;
  TextHint := '메시지 입력 (Enter 보내기, Shift+Enter 줄바꿈, / 명령)';
end;

destructor TChatInput.Destroy;
begin
  FHistory.Free;
  inherited Destroy;
end;

procedure TChatInput.SetCommands(const Commands: TArray<TSlashCommand>);
begin
  FCommands := Commands;
end;

function TChatInput.WantedLines: Integer;
begin
  Result := EnsureRange(Lines.Count, 1, 8);
end;

function TChatInput.CaretLine: Integer;
begin
  Result := Perform(EM_LINEFROMCHAR, SelStart, 0);
end;

function TChatInput.PopupVisible: Boolean;
begin
  Result := (FPopup <> nil) and FPopup.Visible;
end;

procedure TChatInput.HidePopup;
begin
  if FPopup <> nil then
    FPopup.Visible := False;
end;

procedure TChatInput.UpdatePopup;
var
  Prefix, Line: string;
  Index: Integer;
  Pt: TPoint;
begin
  Prefix := Text;
  if (Prefix = '') or (Prefix[1] <> '/') or (Prefix.IndexOfAny([' ', #13, #10]) >= 0) or
    (Length(FCommands) = 0) then
  begin
    HidePopup;
    Exit;
  end;
  if FPopup = nil then
  begin
    FPopup := TListBox.Create(Owner);
    FPopup.Visible := False;
    { On the frame, not the input panel, so the list can sit above the input. }
    FPopup.Parent := Owner as TWinControl;
    FPopup.OnDblClick := PopupClick;
    FPopup.TabStop := False;
  end;
  FPopup.Items.BeginUpdate;
  try
    FPopup.Items.Clear;
    for Index := 0 to High(FCommands) do
      if ('/' + FCommands[Index].Name).StartsWith(Prefix, True) then
      begin
        Line := '/' + FCommands[Index].Name;
        if FCommands[Index].Description <> '' then
          Line := Line + '  —  ' + FCommands[Index].Description;
        FPopup.Items.Add(Line);
      end;
  finally
    FPopup.Items.EndUpdate;
  end;
  if FPopup.Items.Count = 0 then
  begin
    HidePopup;
    Exit;
  end;
  FPopup.ItemIndex := 0;
  FPopup.Font := Font;
  FPopup.Color := Color;
  FPopup.Height := Min(FPopup.Items.Count, MaxPopupRows) * FPopup.ItemHeight + 4;
  Pt := FPopup.Parent.ScreenToClient(ClientToScreen(Point(0, 0)));
  FPopup.SetBounds(Pt.X, Max(0, Pt.Y - FPopup.Height), Width, FPopup.Height);
  FPopup.Visible := True;
  FPopup.BringToFront;
end;

procedure TChatInput.AcceptPopup;
var
  Choice: string;
begin
  if not PopupVisible or (FPopup.ItemIndex < 0) then
    Exit;
  Choice := FPopup.Items[FPopup.ItemIndex];
  if Choice.Contains('  —  ') then
    Choice := Copy(Choice, 1, Pos('  —  ', Choice) - 1);
  HidePopup;
  Text := Choice + ' ';
  SelStart := Length(Text);
end;

procedure TChatInput.PopupClick(Sender: TObject);
begin
  AcceptPopup;
  SetFocus;
end;

procedure TChatInput.Recall(Delta: Integer);
var
  Next: Integer;
begin
  if FHistory.Count = 0 then
    Exit;
  if FHistoryIndex < 0 then
  begin
    if Delta > 0 then
      Exit;
    FDraft := Text;
    Next := FHistory.Count - 1;
  end
  else
    Next := FHistoryIndex + Delta;
  if Next >= FHistory.Count then
  begin
    FHistoryIndex := -1;
    Text := FDraft;
  end
  else
  begin
    FHistoryIndex := Max(0, Next);
    Text := FHistory[FHistoryIndex];
  end;
  SelStart := Length(Text);
end;

procedure TChatInput.KeyDown(var Key: Word; Shift: TShiftState);
var
  Sent: string;
begin
  if PopupVisible then
    case Key of
      VK_UP, VK_DOWN:
        begin
          FPopup.ItemIndex := EnsureRange(FPopup.ItemIndex + IfThen(Key = VK_UP, -1, 1), 0,
            FPopup.Items.Count - 1);
          Key := 0;
          Exit;
        end;
      VK_TAB, VK_RETURN:
        begin
          AcceptPopup;
          Key := 0;
          Exit;
        end;
      VK_ESCAPE:
        begin
          HidePopup;
          Key := 0;
          Exit;
        end;
    end;
  if (Key = VK_RETURN) and (ssShift in Shift) then
  begin
    SelText := sLineBreak;
    Key := 0;
    Exit;
  end;
  if (Key = VK_RETURN) and (Shift = []) then
  begin
    Key := 0;
    Sent := Trim(Text);
    if (Sent = '') or not Assigned(FOnSubmit) then
      Exit;
    if (FHistory.Count = 0) or (FHistory[FHistory.Count - 1] <> Sent) then
      FHistory.Add(Sent);
    while FHistory.Count > MaxHistory do
      FHistory.Delete(0);
    FHistoryIndex := -1;
    FDraft := '';
    FOnSubmit(Sent);
    Exit;
  end;
  if (Key = VK_UP) and (Shift = []) and (CaretLine = 0) then
  begin
    Recall(-1);
    Key := 0;
    Exit;
  end;
  if (Key = VK_DOWN) and (Shift = []) and (FHistoryIndex >= 0) and
    (CaretLine >= Lines.Count - 1) then
  begin
    Recall(1);
    Key := 0;
    Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

procedure TChatInput.KeyPress(var Key: Char);
begin
  { Enter is handled in KeyDown; stop the beep and the stray line break. }
  if Key = #13 then
    Key := #0;
  inherited KeyPress(Key);
end;

procedure TChatInput.Change;
begin
  inherited Change;
  UpdatePopup;
  if Assigned(FOnHeightWanted) then
    FOnHeightWanted(Self);
end;

procedure TChatInput.CMExit(var Message: TCMExit);
begin
  inherited;
  if (FPopup <> nil) and not FPopup.Focused then
    HidePopup;
end;

{ The dockable form maps Esc to "hide"; that shortcut check runs before the control sees the key,
  so Esc in the input is caught here and only closes the command list. }
procedure TChatInput.CNKeyDown(var Message: TWMKeyDown);
begin
  if Message.CharCode = VK_ESCAPE then
  begin
    HidePopup;
    Message.Result := 1;
  end
  else
    inherited;
end;

end.
