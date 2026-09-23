unit DelphiAgent.DockForm;
{ High-contrast chat frame. The IDE embeds it in a dockable form. }
interface
uses
  Vcl.Forms, Vcl.ExtCtrls, Vcl.StdCtrls, Vcl.Controls, System.Classes,
  DelphiAgent.HostTools, DelphiAgent.RpcClient;
type
  TDelphiAgentChatFrame = class(TFrame, IAgentApproval)
    memLog: TMemo;
    pnlBottom: TPanel;
    edtInput: TEdit;
    pnlButtons: TPanel;
    btnSend: TButton;
    btnCancel: TButton;
    lblStatus: TLabel;
  private
    FCompile: TButton;
    FFile: TButton;
    FPickModel: Boolean;
    FTimer: TTimer;
    FClient: TAgentRpcClient;
    FNotedNoProject: Boolean;
    FStartError: string;
    procedure BuildUi;
    procedure StyleHighContrast;
    procedure RefreshStatus;
    procedure AppendLog(const Text: string);
    procedure EnsureStarted;
    procedure TimerTick(Sender: TObject);
    procedure SendClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure CompileClick(Sender: TObject);
    procedure HandleHostTool(const CallId, ToolName, ArgumentsJson: string);
    procedure HandleUi(const Line: string);
    procedure HandleModels(const Text: string);
    procedure FileClick(Sender: TObject);
    function ApproveBufferChange(const FileName, Preview: string): Boolean;
    procedure ShowConflict(const FileName: string);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure HostFrameCreated;
  end;
implementation
{$R *.dfm}
uses
  Vcl.Graphics, System.SysUtils, Winapi.Windows,
  DelphiAgent.Options, DelphiAgent.RpcProtocol, DelphiAgent.ChatCommand,
  DelphiAgent.AskDialog, DelphiAgent.IdeContext,
  DelphiAgent.DirtyBuffers, DelphiAgent.Compile;
const
  SSend = #$BCF4#$B0B4#$AE30;
  SStop = #$C911#$C9C0;
  SCompile = #$CEF4#$D30C#$C77C;
  SWait = #$B300#$AE30;
  SConnected = #$C5F0#$ACB0#$B428;
  SNoProject = #$D65C#$C131' '#$D504#$B85C#$C81D#$D2B8#$AC00' '#$C5C6#$C2B5#$B2C8#$B2E4'.';
procedure TDelphiAgentChatFrame.StyleHighContrast;
begin
  Color := clBlack;
  ParentBackground := False;
  ParentColor := False;
  Font.Name := 'Malgun Gothic';
  Font.Color := clWhite;
  Font.Size := 10;
end;
procedure TDelphiAgentChatFrame.BuildUi;
begin
  StyleHighContrast;
  memLog.Color := clBlack;
  memLog.Font.Color := clWhite;
  memLog.Font.Name := 'Malgun Gothic';
  memLog.Font.Size := 10;
  edtInput.Color := clBlack;
  edtInput.Font.Color := clWhite;
  edtInput.Font.Name := 'Malgun Gothic';
  lblStatus.Color := clBlack;
  lblStatus.Font.Color := clWhite;
  lblStatus.Font.Name := 'Malgun Gothic';
  lblStatus.Transparent := False;
  lblStatus.ParentColor := False;
  lblStatus.Layout := tlCenter;
  lblStatus.AutoSize := False;
  lblStatus.Height := 22;
  lblStatus.Align := alBottom;
  btnSend.Caption := SSend;
  btnCancel.Caption := SStop;
  pnlBottom.Color := clBlack;
  pnlBottom.ParentBackground := False;
  pnlButtons.Color := clBlack;
  pnlButtons.ParentBackground := False;
  btnSend.OnClick := SendClick;
  btnCancel.OnClick := CancelClick;
  if FCompile = nil then
  begin
    FCompile := TButton.Create(pnlButtons);
    FCompile.Parent := pnlButtons;
    FCompile.Caption := SCompile;
    FCompile.OnClick := CompileClick;
  end;
  pnlButtons.Width := 230;
  btnSend.SetBounds(4, 4, 220, 28);
  btnCancel.SetBounds(4, 36, 70, 28);
  FCompile.SetBounds(78, 36, 70, 28);
  if FFile = nil then
  begin
    FFile := TButton.Create(pnlButtons);
    FFile.Parent := pnlButtons;
    FFile.Caption := #$D30C#$C77C;
    FFile.OnClick := FileClick;
  end;
  FFile.SetBounds(152, 36, 70, 28);
  RefreshStatus;
end;
constructor TDelphiAgentChatFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
end;
procedure TDelphiAgentChatFrame.HostFrameCreated;
begin
  BuildUi;
  if not Assigned(FTimer) then
  begin
    FTimer := TTimer.Create(Self);
    FTimer.Interval := 1000;
    FTimer.OnTimer := TimerTick;
    FTimer.Enabled := True;
  end;
  InstallProjectWatch(RefreshStatus);
  EnsureStarted;
end;
destructor TDelphiAgentChatFrame.Destroy;
begin
  if Assigned(FTimer) then
  begin
    FTimer.OnTimer := nil;
    FTimer.Enabled := False;
    FreeAndNil(FTimer);
  end;
  RemoveProjectWatch;
  if FClient <> nil then
  begin
    FClient.OnLog := nil;
    FClient.OnStatus := nil;
    FClient.OnHostTool := nil;
    FClient.SendAbort;
    FClient.Free;
    FClient := nil;
  end;
  inherited Destroy;
end;
procedure TDelphiAgentChatFrame.AppendLog(const Text: string);
begin
  memLog.SelStart := Length(memLog.Text);
  memLog.SelLength := 0;
  memLog.SelText := Text;
end;
procedure TDelphiAgentChatFrame.RefreshStatus;
var
  Kind, ProjectName, Folder, Reason: string;
  ProjectFile: string;
  Pid: Cardinal;
begin
  ProjectFile := ActiveProjectFile;
  if ProjectFile = '' then
  begin
    ProjectName := #$C5C6#$C74C;
    Folder := '';
  end
  else
  begin
    ProjectName := ChangeFileExt(ExtractFileName(ProjectFile), '');
    Folder := ExcludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(ProjectFile)));
  end;
  Pid := 0;
  Kind := SWait;
  Reason := '';
  if FClient <> nil then
  begin
    Pid := FClient.Pid;
    if (FClient.LinkError <> '') or (FStartError <> '') then
    begin
      Kind := #$C624#$B958;
      if FClient.LinkError <> '' then
        Reason := ' ' + FClient.LinkError
      else
        Reason := ' ' + FStartError;
    end
    else if FClient.Ready then
      Kind := SConnected
    else
      Kind := SWait;
    if FClient.StateCwd <> '' then
      Folder := ExcludeTrailingPathDelimiter(FClient.StateCwd);
  end;
  lblStatus.Caption := Format('[%s]  pid=%d  프로젝트=%s  폴더=%s%s',
    [Kind, Pid, ProjectName, Folder, Reason]);
  if (FClient <> nil) and (FClient.ModelLabel <> '') then
    lblStatus.Caption := lblStatus.Caption + '  모델=' + FClient.ModelLabel;
  btnSend.Enabled := (FClient <> nil) and FClient.Ready and FClient.HostToolsSent;
end;
procedure TDelphiAgentChatFrame.EnsureStarted;
var
  Dir: string;
begin
  Dir := ActiveProjectDir;
  if Dir = '' then
  begin
    if not FNotedNoProject then
    begin
      AppendLog(SNoProject + sLineBreak);
      FNotedNoProject := True;
    end;
  end
  else
    FNotedNoProject := False;
  if (FClient <> nil) and (FClient.Pid <> 0) and (Dir <> '') and
    not SameText(ExcludeTrailingPathDelimiter(FClient.Cwd), ExcludeTrailingPathDelimiter(Dir)) then
    FClient.Stop;
  if FClient = nil then
    FClient := TAgentRpcClient.Create;
  FClient.OnLog := AppendLog;
  FClient.OnStatus := RefreshStatus;
  FClient.OnHostTool := HandleHostTool;
  FClient.OnUi := HandleUi;
  FClient.OnModels := HandleModels;
  if FClient.Pid = 0 then
  begin
    if Dir <> '' then
      Dir := ExcludeTrailingPathDelimiter(Dir)
    else
      Dir := GetCurrentDir;
    if not FClient.Start(OmpExecutable, Dir) then
    begin
      FStartError := '프로세스 시작 실패 ' + IntToStr(GetLastError);
      AppendLog('omp start failed ' + IntToStr(GetLastError) + sLineBreak);
    end
    else
      FStartError := '';
  end;
  RefreshStatus;
end;
procedure TDelphiAgentChatFrame.TimerTick(Sender: TObject);
begin
  EnsureStarted;
  if Assigned(FTimer) and (FClient <> nil) and FClient.HostToolsSent then
    FTimer.Enabled := False;
end;
procedure TDelphiAgentChatFrame.SendClick(Sender: TObject);
var
  Dirty: TArray<TEditorText>;
  Files, Texts, Paths: TArray<string>;
  Index: Integer;
  Message, Original, Arg1, Arg2: string;
  Command: TChatCommand;
begin
  RefreshStatus;
  EnsureStarted;
  if (FClient = nil) or not FClient.Ready or not FClient.HostToolsSent then
    Exit;
  Original := edtInput.Text;
  Command := ClassifyChat(Original, Arg1, Arg2);
  if Command = ccPrompt then
  begin
    Dirty := DirtyEditorTexts;
    SetLength(Files, Length(Dirty));
    SetLength(Texts, Length(Dirty));
    for Index := 0 to High(Dirty) do
    begin
      Files[Index] := Dirty[Index].FileName;
      Texts[Index] := Dirty[Index].Text;
    end;
    Paths := WriteSnapshots(AgentTempRoot, Files, Texts);
    RememberSnapshots(Files, Texts);
    Message := MessageWithSnapshots(Original, Paths);
    if not FClient.SendPrompt(Message) then
      Exit;
    AppendLog(sLineBreak + '> ' + Original + sLineBreak);
  end
  else
  begin
    if not DispatchSlash(Original, FClient.SendRaw, FPickModel) then
      FClient.SendPrompt(Original);
    if not FPickModel then
      AppendLog(sLineBreak + '> ' + Original + sLineBreak);
  end;
  edtInput.Text := '';
end;
procedure TDelphiAgentChatFrame.HandleModels(const Text: string);
var
  Provider, ModelId: string;
begin
  if not FPickModel then
    Exit;
  FPickModel := False;
  if ChooseModel(Text, Provider, ModelId) then
  begin
    FClient.SendRaw('set_model', BuildSetModelFrame('req', Provider, ModelId));
    AppendLog(#$BAA8#$B378' ' + Provider + '/' + ModelId + sLineBreak);
  end;
end;
procedure TDelphiAgentChatFrame.HandleUi(const Line: string);
var
  Reply, Notice: string;
begin
  if (FClient = nil) or not ExtensionReply(Line, Reply, Notice) then
    Exit;
  if Notice <> '' then
    AppendLog(Notice + sLineBreak);
  if Reply <> '' then
    FClient.SendRaw('extension_ui_response', Reply);
end;
procedure TDelphiAgentChatFrame.FileClick(Sender: TObject);
var
  Path: string;
begin
  if not AskOpenFile(Path) then
    Exit;
  if edtInput.Text = '' then
    edtInput.Text := Path
  else
    edtInput.Text := edtInput.Text + ' ' + Path;
end;
procedure TDelphiAgentChatFrame.CancelClick(Sender: TObject);
begin
  if (FClient <> nil) and FClient.Ready then
    FClient.SendAbort;
end;
procedure TDelphiAgentChatFrame.CompileClick(Sender: TObject);
var
  Json: string;
begin
  Json := BuildActiveProjectJson;
  if Json.Contains('"ok":true') then
    AppendLog(SCompile + ' ok' + sLineBreak)
  else if Json.Contains('프로젝트 없음') then
    AppendLog(SCompile + ' ' + #$D504#$B85C#$C81D#$D2B8' '#$C5C6#$C74C + sLineBreak)
  else
    AppendLog(SCompile + ' ' + #$C2E4#$D328 + sLineBreak);
end;
procedure TDelphiAgentChatFrame.HandleHostTool(const CallId, ToolName, ArgumentsJson: string);
var
  Text: string;
  IsError: Boolean;
begin
  if (FClient <> nil) and FClient.WasCancelled(CallId) then
    Exit;
  ExecuteHostTool(ToolName, ArgumentsJson, Self, Text, IsError);
  if (FClient <> nil) and not FClient.WasCancelled(CallId) then
    FClient.SendHostResult(CallId, Text, IsError);
end;
function TDelphiAgentChatFrame.ApproveBufferChange(const FileName, Preview: string): Boolean;
var
  Dialog: TForm;
  Memo: TMemo;
  YesButton, NoButton: TButton;
begin
  Dialog := TForm.CreateNew(nil);
  try
    Dialog.Caption := 'DelphiAgent';
    Dialog.BorderStyle := bsDialog;
    Dialog.Position := poScreenCenter;
    Dialog.ClientWidth := 520;
    Dialog.ClientHeight := 300;
    Dialog.Color := clBlack;
    Memo := TMemo.Create(Dialog);
    Memo.Parent := Dialog;
    Memo.Align := alTop;
    Memo.Height := 240;
    Memo.ReadOnly := True;
    Memo.ScrollBars := ssVertical;
    Memo.Color := clBlack;
    Memo.Font.Color := clWhite;
    Memo.Font.Name := 'Malgun Gothic';
    Memo.Text := FileName + sLineBreak + Preview;
    YesButton := TButton.Create(Dialog);
    YesButton.Parent := Dialog;
    YesButton.Caption := '승인';
    YesButton.ModalResult := mrYes;
    YesButton.Left := 300;
    YesButton.Top := 256;
    YesButton.Width := 88;
    NoButton := TButton.Create(Dialog);
    NoButton.Parent := Dialog;
    NoButton.Caption := '취소';
    NoButton.ModalResult := mrCancel;
    NoButton.Left := 400;
    NoButton.Top := 256;
    NoButton.Width := 88;
    Result := Dialog.ShowModal = mrYes;
  finally
    Dialog.Free;
  end;
end;
procedure TDelphiAgentChatFrame.ShowConflict(const FileName: string);
begin
  AppendLog('충돌: 스냅샷 이후 버퍼가 바뀌어 반영하지 않았습니다. ' + FileName + sLineBreak);
end;
end.
