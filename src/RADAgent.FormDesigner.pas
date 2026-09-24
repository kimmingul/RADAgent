unit RADAgent.FormDesigner;

{ Access to one unit's form designer through public ToolsAPI: find the editor, map names to
  native components, render property values, and notify the designer. Main thread only. }

interface

uses
  System.Classes, System.TypInfo, ToolsAPI, DesignIntf;

const
  { Kinds that round-trip through a single text value. }
  TextKinds = [tkInteger, tkChar, tkEnumeration, tkFloat, tkString, tkSet, tkWChar,
    tkLString, tkWString, tkInt64, tkUString];

function FindFormEditor(const Path: string; out Problem: string): IOTAFormEditor;
function NativeOf(const Component: IOTAComponent): TComponent;
function RootOf(const Editor: IOTAFormEditor): TComponent;
{ Empty name or the root's own name means the root. }
function FindNative(const Editor: IOTAFormEditor; const Name: string): TComponent;
{ IOTAComponent for a native component of this form (root included). }
function FindOta(const Editor: IOTAFormEditor; Native: TComponent): IOTAComponent;
function DesignerOf(const Editor: IOTAFormEditor): IDesigner;
procedure MarkDesignerModified(const Editor: IOTAFormEditor);
function PropText(const Editor: IOTAFormEditor; Instance: TComponent; Prop: PPropInfo): string;

implementation

uses
  System.SysUtils, System.Variants;

{ Opens the module when needed; the designer must exist for the unit's form. }
function FindFormEditor(const Path: string; out Problem: string): IOTAFormEditor;
var
  Modules: IOTAModuleServices;
  Module: IOTAModule;
  Index: Integer;
begin
  Result := nil;
  Problem := '';
  if Path = '' then
  begin
    Problem := 'Path cannot be empty.';
    Exit;
  end;
  Modules := BorlandIDEServices as IOTAModuleServices;
  Module := Modules.FindModule(Path);
  if Module = nil then
    Module := Modules.OpenModule(Path);
  if Module = nil then
  begin
    Problem := 'Failed to open module.';
    Exit;
  end;
  for Index := 0 to Module.ModuleFileCount - 1 do
    if Supports(Module.ModuleFileEditors[Index], IOTAFormEditor, Result) then
      Exit;
  Result := nil;
  Problem := 'This unit has no form.';
end;

function NativeOf(const Component: IOTAComponent): TComponent;
var
  Native: INTAComponent;
begin
  Result := nil;
  if Supports(Component, INTAComponent, Native) then
    Result := Native.GetComponent;
end;

function RootOf(const Editor: IOTAFormEditor): TComponent;
begin
  Result := NativeOf(Editor.GetRootComponent);
end;

function FindNative(const Editor: IOTAFormEditor; const Name: string): TComponent;
var
  Root: TComponent;
begin
  Root := RootOf(Editor);
  if (Root = nil) or (Name = '') or SameText(Name, Root.Name) then
    Exit(Root);
  Result := Root.FindComponent(Name);
end;

function FindOta(const Editor: IOTAFormEditor; Native: TComponent): IOTAComponent;
begin
  if Native = RootOf(Editor) then
    Result := Editor.GetRootComponent
  else
    Result := Editor.FindComponent(Native.Name);
end;

function DesignerOf(const Editor: IOTAFormEditor): IDesigner;
var
  Form: INTAFormEditor;
begin
  Result := nil;
  if Supports(Editor, INTAFormEditor, Form) then
    Result := Form.FormDesigner;
end;

procedure MarkDesignerModified(const Editor: IOTAFormEditor);
var
  Designer: IDesigner;
begin
  Designer := DesignerOf(Editor);
  if Designer <> nil then
    Designer.Modified;
end;

function PropText(const Editor: IOTAFormEditor; Instance: TComponent; Prop: PPropInfo): string;
var
  Value: TObject;
  Method: TMethod;
  Designer: IDesigner;
begin
  Result := '';
  case Prop.PropType^.Kind of
    tkClass:
      begin
        Value := GetObjectProp(Instance, Prop);
        if Value is TComponent then
          Result := TComponent(Value).Name
        else if Value <> nil then
          Result := '(' + Value.ClassName + ')';
      end;
    tkMethod:
      begin
        Method := GetMethodProp(Instance, Prop);
        if Method.Code = nil then
          Exit;
        Designer := DesignerOf(Editor);
        if Designer <> nil then
          Result := Designer.GetMethodName(Method);
        if Result = '' then
          Result := '(handler)';
      end;
  else
    if Prop.PropType^.Kind in TextKinds then
      Result := VarToStr(GetPropValue(Instance, Prop, True));
  end;
end;

end.
