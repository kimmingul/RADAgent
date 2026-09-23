unit DelphiAgent.DirtyBuffers;

{ Writes dirty editor text under %TEMP%\DelphiAgent. Does not save the IDE buffer. }

interface

uses
  System.SysUtils;

function SnapshotFileName(const TempRoot, SourceFile: string; Index: Integer): string;
function WriteSnapshots(const TempRoot: string; const Files, Texts: TArray<string>): TArray<string>;
procedure RememberSnapshots(const Files, Texts: TArray<string>);
function SnapshotConflicts(const FileName, CurrentText: string): Boolean;

implementation

uses
  System.IOUtils, System.Generics.Collections;

var
  GSnapshotText: TDictionary<string, string>;

function SnapshotKey(const FileName: string): string;
begin
  Result := AnsiLowerCase(ExpandFileName(FileName));
end;

function SnapshotFileName(const TempRoot, SourceFile: string; Index: Integer): string;
var
  Leaf: string;
begin
  Leaf := TPath.GetFileName(SourceFile);
  if Leaf = '' then
    Leaf := 'buffer.txt';
  Result := IncludeTrailingPathDelimiter(TempRoot) + 'snap-' + IntToStr(Index) + '-' + Leaf;
end;

function WriteSnapshots(const TempRoot: string; const Files, Texts: TArray<string>): TArray<string>;
var
  Index, Count: Integer;
begin
  Count := Length(Files);
  if Length(Texts) < Count then
    Count := Length(Texts);
  SetLength(Result, Count);
  if Count = 0 then
    Exit;
  ForceDirectories(TempRoot);
  for Index := 0 to Count - 1 do
  begin
    Result[Index] := SnapshotFileName(TempRoot, Files[Index], Index);
    TFile.WriteAllText(Result[Index], Texts[Index], TEncoding.UTF8);
  end;
end;

procedure RememberSnapshots(const Files, Texts: TArray<string>);
var
  Index, Count: Integer;
begin
  if GSnapshotText = nil then
    GSnapshotText := TDictionary<string, string>.Create
  else
    GSnapshotText.Clear;
  Count := Length(Files);
  if Length(Texts) < Count then
    Count := Length(Texts);
  for Index := 0 to Count - 1 do
    GSnapshotText.AddOrSetValue(SnapshotKey(Files[Index]), Texts[Index]);
end;

function SnapshotConflicts(const FileName, CurrentText: string): Boolean;
var
  Saved: string;
begin
  Result := False;
  if (GSnapshotText = nil) or not GSnapshotText.TryGetValue(SnapshotKey(FileName), Saved) then
    Exit;
  Result := Saved <> CurrentText;
end;

initialization

finalization
  GSnapshotText.Free;

end.
