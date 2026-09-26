unit RADAgent.FormEvents;

{ Connects or disconnects a form component's event handler after the user approves. The
  designer adds the Delphi handler stub; C++ handlers are written first (RADAgent.HandlerCode).
  Never saves. Main thread only. }

interface

uses
  ToolsAPI, RADAgent.Approval, RADAgent.FormEdits;

function SetEvent(const Editor: IOTAFormEditor; const Args: TFormToolArgs;
  const Approval: IAgentApproval; out Problem: string): Boolean;

implementation

uses
  System.SysUtils, System.StrUtils, System.Classes, System.TypInfo, DesignIntf,
  RADAgent.FormDesigner, RADAgent.Lang, RADAgent.HandlerCode;

function EventNames(Instance: TComponent): string;
var
  Props: PPropList;
  Count, Index: Integer;
begin
  Result := '';
  Count := GetPropList(Instance.ClassInfo, [tkMethod], nil);
  GetMem(Props, Count * SizeOf(PPropInfo));
  try
    GetPropList(Instance.ClassInfo, [tkMethod], Props);
    for Index := 0 to Count - 1 do
      Result := Result + IfThen(Result <> '', ', ') + string(Props[Index].Name);
  finally
    FreeMem(Props);
  end;
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
    Problem := 'Component not found: ' + Args.Component;
    Exit;
  end;
  Prop := GetPropInfo(Instance, Args.Event);
  if (Prop = nil) or (Prop.PropType^.Kind <> tkMethod) then
  begin
    { The FMX designer's form class publishes fewer events than TForm (no drag events). }
    Problem := 'Not an event property of ' + Instance.ClassName + ' in the designer: ' + Args.Event +
      '. Its events: ' + EventNames(Instance) + '. Assign other events in code (for example in ' +
      'the OnCreate handler).';
    Exit;
  end;
  if (Args.Handler <> '') and not IsValidIdent(Args.Handler) then
  begin
    Problem := 'Not a valid method name: ' + Args.Handler;
    Exit;
  end;
  Designer := DesignerOf(Editor);
  if Designer = nil then
  begin
    Problem := 'Form designer not found.';
    Exit;
  end;
  if not ApprovedEdit(Approval, Args.Path, TrF('formedits.eventPreview', [Instance.Name,
    string(Prop.Name), PropText(Editor, Instance, Prop), IfThen(Args.Handler <> '',
    Args.Handler, Tr('formedits.disconnectEvent'))]), Problem) then
    Exit;
  if FindNative(Editor, Args.Component) <> Instance then
  begin
    Problem := 'Component changed while waiting for approval.';
    Exit;
  end;
  try
    { CreateMethod returns the existing method when the name exists, or adds a stub (Delphi).
      The C++ designer writes no code, so the handler is written first (RADAgent.HandlerCode). }
    if Args.Handler = '' then
    begin
      Method.Code := nil;
      Method.Data := nil;
    end
    else
    begin
      if IsCppForm(Editor) and not EnsureCppHandler(Editor, RootOf(Editor).ClassName, Args.Handler,
        Prop.PropType^, Problem) then
        Exit;
      Method := Designer.CreateMethod(Args.Handler, GetTypeData(Prop.PropType^));
      if not IsCppForm(Editor) then
        KeepDelphiHandler(Editor, RootOf(Editor).ClassName, Args.Handler);
    end;
    SetMethodProp(Instance, Prop, Method);
  except
    on E: Exception do
    begin
      Problem := 'Failed to connect event: ' + E.Message;
      Exit;
    end;
  end;
  MarkDesignerModified(Editor);
  Result := True;
end;

end.
