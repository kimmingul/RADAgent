unit DesignProgramTests;

{ Tests for RADAgent.DesignProgram (the program source and Custom_Styles edits that give a VCL
  project its style), RADAgent.DesignDoc (DESIGN.md from each embedded preset), the style catalog
  and RADAgent.PropValues (DESIGN.md colors and identifiers as property text). }

interface

uses
  TestCheck;

procedure RunDesignProgramTests(const Check: TCheckProc);

implementation

uses
  System.SysUtils, System.Generics.Collections, System.Win.Registry, Winapi.Windows, System.TypInfo, Vcl.Graphics,
  RADAgent.DesignProgram, RADAgent.DesignCatalog, RADAgent.DesignDoc, RADAgent.DesignTokens, RADAgent.PropValues;

const
  Dpr = 'program Demo;'#13#10#13#10 +
    '{ uses nothing here }'#13#10 +
    'uses'#13#10 +
    '  Vcl.Forms,'#13#10 +
    '  Main in ''Main.pas'' {MainForm};'#13#10#13#10 +
    '{$R *.res}'#13#10#13#10 +
    'begin'#13#10 +
    '  Application.Initialize;'#13#10 +
    '  Application.MainFormOnTaskbar := True;'#13#10 +
    '  Application.CreateForm(TMainForm, MainForm);'#13#10 +
    '  Application.Run;'#13#10 +
    'end.'#13#10;
  CppMain = '#include <vcl.h>'#13#10 +
    '#pragma hdrstop'#13#10 +
    'int WINAPI _tWinMain(HINSTANCE, HINSTANCE, LPTSTR, int)'#13#10 +
    '{'#13#10 +
    '    Application->Initialize();'#13#10 +
    '    Application->MainFormOnTaskbar = true;'#13#10 +
    '    Application->Run();'#13#10 +
    '}'#13#10;

procedure ProgramTests(const Check: TCheckProc);
var
  Source, Again, Problem: string;
begin
  Check(SetProgramStyle(Dpr, 'Windows11 Modern Light', False, Source, Problem), 'a VCL .dpr gets a style');
  Check(Source.Contains('{MainForm},'#13#10'  Vcl.Themes,'#13#10'  Vcl.Styles;'),
    'the style units end the uses clause, not the comment that mentions uses');
  Check(Source.Contains('MainFormOnTaskbar := True;'#13#10 +
    '  TStyleManager.TrySetStyle(''Windows11 Modern Light'');'#13#10 +
    '  Application.CreateForm'), 'TrySetStyle follows MainFormOnTaskbar, before the forms');
  Check(SetProgramStyle(Source, 'Windows11 Modern Dark', False, Again, Problem) and
    Again.Contains('TrySetStyle(''Windows11 Modern Dark'')') and not Again.Contains('Modern Light') and
    (Again.CountChar(';') = Source.CountChar(';')), 'a second run changes the call, adds nothing');
  Check((Pos('{$R *.res}', Source) > 0) and (Pos('{$R *.res}', Source, Pos('{$R *.res}', Source) + 1) = 0),
    'a program that links its .res keeps one directive');
  Check(SetProgramStyle(StringReplace(Dpr, '{$R *.res}'#13#10#13#10, '', []), 'Carbon', False, Again, Problem) and
    Again.Contains('Vcl.Styles;'#13#10#13#10'{$R *.res}'#13#10#13#10'begin'),
    'a program without {$R *.res} gets it: Custom_Styles live in the project .res');
  Check(SetProgramStyle(CppMain, 'Carbon', True, Source, Problem) and
    Source.Contains('#include <vcl.h>'#13#10'#include <Vcl.Themes.hpp>'#13#10'#include <Vcl.Styles.hpp>') and
    Source.Contains('true;'#13#10'    TStyleManager::TrySetStyle("Carbon");'),
    'C++Builder: includes after vcl.h, the call after MainFormOnTaskbar');
  Check(not SetProgramStyle('program X; begin end.', 'Carbon', False, Source, Problem) and
    (Source = 'program X; begin end.'), 'no uses clause: refused, source unchanged');
end;

procedure CustomStylesTests(const Check: TCheckProc);
var
  Styles: array of TLinkedStyle;
  Value: string;
begin
  SetLength(Styles, 2);
  Styles[0].Name := 'Windows11 Modern Light';
  Styles[0].Path := '$(BDSCOMMONDIR)\Styles\WindowsModern.vsf';
  Styles[1].Name := 'Carbon';
  Styles[1].Path := '$(BDSCOMMONDIR)\Styles\Carbon.vsf';
  Value := MergeCustomStyles('Carbon|VCLSTYLE|C:\Old\Carbon.vsf', Styles);
  Check(Value = 'Carbon|VCLSTYLE|C:\Old\Carbon.vsf;' +
    '"Windows11 Modern Light|VCLSTYLE|$(BDSCOMMONDIR)\Styles\WindowsModern.vsf"',
    'a listed style stays; a new one with spaces is quoted and appended');
  Check(MergeCustomStyles(Value, Styles) = Value, 'merging again changes nothing');
end;

procedure ComposeTests(const Check: TCheckProc);
var
  Style, Dark: TDesignStyle;
  Id, Doc: string;
  Map: TFrontMatter;
begin
  Style := Default(TDesignStyle);
  Style.FileName := 'Win10Modern.style';
  Style.Framework := 'FMX';
  Style.Name := 'Windows 10 Modern';
  Style.System := 'windows-10';
  Style.Basis := 'name';
  Style.Preset := 'fluent-windows11';
  Style.PresetBasis := 'policy';
  Style.Colors := [TPair<string, string>.Create('background', '#F3F3F3'),
    TPair<string, string>.Create('textDisabled', '#A0A0A0')];
  Dark := Default(TDesignStyle);
  for Id in PresetIds do
  begin
    Check(PresetText(Id) <> '', 'preset ' + Id + ' is embedded');
    Doc := ComposeDesignDoc('Demo', Style, Dark, Id);
    Map := ReadFrontMatter(Doc);
    try
      Check(Map.ContainsKey('radstudio.styleFile') and (Map['radstudio.styleFile'] = 'Win10Modern.style') and
        (Map['radstudio.preset'] = Id), Id + ': radstudio block');
      Check(Map.ContainsKey('colors.style-background') and Map.ContainsKey('colors.style-text-disabled') and
        Map.ContainsKey('colors.primary'), Id + ': style colors join the preset colors');
      Check((Length(Dimensions(Map, 'spacing')) >= 3) and (Length(FontSizes(Map)) >= 3) and
        (Length(FontFamilies(Map)) >= 1), Id + ': spacing and type ramp are readable');
      Check(Map['name'] = 'Demo design', Id + ': the preset''s own name is replaced');
    finally
      Map.Free;
    end;
    Check(Pos('## Overview', Doc) < Pos('## Colors', Doc), Id + ': section order kept');
  end;
end;

{ Every catalogued style points at an embedded preset; a vendor-verified match stays a match. }
procedure CatalogTests(const Check: TCheckProc);
const
  Frameworks: array[0..1] of string = ('VCL', 'FMX');
var
  Framework: string;
  Style: TDesignStyle;
  Count: Integer;
begin
  { The IDE sets BDS; a console test run may not have it. }
  if GetEnvironmentVariable('BDS') = '' then
    with TRegistry.Create(KEY_READ) do
    try
      RootKey := HKEY_LOCAL_MACHINE;
      if OpenKeyReadOnly('SOFTWARE\WOW6432Node\Embarcadero\BDS\37.0') then
        SetEnvironmentVariable('BDS', PChar(ExcludeTrailingPathDelimiter(ReadString('RootDir'))));
    finally
      Free;
    end;
  Count := 0;
  for Framework in Frameworks do
    for Style in InstalledStyles(Framework) do
    begin
      Inc(Count);
      Check(PresetText(Style.Preset) <> '', Style.FileName + ': its preset ' + Style.Preset + ' exists');
      Check((Style.Basis <> 'name') or (Style.PresetBasis = 'policy'),
        Style.FileName + ': a name-only provenance is never a preset match');
    end;
  Check(Count > 0, 'the catalog lists installed styles');
  Check(FindStyle('VCL', 'WindowsModern', Style) and (Style.PresetBasis = 'match') and Style.Loadable and
    (Style.MacroPath = '$(BDSCOMMONDIR)\Styles\WindowsModern.vsf'), 'WindowsModern.vsf: Windows 11, loadable, linked by macro path');
  Check(FindStyle('FMX', 'Material_3.0', Style) and not Style.Loadable,
    'Material_3.0.fmxstyle is a style designer project, not loadable by an application');
end;

procedure PropValueTests(const Check: TCheckProc);
var
  Font: TFont;
begin
  Font := TFont.Create;
  try
    Check(SetOrdinalText(Font, GetPropInfo(Font, 'Color'), '#0067C0') and (Font.Color = $00C06700),
      'a DESIGN.md hex color becomes a VCL TColor ($00BBGGRR)');
    Check(SetOrdinalText(Font, GetPropInfo(Font, 'Color'), 'clWindowText') and (Font.Color = clWindowText),
      'a system color name is accepted');
    Check(not SetOrdinalText(Font, GetPropInfo(Font, 'Height'), '#0067C0'),
      'hex text is only a color for color types');
    try
      SetOrdinalText(Font, GetPropInfo(Font, 'Color'), '#FF0067C0');
      Check(False, 'an 8-digit color is refused');
    except
      on E: EConvertError do
        Check(E.Message.Contains('#RRGGBB'), 'an 8-digit color is refused with the accepted forms');
    end;
  finally
    Font.Free;
  end;
end;

procedure RunDesignProgramTests(const Check: TCheckProc);
begin
  PropValueTests(Check);
  ProgramTests(Check);
  CustomStylesTests(Check);
  ComposeTests(Check);
  CatalogTests(Check);
end;

end.
