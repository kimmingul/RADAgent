unit DelphiAgent.IdeMenus;

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
  DelphiAgent.EditorContext;

const
  MenuTag = $DA6E;

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
  Send('활성 프로젝트의 빌드 오류를 고쳐줘. 먼저 rad.compile로 오류 위치와 내용을 확인하고 고친 뒤 ' +
    '다시 rad.compile로 확인해.');
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
  Prompt := SelectionPrompt('아래 선택한 코드가 무엇을 하는지 설명해줘. 파일은 고치지 마.');
  if Prompt <> '' then
    Send(Prompt);
end;

procedure TMenuHandlers.FixSelection(Sender: TObject);
var
  Prompt: string;
begin
  Prompt := SelectionPrompt('아래 선택한 코드의 문제를 찾아 고쳐줘.');
  if Prompt <> '' then
    Send(Prompt);
end;

function AddItem(Menu: TPopupMenu; const Caption: string; Handler: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(Menu);
  Result.Caption := Caption;
  Result.Tag := MenuTag;
  Result.OnClick := Handler;
  Menu.Items.Add(Result);
  GTracker.Track(Result);
end;

function HasOurItems(Menu: TPopupMenu): Boolean;
var
  Index: Integer;
begin
  for Index := 0 to Menu.Items.Count - 1 do
    if Menu.Items[Index].Tag = MenuTag then
      Exit(True);
  Result := False;
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
  if (Menu = nil) or HasOurItems(Menu) then
    Exit;
  AddItem(Menu, '-', nil);
  AddItem(Menu, 'DelphiAgent: 빌드 오류 고치기', GHandlers.FixBuild);
end;

procedure TEditorMenu.EditorViewActivated(const EditWindow: INTAEditWindow; const EditView: IOTAEditView);
var
  Popup: TComponent;
begin
  if (EditWindow = nil) or (EditWindow.Form = nil) then
    Exit;
  { EditorLocalMenu is the editor's context menu component on every edit window. }
  Popup := EditWindow.Form.FindComponent('EditorLocalMenu');
  if not (Popup is TPopupMenu) or HasOurItems(TPopupMenu(Popup)) then
    Exit;
  AddItem(TPopupMenu(Popup), '-', nil);
  AddItem(TPopupMenu(Popup), 'DelphiAgent: 선택 영역 설명', GHandlers.ExplainSelection);
  AddItem(TPopupMenu(Popup), 'DelphiAgent: 선택 영역 고치기', GHandlers.FixSelection);
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
