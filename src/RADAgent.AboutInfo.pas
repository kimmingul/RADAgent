unit RADAgent.AboutInfo;

{ RAD Agent in the IDE's splash screen (while the IDE starts) and in Help > About, with its
  version and icon (resources\PluginIcon-24.png and -48.png, RCDATA from RADAgentResources.rc).
  Also puts the versions at the top of rpc.log. Main thread only. }

interface

procedure InstallAboutInfo;
procedure RemoveAboutInfo;

implementation

uses
  System.SysUtils, System.Classes, Winapi.Windows, Vcl.Graphics, ToolsAPI, RADAgent.AgentVersion,
  RADAgent.OmpCheck, RADAgent.Options, RADAgent.Lang;

var
  GAboutIndex: Integer = -1;

function LoadPng(const Name: string): TWICImage;
var
  Stream: TResourceStream;
begin
  Stream := TResourceStream.Create(HInstance, Name, RT_RCDATA);
  try
    Result := TWICImage.Create;
    Result.LoadFromStream(Stream);
  finally
    Stream.Free;
  end;
end;

function Title: string;
begin
  Result := 'RAD Agent ' + AgentVersion;
end;

{$IF CompilerVersion >= 35}
{ The final interfaces: the IDE answers QueryInterface for those, not for each ancestor. }
procedure AddEntries(const Description: string);
var
  Small, Large: TWICImage;
  About: IOTAAboutBoxServices;
begin
  Small := LoadPng('RADAGENT_PLUGIN24');
  Large := LoadPng('RADAGENT_PLUGIN48');
  try
    { Only while the IDE starts: loading the package later has no splash screen. }
    if SplashScreenServices <> nil then
      SplashScreenServices.AddPluginBitmap(Title, [Small, Large]);
    if Supports(BorlandIDEServices, IOTAAboutBoxServices, About) then
      GAboutIndex := About.AddPluginInfo(Title, Description, [Small, Large]);
  finally
    Small.Free;
    Large.Free;
  end;
end;
{$ELSE}
{ RAD Studio 10.4 takes 24x24 bitmaps only; the entries go without the icon. }
procedure AddEntries(const Description: string);
var
  About: IOTAAboutBoxServices;
begin
  if SplashScreenServices <> nil then
    SplashScreenServices.AddPluginBitmap(Title, 0);
  if Supports(BorlandIDEServices, IOTAAboutBoxServices, About) then
    GAboutIndex := About.AddPluginInfo(Title, Description, 0);
end;
{$IFEND}

procedure InstallAboutInfo;
begin
  SetRpcLogHeader('version ' + VersionLine(KnownOmpVersion));
  AppendRpcLog('version ' + VersionLine(KnownOmpVersion));
  try
    AddEntries(TrF('aboutinfo.description', [AgentBitness, ReleaseNotesUrl]));
  except
    on E: Exception do
      AppendRpcLog('about box: ' + E.Message);
  end;
end;

procedure RemoveAboutInfo;
var
  About: IOTAAboutBoxServices;
begin
  if (GAboutIndex >= 0) and (BorlandIDEServices <> nil) and
    Supports(BorlandIDEServices, IOTAAboutBoxServices, About) then
    About.RemovePluginInfo(GAboutIndex);
  GAboutIndex := -1;
end;

end.
