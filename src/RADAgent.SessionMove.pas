unit RADAgent.SessionMove;

{ Moves an omp session file (JSONL) into another session folder and points its header's cwd at
  the new working folder, so omp lists the conversation for that folder. No ToolsAPI, no VCL. }

interface

{ Moves OldFile into TargetDir with the session header's cwd set to Cwd; returns the new path, or
  OldFile when it is already there, missing, the target exists, or it cannot be moved. }
function MoveSessionFile(const OldFile, TargetDir, Cwd: string): string;

implementation

uses
  System.SysUtils, System.Classes, System.JSON;

function MoveSessionFile(const OldFile, TargetDir, Cwd: string): string;
const
  HeaderLines = 5;
var
  Lines: TStringList;
  Index: Integer;
  Header: TJSONValue;
  Target: string;
  Utf8: TEncoding;
begin
  Result := OldFile;
  if (OldFile = '') or (TargetDir = '') or not FileExists(OldFile) or
    SameText(ExcludeTrailingPathDelimiter(ExtractFileDir(OldFile)), ExcludeTrailingPathDelimiter(TargetDir)) then
    Exit;
  Target := IncludeTrailingPathDelimiter(TargetDir) + ExtractFileName(OldFile);
  if FileExists(Target) then
    Exit;
  Utf8 := TUTF8Encoding.Create(False);
  Lines := TStringList.Create;
  try
    Lines.LineBreak := #10;
    Lines.WriteBOM := False;
    Lines.LoadFromFile(OldFile, Utf8);
    { The header is one of the first lines: the object whose type is "session" carries cwd. }
    for Index := 0 to Lines.Count - 1 do
    begin
      if Index >= HeaderLines then
        Break;
      Header := TJSONObject.ParseJSONValue(Lines[Index]);
      try
        if (Header is TJSONObject) and (TJSONObject(Header).GetValue<string>('type', '') = 'session') then
        begin
          TJSONObject(Header).RemovePair('cwd').Free;
          TJSONObject(Header).AddPair('cwd', Cwd);
          Lines[Index] := Header.ToJSON;
          Break;
        end;
      finally
        Header.Free;
      end;
    end;
    ForceDirectories(TargetDir);
    Lines.SaveToFile(Target, Utf8);
  finally
    Lines.Free;
    Utf8.Free;
  end;
  if DeleteFile(OldFile) then
    Result := Target
  else
    DeleteFile(Target);
end;

end.
