unit RADAgent.ChatApprovalCard;

{ Approval asked inside the chat: a card with the change (line diff) and approve/deny buttons. The
  host tool that needs the answer waits here, pumping messages like a modal dialog would, until
  the page answers, the turn is stopped or the chat view goes away. Main thread only. }

interface

{ True while a WebView chat page is attached and can show cards. }
procedure SetInChatApprovals(Enabled: Boolean);
function InChatApprovals: Boolean;
function AskInChat(const Target, Before, After: string): Boolean;
{ From the page: the user's choice for card Id. }
procedure AnswerApproval(const Id: string; Approved: Boolean);
{ Stop pressed or view closed: every waiting card counts as refused. }
procedure RefuseAllApprovals;

implementation

uses
  System.SysUtils, System.JSON, System.Generics.Collections, Winapi.Windows, Vcl.Forms,
  RADAgent.ChatSession, RADAgent.LineDiff, RADAgent.DockKeeper, RADAgent.Lang;

const
  MaxLines = 400;

var
  GEnabled: Boolean;
  GNext: Integer;
  GAnswers: TDictionary<string, Boolean>;
  GWaiting: TList<string>;

procedure SetInChatApprovals(Enabled: Boolean);
begin
  GEnabled := Enabled;
  if not Enabled then
    RefuseAllApprovals;
end;

function InChatApprovals: Boolean;
begin
  Result := GEnabled;
end;

procedure AnswerApproval(const Id: string; Approved: Boolean);
begin
  if GWaiting.Contains(Id) then
    GAnswers.AddOrSetValue(Id, Approved);
end;

procedure RefuseAllApprovals;
var
  Id: string;
begin
  for Id in GWaiting do
    if not GAnswers.ContainsKey(Id) then
      GAnswers.Add(Id, False);
end;

function Line(const Kind, Text: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('k', Kind);
  Result.AddPair('t', Text);
end;

function CardJson(const Id, Target, Before, After: string): string;
const
  Kinds: array[TDiffKind] of string = ('same', 'del', 'add');
var
  Obj: TJSONObject;
  Lines: TJSONArray;
  Diff: TArray<TDiffLine>;
  Text: string;
  Index, Added, Removed: Integer;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('t', 'approval');
    Obj.AddPair('id', Id);
    Obj.AddPair('target', Target);
    Lines := TJSONArray.Create;
    Added := 0;
    Removed := 0;
    if Before = '' then
    begin
      for Text in SplitLines(After) do
        if Lines.Count < MaxLines then
          Lines.AddElement(Line('text', Text));
      Obj.AddPair('summary', '');
    end
    else
    begin
      Diff := DiffLines(Before, After);
      for Index := 0 to High(Diff) do
        case Diff[Index].Kind of
          dkAdded: Inc(Added);
          dkRemoved: Inc(Removed);
        end;
      Diff := CollapseContext(Diff, 3);
      for Index := 0 to High(Diff) do
        if Lines.Count < MaxLines then
          Lines.AddElement(Line(Kinds[Diff[Index].Kind], Diff[Index].Text));
      Obj.AddPair('summary', TrF('chatapprovalcard.summary', [Removed, Added]));
    end;
    Obj.AddPair('lines', Lines);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function ResultJson(const Id: string; Approved: Boolean): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('t', 'approvalResult');
    Obj.AddPair('id', Id);
    Obj.AddPair('ok', TJSONBool.Create(Approved));
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function AskInChat(const Target, Before, After: string): Boolean;
var
  Id: string;
  NoHandles: THandle;
begin
  NoHandles := 0;
  Inc(GNext);
  Id := 'approval-' + IntToStr(GNext);
  GWaiting.Add(Id);
  try
    RevealChat;
    ChatSession.Emit(CardJson(Id, Target, Before, After));
    while not GAnswers.ContainsKey(Id) do
    begin
      if Application.Terminated or not GEnabled then
        GAnswers.AddOrSetValue(Id, False)
      else
      begin
        MsgWaitForMultipleObjects(0, NoHandles, False, 100, QS_ALLINPUT);
        Application.ProcessMessages;
      end;
    end;
    Result := GAnswers[Id];
    GAnswers.Remove(Id);
  finally
    GWaiting.Remove(Id);
  end;
  ChatSession.Emit(ResultJson(Id, Result));
end;

initialization
  GAnswers := TDictionary<string, Boolean>.Create;
  GWaiting := TList<string>.Create;

finalization
  GWaiting.Free;
  GAnswers.Free;

end.
