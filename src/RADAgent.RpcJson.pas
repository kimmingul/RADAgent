unit RADAgent.RpcJson;

{ Small JSON readers shared by the RPC frame parsers. No VCL, no ToolsAPI. }

interface

uses
  System.JSON;

{ Parsed object or nil; the caller frees it. }
function JsonObject(const Line: string): TJSONObject;
{ String or number value as text; '' when missing. }
function JsonStr(Obj: TJSONObject; const Name: string): string;
function JsonChild(Obj: TJSONObject; const Name: string): TJSONObject;
function JsonInt(Obj: TJSONObject; const Name: string; Default: Int64 = 0): Int64;
function IsJsonTrue(Value: TJSONValue): Boolean;
function IsJsonFalse(Value: TJSONValue): Boolean;
{ Joins the text parts of a message "content" (string or part array). }
function ContentText(Value: TJSONValue): string;
function CollapseWhitespace(const S: string): string;

implementation

uses
  System.SysUtils, System.Generics.Collections;

function JsonObject(const Line: string): TJSONObject;
var
  Value: TJSONValue;
begin
  Result := nil;
  if Trim(Line) = '' then
    Exit;
  try
    Value := TJSONObject.ParseJSONValue(Line);
  except
    Exit;
  end;
  if Value is TJSONObject then
    Result := TJSONObject(Value)
  else
    Value.Free;
end;

function JsonStr(Obj: TJSONObject; const Name: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  if Obj = nil then
    Exit;
  Value := Obj.GetValue(Name);
  if Value is TJSONString then
    Result := TJSONString(Value).Value
  else if Value is TJSONNumber then
    Result := Value.Value;
end;

function JsonChild(Obj: TJSONObject; const Name: string): TJSONObject;
begin
  Result := nil;
  if (Obj <> nil) and (Obj.GetValue(Name) is TJSONObject) then
    Result := TJSONObject(Obj.GetValue(Name));
end;

function JsonInt(Obj: TJSONObject; const Name: string; Default: Int64): Int64;
begin
  Result := Default;
  { omp sends some counts as fractions (auto_retry_start delayMs); AsInt64 raises on those. }
  if (Obj <> nil) and (Obj.GetValue(Name) is TJSONNumber) then
    Result := Round(TJSONNumber(Obj.GetValue(Name)).AsDouble);
end;

function IsJsonTrue(Value: TJSONValue): Boolean;
begin
  Result := (Value is TJSONTrue) or ((Value is TJSONString) and SameText(TJSONString(Value).Value, 'true'));
end;

function IsJsonFalse(Value: TJSONValue): Boolean;
begin
  Result := (Value is TJSONFalse) or ((Value is TJSONString) and SameText(TJSONString(Value).Value, 'false'));
end;

function ContentText(Value: TJSONValue): string;
var
  Parts: TJSONArray;
  Index: Integer;
  Part: TJSONObject;
begin
  Result := '';
  if Value is TJSONString then
    Exit(TJSONString(Value).Value);
  if not (Value is TJSONArray) then
    Exit;
  Parts := TJSONArray(Value);
  for Index := 0 to Parts.Count - 1 do
    if Parts.Items[Index] is TJSONObject then
    begin
      Part := TJSONObject(Parts.Items[Index]);
      if (JsonStr(Part, 'type') = 'text') or (JsonStr(Part, 'type') = '') then
        if Result = '' then
          Result := JsonStr(Part, 'text')
        else
          Result := Result + sLineBreak + JsonStr(Part, 'text');
    end;
end;

function CollapseWhitespace(const S: string): string;
var
  Index: Integer;
  InSpace: Boolean;
  Builder: TStringBuilder;
begin
  if S = '' then
    Exit('');
  Builder := TStringBuilder.Create;
  try
    InSpace := False;
    for Index := 1 to Length(S) do
      if CharInSet(S[Index], [' ', #9, #10, #13]) then
      begin
        if not InSpace then
          Builder.Append(' ');
        InSpace := True;
      end
      else
      begin
        Builder.Append(S[Index]);
        InSpace := False;
      end;
    Result := Trim(Builder.ToString);
  finally
    Builder.Free;
  end;
end;

end.
