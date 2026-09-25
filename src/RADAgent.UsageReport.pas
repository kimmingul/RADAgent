unit RADAgent.UsageReport;

{ The plan limits of one provider from "omp usage --json", shaped for the usage panel. No VCL,
  no ToolsAPI. }

interface

uses
  System.JSON;

{ The limits of one provider from "omp usage --json" as "plan" and "limits" (window, group, used,
  resetsAt per row). nil when the report has no such provider. The caller frees it. }
function UsageLimits(const UsageJson, Provider: string): TJSONObject;

implementation

uses
  System.SysUtils, System.Generics.Collections, RADAgent.RpcJson;

{ Anthropic names a limit after its window ("Claude 5 Hour"); Antigravity after the models it
  covers ("Gemini"). A tier ("fable") narrows a limit to those models. }
function LimitGroup(Limit: TJSONObject): string;
var
  Label_, WindowLabel: string;
begin
  Result := JsonStr(JsonChild(Limit, 'scope'), 'tier');
  if Result <> '' then
    Exit(UpperCase(Copy(Result, 1, 1)) + Copy(Result, 2, MaxInt));
  Label_ := JsonStr(Limit, 'label');
  WindowLabel := JsonStr(JsonChild(Limit, 'window'), 'label');
  if (WindowLabel <> '') and Label_.ToLower.Contains(WindowLabel.ToLower) then
    Result := ''
  else
    Result := Label_;
end;

function UsageLimits(const UsageJson, Provider: string): TJSONObject;
var
  Obj, Report, Limit, Window, Amount, Row: TJSONObject;
  Item, Entry: TJSONValue;
  Rows: TJSONArray;
  Seen: TList<string>;
  Key, Plan: string;
begin
  Result := nil;
  Obj := JsonObject(UsageJson);
  Seen := TList<string>.Create;
  try
    if (Obj = nil) or not (Obj.GetValue('reports') is TJSONArray) then
      Exit;
    for Item in TJSONArray(Obj.GetValue('reports')) do
    begin
      if not (Item is TJSONObject) or not SameText(JsonStr(TJSONObject(Item), 'provider'), Provider) then
        Continue;
      Report := TJSONObject(Item);
      Plan := JsonStr(JsonChild(Report, 'metadata'), 'planType');
      Result := TJSONObject.Create;
      Result.AddPair('plan', UpperCase(Copy(Plan, 1, 1)) + Copy(Plan, 2, MaxInt));
      Rows := TJSONArray.Create;
      Result.AddPair('limits', Rows);
      if Report.GetValue('limits') is TJSONArray then
        for Entry in TJSONArray(Report.GetValue('limits')) do
        begin
          if not (Entry is TJSONObject) then
            Continue;
          Limit := TJSONObject(Entry);
          Window := JsonChild(Limit, 'window');
          Amount := JsonChild(Limit, 'amount');
          Key := JsonStr(Limit, 'label') + '|' + JsonStr(Window, 'id') + '|' + JsonStr(Window, 'resetsAt');
          if (Amount = nil) or Seen.Contains(Key) then
            Continue;
          Seen.Add(Key);
          Row := TJSONObject.Create;
          Row.AddPair('window', JsonStr(Window, 'id'));
          Row.AddPair('windowLabel', JsonStr(Window, 'label'));
          Row.AddPair('group', LimitGroup(Limit));
          if Amount.GetValue('usedFraction') is TJSONNumber then
            Row.AddPair('used', TJSONNumber.Create(TJSONNumber(Amount.GetValue('usedFraction')).AsDouble))
          else
            Row.AddPair('used', TJSONNumber.Create(0));
          Row.AddPair('resetsAt', TJSONNumber.Create(JsonInt(Window, 'resetsAt', 0)));
          Row.AddPair('status', JsonStr(Limit, 'status'));
          Rows.AddElement(Row);
        end;
      Exit;
    end;
  finally
    Seen.Free;
    Obj.Free;
  end;
end;

end.
