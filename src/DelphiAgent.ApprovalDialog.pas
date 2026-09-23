unit DelphiAgent.ApprovalDialog;

{ Modal approval dialog displaying line diffs with IDE theme support. }

interface

{ Shows a modal diff comparison dialog. Returns True if approved (mrYes). }
function AskApprovalDiff(const Target, Before, After: string): Boolean;

implementation

uses
  Winapi.Windows, Winapi.Messages, Winapi.RichEdit,
  System.SysUtils, System.Classes, System.UITypes,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ComCtrls, Vcl.ExtCtrls,
  Vcl.Graphics, Vcl.Themes,
  ToolsAPI,
  DelphiAgent.LineDiff;

const
  SApprove = '승인';
  SCancel = '취소';
  STitle = 'DelphiAgent 승인';

procedure SetSelectionBackColor(RichEdit: TRichEdit; Color: TColor);
var
  Fmt: TCharFormat2;
begin
  FillChar(Fmt, SizeOf(Fmt), 0);
  Fmt.cbSize := SizeOf(Fmt);
  Fmt.dwMask := CFM_BACKCOLOR;
  Fmt.crBackColor := ColorToRGB(Color);
  SendMessage(RichEdit.Handle, EM_SETCHARFORMAT, SCF_SELECTION, LPARAM(@Fmt));
end;

function IsColorDark(Color: TColor): Boolean;
var
  RgbVal: Longint;
  R, G, B: Integer;
begin
  RgbVal := ColorToRGB(Color);
  R := GetRValue(RgbVal);
  G := GetGValue(RgbVal);
  B := GetBValue(RgbVal);
  Result := ((R * 299 + G * 587 + B * 114) div 1000) < 128;
end;

function GetEditEffectiveBg(RichEdit: TRichEdit): TColor;
var
  C: TColor;
begin
  C := RichEdit.Color;
  if (C = clWindow) or (C = clDefault) then
  begin
    if TStyleManager.IsCustomStyleActive then
      Exit(TStyleManager.ActiveStyle.GetSystemColor(clWindow))
    else
      Exit(GetSysColor(COLOR_WINDOW));
  end;
  Result := ColorToRGB(C);
end;

procedure ApplyIdeTheme(Form: TForm);
var
  Theming: IOTAIDEThemingServices250;
begin
  if BorlandIDEServices = nil then
    Exit;
  if Supports(BorlandIDEServices, IOTAIDEThemingServices250, Theming) then
  begin
    if Theming.IDEThemingEnabled then
      Theming.ApplyTheme(Form);
  end;
end;

procedure AppendRichLine(RichEdit: TRichEdit; const S: string; TextColor, BackColor: TColor);
var
  StartPos: Integer;
begin
  StartPos := RichEdit.GetTextLen;
  RichEdit.SelStart := StartPos;
  RichEdit.SelLength := 0;
  RichEdit.SelText := S + sLineBreak;
  if Length(S) > 0 then
  begin
    RichEdit.SelStart := StartPos;
    RichEdit.SelLength := Length(S);
    RichEdit.SelAttributes.Color := TextColor;
    SetSelectionBackColor(RichEdit, BackColor);
  end;
  RichEdit.SelStart := RichEdit.GetTextLen;
  RichEdit.SelLength := 0;
end;

function AskApprovalDiff(const Target, Before, After: string): Boolean;
var
  Form: TForm;
  TopPanel, BottomPanel: TPanel;
  LblTarget, LblSummary: TLabel;
  RichEdit: TRichEdit;
  BtnApprove, BtnCancel: TButton;
  EditBg, RemovedText, RemovedBg, AddedText, AddedBg, SameText, PlainText: TColor;
  IsDark: Boolean;
  Diff, Collapsed: TArray<TDiffLine>;
  AfterLines: TArray<string>;
  RemovedCount, AddedCount, I: Integer;
  Line: string;
begin
  Form := TForm.CreateNew(nil);
  try
    Form.Caption := STitle;
    Form.Position := poScreenCenter;
    Form.BorderStyle := bsSizeable;
    Form.ClientWidth := Form.ScaleValue(720);
    Form.ClientHeight := Form.ScaleValue(480);

    { Top panel with target and summary labels }
    TopPanel := TPanel.Create(Form);
    TopPanel.Parent := Form;
    TopPanel.Align := alTop;
    TopPanel.BevelOuter := bvNone;
    TopPanel.Caption := '';
    TopPanel.Height := Form.ScaleValue(52);
    TopPanel.Padding.SetBounds(Form.ScaleValue(12), Form.ScaleValue(6),
      Form.ScaleValue(12), Form.ScaleValue(4));

    LblTarget := TLabel.Create(Form);
    LblTarget.Parent := TopPanel;
    LblTarget.Align := alTop;
    LblTarget.EllipsisPosition := epPathEllipsis;
    LblTarget.ShowHint := True;
    LblTarget.Hint := Target;
    LblTarget.Caption := Target;
    LblTarget.Font.Style := [fsBold];

    LblSummary := TLabel.Create(Form);
    LblSummary.Parent := TopPanel;
    LblSummary.Align := alBottom;
    LblSummary.Font.Color := clGrayText;

    { Bottom panel with action buttons }
    BottomPanel := TPanel.Create(Form);
    BottomPanel.Parent := Form;
    BottomPanel.Align := alBottom;
    BottomPanel.BevelOuter := bvNone;
    BottomPanel.Caption := '';
    BottomPanel.Height := Form.ScaleValue(46);

    BtnCancel := TButton.Create(Form);
    BtnCancel.Parent := BottomPanel;
    BtnCancel.Caption := SCancel;
    BtnCancel.ModalResult := mrCancel;
    BtnCancel.Cancel := True;
    BtnCancel.Default := False;
    BtnCancel.Width := Form.ScaleValue(84);
    BtnCancel.Height := Form.ScaleValue(30);
    BtnCancel.Anchors := [akRight, akBottom];
    BtnCancel.Left := BottomPanel.ClientWidth - Form.ScaleValue(96);
    BtnCancel.Top := Form.ScaleValue(8);

    BtnApprove := TButton.Create(Form);
    BtnApprove.Parent := BottomPanel;
    BtnApprove.Caption := SApprove;
    BtnApprove.ModalResult := mrYes;
    BtnApprove.Cancel := False;
    BtnApprove.Default := False;
    BtnApprove.Width := Form.ScaleValue(84);
    BtnApprove.Height := Form.ScaleValue(30);
    BtnApprove.Anchors := [akRight, akBottom];
    BtnApprove.Left := BtnCancel.Left - Form.ScaleValue(92);
    BtnApprove.Top := Form.ScaleValue(8);

    { Middle rich edit for diff display }
    RichEdit := TRichEdit.Create(Form);
    RichEdit.Parent := Form;
    RichEdit.Align := alClient;
    RichEdit.ReadOnly := True;
    RichEdit.WordWrap := False;
    RichEdit.ScrollBars := ssBoth;
    RichEdit.Font.Name := 'Consolas';
    RichEdit.Font.Size := 10;

    { Apply IDE theme before calculating colors }
    ApplyIdeTheme(Form);
    Form.HandleNeeded;
    RichEdit.HandleNeeded;

    EditBg := GetEditEffectiveBg(RichEdit);
    IsDark := IsColorDark(EditBg);

    if IsDark then
    begin
      RemovedText := RGB(255, 128, 128);
      RemovedBg := RGB(64, 20, 20);
      AddedText := RGB(128, 255, 128);
      AddedBg := RGB(20, 60, 20);
      SameText := RGB(160, 160, 160);
      PlainText := RGB(220, 220, 220);
    end
    else
    begin
      RemovedText := RGB(180, 0, 0);
      RemovedBg := RGB(255, 230, 230);
      AddedText := RGB(0, 130, 0);
      AddedBg := RGB(230, 255, 230);
      SameText := RGB(110, 110, 110);
      PlainText := RGB(30, 30, 30);
    end;

    RichEdit.Lines.BeginUpdate;
    try
      if Before = '' then
      begin
        AfterLines := SplitLines(After);
        LblSummary.Caption := Format('추가 %d줄', [Length(AfterLines)]);
        for Line in AfterLines do
          AppendRichLine(RichEdit, Line, PlainText, EditBg);
      end
      else
      begin
        Diff := DiffLines(Before, After);
        RemovedCount := 0;
        AddedCount := 0;
        for I := 0 to High(Diff) do
        begin
          if Diff[I].Kind = dkRemoved then
            Inc(RemovedCount)
          else if Diff[I].Kind = dkAdded then
            Inc(AddedCount);
        end;
        LblSummary.Caption := Format('삭제 %d줄, 추가 %d줄', [RemovedCount, AddedCount]);

        Collapsed := CollapseContext(Diff, 3);
        for I := 0 to High(Collapsed) do
        begin
          case Collapsed[I].Kind of
            dkRemoved:
              AppendRichLine(RichEdit, '- ' + Collapsed[I].Text, RemovedText, RemovedBg);
            dkAdded:
              AppendRichLine(RichEdit, '+ ' + Collapsed[I].Text, AddedText, AddedBg);
            dkSame:
              AppendRichLine(RichEdit, '  ' + Collapsed[I].Text, SameText, EditBg);
          end;
        end;
      end;
    finally
      RichEdit.Lines.EndUpdate;
    end;

    RichEdit.SelStart := 0;
    RichEdit.SelLength := 0;
    SendMessage(RichEdit.Handle, EM_SCROLLCARET, 0, 0);

    Result := Form.ShowModal = mrYes;
  finally
    Form.Free;
  end;
end;

end.
