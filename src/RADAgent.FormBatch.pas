unit RADAgent.FormBatch;

{ rad.form_apply: many designer changes (delete, create, properties, events) shown as one list
  and approved once, then applied in order through RADAgent.FormEdits. Never saves.
  Main thread only. }

interface

uses
  RADAgent.Approval;

procedure ApplyFormBatch(const ArgumentsJson: string; const Approval: IAgentApproval;
  out ResultText: string; out IsError: Boolean);

implementation

uses
  System.SysUtils, System.Classes, System.JSON, ToolsAPI, RADAgent.FormDesigner,
  RADAgent.FormEdits, RADAgent.Lang;

function Pairs(Item: TJSONObject; const Name: string): TJSONObject;
begin
  Result := nil;
  if (Item <> nil) and (Item.GetValue(Name) is TJSONObject) then
    Result := TJSONObject(Item.GetValue(Name));
end;

function Text(Value: TJSONValue): string;
begin
  if Value is TJSONString then
    Result := TJSONString(Value).Value
  else if Value <> nil then
    Result := Value.Value
  else
    Result := '';
end;

{ The change list the user approves. }
function Describe(const Editor: IOTAFormEditor; Deletes, Components: TJSONArray): string;
var
  Lines: TStringList;
  Value: TJSONValue;
  Item, Props: TJSONObject;
  Pair: TJSONPair;
  Head: string;
begin
  Lines := TStringList.Create;
  try
    if Deletes <> nil then
      for Value in Deletes do
        Lines.Add(TrF('formbatch.deleteItem', [Text(Value)]));
    if Components <> nil then
      for Value in Components do
        if Value is TJSONObject then
        begin
          Item := TJSONObject(Value);
          if FindNative(Editor, Item.GetValue<string>('name', '')) <> nil then
            Head := TrF('formbatch.modifyItem', [Item.GetValue<string>('name', '')])
          else
            Head := TrF('formbatch.addItem', [Item.GetValue<string>('name', ''),
              Item.GetValue<string>('class', ''), Item.GetValue<string>('parent', Tr('formbatch.formParent'))]);
          Lines.Add(Head);
          Props := Pairs(Item, 'properties');
          if Props <> nil then
            for Pair in Props do
              Lines.Add('    ' + Pair.JsonString.Value + ' = ' + Text(Pair.JsonValue));
          Props := Pairs(Item, 'events');
          if Props <> nil then
            for Pair in Props do
              Lines.Add('    ' + Pair.JsonString.Value + ' -> ' + Text(Pair.JsonValue));
        end;
    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

procedure ApplyComponent(const Editor: IOTAFormEditor; const Path: string; Item: TJSONObject;
  const Approval: IAgentApproval; Errors, Created: TJSONArray);
var
  Args: TFormToolArgs;
  Props: TJSONObject;
  Pair: TJSONPair;
  Problem, NewName: string;
begin
  Args := Default(TFormToolArgs);
  Args.Path := Path;
  Args.Name := Item.GetValue<string>('name', '');
  if (Args.Name <> '') and (FindNative(Editor, Args.Name) = nil) then
  begin
    Args.ClassName := Item.GetValue<string>('class', '');
    Args.Parent := Item.GetValue<string>('parent', '');
    Props := Pairs(Item, 'properties');
    if Props <> nil then
    begin
      Args.Left := StrToIntDef(Text(Props.GetValue('Left')), StrToIntDef(Text(Props.GetValue('Position.X')), 0));
      Args.Top := StrToIntDef(Text(Props.GetValue('Top')), StrToIntDef(Text(Props.GetValue('Position.Y')), 0));
    end;
    if not AddComponent(Editor, Args, Approval, NewName, Problem) then
    begin
      Errors.Add(Args.Name + ': ' + Problem);
      Exit;
    end;
    Created.Add(NewName);
    Args.Name := NewName;
  end;
  Args.Component := Args.Name;
  Props := Pairs(Item, 'properties');
  if Props <> nil then
    for Pair in Props do
    begin
      Args.PropName := Pair.JsonString.Value;
      Args.Value := Text(Pair.JsonValue);
      if not SetProperty(Editor, Args, Approval, Problem) then
        Errors.Add(Args.Name + '.' + Args.PropName + ': ' + Problem);
    end;
  Props := Pairs(Item, 'events');
  if Props <> nil then
    for Pair in Props do
    begin
      Args.Event := Pair.JsonString.Value;
      Args.Handler := Text(Pair.JsonValue);
      if not SetEvent(Editor, Args, Approval, Problem) then
        Errors.Add(Args.Name + '.' + Args.Event + ': ' + Problem);
    end;
end;

procedure ApplyFormBatch(const ArgumentsJson: string; const Approval: IAgentApproval;
  out ResultText: string; out IsError: Boolean);
var
  Root, Reply: TJSONObject;
  Deletes, Components, Errors, Created: TJSONArray;
  Value: TJSONValue;
  Editor: IOTAFormEditor;
  Path, Problem: string;
  Args: TFormToolArgs;
  Batch: IAgentApproval;
begin
  IsError := True;
  Value := TJSONObject.ParseJSONValue(ArgumentsJson);
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    ResultText := 'Argument is not a JSON object.';
    Exit;
  end;
  Root := TJSONObject(Value);
  Reply := TJSONObject.Create;
  try
    Path := Root.GetValue<string>('path', '');
    Editor := FindFormEditor(Path, Problem);
    if (Editor = nil) or (RootOf(Editor) = nil) then
    begin
      ResultText := Problem;
      Exit;
    end;
    Deletes := nil;
    Components := nil;
    if Root.GetValue('delete') is TJSONArray then
      Deletes := TJSONArray(Root.GetValue('delete'));
    if Root.GetValue('components') is TJSONArray then
      Components := TJSONArray(Root.GetValue('components'));
    if (Approval = nil) or not Approval.ApproveChange(Path, '', Describe(Editor, Deletes, Components)) then
    begin
      ResultText := SEditCancelled;
      IsError := False;
      Exit;
    end;
    Batch := PreApproved(Approval);
    Errors := TJSONArray.Create;
    Created := TJSONArray.Create;
    Reply.AddPair('errors', Errors);
    Reply.AddPair('created', Created);
    if Deletes <> nil then
      for Value in Deletes do
      begin
        Args := Default(TFormToolArgs);
        Args.Path := Path;
        Args.Component := Text(Value);
        if not DeleteComponent(Editor, Args, Batch, Problem) then
          Errors.Add(Args.Component + ': ' + Problem);
      end;
    if Components <> nil then
      for Value in Components do
        if Value is TJSONObject then
          ApplyComponent(Editor, Path, TJSONObject(Value), Batch, Errors, Created);
    Reply.AddPair('ok', TJSONBool.Create(Errors.Count = 0));
    ResultText := Reply.ToJSON;
    IsError := False;
  finally
    Reply.Free;
    Root.Free;
  end;
end;

end.
