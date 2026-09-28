unit RADAgent.HostToolArgs;

{ Checks rad.* call arguments against the tool's declared schema before dispatch: an argument
  the schema does not declare (additionalProperties false) or a missing required one becomes an
  error that names the expected arguments, so the model retries with the right keys instead of
  the tool failing on an empty value. omp does not validate host-tool arguments. No ToolsAPI. }

interface

{ False with Problem set when ArgumentsJson has an undeclared or lacks a required argument.
  Unknown tools and non-object arguments pass; the tool itself reports those. }
function CheckHostToolArgs(const ToolName, ArgumentsJson: string; out Problem: string): Boolean;

implementation

uses
  System.SysUtils, System.JSON, RADAgent.HostToolDefs;

function FindTool(Tools: TJSONArray; const ToolName: string): TJSONObject;
var
  Index: Integer;
begin
  for Index := 0 to Tools.Count - 1 do
    if TJSONObject(Tools.Items[Index]).GetValue<string>('name', '') = ToolName then
      Exit(TJSONObject(Tools.Items[Index]));
  Result := nil;
end;

function Expected(Props: TJSONObject): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to Props.Count - 1 do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Props.Pairs[Index].JsonString.Value;
  end;
end;

function CheckAgainst(Params, Args: TJSONObject; const ToolName: string; out Problem: string): Boolean;
var
  Props: TJSONObject;
  Required: TJSONArray;
  Index: Integer;
  Key: string;
begin
  Result := True;
  Problem := '';
  Props := Params.GetValue('properties') as TJSONObject;
  if Props = nil then
    Exit;
  if Params.GetValue('additionalProperties') is TJSONFalse then
    for Index := 0 to Args.Count - 1 do
    begin
      Key := Args.Pairs[Index].JsonString.Value;
      if Props.GetValue(Key) = nil then
      begin
        Problem := Format('Unknown argument "%s" for %s; expected: %s.', [Key, ToolName, Expected(Props)]);
        Exit(False);
      end;
    end;
  Required := Params.GetValue('required') as TJSONArray;
  if Required <> nil then
    for Index := 0 to Required.Count - 1 do
      if Args.GetValue(Required.Items[Index].Value) = nil then
      begin
        Problem := Format('Missing required argument "%s" for %s; expected: %s.',
          [Required.Items[Index].Value, ToolName, Expected(Props)]);
        Exit(False);
      end;
end;

function CheckHostToolArgs(const ToolName, ArgumentsJson: string; out Problem: string): Boolean;
var
  Profile: TToolProfile;
  Frame, Args: TJSONValue;
  Tool: TJSONObject;
begin
  Result := True;
  Problem := '';
  Args := TJSONObject.ParseJSONValue(ArgumentsJson);
  try
    if not (Args is TJSONObject) then
      Exit;
    { FMX with forms offers every tool; argument names do not differ between profiles. }
    Profile := DefaultToolProfile;
    Profile.Framework := 'FMX';
    Frame := TJSONObject.ParseJSONValue(BuildSetHostToolsFrame('', Profile));
    try
      Tool := FindTool(TJSONObject(Frame).GetValue('tools') as TJSONArray, ToolName);
      if (Tool <> nil) and (Tool.GetValue('parameters') is TJSONObject) then
        Result := CheckAgainst(TJSONObject(Tool.GetValue('parameters')), TJSONObject(Args), ToolName, Problem);
    finally
      Frame.Free;
    end;
  finally
    Args.Free;
  end;
end;

end.
