unit RADAgent.RpcQueue;

{ omp's pending-message queue (omp 18.4.4 and later): the queue_update event and get_state's
  queuedMessages list the text of every steering and follow-up message omp has not read yet, and
  remove_queued_message calls one off. Older omp sends none of these. No VCL, no ToolsAPI. }

interface

uses
  System.JSON;

type
  TQueueSnapshot = record
    Steering, FollowUp: TArray<string>;
  end;

{ The two lists of a queue_update event or of get_state's queuedMessages object. }
function ReadQueueSnapshot(Obj: TJSONObject; out Snapshot: TQueueSnapshot): Boolean;
function ParseQueueUpdate(const Line: string; out Snapshot: TQueueSnapshot): Boolean;
{ Queue: 'steering' or 'followUp'; Message: the text omp listed. }
function BuildRemoveQueuedFrame(const Id, Message, Queue: string): string;
{ The remove_queued_message response. Removed: omp dropped the message; False when omp had
  already read it or refused the command. }
function ParseRemoveQueued(const Line: string; out Removed: Boolean): Boolean;

implementation

uses
  System.Generics.Collections, RADAgent.RpcJson;

function StringList(Value: TJSONValue): TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  if Value is TJSONArray then
    for Index := 0 to TJSONArray(Value).Count - 1 do
      if TJSONArray(Value).Items[Index] is TJSONString then
        Result := Result + [TJSONString(TJSONArray(Value).Items[Index]).Value];
end;

function ReadQueueSnapshot(Obj: TJSONObject; out Snapshot: TQueueSnapshot): Boolean;
begin
  Snapshot := Default(TQueueSnapshot);
  Result := (Obj <> nil) and (Obj.GetValue('steering') is TJSONArray) and
    (Obj.GetValue('followUp') is TJSONArray);
  if not Result then
    Exit;
  Snapshot.Steering := StringList(Obj.GetValue('steering'));
  Snapshot.FollowUp := StringList(Obj.GetValue('followUp'));
end;

function ParseQueueUpdate(const Line: string; out Snapshot: TQueueSnapshot): Boolean;
var
  Root: TJSONObject;
begin
  Snapshot := Default(TQueueSnapshot);
  Root := JsonObject(Line);
  try
    Result := (JsonStr(Root, 'type') = 'queue_update') and ReadQueueSnapshot(Root, Snapshot);
  finally
    Root.Free;
  end;
end;

function BuildRemoveQueuedFrame(const Id, Message, Queue: string): string;
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('id', Id);
    Obj.AddPair('type', 'remove_queued_message');
    Obj.AddPair('message', Message);
    Obj.AddPair('queue', Queue);
    Result := Obj.ToJSON;
  finally
    Obj.Free;
  end;
end;

function ParseRemoveQueued(const Line: string; out Removed: Boolean): Boolean;
var
  Root, Data: TJSONObject;
begin
  Removed := False;
  Root := JsonObject(Line);
  try
    Result := (JsonStr(Root, 'type') = 'response') and (JsonStr(Root, 'command') = 'remove_queued_message');
    if not Result or IsJsonFalse(Root.GetValue('success')) then
      Exit;
    Data := JsonChild(Root, 'data');
    Removed := (Data <> nil) and IsJsonTrue(Data.GetValue('removed'));
  finally
    Root.Free;
  end;
end;

end.
