unit RADAgent.CppLsp;

{ clangd for C++Builder projects (RAD Studio ships no C++ language server omp can use). Before
  omp starts: a compilation database in <project>\.omp\clangd\compile_commands.json built from
  what the platform's compiler really uses (its header folders, target, C++ standard and the
  Embarcadero macros), the project's include paths and defines, and __published=public; then
  <project>\.omp\lsp.json points omp at clangd. clangd is the user's own install (settings or PATH).
  Stock clangd does not know __property, so two errors always show (see CppLspNoise). Main
  thread only. }

interface

uses
  RADAgent.ProjectProfile;

const
  { For omp's guide: what to ignore from clangd. }
  CppLspNoise = 'clangd does not know C++Builder''s __property: ignore its errors about ' +
    '__property/read in System.hpp, "too many errors emitted", and "No matching constructor for initialization of ''TForm''" ' +
    '(also TFrame/TDataModule), and on Win32 "function declared ''fastcall'' here was previously ' +
    'declared without calling convention" at constructors; VCL/FMX properties (Caption, Text) have ' +
    'no hover or definition. ' +
    'rad.compile is the final check.';

{ clangd.exe from the setting or PATH, '' when there is none. }
function ClangdExecutable: string;
{ Writes the compilation database and .omp\lsp.json; False when clangd or the compiler is missing. }
function EnsureClangd(const Profile: TProjectProfile): Boolean;

implementation

uses
  System.SysUtils, System.StrUtils, System.Classes, System.IOUtils, System.JSON, System.RegularExpressions,
  System.Generics.Collections, Winapi.Windows, ToolsAPI, RADAgent.AgentSettings,
  RADAgent.IdeContext, RADAgent.CppDiagnostics, RADAgent.ProcessRun, RADAgent.Options;

type
  TCompilerFacts = record
    Target, Std: string;
    Includes, Defines: TArray<string>;
  end;

var
  { Per compiler path: running it takes a second or two. }
  GFacts: TDictionary<string, TCompilerFacts>;

function ClangdExecutable: string;
var
  Buf: array[0..MAX_PATH] of Char;
  Part: PChar;
begin
  Result := Trim(ClangdPath);
  if Result <> '' then
  begin
    if DirectoryExists(Result) then
      Result := TPath.Combine(Result, 'clangd.exe');
    if not FileExists(Result) then
      Result := '';
    Exit;
  end;
  Part := nil;
  if SearchPath(nil, 'clangd.exe', nil, MAX_PATH, Buf, Part) > 0 then
    Result := PChar(@Buf[0]);
end;

{ Macros stock clang does not define for the GNU target: the compiler's own names without a
  leading double underscore (_WIN32, _M_IX86, UNICODE...) and the Embarcadero version macros. }
function WantedMacro(const Name: string): Boolean;
begin
  Result := not Name.StartsWith('__') or TRegEx.IsMatch(Name,
    '^(__BORLANDC__|__CODEGEARC\w*|__BCPLUSPLUS__|__TURBOC__|__WIN32__|__WIN64__)$');
end;

{ What Compiler really passes to its front end ("-###") and defines ("-dM -E"). }
function CompilerFacts(const Compiler: string): TCompilerFacts;
var
  Empty, Output, Line, Arg, Driver: string;
  Args: TArray<string>;
  Index: Integer;
  Match: TMatch;
begin
  if GFacts.TryGetValue(LowerCase(Compiler), Result) then
    Exit;
  Result := Default(TCompilerFacts);
  Empty := ProcessTempFile('clangd-probe.cpp');
  TFile.WriteAllText(Empty, '');
  try
    RunCaptured('"' + Compiler + '" -### -c -tW -tU "' + Empty + '"', ExtractFileDir(Empty), Output, 30000);
    for Line in Output.Split([#10]) do
      if Line.Contains('"-cc1"') then
      begin
        Args := nil;
        for Match in TRegEx.Matches(Line, '"((?:[^"\\]|\\.)*)"') do
          Args := Args + [StringReplace(Match.Groups[1].Value, '\\', '\', [rfReplaceAll])];
        for Index := 0 to High(Args) - 1 do
        begin
          Arg := Args[Index];
          if Arg = '-triple' then
            Result.Target := Args[Index + 1]
          else if ((Arg = '-isystem') or (Arg = '-internal-isystem') or (Arg = '-internal-externc-isystem')) and
            not Args[Index + 1].Contains('\lib\clang\') and (IndexText(Args[Index + 1], Result.Includes) < 0) then
            Result.Includes := Result.Includes + [Args[Index + 1]];
          if Arg.StartsWith('-std=') then
            Result.Std := Arg;
        end;
      end;
    { bcc32c and bcc64 take clang's own options through -Xdriver; bcc64x takes them directly. }
    if SameText(ExtractFileName(Compiler), 'bcc64x.exe') then
      Driver := ''
    else
      Driver := '-Xdriver ';
    RunCaptured('"' + Compiler + '" ' + Driver + '-E ' + Driver + '-dM -tW -tU "' + Empty + '"',
      ExtractFileDir(Empty), Output, 30000);
    for Match in TRegEx.Matches(Output, '(?m)^#define (\S+) ?(.*?)\r?$') do
      if WantedMacro(Match.Groups[1].Value) then
        Result.Defines := Result.Defines + [Match.Groups[1].Value + '=' + Match.Groups[2].Value];
  finally
    System.SysUtils.DeleteFile(Empty);
  end;
  { Stock clang has no OMF or Embarcadero ELF targets. Those compilers (bcc32c, bcc64) use the
    Dinkumware headers, which parse as MSVC; bcc64x uses libc++/MinGW (windows-gnu). }
  Result.Target := TRegEx.Replace(Result.Target, '-(omf|elf)$', '-msvc');
  if Result.Target <> '' then
    GFacts.AddOrSetValue(LowerCase(Compiler), Result);
end;

function ActivePlatform(const Project: IOTAProject): string;
var
  Configs: IOTAProjectOptionsConfigurations;
begin
  Result := '';
  if Supports(Project.ProjectOptions, IOTAProjectOptionsConfigurations, Configs) then
    Result := Configs.ActivePlatformName;
end;

function Arguments(const Facts: TCompilerFacts; const Includes, Defines: TArray<string>;
  const FileName: string): TJSONArray;
var
  Item: string;
begin
  Result := TJSONArray.Create;
  Result.Add('clang++').Add('--target=' + Facts.Target).Add('-fborland-extensions')
    .Add('-nostdinc++').Add('-nostdlibinc').Add('-D__published=public');
  if Facts.Std <> '' then
    Result.Add(Facts.Std);
  for Item in Facts.Includes do
    Result.Add('-isystem').Add(Item);
  for Item in Includes do
    Result.Add('-I').Add(Item);
  for Item in Facts.Defines do
    Result.Add('-D' + Item);
  for Item in Defines do
    Result.Add('-D' + Item);
  Result.Add('-c').Add(FileName);
end;

procedure WriteJson(const Path: string; Value: TJSONValue);
begin
  ForceDirectories(ExtractFileDir(Path));
  TFile.WriteAllBytes(Path, TEncoding.UTF8.GetBytes(Value.Format(2)));
end;

function EnsureClangd(const Profile: TProjectProfile): Boolean;
var
  Clangd, Exe, DbDir, FileName: string;
  Project: IOTAProject;
  Facts: TCompilerFacts;
  Includes, Defines, Files: TArray<string>;
  Db: TJSONArray;
  Entry, Root, Servers, Server: TJSONObject;
  Index: Integer;
begin
  Result := False;
  Project := CurrentProject;
  if (Profile.Tools.Language <> 'cpp') or (Project = nil) then
    Exit;
  Clangd := ClangdExecutable;
  Exe := Compiler(ActivePlatform(Project));
  if (Clangd = '') or (Exe = '') then
    Exit;
  Facts := CompilerFacts(Exe);
  if Facts.Target = '' then
    Exit;
  ProjectOptions(Project, ActivePlatform(Project), Includes, Defines);
  Files := nil;
  for Index := 0 to Project.GetModuleCount - 1 do
    if SameText(ExtractFileExt(Project.GetModule(Index).FileName), '.cpp') then
      Files := Files + [Project.GetModule(Index).FileName];
  if FileExists(ChangeFileExt(Project.FileName, '.cpp')) and
    (IndexText(ChangeFileExt(Project.FileName, '.cpp'), Files) < 0) then
    Files := Files + [ChangeFileExt(Project.FileName, '.cpp')];
  DbDir := TPath.Combine(Profile.ProjectDir, '.omp\clangd');
  Db := TJSONArray.Create;
  try
    for FileName in Files do
    begin
      Entry := TJSONObject.Create;
      Entry.AddPair('directory', ExtractFileDir(FileName));
      Entry.AddPair('file', FileName);
      Entry.AddPair('arguments', Arguments(Facts, Includes, Defines, FileName));
      Db.AddElement(Entry);
    end;
    WriteJson(TPath.Combine(DbDir, 'compile_commands.json'), Db);
  finally
    Db.Free;
  end;
  Root := TJSONObject.Create;
  try
    Servers := TJSONObject.Create;
    Root.AddPair('servers', Servers);
    Server := TJSONObject.Create;
    Servers.AddPair('clangd', Server);
    Server.AddPair('command', Clangd);
    { No background index: it would write .cache\ into the project (and every checkpoint). }
    Server.AddPair('args', TJSONArray.Create.Add('--compile-commands-dir=' + DbDir)
      .Add('--background-index=false').Add('--log=error'));
    Server.AddPair('fileTypes', TJSONArray.Create.Add('.cpp').Add('.h').Add('.hpp').Add('.cc').Add('.cxx'));
    Server.AddPair('languageId', 'cpp');
    Server.AddPair('rootMarkers', TJSONArray.Create.Add('*.cbproj').Add('*.groupproj'));
    Server.AddPair('warmupTimeoutMs', TJSONNumber.Create(60000));
    WriteJson(TPath.Combine(Profile.ProjectDir, '.omp\lsp.json'), Root);
  finally
    Root.Free;
  end;
  Result := True;
end;

initialization
  GFacts := TDictionary<string, TCompilerFacts>.Create;

finalization
  GFacts.Free;

end.
