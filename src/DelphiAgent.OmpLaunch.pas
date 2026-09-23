unit DelphiAgent.OmpLaunch;

{ Files written before each omp start: a DelphiAgent --config that inlines the rad.* tool docs,
  the project guide appended to omp's system prompt (language, framework, forms, how to use the
  IDE tools) and, for Delphi projects, <project>\.omp\lsp.json for DelphiLSP. No VCL. }

interface

uses
  DelphiAgent.ProjectProfile, DelphiAgent.HostToolDefs;

{ %TEMP%\DelphiAgent\omp-host.yml: tools.xdevInlineDevices = rad.* }
function HostConfigFile: string;
{ %TEMP%\DelphiAgent\project-guide.md for Profile. }
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
  DelphiAgent.Options, DelphiAgent.AgentSettings, DelphiAgent.ChatPlan;

procedure WriteText(const Path, Text: string);
begin
  ForceDirectories(ExtractFileDir(Path));
  { No BOM: omp reads these as YAML/JSON/Markdown. }
  TFile.WriteAllBytes(Path, TEncoding.UTF8.GetBytes(Text));
end;

function HostConfigFile: string;
begin
  Result := AgentTempRoot + 'omp-host.yml';
  WriteText(Result, '{"tools":{"xdevInlineDevices":["rad.*"]}}');
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
  { Plan mode: omp asks before disk tools, and DelphiAgent answers Deny. }
  if PlanActive then
    ExtraArgs := Trim(ExtraArgs + ' --approval-mode always-ask');
  Lsp := EnsureDelphiLsp(Profile);
  Guide := WriteProjectGuide(Profile, Lsp);
  Note := '';
  if not Lsp and (Profile.Tools.Language = 'delphi') and (Profile.ProjectFile <> '') and
    not SameText(GLspNoted, Profile.ProjectFile) then
  begin
    GLspNoted := Profile.ProjectFile;
    Note := 'DelphiLSP 설정이 없어 omp가 grep으로 코드를 찾습니다. Tools > Options > Editor > Language > ' +
      'Code Insight에서 Generate LSP Config를 켜고 프로젝트를 다시 열면 연결됩니다.';
  end;
end;

function WriteProjectGuide(const Profile: TProjectProfile; LspReady: Boolean): string;
var
  Lines: TStringList;
  Module: TProjectModule;
  Forms: Integer;
begin
  Result := AgentTempRoot + 'project-guide.md';
  Lines := TStringList.Create;
  try
    Lines.Add('# RAD Studio IDE host (DelphiAgent)');
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
    Lines.Add('- Never write project sources or form files on disk while the IDE has the project open; ' +
      'change them through rad.apply_edits (code) and rad.form_apply (forms). Nothing is saved.');
    Lines.Add('- Read code with rad.read_buffer (line numbers for edits). Batch related edits into one ' +
      'rad.apply_edits call and form layout into one rad.form_apply call: each call is one approval.');
    if Profile.Tools.HasForms then
      Lines.Add('- Build UI in the designer with rad.form_apply, then write handlers with rad.apply_edits. ' +
        'Check classes with rad.list_components when unsure.');
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
    Lines.Add('- @path in the user message is the file content from disk; unsaved IDE buffers arrive as ' +
      'snapshot paths instead.');
    Lines.Add('- Subagents (task tool) cannot call rad.* tools and must never edit project files. Use them ' +
      'only for read-only research (agent scout: search, read, compare) in parallel; keep every IDE ' +
      'change in this session.');
    if PlanActive then
    begin
      Lines.Add('');
      Lines.Add('## PLAN MODE (active)');
      Lines.Add('- Do not change anything: no rad.* changes, no write/edit/bash on files. Investigate with ' +
        'read, grep, glob, rad.read_buffer, rad.project_info, rad.form_components.');
      Lines.Add('- Finish with exactly one rad.submit_plan call (title, slug in English, goal, context, ' +
        'steps, files, risks, verification) and stop. The user reviews it and chooses to proceed.');
      Lines.Add('- Write the plan in the user''s language.');
    end;
    Lines.Add('- Do not read skills about IDE file operations; these rules replace them.');
    WriteText(Result, Lines.Text);
  finally
    Lines.Free;
  end;
end;

end.
