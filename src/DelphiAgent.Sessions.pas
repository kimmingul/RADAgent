unit DelphiAgent.Sessions;

{ Lists omp session files next to the current session (same project bucket) and lets the user
  pick one. Reads only a small prefix of each file. No ToolsAPI. }

interface

type
  TSessionEntry = record
    Path: string;
    Title: string;
    Modified: TDateTime;
    Current: Boolean;
  end;

function ListSessions(const CurrentFile: string): TArray<TSessionEntry>;
{ Modal choice; returns the chosen path or '' when cancelled. }
function ChooseSession(const Entries: TArray<TSessionEntry>): string;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, System.Math,
  System.Generics.Collections, System.Generics.Defaults, DelphiAgent.AskDialog;

const
  MaxEntries = 50;
  PrefixBytes = 16384;

function ReadPrefix(const Path: string): string;
var
  Stream: TFileStream;
  Bytes: TBytes;
begin
  Result := '';
  try
    Stream := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Bytes, Min(Stream.Size, PrefixBytes));
      if Length(Bytes) > 0 then
        Stream.ReadBuffer(Bytes[0], Length(Bytes));
    finally
      Stream.Free;
    end;
    Result := TEncoding.UTF8.GetString(Bytes);
  except
    Result := '';
  end;
end;

function FirstUserText(Obj: TJSONObject): string;
var
  Msg: TJSONObject;
  Content: TJSONValue;
  Items: TJSONArray;
  Index: Integer;
begin
  Result := '';
  if not (Obj.GetValue('message') is TJSONObject) then
    Exit;
  Msg := TJSONObject(Obj.GetValue('message'));
  if Msg.GetValue<string>('role', '') <> 'user' then
    Exit;
  Content := Msg.GetValue('content');
  if Content is TJSONString then
    Exit(TJSONString(Content).Value);
  if Content is TJSONArray then
  begin
    Items := TJSONArray(Content);
    for Index := 0 to Items.Count - 1 do
      if (Items.Items[Index] is TJSONObject) and
        (TJSONObject(Items.Items[Index]).GetValue<string>('type', '') = 'text') then
        Exit(TJSONObject(Items.Items[Index]).GetValue<string>('text', ''));
  end;
end;

{ Title record first, else the first user message. }
function TitleOf(const Path: string): string;
var
  Lines: TArray<string>;
  Line, Kind, FirstUser: string;
  Value: TJSONValue;
  Obj: TJSONObject;
begin
  Result := '';
  FirstUser := '';
  Lines := ReadPrefix(Path).Split([#10]);
  for Line in Lines do
  begin
    Value := TJSONObject.ParseJSONValue(Line.Trim);
    try
      if not (Value is TJSONObject) then
        Continue;
      Obj := TJSONObject(Value);
      Kind := Obj.GetValue<string>('type', '');
      if ((Kind = 'title') or (Kind = 'session')) and (Obj.GetValue<string>('title', '') <> '') then
        Exit(Obj.GetValue<string>('title', ''));
      if (FirstUser = '') and (Kind = 'message') then
        FirstUser := FirstUserText(Obj);
    finally
      Value.Free;
    end;
  end;
  Result := FirstUser.Replace(#13, ' ').Replace(#10, ' ').Trim;
  if Length(Result) > 80 then
    Result := Copy(Result, 1, 80) + '…';
  if Result = '' then
    Result := '(메시지 없음)';
end;

function ListSessions(const CurrentFile: string): TArray<TSessionEntry>;
var
  Dir, Path: string;
  List: TList<TSessionEntry>;
  Entry: TSessionEntry;
begin
  Result := nil;
  Dir := ExtractFileDir(CurrentFile);
  if (Dir = '') or not TDirectory.Exists(Dir) then
    Exit;
  List := TList<TSessionEntry>.Create;
  try
    for Path in TDirectory.GetFiles(Dir, '*.jsonl') do
    begin
      Entry.Path := Path;
      Entry.Modified := TFile.GetLastWriteTime(Path);
      Entry.Current := SameText(Path, CurrentFile);
      Entry.Title := '';
      List.Add(Entry);
    end;
    List.Sort(TComparer<TSessionEntry>.Construct(
      function(const A, B: TSessionEntry): Integer
      begin
        Result := CompareValue(B.Modified, A.Modified);
      end));
    while List.Count > MaxEntries do
      List.Delete(List.Count - 1);
    Result := List.ToArray;
  finally
    List.Free;
  end;
  for var Index := 0 to High(Result) do
    Result[Index].Title := TitleOf(Result[Index].Path);
end;

function ChooseSession(const Entries: TArray<TSessionEntry>): string;
var
  Items: TStringList;
  Index: Integer;
  Choice, Line: string;
begin
  Result := '';
  if Length(Entries) = 0 then
    Exit;
  Items := TStringList.Create;
  try
    for Index := 0 to High(Entries) do
    begin
      Line := Format('%d. %s  %s', [Index + 1, FormatDateTime('yyyy-mm-dd hh:nn',
        Entries[Index].Modified), Entries[Index].Title]);
      if Entries[Index].Current then
        Line := Line + '  (현재)';
      Items.Add(Line);
    end;
    if not AskChoice('세션 전환', Items, Choice) then
      Exit;
    Index := Items.IndexOf(Choice);
    if Index >= 0 then
      Result := Entries[Index].Path;
  finally
    Items.Free;
  end;
end;

end.
