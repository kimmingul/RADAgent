unit DelphiAgent.ChatExtensions;

{ The composer's + menu on the IDE side: files and pictures to attach, extra workspace folders,
  connectors (MCP servers) and plugins (omp plugins and extension modules) with on/off switches.
  Main thread only. }

interface

{ Page message "extensions": connectors and plugins with their state. }
function PageExtensions: string;
{ File dialog; page message "attachments" with the chosen files, or '' when cancelled. }
function PickAttachments: string;
{ Folder dialog, then omp /add-dir. }
procedure AddWorkspaceFolder;
{ Connector: omp /mcp enable|disable (applies at once). }
procedure ToggleConnector(const Name: string; Enable: Boolean);
{ Plugin (Kind 'plugin': omp plugin enable|disable) or extension module (Kind 'extension':
  this project's disabledExtensions). Both restart omp on the same session. }
procedure TogglePlugin(const Kind, Name: string; Enable: Boolean);
{ Prompt parts for attached files: text for omp (paths) and ImageContent[] for small pictures. }
procedure BuildAttachments(const Paths: TArray<string>; out Text, ImagesJson, Display: string);

implementation

uses
  System.SysUtils, System.Classes, System.JSON, System.IOUtils, System.NetEncoding, Vcl.Dialogs,
  DelphiAgent.ChatSession, DelphiAgent.OmpCatalog, DelphiAgent.OmpSettings, DelphiAgent.OmpCli,
  DelphiAgent.AgentSettings,
  DelphiAgent.IdeContext;

const
  { v1 frames are 1 MiB; base64 grows 4/3, so larger pictures go by path. }
  MaxInlineImage = 600 * 1024;

function ProjectDir: string;
begin
  Result := ExcludeTrailingPathDelimiter(ActiveProjectDir);
  if (Result = '') and (ChatSession.Client <> nil) then
    Result := ExcludeTrailingPathDelimiter(ChatSession.Client.Cwd);
end;

function Entry(const Id, Name, Detail: string; Enabled: Boolean): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', Id);
  Result.AddPair('name', Name);
  Result.AddPair('detail', Detail);
  Result.AddPair('enabled', TJSONBool.Create(Enabled));
end;

function PageExtensions: string;
var
  Obj, Item: TJSONObject;
  Connectors, Plugins: TJSONArray;
  Server: TMcpServer;
  Plugin: TPluginInfo;
  Module: TToggleItem;
  Dir: string;
begin
  Dir := ProjectDir;
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('t', 'extensions');
    Connectors := TJSONArray.Create;
    for Server in DiscoverMcpServers(Dir) do
      Connectors.AddElement(Entry(Server.Name, Server.Name, Server.Source, Server.Enabled));
    Obj.AddPair('connectors', Connectors);
    Plugins := TJSONArray.Create;
    for Plugin in ChatSession.Catalog.Plugins do
    begin
      Item := Entry(Plugin.Name, Plugin.Name, Plugin.Source, Plugin.Enabled);
      Item.AddPair('kind', 'plugin');
      Plugins.AddElement(Item);
    end;
    for Module in DiscoverExtensionModules(Dir) do
    begin
      Item := Entry(Module.Name, Module.Name, '확장 · ' + Module.Source,
        (ChatSession.Catalog.Project = nil) or
        not ChatSession.Catalog.Project.IsDisabled(ToggleIdPrefix[tkExtension] + Module.Name));
      Item.AddPair('kind', 'extension');
      Plugins.AddElement(Item);
    end;
    Obj.AddPair('plugins', Plugins);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function IsPicture(const Path: string): Boolean;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(Path));
  Result := (Ext = '.png') or (Ext = '.jpg') or (Ext = '.jpeg') or (Ext = '.gif') or (Ext = '.webp');
end;

function MimeOf(const Path: string): string;
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(Path));
  if Ext = '.png' then
    Result := 'image/png'
  else if (Ext = '.jpg') or (Ext = '.jpeg') then
    Result := 'image/jpeg'
  else if Ext = '.gif' then
    Result := 'image/gif'
  else
    Result := 'image/webp';
end;

function PickAttachments: string;
var
  Dialog: TOpenDialog;
  Obj, Item: TJSONObject;
  Items: TJSONArray;
  Path: string;
begin
  Result := '';
  Dialog := TOpenDialog.Create(nil);
  try
    Dialog.Title := '파일 또는 사진 추가';
    Dialog.Filter := '모든 파일 (*.*)|*.*|사진 (*.png;*.jpg;*.jpeg;*.gif;*.webp)|*.png;*.jpg;*.jpeg;*.gif;*.webp';
    Dialog.Options := Dialog.Options + [ofAllowMultiSelect, ofFileMustExist];
    if not Dialog.Execute then
      Exit;
    Obj := TJSONObject.Create;
    try
      Obj.AddPair('t', 'attachments');
      Items := TJSONArray.Create;
      for Path in Dialog.Files do
      begin
        Item := TJSONObject.Create;
        Item.AddPair('path', Path);
        Item.AddPair('name', ExtractFileName(Path));
        Item.AddPair('image', TJSONBool.Create(IsPicture(Path)));
        Items.AddElement(Item);
      end;
      Obj.AddPair('items', Items);
      Result := Obj.ToJSON;
    finally
      Obj.Free;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure BuildAttachments(const Paths: TArray<string>; out Text, ImagesJson, Display: string);
var
  Images: TJSONArray;
  Image: TJSONObject;
  Path: string;
  Names: TStringList;
begin
  Text := '';
  ImagesJson := '';
  Images := TJSONArray.Create;
  Names := TStringList.Create;
  try
    for Path in Paths do
    begin
      if not FileExists(Path) then
        Continue;
      Names.Add(ExtractFileName(Path));
      if IsPicture(Path) and (TFile.GetSize(Path) <= MaxInlineImage) then
      begin
        Image := TJSONObject.Create;
        Image.AddPair('type', 'image');
        Image.AddPair('data', TNetEncoding.Base64String.EncodeBytesToString(TFile.ReadAllBytes(Path)));
        Image.AddPair('mimeType', MimeOf(Path));
        Images.AddElement(Image);
      end
      else
        Text := Text + sLineBreak + '첨부 파일: ' + Path;
    end;
    if Images.Count > 0 then
      ImagesJson := Images.ToJSON;
    Names.Delimiter := ',';
    Names.StrictDelimiter := True;
    Display := '';
    if Names.Count > 0 then
      Display := '첨부: ' + StringReplace(Names.DelimitedText, ',', ', ', [rfReplaceAll]);
  finally
    Names.Free;
    Images.Free;
  end;
end;

procedure AddWorkspaceFolder;
var
  Dialog: TFileOpenDialog;
  Folder: string;
begin
  if not ChatSession.Connected or ChatSession.Busy then
    Exit;
  Dialog := TFileOpenDialog.Create(nil);
  try
    Dialog.Title := '폴더 추가';
    Dialog.Options := Dialog.Options + [fdoPickFolders];
    if not Dialog.Execute then
      Exit;
    Folder := Dialog.FileName;
  finally
    Dialog.Free;
  end;
  { omp keeps extra roots for the session; the agent may read, grep and glob them. }
  if ChatSession.Client.SendPrompt('/add-dir ' + Folder) then
    ChatSession.Notice('info', '작업 폴더를 추가했습니다: ' + Folder);
end;

procedure ToggleConnector(const Name: string; Enable: Boolean);
const
  Verb: array[Boolean] of string = ('disable', 'enable');
  Word: array[Boolean] of string = ('껐습니다', '켰습니다');
begin
  if not ChatSession.Connected or ChatSession.Busy then
    Exit;
  if ChatSession.Client.SendPrompt('/mcp ' + Verb[Enable] + ' ' + Name) then
    ChatSession.Notice('info', '커넥터 ' + Name + '을(를) ' + Word[Enable]);
end;

procedure TogglePlugin(const Kind, Name: string; Enable: Boolean);
const
  Verb: array[Boolean] of string = ('disable', 'enable');
  Word: array[Boolean] of string = ('껐습니다', '켰습니다');
var
  Project: TOmpProjectSettings;
begin
  if Kind = 'plugin' then
    RunOmp(OmpCommand, 'plugin ' + Verb[Enable] + ' ' + Name, ProjectDir, 20000)
  else
  begin
    Project := ChatSession.Catalog.Project;
    if Project = nil then
      Exit;
    Project.SetDisabled(ToggleIdPrefix[tkExtension] + Name, not Enable);
    Project.Save;
  end;
  ChatSession.Notice('info', '플러그인 ' + Name + '을(를) ' + Word[Enable] + '. omp를 다시 시작합니다.');
  ChatSession.RestartWhenIdle;
end;

end.
