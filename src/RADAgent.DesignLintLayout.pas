unit RADAgent.DesignLintLayout;

{ Whole-form layout design lint rules:
  1. align: visible siblings under same parent forming a vertical stack (horizontal ranges
     overlap) or horizontal row (vertical ranges overlap) with edges differing by 1..3 px
     reported as misalignment once with expected set to reference control's edge (skip Align).
  2. button-order: horizontal button row under one parent (class contains 'Button'/'BitBtn',
     vertical ranges overlap) comparing primary (Default=True or ModalResult in [1,6]) vs
     cancel (Cancel=True or ModalResult in [2,7]). apple-macos: primary right of cancel;
     Windows/Material/other: primary left of cancel.
  3. type-scale: distinct explicit font sizes across form (VCL: ParentFont False -> px from
     -Font.Height*96/PPI when <0, else Font.Size*96/72; FMX: TextSettings.Font.Size without 'Size'
     in StyledSettings). Ignores icon fonts ('Icons','MDL2','Symbol'). >4 sizes -> finding on
     root with rarest. }

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  RADAgent.DesignLintRules;

procedure CheckLayout(Root: TComponent; const Components: TList<TComponent>;
  const Ctx: TDesignRulesContext; const Preset: string; var Findings: TList<TDesignLintFinding>);

implementation

uses
  System.TypInfo, Vcl.Controls;

type
  TVisualInfo = record
    Component: TComponent;
    Name: string;
    Left, Top, Width, Height, Right, Bottom: Integer;
  end;

{ Aligned: also controls placed by Align (their bounds are where the designer put them); the
  alignment rule skips them, the button order rule does not. }
function GetVisualInfo(Comp: TComponent; const Framework: string; out Info: TVisualInfo;
  Aligned: Boolean = False): Boolean;
var
  PosObj: TObject;
  X, Y, FW, FH: Double;
  Vis: PPropInfo;
begin
  Result := False;
  if (Comp = nil) or (Comp.Name = '') or (not Aligned and IsControlAligned(Comp)) then Exit;
  if Framework = 'VCL' then
  begin
    if not (Comp is TControl) or not TControl(Comp).Visible then Exit;
    Info.Left := TControl(Comp).Left; Info.Top := TControl(Comp).Top;
    Info.Width := TControl(Comp).Width; Info.Height := TControl(Comp).Height;
  end
  else
  begin
    PosObj := ObjProp(Comp, 'Position'); Vis := GetPropInfo(Comp, 'Visible');
    if (PosObj = nil) or ((Vis <> nil) and (GetOrdProp(Comp, Vis) = 0)) or
      not (GetNumericProp(PosObj, 'X', X) and GetNumericProp(PosObj, 'Y', Y) and
        GetNumericProp(Comp, 'Width', FW) and GetNumericProp(Comp, 'Height', FH)) then Exit;
    Info.Left := Round(X); Info.Top := Round(Y); Info.Width := Round(FW); Info.Height := Round(FH);
  end;
  if (Info.Width <= 0) or (Info.Height <= 0) then Exit;
  Info.Component := Comp; Info.Name := Comp.Name;
  Info.Right := Info.Left + Info.Width; Info.Bottom := Info.Top + Info.Height;
  Result := True;
end;

procedure CheckAlign(const Siblings: TList<TComponent>; const Framework: string;
  var Findings: TList<TDesignLintFinding>; Reported: TDictionary<string, Boolean>);
var
  Visuals: TList<TVisualInfo>;
  Comp: TComponent;
  Info, A, B, First, Second: TVisualInfo;
  I, J, K, Diff, V1, V2: Integer;
  Tag, Suffix, Side: string;
begin
  if Siblings.Count < 2 then Exit;
  Visuals := TList<TVisualInfo>.Create;
  try
    for Comp in Siblings do if GetVisualInfo(Comp, Framework, Info) then Visuals.Add(Info);
    for I := 0 to Visuals.Count - 2 do
      for J := I + 1 to Visuals.Count - 1 do
      begin
        A := Visuals[I]; B := Visuals[J];
        for K := 0 to 1 do
        begin
          if K = 0 then
          begin
            if not ((A.Left < B.Right) and (B.Left < A.Right)) then Continue;
            Diff := Abs(A.Left - B.Left); Suffix := ':l'; Side := 'Left';
            if (A.Top < B.Top) or ((A.Top = B.Top) and (A.Name < B.Name)) then begin First := A; Second := B; end
            else begin First := B; Second := A; end;
            V1 := Second.Left; V2 := First.Left;
          end else
          begin
            if not ((A.Top < B.Bottom) and (B.Top < A.Bottom)) then Continue;
            Diff := Abs(A.Top - B.Top); Suffix := ':t'; Side := 'Top';
            if (A.Left < B.Left) or ((A.Left = B.Left) and (A.Name < B.Name)) then begin First := A; Second := B; end
            else begin First := B; Second := A; end;
            V1 := Second.Top; V2 := First.Top;
          end;
          if (Diff < 1) or (Diff > 3) then Continue;
          if A.Name < B.Name then Tag := A.Name + ':' + B.Name + Suffix else Tag := B.Name + ':' + A.Name + Suffix;
          if Reported.ContainsKey(Tag) then Continue;
          Reported.Add(Tag, True);
          AddFinding(Findings, First.Name + ', ' + Second.Name, 'align', IntToStr(V1) + 'px', IntToStr(V2) + 'px',
            Format('%s edge of %s (%dpx) misaligned with %s (%dpx); differs by %dpx.', [Side, Second.Name, V1, First.Name, V2, Diff]));
        end;
      end;
  finally
    Visuals.Free;
  end;
end;

function IsButton(C: TComponent; Kind: Integer): Boolean;
var
  P: PPropInfo;
  V: Double;
  PropName, S1, S2: string;
  MR1, MR2: Integer;
begin
  if Kind = 1 then begin PropName := 'Default'; MR1 := 1; MR2 := 6; S1 := 'mrOk'; S2 := 'mrYes'; end
  else begin PropName := 'Cancel'; MR1 := 2; MR2 := 7; S1 := 'mrCancel'; S2 := 'mrNo'; end;
  P := GetPropInfo(C, PropName);
  if (P <> nil) and (GetOrdProp(C, P) <> 0) then Exit(True);
  if GetNumericProp(C, 'ModalResult', V) and ((Round(V) = MR1) or (Round(V) = MR2)) then Exit(True);
  P := GetPropInfo(C, 'ModalResult');
  Result := (P <> nil) and (P^.PropType^.Kind = tkEnumeration) and
    (SameText(GetEnumProp(C, P), S1) or SameText(GetEnumProp(C, P), S2));
end;

procedure CheckButtonOrder(const Siblings: TList<TComponent>; const Framework, Preset: string;
  var Findings: TList<TDesignLintFinding>; Reported: TDictionary<string, Boolean>);
var
  Btns: TList<TVisualInfo>;
  Comp: TComponent;
  Info, Pri, Can: TVisualInfo;
  I, J: Integer;
  IsMac: Boolean;
  ValS, ExpS, OrdName: string;
begin
  if Siblings.Count < 2 then Exit;
  Btns := TList<TVisualInfo>.Create;
  try
    for Comp in Siblings do
      if ((Pos('button', LowerCase(Comp.ClassName)) > 0) or (Pos('bitbtn', LowerCase(Comp.ClassName)) > 0)) and
        GetVisualInfo(Comp, Framework, Info, True) then Btns.Add(Info);
    if Btns.Count < 2 then Exit;
    IsMac := SameText(Preset, 'apple-macos');
    if IsMac then OrdName := 'apple-macos order (Cancel, OK)' else OrdName := 'Windows / Material order (OK, Cancel)';
    for I := 0 to Btns.Count - 1 do
    begin
      Pri := Btns[I];
      if not IsButton(Pri.Component, 1) or Reported.ContainsKey(Pri.Name) then Continue;
      for J := 0 to Btns.Count - 1 do
      begin
        Can := Btns[J];
        if (I = J) or not IsButton(Can.Component, 2) or not ((Pri.Top < Can.Bottom) and (Can.Top < Pri.Bottom)) then Continue;
        if (IsMac and (Pri.Left < Can.Left)) or (not IsMac and (Pri.Left > Can.Left)) then
        begin
          Reported.Add(Pri.Name, True);
          if IsMac then begin ValS := 'left of ' + Can.Name; ExpS := 'right of ' + Can.Name; end
          else begin ValS := 'right of ' + Can.Name; ExpS := 'left of ' + Can.Name; end;
          AddFinding(Findings, Pri.Name, 'button-order', ValS, ExpS,
            Format('Button order violation: primary button "%s" is %s; expected %s under %s.',
              [Pri.Name, ValS, ExpS, OrdName]));
          Break;
        end;
      end;
    end;
  finally
    Btns.Free;
  end;
end;

function HasStyledSetting(Comp: TComponent; TSet: TObject; const Setting: string): Boolean;
var
  P: PPropInfo;
  O: TObject;
begin
  O := Comp; P := GetPropInfo(Comp, 'StyledSettings');
  if P = nil then begin O := TSet; P := GetPropInfo(TSet, 'StyledSettings'); end;
  Result := (P = nil) or GetSetProp(O, P, True).Contains(Setting);
end;

function GetExplicitFontSize(Comp: TComponent; const Framework: string; PPI: Integer): Integer;
var
  P: PPropInfo;
  F, TSet: TObject;
  Fam: string;
  H, S: Double;
begin
  Result := 0;
  if Framework = 'VCL' then
  begin
    P := GetPropInfo(Comp, 'ParentFont');
    if (P = nil) or (GetOrdProp(Comp, P) <> 0) then Exit;
    F := ObjProp(Comp, 'Font'); if F = nil then Exit;
    Fam := UpperCase(GetStrProp(F, 'Name'));
    if Fam.Contains('ICONS') or Fam.Contains('MDL2') or Fam.Contains('SYMBOL') then Exit;
    if PPI <= 0 then PPI := 96;
    if GetNumericProp(F, 'Height', H) and (H < 0) then Result := Round(-H * 96.0 / PPI)
    else if GetNumericProp(F, 'Size', S) and (S > 0) then Result := Round(S * 96.0 / 72.0);
  end
  else
  begin
    TSet := ObjProp(Comp, 'TextSettings');
    if (TSet = nil) or HasStyledSetting(Comp, TSet, 'Size') then Exit;
    F := ObjProp(TSet, 'Font'); if F = nil then Exit;
    Fam := UpperCase(GetStrProp(F, 'Family'));
    if Fam.Contains('ICONS') or Fam.Contains('MDL2') or Fam.Contains('SYMBOL') then Exit;
    if GetNumericProp(F, 'Size', S) and (S > 0) then Result := Round(S);
  end;
end;

procedure CheckTypeScale(Root: TComponent; const Components: TList<TComponent>; const Ctx: TDesignRulesContext;
  var Findings: TList<TDesignLintFinding>);
var
  SizesMap: TDictionary<Integer, TList<string>>;
  NumList: TList<Integer>;
  Comp: TComponent;
  CompName, SizesStr, RarestStr, RootName: string;
  Px, I, J, Temp: Integer;
  CompList, Rarest: TList<string>;
begin
  SizesMap := TDictionary<Integer, TList<string>>.Create;
  NumList := TList<Integer>.Create; Rarest := TList<string>.Create;
  try
    for Comp in Components do if (Comp <> nil) and (Comp <> Root) then
    begin
      Px := GetExplicitFontSize(Comp, Ctx.Framework, Ctx.PixelsPerInch);
      if Px > 0 then
      begin
        CompName := Comp.Name; if CompName = '' then CompName := Comp.ClassName;
        if not SizesMap.TryGetValue(Px, CompList) then
        begin CompList := TList<string>.Create; SizesMap.Add(Px, CompList); end;
        CompList.Add(CompName);
      end;
    end;
    if SizesMap.Count > 4 then
    begin
      for Px in SizesMap.Keys do NumList.Add(Px);
      NumList.Sort;
      for I := 0 to NumList.Count - 1 do Rarest.Add(IntToStr(NumList[I]) + 'px');
      SizesStr := string.Join(', ', Rarest.ToArray);
      Rarest.Clear;
      for I := 0 to NumList.Count - 2 do
        for J := I + 1 to NumList.Count - 1 do
          if SizesMap[NumList[I]].Count > SizesMap[NumList[J]].Count then
          begin Temp := NumList[I]; NumList[I] := NumList[J]; NumList[J] := Temp; end;
      for I := 0 to NumList.Count - 1 do
      begin
        if I >= 3 then Break;
        Rarest.Add(Format('%dpx on %s', [NumList[I], string.Join(', ', SizesMap[NumList[I]].ToArray)]));
      end;
      RarestStr := string.Join('; ', Rarest.ToArray);
      if (Root <> nil) and (Root.Name <> '') then RootName := Root.Name else RootName := 'Form';
      AddFinding(Findings, RootName, 'type-scale', Format('%d sizes (%s)', [SizesMap.Count, SizesStr]),
        'at most 4 distinct font sizes',
        Format('Form "%s" has %d distinct explicit font sizes (%s), exceeding maximum of 4. Rarest: %s.',
          [RootName, SizesMap.Count, SizesStr, RarestStr]));
    end;
  finally
    for CompList in SizesMap.Values do CompList.Free;
    SizesMap.Free; NumList.Free; Rarest.Free;
  end;
end;

procedure CheckLayout(Root: TComponent; const Components: TList<TComponent>;
  const Ctx: TDesignRulesContext; const Preset: string; var Findings: TList<TDesignLintFinding>);
var
  ParentsMap: TDictionary<string, TList<TComponent>>;
  Reported: TDictionary<string, Boolean>;
  SibList: TList<TComponent>;
  Comp: TComponent;
  PName, Framework: string;
begin
  if (Components = nil) or (Components.Count = 0) then Exit;
  Framework := Ctx.Framework;
  if Framework = '' then
  begin
    if (Root <> nil) and (GetPropInfo(Root, 'Position') <> nil) then Framework := 'FMX' else Framework := 'VCL';
  end;
  ParentsMap := TDictionary<string, TList<TComponent>>.Create; Reported := TDictionary<string, Boolean>.Create;
  try
    for Comp in Components do if Comp <> nil then
    begin
      PName := ParentName(Comp);
      if not ParentsMap.TryGetValue(PName, SibList) then
      begin SibList := TList<TComponent>.Create; ParentsMap.Add(PName, SibList); end;
      SibList.Add(Comp);
    end;
    for SibList in ParentsMap.Values do if SibList.Count >= 2 then
    begin CheckAlign(SibList, Framework, Findings, Reported); CheckButtonOrder(SibList, Framework, Preset, Findings, Reported); end;
    CheckTypeScale(Root, Components, Ctx, Findings);
  finally
    for SibList in ParentsMap.Values do SibList.Free;
    ParentsMap.Free; Reported.Free;
  end;
end;

end.
