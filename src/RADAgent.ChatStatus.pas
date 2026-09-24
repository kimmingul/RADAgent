unit RADAgent.ChatStatus;

{ Session, catalog and editor state as page messages for the top bar and the composer
  (src\chat\topbar.js, composer.js). Main thread only. }

interface

{ Connection, model, thinking level, approval mode, context use, activity, session title. }
function PageStatus: string;
{ Models and thinking levels for the composer selects. }
function PageCatalog: string;
{ Active file, selection and unsaved count for the context chips. }
function PageContext: string;
{ Slash commands for the composer's command menu. }
function PageCommands: string;
{ Project folder files (relative paths) for the composer's @ menu. }
function PageFiles: string;

implementation

uses
  System.SysUtils, System.JSON, RADAgent.ChatSession, RADAgent.RpcResponses,
  System.IOUtils, RADAgent.EditorContext, RADAgent.IdeContext, RADAgent.ChatPlan, RADAgent.Lang;

function Finish(Obj: TJSONObject): string;
begin
  try
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function StateText(Session: TChatSession; out IsError: Boolean): string;
begin
  IsError := False;
  if Session.Client = nil then
    Exit(Tr('chatstatus.idle'));
  IsError := True;
  if Session.StartError <> '' then
    Exit(TrF('chatstatus.error', [Session.StartError]));
  if Session.Client.LinkError <> '' then
    Exit(TrF('chatstatus.error', [Session.Client.LinkError]));
  IsError := False;
  if Session.Connected then
    Result := Tr('chatstatus.connected')
  else
    Result := Tr('chatstatus.connecting');
end;

function PageStatus: string;
var
  Session: TChatSession;
  Obj: TJSONObject;
  IsError: Boolean;
  Title, Folder, ProjectFile: string;
begin
  Session := ChatSession;
  Obj := TJSONObject.Create;
  Obj.AddPair('t', 'status');
  Obj.AddPair('state', StateText(Session, IsError));
  Obj.AddPair('error', TJSONBool.Create(IsError));
  Obj.AddPair('connected', TJSONBool.Create(Session.Connected));
  Obj.AddPair('busy', TJSONBool.Create(Session.Busy));
  if Session.Busy then
    Obj.AddPair('activity', Session.Activity.Text)
  else
    Obj.AddPair('activity', '');
  if Session.State.ModelId <> '' then
    Obj.AddPair('model', Session.State.Provider + '/' + Session.State.ModelId)
  else
    Obj.AddPair('model', '');
  Obj.AddPair('thinking', Session.State.ThinkingLevel);
  if PlanActive then
    Obj.AddPair('approval', 'plan')
  else
    Obj.AddPair('approval', Session.Catalog.ApprovalMode);
  if Session.State.HasContext then
    Obj.AddPair('context', TJSONNumber.Create(Session.State.ContextPercent))
  else
    Obj.AddPair('context', TJSONNumber.Create(-1));
  ProjectFile := ActiveProjectFile;
  Title := Session.State.SessionName;
  if Title = '' then
    Title := Tr('chatstatus.newConversation');
  Obj.AddPair('title', Title);
  if ProjectFile <> '' then
    Obj.AddPair('project', ChangeFileExt(ExtractFileName(ProjectFile), ''))
  else
    Obj.AddPair('project', '');
  Folder := Session.State.Cwd;
  if (Folder = '') and (Session.Client <> nil) then
    Folder := Session.Client.Cwd;
  Obj.AddPair('cwd', ExcludeTrailingPathDelimiter(Folder));
  if Session.Client <> nil then
    Obj.AddPair('pid', TJSONNumber.Create(Session.Client.Pid))
  else
    Obj.AddPair('pid', TJSONNumber.Create(0));
  Result := Finish(Obj);
end;

function StringArray(const Items: TArray<string>): TJSONArray;
var
  Item: string;
begin
  Result := TJSONArray.Create;
  for Item in Items do
    Result.Add(Item);
end;

function PageCatalog: string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  Obj.AddPair('t', 'catalog');
  Obj.AddPair('models', StringArray(ChatSession.Catalog.Models));
  Obj.AddPair('levels', StringArray(ChatSession.Catalog.ThinkingLevels));
  Result := Finish(Obj);
end;

function PageContext: string;
var
  Info: TEditorInfo;
  Obj: TJSONObject;
begin
  Info := ActiveEditorInfo;
  Obj := TJSONObject.Create;
  Obj.AddPair('t', 'context');
  Obj.AddPair('path', Info.FileName);
  Obj.AddPair('file', ExtractFileName(Info.FileName));
  if Info.HasSelection then
    Obj.AddPair('selection', Format('%d–%d', [Info.StartLine, Info.EndLine]))
  else
    Obj.AddPair('selection', '');
  Obj.AddPair('unsaved', TJSONNumber.Create(UnsavedModuleCount));
  Result := Finish(Obj);
end;

function PageCommands: string;
var
  Obj, Item: TJSONObject;
  List: TJSONArray;
  Command: TSlashCommand;
begin
  Obj := TJSONObject.Create;
  Obj.AddPair('t', 'commands');
  List := TJSONArray.Create;
  { RADAgent's own; omp's RPC command list has no /btw. }
  Item := TJSONObject.Create;
  Item.AddPair('name', 'btw');
  Item.AddPair('description', Tr('chatstatus.btwDescription'));
  Item.AddPair('hint', Tr('chatstatus.btwHint'));
  List.AddElement(Item);
  for Command in ChatSession.Commands do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('name', Command.Name);
    Item.AddPair('description', Command.Description);
    Item.AddPair('hint', Command.Hint);
    List.AddElement(Item);
  end;
  Obj.AddPair('items', List);
  Result := Finish(Obj);
end;

function PageFiles: string;
const
  MaxFiles = 3000;
  Skip: array[0..8] of string = ('.git', '.omp', '__history', '__recovery', 'Win32', 'Win64',
    'Debug', 'Release', 'node_modules');
var
  Root: string;
  Obj: TJSONObject;
  Items: TJSONArray;

  procedure Walk(const Dir: string);
  var
    Path, Name: string;
    Ignored: Boolean;
  begin
    for Path in TDirectory.GetFiles(Dir) do
      if Items.Count < MaxFiles then
        Items.Add(ExtractRelativePath(Root, Path));
    for Path in TDirectory.GetDirectories(Dir) do
    begin
      Name := ExtractFileName(Path);
      Ignored := False;
      for var Item in Skip do
        Ignored := Ignored or SameText(Item, Name);
      if not Ignored and (Items.Count < MaxFiles) then
        Walk(Path);
    end;
  end;

begin
  Root := IncludeTrailingPathDelimiter(ActiveProjectDir);
  Obj := TJSONObject.Create;
  Items := TJSONArray.Create;
  Obj.AddPair('t', 'files');
  Obj.AddPair('items', Items);
  try
    if Root <> PathDelim then
      Walk(ExcludeTrailingPathDelimiter(Root));
  except
    { An unreadable folder only shortens the list. }
  end;
  Result := Finish(Obj);
end;

end.
