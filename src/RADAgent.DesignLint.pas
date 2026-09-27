unit RADAgent.DesignLint;

{ rad.design_lint: checks the designed form of the unit at Path against <ProjectDir>\DESIGN.md.
  ResultText is JSON for the model; False only when the check could not run. Main thread only. }

interface

function DesignLint(const Path: string; out ResultText: string): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Generics.Collections,
  System.TypInfo, Vcl.Controls, ToolsAPI,
  RADAgent.IdeContext, RADAgent.FormDesigner, RADAgent.DesignTokens, RADAgent.DesignLintRules;

type
  TVisualInfo = record
    Component: TComponent;
    Name: string;
    Left, Top, Right, Bottom: Integer;
  end;

procedure CheckGapForSiblings(const Siblings: TList<TComponent>; const Ctx: TDesignRulesContext;
  var Findings: TList<TDesignLintFinding>; ReportedPairs: TDictionary<string, Boolean>);
var
  Visuals: TList<TVisualInfo>;
  C: TComponent;
  Info, A, B, First, Second, Mid: TVisualInfo;
  PosObj: TObject;
  W, H, I, J, K, Gap, Cnt: Integer;
  PairKey, ExpStr: string;
  Nearest: Boolean;
  X, Y, FW, FH: Double;
begin
  if (Length(Ctx.SpacingScale) = 0) or (Siblings.Count < 2) then Exit;
  Visuals := TList<TVisualInfo>.Create;
  try
    for C in Siblings do
    begin
      if (C.Name = '') or IsControlAligned(C) then Continue;
      if Ctx.Framework = 'VCL' then
      begin
        if not (C is TControl) or not TControl(C).Visible then Continue;
        Info.Component := C; Info.Name := C.Name;
        Info.Left := TControl(C).Left; Info.Top := TControl(C).Top;
        W := TControl(C).Width; H := TControl(C).Height;
      end
      else
      begin
        PosObj := ObjProp(C, 'Position');
        if PosObj = nil then Continue;
        if (GetPropInfo(C, 'Visible') <> nil) and (GetOrdProp(C, 'Visible') = 0) then Continue;
        Info.Component := C; Info.Name := C.Name;
        if not (GetNumericProp(PosObj, 'X', X) and GetNumericProp(PosObj, 'Y', Y) and
          GetNumericProp(C, 'Width', FW) and GetNumericProp(C, 'Height', FH)) then Continue;
        Info.Left := Round(X); Info.Top := Round(Y); W := Round(FW); H := Round(FH);
      end;
      if (W <= 0) or (H <= 0) then Continue;
      Info.Right := Info.Left + W; Info.Bottom := Info.Top + H;
      Visuals.Add(Info);
    end;

    Cnt := Visuals.Count;
    ExpStr := ScaleToString(Ctx.SpacingScale, 'px');
    for I := 0 to Cnt - 2 do
      for J := I + 1 to Cnt - 1 do
      begin
        A := Visuals[I]; B := Visuals[J];
        if A.Name < B.Name then PairKey := A.Name + ':' + B.Name
        else PairKey := B.Name + ':' + A.Name;
        if ReportedPairs.ContainsKey(PairKey) then Continue;

        // Horizontal: overlap on Y
        if (A.Top < B.Bottom) and (B.Top < A.Bottom) then
        begin
          First := A; Second := B;
          if First.Right > Second.Left then begin First := B; Second := A; end;
          if (First.Right <= Second.Left) and (Second.Left - First.Right <= 48) and (Second.Left - First.Right > 0) then
          begin
            Gap := Second.Left - First.Right;
            Nearest := True;
            for K := 0 to Cnt - 1 do
            begin
              Mid := Visuals[K];
              if (Mid.Component <> First.Component) and (Mid.Component <> Second.Component) and
                 (Mid.Top < Second.Bottom) and (Second.Top < Mid.Bottom) and
                 (Mid.Left >= First.Right) and (Mid.Right <= Second.Left) then
              begin Nearest := False; Break; end;
            end;
            if Nearest and not IsInScale(Gap, Ctx.SpacingScale, 1.0) then
            begin
              ReportedPairs.Add(PairKey, True);
              AddFinding(Findings, A.Name + ', ' + B.Name, 'gap', IntToStr(Gap) + 'px', ExpStr,
                Format('Horizontal gap between %s and %s (%dpx) is not in spacing scale (%s).', [A.Name, B.Name, Gap, ExpStr]));
              Continue;
            end;
          end;
        end;

        // Vertical: overlap on X
        if (A.Left < B.Right) and (B.Left < A.Right) then
        begin
          First := A; Second := B;
          if First.Bottom > Second.Top then begin First := B; Second := A; end;
          if (First.Bottom <= Second.Top) and (Second.Top - First.Bottom <= 48) and (Second.Top - First.Bottom > 0) then
          begin
            Gap := Second.Top - First.Bottom;
            Nearest := True;
            for K := 0 to Cnt - 1 do
            begin
              Mid := Visuals[K];
              if (Mid.Component <> First.Component) and (Mid.Component <> Second.Component) and
                 (Mid.Left < Second.Right) and (Second.Left < Mid.Right) and
                 (Mid.Top >= First.Bottom) and (Mid.Bottom <= Second.Top) then
              begin Nearest := False; Break; end;
            end;
            if Nearest and not IsInScale(Gap, Ctx.SpacingScale, 1.0) then
            begin
              ReportedPairs.Add(PairKey, True);
              AddFinding(Findings, A.Name + ', ' + B.Name, 'gap', IntToStr(Gap) + 'px', ExpStr,
                Format('Vertical gap between %s and %s (%dpx) is not in spacing scale (%s).', [A.Name, B.Name, Gap, ExpStr]));
            end;
          end;
        end;
      end;
  finally
    Visuals.Free;
  end;
end;

procedure CollectComponents(Comp: TComponent; List: TList<TComponent>);
var
  I: Integer;
begin
  if (Comp = nil) or List.Contains(Comp) then Exit;
  List.Add(Comp);
  for I := 0 to Comp.ComponentCount - 1 do
    CollectComponents(Comp.Components[I], List);
end;

function BuildErrorJson(const Msg: string): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('ok', TJSONFalse.Create);
    Obj.AddPair('error', Msg);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function DesignLint(const Path: string; out ResultText: string): Boolean;
var
  DesignPath, DesignContent, Problem, Framework, PName, SummaryStr, OmitStr: string;
  Editor: IOTAFormEditor;
  Root, Comp: TComponent;
  FrontMatter: TFrontMatter;
  Ctx: TDesignRulesContext;
  Skipped: TList<string>;
  AllComponents: TList<TComponent>;
  Findings: TList<TDesignLintFinding>;
  ParentsMap: TDictionary<string, TList<TComponent>>;
  ReportedPairs: TDictionary<string, Boolean>;
  SibList: TList<TComponent>;
  PPIVal: Double;
  Obj, FindingObj: TJSONObject;
  FindingsArr, SkippedArr: TJSONArray;
  I, TotalFindings, ShownCount, OmittedCount: Integer;
  RuleCounts: TDictionary<string, Integer>;
  RulePair: TPair<string, Integer>;
  CountsArr: TList<string>;
begin
  ResultText := '';
  DesignPath := IncludeTrailingPathDelimiter(ActiveProjectDir) + 'DESIGN.md';
  if not FileExists(DesignPath) then
  begin
    ResultText := BuildErrorJson('No DESIGN.md in the project folder. Ask the user to run /design first.');
    Exit(False);
  end;

  Editor := FindFormEditor(ProjectPath(Path), Problem);
  if Editor = nil then
  begin
    ResultText := BuildErrorJson(Problem);
    Exit(False);
  end;

  Root := RootOf(Editor);
  if Root = nil then
  begin
    ResultText := BuildErrorJson('Form root component could not be accessed.');
    Exit(False);
  end;

  try
    DesignContent := TFile.ReadAllText(DesignPath, TEncoding.UTF8);
  except
    on E: Exception do
    begin
      ResultText := BuildErrorJson('Failed to read DESIGN.md: ' + E.Message);
      Exit(False);
    end;
  end;

  FrontMatter := ReadFrontMatter(DesignContent);
  Skipped := TList<string>.Create;
  AllComponents := TList<TComponent>.Create;
  Findings := TList<TDesignLintFinding>.Create;
  ParentsMap := TDictionary<string, TList<TComponent>>.Create;
  RuleCounts := TDictionary<string, Integer>.Create;
  CountsArr := TList<string>.Create;
  try
    if FrontMatter.TryGetValue('radstudio.framework', Framework) and (Trim(Framework) <> '') then
      Ctx.Framework := UpperCase(Trim(Framework))
    else if GetPropInfo(Root, 'Position') <> nil then
      Ctx.Framework := 'FMX'
    else
      Ctx.Framework := 'VCL';

    Ctx.PixelsPerInch := 96;
    if (Ctx.Framework = 'VCL') and GetNumericProp(Root, 'PixelsPerInch', PPIVal) and (PPIVal > 0) then
      Ctx.PixelsPerInch := Round(PPIVal);

    Ctx.SpacingScale := Dimensions(FrontMatter, 'spacing');
    Ctx.RoundedScale := Dimensions(FrontMatter, 'rounded');
    Ctx.FontSizes := FontSizes(FrontMatter);
    Ctx.FontFamilies := FontFamilies(FrontMatter);
    Ctx.Colors := Colors(FrontMatter);
    FrontMatter.TryGetValue('radstudio.style', Ctx.StyleName);

    if Length(Ctx.SpacingScale) = 0 then
    begin
      Skipped.Add('spacing');
      Skipped.Add('gap');
    end;
    if Length(Ctx.FontSizes) = 0 then Skipped.Add('font-size');
    if Length(Ctx.FontFamilies) = 0 then Skipped.Add('font-family');
    if Ctx.Framework = 'VCL' then
    begin
      if Ctx.StyleName = '' then Skipped.Add('literal-color');
    end
    else
    begin
      if Length(Ctx.Colors) = 0 then Skipped.Add('literal-color');
    end;
    if (Ctx.Framework <> 'FMX') or (Length(Ctx.RoundedScale) = 0) then
      Skipped.Add('radius');

    CollectComponents(Root, AllComponents);

    // Component-level rule checks
    for Comp in AllComponents do
    begin
      if not Skipped.Contains('spacing') then CheckSpacing(Comp, Ctx, Findings);
      if not Skipped.Contains('font-size') or not Skipped.Contains('font-family') then
        CheckTypography(Comp, Ctx, Findings);
      if not Skipped.Contains('literal-color') then CheckColors(Comp, Ctx, Findings);
      if not Skipped.Contains('radius') then CheckRadius(Comp, Ctx, Findings);

      PName := ParentName(Comp);
      if not ParentsMap.TryGetValue(PName, SibList) then
      begin
        SibList := TList<TComponent>.Create;
        ParentsMap.Add(PName, SibList);
      end;
      SibList.Add(Comp);
    end;

    // Sibling gap checks
    if not Skipped.Contains('gap') then
    begin
      ReportedPairs := TDictionary<string, Boolean>.Create;
      try
        for SibList in ParentsMap.Values do
          if SibList.Count >= 2 then
            CheckGapForSiblings(SibList, Ctx, Findings, ReportedPairs);
      finally
        ReportedPairs.Free;
      end;
    end;

    // Tally finding counts by rule
    TotalFindings := Findings.Count;
    for I := 0 to TotalFindings - 1 do
    begin
      if not RuleCounts.ContainsKey(Findings[I].Rule) then
        RuleCounts.Add(Findings[I].Rule, 1)
      else
        RuleCounts[Findings[I].Rule] := RuleCounts[Findings[I].Rule] + 1;
    end;

    for RulePair in RuleCounts do
      CountsArr.Add(Format('%s: %d', [RulePair.Key, RulePair.Value]));

    ShownCount := TotalFindings;
    if ShownCount > 100 then ShownCount := 100;
    OmittedCount := TotalFindings - ShownCount;

    if OmittedCount > 0 then
      OmitStr := Format(' (%d more)', [OmittedCount])
    else
      OmitStr := '';

    if TotalFindings = 0 then
      SummaryStr := '0 findings'
    else if CountsArr.Count > 0 then
      SummaryStr := Format('%d findings%s: %s', [TotalFindings, OmitStr, string.Join(', ', CountsArr.ToArray)])
    else
      SummaryStr := Format('%d findings%s', [TotalFindings, OmitStr]);

    Obj := TJSONObject.Create;
    try
      Obj.AddPair('ok', TJSONTrue.Create);
      Obj.AddPair('designFile', DesignPath);
      Obj.AddPair('form', Root.Name);
      Obj.AddPair('framework', Ctx.Framework);
      Obj.AddPair('checked', TJSONNumber.Create(AllComponents.Count));

      SkippedArr := TJSONArray.Create;
      for I := 0 to Skipped.Count - 1 do
        SkippedArr.Add(Skipped[I]);
      Obj.AddPair('skipped', SkippedArr);

      FindingsArr := TJSONArray.Create;
      for I := 0 to ShownCount - 1 do
      begin
        FindingObj := TJSONObject.Create;
        FindingObj.AddPair('component', Findings[I].Component);
        FindingObj.AddPair('rule', Findings[I].Rule);
        FindingObj.AddPair('value', Findings[I].Value);
        FindingObj.AddPair('expected', Findings[I].Expected);
        FindingObj.AddPair('message', Findings[I].Message);
        FindingsArr.AddElement(FindingObj);
      end;
      Obj.AddPair('findings', FindingsArr);
      Obj.AddPair('summary', SummaryStr);

      ResultText := Obj.ToJSON;
      Result := True;
    finally
      Obj.Free;
    end;
  finally
    for SibList in ParentsMap.Values do
      SibList.Free;
    ParentsMap.Free;
    Findings.Free;
    AllComponents.Free;
    Skipped.Free;
    FrontMatter.Free;
    RuleCounts.Free;
    CountsArr.Free;
  end;
end;

end.
