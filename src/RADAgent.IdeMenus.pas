unit RADAgent.IdeMenus;

{ Chat entry points inside the IDE: the Messages view context menu (fix build errors) and the
  editor context menu (explain / fix the selection). Each item sends a prompt through SendPrompt. }

interface

uses
  System.SysUtils;

type
  TSendPrompt = reference to procedure(const Text: string);

procedure InstallIdeMenus(const SendPrompt: TSendPrompt);
procedure RemoveIdeMenus;

implementation

uses
  System.Classes, Vcl.Forms, Vcl.Menus, Vcl.Controls, Vcl.ComCtrls, DockForm, ToolsAPI,
  RADAgent.EditorContext, RADAgent.Lang;

const
  MenuTag = $DA6E;
  TagFixBuild = $DA6F;
  TagExplainSelection = $DA70;
  TagFixSelection = $DA71;

type
  { Owns nothing; hears when the IDE frees a menu that carries our items. }
  TItemTracker = class(TComponent)
  private
    FItems: TList;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Track(Item: TMenuItem);
    procedure FreeAll;
  end;

  TMenuHandlers = class
    procedure FixBuild(Sender: TObject);
    procedure ExplainSelection(Sender: TObject);
    procedure FixSelection(Sender: TObject);
  end;

  TMessageMenu = class(TNotifierObject, IOTAMessageNotifier, INTAMessageNotifier)
  public
    procedure MessageGroupAdded(const Group: IOTAMessageGroup);
    procedure MessageGroupDeleted(const Group: IOTAMessageGroup);
    procedure MessageViewMenuShown(Menu: TPopupMenu; const MessageGroup: IOTAMessageGroup;
      LineRef: Pointer);
  end;

  TEditorMenu = class(TNotifierObject, INTAEditServicesNotifier)
  public
    procedure WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
    procedure WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
    procedure WindowActivated(const EditWindow: INTAEditWindow);
    procedure WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer;
      var Handled: Boolean);
    procedure EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
    procedure EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
    procedure DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
    procedure DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
    procedure DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
  end;

var
  GSend: TSendPrompt;
  GHandlers: TMenuHandlers;
  GMessageIndex: Integer = -1;
  GEditorIndex: Integer = -1;
  GTracker: TItemTracker;

constructor TItemTracker.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FItems := TList.Create;
end;

destructor TItemTracker.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TItemTracker.Track(Item: TMenuItem);
begin
  FItems.Add(Item);
  Item.FreeNotification(Self);
end;

procedure TItemTracker.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if Operation = opRemove then
    FItems.Remove(AComponent);
end;

procedure TItemTracker.FreeAll;
begin
  while FItems.Count > 0 do
    TMenuItem(FItems[FItems.Count - 1]).Free;
end;

procedure Send(const Text: string);
begin
  if Assigned(GSend) then
    GSend(Text);
end;

procedure TMenuHandlers.FixBuild(Sender: TObject);
begin
  Send(Tr('idemenus.fixBuildPrompt'));
end;

function SelectionPrompt(const Request: string): string;
var
  Info: TEditorInfo;
begin
  Info := ActiveEditorInfo;
  Result := '';
  if not Info.HasSelection then
    Exit;
  Result := Request + SelectionAttachment(Info);
end;

procedure TMenuHandlers.ExplainSelection(Sender: TObject);
var
  Prompt: string;
begin
  Prompt := SelectionPrompt(Tr('idemenus.explainSelectionPrompt'));
  if Prompt <> '' then
    Send(Prompt);
end;

procedure TMenuHandlers.FixSelection(Sender: TObject);
var
  Prompt: string;
begin
  Prompt := SelectionPrompt(Tr('idemenus.fixSelectionPrompt'));
  if Prompt <> '' then
    Send(Prompt);
end;

function AddItem(Menu: TPopupMenu; const Caption: string; Handler: TNotifyEvent; Tag: Integer = MenuTag): TMenuItem;
begin
  Result := TMenuItem.Create(Menu);
  Result.Caption := Caption;
  Result.Tag := Tag;
  Result.OnClick := Handler;
  Menu.Items.Add(Result);
  GTracker.Track(Result);
end;

function HasOurItems(Menu: TPopupMenu): Boolean;
var
  Index: Integer;
begin
  for Index := 0 to Menu.Items.Count - 1 do
    if (Menu.Items[Index].Tag >= MenuTag) and (Menu.Items[Index].Tag <= TagFixSelection) then
      Exit(True);
  Result := False;
end;

procedure RefreshMenuCaptions(Menu: TPopupMenu);
var
  Index: Integer;
  Item: TMenuItem;
begin
  if Menu = nil then
    Exit;
  for Index := 0 to Menu.Items.Count - 1 do
  begin
    Item := Menu.Items[Index];
    case Item.Tag of
      TagFixBuild: Item.Caption := Tr('idemenus.fixBuild');
      TagExplainSelection: Item.Caption := Tr('idemenus.explainSelection');
      TagFixSelection: Item.Caption := Tr('idemenus.fixSelection');
    end;
  end;
end;

procedure TMessageMenu.MessageGroupAdded(const Group: IOTAMessageGroup);
begin
end;

procedure TMessageMenu.MessageGroupDeleted(const Group: IOTAMessageGroup);
begin
end;

procedure TMessageMenu.MessageViewMenuShown(Menu: TPopupMenu; const MessageGroup: IOTAMessageGroup;
  LineRef: Pointer);
begin
  if Menu = nil then
    Exit;
  if HasOurItems(Menu) then
  begin
    RefreshMenuCaptions(Menu);
    Exit;
  end;
  AddItem(Menu, '-', nil);
  AddItem(Menu, Tr('idemenus.fixBuild'), GHandlers.FixBuild, TagFixBuild);
end;

procedure TEditorMenu.EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
var
  Popup: TComponent;
  Menu: TPopupMenu;
begin
  if (EditWindow = nil) or (EditWindow.Form = nil) then
    Exit;
  { EditorLocalMenu is the editor's context menu component on every edit window. }
  Popup := EditWindow.Form.FindComponent('EditorLocalMenu');
  if not (Popup is TPopupMenu) then
    Exit;
  Menu := TPopupMenu(Popup);
  if HasOurItems(Menu) then
  begin
    RefreshMenuCaptions(Menu);
    Exit;
  end;
  AddItem(Menu, '-', nil);
  AddItem(Menu, Tr('idemenus.explainSelection'), GHandlers.ExplainSelection, TagExplainSelection);
  AddItem(Menu, Tr('idemenus.fixSelection'), GHandlers.FixSelection, TagFixSelection);
end;

procedure TEditorMenu.WindowShow(const EditWindow: INTAEditWindow; Show, LoadedFromDesktop: Boolean);
begin
end;

procedure TEditorMenu.WindowNotification(const EditWindow: INTAEditWindow; Operation: TOperation);
begin
end;

procedure TEditorMenu.WindowActivated(const EditWindow: INTAEditWindow);
begin
end;

procedure TEditorMenu.WindowCommand(const EditWindow: INTAEditWindow; Command, Param: Integer;
  var Handled: Boolean);
begin
end;

procedure TEditorMenu.EditorViewModified(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
begin
end;

procedure TEditorMenu.DockFormVisibleChanged(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TEditorMenu.DockFormUpdated(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure TEditorMenu.DockFormRefresh(const EditWindow: INTAEditWindow; DockForm: TDockableForm);
begin
end;

procedure InstallIdeMenus(const SendPrompt: TSendPrompt);
var
  Messages: IOTAMessageServices;
  Editors: IOTAEditorServices;
begin
  GSend := SendPrompt;
  if GHandlers = nil then
    GHandlers := TMenuHandlers.Create;
  if GTracker = nil then
    GTracker := TItemTracker.Create(nil);
  if (GMessageIndex < 0) and Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    GMessageIndex := Messages.AddNotifier(TMessageMenu.Create);
  if (GEditorIndex < 0) and Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    GEditorIndex := Editors.AddNotifier(TEditorMenu.Create);
end;

procedure RemoveIdeMenus;
var
  Messages: IOTAMessageServices;
  Editors: IOTAEditorServices;
begin
  GSend := nil;
  if (GMessageIndex >= 0) and Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
    Messages.RemoveNotifier(GMessageIndex);
  GMessageIndex := -1;
  if (GEditorIndex >= 0) and Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
    Editors.RemoveNotifier(GEditorIndex);
  GEditorIndex := -1;
  { Our items live in IDE menus that outlive the package; their handlers must not. }
  if GTracker <> nil then
    GTracker.FreeAll;
  FreeAndNil(GTracker);
  FreeAndNil(GHandlers);
end;

end.
