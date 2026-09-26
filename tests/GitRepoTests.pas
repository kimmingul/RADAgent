unit GitRepoTests;

{ Checkpoints on a throwaway repository: they keep the whole tree and the prompt, never move the
  user's branch, and going back restores changed files and removes files added later. }

interface

uses
  TestCheck;

procedure RunGitRepoTests(const Check: TCheckProc);

implementation

uses
  System.SysUtils, System.IOUtils, Winapi.Windows, RADAgent.GitRepo, RADAgent.Options, RADAgent.RpcJson;

procedure RunGitRepoTests(const Check: TCheckProc);
var
  Dir, Root, Commit, Current, Problem, HeadBefore: string;
  Seq, Safety: Integer;
  Points: TArray<TCheckpoint>;
  Renamed: TCheckpoint;
begin
  if GitExecutable = '' then
  begin
    Check(False, 'git is installed');
    Exit;
  end;
  Dir := AgentTempRoot + 'git-tests-' + FormatDateTime('hhnnsszzz', Now);
  ForceDirectories(Dir);
  try
    Check(GitRoot(Dir) = '', 'a fresh folder is not a repository');
    Check(InitRepo(Dir, Problem), 'git init with a first commit: ' + Problem);
    Check(SameText(ExcludeTrailingPathDelimiter(GitRoot(Dir)), ExcludeTrailingPathDelimiter(Dir)),
      'the folder is its own repository');
    Check(FileExists(TPath.Combine(Dir, '.gitignore')), 'a Delphi .gitignore is written');
    Root := GitRoot(Dir);
    TFile.WriteAllText(TPath.Combine(Dir, 'Unit1.pas'), 'unit Unit1; // v1', TEncoding.UTF8);
    HeadBefore := TFile.ReadAllText(TPath.Combine(Dir, '.git\HEAD'));
    Check(CreateCheckpoint(Root, CheckpointRefs, '첫 메시지'#10'둘째 줄', Seq, Commit, Problem) and (Seq = 1),
      'first checkpoint is number 1: ' + Problem);
    Check(TFile.ReadAllText(TPath.Combine(Dir, '.git\HEAD')) = HeadBefore, 'a checkpoint does not move HEAD');
    Points := ListCheckpoints(Root);
    Check((Length(Points) = 1) and (Points[0].Commit = Commit) and (Points[0].Prompt = '첫 메시지'#10'둘째 줄'),
      'the checkpoint keeps its commit and the whole prompt');
    TFile.WriteAllText(TPath.Combine(Dir, 'Unit1.pas'), 'unit Unit1; // v2', TEncoding.UTF8);
    TFile.WriteAllText(TPath.Combine(Dir, 'Unit2.pas'), 'unit Unit2;', TEncoding.UTF8);
    Check(CreateCheckpoint(Root, SafetyRefs, 'before going back', Safety, Current, Problem),
      'the state before going back is kept: ' + Problem);
    Check(Length(ListCheckpoints(Root)) = 1, 'that safety checkpoint is not listed with the messages');
    Check(RestoreCheckpoint(Root, Commit, Current, Problem), 'going back succeeds: ' + Problem);
    Check(TFile.ReadAllText(TPath.Combine(Dir, 'Unit1.pas'), TEncoding.UTF8).Contains('// v1'),
      'a changed file is back to the checkpoint');
    Check(not FileExists(TPath.Combine(Dir, 'Unit2.pas')), 'a file added after the checkpoint is removed');
    Check(RestoreCheckpoint(Root, Current, Commit, Problem) and
      TFile.ReadAllText(TPath.Combine(Dir, 'Unit1.pas'), TEncoding.UTF8).Contains('// v2') and
      FileExists(TPath.Combine(Dir, 'Unit2.pas')), 'going back can itself be undone');
    Check(BranchAtCheckpoint(Root, Commit, 'radagent/test', Problem) and
      TFile.ReadAllText(TPath.Combine(Dir, '.git\HEAD')).Contains('refs/heads/radagent/test'),
      'a branch at the checkpoint becomes the current branch: ' + Problem);
    { A file renamed after the checkpoint: its new name is a file the checkpoint did not have. }
    TFile.Move(TPath.Combine(Dir, 'Unit1.pas'), TPath.Combine(Dir, 'Renamed.pas'));
    Check(CreateCheckpoint(Root, SafetyRefs, 'renamed', Safety, Current, Problem) and
      RestoreCheckpoint(Root, Commit, Current, Problem) and FileExists(TPath.Combine(Dir, 'Unit1.pas')) and
      not FileExists(TPath.Combine(Dir, 'Renamed.pas')), 'going back undoes a rename without leaving both files');
    { Which message a checkpoint belongs to: the same words sent twice are two messages. }
    Renamed := Default(TCheckpoint);
    Renamed.Prompt := 'Fix build';
    Points := [Renamed, Renamed];
    Points[0].Seq := 1;
    Points[0].Stamp := 1000;
    Points[1].Seq := 2;
    Points[1].Stamp := 5000;
    Check((CheckpointFor(Points, 0, 1200, 'Fix build') = 1) and (CheckpointFor(Points, 1200, 5100, 'Fix build') = 2),
      'each message gets the checkpoint taken just before it, not a later one with the same text');
    Check(CheckpointFor(Points, 5100, 9000, 'Fix build') = 0, 'a message without its own checkpoint gets none');
    Check(CheckpointFor(Points, 0, 1200, 'Other text') = 0, 'a checkpoint of other words is not taken');
    Check(Abs(UnixMs - Int64(Round((Now - EncodeDate(1970, 1, 1)) * MSecsPerDay))) < 24 * 3600 * 1000,
      'checkpoint time uses the ms-since-1970 clock omp stamps messages with');
  finally
    { git object files are read-only. }
    for Current in TDirectory.GetFiles(Dir, '*', TSearchOption.soAllDirectories) do
      SetFileAttributes(PChar(Current), FILE_ATTRIBUTE_NORMAL);
    TDirectory.Delete(Dir, True);
  end;
end;

end.
