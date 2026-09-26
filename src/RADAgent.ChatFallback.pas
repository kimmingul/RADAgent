unit RADAgent.ChatFallback;

{ Plain-text transcript used only when WebView2 cannot start. Renders the same page messages. }

interface

uses
  Vcl.Controls, Vcl.StdCtrls;

function CreateFallback(Parent: TWinControl; const Problem: string): TMemo;
procedure AppendFallback(Memo: TMemo; const Json: string);

implementation

uses
  System.SysUtils, System.StrUtils, System.JSON, RADAgent.Lang;

procedure Append(Memo: TMemo; const Text: string);
begin
  Memo.SelStart := Memo.GetTextLen;
  Memo.SelLength := 0;
  Memo.SelText := AdjustLineBreaks(Text, tlbsCRLF);
end;

function CreateFallback(Parent: TWinControl; const Problem: string): TMemo;
begin
  Result := TMemo.Create(Parent);
  Result.Parent := Parent;
  Result.Align := alClient;
  Result.ReadOnly := True;
  Result.ScrollBars := ssVertical;
  Result.Font.Name := 'Malgun Gothic';
  Result.Font.Size := 10;
  Append(Result, TrF('chatfallback.banner', [Problem]) + sLineBreak);
end;

{ A finished side question: question and answer (or why there is none). }
procedure AppendBtw(Memo: TMemo; Obj: TJSONObject);
var
  Turn: string;
begin
  Turn := 'topic.turns[' + Obj.GetValue<string>('turn', '0') + '].';
  if Obj.GetValue<string>(Turn + 'state', '') = 'running' then
    Exit;
  Append(Memo, sLineBreak + '[BTW] ' + Obj.GetValue<string>(Turn + 'q', '') + sLineBreak +
    Obj.GetValue<string>(Turn + 'a', '') + Obj.GetValue<string>(Turn + 'error', '') + sLineBreak);
end;

{ Restored conversation history: replay user and assistant turns in order. }
procedure AppendHistory(Memo: TMemo; Obj: TJSONObject);
var
  Items: TJSONArray;
  Item: TJSONValue;
  ItemObj: TJSONObject;
  Role, Text: string;
begin
  if not (Obj.GetValue('items') is TJSONArray) then
    Exit;
  Items := TJSONArray(Obj.GetValue('items'));
  for Item in Items do
  begin
    if Item is TJSONObject then
    begin
      ItemObj := TJSONObject(Item);
      Role := ItemObj.GetValue<string>('role', '');
      Text := ItemObj.GetValue<string>('text', '');
      if Role = 'user' then
        Append(Memo, sLineBreak + '> ' + Text + sLineBreak)
      else if Role = 'assistant' then
        Append(Memo, Text + sLineBreak);
    end;
  end;
end;

procedure AppendFallback(Memo: TMemo; const Json: string);
var
  Value: TJSONValue;
  Obj: TJSONObject;
  Kind: string;
begin
  Value := TJSONObject.ParseJSONValue(Json);
  try
    if not (Value is TJSONObject) then
      Exit;
    Obj := TJSONObject(Value);
    Kind := Obj.GetValue<string>('t', '');
    if Kind = 'user' then
      Append(Memo, sLineBreak + '> ' + Obj.GetValue<string>('text', '') + sLineBreak)
    else if Kind = 'history' then
      AppendHistory(Memo, Obj)
    else if Kind = 'assistantDelta' then
      Append(Memo, Obj.GetValue<string>('text', ''))
    else if Kind = 'assistantEnd' then
      Append(Memo, sLineBreak)
    else if Kind = 'toolStart' then
      Append(Memo, sLineBreak + Tr('chatfallback.tool') + ' ' + Obj.GetValue<string>('name', '') + ' ' +
        Obj.GetValue<string>('detail', '') + sLineBreak)
    else if Kind = 'toolEnd' then
      Append(Memo, IfThen(Obj.GetValue<Boolean>('ok', False), Tr('chatfallback.done'), Tr('chatfallback.failed')) + sLineBreak)
    else if Kind = 'notice' then
      Append(Memo, '[' + Obj.GetValue<string>('level', '') + '] ' + Obj.GetValue<string>('text', '') +
        sLineBreak)
    else if Kind = 'subagent' then
      Append(Memo, Tr('chatfallback.subagent') + ' ' + Obj.GetValue<string>('agent', '') + ' ' +
        Obj.GetValue<string>('id', '') + ': ' + Obj.GetValue<string>('status', '') + sLineBreak)
    else if Kind = 'todos' then
      Append(Memo, TrF('chatfallback.todos', [Obj.GetValue<TJSONArray>('items').Count]) + sLineBreak)
    else if Kind = 'btw' then
      AppendBtw(Memo, Obj)
    else if Kind = 'clear' then
      Memo.Clear;
  finally
    Value.Free;
  end;
end;

end.
