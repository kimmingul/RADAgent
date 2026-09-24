unit RADAgent.MenuIcon;

{ The RADAgent icon (resources\MenuIcon-16.png and -32.png, linked as RCDATA from
  RADAgentIcons.rc) in the IDE image list, for the main-menu entry. Both sizes go in so the
  IDE picks the sharp one at high DPI. IDE context menus draw only from their own image lists and
  ignore item bitmaps, so our items there stay text-only. Main thread only. }

interface

{ Index in the IDE image list; -1 when the image could not be added. Added once. }
function AgentImageIndex: Integer;

implementation

uses
  System.SysUtils, System.Classes, Winapi.Windows, Vcl.Graphics, ToolsAPI, RADAgent.Options;

var
  GIndex: Integer = -2;

function LoadPng(const Name: string): TWICImage;
var
  Stream: TResourceStream;
begin
  Result := nil;
  if FindResource(HInstance, PChar(Name), RT_RCDATA) = 0 then
    Exit;
  Stream := TResourceStream.Create(HInstance, Name, RT_RCDATA);
  try
    Result := TWICImage.Create;
    Result.LoadFromStream(Stream);
  finally
    Stream.Free;
  end;
end;

function AgentImageIndex: Integer;
var
  Services: INTAServices280;
  Small, Large: TWICImage;
begin
  if GIndex <> -2 then
    Exit(GIndex);
  GIndex := -1;
  Small := nil;
  Large := nil;
  try
    try
      Small := LoadPng('RADAGENT_ICON16');
      Large := LoadPng('RADAGENT_ICON32');
      if (Small <> nil) and (Large <> nil) and Supports(BorlandIDEServices, INTAServices280, Services) then
        GIndex := Services.AddImage('RADAgent.Chat', [Small, Large]);
    except
      on E: Exception do
        AppendRpcLog('menu icon: ' + E.Message);
    end;
  finally
    { The image list copies what it is given (checked in the IDE). }
    Small.Free;
    Large.Free;
  end;
  Result := GIndex;
end;

end.
