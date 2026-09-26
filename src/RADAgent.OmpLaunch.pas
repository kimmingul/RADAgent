unit RADAgent.OmpLaunch;

{ Files written before each omp start: a RADAgent --config that inlines the rad.* tool docs,
  the project guide appended to omp's system prompt (language, framework, forms, how to use the
  IDE tools) and <project>\.omp\lsp.json: DelphiLSP for Delphi, clangd for C++Builder
  (RADAgent.CppLsp). No VCL. }

interface

uses
  RADAgent.ProjectProfile, RADAgent.HostToolDefs, RADAgent.Skills;

{ %TEMP%\RADAgent\omp-host-p<pid>.yml: tools.xdevInlineDevices = rad.* and the skill folder. }
function HostConfigFile(const Skills: TSkillSet; const UserSkillDirs: TArray<string>): string;
{ %TEMP%\RADAgent\project-guide-p<pid>.md for Profile. }
function WriteProjectGuide(const Profile: TProjectProfile; LspReady: Boolean;
  const SkillName: string = ''): string;
{ Writes <project>\.omp\lsp.json when the IDE generated <project>.delphilsp.json. }
function EnsureDelphiLsp(const Profile: TProjectProfile): Boolean;
{ <project>.delphilsp.json next to the project, or ''. }
function DelphiLspSettingsFile(const Profile: TProjectProfile): string;
{ Everything an omp start needs for the active project. Note is a one-time hint for the chat.
  UserSkillDirs: the skills.customDirectories omp has without RAD Agent. }
procedure PrepareLaunch(const ProjectOverlay: string; const UserSkillDirs: TArray<string>;
  out Tools: TToolProfile; out Configs: TArray<string>; out Guide, Note, ExtraArgs: string);

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, Winapi.Windows,
  RADAgent.Options, RADAgent.AgentSettings, RADAgent.ChatPlan, RADAgent.OmpCheck,
  RADAgent.ChatCheckpoints, RADAgent.Lang, RADAgent.CppLsp;

procedure WriteText(const Path, Text: string);
begin
  ForceDirectories(ExtractFileDir(Path));
  { No BOM: omp reads these as YAML/JSON/Markdown. }
  TFile.WriteAllBytes(Path, TEncoding.UTF8.GetBytes(Text));
end;

function HostConfigFile(const Skills: TSkillSet; const UserSkillDirs: TArray<string>): string;
begin
  Result := ProcessTempFile('omp-host.yml');
  WriteText(Result, HostConfigJson(Skills, UserSkillDirs));
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
  Delphi, Init, Config: TJSONObject;
  Types, Markers: TJSONArray;
begin
  Settings := DelphiLspSettingsFile(Profile);
  Server := IncludeTrailingPathDelimiter(BdsDir) + 'bin64\DelphiLSP.exe';
  { Releases without a 64-bit IDE (10.4 to 12) ship only the 32-bit server. }
  if not FileExists(Server) then
    Server := IncludeTrailingPathDelimiter(BdsDir) + 'bin\DelphiLSP.exe';
  Result := (Settings <> '') and FileExists(Server);
  if not Result then
    Exit;
  Delphi := TJSONObject.Create;
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
  Result := UpdateLspServer(Profile.ProjectDir, 'delphilsp', Delphi);
end;

var
  GLspNoted: string;

procedure PrepareLaunch(const ProjectOverlay: string; const UserSkillDirs: TArray<string>;
  out Tools: TToolProfile; out Configs: TArray<string>; out Guide, Note, ExtraArgs: string);
var
  Profile: TProjectProfile;
  Lsp: Boolean;
  Skills: TSkillSet;
begin
  Profile := ActiveProfile;
  Tools := Profile.Tools;
  Tools.PlanMode := PlanActive;
  Skills := WriteSkill(Profile.Tools.Language);
  Configs := [HostConfigFile(Skills, UserSkillDirs), ProjectOverlay];
  ExtraArgs := OmpExtraArgs;
  { Plan mode: omp asks before disk tools, and RADAgent answers Deny. }
  if PlanActive then
    ExtraArgs := Trim(ExtraArgs + ' --approval-mode always-ask');
  if Profile.Tools.Language = 'cpp' then
    Lsp := EnsureClangd(Profile)
  else
    Lsp := EnsureDelphiLsp(Profile);
  if Skills.Dir = '' then
    Skills.Name := '';
  Guide := WriteProjectGuide(Profile, Lsp, Skills.Name);
  { A new omp is checked once, in the background; the chat hears about problems. A new RAD Agent
    says so once, with its release notes. }
  AnnounceAgentUpdate;
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
  end
  else if not Lsp and (Profile.Tools.Language = 'cpp') and (Profile.ProjectFile <> '') and
    not SameText(GLspNoted, Profile.ProjectFile) then
  begin
    GLspNoted := Profile.ProjectFile;
    Note := Tr('omplaunch.noClangdNote');
  end;
end;

function WriteProjectGuide(const Profile: TProjectProfile; LspReady: Boolean;
  const SkillName: string): string;
var
  Lines: TStringList;
  Module: TProjectModule;
  Forms: Integer;
begin
  Result := ProcessTempFile('project-guide.md');
  Lines := TStringList.Create;
  try
    Lines.Add('# RAD Studio IDE host (RAD Agent)');
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
    Lines.Add('- Never edit form files (.dfm/.fmx) or the project files (.dproj/.dpr/.cbproj/.groupproj) ' +
      'with your own write/edit tools; forms change only through the rad.form_* tools, modules through ' +
      'rad.new_module.');
    if Profile.Tools.HasForms and Profile.Tools.FormText then
      Lines.Add('- For bulk property changes across many forms or components, rad.form_text_edit edits ' +
        'the form text (properties only) with one approval.');
    if Profile.Tools.HasForms then
      Lines.Add('- After building or changing a layout, look at it with rad.form_screenshot and fix ' +
        'overlaps, alignment and clipped text before answering.');
    if Profile.Tools.HasForms and (Profile.Tools.Language = 'cpp') then
      Lines.Add('- Build UI in the designer with rad.form_apply (one call, one approval). Its events (and ' +
        'rad.form_set_event) add each handler: the __fastcall declaration in the form class''s ' +
        '__published section (.h) and a body with one comment (.cpp). Then fill the bodies in the .cpp; ' +
        'do not declare handlers by hand. Check classes with rad.list_components when unsure.')
    else if Profile.Tools.HasForms then
      Lines.Add('- Build UI in the designer with rad.form_apply (one call, one approval), then write the ' +
        'handlers in the .pas file. Check classes with rad.list_components when unsure.');
    if (Profile.Tools.Framework <> '') and Profile.Tools.DesignerUi then
      Lines.Add('- UI rule (project setting "designer required"): build every fixed part of the UI in the ' +
        'form designer - forms, frames, dialogs, the main menu and its items, toolbars, status bars, ' +
        'panels, layouts, tab sheets. New forms, frames and dialogs come from rad.new_module (kind form ' +
        'or frame); components, properties and events from rad.form_apply. A dialog is a designed form, ' +
        'not TForm.CreateNew. Create controls in code only when their number or kind comes from data at ' +
        'run time (grid columns, list rows, recent-file menu entries), under a designed parent. A custom ' +
        'control class (derived from TControl or TComponent, drawing itself or making its own scroll ' +
        'bars and sub-controls in its constructor) is not form UI: keep its parts in code and do not ' +
        'turn it into a frame. If a fixed part seems impossible in the designer, ask the user before ' +
        'building it in code.')
    else if Profile.Tools.Framework <> '' then
      Lines.Add('- Prefer the form designer for fixed UI (rad.new_module, rad.form_apply); this project ' +
        'allows building UI in code where that is clearly simpler.');
    Lines.Add('- While a debug session is running (rad.debug_state), do not edit sources unless asked.');
    Lines.Add('- Every user message is a git checkpoint; do not run git commands that commit, reset or ' +
      'switch branches unless the user asks.');
    Lines.Add('- After changes call rad.compile and fix the reported errors before answering.');
    Lines.Add('- Use rad.project_info for configurations, platforms and modules; rad.set_build_config ' +
      'to switch them.');
    if (Profile.Tools.Language = 'cpp') and LspReady then
      Lines.Add('- clangd is configured: use the lsp tool for definition, references, hover and ' +
        'diagnostics. ' + CppLspNoise)
    else if Profile.Tools.Language = 'cpp' then
      Lines.Add('- No language server for C++ here: use grep/read for navigation.')
    else if LspReady then
      Lines.Add('- DelphiLSP is configured: use the lsp tool for definition and diagnostics; it does not ' +
        'answer references, so use grep for those.')
    else
      Lines.Add('- DelphiLSP is not configured for this project (no .delphilsp.json); use grep/read.');
    if SkillName <> '' then
      Lines.Add('- Before writing code, adding units or forms, or naming components, read skill://' +
        SkillName + ' (conventions, project layout, component usage). The project''s own style and ' +
        'rules win over it.');
    Lines.Add('- RAD Studio sources for VCL/FMX/RTL declarations and defaults: ' +
      IncludeTrailingPathDelimiter(BdsDir) + 'source (grep there instead of guessing an API).');
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
