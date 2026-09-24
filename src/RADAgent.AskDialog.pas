unit RADAgent.AskDialog;

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
{ InputCancelled: the user closed an input prompt without a value. }
function ExtensionReply(const Line: string; out Reply, Notice: string; out InputCancelled: Boolean): Boolean;

type
  TRawSend = procedure(const FrameType, Frame: string) of object;

function DispatchSlash(const Original: string; const Send: TRawSend;
  out PickModels: Boolean): Boolean;

implementation

uses
  Winapi.Windows, Winapi.ShellAPI, Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, Vcl.Graphics, Vcl.Dialogs,
  RADAgent.ChatCommand, RADAgent.RpcProtocol, RADAgent.ChatPlan, RADAgent.ChatSession,
  RADAgent.ChatApprovalCard, RADAgent.Lang;

var
  { The open AskText form, so an omp "cancel" (login finished in the browser) can close it. }
  GActiveAsk: TForm;

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
    MakeButton(Form, Tr('askdialog.ok'), 220, 320, mrOk);
    MakeButton(Form, Tr('askdialog.cancel'), 316, 320, mrCancel);
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
    LabelText.AutoSize := False;
    LabelText.SetBounds(12, 16, 396, 64);
    LabelText.WordWrap := True;
    LabelText.Caption := Message;
    MakeButton(Form, Tr('askdialog.ok'), 220, 96, mrYes);
    MakeButton(Form, Tr('askdialog.cancel'), 316, 96, mrNo);
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
    LabelText.AutoSize := False;
    LabelText.SetBounds(12, 12, 396, 36);
    LabelText.WordWrap := True;
    LabelText.Caption := Prompt;
    Edit := TEdit.Create(Form);
    Edit.Parent := Form;
    Edit.SetBounds(12, 52, 396, 24);
    Edit.Color := clBlack;
    Edit.Font.Color := clWhite;
    MakeButton(Form, Tr('askdialog.ok'), 220, 96, mrOk);
    MakeButton(Form, Tr('askdialog.cancel'), 316, 96, mrCancel);
    GActiveAsk := Form;
    try
      Result := (Form.ShowModal = mrOk) and (Trim(Edit.Text) <> '');
    finally
      GActiveAsk := nil;
    end;
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
    if not AskChoice(Tr('askdialog.chooseModelTitle'), Lines, Choice) then
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

function ExtensionReply(const Line: string; out Reply, Notice: string; out InputCancelled: Boolean): Boolean;
var
  Ui: TExtensionUi;
  Choice: string;
  Items: TStringList;
  Index: Integer;
begin
  Reply := '';
  Notice := '';
  InputCancelled := False;
  Result := False;
  if not ParseExtensionUi(Line, Ui) then
    Exit;
  Result := True;
  if (Ui.Method = 'notify') or (Ui.Method = 'setStatus') then
  begin
    Notice := Ui.Message;
    Reply := BuildUiReply(Ui.Id, '', True, False);
  end
  else if Ui.Method = 'open_url' then
  begin
    { Login: omp waits for the browser flow, not for a reply. }
    if Ui.Url.StartsWith('http://', True) or Ui.Url.StartsWith('https://', True) then
      ShellExecute(0, 'open', PChar(Ui.Url), nil, nil, SW_SHOWNORMAL);
    Notice := Trim(TrF('askdialog.finishLoginInBrowser', [Trim(Ui.Message + ' ' + Ui.Url)]));
  end
  else if Ui.Method = 'confirm' then
    Reply := BuildUiReply(Ui.Id, '', AskYes(Ui.Title, Ui.Message), False)
  else if ApprovalTargetsRad(Ui) and (ApproveOption(Ui) <> '') then
    { omp gates its write tool, which also carries rad.* calls. RADAgent asks for those
      itself (per the same approval mode), so a second omp prompt would only repeat it. }
    Reply := BuildUiReply(Ui.Id, ApproveOption(Ui), False, False)
  else if PlanActive and IsToolApproval(Ui) and (DenyOption(Ui) <> '') then
  begin
    { Plan mode: omp may read and search, not write, edit or run commands. }
    Reply := BuildUiReply(Ui.Id, DenyOption(Ui), False, False);
    Notice := TrF('askdialog.planModeDeniedTool', [Copy(Ui.Title, 1, Pos(#10, Ui.Title + #10) - 1)]);
  end
  else if IsToolApproval(Ui) and InChatApprovals and (ApproveOption(Ui) <> '') and (DenyOption(Ui) <> '') then
  begin
    { omp's own tools (edit, write, bash…) ask in the chat like the rad.* changes do. }
    if AskInChat(Copy(Ui.Title, 1, Pos(#10, Ui.Title + #10) - 1), '',
      Trim(Copy(Ui.Title, Pos(#10, Ui.Title + #10) + 1, MaxInt) + #10 + Ui.Message)) then
      Reply := BuildUiReply(Ui.Id, ApproveOption(Ui), False, False)
    else
      Reply := BuildUiReply(Ui.Id, DenyOption(Ui), False, False);
  end
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
  else if Ui.Method = 'cancel' then
  begin
    if GActiveAsk <> nil then
      GActiveAsk.ModalResult := mrCancel;
  end
  else if (Ui.Method = 'input') or (Ui.Method = 'editor') then
  begin
    if Ui.Message = '' then
      Ui.Message := Ui.Title;
    if AskText(Ui.Title, Ui.Message, Choice) then
      Reply := BuildUiReply(Ui.Id, Choice, False, False)
    else
    begin
      Reply := BuildUiReply(Ui.Id, '', False, True);
      InputCancelled := True;
    end;
  end
  else
    Reply := BuildUiReply(Ui.Id, '', True, False);
end;

{ The levels omp offers for the current model; the common set before the catalog arrives. }
function ThinkingChoices: string;
begin
  Result := string.Join(',', ChatSession.Catalog.ThinkingLevels);
  if Result = '' then
    Result := 'off,minimal,low,medium,high,xhigh';
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
      if AskYes(Tr('askdialog.newSessionTitle'), Tr('askdialog.newSessionConfirm')) then
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
        if (Arg1 = '') and not AskCsv(Tr('askdialog.fastModeTitle'), 'on,off', Arg1) then
          Exit;
        Send('set_fast_mode', BuildSetFastFrame('req', SameText(Arg1, 'on')));
      end;
    ccThinking:
      begin
        if (Arg1 = '') and not AskCsv(Tr('askdialog.thinkingTitle'), ThinkingChoices, Arg1) then
          Exit;
        Send('set_thinking_level', BuildSetThinkingFrame('req', Arg1));
      end;
  end;
end;

end.
