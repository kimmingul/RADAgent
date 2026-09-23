unit DelphiAgent.AskDialog;

{ Modal prompts for slash commands and omp extension UI. }

interface

uses
  System.Classes, System.SysUtils;

function AskChoice(const Title: string; Items: TStrings; out Choice: string): Boolean;
function AskCsv(const Title, Csv: string; out Choice: string): Boolean;
function AskYes(const Title, Message: string): Boolean;
function AskText(const Title, Prompt: string; out Value: string): Boolean;
function AskOpenFile(out Path: string): Boolean;
function ChooseModel(const ListText: string; out Provider, ModelId: string): Boolean;
function ExtensionReply(const Line: string; out Reply, Notice: string): Boolean;

type
  TRawSend = procedure(const FrameType, Frame: string) of object;

function DispatchSlash(const Original: string; const Send: TRawSend;
  out PickModels: Boolean): Boolean;

implementation

uses
  Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, Vcl.Graphics, Vcl.Dialogs,
  DelphiAgent.ChatCommand, DelphiAgent.RpcProtocol;

const
  SOk = #$D655#$C778;
  SCancel = #$CDE8#$C18C;

procedure PaintDark(Form: TForm);
begin
  Form.BorderStyle := bsDialog;
  Form.Position := poScreenCenter;
  Form.Color := clBlack;
  Form.Font.Name := 'Malgun Gothic';
  Form.Font.Color := clWhite;
end;

function MakeButton(Form: TForm; const Caption: string; Left, Top, Modal: Integer): TButton;
begin
  Result := TButton.Create(Form);
  Result.Parent := Form;
  Result.Caption := Caption;
  Result.Left := Left;
  Result.Top := Top;
  Result.Width := 88;
  Result.Height := 28;
  Result.ModalResult := Modal;
end;

function AskChoice(const Title: string; Items: TStrings; out Choice: string): Boolean;
var
  Form: TForm;
  List: TListBox;
begin
  Choice := '';
  Form := TForm.CreateNew(nil);
  try
    PaintDark(Form);
    Form.Caption := Title;
    Form.ClientWidth := 420;
    Form.ClientHeight := 360;
    List := TListBox.Create(Form);
    List.Parent := Form;
    List.SetBounds(8, 8, 404, 300);
    List.Color := clBlack;
    List.Font.Color := clWhite;
    List.Font.Name := 'Malgun Gothic';
    if Items <> nil then
      List.Items.Assign(Items);
    if List.Items.Count > 0 then
      List.ItemIndex := 0;
    MakeButton(Form, SOk, 220, 320, mrOk);
    MakeButton(Form, SCancel, 316, 320, mrCancel);
    Result := (Form.ShowModal = mrOk) and (List.ItemIndex >= 0);
    if Result then
      Choice := List.Items[List.ItemIndex];
  finally
    Form.Free;
  end;
end;

function AskCsv(const Title, Csv: string; out Choice: string): Boolean;
var
  Items: TStringList;
begin
  Items := TStringList.Create;
  try
    Items.StrictDelimiter := True;
    Items.Delimiter := ',';
    Items.DelimitedText := Csv;
    Result := AskChoice(Title, Items, Choice);
  finally
    Items.Free;
  end;
end;

function AskYes(const Title, Message: string): Boolean;
var
  Form: TForm;
  LabelText: TLabel;
begin
  Form := TForm.CreateNew(nil);
  try
    PaintDark(Form);
    Form.Caption := Title;
    Form.ClientWidth := 420;
    Form.ClientHeight := 140;
    LabelText := TLabel.Create(Form);
    LabelText.Parent := Form;
    LabelText.SetBounds(12, 16, 396, 64);
    LabelText.WordWrap := True;
    LabelText.Caption := Message;
    MakeButton(Form, SOk, 220, 96, mrYes);
    MakeButton(Form, SCancel, 316, 96, mrNo);
    Result := Form.ShowModal = mrYes;
  finally
    Form.Free;
  end;
end;

function AskText(const Title, Prompt: string; out Value: string): Boolean;
var
  Form: TForm;
  LabelText: TLabel;
  Edit: TEdit;
begin
  Value := '';
  Form := TForm.CreateNew(nil);
  try
    PaintDark(Form);
    Form.Caption := Title;
    Form.ClientWidth := 420;
    Form.ClientHeight := 140;
    LabelText := TLabel.Create(Form);
    LabelText.Parent := Form;
    LabelText.SetBounds(12, 12, 396, 36);
    LabelText.WordWrap := True;
    LabelText.Caption := Prompt;
    Edit := TEdit.Create(Form);
    Edit.Parent := Form;
    Edit.SetBounds(12, 52, 396, 24);
    Edit.Color := clBlack;
    Edit.Font.Color := clWhite;
    MakeButton(Form, SOk, 220, 96, mrOk);
    MakeButton(Form, SCancel, 316, 96, mrCancel);
    Result := (Form.ShowModal = mrOk) and (Trim(Edit.Text) <> '');
    if Result then
      Value := Trim(Edit.Text);
  finally
    Form.Free;
  end;
end;

function AskOpenFile(out Path: string): Boolean;
var
  Dialog: TOpenDialog;
begin
  Path := '';
  Dialog := TOpenDialog.Create(nil);
  try
    Dialog.Options := Dialog.Options + [ofFileMustExist];
    Result := Dialog.Execute;
    if Result then
      Path := Dialog.FileName;
  finally
    Dialog.Free;
  end;
end;

function ChooseModel(const ListText: string; out Provider, ModelId: string): Boolean;
var
  Lines: TStringList;
  Choice: string;
  SplitAt: Integer;
begin
  Provider := '';
  ModelId := '';
  Result := False;
  Lines := TStringList.Create;
  try
    Lines.Text := ListText;
    if not AskChoice(#$BAA8#$B378, Lines, Choice) then
      Exit;
    SplitAt := Pos('/', Choice);
    if SplitAt <= 1 then
      Exit;
    Provider := Copy(Choice, 1, SplitAt - 1);
    ModelId := Copy(Choice, SplitAt + 1, MaxInt);
    Result := (Provider <> '') and (ModelId <> '');
  finally
    Lines.Free;
  end;
end;

function ExtensionReply(const Line: string; out Reply, Notice: string): Boolean;
var
  Ui: TExtensionUi;
  Choice: string;
  Items: TStringList;
  Index: Integer;
begin
  Reply := '';
  Notice := '';
  Result := False;
  if not ParseExtensionUi(Line, Ui) then
    Exit;
  Result := True;
  if (Ui.Method = 'notify') or (Ui.Method = 'setStatus') then
  begin
    Notice := Ui.Message;
    Reply := BuildUiReply(Ui.Id, '', True, False);
  end
  else if Ui.Method = 'confirm' then
    Reply := BuildUiReply(Ui.Id, '', AskYes(Ui.Title, Ui.Message), False)
  else if Ui.Method = 'select' then
  begin
    Items := TStringList.Create;
    try
      for Index := 0 to High(Ui.Options) do
        Items.Add(Ui.Options[Index]);
      if AskChoice(Ui.Title, Items, Choice) then
        Reply := BuildUiReply(Ui.Id, Choice, False, False)
      else
        Reply := BuildUiReply(Ui.Id, '', False, True);
    finally
      Items.Free;
    end;
  end
  else if (Ui.Method = 'input') or (Ui.Method = 'editor') then
  begin
    if AskText(Ui.Title, Ui.Message, Choice) then
      Reply := BuildUiReply(Ui.Id, Choice, False, False)
    else
      Reply := BuildUiReply(Ui.Id, '', False, True);
  end
  else
    Reply := BuildUiReply(Ui.Id, '', True, False);
end;

function DispatchSlash(const Original: string; const Send: TRawSend;
  out PickModels: Boolean): Boolean;
var
  Arg1, Arg2: string;
  Command: TChatCommand;
begin
  PickModels := False;
  Result := False;
  if not Assigned(Send) then
    Exit;
  Command := ClassifyChat(Original, Arg1, Arg2);
  if (Command = ccPrompt) or (Command = ccSlashAsPrompt) then
    Exit;
  Result := True;
  case Command of
    ccNewSession:
      if AskYes(#$C138#$C158, #$C138#$C158#$C744' '#$C9C0#$C6B8#$AE4C#$C694'?') then
        Send('new_session', BuildIdTypeFrame('req', 'new_session'));
    ccAbort: Send('abort', BuildIdTypeFrame('req', 'abort'));
    ccListModels:
      begin
        PickModels := True;
        Send('get_available_models', BuildIdTypeFrame('req', 'get_available_models'));
      end;
    ccSetModel: Send('set_model', BuildSetModelFrame('req', Arg1, Arg2));
    ccFast:
      begin
        if (Arg1 = '') and not AskCsv(#$BE60#$B984, 'on,off', Arg1) then
          Exit;
        Send('set_fast_mode', BuildSetFastFrame('req', SameText(Arg1, 'on')));
      end;
    ccThinking:
      begin
        if (Arg1 = '') and not AskCsv(#$C0DD#$AC01, 'off,minimal,low,medium,high,xhigh', Arg1) then
          Exit;
        Send('set_thinking_level', BuildSetThinkingFrame('req', Arg1));
      end;
  end;
end;

end.
