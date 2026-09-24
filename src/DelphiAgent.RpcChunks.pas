unit DelphiAgent.RpcChunks;

{ omp RPC protocol v2: a stdout object over 1 MiB arrives as an uninterrupted run of rpc_chunk
  frames (chunkId, index, count, byteLength, base64 data). This rebuilds the original line and
  rejects interleaved, interrupted, oversized or mis-sized runs, as omp's rpc.md requires.
  No ToolsAPI, no VCL. }

interface

uses
  System.SysUtils;

type
  TRpcChunkAssembler = class
  private
    FId: string;
    FCount, FNext: Integer;
    FByteLength: Int64;
    FBytes: TBytes;
    FError: string;
    procedure Fail(const Reason: string);
  public
    { Line when it is an ordinary frame; the rebuilt frame after the last chunk; '' while a run
      is incomplete or after a broken run (Error says why). }
    function Feed(const Line: string): string;
    { Why the last run was dropped; cleared by the next Feed. }
    property Error: string read FError;
  end;

function IsChunkLine(const Line: string): Boolean;

implementation

uses
  System.JSON, System.NetEncoding, DelphiAgent.RpcJson, DelphiAgent.RpcProtocol;

function IsChunkLine(const Line: string): Boolean;
begin
  { Cheap test first: every chunk frame names its type near the start. }
  Result := (Pos('"rpc_chunk"', Copy(Line, 1, 64)) > 0) and
    (FrameTypeOf(Line) = 'rpc_chunk');
end;

procedure TRpcChunkAssembler.Fail(const Reason: string);
begin
  FError := Reason;
  FId := '';
  FBytes := nil;
  FCount := 0;
  FNext := 0;
end;

function TRpcChunkAssembler.Feed(const Line: string): string;
var
  Obj: TJSONObject;
  Id: string;
  Index, Count, Start: Integer;
  Size: Int64;
  Part: TBytes;
begin
  Result := '';
  FError := '';
  if not IsChunkLine(Line) then
  begin
    if FId <> '' then
      Fail('rpc_chunk run interrupted');
    Exit(Line);
  end;
  Obj := JsonObject(Line);
  try
    Id := JsonStr(Obj, 'chunkId');
    Index := JsonInt(Obj, 'index', -1);
    Count := JsonInt(Obj, 'count', 0);
    Size := JsonInt(Obj, 'byteLength', -1);
    if (Id = '') or (Count <= 0) or (Size < 0) or (Size > MaxReassembledFrameBytes) then
    begin
      Fail('rpc_chunk header invalid');
      Exit;
    end;
    if Index = 0 then
    begin
      if FId <> '' then
        Fail('rpc_chunk runs interleaved');
      FId := Id;
      FCount := Count;
      FByteLength := Size;
      FNext := 0;
      FBytes := nil;
    end;
    if (Id <> FId) or (Index <> FNext) or (Count <> FCount) or (Size <> FByteLength) then
    begin
      Fail('rpc_chunk out of order');
      Exit;
    end;
    try
      Part := TNetEncoding.Base64.DecodeStringToBytes(JsonStr(Obj, 'data'));
    except
      Fail('rpc_chunk data invalid');
      Exit;
    end;
    if Length(FBytes) + Length(Part) > FByteLength then
    begin
      Fail('rpc_chunk longer than byteLength');
      Exit;
    end;
    Start := Length(FBytes);
    SetLength(FBytes, Start + Length(Part));
    if Length(Part) > 0 then
      Move(Part[0], FBytes[Start], Length(Part));
    Inc(FNext);
    if FNext < FCount then
      Exit;
    if Length(FBytes) <> FByteLength then
    begin
      Fail('rpc_chunk shorter than byteLength');
      Exit;
    end;
    Result := TEncoding.UTF8.GetString(FBytes);
    FId := '';
    FBytes := nil;
  finally
    Obj.Free;
  end;
end;

end.
