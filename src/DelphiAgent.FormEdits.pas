unit DelphiAgent.FormEdits;

{ Form designer changes that run only after the user approves: set a property, add, delete or
  rename a component, and connect an event handler. The designer updates the unit buffer
  (fields, handler stubs). Never saves. Main thread only. }

interface

uses
  ToolsAPI, DelphiAgent.Approval;

type
  TFormToolArgs = record
    Path: string;
    Component: string;
    PropName: string;
    Value: string;
    ClassName: string;
    Name: string;
    Parent: string;
    Left: Integer;
    Top: Integer;
    NewName: string;
    Event: string;
    Handler: string;
  end;

function SetProperty(const Editor: IOTAFormEditor; const Args: TFormToolArgs;
  const Approval: IAgentApproval; out Problem: string): Boolean;
function AddComponent(const Editor: IOTAFormEditor; const Args: TFormToolArgs;
  const Approval: IAgentApproval; out CreatedName, Problem: string): Boolean;
function DeleteComponent(const Editor: IOTAFormEditor; const Args: TFormToolArgs;
  const Approval: IAgentApproval; out Problem: string): Boolean;
function RenameComponent(const Editor: IOTAFormEditor; const Args: TFormToolArgs;
  const Approval: IAgentApproval; out Problem: string): Boolean;
function SetEvent(const Editor: IOTAFormEditor; const Args: TFormToolArgs;
  const Approval: IAgentApproval; out Problem: string): Boolean;

implementation

uses
  System.SysUtils, System.StrUtils, System.Classes, System.TypInfo, Vcl.Controls, DesignIntf,
  DelphiAgent.FormDesigner;

function Approved(const Approval: IAgentApproval; const Path, Preview: string;
  out Problem: string): Boolean;
begin
  Result := (Approval <> nil) and Approval.ApproveChange(Path, '', Preview);
  if not Result then
    Problem := SEditCancelled;
end;

{ Finds a non-root component by name. The root cannot be deleted or renamed here. }
function FindChild(const Editor: IOTAFormEditor; const Name: string; out Problem: string): TComponent;
begin
  Result := nil;
  if (Name = '') or (FindNative(Editor, Name) = RootOf(Editor)) then
  begin
    Problem := '폼 자체가 아닌 컴포넌트 이름이 필요합니다.';
    Exit;
  end;
  Result := FindNative(Editor, Name);
  if Result = nil then
    Problem := '컴포넌트를 찾지 못했습니다: ' + Name;
end;

function SetProperty(const Editor: IOTAFormEditor; const Args: TFormToolArgs;
  const Approval: IAgentApproval; out Problem: string): Boolean;
var
  Instance: TComponent;
  Prop: PPropInfo;
begin
  Result := False;
  Problem := '';
  Instance := FindNative(Editor, Args.Component);
  if Instance = nil then
  begin
    Problem := '컴포넌트를 찾지 못했습니다: ' + Args.Component;
    Exit;
  end;
  Prop := GetPropInfo(Instance, Args.PropName);
  if (Prop = nil) or (Prop.SetProc = nil) then
  begin
    Problem := '쓸 수 있는 속성이 아닙니다: ' + Args.PropName;
    Exit;
  end;
  if not (Prop.PropType^.Kind in TextKinds) then
  begin
    Problem := '문자, 숫자, 열거, 집합 속성만 바꿀 수 있습니다. 이벤트는 rad.form_set_event를 쓰세요: ' +
      Args.PropName;
    Exit;
  end;
  if not Approved(Approval, Args.Path, Instance.Name + '.' + string(Prop.Name) + ': ' +
    PropText(Editor, Instance, Prop) + ' -> ' + Args.Value, Problem) then
    Exit;
  { The dialog pumps messages; the component may be gone. }
  if FindNative(Editor, Args.Component) <> Instance then
  begin
    Problem := '승인하는 동안 컴포넌트가 바뀌었습니다.';
    Exit;
  end;
  try
    SetPropValue(Instance, Prop, Args.Value);
  except
    on E: Exception do
    begin
      Problem := '속성 값을 넣지 못했습니다: ' + E.Message;
      Exit;
    end;
  end;
  MarkDesignerModified(Editor);
  Result := True;
end;

function AddComponent(const Editor: IOTAFormEditor; const Args: TFormToolArgs;
  const Approval: IAgentApproval; out CreatedName, Problem: string): Boolean;
var
  Created: IOTAComponent;
  ParentNative, Native: TComponent;
begin
  Result := False;
  CreatedName := '';
  Problem := '';
  if Args.ClassName = '' then
  begin
    Problem := 'class가 비어 있습니다.';
    Exit;
  end;
  if GetClass(Args.ClassName) = nil then
  begin
    Problem := '등록되지 않은 컴포넌트 클래스입니다: ' + Args.ClassName;
    Exit;
  end;
  if (Args.Name <> '') and (FindNative(Editor, Args.Name) <> nil) then
  begin
    Problem := '같은 이름의 컴포넌트가 있습니다: ' + Args.Name;
    Exit;
  end;
  ParentNative := FindNative(Editor, Args.Parent);
  if ParentNative = nil then
  begin
    Problem := '부모 컴포넌트를 찾지 못했습니다: ' + Args.Parent;
    Exit;
  end;
  if not Approved(Approval, Args.Path, Format('추가 %s: %s  부모=%s  위치=%d,%d',
    [IfThen(Args.Name <> '', Args.Name, '(자동)'), Args.ClassName, ParentNative.Name,
    Args.Left, Args.Top]), Problem) then
    Exit;
  if FindNative(Editor, Args.Parent) <> ParentNative then
  begin
    Problem := '승인하는 동안 부모 컴포넌트가 바뀌었습니다.';
    Exit;
  end;
  Created := Editor.CreateComponent(FindOta(Editor, ParentNative), Args.ClassName,
    Args.Left, Args.Top, -1, -1);
  Native := NativeOf(Created);
  if Native = nil then
  begin
    Problem := '컴포넌트를 만들지 못했습니다: ' + Args.ClassName;
    Exit;
  end;
  { CreateComponent does not honour X,Y for controls (it cascades); place it explicitly. }
  if Native is TControl then
    TControl(Native).SetBounds(Args.Left, Args.Top, TControl(Native).Width, TControl(Native).Height);
  if Args.Name <> '' then
  try
    Native.Name := Args.Name;
  except
    on E: Exception do
    begin
      Problem := '만들었지만 이름을 바꾸지 못했습니다(' + Native.Name + '): ' + E.Message;
      MarkDesignerModified(Editor);
      Exit;
    end;
  end;
  MarkDesignerModified(Editor);
  CreatedName := Native.Name;
  Result := True;
end;

function DeleteComponent(const Editor: IOTAFormEditor; const Args: TFormToolArgs;
  const Approval: IAgentApproval; out Problem: string): Boolean;
var
  Native: TComponent;
  Ota: IOTAComponent;
begin
  Result := False;
  Problem := '';
  Native := FindChild(Editor, Args.Component, Problem);
  if Native = nil then
    Exit;
  if not Approved(Approval, Args.Path, Format('삭제 %s: %s', [Native.Name, Native.ClassName]),
    Problem) then
    Exit;
  if FindNative(Editor, Args.Component) <> Native then
  begin
    Problem := '승인하는 동안 컴포넌트가 바뀌었습니다.';
    Exit;
  end;
  Ota := FindOta(Editor, Native);
  if (Ota = nil) or not Ota.Delete then
  begin
    Problem := '컴포넌트를 지우지 못했습니다: ' + Args.Component;
    Exit;
  end;
  MarkDesignerModified(Editor);
  Result := True;
end;

function RenameComponent(const Editor: IOTAFormEditor; const Args: TFormToolArgs;
  const Approval: IAgentApproval; out Problem: string): Boolean;
var
  Native: TComponent;
begin
  Result := False;
  Problem := '';
  Native := FindChild(Editor, Args.Component, Problem);
  if Native = nil then
    Exit;
  if not IsValidIdent(Args.NewName) then
  begin
    Problem := '올바른 식별자가 아닙니다: ' + Args.NewName;
    Exit;
  end;
  if FindNative(Editor, Args.NewName) <> nil then
  begin
    Problem := '같은 이름의 컴포넌트가 있습니다: ' + Args.NewName;
    Exit;
  end;
  if not Approved(Approval, Args.Path, Format('이름 변경 %s -> %s', [Native.Name, Args.NewName]),
    Problem) then
    Exit;
  if FindNative(Editor, Args.Component) <> Native then
  begin
    Problem := '승인하는 동안 컴포넌트가 바뀌었습니다.';
    Exit;
  end;
  { The designer renames the field and default-named handlers through ValidateRename. }
  try
    Native.Name := Args.NewName;
  except
    on E: Exception do
    begin
      Problem := '이름을 바꾸지 못했습니다: ' + E.Message;
      Exit;
    end;
  end;
  MarkDesignerModified(Editor);
  Result := True;
end;

function SetEvent(const Editor: IOTAFormEditor; const Args: TFormToolArgs;
  const Approval: IAgentApproval; out Problem: string): Boolean;
var
  Instance: TComponent;
  Prop: PPropInfo;
  Designer: IDesigner;
  Method: TMethod;
begin
  Result := False;
  Problem := '';
  Instance := FindNative(Editor, Args.Component);
  if Instance = nil then
  begin
    Problem := '컴포넌트를 찾지 못했습니다: ' + Args.Component;
    Exit;
  end;
  Prop := GetPropInfo(Instance, Args.Event);
  if (Prop = nil) or (Prop.PropType^.Kind <> tkMethod) then
  begin
    Problem := '이벤트 속성이 아닙니다: ' + Args.Event;
    Exit;
  end;
  if (Args.Handler <> '') and not IsValidIdent(Args.Handler) then
  begin
    Problem := '올바른 메서드 이름이 아닙니다: ' + Args.Handler;
    Exit;
  end;
  Designer := DesignerOf(Editor);
  if Designer = nil then
  begin
    Problem := '폼 디자이너를 찾지 못했습니다.';
    Exit;
  end;
  if not Approved(Approval, Args.Path, Format('이벤트 %s.%s: %s -> %s', [Instance.Name,
    string(Prop.Name), PropText(Editor, Instance, Prop), IfThen(Args.Handler <> '',
    Args.Handler, '(연결 해제)')]), Problem) then
    Exit;
  if FindNative(Editor, Args.Component) <> Instance then
  begin
    Problem := '승인하는 동안 컴포넌트가 바뀌었습니다.';
    Exit;
  end;
  try
    { CreateMethod returns the existing method when the name exists, or adds a stub. }
    if Args.Handler = '' then
    begin
      Method.Code := nil;
      Method.Data := nil;
    end
    else
      Method := Designer.CreateMethod(Args.Handler, GetTypeData(Prop.PropType^));
    SetMethodProp(Instance, Prop, Method);
  except
    on E: Exception do
    begin
      Problem := '이벤트를 연결하지 못했습니다: ' + E.Message;
      Exit;
    end;
  end;
  MarkDesignerModified(Editor);
  Result := True;
end;

end.
