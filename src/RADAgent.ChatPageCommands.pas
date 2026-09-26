unit RADAgent.ChatPageCommands;

{ Requests from the chat page (top bar, composer, links) carried out on the IDE side. The page
  owns no state beyond its input; every action goes through the session or ChatActions.
  Main thread only. }

interface

type
  { What the hosting frame must do after a page request. }
  TPageAction = (paNone, paThemeChanged, paRefresh);

function HandlePageRequest(const Json: string): TPageAction;
{ Submits Text as if typed in the composer, with attached files; True when it reached omp. }
function SubmitFromPage(const Text: string; WithSelection: Boolean;
  const Attachments: TArray<string> = nil; FollowUp: Boolean = False): Boolean;

implementation

uses
  System.SysUtils, System.JSON, Winapi.Windows, Winapi.ShellAPI, Vcl.Dialogs, Vcl.Clipbrd,
  RADAgent.ChatSession, RADAgent.ChatActions, RADAgent.ChatCommand,
  RADAgent.EditorContext, RADAgent.SettingsDialog, RADAgent.ChatExtensions,
  RADAgent.ChatApprovalCard, RADAgent.ChatPlan, RADAgent.ChatStatus, RADAgent.ChatBtw,
  RADAgent.ChatCheckpoints, RADAgent.ChatStop, RADAgent.ChatSlash, RADAgent.ChatQueue, RADAgent.ChatUsage, RADAgent.Lang;

function Post(const Kind, Field, Value: string): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('t', Kind);
    if Field <> '' then
      Obj.AddPair(Field, Value);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

{ The composer's answer for submission Id: accepted (clear that draft) or not (keep it). }
function Submitted(const Id: string; Accepted: Boolean): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('t', 'submitted');
    Obj.AddPair('id', Id);
    Obj.AddPair('ok', TJSONBool.Create(Accepted));
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function SubmitFromPage(const Text: string; WithSelection: Boolean;
  const Attachments: TArray<string>; FollowUp: Boolean): Boolean;
var
  Info: TEditorInfo;
  Attachment, AttachmentLabel, FilesText, ImagesJson, FilesLabel: string;
begin
  Attachment := '';
  AttachmentLabel := '';
  if WithSelection then
  begin
    Info := ActiveEditorInfo;
    Attachment := SelectionAttachment(Info);
    if Attachment <> '' then
      AttachmentLabel := TrF('chatpagecommands.selectionAttachment', [ExtractFileName(Info.FileName),
        Info.StartLine, Info.EndLine]);
  end;
  BuildAttachments(Attachments, FilesText, ImagesJson, FilesLabel);
  if FilesLabel <> '' then
    if AttachmentLabel = '' then
      AttachmentLabel := FilesLabel
    else
      AttachmentLabel := AttachmentLabel + ', ' + FilesLabel;
  Result := SubmitChat(Text, Attachment + FilesText, AttachmentLabel, ImagesJson, FollowUp);
end;

function StringsOf(Value: TJSONValue): TArray<string>;
var
  Item: TJSONValue;
begin
  Result := nil;
  if Value is TJSONArray then
    for Item in TJSONArray(Value) do
      if Item is TJSONString then
        Result := Result + [TJSONString(Item).Value];
end;

procedure ExportWithDialog;
var
  Dialog: TSaveDialog;
begin
  Dialog := TSaveDialog.Create(nil);
  try
    Dialog.Filter := 'HTML (*.html)|*.html';
    Dialog.DefaultExt := 'html';
    Dialog.FileName := 'RADAgent-' + FormatDateTime('yyyymmdd-hhnn', Now) + '.html';
    Dialog.Options := Dialog.Options + [ofOverwritePrompt];
    if Dialog.Execute then
      ExportConversation(Dialog.FileName);
  finally
    Dialog.Free;
  end;
end;

procedure SetModel(const Selector: string);
var
  Slash: Integer;
begin
  Slash := Pos('/', Selector);
  if Slash <= 1 then
    Exit;
  ChatSession.SendCommand('set_model', BuildSetModelFrame('req', Copy(Selector, 1, Slash - 1),
    Copy(Selector, Slash + 1, MaxInt)));
  { The thinking levels depend on the model. }
  ChatSession.RequestCatalog;
end;

function HandlePageRequest(const Json: string): TPageAction;
var
  Value: TJSONValue;
  Obj: TJSONObject;
  Kind, Text: string;
  Session: TChatSession;
begin
  Result := paNone;
  Session := ChatSession;
  Value := TJSONObject.ParseJSONValue(Json);
  try
    if not (Value is TJSONObject) then
      Exit;
    Obj := TJSONObject(Value);
    Kind := Obj.GetValue<string>('t', '');
    Text := Obj.GetValue<string>('text', '');
    if Kind = 'submit' then
      Session.PostToView(Submitted(Obj.GetValue<string>('id', ''),
        SubmitFromPage(Text, Obj.GetValue<Boolean>('withSelection', False),
        StringsOf(Obj.GetValue('attachments')), Obj.GetValue<Boolean>('followUp', False))))
    else if Kind = 'btw' then
    begin
      AskBtw(Text, Obj.GetValue<string>('topic', ''));
      if Obj.GetValue<Boolean>('composer', False) then
        Session.PostToView(Submitted(Obj.GetValue<string>('id', ''), True));
    end
    else if Kind = 'restore' then
      GoBackTo(Obj.GetValue<Integer>('seq', 0), Obj.GetValue<Boolean>('branch', False))
    else if Kind = 'btwStop' then
      StopBtw(Obj.GetValue<string>('id', ''))
    else if Kind = 'btwDelete' then
      DeleteBtw(Obj.GetValue<string>('id', ''))
    else if Kind = 'btwList' then
      Session.PostToView(PageBtwList)
    else if Kind = 'approval' then
      AnswerApproval(Obj.GetValue<string>('id', ''), Obj.GetValue<Boolean>('ok', False))
    else if Kind = 'proceedPlan' then
      ProceedWithPlan(Obj.GetValue<string>('path', ''))
    else if Kind = 'abort' then
    begin
      StopTurn
    end
    else if Kind = 'newSession' then
      StartNewSession
    else if Kind = 'sessions' then
      PickSession
    else if Kind = 'export' then
      ExportWithDialog
    else if Kind = 'settings' then
    begin
      ShowSettings;
      Result := paThemeChanged;
    end
    else if Kind = 'compile' then
      CompileActiveProject
    else if Kind = 'attachFiles' then
    begin
      Text := PickAttachments;
      if Text <> '' then
        Session.PostToView(Text);
    end
    else if Kind = 'addFolder' then
      AddWorkspaceFolder
    else if Kind = 'listFiles' then
      Session.PostToView(PageFiles)
    else if Kind = 'listExtensions' then
      Session.PostToView(PageExtensions)
    else if Kind = 'toggleMcpServer' then
      ToggleMcpServer(Obj.GetValue<string>('id', ''), Obj.GetValue<Boolean>('enabled', True))
    else if Kind = 'togglePlugin' then
      TogglePlugin(Obj.GetValue<string>('kind', ''), Obj.GetValue<string>('id', ''),
        Obj.GetValue<Boolean>('enabled', True))
    else if Kind = 'manageExtensions' then
    begin
      ShowSettings(3);
      Result := paThemeChanged;
    end
    else if Kind = 'setModel' then
      SetModel(Obj.GetValue<string>('value', ''))
    else if Kind = 'setThinking' then
      Session.SendCommand('set_thinking_level', BuildSetThinkingFrame('req', Obj.GetValue<string>('value', '')))
    else if Kind = 'setApproval' then
      SetApprovalMode(Obj.GetValue<string>('value', ''))
    else if Kind = 'openFile' then
    begin
      if not OpenFileAtLine(Obj.GetValue<string>('path', ''), Obj.GetValue<Integer>('line', 0)) then
        Session.Notice('warn', TrF('chatpagecommands.cannotOpenFile', [Obj.GetValue<string>('path', '')]));
    end
    else if Kind = 'openUrl' then
    begin
      Text := Obj.GetValue<string>('url', '');
      if Text.StartsWith('http://', True) or Text.StartsWith('https://', True) then
        ShellExecute(0, 'open', PChar(Text), nil, nil, SW_SHOWNORMAL);
    end
    else if Kind = 'copy' then
      Clipboard.AsText := Text
    else if Kind = 'runCommand' then
      SubmitChat(Text, '', '')
    else if Kind = 'abortRetry' then
      AbortRetry
    else if Kind = 'subagentLog' then
      ShowSubagentLog(Obj.GetValue<string>('id', ''))
    else if Kind = 'usage' then
      RequestUsage;
    { Most requests change what the top bar or composer shows. }
    if Result = paNone then
      Result := paRefresh;
  finally
    Value.Free;
  end;
end;

end.
