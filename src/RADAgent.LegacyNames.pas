unit RADAgent.LegacyNames;

{ RADAgent was called DelphiAgent. Settings and notes kept under the old name move once to the
  new one, so an update keeps them: the IDE registry key, a project's .omp overlay, the /btw
  notes folder and the git checkpoint refs. No ToolsAPI. }

interface

{ Moves <BaseKey>\DelphiAgent to NewKey (HKCU) when NewKey does not exist yet. }
procedure MigrateRegistryKey(const BaseKey, NewKey: string);
{ <project>\.omp\delphiagent.yml becomes NewPath when NewPath does not exist yet. }
procedure MigrateProjectOverlay(const ProjectDir, NewPath: string);
{ %LOCALAPPDATA%\DelphiAgent\btw becomes NewDir when NewDir does not exist yet. }
procedure MigrateBtwNotes(const NewDir: string);

const
  LegacyRefs = 'refs/delphiagent/';

implementation

uses
  System.SysUtils, System.IOUtils, System.Win.Registry, Winapi.Windows;

procedure MigrateRegistryKey(const BaseKey, NewKey: string);
var
  Reg: TRegistry;
  OldKey: string;
begin
  OldKey := BaseKey + '\DelphiAgent';
  Reg := TRegistry.Create(KEY_ALL_ACCESS);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.KeyExists(OldKey) and not Reg.KeyExists(NewKey) then
      Reg.MoveKey(OldKey, NewKey, True);
  except
    { A settings move that fails leaves defaults; never block the IDE over it. }
  end;
  Reg.Free;
end;

procedure MigrateProjectOverlay(const ProjectDir, NewPath: string);
var
  OldPath: string;
begin
  OldPath := TPath.Combine(TPath.Combine(ProjectDir, '.omp'), 'delphiagent.yml');
  if FileExists(OldPath) and not FileExists(NewPath) then
    RenameFile(OldPath, NewPath);
end;

procedure MigrateBtwNotes(const NewDir: string);
var
  OldDir: string;
begin
  OldDir := IncludeTrailingPathDelimiter(GetEnvironmentVariable('LOCALAPPDATA')) + 'DelphiAgent\btw';
  if DirectoryExists(OldDir) and not DirectoryExists(NewDir) then
  begin
    ForceDirectories(ExtractFileDir(ExcludeTrailingPathDelimiter(NewDir)));
    try
      TDirectory.Move(OldDir, NewDir);
    except
    end;
  end;
end;

end.
