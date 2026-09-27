unit RADAgent.DesignInit;

{ The project's design system: rad.design_styles lists the installed styles and presets,
  rad.design_init (and the /design command) writes <project>\DESIGN.md for a chosen style and
  gives the project that style. Main thread only. }

interface

uses
  RADAgent.Approval, RADAgent.DesignCatalog;

{ <project folder>\DESIGN.md, '' without a project. }
function DesignFile: string;
{ 'VCL', 'FMX' or '' for the active project. }
function ProjectFramework: string;
{ rad.design_styles result. }
function DesignStylesJson: string;
{ The counterpart of Style in the other theme, when Style is light and the pair is installed. }
function DarkOf(const Style: TDesignStyle): TDesignStyle;
{ Writes DESIGN.md for Style with PresetId ('' = the style's preset) and, when ApplyStyle, links
  the style into the project. Approval is asked for the file and for the project change. }
function InitDesign(const Style: TDesignStyle; const PresetId: string; ApplyStyle: Boolean;
  const Approval: IAgentApproval; out ResultText: string): Boolean;
{ rad.design_init: StyleArg is a file or style name of the project's framework. }
function InitDesignTool(const StyleArg, PresetArg, ApplyArg: string; const Approval: IAgentApproval;
  out ResultText: string): Boolean;

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, ToolsAPI, RADAgent.IdeContext, RADAgent.DesignDoc,
  RADAgent.DesignApply, RADAgent.DesignTokens, RADAgent.Lang, RADAgent.IdeFiles;

function DesignFile: string;
begin
  Result := '';
  if ActiveProjectDir <> '' then
    Result := IncludeTrailingPathDelimiter(ActiveProjectDir) + 'DESIGN.md';
end;

function ProjectFramework: string;
var
  Project: IOTAProject;
begin
  Result := '';
  Project := CurrentProject;
  if Project = nil then
    Exit;
  if SameText(Project.FrameworkType, sFrameworkTypeVCL) or SameText(Project.FrameworkType, sFrameworkTypeFMX) then
    Result := UpperCase(Project.FrameworkType);
end;

function DarkOf(const Style: TDesignStyle): TDesignStyle;
begin
  Result := Default(TDesignStyle);
  if (Style.Pair <> '') and not SameText(Style.Theme, 'dark') and
    FindStyle(Style.Framework, Style.Pair, Result) and not SameText(Result.Theme, 'dark') then
    Result := Default(TDesignStyle);
end;

function StyleJson(const Style: TDesignStyle): TJSONObject;
var
  Provenance: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('file', Style.FileName);
  Result.AddPair('name', Style.Name);
  Result.AddPair('theme', Style.Theme);
  if Style.Pair <> '' then
    Result.AddPair('pair', Style.Pair);
  if Length(Style.Platforms) > 0 then
    Result.AddPair('platforms', string.Join(', ', Style.Platforms));
  if not Style.Loadable then
    Result.AddPair('loadable', TJSONFalse.Create);
  Provenance := TJSONObject.Create;
  Provenance.AddPair('system', Style.System);
  Provenance.AddPair('basis', Style.Basis);
  Result.AddPair('provenance', Provenance);
  Result.AddPair('preset', Style.Preset);
  Result.AddPair('presetBasis', Style.PresetBasis);
end;

function DesignStylesJson: string;
var
  Obj, Current, Preset: TJSONObject;
  Styles, Presets: TJSONArray;
  Style: TDesignStyle;
  Framework, Id: string;
  Tokens: TFrontMatter;
begin
  Framework := ProjectFramework;
  if Framework = '' then
    Exit('{"ok":false,"error":"The active project is not a VCL or FMX application."}');
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('framework', Framework);
    if FileExists(DesignFile) then
    begin
      Tokens := ReadFrontMatter(TFile.ReadAllText(DesignFile, TEncoding.UTF8));
      try
        Current := TJSONObject.Create;
        Current.AddPair('file', DesignFile);
        if Tokens.ContainsKey('radstudio.styleFile') then
          Current.AddPair('style', Tokens['radstudio.styleFile']);
        if Tokens.ContainsKey('radstudio.preset') then
          Current.AddPair('preset', Tokens['radstudio.preset']);
        Obj.AddPair('designFile', Current);
      finally
        Tokens.Free;
      end;
    end;
    Styles := TJSONArray.Create;
    Obj.AddPair('styles', Styles);
    for Style in InstalledStyles(Framework) do
      Styles.AddElement(StyleJson(Style));
    Presets := TJSONArray.Create;
    Obj.AddPair('presets', Presets);
    for Id in PresetIds do
    begin
      Preset := TJSONObject.Create;
      Preset.AddPair('id', Id);
      Preset.AddPair('title', PresetTitle(Id));
      Presets.AddElement(Preset);
    end;
    Obj.AddPair('note', 'provenance.basis: vendor-statement or file-content are verified; name is only ' +
      'suggested by the file name; none is an Embarcadero skin. presetBasis match: the preset is the ' +
      'style''s own design system; policy: a chosen supplement.');
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function ProjectName: string;
var
  Project: IOTAProject;
begin
  Result := 'Project';
  Project := CurrentProject;
  if Project <> nil then
    Result := ChangeFileExt(ExtractFileName(Project.FileName), '');
end;

function InitDesign(const Style: TDesignStyle; const PresetId: string; ApplyStyle: Boolean;
  const Approval: IAgentApproval; out ResultText: string): Boolean;
var
  Preset, Path, Before, Doc, Done, Problem: string;
  Dark: TDesignStyle;
  Reply: TJSONObject;
begin
  Result := False;
  Path := DesignFile;
  if Path = '' then
  begin
    ResultText := '{"ok":false,"error":"No active project."}';
    Exit;
  end;
  Preset := PresetId;
  if Preset = '' then
    Preset := Style.Preset;
  if PresetText(Preset) = '' then
  begin
    ResultText := Format('{"ok":false,"error":"Unknown preset %s; use one of rad.design_styles presets."}',
      [Preset]);
    Exit;
  end;
  Dark := DarkOf(Style);
  Doc := ComposeDesignDoc(ProjectName, Style, Dark, Preset);
  Before := '';
  if FileExists(Path) then
    Before := TFile.ReadAllText(Path, TEncoding.UTF8);
  if (Approval = nil) or not Approval.ApproveChange(Path, Before, Doc) then
  begin
    ResultText := SEditCancelled;
    Exit(True);
  end;
  TFile.WriteAllBytes(Path, TEncoding.UTF8.GetBytes(Doc));
  Reply := TJSONObject.Create;
  try
    Reply.AddPair('ok', TJSONTrue.Create);
    Reply.AddPair('designFile', Path);
    Reply.AddPair('style', Style.FileName);
    if Dark.FileName <> '' then
      Reply.AddPair('darkStyle', Dark.FileName);
    Reply.AddPair('preset', Preset);
    Result := True;
    if ApplyStyle then
    begin
      if not Approval.ApproveChange(ActiveProjectFile, '',
        TrF('designinit.applyStyle', [Style.Name, Style.FileName])) then
        Reply.AddPair('styleApplied', 'no: the user declined; the project keeps its style.')
      else if ApplyProjectStyle(Style, Dark, Done, Problem) then
      begin
        Reply.AddPair('styleApplied', Done);
        { The program source, project options and form are on disk at once, as the design says. }
        if not SaveProjectModules(ExcludeTrailingPathDelimiter(ActiveProjectDir), Problem) then
          Reply.AddPair('saveError', Problem);
      end
      else
      begin
        Reply.AddPair('styleError', Problem);
        Result := False;
      end;
    end;
    Reply.AddPair('next', 'Read DESIGN.md and skill://radstudio-ui-design before changing UI; check ' +
      'forms with rad.design_lint.');
    ResultText := Reply.ToJSON;
  finally
    Reply.Free;
  end;
end;

function InitDesignTool(const StyleArg, PresetArg, ApplyArg: string; const Approval: IAgentApproval;
  out ResultText: string): Boolean;
var
  Framework: string;
  Style: TDesignStyle;
begin
  Result := False;
  Framework := ProjectFramework;
  if Framework = '' then
    ResultText := '{"ok":false,"error":"The active project is not a VCL or FMX application."}'
  else if not FindStyle(Framework, StyleArg, Style) then
    ResultText := Format('{"ok":false,"error":"No installed %s style %s; pick one from ' +
      'rad.design_styles."}', [Framework, StringReplace(StyleArg, '"', '''', [rfReplaceAll])])
  else
    Result := InitDesign(Style, Trim(PresetArg), not SameText(Trim(ApplyArg), 'false'), Approval,
      ResultText);
end;

end.
