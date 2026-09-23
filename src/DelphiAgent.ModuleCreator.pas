unit DelphiAgent.ModuleCreator;

{ rad.new_module: adds a form, frame, data module or plain unit to the active project through
  IOTAModuleServices.CreateModule. The IDE writes the source and form file for the project's
  language and framework. Never saves. Main thread only. }

interface

uses
  DelphiAgent.Approval;

{ Kind: form, frame, datamodule or unit. Name: optional form (or unit) name. }
function NewModule(const Kind, Name: string; const Approval: IAgentApproval;
  out ResultText: string): Boolean;

implementation

uses
  System.SysUtils, System.JSON, ToolsAPI, DelphiAgent.IdeContext;

type
  TModuleCreator = class(TInterfacedObject, IOTACreator, IOTAModuleCreator)
  private
    FOwner: IOTAModule;
    FCreatorType, FAncestor, FFormName: string;
  public
    constructor Create(const Owner: IOTAModule; const CreatorType, Ancestor, FormName: string);
    { IOTACreator }
    function GetCreatorType: string;
    function GetExisting: Boolean;
    function GetFileSystem: string;
    function GetOwner: IOTAModule;
    function GetUnnamed: Boolean;
    { IOTAModuleCreator }
    function GetAncestorName: string;
    function GetImplFileName: string;
    function GetIntfFileName: string;
    function GetFormName: string;
    function GetMainForm: Boolean;
    function GetShowForm: Boolean;
    function GetShowSource: Boolean;
    function NewFormFile(const FormIdent, AncestorIdent: string): IOTAFile;
    function NewImplSource(const ModuleIdent, FormIdent, AncestorIdent: string): IOTAFile;
    function NewIntfSource(const ModuleIdent, FormIdent, AncestorIdent: string): IOTAFile;
    procedure FormCreated(const FormEditor: IOTAFormEditor);
  end;

constructor TModuleCreator.Create(const Owner: IOTAModule; const CreatorType, Ancestor, FormName: string);
begin
  inherited Create;
  FOwner := Owner;
  FCreatorType := CreatorType;
  FAncestor := Ancestor;
  FFormName := FormName;
end;

function TModuleCreator.GetCreatorType: string;
begin
  Result := FCreatorType;
end;

function TModuleCreator.GetExisting: Boolean;
begin
  Result := False;
end;

function TModuleCreator.GetFileSystem: string;
begin
  Result := '';
end;

function TModuleCreator.GetOwner: IOTAModule;
begin
  Result := FOwner;
end;

function TModuleCreator.GetUnnamed: Boolean;
begin
  Result := True;
end;

function TModuleCreator.GetAncestorName: string;
begin
  Result := FAncestor;
end;

function TModuleCreator.GetImplFileName: string;
begin
  Result := '';
end;

function TModuleCreator.GetIntfFileName: string;
begin
  Result := '';
end;

function TModuleCreator.GetFormName: string;
begin
  Result := FFormName;
end;

function TModuleCreator.GetMainForm: Boolean;
begin
  Result := False;
end;

function TModuleCreator.GetShowForm: Boolean;
begin
  Result := True;
end;

function TModuleCreator.GetShowSource: Boolean;
begin
  Result := True;
end;

{ nil lets the IDE generate the default source and form file for the project's framework. }
function TModuleCreator.NewFormFile(const FormIdent, AncestorIdent: string): IOTAFile;
begin
  Result := nil;
end;

function TModuleCreator.NewImplSource(const ModuleIdent, FormIdent, AncestorIdent: string): IOTAFile;
begin
  Result := nil;
end;

function TModuleCreator.NewIntfSource(const ModuleIdent, FormIdent, AncestorIdent: string): IOTAFile;
begin
  Result := nil;
end;

procedure TModuleCreator.FormCreated(const FormEditor: IOTAFormEditor);
begin
end;

function NewModule(const Kind, Name: string; const Approval: IAgentApproval;
  out ResultText: string): Boolean;
var
  Project: IOTAProject;
  Creator: TModuleCreator;
  CreatorRef: IOTAModuleCreator;
  Module: IOTAModule;
  CreatorType, Ancestor, Caption: string;
  Obj: TJSONObject;
  Index: Integer;
begin
  Result := False;
  Project := CurrentProject;
  if Project = nil then
  begin
    ResultText := '활성 프로젝트가 없습니다.';
    Exit;
  end;
  CreatorType := sForm;
  if SameText(Kind, 'form') then
    Ancestor := 'Form'
  else if SameText(Kind, 'frame') then
    Ancestor := 'Frame'
  else if SameText(Kind, 'datamodule') then
    Ancestor := 'DataModule'
  else if SameText(Kind, 'unit') then
  begin
    CreatorType := sUnit;
    Ancestor := '';
  end
  else
  begin
    ResultText := 'kind는 form, frame, datamodule, unit 중 하나입니다.';
    Exit;
  end;
  if (Name <> '') and not IsValidIdent(Name) then
  begin
    ResultText := '올바른 식별자가 아닙니다: ' + Name;
    Exit;
  end;
  Caption := Format('새 %s 추가: %s (프로젝트 %s)', [LowerCase(Kind), Name,
    ExtractFileName(Project.FileName)]);
  if (Approval = nil) or not Approval.ApproveChange(Project.FileName, '', Caption) then
  begin
    ResultText := SEditCancelled;
    Exit(True);
  end;
  Creator := TModuleCreator.Create(Project, CreatorType, Ancestor, Name);
  CreatorRef := Creator;
  Module := (BorlandIDEServices as IOTAModuleServices).CreateModule(CreatorRef);
  if Module = nil then
  begin
    ResultText := '모듈을 만들지 못했습니다.';
    Exit;
  end;
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('ok', TJSONTrue.Create);
    for Index := 0 to Module.ModuleFileCount - 1 do
      if SameText(ExtractFileExt(Module.ModuleFileEditors[Index].FileName), '.pas') or
        SameText(ExtractFileExt(Module.ModuleFileEditors[Index].FileName), '.cpp') then
        Obj.AddPair('file', Module.ModuleFileEditors[Index].FileName);
    Obj.AddPair('module', Module.FileName);
    ResultText := Obj.ToJSON;
  finally
    Obj.Free;
  end;
  Result := True;
end;

end.
