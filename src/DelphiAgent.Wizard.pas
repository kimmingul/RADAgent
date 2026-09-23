unit DelphiAgent.Wizard;

{ Package entry. Registers the wizard, the View menu, and the dockable chat. }

interface

procedure Register;

implementation

uses
  System.SysUtils, System.Classes, System.IniFiles, Winapi.Windows, Vcl.Forms,
  Vcl.Controls, Vcl.Menus, Vcl.ActnList, Vcl.ImgList, Vcl.ComCtrls, Vcl.ToolWin,
  ToolsAPI, DesignIntf, DelphiAgent.DockForm, DelphiAgent.Compile, DelphiAgent.RpcClient;

type
  TDelphiAgentWizard = class(TNotifierObject, IOTAWizard)
  protected
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    procedure Execute;
  end;

  TDelphiAgentDockable = class(TInterfacedObject, INTACustomDockableForm)
  private
    FForm: TCustomForm;
  public
    function GetCaption: string;
    function GetIdentifier: string;
    function GetFrameClass: TCustomFrameClass;
    procedure FrameCreated(AFrame: TCustomFrame);
    function GetMenuActionList: TCustomActionList;
    function GetMenuImageList: TCustomImageList;
    function GetToolBarActionList: TCustomActionList;
    function GetToolBarImageList: TCustomImageList;
    procedure CustomizePopupMenu(PopupMenu: TPopupMenu);
    procedure CustomizeToolBar(ToolBar: TToolBar);
    procedure SaveWindowState(Desktop: TCustomIniFile; const Section: string; IsProject: Boolean);
    procedure LoadWindowState(Desktop: TCustomIniFile; const Section: string);
    function GetEditState: TEditState;
    function EditAction(Action: TEditAction): Boolean;
    procedure Show;
  end;

  TMenuOwner = class(TComponent)
  public
    procedure OpenChat(Sender: TObject);
  end;

var
  GWizard: IOTAWizard;
  GDockObj: TDelphiAgentDockable;
  GDockable: INTACustomDockableForm;
  GMenuOwner: TMenuOwner;
  GViewAction: TAction;
  GViewItem: TMenuItem;

procedure TMenuOwner.OpenChat(Sender: TObject);
begin
  if GDockObj <> nil then
    GDockObj.Show;
end;

function TDelphiAgentWizard.GetIDString: string;
begin
  Result := 'DelphiAgent.Wizard';
end;

function TDelphiAgentWizard.GetName: string;
begin
  Result := 'DelphiAgent';
end;

function TDelphiAgentWizard.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

procedure TDelphiAgentWizard.Execute;
begin
  if GDockObj <> nil then
    GDockObj.Show;
end;

function TDelphiAgentDockable.GetCaption: string;
begin
  Result := 'DelphiAgent';
end;

function TDelphiAgentDockable.GetIdentifier: string;
begin
  Result := '{8F3A1C24-7B6E-4D19-A5C0-2E91D4B70F6A}';
end;

function TDelphiAgentDockable.GetFrameClass: TCustomFrameClass;
begin
  Result := TDelphiAgentChatFrame;
end;

procedure TDelphiAgentDockable.FrameCreated(AFrame: TCustomFrame);
var
  Chat: TDelphiAgentChatFrame;
begin
  Chat := AFrame as TDelphiAgentChatFrame;
  Chat.HostFrameCreated;
end;

function TDelphiAgentDockable.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TDelphiAgentDockable.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

function TDelphiAgentDockable.GetToolBarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TDelphiAgentDockable.GetToolBarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TDelphiAgentDockable.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

procedure TDelphiAgentDockable.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TDelphiAgentDockable.SaveWindowState(Desktop: TCustomIniFile;
  const Section: string; IsProject: Boolean);
begin
end;

procedure TDelphiAgentDockable.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TDelphiAgentDockable.GetEditState: TEditState;
begin
  Result := [];
end;

function TDelphiAgentDockable.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;

procedure TDelphiAgentDockable.Show;
var
  Services: INTAServices270;
begin
  Services := BorlandIDEServices as INTAServices270;
  if (FForm = nil) or (csDestroying in FForm.ComponentState) then
    FForm := Services.CreateDockableForm(Self);
  if (FForm <> nil) and not (csDestroying in FForm.ComponentState) then
    FForm.Show;
end;

procedure NoteMenu(const Msg: string);
begin
  OutputDebugString(PChar('DelphiAgent: ' + Msg));
end;

function MainMenuHasItem(const ItemName: string): Boolean;
var
  Menu: TMainMenu;
  Index: Integer;
begin
  Result := False;
  if (Application = nil) or (Application.MainForm = nil) then
    Exit;
  Menu := Application.MainForm.Menu;
  if Menu = nil then
    Exit;
  for Index := 0 to Menu.Items.Count - 1 do
    if SameText(Menu.Items[Index].Name, ItemName) then
      Exit(True);
end;

function TryAddAgentMenu(const Services: INTAServices; const ParentName: string): Boolean;
begin
  Result := False;
  if (Services = nil) or not MainMenuHasItem(ParentName) then
    Exit;
  try
    Services.AddActionMenu(ParentName, GViewAction, GViewItem, True, True);
    Result := True;
  except
    on E: Exception do
      NoteMenu(ParentName + ': ' + E.Message);
  end;
end;

procedure InstallViewMenu;
const
  MenuNames: array[0..3] of string = ('ViewsMenu', 'ViewMenu', 'ToolsMenu', 'HelpMenu');
var
  Services: INTAServices;
  Index: Integer;
  Placed: Boolean;
begin
  if GMenuOwner <> nil then
    Exit;
  Placed := False;
  try
    GMenuOwner := TMenuOwner.Create(nil);
    GViewAction := TAction.Create(GMenuOwner);
    GViewAction.Caption := 'DelphiAgent';
    GViewAction.OnExecute := GMenuOwner.OpenChat;
    GViewItem := TMenuItem.Create(GMenuOwner);
    GViewItem.Caption := 'DelphiAgent';
    GViewItem.OnClick := GMenuOwner.OpenChat;
    Services := BorlandIDEServices as INTAServices;
    for Index := 0 to High(MenuNames) do
      if TryAddAgentMenu(Services, MenuNames[Index]) then
      begin
        Placed := True;
        Break;
      end;
    if not Placed then
    begin
      try
        Services.AddActionMenu('ToolsMenu', GViewAction, GViewItem, True, True);
        Placed := True;
      except
        on E: Exception do
          NoteMenu('ToolsMenu: ' + E.Message);
      end;
    end;
  except
    on E: Exception do
      NoteMenu(E.Message);
  end;
  if not Placed then
  begin
    NoteMenu('menu not installed');
    GViewItem := nil;
    GViewAction := nil;
    FreeAndNil(GMenuOwner);
  end;
end;

procedure RemoveViewMenu;
begin
  if GViewItem <> nil then
  begin
    GViewItem.OnClick := nil;
    GViewItem.Action := nil;
    if GViewItem.Parent <> nil then
      GViewItem.Parent.Remove(GViewItem);
  end;
  if GViewAction <> nil then
  begin
    GViewAction.OnExecute := nil;
    GViewAction.ActionList := nil;
  end;
  GViewItem := nil;
  GViewAction := nil;
  FreeAndNil(GMenuOwner);
end;

procedure Register;
var
  Services: INTAServices270;
begin
  GWizard := TDelphiAgentWizard.Create;
  RegisterPackageWizard(GWizard);
  GDockObj := TDelphiAgentDockable.Create;
  GDockable := GDockObj;
  Services := BorlandIDEServices as INTAServices270;
  Services.RegisterDockableForm(GDockable);
  InstallCompileNotifier;
  InstallViewMenu;
end;

procedure UnregisterAll;
var
  Services: INTAServices270;
begin
  RemoveCompileNotifier;
  GDockObj := nil;
  if (GDockable <> nil) and (BorlandIDEServices <> nil) and
    Supports(BorlandIDEServices, INTAServices270, Services) then
    Services.UnregisterDockableForm(GDockable);
  GDockable := nil;
  ShutdownActiveClient;
  GWizard := nil;
  RemoveViewMenu;
end;

initialization

finalization
  UnregisterAll;

end.
