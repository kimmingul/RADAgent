unit RADAgent.Wizard;

{ Package entry. Registers the wizard, the View menu, and the dockable chat. }

interface

procedure Register;

implementation

uses
  System.SysUtils, System.Classes, System.IniFiles, Winapi.Windows, Vcl.Forms,
  Vcl.Controls, Vcl.Menus, Vcl.ActnList, Vcl.ImgList, Vcl.ComCtrls, Vcl.ToolWin, Vcl.ExtCtrls,
  ToolsAPI, DesignIntf, RADAgent.DockForm, RADAgent.Compile, RADAgent.RpcClient,
  RADAgent.Options, RADAgent.ChatSession, RADAgent.IdeMenus, RADAgent.DockKeeper,
  RADAgent.MenuIcon;

type
  TRADAgentWizard = class(TNotifierObject, IOTAWizard)
  protected
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    procedure Execute;
  end;

  TRADAgentDockable = class(TInterfacedObject, INTACustomDockableForm)
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
    function Showing: Boolean;
  end;

  TMenuOwner = class(TComponent)
  public
    FRetry: TTimer;
    FTries: Integer;
    procedure OpenChat(Sender: TObject);
    procedure RetryMenu(Sender: TObject);
  end;

var
  GWizard: IOTAWizard;
  GDockObj: TRADAgentDockable;
  GDockable: INTACustomDockableForm;
  GMenuOwner: TMenuOwner;
  GViewAction: TAction;
  GViewItem: TMenuItem;

procedure TMenuOwner.OpenChat(Sender: TObject);
begin
  if GDockObj <> nil then
    GDockObj.Show;
end;

function TRADAgentWizard.GetIDString: string;
begin
  Result := 'RADAgent.Wizard';
end;

function TRADAgentWizard.GetName: string;
begin
  Result := 'RADAgent';
end;

function TRADAgentWizard.GetState: TWizardState;
begin
  Result := [wsEnabled];
end;

procedure TRADAgentWizard.Execute;
begin
  if GDockObj <> nil then
    GDockObj.Show;
end;

function TRADAgentDockable.GetCaption: string;
begin
  Result := 'RADAgent';
end;

function TRADAgentDockable.GetIdentifier: string;
begin
  Result := '{8F3A1C24-7B6E-4D19-A5C0-2E91D4B70F6A}';
end;

function TRADAgentDockable.GetFrameClass: TCustomFrameClass;
begin
  Result := TRADAgentChatFrame;
end;

procedure TRADAgentDockable.FrameCreated(AFrame: TCustomFrame);
var
  Chat: TRADAgentChatFrame;
begin
  Chat := AFrame as TRADAgentChatFrame;
  Chat.HostFrameCreated;
end;

function TRADAgentDockable.GetMenuActionList: TCustomActionList;
begin
  Result := nil;
end;

function TRADAgentDockable.GetMenuImageList: TCustomImageList;
begin
  Result := nil;
end;

function TRADAgentDockable.GetToolBarActionList: TCustomActionList;
begin
  Result := nil;
end;

function TRADAgentDockable.GetToolBarImageList: TCustomImageList;
begin
  Result := nil;
end;

procedure TRADAgentDockable.CustomizePopupMenu(PopupMenu: TPopupMenu);
begin
end;

procedure TRADAgentDockable.CustomizeToolBar(ToolBar: TToolBar);
begin
end;

procedure TRADAgentDockable.SaveWindowState(Desktop: TCustomIniFile;
  const Section: string; IsProject: Boolean);
begin
end;

procedure TRADAgentDockable.LoadWindowState(Desktop: TCustomIniFile; const Section: string);
begin
end;

function TRADAgentDockable.GetEditState: TEditState;
begin
  Result := [];
end;

function TRADAgentDockable.EditAction(Action: TEditAction): Boolean;
begin
  Result := False;
end;
function FindFrameIn(Parent: TWinControl): TRADAgentChatFrame;
var
  Index: Integer;
begin
  for Index := 0 to Parent.ControlCount - 1 do
  begin
    if Parent.Controls[Index] is TRADAgentChatFrame then
      Exit(TRADAgentChatFrame(Parent.Controls[Index]));
    if Parent.Controls[Index] is TWinControl then
    begin
      Result := FindFrameIn(TWinControl(Parent.Controls[Index]));
      if Result <> nil then
        Exit;
    end;
  end;
  Result := nil;
end;

{ The IDE may free the dockable form on a desktop switch; never trust a cached pointer.
  The frame's nearest parent form is the dockable form even while docked into another window. }
function FindChatForm: TCustomForm;
var
  FormIndex: Integer;
  Form: TCustomForm;
  Frame: TRADAgentChatFrame;
begin
  for FormIndex := 0 to Screen.CustomFormCount - 1 do
  begin
    Form := Screen.CustomForms[FormIndex];
    if csDestroying in Form.ComponentState then
      Continue;
    Frame := FindFrameIn(Form);
    if Frame <> nil then
      Exit(GetParentForm(Frame, False));
  end;
  Result := nil;
end;

procedure TRADAgentDockable.Show;
var
  Services: INTAServices270;
  Form: TCustomForm;
begin
  Form := FindChatForm;
  if Form = nil then
  begin
    Services := BorlandIDEServices as INTAServices270;
    Form := Services.CreateDockableForm(Self);
  end;
  if Form <> nil then
    Form.Show;
end;

function TRADAgentDockable.Showing: Boolean;
var
  Form: TCustomForm;
begin
  Form := FindChatForm;
  Result := (Form <> nil) and Form.Visible;
end;

procedure ShowChatAndSend(const Text: string);
begin
  if GDockObj = nil then
    Exit;
  GDockObj.Show;
  SendFromIde(Text);
end;

procedure NoteMenu(const Msg: string);
begin
  OutputDebugString(PChar('RADAgent: ' + Msg));
  AppendRpcLog('menu ' + Msg);
end;

{ The IDE main menu comes from INTAServices; Application.MainForm.Menu is not it. }
function MainMenuHasItem(const ItemName: string): Boolean;
var
  Services: INTAServices;
  Menu: TMainMenu;
  Index: Integer;
begin
  Result := False;
  if not Supports(BorlandIDEServices, INTAServices, Services) then
    Exit;
  Menu := Services.MainMenu;
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
    { AddActionMenu can return without attaching; only a parented item counts. }
    Result := GViewItem.Parent <> nil;
    NoteMenu(ParentName + BoolToStr(Result, True));
  except
    on E: Exception do
      NoteMenu(ParentName + ': ' + E.Message);
  end;
end;

{ At IDE startup Register runs before the main menu exists. Returns True once placed. }
function InstallViewMenu: Boolean;
const
  MenuNames: array[0..3] of string = ('ViewsMenu', 'ViewMenu', 'ToolsMenu', 'HelpMenu');
var
  Services: INTAServices;
  Index: Integer;
  Placed: Boolean;
begin
  if (GMenuOwner <> nil) and (GViewItem <> nil) and (GViewItem.Parent <> nil) then
    Exit(True);
  Placed := False;
  try
    if GMenuOwner = nil then
      GMenuOwner := TMenuOwner.Create(nil);
    if GViewAction = nil then
    begin
      GViewAction := TAction.Create(GMenuOwner);
      GViewAction.Caption := 'RADAgent';
      GViewAction.ImageIndex := AgentImageIndex;
      GViewAction.OnExecute := GMenuOwner.OpenChat;
    end;
    if GViewItem = nil then
    begin
      GViewItem := TMenuItem.Create(GMenuOwner);
      GViewItem.Caption := 'RADAgent';
      GViewItem.ImageIndex := AgentImageIndex;
      GViewItem.OnClick := GMenuOwner.OpenChat;
    end;
    Services := BorlandIDEServices as INTAServices;
    for Index := 0 to High(MenuNames) do
      if TryAddAgentMenu(Services, MenuNames[Index]) then
      begin
        Placed := True;
        Break;
      end;
  except
    on E: Exception do
      NoteMenu(E.Message);
  end;
  if not Placed then
    NoteMenu('menu not ready');
  Result := Placed;
end;

procedure TMenuOwner.RetryMenu(Sender: TObject);
begin
  Inc(FTries);
  if InstallViewMenu or (FTries >= 240) then
  begin
    if FTries >= 240 then
      NoteMenu('menu not installed');
    FRetry.Enabled := False;
  end;
end;

procedure ScheduleViewMenu;
begin
  if InstallViewMenu or (GMenuOwner = nil) or (GMenuOwner.FRetry <> nil) then
    Exit;
  GMenuOwner.FRetry := TTimer.Create(GMenuOwner);
  GMenuOwner.FRetry.Interval := 500;
  GMenuOwner.FRetry.OnTimer := GMenuOwner.RetryMenu;
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
  GWizard := TRADAgentWizard.Create;
  RegisterPackageWizard(GWizard);
  GDockObj := TRADAgentDockable.Create;
  GDockable := GDockObj;
  Services := BorlandIDEServices as INTAServices270;
  Services.RegisterDockableForm(GDockable);
  InstallCompileNotifier;
  ScheduleViewMenu;
  InstallIdeMenus(ShowChatAndSend);
  InstallDockKeeper(
    function: Boolean
    begin
      Result := (GDockObj <> nil) and GDockObj.Showing;
    end,
    procedure
    begin
      if GDockObj <> nil then
        GDockObj.Show;
    end);
end;

procedure UnregisterAll;
var
  Services: INTAServices270;
begin
  RemoveDockKeeper;
  RemoveIdeMenus;
  RemoveCompileNotifier;
  GDockObj := nil;
  if (GDockable <> nil) and (BorlandIDEServices <> nil) and
    Supports(BorlandIDEServices, INTAServices270, Services) then
    Services.UnregisterDockableForm(GDockable);
  GDockable := nil;
  FreeChatSession;
  ShutdownActiveClient;
  GWizard := nil;
  RemoveViewMenu;
end;

initialization

finalization
  UnregisterAll;

end.
