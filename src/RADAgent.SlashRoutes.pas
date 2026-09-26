unit RADAgent.SlashRoutes;

{ Which slash commands RADAgent carries out itself. omp runs the commands it lists over RPC
  (get_available_commands); the ones its terminal UI keeps to itself would reach the model as
  plain text, so RADAgent maps them onto RPC features or its own windows, or says they need
  the terminal. A command omp starts to list over RPC goes to omp again. No VCL, no ToolsAPI. }

interface

type
  TSlashRoute = (
    { Not RADAgent's: omp gets the text. }
    srNone,
    srClear, srDelete, srResume, srTree, srBranch, srFork, srLogin, srCopy, srRestart,
    srSettings, srExtensions, srAgents, srPlan, srHotkeys, srHub, srQueue, srExit, srVersion,
    { Only omp's terminal UI can run it. }
    srTerminalOnly);

{ Name: the command without "/" (lower case); Args: the rest. RpcNames: omp's RPC list. }
function RouteSlash(const Text: string; const RpcNames: TArray<string>; out Name, Args: string): TSlashRoute;
{ The commands RadAgent answers itself, for the / menu: name and argument hint. }
function LocalCommandNames: TArray<string>;
function LocalCommandHint(const Name: string): string;

implementation

uses
  System.SysUtils;

type
  TRouteName = record
    Name: string;
    Route: TSlashRoute;
    Hint: string;
  end;

const
  Routes: array[0..21] of TRouteName = (
    (Name: 'clear'; Route: srClear; Hint: ''),
    (Name: 'delete'; Route: srDelete; Hint: ''),
    (Name: 'resume'; Route: srResume; Hint: ''),
    (Name: 'tree'; Route: srTree; Hint: ''),
    (Name: 'branch'; Route: srBranch; Hint: ''),
    (Name: 'rewind'; Route: srBranch; Hint: ''),
    (Name: 'fork'; Route: srFork; Hint: ''),
    (Name: 'login'; Route: srLogin; Hint: '[provider]'),
    (Name: 'copy'; Route: srCopy; Hint: '[code]'),
    (Name: 'restart'; Route: srRestart; Hint: ''),
    (Name: 'settings'; Route: srSettings; Hint: ''),
    (Name: 'extensions'; Route: srExtensions; Hint: ''),
    (Name: 'status'; Route: srExtensions; Hint: ''),
    (Name: 'agents'; Route: srAgents; Hint: ''),
    (Name: 'plan'; Route: srPlan; Hint: ''),
    (Name: 'hotkeys'; Route: srHotkeys; Hint: ''),
    (Name: 'hub'; Route: srHub; Hint: ''),
    (Name: 'queue'; Route: srQueue; Hint: '<message>'),
    (Name: 'version'; Route: srVersion; Hint: ''),
    (Name: 'exit'; Route: srExit; Hint: ''),
    (Name: 'quit'; Route: srExit; Hint: ''),
    (Name: 'q'; Route: srExit; Hint: ''));

  { omp 18.2.11 terminal-only built-ins with no RPC counterpart. }
  TerminalOnly: array[0..19] of string = ('goal', 'guided-goal', 'loop', 'vibe', 'tan', 'omfg',
    'cleanse', 'plan-review', 'collab', 'join', 'leave', 'pause', 'live', 'record', 'git', 'debug',
    'setup', 'skills', 'logout', 'open');

function RouteSlash(const Text: string; const RpcNames: TArray<string>; out Name, Args: string): TSlashRoute;
var
  Body, Known: string;
  Space: Integer;
  Item: TRouteName;
begin
  Result := srNone;
  Name := '';
  Args := '';
  Body := Trim(Text);
  if not Body.StartsWith('/') then
    Exit;
  Space := Pos(' ', Body);
  if Space = 0 then
    Name := LowerCase(Copy(Body, 2, MaxInt))
  else
  begin
    Name := LowerCase(Copy(Body, 2, Space - 2));
    Args := Trim(Copy(Body, Space + 1, MaxInt));
  end;
  for Known in RpcNames do
    if SameText(Known, Name) then
      Exit;
  for Item in Routes do
    if Item.Name = Name then
      Exit(Item.Route);
  for Known in TerminalOnly do
    if Known = Name then
      Exit(srTerminalOnly);
end;

function LocalCommandNames: TArray<string>;
var
  Item: TRouteName;
begin
  Result := nil;
  for Item in Routes do
    if (Item.Name <> 'q') and (Item.Name <> 'status') and (Item.Name <> 'rewind') and (Item.Name <> 'quit') then
      Result := Result + [Item.Name];
end;

function LocalCommandHint(const Name: string): string;
var
  Item: TRouteName;
begin
  Result := '';
  for Item in Routes do
    if Item.Name = Name then
      Exit(Item.Hint);
end;

end.
