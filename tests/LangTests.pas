unit LangTests;

{ Tests for RADAgent.Lang and the tables in src\lang. The tables are linked into the test
  program the same way as into the package (RADAgentResources.rc). }

interface

uses
  TestCheck;

procedure RunLangTests(const Check: TCheckProc);

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, System.RegularExpressions,
  System.Generics.Collections, System.Generics.Defaults, RADAgent.Lang;

function LoadFile(const Code: string): TJSONObject;
var
  Path: string;
begin
  Path := TPath.Combine(ExtractFilePath(ParamStr(0)), '..\src\lang\' + Code + '.json');
  Result := TJSONObject.ParseJSONValue(TFile.ReadAllText(Path, TEncoding.UTF8)) as TJSONObject;
end;

(* Placeholders a translator must keep: Format specs (%s, %0:s, %%) and page braces ({0}). *)
function Placeholders(const Text: string): string;
var
  Found: TList<string>;
  Match: TMatch;
begin
  Found := TList<string>.Create;
  try
    for Match in TRegEx.Matches(Text, '%%|%(\d+:)?-?\d*(\.\d+)?[sdfxgnmpue]|\{\d+\}') do
      Found.Add(Match.Value);
    Found.Sort(TComparer<string>.Default);
    Result := string.Join(' ', Found.ToArray);
  finally
    Found.Free;
  end;
end;

procedure TestTablesMatchEnglish(const Check: TCheckProc);
var
  English, Other: TJSONObject;
  Language: TLanguage;
  Pair: TJSONPair;
  Missing, Broken: Integer;
begin
  English := LoadFile('en');
  try
    for Language := lgJapanese to High(TLanguage) do
    begin
      Other := LoadFile(LanguageCodes[Language]);
      try
        Missing := 0;
        Broken := 0;
        { Keys contain dots, so look them up by name; TryGetValue would read them as paths. }
        for Pair in English do
          if Other.GetValue(Pair.JsonString.Value) = nil then
            Inc(Missing)
          else if Placeholders(Other.GetValue(Pair.JsonString.Value).Value) <>
            Placeholders(Pair.JsonValue.Value) then
            Inc(Broken);
        Check(Missing = 0, LanguageCodes[Language] + '.json has every English key');
        Check(Broken = 0, LanguageCodes[Language] + '.json keeps every placeholder');
        Check(Other.Count = English.Count, LanguageCodes[Language] + '.json has no extra keys');
      finally
        Other.Free;
      end;
    end;
  finally
    English.Free;
  end;
end;

procedure TestSwitching(const Check: TCheckProc);
var
  English, Korean: string;
  Generation: Integer;
begin
  SelectLanguage('en');
  English := Tr('settingsdialog.language');
  Check((TrF('ompprobe.countItems', [1]) = '1 item') and (TrF('ompprobe.countItems', [2]) = '2 items'),
    'a first value of 1 picks the singular wording');
  Generation := LanguageGeneration;
  SelectLanguage('ko');
  Korean := Tr('settingsdialog.language');
  Check(English = 'Language', 'English table is linked');
  Check((Korean <> '') and (Korean <> English) and (Korean <> 'settingsdialog.language'),
    'switching to Korean changes the text');
  Check(LanguageGeneration <> Generation, 'switching bumps the generation');
  Check(CurrentLanguage = lgKorean, 'current language follows the switch');
  Check(Tr('no.such.key') = 'no.such.key', 'an unknown key shows as itself');
  Check(TrF('options.pipeClosedDetail', ['x']).EndsWith('x'), 'TrF fills the placeholder');
  Check(PageStrings.Contains('"lang":"ko"') and PageStrings.Contains('page.composer.placeholder'),
    'page strings carry the language and the page keys');
  SelectLanguage('xx');
  Check(CurrentLanguage = SystemLanguage, 'an unknown code falls back to the system language');
  SelectLanguage('en');
end;

procedure RunLangTests(const Check: TCheckProc);
begin
  TestTablesMatchEnglish(Check);
  TestSwitching(Check);
end;

end.
