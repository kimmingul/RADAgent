unit RADAgent.HostToolDefs;

{ Host-tool names and the set_host_tools frame, shaped by the active project: form tools only
  when the project has forms, wording for Delphi or C++Builder and for VCL or FMX. omp inlines
  these docs in its system prompt (tools.xdevInlineDevices), so they must stay short. No ToolsAPI. }

interface

const
  ToolCompile = 'rad.compile';
  ToolOpenBuffer = 'rad.open_buffer';
  ToolInsertAtCaret = 'rad.insert_at_caret';
  ToolProjectInfo = 'rad.project_info';
  ToolSetBuildConfig = 'rad.set_build_config';
  ToolNewModule = 'rad.new_module';
  ToolListComponents = 'rad.list_components';
  ToolDebugState = 'rad.debug_state';
  ToolDebugStack = 'rad.debug_stack';
  ToolDebugEvaluate = 'rad.debug_evaluate';
  ToolDebugBreakpoints = 'rad.debug_breakpoints';
  ToolFormComponents = 'rad.form_components';
  ToolFormProperties = 'rad.form_properties';
  ToolFormApply = 'rad.form_apply';
  ToolFormSetProperty = 'rad.form_set_property';
  ToolFormAddComponent = 'rad.form_add_component';
  ToolFormDeleteComponent = 'rad.form_delete_component';
  ToolFormRenameComponent = 'rad.form_rename_component';
  ToolFormSetEvent = 'rad.form_set_event';
  ToolFormScreenshot = 'rad.form_screenshot';
  ToolFormTextEdit = 'rad.form_text_edit';
  ToolDebugRun = 'rad.debug_run';
  ToolDebugStep = 'rad.debug_step';
  ToolDebugPause = 'rad.debug_pause';
  ToolDebugReset = 'rad.debug_reset';
  ToolDebugAddBreakpoint = 'rad.debug_add_breakpoint';
  ToolSubmitPlan = 'rad.submit_plan';

type
  TToolProfile = record
    { 'delphi' or 'cpp'. }
    Language: string;
    { 'VCL', 'FMX' or '' (no framework). }
    Framework: string;
    HasForms: Boolean;
    { RADAgent plan mode: read-only rad.* tools plus rad.submit_plan. }
    PlanMode: Boolean;
    { rad.form_text_edit is offered (project setting "auto"); False: designer only. }
    FormText: Boolean;
  end;

{ Delphi VCL with forms: every tool. }
function DefaultToolProfile: TToolProfile;
{ Tools that change the IDE (buffers, designer, project, debugger); refused in plan mode. }
function IsChangingTool(const Name: string): Boolean;
function BuildSetHostToolsFrame(const Id: string): string; overload;
function BuildSetHostToolsFrame(const Id: string; const Profile: TToolProfile): string; overload;

implementation

uses
  System.SysUtils, System.JSON;

function DefaultToolProfile: TToolProfile;
begin
  Result.Language := 'delphi';
  Result.Framework := 'VCL';
  Result.HasForms := True;
  Result.PlanMode := False;
  Result.FormText := True;
end;

function IsChangingTool(const Name: string): Boolean;
begin
  Result := (Name = ToolInsertAtCaret) or
    (Name = ToolSetBuildConfig) or (Name = ToolNewModule) or (Name = ToolFormApply) or
    (Name = ToolFormSetProperty) or (Name = ToolFormAddComponent) or (Name = ToolFormDeleteComponent) or
    (Name = ToolFormRenameComponent) or (Name = ToolFormSetEvent) or (Name = ToolFormTextEdit) or (Name = ToolDebugRun) or
    (Name = ToolDebugStep) or (Name = ToolDebugPause) or (Name = ToolDebugReset) or
    (Name = ToolDebugAddBreakpoint);
end;

{ PropList is comma separated. Every property is a string; the first one is required. }
function ToolDef(const Name, Description, PropList: string): TJSONObject;
var
  Params, Props, Prop: TJSONObject;
  Required: TJSONArray;
  Names: TArray<string>;
  Index: Integer;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', Name);
  Result.AddPair('description', Description);
  Params := TJSONObject.Create;
  Params.AddPair('type', 'object');
  Props := TJSONObject.Create;
  if PropList <> '' then
  begin
    Names := PropList.Split([',']);
    for Index := 0 to High(Names) do
    begin
      Prop := TJSONObject.Create;
      Prop.AddPair('type', 'string');
      Props.AddPair(Names[Index], Prop);
    end;
    Required := TJSONArray.Create;
    Required.Add(Names[0]);
    Params.AddPair('required', Required);
  end;
  Params.AddPair('properties', Props);
  Params.AddPair('additionalProperties', TJSONFalse.Create);
  Result.AddPair('parameters', Params);
end;

{ Tool with a hand-written JSON schema for array/object arguments. }
function SchemaDef(const Name, Description, Schema: string): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', Name);
  Result.AddPair('description', Description);
  Result.AddPair('parameters', TJSONObject.ParseJSONValue(Schema));
end;

const
  PlanSchema = '{"type":"object","required":["title","steps"],"properties":{"title":{"type":"string"},' +
    '"slug":{"type":"string"},"goal":{"type":"string"},"context":{"type":"string"},"steps":{"type":' +
    '"array","items":{"type":"string"}},"files":{"type":"array","items":{"type":"string"}},"risks":' +
    '{"type":"array","items":{"type":"string"}},"verification":{"type":"array","items":{"type":"string"}}}}';
  FormTextSchema = '{"type":"object","required":["edits"],"properties":{"edits":{"type":"array",' +
    '"items":{"type":"object","required":["path","old","new"],"properties":{"path":{"type":"string"},' +
    '"old":{"type":"string"},"new":{"type":"string"}}}}}}';
  FormApplySchema = '{"type":"object","required":["path"],"properties":{"path":{"type":"string"},' +
    '"delete":{"type":"array","items":{"type":"string"}},"components":{"type":"array","items":' +
    '{"type":"object","required":["name"],"properties":{"name":{"type":"string"},"class":' +
    '{"type":"string"},"parent":{"type":"string"},"properties":{"type":"object",' +
    '"additionalProperties":{"type":"string"}},"events":{"type":"object","additionalProperties":' +
    '{"type":"string"}}}}}}}';

procedure AddFormTools(Tools: TJSONArray; const P: TToolProfile);
var
  UnitKind, Layout, Example: string;
begin
  if P.Language = 'cpp' then
    UnitKind := '.cpp'
  else
    UnitKind := '.pas';
  if P.Framework = 'FMX' then
  begin
    Layout := 'FMX: place with Position.X/Position.Y, size with Width/Height, Align=Client/Top/' +
      'Bottom/Client, captions are Text (TLabel.Text, TButton.Text), containers TLayout/TRectangle; ' +
      'menus are TMainMenu/TMenuBar with TMenuItem children (parent = menu or parent item).';
    Example := '{"name":"Memo1","class":"TMemo","properties":{"Align":"Client"}}';
  end
  else
  begin
    Layout := 'VCL: place with Left/Top/Width/Height, Align=alClient/alTop/alBottom, captions are ' +
      'Caption (TLabel, TButton), Text for TEdit; menu items are TMenuItem components whose parent is ' +
      'the TMainMenu/TPopupMenu or the parent item; ShortCut takes text like Ctrl+N.';
    Example := '{"name":"Memo1","class":"TMemo","properties":{"Align":"alClient","ScrollBars":"ssBoth"}}';
  end;
  Tools.AddElement(ToolDef(ToolFormComponents,
    'List the root and every component (name, class, parent) of the form of the unit at absolute ' +
    'path (' + UnitKind + '). Read-only.', 'path'));
  Tools.AddElement(ToolDef(ToolFormProperties,
    'Published property values of one component (empty = the form). Read-only.', 'path,component'));
  Tools.AddElement(SchemaDef(ToolFormApply,
    'Preferred way to build or change a ' + P.Framework + ' form: one approval for the whole batch. ' +
    'delete removes components; each components[] item updates the named component or, with class, ' +
    'creates it under parent (empty = form). properties are applied in order as text; dotted names ' +
    'reach sub-objects (Font.Size, Margins.Left); a component name sets a reference (PopupMenu, Menu). ' +
    'events map event to handler method (stub added if missing). ' + Layout + ' Example item: ' +
    Example + '. Does not save.', FormApplySchema));
  Tools.AddElement(ToolDef(ToolFormSetProperty,
    'After approval set one property (dotted path allowed) of a component (empty = the form).',
    'path,component,property,value'));
  Tools.AddElement(ToolDef(ToolFormAddComponent,
    'After approval drop one component class under parent at left,top, optionally named.',
    'path,class,name,parent,left,top'));
  Tools.AddElement(ToolDef(ToolFormDeleteComponent,
    'After approval delete a component; the designer removes its field.', 'path,component'));
  Tools.AddElement(ToolDef(ToolFormRenameComponent,
    'After approval rename a component; fields and default handler names follow.',
    'path,component,newName'));
  Tools.AddElement(ToolDef(ToolFormSetEvent,
    'After approval connect event (OnClick) to handler; empty handler disconnects.',
    'path,component,event,handler'));
  Tools.AddElement(ToolDef(ToolFormScreenshot,
    'PNG image of the form as the designer shows it (absolute unit path). Use it after layout ' +
    'changes to check overlaps, alignment and clipped text. Read-only.', 'path'));
  if P.FormText then
    Tools.AddElement(SchemaDef(ToolFormTextEdit,
    'Bulk property changes as text in .dfm/.fmx files (many forms or many components at once): ' +
    'each edit replaces old text (must occur once) with new in the form file of path. Only property ' +
    'lines; no object/inherited/end lines (use rad.form_apply for components and events). New ' +
    'properties must exist. One approval for all edits; the IDE reloads the forms.', FormTextSchema));
end;

function BuildSetHostToolsFrame(const Id: string): string;
begin
  Result := BuildSetHostToolsFrame(Id, DefaultToolProfile);
end;

function BuildSetHostToolsFrame(const Id: string; const Profile: TToolProfile): string;
var
  Obj: TJSONObject;
  Tools: TJSONArray;
  Lang, Expr: string;
  Index: Integer;
begin
  if Profile.Language = 'cpp' then
  begin
    Lang := 'C++Builder';
    Expr := 'C++';
  end
  else
  begin
    Lang := 'Delphi';
    Expr := 'Delphi';
  end;
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('id', Id);
    Obj.AddPair('type', 'set_host_tools');
    Tools := TJSONArray.Create;
    Tools.AddElement(ToolDef(ToolProjectInfo,
      'Active ' + Lang + ' project: file, framework, configuration, platform, available ' +
      'configurations/platforms, forms and units. Read-only.', ''));
    Tools.AddElement(ToolDef(ToolCompile,
      'Build the active ' + Lang + ' project in the IDE and return compiler errors (file, line, ' +
      'message). Call after edits.', ''));
    Tools.AddElement(ToolDef(ToolSetBuildConfig,
      'After approval switch the active build configuration (e.g. Debug, Release) and/or ' +
      'target platform (e.g. Win32, Win64).', 'config,platform'));
    Tools.AddElement(ToolDef(ToolNewModule,
      'After approval add a new module to the project. kind: form, frame, datamodule or unit; ' +
      'name: optional form name, or unit name (Delphi units may be dotted, e.g. App.Csv); a named unit ' +
      'becomes <name>.pas (.cpp) in the project folder. Returns the new file. Form tools appear after the first form.',
      'kind,name'));
    Tools.AddElement(ToolDef(ToolListComponents,
      'Installed component classes on the IDE palette with their package; filter is a ' +
      'case-insensitive substring. Use it to pick valid classes for forms. Read-only.', 'filter'));
    Tools.AddElement(ToolDef(ToolOpenBuffer, 'Open a file in the IDE editor.', 'file'));
    Tools.AddElement(ToolDef(ToolInsertAtCaret,
      'After approval insert text at the editor caret (the file is then saved).', 'text'));
    if Profile.HasForms then
      AddFormTools(Tools, Profile);
    Tools.AddElement(ToolDef(ToolDebugState,
      'Debugger process state and the stopped source location. Read-only.', ''));
    Tools.AddElement(ToolDef(ToolDebugStack,
      'Call stack of the current thread while stopped. Read-only.', ''));
    Tools.AddElement(ToolDef(ToolDebugEvaluate,
      'Evaluate a ' + Expr + ' expression in the stopped debuggee without side effects.', 'expression'));
    Tools.AddElement(ToolDef(ToolDebugBreakpoints, 'List source breakpoints. Read-only.', ''));
    Tools.AddElement(ToolDef(ToolDebugRun,
      'After approval run the project under the debugger (F9) or continue; returns the state.', ''));
    Tools.AddElement(ToolDef(ToolDebugStep,
      'After approval step the stopped debuggee. mode: over, into or return.', 'mode'));
    Tools.AddElement(ToolDef(ToolDebugPause, 'After approval pause the running debuggee.', ''));
    Tools.AddElement(ToolDef(ToolDebugReset, 'After approval terminate the debuggee.', ''));
    Tools.AddElement(ToolDef(ToolDebugAddBreakpoint,
      'After approval add a source breakpoint at file (absolute path) and 1-based line.', 'file,line'));
    if Profile.PlanMode then
    begin
      for Index := Tools.Count - 1 downto 0 do
        if IsChangingTool(TJSONObject(Tools.Items[Index]).GetValue<string>('name')) then
          Tools.Remove(Index).Free;
      Tools.AddElement(SchemaDef(ToolSubmitPlan,
        'Plan mode only: submit the finished plan. RAD Agent writes it to docs\plans\<date>-<slug>.md ' +
        'with fixed sections (goal, context, numbered steps, files, risks, verification), adds it to ' +
        'the project and asks the user to proceed. Call once, then stop and wait.', PlanSchema));
    end;
    Obj.AddPair('tools', Tools);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

end.
