unit DelphiAgent.FormTools;

{ rad.form_* dispatch. Reads (component list, published properties) live here; approved
  changes live in DelphiAgent.FormEdits. Never saves. Main thread only. }

interface

uses
  DelphiAgent.Approval, DelphiAgent.FormEdits;

function IsFormTool(const ToolName: string): Boolean;
procedure ExecuteFormTool(const ToolName: string; const Args: TFormToolArgs;
  const ArgumentsJson: string; const Approval: IAgentApproval; out ResultText: string;
  out IsError: Boolean);

implementation

uses
  System.SysUtils, System.Classes, System.JSON, System.TypInfo, System.Rtti, Vcl.Controls, ToolsAPI,
  DelphiAgent.HostToolDefs, DelphiAgent.FormDesigner, DelphiAgent.FormBatch, DelphiAgent.IdeContext;

function IsFormTool(const ToolName: string): Boolean;
begin
  Result := (ToolName = ToolFormComponents) or (ToolName = ToolFormProperties) or
    (ToolName = ToolFormApply) or
    (ToolName = ToolFormSetProperty) or (ToolName = ToolFormAddComponent) or
    (ToolName = ToolFormDeleteComponent) or (ToolName = ToolFormRenameComponent) or
    (ToolName = ToolFormSetEvent);
end;

{ VCL TControl.Parent, or FMX TFmxObject.Parent through RTTI (no FMX package needed). }
function ParentName(Component: TComponent): string;
var
  Context: TRttiContext;
  Prop: TRttiProperty;
  Value: TObject;
begin
  Result := '';
  if Component is TControl then
  begin
    if TControl(Component).Parent <> nil then
      Result := TControl(Component).Parent.Name;
    Exit;
  end;
  Prop := Context.GetType(Component.ClassType).GetProperty('Parent');
  if (Prop = nil) or not Prop.IsReadable or (Prop.PropertyType.TypeKind <> tkClass) then
    Exit;
  Value := Prop.GetValue(Component).AsObject;
  if Value is TComponent then
    Result := TComponent(Value).Name;
end;

function ComponentsJson(const Editor: IOTAFormEditor): string;
var
  Root: TComponent;
  Items: TJSONArray;
  Obj, Item: TJSONObject;
  Index: Integer;
begin
  Root := RootOf(Editor);
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('root', Root.Name);
    Obj.AddPair('class', Root.ClassName);
    Items := TJSONArray.Create;
    for Index := 0 to Root.ComponentCount - 1 do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('name', Root.Components[Index].Name);
      Item.AddPair('class', Root.Components[Index].ClassName);
      Item.AddPair('parent', ParentName(Root.Components[Index]));
      Items.AddElement(Item);
    end;
    Obj.AddPair('components', Items);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function PropertiesJson(const Editor: IOTAFormEditor; Instance: TComponent): string;
var
  List: PPropList;
  Count, Index: Integer;
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Count := GetPropList(Instance, List);
    try
      for Index := 0 to Count - 1 do
        Obj.AddPair(string(List[Index].Name), PropText(Editor, Instance, List[Index]));
    finally
      FreeMem(List);
    end;
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function NameJson(const Name: string): string;
var
  Reply: TJSONObject;
begin
  Reply := TJSONObject.Create;
  try
    Reply.AddPair('ok', TJSONTrue.Create);
    Reply.AddPair('name', Name);
    Result := Reply.ToJSON;
  finally
    Reply.Free;
  end;
end;

{ Cancel is not an error: the model should report it, not retry blindly. }
procedure Finish(Ok: Boolean; const OkText, Problem: string; out ResultText: string;
  out IsError: Boolean);
begin
  if Ok then
    ResultText := OkText
  else
    ResultText := Problem;
  IsError := not Ok and (Problem <> SEditCancelled);
end;

procedure RunFormTool(const ToolName: string; const Args: TFormToolArgs; const ArgumentsJson: string;
  const Approval: IAgentApproval; out ResultText: string; out IsError: Boolean);
var
  Editor: IOTAFormEditor;
  Instance: TComponent;
  Problem, CreatedName: string;
  Ok: Boolean;
begin
  IsError := True;
  if ToolName = ToolFormApply then
  begin
    ApplyFormBatch(ArgumentsJson, Approval, ResultText, IsError);
    Exit;
  end;
  Editor := FindFormEditor(Args.Path, Problem);
  if (Editor = nil) or (RootOf(Editor) = nil) then
  begin
    if Problem = '' then
      Problem := '폼 디자이너를 열지 못했습니다.';
    ResultText := Problem;
    Exit;
  end;
  if ToolName = ToolFormComponents then
  begin
    ResultText := ComponentsJson(Editor);
    IsError := False;
  end
  else if ToolName = ToolFormProperties then
  begin
    Instance := FindNative(Editor, Args.Component);
    if Instance = nil then
      ResultText := '컴포넌트를 찾지 못했습니다: ' + Args.Component
    else
    begin
      ResultText := PropertiesJson(Editor, Instance);
      IsError := False;
    end;
  end
  else if ToolName = ToolFormAddComponent then
  begin
    Ok := AddComponent(Editor, Args, Approval, CreatedName, Problem);
    Finish(Ok, NameJson(CreatedName), Problem, ResultText, IsError);
  end
  else
  begin
    if ToolName = ToolFormSetProperty then
      Ok := SetProperty(Editor, Args, Approval, Problem)
    else if ToolName = ToolFormDeleteComponent then
      Ok := DeleteComponent(Editor, Args, Approval, Problem)
    else if ToolName = ToolFormRenameComponent then
      Ok := RenameComponent(Editor, Args, Approval, Problem)
    else
      Ok := SetEvent(Editor, Args, Approval, Problem);
    Finish(Ok, '{"ok":true}', Problem, ResultText, IsError);
  end;
end;

procedure ExecuteFormTool(const ToolName: string; const Args: TFormToolArgs;
  const ArgumentsJson: string; const Approval: IAgentApproval; out ResultText: string;
  out IsError: Boolean);
begin
  RunFormTool(ToolName, Args, ArgumentsJson, Approval, ResultText, IsError);
end;

end.
