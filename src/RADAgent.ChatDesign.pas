unit RADAgent.ChatDesign;

{ /design [style] [preset]: the user picks one of the installed styles of the project's framework
  (VCL or FMX); RAD Agent writes DESIGN.md with the style's platform preset and gives the project
  the style, with the chat's approval cards as the approval mode says. Refused in plan mode.
  Main thread only. }

interface

procedure RunDesignCommand(const Args: string);

implementation

uses
  System.SysUtils, System.Classes, System.JSON, RADAgent.ChatSession, RADAgent.AskDialog,
  RADAgent.Lang, RADAgent.DesignCatalog, RADAgent.DesignInit, RADAgent.Approval, RADAgent.RpcJson,
  RADAgent.ChatPlan;

function ThemeText(const Theme: string): string;
begin
  if SameText(Theme, 'dark') then
    Result := Tr('chatdesign.themeDark')
  else if SameText(Theme, 'light') then
    Result := Tr('chatdesign.themeLight')
  else
    Result := Tr('chatdesign.themeUnknown');
end;

function OriginText(const Style: TDesignStyle): string;
begin
  if SameText(Style.Basis, 'none') then
    Result := Tr('chatdesign.originNone')
  else if SameText(Style.Basis, 'unclassified') then
    Result := Tr('chatdesign.originUnknown')
  else if SameText(Style.Basis, 'name') then
    Result := TrF('chatdesign.originName', [Style.System])
  else
    Result := TrF('chatdesign.originVerified', [Style.System]);
end;

function PickStyle(const Framework: string; out Style: TDesignStyle): Boolean;
var
  Choices: TArray<TDesignStyle>;
  Items: TStringList;
  Item: TDesignStyle;
  Index: Integer;
begin
  Result := False;
  Choices := nil;
  Items := TStringList.Create;
  try
    for Item in InstalledStyles(Framework) do
      if Item.Loadable then
      begin
        Choices := Choices + [Item];
        Items.Add(TrF('chatdesign.item', [Item.Name, ThemeText(Item.Theme), OriginText(Item),
          PresetTitle(Item.Preset)]));
      end;
    if Items.Count = 0 then
    begin
      ChatSession.Notice('warn', TrF('chatdesign.noStyles', [Framework]));
      Exit;
    end;
    Index := AskIndex(TrF('chatdesign.pickTitle', [Framework]), Items);
  finally
    Items.Free;
  end;
  if Index < 0 then
    Exit;
  Style := Choices[Index];
  Result := True;
end;

procedure RunDesignCommand(const Args: string);
var
  Framework, StyleArg, PresetArg, ResultText, Error: string;
  Parts: TArray<string>;
  Style: TDesignStyle;
  Obj: TJSONObject;
  Declined: Boolean;
begin
  if ChatSession.Busy then
  begin
    ChatSession.Notice('warn', Tr('chatslash.busy'));
    Exit;
  end;
  if PlanActive then
  begin
    ChatSession.Notice('warn', Tr('chatdesign.planMode'));
    Exit;
  end;
  Framework := ProjectFramework;
  if Framework = '' then
  begin
    ChatSession.Notice('warn', Tr('chatdesign.noFramework'));
    Exit;
  end;
  Parts := Trim(Args).Split([' '], TStringSplitOptions.ExcludeEmpty);
  StyleArg := '';
  PresetArg := '';
  if Length(Parts) > 0 then
    StyleArg := Parts[0];
  if Length(Parts) > 1 then
    PresetArg := Parts[1];
  if StyleArg <> '' then
  begin
    if not FindStyle(Framework, StyleArg, Style) then
    begin
      ChatSession.Notice('warn', TrF('chatdesign.unknownStyle', [StyleArg, Framework]));
      Exit;
    end;
  end
  else if not PickStyle(Framework, Style) then
    Exit;
  if (PresetArg <> '') and (PresetText(PresetArg) = '') then
  begin
    ChatSession.Notice('warn', TrF('chatdesign.unknownPreset', [PresetArg, string.Join(', ', PresetIds)]));
    Exit;
  end;
  { The chat's approval: cards (or none) as the approval mode says, like rad.design_init. }
  InitDesign(Style, PresetArg, True, ChatSession.Approval, ResultText);
  if ResultText = SEditCancelled then
  begin
    ChatSession.Notice('info', Tr('chatdesign.cancelled'));
    Exit;
  end;
  Obj := JsonObject(ResultText);
  try
    Error := JsonStr(Obj, 'styleError');
    if Error = '' then
      Error := JsonStr(Obj, 'error');
    Declined := JsonStr(Obj, 'styleApplied').StartsWith('no:');
  finally
    Obj.Free;
  end;
  if PresetArg = '' then
    PresetArg := Style.Preset;
  if Error <> '' then
    ChatSession.Notice('warn', TrF('chatdesign.failed', [Error]))
  else if Declined then
    ChatSession.Notice('info', TrF('chatdesign.docOnly', [DesignFile, Style.Name]))
  else
    ChatSession.Notice('info', TrF('chatdesign.done', [DesignFile, Style.Name, PresetTitle(PresetArg)]));
end;

end.
