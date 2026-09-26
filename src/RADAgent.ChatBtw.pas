unit RADAgent.ChatBtw;

{ /btw side questions. Each question runs in its own omp child (RADAgent.BtwRunner) forked
  from the conversation, so it works while the agent is busy and never enters the conversation.
  Follow-ups resume the topic's own session. Answers show as folded cards in the chat and stay
  in the BTW notes (RADAgent.BtwStore), listed on the page panel. Main thread only. }

interface

{ New topic when TopicId is '', else a follow-up in that topic. }
procedure AskBtw(const Question, TopicId: string);
procedure StopBtw(const TopicId: string);
procedure DeleteBtw(const TopicId: string);
{ Every topic of the active project for the notes panel. }
function PageBtwList: string;
{ Package unload: ends every side child. }
procedure ShutdownBtw;

implementation

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.Generics.Collections,
  Winapi.Windows, Vcl.ExtCtrls, RADAgent.BtwStore, RADAgent.BtwRunner, RADAgent.ChatSession,
  RADAgent.IdeContext, RADAgent.Options, RADAgent.AgentSettings, RADAgent.Lang;

const
  ProgressIntervalMs = 200;
  Guide =
    'You are answering a side question ("by the way") about the conversation above. It is ' +
    'separate from the main task: do not continue, resume or plan the main task, and do not ' +
    'claim to have run, read or changed anything. Tools are disabled; answer from the ' +
    'conversation and your own knowledge. If the conversation does not contain what is needed, ' +
    'say so briefly. Answer concisely in the language of the question.';

type
  TActiveBtw = class
  public
    Run: TBtwRun;
    Topic: TBtwTopic;
    ProjectDir: string;
    LastPost: UInt64;
    destructor Destroy; override;
  end;

  TBtwTicker = class
  public
    procedure Tick(Sender: TObject);
  end;

var
  GActive: TObjectDictionary<string, TActiveBtw>;
  GTimer: TTimer;
  GTicker: TBtwTicker;

destructor TActiveBtw.Destroy;
begin
  Run.Free;
  inherited Destroy;
end;

function GuideFile: string;
begin
  Result := ProcessTempFile('btw-guide.md');
  { Rewritten only when it differs: a running side child may be reading it. }
  if not FileExists(Result) or (TEncoding.UTF8.GetString(TFile.ReadAllBytes(Result)) <> Guide) then
  begin
    ForceDirectories(AgentTempRoot);
    TFile.WriteAllBytes(Result, TEncoding.UTF8.GetBytes(Guide));
  end;
end;

{ Chat card for one turn; the page also refreshes the notes panel from it. }
function CardJson(const Topic: TBtwTopic; Turn: Integer): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('t', 'btw');
    Obj.AddPair('topic', TopicToJson(Topic));
    Obj.AddPair('turn', TJSONNumber.Create(Turn));
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function CommandLine(const ProjectDir: string; const Topic: TBtwTopic): string;
var
  Extra: string;
  State: TChatSession;
begin
  State := ChatSession;
  Extra := '--no-tools --no-skills --no-extensions --no-lsp --no-title --session-dir ' +
    QuoteArg(BtwSessionDir(ProjectDir));
  if (Topic.SessionFile <> '') and FileExists(Topic.SessionFile) then
    Extra := Extra + ' --resume ' + QuoteArg(Topic.SessionFile)
  else if (Topic.MainSession <> '') and FileExists(Topic.MainSession) then
    Extra := Extra + ' --fork ' + QuoteArg(Topic.MainSession);
  if State.State.ModelId <> '' then
    Extra := Extra + ' --model ' + QuoteArg(State.State.Provider + '/' + State.State.ModelId);
  if State.State.ThinkingLevel <> '' then
    Extra := Extra + ' --thinking ' + State.State.ThinkingLevel;
  Result := BuildOmpCommandLine(OmpCommand, ProjectDir, [], GuideFile, Extra);
end;

procedure EnsureTimer;
begin
  if GTimer = nil then
  begin
    GTicker := TBtwTicker.Create;
    GTimer := TTimer.Create(nil);
    GTimer.Interval := 100;
    GTimer.OnTimer := GTicker.Tick;
  end;
  GTimer.Enabled := True;
end;

function IsCurrentProject(const ProjectDir: string): Boolean;
var
  CurrentDir: string;
begin
  CurrentDir := ExcludeTrailingPathDelimiter(ActiveProjectDir);
  Result := (CurrentDir <> '') and (ProjectDir <> '') and
    SameText(ExcludeTrailingPathDelimiter(ProjectDir), CurrentDir);
end;

procedure AskBtw(const Question, TopicId: string);
var
  Active: TActiveBtw;
  Topic: TBtwTopic;
  Turn: TBtwTurn;
  Dir: string;
begin
  Dir := ActiveProjectDir;
  if Trim(Question) = '' then
    Exit;
  if Dir = '' then
  begin
    ChatSession.Notice('warn', Tr('chatbtw.needProject'));
    Exit;
  end;
  if TopicId <> '' then
  begin
    if GActive.ContainsKey(TopicId) then
    begin
      if IsCurrentProject(GActive[TopicId].ProjectDir) then
        ChatSession.Notice('warn', Tr('chatbtw.alreadyRunning'))
      else
        ChatSession.Notice('warn', Tr('chatbtw.notFound'));
      Exit;
    end;
    if not LoadTopic(Dir, TopicId, Topic) then
    begin
      ChatSession.Notice('warn', Tr('chatbtw.notFound'));
      Exit;
    end;
  end
  else
  begin
    Topic := Default(TBtwTopic);
    Topic.Id := NewTopicId;
    Topic.Created := NowText;
    Topic.MainSession := ChatSession.State.SessionFile;
    Topic.MainTitle := ChatSession.State.SessionName;
  end;
  Turn := Default(TBtwTurn);
  Turn.Question := Trim(Question);
  Turn.State := 'running';
  Turn.Asked := NowText;
  Topic.Turns := Topic.Turns + [Turn];
  ForceDirectories(BtwSessionDir(Dir));
  Active := TActiveBtw.Create;
  Active.ProjectDir := Dir;
  Active.Run := TBtwRun.Create;
  Active.Run.Start(CommandLine(Dir, Topic), Dir, ProcessTempFile('btw-' + Topic.Id + '.stderr.log'),
    Turn.Question);
  Active.Topic := Topic;
  GActive.Add(Topic.Id, Active);
  SaveTopic(Dir, Topic);
  if IsCurrentProject(Dir) then
    ChatSession.Emit(CardJson(Topic, High(Topic.Turns)));
  EnsureTimer;
end;

procedure Settle(Active: TActiveBtw);
var
  Last: Integer;
begin
  Last := High(Active.Topic.Turns);
  Active.Topic.Turns[Last].Answer := Active.Run.Text;
  if not Active.Run.Finished then
    Exit;
  Active.Topic.Turns[Last].Error := Active.Run.Error;
  if Active.Run.Aborted then
    Active.Topic.Turns[Last].State := 'stopped'
  else if Active.Run.Error <> '' then
    Active.Topic.Turns[Last].State := 'error'
  else
    Active.Topic.Turns[Last].State := 'done';
  if Active.Run.SessionFile <> '' then
    Active.Topic.SessionFile := Active.Run.SessionFile;
  SaveTopic(Active.ProjectDir, Active.Topic);
end;

procedure TBtwTicker.Tick(Sender: TObject);
var
  Id: string;
  Active: TActiveBtw;
  Done: TArray<string>;
begin
  Done := nil;
  for Id in GActive.Keys do
  begin
    Active := GActive[Id];
    if not Active.Run.Poll and not Active.Run.Finished then
      Continue;
    Settle(Active);
    if Active.Run.Finished then
    begin
      if IsCurrentProject(Active.ProjectDir) then
        ChatSession.Emit(CardJson(Active.Topic, High(Active.Topic.Turns)));
      Done := Done + [Id];
    end
    else if GetTickCount64 - Active.LastPost >= ProgressIntervalMs then
    begin
      Active.LastPost := GetTickCount64;
      if IsCurrentProject(Active.ProjectDir) then
        ChatSession.PostToView(CardJson(Active.Topic, High(Active.Topic.Turns)));
    end;
  end;
  for Id in Done do
    GActive.Remove(Id);
  GTimer.Enabled := GActive.Count > 0;
end;

procedure StopBtw(const TopicId: string);
begin
  if GActive.ContainsKey(TopicId) then
    GActive[TopicId].Run.Abort;
end;

procedure DeleteBtw(const TopicId: string);
var
  Dir: string;
begin
  Dir := ActiveProjectDir;
  if GActive.ContainsKey(TopicId) then
  begin
    Dir := GActive[TopicId].ProjectDir;
    GActive.Remove(TopicId);
  end;
  if Dir <> '' then
    DeleteTopic(Dir, TopicId);
  if IsCurrentProject(Dir) then
    ChatSession.PostToView(PageBtwList);
end;

function PageBtwList: string;
var
  Obj: TJSONObject;
  Items: TJSONArray;
  Topic: TBtwTopic;
  Dir: string;
begin
  Dir := ActiveProjectDir;
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('t', 'btwList');
    Obj.AddPair('session', ChatSession.State.SessionFile);
    Items := TJSONArray.Create;
    Obj.AddPair('items', Items);
    if Dir <> '' then
      for Topic in LoadTopics(Dir) do
        { A running topic on disk looks stopped; the live one is current. }
        if GActive.ContainsKey(Topic.Id) and IsCurrentProject(GActive[Topic.Id].ProjectDir) then
          Items.AddElement(TopicToJson(GActive[Topic.Id].Topic))
        else
          Items.AddElement(TopicToJson(Topic));
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

procedure ShutdownBtw;
begin
  FreeAndNil(GTimer);
  FreeAndNil(GTicker);
  { TActiveBtw.Destroy frees the run, which ends its child. }
  GActive.Clear;
end;

initialization
  GActive := TObjectDictionary<string, TActiveBtw>.Create([doOwnsValues]);

finalization
  ShutdownBtw;
  FreeAndNil(GActive);

end.
