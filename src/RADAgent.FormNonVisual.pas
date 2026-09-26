unit RADAgent.FormNonVisual;

{ Non-visual components of a designed form (menus, dialogs, timers, action and image lists,
  data access, style books) sit as icons wherever the designer dropped them, usually the middle of
  the form. Their place is TComponent.DesignInfo (streamed as Left/Top). Here they are told apart
  from controls and their sub-items, and lined up along the bottom of the form, grouped by kind.
  Main thread only. }

interface

uses
  System.Classes, ToolsAPI, RADAgent.Approval;

{ An icon on the design surface: not a control, and not an item of another component (menu item,
  action, dataset field). }
function IsNonVisual(Root, Component: TComponent): Boolean;
procedure SetDesignPos(Component: TComponent; Left, Top: Integer);
{ Lines every non-visual component up in rows at the bottom of the form, grouped by kind (menus,
  actions, dialogs, timers, images, data, styles, others) and in creation order within a kind.
  Returns how many were placed. The caller marks the designer modified. }
function ArrangeNonVisual(const Editor: IOTAFormEditor): Integer;
{ rad.form_arrange_nonvisual: after approval, ArrangeNonVisual and mark the designer modified. }
function ArrangeIcons(const Editor: IOTAFormEditor; const Path: string; const Approval: IAgentApproval;
  out ResultText: string): Boolean;

implementation

uses
  System.SysUtils, System.StrUtils, System.Types, System.TypInfo, System.Generics.Collections,
  System.Generics.Defaults, Vcl.Controls, RADAgent.FormDesigner, RADAgent.FormEdits, RADAgent.Lang;

const
  { Captions are centred under the icons and wider than them: room on the left and between. }
  CellWidth = 128;
  RowHeight = 60;
  Margin = 48;
  BottomGap = 52;
  { Ancestor class names per group, in the order the groups are laid out. }
  Groups: array[0..6] of string = (
    ',TMenu,TMainMenu,TPopupMenu,TMenuBar,',
    ',TCustomActionList,TActionList,TActionManager,',
    ',TCommonDialog,',
    ',TTimer,',
    ',TCustomImageList,TBaseImageList,TImageList,',
    ',TDataSet,TDataSource,TCustomConnection,TCustomBindingsList,TBindSourceAdapter,TBaseBindScopeComponent,',
    ',TStyleBook,TLang,');

function InheritsFromName(Component: TComponent; const Names: string): Boolean;
var
  Cls: TClass;
begin
  Cls := Component.ClassType;
  while Cls <> nil do
  begin
    if Pos(',' + Cls.ClassName + ',', Names) > 0 then
      Exit(True);
    Cls := Cls.ClassParent;
  end;
  Result := False;
end;

function GroupOf(Component: TComponent): Integer;
begin
  for Result := 0 to High(Groups) do
    if InheritsFromName(Component, Groups[Result]) then
      Exit;
  Result := Length(Groups);
end;

function IsNonVisual(Root, Component: TComponent): Boolean;
var
  Parent: TComponent;
begin
  Result := False;
  if (Component = nil) or (Component = Root) or (Component is TControl) then
    Exit;
  { FMX controls and items have a Position; VCL and FMX sub-items name their parent. }
  if GetPropInfo(Component, 'Position') <> nil then
    Exit;
  Parent := Component.GetParentComponent;
  Result := (Parent = nil) or (Parent = Root);
end;

procedure SetDesignPos(Component: TComponent; Left, Top: Integer);
var
  Info: LongInt;
begin
  LongRec(Info).Lo := Word(SmallInt(Left));
  LongRec(Info).Hi := Word(SmallInt(Top));
  Component.DesignInfo := Info;
end;

function RootSize(Root: TComponent): TPoint;

  function Dimension(const ClientName, SizeName: string): Integer;
  var
    Prop: PPropInfo;
  begin
    Prop := GetPropInfo(Root, ClientName);
    if Prop = nil then
      Prop := GetPropInfo(Root, SizeName);
    if Prop = nil then
      Exit(0);
    if Prop.PropType^.Kind = tkFloat then
      Result := Round(GetFloatProp(Root, Prop))
    else if Prop.PropType^.Kind in [tkInteger, tkInt64] then
      Result := GetOrdProp(Root, Prop)
    else
      Result := 0;
  end;

begin
  Result := Point(Dimension('ClientWidth', 'Width'), Dimension('ClientHeight', 'Height'));
  if Result.X < CellWidth + 2 * Margin then
    Result.X := 640;
  if Result.Y < RowHeight + BottomGap then
    Result.Y := 480;
end;

function ArrangeNonVisual(const Editor: IOTAFormEditor): Integer;
var
  Root: TComponent;
  Items: TList<TComponent>;
  Index, PerRow: Integer;
  Size: TPoint;
begin
  Result := 0;
  Root := RootOf(Editor);
  if Root = nil then
    Exit;
  Items := TList<TComponent>.Create;
  try
    for Index := 0 to Root.ComponentCount - 1 do
      if IsNonVisual(Root, Root.Components[Index]) then
        Items.Add(Root.Components[Index]);
    { Stable: creation order within a group. }
    Items.Sort(TComparer<TComponent>.Construct(
      function(const A, B: TComponent): Integer
      begin
        Result := GroupOf(A) - GroupOf(B);
        if Result = 0 then
          Result := A.ComponentIndex - B.ComponentIndex;
      end));
    Size := RootSize(Root);
    PerRow := (Size.X - 2 * Margin) div CellWidth;
    for Index := 0 to Items.Count - 1 do
      SetDesignPos(Items[Index], Margin + (Index mod PerRow) * CellWidth,
        Size.Y - BottomGap - (Index div PerRow) * RowHeight);
    Result := Items.Count;
  finally
    Items.Free;
  end;
end;

function ArrangeIcons(const Editor: IOTAFormEditor; const Path: string; const Approval: IAgentApproval;
  out ResultText: string): Boolean;
var
  Root: TComponent;
  Names: string;
  Index, Count: Integer;
begin
  Result := False;
  Root := RootOf(Editor);
  Names := '';
  Count := 0;
  for Index := 0 to Root.ComponentCount - 1 do
    if IsNonVisual(Root, Root.Components[Index]) then
    begin
      Names := Names + IfThen(Names <> '', ', ', '') + Root.Components[Index].Name;
      Inc(Count);
    end;
  if Count = 0 then
  begin
    ResultText := '{"ok":true,"arranged":0}';
    Exit(True);
  end;
  if not ApprovedEdit(Approval, Path, TrF('formnonvisual.arrangePreview', [Count, Names]), ResultText) then
    Exit;
  if RootOf(Editor) <> Root then
  begin
    ResultText := 'Form changed while waiting for approval.';
    Exit;
  end;
  Count := ArrangeNonVisual(Editor);
  MarkDesignerModified(Editor);
  ResultText := Format('{"ok":true,"arranged":%d}', [Count]);
  Result := True;
end;

end.
