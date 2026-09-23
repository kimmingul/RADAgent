unit DelphiAgent.HostToolDefs;

{ Host-tool names and the set_host_tools frame. No ToolsAPI. }

interface

const
  ToolCompile = 'rad.compile';
  ToolOpenBuffer = 'rad.open_buffer';
  ToolInsertAtCaret = 'rad.insert_at_caret';
  ToolListDirty = 'rad.list_dirty';
  ToolReadBuffer = 'rad.read_buffer';
  ToolApplyEdit = 'rad.apply_edit';
  ToolDebugState = 'rad.debug_state';
  ToolDebugStack = 'rad.debug_stack';
  ToolDebugEvaluate = 'rad.debug_evaluate';
  ToolDebugBreakpoints = 'rad.debug_breakpoints';
  ToolFormComponents = 'rad.form_components';
  ToolFormProperties = 'rad.form_properties';
  ToolFormSetProperty = 'rad.form_set_property';
  ToolFormAddComponent = 'rad.form_add_component';
  ToolFormDeleteComponent = 'rad.form_delete_component';
  ToolFormRenameComponent = 'rad.form_rename_component';
  ToolFormSetEvent = 'rad.form_set_event';
  ToolDebugRun = 'rad.debug_run';
  ToolDebugStep = 'rad.debug_step';
  ToolDebugPause = 'rad.debug_pause';
  ToolDebugReset = 'rad.debug_reset';
  ToolDebugAddBreakpoint = 'rad.debug_add_breakpoint';

function BuildSetHostToolsFrame(const Id: string): string;

implementation

uses
  System.SysUtils, System.JSON;

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

function BuildSetHostToolsFrame(const Id: string): string;
var
  Obj: TJSONObject;
  Tools: TJSONArray;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('id', Id);
    Obj.AddPair('type', 'set_host_tools');
    Tools := TJSONArray.Create;
    Tools.AddElement(ToolDef(ToolCompile,
      'Build the active Delphi project and return compiler errors.', ''));
    Tools.AddElement(ToolDef(ToolOpenBuffer,
      'Open a file in the IDE editor.', 'file'));
    Tools.AddElement(ToolDef(ToolInsertAtCaret,
      'Insert text at the editor caret after the user approves.', 'text'));
    Tools.AddElement(ToolDef(ToolListDirty,
      'List open IDE buffers that differ from disk. Does not save.', ''));
    Tools.AddElement(ToolDef(ToolReadBuffer,
      'Return unsaved IDE editor text for an absolute path. Does not save.', 'path'));
    Tools.AddElement(ToolDef(ToolApplyEdit,
      'After the user confirms, replace lines startLine..endLine (1-based, inclusive) of the ' +
      'open IDE buffer at absolute path with newText, or the whole buffer with content. ' +
      'Refuses if the buffer changed since the prompt snapshot. Does not save.',
      'path,content,startLine,endLine,newText'));
    Tools.AddElement(ToolDef(ToolDebugState,
      'Report the IDE debugger process state and the stopped source location. Read-only.', ''));
    Tools.AddElement(ToolDef(ToolDebugStack,
      'Return the call stack of the current debuggee thread while stopped. Read-only.', ''));
    Tools.AddElement(ToolDef(ToolDebugEvaluate,
      'Evaluate a Delphi expression in the stopped debuggee without side effects.', 'expression'));
    Tools.AddElement(ToolDef(ToolDebugBreakpoints,
      'List IDE source breakpoints. Read-only.', ''));
    Tools.AddElement(ToolDef(ToolFormComponents,
      'List the root and every component of the form designed by the unit at absolute path ' +
      '(.pas). Returns name, class and parent control. Read-only.', 'path'));
    Tools.AddElement(ToolDef(ToolFormProperties,
      'Return published property values of one component (empty component = the form) of ' +
      'the form at absolute path. Read-only.', 'path,component'));
    Tools.AddElement(ToolDef(ToolFormSetProperty,
      'After the user confirms, set one text, number, enum or set property of a component ' +
      '(empty component = the form) in the open form designer. Does not save.',
      'path,component,property,value'));
    Tools.AddElement(ToolDef(ToolFormAddComponent,
      'After the user confirms, drop a registered component class (e.g. TButton) on the form ' +
      'designer under parent (empty = the form) at left,top, optionally naming it. Does not save.',
      'path,class,name,parent,left,top'));
    Tools.AddElement(ToolDef(ToolFormDeleteComponent,
      'After the user confirms, delete a component (not the form) from the form designer. ' +
      'The designer removes its field. Does not save.', 'path,component'));
    Tools.AddElement(ToolDef(ToolFormRenameComponent,
      'After the user confirms, rename a component (not the form) to newName. The designer ' +
      'renames its field and default-named handlers (Button1Click -> NewNameClick). Does not save.',
      'path,component,newName'));
    Tools.AddElement(ToolDef(ToolFormSetEvent,
      'After the user confirms, connect event (e.g. OnClick) of a component (empty = the form) ' +
      'to handler. An existing method is reused, otherwise the designer adds an empty stub. ' +
      'Empty handler disconnects. Does not save.', 'path,component,event,handler'));
    Tools.AddElement(ToolDef(ToolDebugRun,
      'After the user confirms, build and start the active project under the debugger (F9), or ' +
      'continue a stopped debuggee. Waits up to 5 s and returns the debugger state.', ''));
    Tools.AddElement(ToolDef(ToolDebugStep,
      'After the user confirms, step the stopped debuggee. mode: over (F8), into (F7) or return ' +
      '(run until the function returns). Returns the new debugger state.', 'mode'));
    Tools.AddElement(ToolDef(ToolDebugPause,
      'After the user confirms, pause the running debuggee. Returns the debugger state.', ''));
    Tools.AddElement(ToolDef(ToolDebugReset,
      'After the user confirms, terminate the debuggee (Program Reset). Returns the state.', ''));
    Tools.AddElement(ToolDef(ToolDebugAddBreakpoint,
      'After the user confirms, add a source breakpoint at file (absolute path) and 1-based line.',
      'file,line'));
    Obj.AddPair('tools', Tools);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

end.
