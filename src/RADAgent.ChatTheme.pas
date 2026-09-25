unit RADAgent.ChatTheme;

{ Chat colours. Follows the IDE theme through IOTAIDEThemingServices; the high-contrast palette
  and font size come from RADAgent.AgentSettings. Also notifies when the IDE theme changes. }

interface

uses
  System.Classes, System.SysUtils, Vcl.Graphics, Vcl.Forms;

type
  TChatPalette = record
    Bg, Fg, Muted, Accent, UserBg, AssistantBg, CodeBg, Border, Error, Success, Warn, Link: TColor;
    FontSize: Integer;
  end;

  TThemeChanged = procedure of object;

  { RADAgent's own dialogs. A class of our own, so registering it with the IDE theming does not
    touch other packages' plain TForms. }
  TAgentForm = class(TForm)
  protected
    procedure CreateWnd; override;
  end;

function CurrentPalette: TChatPalette;
{ Page message of kind "theme" carrying the CSS variables. }
function PaletteJson(const Palette: TChatPalette): string;
{ Applies the IDE theme to VCL controls under Root, then the palette to plain controls. }
procedure ApplyVclTheme(Root: TComponent);
{ Dark/light like the IDE: registers the form's class with the IDE theming (once), applies the
  IDE style, then the palette (greyed notes use the muted colour). Call once the controls exist. }
procedure ThemeForm(Form: TCustomForm);
procedure InstallThemeWatch(const OnChanged: TThemeChanged);
procedure RemoveThemeWatch;

implementation

uses
  System.JSON, System.Generics.Collections, Winapi.Windows, Winapi.Dwmapi, Vcl.Themes, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, ToolsAPI,
  RADAgent.AgentSettings;

type
  TThemeWatch = class(TNotifierObject, INTAIDEThemingServicesNotifier)
  public
    procedure ChangingTheme;
    procedure ChangedTheme;
  end;

var
  GOnThemeChanged: TThemeChanged;
  GWatchIndex: Integer = -1;
  GRegistered: TList<TClass>;

function Theming: IOTAIDEThemingServices250;
begin
  if not Supports(BorlandIDEServices, IOTAIDEThemingServices250, Result) then
    Result := nil;
end;

function Blend(A, B: TColor; Amount: Double): TColor;
var
  Ca, Cb: Longint;
begin
  Ca := ColorToRGB(A);
  Cb := ColorToRGB(B);
  Result := RGB(Round(GetRValue(Ca) + (GetRValue(Cb) - GetRValue(Ca)) * Amount),
    Round(GetGValue(Ca) + (GetGValue(Cb) - GetGValue(Ca)) * Amount),
    Round(GetBValue(Ca) + (GetBValue(Cb) - GetBValue(Ca)) * Amount));
end;

function IsDark(Color: TColor): Boolean;
var
  C: Longint;
begin
  C := ColorToRGB(Color);
  Result := (0.299 * GetRValue(C) + 0.587 * GetGValue(C) + 0.114 * GetBValue(C)) < 128;
end;

function HighContrastPalette: TChatPalette;
begin
  Result.Bg := clBlack;
  Result.Fg := clWhite;
  Result.Muted := RGB(210, 210, 210);
  Result.Accent := RGB(255, 255, 0);
  Result.UserBg := RGB(0, 0, 96);
  Result.AssistantBg := clBlack;
  Result.CodeBg := RGB(24, 24, 24);
  Result.Border := clWhite;
  Result.Error := RGB(255, 110, 110);
  Result.Success := RGB(120, 255, 120);
  Result.Warn := RGB(255, 220, 0);
  Result.Link := RGB(0, 255, 255);
  Result.FontSize := ChatFontSize + 2;
end;

function CurrentPalette: TChatPalette;
var
  Services: IOTAIDEThemingServices250;
  Style: TCustomStyleServices;
begin
  if HighContrastEnabled then
    Exit(HighContrastPalette);
  Services := Theming;
  if (Services <> nil) and Services.IDEThemingEnabled and (Services.StyleServices <> nil) then
    Style := Services.StyleServices
  else
    Style := StyleServices;
  Result.Bg := Style.GetSystemColor(clWindow);
  Result.Fg := Style.GetSystemColor(clWindowText);
  Result.Accent := Style.GetSystemColor(clHighlight);
  Result.Muted := Blend(Result.Fg, Result.Bg, 0.45);
  Result.UserBg := Blend(Result.Bg, Result.Fg, 0.1);
  Result.AssistantBg := Result.Bg;
  Result.CodeBg := Blend(Result.Bg, Result.Fg, 0.07);
  Result.Border := Blend(Result.Bg, Result.Fg, 0.2);
  if IsDark(Result.Bg) then
  begin
    Result.Error := RGB(241, 112, 112);
    Result.Success := RGB(110, 200, 120);
    Result.Warn := RGB(230, 190, 90);
    Result.Link := RGB(110, 170, 255);
  end
  else
  begin
    Result.Error := RGB(190, 30, 30);
    Result.Success := RGB(20, 130, 50);
    Result.Warn := RGB(170, 110, 0);
    Result.Link := RGB(0, 90, 200);
  end;
  Result.FontSize := ChatFontSize;
end;

function Css(Color: TColor): string;
var
  C: Longint;
begin
  C := ColorToRGB(Color);
  Result := Format('#%.2x%.2x%.2x', [GetRValue(C), GetGValue(C), GetBValue(C)]);
end;

function PaletteJson(const Palette: TChatPalette): string;
var
  Root, Vars: TJSONObject;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('t', 'theme');
    Vars := TJSONObject.Create;
    Vars.AddPair('bg', Css(Palette.Bg));
    Vars.AddPair('fg', Css(Palette.Fg));
    Vars.AddPair('muted', Css(Palette.Muted));
    Vars.AddPair('accent', Css(Palette.Accent));
    Vars.AddPair('userBg', Css(Palette.UserBg));
    Vars.AddPair('assistantBg', Css(Palette.AssistantBg));
    Vars.AddPair('codeBg', Css(Palette.CodeBg));
    Vars.AddPair('border', Css(Palette.Border));
    Vars.AddPair('error', Css(Palette.Error));
    Vars.AddPair('success', Css(Palette.Success));
    Vars.AddPair('warn', Css(Palette.Warn));
    Vars.AddPair('link', Css(Palette.Link));
    Vars.AddPair('font', '''Segoe UI'', ''Malgun Gothic'', sans-serif');
    Vars.AddPair('monoFont', 'Consolas, ''D2Coding'', ''Malgun Gothic'', monospace');
    Vars.AddPair('fontSize', TJSONNumber.Create(Palette.FontSize));
    Root.AddPair('vars', Vars);
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

procedure PaintPlain(Root: TComponent; const Palette: TChatPalette; HighContrast: Boolean);
var
  Index: Integer;
  Item: TComponent;
begin
  for Index := 0 to Root.ComponentCount - 1 do
  begin
    Item := Root.Components[Index];
    { The IDE style paints over Color/Font.Color; high contrast must opt out of it. Themed
      check boxes ignore Font.Color, so they keep the IDE style. }
    if (Item is TControl) and not (Item is TCheckBox) then
      if HighContrast then
        TControl(Item).StyleElements := [seBorder]
      else
        TControl(Item).StyleElements := [seFont, seClient, seBorder];
    if Item is TPanel then
    begin
      TPanel(Item).ParentBackground := False;
      TPanel(Item).Color := Palette.Bg;
      TPanel(Item).Font.Color := Palette.Fg;
    end
    else if Item is TLabel then
    begin
      { Notes are drawn greyed (clGrayText); keep them apart from the style's font colour. }
      if TLabel(Item).Font.Color = clGrayText then
      begin
        TLabel(Item).StyleElements := TLabel(Item).StyleElements - [seFont];
        TLabel(Item).Font.Color := Palette.Muted;
      end
      else
        TLabel(Item).Font.Color := Palette.Fg;
    end
    else if Item is TCustomMemo then
    begin
      TMemo(Item).Color := Palette.Bg;
      TMemo(Item).Font.Color := Palette.Fg;
    end
    else if Item is TCheckBox then
      TCheckBox(Item).Font.Color := Palette.Fg
    else if HighContrast and (Item is TWinControl) and ((Item is TCustomEdit) or
      (Item is TCustomListBox) or (Item is TCustomComboBox)) then
    begin
      TEdit(Item).Color := Palette.Bg;
      TEdit(Item).Font.Color := Palette.Fg;
    end;
    { Dialog pages own their controls (settings pages, panels). }
    if Item.ComponentCount > 0 then
      PaintPlain(Item, Palette, HighContrast);
  end;
end;

procedure ApplyVclTheme(Root: TComponent);
var
  Services: IOTAIDEThemingServices250;
begin
  Services := Theming;
  if not HighContrastEnabled and (Services <> nil) and Services.IDEThemingEnabled then
    Services.ApplyTheme(Root);
  PaintPlain(Root, CurrentPalette, HighContrastEnabled);
end;

{ ApplyTheme walks the components a component owns; pages that own their own controls need it too. }
procedure ApplyOwned(const Services: IOTAIDEThemingServices250; Root: TComponent);
var
  Index: Integer;
begin
  for Index := 0 to Root.ComponentCount - 1 do
    if Root.Components[Index].ComponentCount > 0 then
    begin
      Services.ApplyTheme(Root.Components[Index]);
      ApplyOwned(Services, Root.Components[Index]);
    end;
end;

procedure ThemeForm(Form: TCustomForm);
var
  Services: IOTAIDEThemingServices250;
  Palette: TChatPalette;
begin
  Services := Theming;
  Palette := CurrentPalette;
  if (Services <> nil) and Services.IDEThemingEnabled and not HighContrastEnabled then
  begin
    if not GRegistered.Contains(Form.ClassType) then
    begin
      Services.RegisterFormClass(TCustomFormClass(Form.ClassType));
      GRegistered.Add(Form.ClassType);
    end;
    Services.ApplyTheme(Form);
    ApplyOwned(Services, Form);
  end
  else
  begin
    Form.StyleElements := [seBorder];
    TForm(Form).Color := Palette.Bg;
    TForm(Form).Font.Color := Palette.Fg;
  end;
  PaintPlain(Form, Palette, HighContrastEnabled);
end;

{ The caption is drawn by Windows: dark with a dark theme (Windows 10 20H1 and later). Set on
  every window creation, since style changes recreate the window. }
procedure TAgentForm.CreateWnd;
const
  DwmUseImmersiveDarkMode = 20;
var
  Dark: BOOL;
begin
  inherited CreateWnd;
  Dark := BOOL(IsDark(CurrentPalette.Bg));
  DwmSetWindowAttribute(Handle, DwmUseImmersiveDarkMode, @Dark, SizeOf(Dark));
end;

procedure TThemeWatch.ChangingTheme;
begin
end;

procedure TThemeWatch.ChangedTheme;
begin
  if Assigned(GOnThemeChanged) then
    GOnThemeChanged;
end;

procedure InstallThemeWatch(const OnChanged: TThemeChanged);
var
  Services: IOTAIDEThemingServices250;
begin
  GOnThemeChanged := OnChanged;
  if GWatchIndex >= 0 then
    Exit;
  Services := Theming;
  if Services <> nil then
    GWatchIndex := Services.AddNotifier(TThemeWatch.Create);
end;

procedure RemoveThemeWatch;
var
  Services: IOTAIDEThemingServices250;
begin
  GOnThemeChanged := nil;
  if GWatchIndex < 0 then
    Exit;
  Services := Theming;
  if Services <> nil then
    Services.RemoveNotifier(GWatchIndex);
  GWatchIndex := -1;
end;

initialization
  GRegistered := TList<TClass>.Create;

finalization
  RemoveThemeWatch;
  GRegistered.Free;

end.
