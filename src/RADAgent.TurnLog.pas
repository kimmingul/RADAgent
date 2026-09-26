unit RADAgent.TurnLog;

{ When each turn started and ended as RAD Agent saw it, kept per project (one JSON object per
  line under %LOCALAPPDATA%\RADAgent\turns). omp records no answer for a turn stopped before any
  output, so a reloaded conversation takes the end time of such turns from here. No ToolsAPI. }

interface

uses
  RADAgent.RpcResponses;

{ The log of the project in ProjectDir. }
function TurnLogFile(const ProjectDir: string): string;
procedure AppendTurn(const FileName: string; StartedAt, EndedAt: Int64; Stopped: Boolean);
{ A user message omp recorded with no answer after it gets the end time (CompletedAt) and stop of
  the logged turn that started after the previous user message and no later than it. A turn is
  unanswered when it ended before the next user message; one sent while it ran is not a turn. }
procedure MergeTurns(const FileName: string; var Items: TArray<THistoryItem>);

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Hash, RADAgent.RpcJson;

const
  { Past this size the oldest half goes. }
  MaxLogBytes = 512 * 1024;

type
  TTurn = record
    StartedAt, EndedAt: Int64;
    Stopped: Boolean;
  end;

function TurnLogFile(const ProjectDir: string): string;
begin
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('LOCALAPPDATA')) + 'RADAgent\turns\' +
    THashMD5.GetHashString(LowerCase(ExcludeTrailingPathDelimiter(ProjectDir))) + '.jsonl';
end;

procedure AppendTurn(const FileName: string; StartedAt, EndedAt: Int64; Stopped: Boolean);
var
  Lines: TStringList;
  Keep: Integer;
begin
  ForceDirectories(ExtractFileDir(FileName));
  if FileExists(FileName) and (TFile.GetSize(FileName) > MaxLogBytes) then
  begin
    Lines := TStringList.Create;
    try
      Lines.LoadFromFile(FileName, TEncoding.UTF8);
      Keep := Lines.Count div 2;
      while Lines.Count > Keep do
        Lines.Delete(0);
      Lines.SaveToFile(FileName, TEncoding.UTF8);
    finally
      Lines.Free;
    end;
  end;
  TFile.AppendAllText(FileName, Format('{"started":%d,"ended":%d,"stopped":%s}', [StartedAt, EndedAt,
    LowerCase(BoolToStr(Stopped, True))]) + sLineBreak, TEncoding.UTF8);
end;

function LoadTurns(const FileName: string): TArray<TTurn>;
var
  Line: string;
  Obj: TJSONObject;
  Turn: TTurn;
begin
  Result := nil;
  if not FileExists(FileName) then
    Exit;
  for Line in TFile.ReadAllLines(FileName, TEncoding.UTF8) do
  begin
    Obj := JsonObject(Line);
    if Obj = nil then
      Continue;
    try
      Turn.StartedAt := JsonInt(Obj, 'started');
      Turn.EndedAt := JsonInt(Obj, 'ended');
      Turn.Stopped := IsJsonTrue(Obj.GetValue('stopped'));
      if (Turn.StartedAt > 0) and (Turn.EndedAt >= Turn.StartedAt) then
        Result := Result + [Turn];
    finally
      Obj.Free;
    end;
  end;
end;

procedure MergeTurns(const FileName: string; var Items: TArray<THistoryItem>);
var
  Turns: TArray<TTurn>;
  Turn: TTurn;
  Index: Integer;
  After, NextSent: Int64;
begin
  Turns := LoadTurns(FileName);
  if Turns = nil then
    Exit;
  After := 0;
  for Index := 0 to High(Items) do
  begin
    if Items[Index].Role <> 'user' then
      Continue;
    NextSent := High(Int64);
    if Index < High(Items) then
      if Items[Index + 1].Role = 'user' then
        NextSent := Items[Index + 1].Timestamp
      else
        NextSent := -1;
    if (NextSent >= 0) and (Items[Index].Timestamp > 0) then
      for Turn in Turns do
        if (Turn.StartedAt > After) and (Turn.StartedAt <= Items[Index].Timestamp) and
          (Turn.EndedAt <= NextSent) then
        begin
          Items[Index].CompletedAt := Turn.EndedAt;
          Items[Index].Stopped := Turn.Stopped;
        end;
    if Items[Index].Timestamp > 0 then
      After := Items[Index].Timestamp;
  end;
end;

end.
