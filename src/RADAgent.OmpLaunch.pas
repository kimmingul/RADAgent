unit RADAgent.OmpLaunch;

{ Files written before each omp start: a RADAgent --config that inlines the rad.* tool docs,
  the project guide appended to omp's system prompt (language, framework, forms, how to use the
  IDE tools) and, for Delphi projects, <project>\.omp\lsp.json for DelphiLSP. No VCL. }

interface

uses
  RADAgent.ProjectProfile, RADAgent.HostToolDefs;

{ %TEMP%\RADAgent\omp-host-p<pid>.yml: tools.xdevInlineDevices = rad.* }
function HostConfigFile: string;
{ %TEMP%\RADAgent\project-guide-p<pid>.md for Profile. }
function WriteProjectGuide(const Profile: TProjectProfile; LspReady: Boolean): string;
{ Writes <project>\.omp\lsp.json when the IDE generated <project>.delphilsp.json. }
function EnsureDelphiLsp(const Profile: TProjectProfile): Boolean;
{ <project>.delphilsp.json next to the project, or ''. }
function DelphiLspSettingsFile(const Profile: TProjectProfile): string;
{ Everything an omp start needs for the active project. Note is a one-time hint for the chat. }
procedure PrepareLaunch(const ProjectOverlay: string; out Tools: TToolProfile;
  out Configs: TArray<string>; out Guide, Note, ExtraArgs: string);

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, Winapi.Windows,
  RADAgent.Options, RADAgent.AgentSettings, RADAgent.ChatPlan, RADAgent.OmpCheck,
  RADAgent.ChatCheckpoints, RADAgent.Lang;

procedure WriteText(const Path, Text: string);
begin
  ForceDirectories(ExtractFileDir(Path));
  { No BOM: omp reads these as YAML/JSON/Markdown. }
  TFile.WriteAllBytes(Path, TEncoding.UTF8.GetBytes(Text));
end;

function HostConfigFile: string;
begin
  Result := ProcessTempFile('omp-host.yml');
  WriteText(Result, OmpHostConfig);
end;

function DelphiLspSettingsFile(const Profile: TProjectProfile): string;
begin
  Result := '';
  if (Profile.ProjectFile = '') or (Profile.Tools.Language <> 'delphi') then
    Exit;
  Result := ChangeFileExt(Profile.ProjectFile, '.delphilsp.json');
  if not FileExists(Result) then
    Result := '';
end;

function BdsDir: string;
begin
  Result := GetEnvironmentVariable('BDS');
  if Result = '' then
    Result := ExtractFileDir(ExtractFileDir(ParamStr(0)));
end;

function FileUri(const Path: string): string;
begin
  Result := 'file:///' + StringReplace(Path, '\', '/', [rfReplaceAll]);
end;

{ templates/omp.lsp.json filled in; see .agents/skills/delphi-lsp. }
function EnsureDelphiLsp(const Profile: TProjectProfile): Boolean;
var
  Settings, Server: string;
  Root, Servers, Delphi, Init, Config: TJSONObject;
  Types, Markers: TJSONArray;
begin
  Settings := DelphiLspSettingsFile(Profile);
  Server := IncludeTrailingPathDelimiter(BdsDir) + 'bin64\DelphiLSP.exe';
  Result := (Settings <> '') and FileExists(Server);
  if not Result then
    Exit;
  Root := TJSONObject.Create;
  try
    Servers := TJSONObject.Create;
    Root.AddPair('servers', Servers);
    Delphi := TJSONObject.Create;
    Servers.AddPair('delphilsp', Delphi);
    Delphi.AddPair('command', Server);
    Types := TJSONArray.Create;
    Types.Add('.pas').Add('.dpr').Add('.dpk').Add('.pp').Add('.inc');
    Delphi.AddPair('fileTypes', Types);
    Delphi.AddPair('languageId', 'pascal');
    Markers := TJSONArray.Create;
    Markers.Add('*.dproj').Add('*.dpr').Add('*.groupproj');
    Delphi.AddPair('rootMarkers', Markers);
    Delphi.AddPair('warmupTimeoutMs', TJSONNumber.Create(60000));
    Init := TJSONObject.Create;
    Init.AddPair('serverType', 'controller');
    Init.AddPair('agentCount', TJSONNumber.Create(2));
    Init.AddPair('returnDccFlags', TJSONTrue.Create);
    Init.AddPair('returnHoverModel', TJSONTrue.Create);
    Init.AddPair('storeProjectSettings', TJSONFalse.Create);
    Delphi.AddPair('initOptions', Init);
    Config := TJSONObject.Create;
    Config.AddPair('settingsFile', FileUri(Settings));
    Delphi.AddPair('settings', Config);
    WriteText(TPath.Combine(Profile.ProjectDir, '.omp\lsp.json'), Root.Format(2));
  finally
    Root.Free;
  end;
end;

var
  GLspNoted: string;

procedure PrepareLaunch(const ProjectOverlay: string; out Tools: TToolProfile;
  out Configs: TArray<string>; out Guide, Note, ExtraArgs: string);
var
  Profile: TProjectProfile;
  Lsp: Boolean;
begin
  Profile := ActiveProfile;
  Tools := Profile.Tools;
  Tools.PlanMode := PlanActive;
  Configs := [HostConfigFile, ProjectOverlay];
  ExtraArgs := OmpExtraArgs;
  { Plan mode: omp asks before disk tools, and RADAgent answers Deny. }
  if PlanActive then
    ExtraArgs := Trim(ExtraArgs + ' --approval-mode always-ask');
  Lsp := EnsureDelphiLsp(Profile);
  Guide := WriteProjectGuide(Profile, Lsp);
  { A new omp is checked once, in the background; the chat hears about problems. }
  if Profile.ProjectDir <> '' then
  begin
    CheckOmpAfterUpdate(Profile.ProjectDir);
    { Every project is a git repository: each user message becomes a checkpoint. }
    EnsureProjectRepo(ExcludeTrailingPathDelimiter(Profile.ProjectDir));
  end;
  Note := '';
  if not Lsp and (Profile.Tools.Language = 'delphi') and (Profile.ProjectFile <> '') and
    not SameText(GLspNoted, Profile.ProjectFile) then
  begin
    GLspNoted := Profile.ProjectFile;
    Note := Tr('omplaunch.noDelphiLspNote');
  end;
end;

function WriteProjectGuide(const Profile: TProjectProfile; LspReady: Boolean): string;
var
  Lines: TStringList;
  Module: TProjectModule;
  Forms: Integer;
begin
  Result := ProcessTempFile('project-guide.md');
  Lines := TStringList.Create;
  try
    Lines.Add('# RAD Studio IDE host (RADAgent)');
    Lines.Add('You run inside RAD Studio. The rad.* tools act on the live IDE: open buffers (unsaved ' +
      'text included), the form designer, the build and the debugger. The user approves every change.');
    if Profile.ProjectFile = '' then
      Lines.Add('No project is open.')
    else
    begin
      Lines.Add('');
      Lines.Add('## Active project');
      Lines.Add('- File: ' + Profile.ProjectFile);
      if Profile.Tools.Language = 'cpp' then
        Lines.Add('- Language: C++Builder (C++, .cpp/.h, forms .dfm or .fmx)')
      else
        Lines.Add('- Language: Delphi (Object Pascal, .pas/.dpr)');
      if Profile.Tools.Framework <> '' then
        Lines.Add('- Framework: ' + Profile.Tools.Framework)
      else
        Lines.Add('- Framework: none (console or library)');
      Forms := 0;
      for Module in Profile.Modules do
        if Module.FormName <> '' then
        begin
          Lines.Add(Format('- Form %s: %s', [Module.FormName, Module.FileName]));
          Inc(Forms);
        end;
      if Forms = 0 then
        Lines.Add('- No forms yet. rad.new_module kind=form adds one; the form tools appear after it.');
    end;
    Lines.Add('');
    Lines.Add('## How to work');
    Lines.Add('- Files on disk are current: the IDE saves every open file before each of your turns and ' +
      'reloads the files you change. Read and edit code with your own read/edit/write tools.');
    Lines.Add('- Never edit form files (.dfm/.fmx) or the project files (.dproj/.dpr/.cbproj/.groupproj) as text; ' +
      'forms change only through the rad.form_* tools, modules through rad.new_module.');
    if Profile.Tools.HasForms and (Profile.Tools.Language = 'cpp') then
      Lines.Add('- Build UI in the designer with rad.form_apply (one call, one approval). Its events (and ' +
        'rad.form_set_event) add each handler: the __fastcall declaration in the form class''s ' +
        '__published section (.h) and a body with one comment (.cpp). Then fill the bodies in the .cpp; ' +
        'do not declare handlers by hand. Check classes with rad.list_components when unsure.')
    else if Profile.Tools.HasForms then
      Lines.Add('- Build UI in the designer with rad.form_apply (one call, one approval), then write the ' +
        'handlers in the .pas file. Check classes with rad.list_components when unsure.');
    Lines.Add('- While a debug session is running (rad.debug_state), do not edit sources unless asked.');
    Lines.Add('- Every user message is a git checkpoint; do not run git commands that commit, reset or ' +
      'switch branches unless the user asks.');
    Lines.Add('- After changes call rad.compile and fix the reported errors before answering.');
    Lines.Add('- Use rad.project_info for configurations, platforms and modules; rad.set_build_config ' +
      'to switch them.');
    if Profile.Tools.Language = 'cpp' then
      Lines.Add('- No language server for C++ here: use grep/read for navigation.')
    else if LspReady then
      Lines.Add('- DelphiLSP is configured: use the lsp tool for definition and diagnostics; it does not ' +
        'answer references, so use grep for those.')
    else
      Lines.Add('- DelphiLSP is not configured for this project (no .delphilsp.json); use grep/read.');
    Lines.Add('- The rad.* schemas are already in this prompt; do not read xd://rad.* docs first.');
    Lines.Add('- @path in the user message is the current file content.');
    Lines.Add('- Subagents (task tool) cannot call rad.* tools. They may edit .pas/.inc/.cpp/.h files on ' +
      'disk in parallel when each owns different files (name the files in each task); forms, project ' +
      'files and compiling stay in this session. After they finish, call rad.compile and fix errors.');
    if PlanActive then
    begin
      Lines.Add('');
      Lines.Add('## PLAN MODE (active)');
      Lines.Add('- Do not change anything: no rad.* changes, no write/edit/bash on files. Investigate with ' +
        'read, grep, glob, rad.project_info, rad.form_components.');
      Lines.Add('- Finish with exactly one rad.submit_plan call (title, slug in English, goal, context, ' +
        'steps, files, risks, verification) and stop. The user reviews it and chooses to proceed.');
      Lines.Add('- Write the plan in the user''s language.');
    end;
    Lines.Add('- Do not read skills about IDE file operations; these rules replace them.');
    if EnglishWork then
    begin
      Lines.Add('');
      Lines.Add('## Language');
      Lines.Add('- Work in English to save tokens: thinking, plans, todo items, tool call intents and ' +
        'every subagent task and report.');
      Lines.Add('- Reply to the user in the language of their message.');
      Lines.Add('- What stays in files follows the project, not this rule: keep string literals, comments, ' +
        'commit messages and documents (docs\plans) in the language the project already uses for them.');
    end;
    WriteText(Result, Lines.Text);
  finally
    Lines.Free;
  end;
end;

end.
