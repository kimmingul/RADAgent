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
    Obj.AddPair('tools', Tools);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

end.
