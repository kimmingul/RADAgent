unit RADAgent.BtwStore;

{ Side questions (/btw) kept apart from the conversation, one JSON file per topic under
  %LOCALAPPDATA%\RADAgent\btw\<project key>\, with the topics' own omp sessions in sessions\.
  Outside the project folder so nothing is committed by accident. No ToolsAPI, no VCL. }

interface

uses
  System.JSON;

type
  TBtwTurn = record
    Question, Answer, Error: string;
    { running, done, error, stopped }
    State: string;
    Asked: string;
  end;

  TBtwTopic = record
    Id, Created: string;
    { The topic's own omp session (a fork of the conversation), used for follow-ups. }
    SessionFile: string;
    { The conversation it was asked from. }
    MainSession, MainTitle: string;
    Turns: TArray<TBtwTurn>;
  end;

function BtwDir(const ProjectDir: string): string;
function BtwSessionDir(const ProjectDir: string): string;
function NewTopicId: string;
function NowText: string;
{ Every saved topic, newest first. }
function LoadTopics(const ProjectDir: string): TArray<TBtwTopic>;
function LoadTopic(const ProjectDir, Id: string; out Topic: TBtwTopic): Boolean;
procedure SaveTopic(const ProjectDir: string; const Topic: TBtwTopic);
{ Removes the topic file and its omp session. }
procedure DeleteTopic(const ProjectDir, Id: string);
{ Same shape on disk and on the chat page. }
function TopicToJson(const Topic: TBtwTopic): TJSONObject;
function TurnToJson(const Turn: TBtwTurn): TJSONObject;

implementation

uses
  System.SysUtils, System.IOUtils, System.Generics.Collections, System.Generics.Defaults,
  RADAgent.LegacyNames;

function ProjectKey(const ProjectDir: string): string;
var
  Ch: Char;
begin
  Result := '';
  for Ch in ExcludeTrailingPathDelimiter(ProjectDir) do
    if CharInSet(Ch, ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) or (Ord(Ch) > 127) then
      Result := Result + Ch
    else
      Result := Result + '-';
end;

function BtwRoot: string;
begin
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('LOCALAPPDATA')) + 'RADAgent\btw';
  MigrateBtwNotes(Result);
end;

function BtwDir(const ProjectDir: string): string;
begin
  Result := BtwRoot + '\' + ProjectKey(ProjectDir) + '\';
end;

function BtwSessionDir(const ProjectDir: string): string;
begin
  Result := BtwDir(ProjectDir) + 'sessions';
end;

function NewTopicId: string;
begin
  Result := FormatDateTime('yyyymmdd-hhnnss-zzz', Now);
end;

function NowText: string;
begin
  Result := FormatDateTime('yyyy-mm-dd hh:nn', Now);
end;

function TurnToJson(const Turn: TBtwTurn): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('q', Turn.Question);
  Result.AddPair('a', Turn.Answer);
  Result.AddPair('state', Turn.State);
  Result.AddPair('error', Turn.Error);
  Result.AddPair('asked', Turn.Asked);
end;

function TopicToJson(const Topic: TBtwTopic): TJSONObject;
var
  Turns: TJSONArray;
  Turn: TBtwTurn;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', Topic.Id);
  Result.AddPair('created', Topic.Created);
  Result.AddPair('session', Topic.SessionFile);
  Result.AddPair('mainSession', Topic.MainSession);
  Result.AddPair('mainTitle', Topic.MainTitle);
  Turns := TJSONArray.Create;
  for Turn in Topic.Turns do
    Turns.AddElement(TurnToJson(Turn));
  Result.AddPair('turns', Turns);
end;

function TopicFromJson(Obj: TJSONObject; out Topic: TBtwTopic): Boolean;
var
  Item: TJSONValue;
  Turn: TBtwTurn;
begin
  Topic := Default(TBtwTopic);
  Topic.Id := Obj.GetValue<string>('id', '');
  Topic.Created := Obj.GetValue<string>('created', '');
  { Notes written under the old DelphiAgent folder name point there. }
  Topic.SessionFile := StringReplace(Obj.GetValue<string>('session', ''), '\DelphiAgent\btw\',
    '\RADAgent\btw\', [rfIgnoreCase]);
  Topic.MainSession := Obj.GetValue<string>('mainSession', '');
  Topic.MainTitle := Obj.GetValue<string>('mainTitle', '');
  if Obj.GetValue('turns') is TJSONArray then
    for Item in TJSONArray(Obj.GetValue('turns')) do
      if Item is TJSONObject then
      begin
        Turn.Question := Item.GetValue<string>('q', '');
        Turn.Answer := Item.GetValue<string>('a', '');
        Turn.State := Item.GetValue<string>('state', '');
        Turn.Error := Item.GetValue<string>('error', '');
        Turn.Asked := Item.GetValue<string>('asked', '');
        { A turn that was running when the IDE closed never finished. }
        if Turn.State = 'running' then
          Turn.State := 'stopped';
        Topic.Turns := Topic.Turns + [Turn];
      end;
  Result := (Topic.Id <> '') and (Length(Topic.Turns) > 0);
end;

function ReadTopicFile(const Path: string; out Topic: TBtwTopic): Boolean;
var
  Value: TJSONValue;
begin
  Result := False;
  try
    Value := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetString(TFile.ReadAllBytes(Path)).TrimLeft([#$FEFF]));
  except
    Exit;
  end;
  try
    Result := (Value is TJSONObject) and TopicFromJson(TJSONObject(Value), Topic);
  finally
    Value.Free;
  end;
end;

function LoadTopics(const ProjectDir: string): TArray<TBtwTopic>;
var
  Path: string;
  Topic: TBtwTopic;
  List: TList<TBtwTopic>;
begin
  Result := nil;
  if not DirectoryExists(BtwDir(ProjectDir)) then
    Exit;
  List := TList<TBtwTopic>.Create;
  try
    for Path in TDirectory.GetFiles(BtwDir(ProjectDir), '*.json') do
      if ReadTopicFile(Path, Topic) then
        List.Add(Topic);
    List.Sort(TComparer<TBtwTopic>.Construct(
      function(const A, B: TBtwTopic): Integer
      begin
        Result := CompareStr(B.Id, A.Id);
      end));
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function TopicPath(const ProjectDir, Id: string): string;
begin
  Result := BtwDir(ProjectDir) + Id + '.json';
end;

function LoadTopic(const ProjectDir, Id: string; out Topic: TBtwTopic): Boolean;
begin
  Result := (Id <> '') and FileExists(TopicPath(ProjectDir, Id)) and
    ReadTopicFile(TopicPath(ProjectDir, Id), Topic);
end;

procedure SaveTopic(const ProjectDir: string; const Topic: TBtwTopic);
var
  Obj: TJSONObject;
begin
  ForceDirectories(BtwDir(ProjectDir));
  Obj := TopicToJson(Topic);
  try
    TFile.WriteAllText(TopicPath(ProjectDir, Topic.Id), Obj.Format(2), TEncoding.UTF8);
  finally
    Obj.Free;
  end;
end;

procedure DeleteTopic(const ProjectDir, Id: string);
var
  Topic: TBtwTopic;
begin
  if LoadTopic(ProjectDir, Id, Topic) and (Topic.SessionFile <> '') and
    SameText(ExtractFileDir(Topic.SessionFile), BtwSessionDir(ProjectDir)) then
    System.SysUtils.DeleteFile(Topic.SessionFile);
  System.SysUtils.DeleteFile(TopicPath(ProjectDir, Id));
end;

end.
