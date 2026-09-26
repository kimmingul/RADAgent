unit RADAgent.ModuleCreator;

{ rad.new_module: adds a form, frame, data module or plain unit to the active project through
  IOTAModuleServices.CreateModule, under a descriptive unit name (RADAgent.UnitNaming). The IDE
  writes the source and form file for the project's language and framework. Saves only a form in a
  dotted unit (created under its last part, then saved as the dotted name). Main thread only. }

interface

uses
  ToolsAPI, RADAgent.Approval;

{ Kind: form, frame, datamodule or unit. UnitName: required (RADAgent.UnitNaming); Name: optional
  component name of a form, frame or data module, by default the last part of UnitName. }
function NewModule(const Kind, UnitName, Name: string; const Approval: IAgentApproval;
  out ResultText: string): Boolean;
{ The unit names of the project's modules (file names without extension). }
function ProjectUnitNames(const Project: IOTAProject): TArray<string>;

implementation

uses
  System.SysUtils, System.StrUtils, System.JSON, RADAgent.IdeContext, RADAgent.UnitNaming,
  RADAgent.UnitRename, RADAgent.Lang;

type
  TModuleCreator = class(TInterfacedObject, IOTACreator, IOTAModuleCreator)
  private
    FOwner: IOTAModule;
    FCreatorType, FAncestor, FFormName, FFramework, FUnitFile: string;
    FCpp: Boolean;
  public
    { Forms get their source from here (Delphi or C++, VCL or FMX): the IDE's default source keeps
      its own class name (TForm2) when the form gets another name, and then fails to open it. }
    { UnitFile: the new .pas/.cpp with its path; named up front so saving asks nothing. }
    constructor Create(const Owner: IOTAModule; const CreatorType, Ancestor, FormName: string;
      Cpp: Boolean; const Framework, UnitFile: string);
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

type
  TSourceFile = class(TInterfacedObject, IOTAFile)
  private
    FText: string;
  public
    constructor Create(const Text: string);
    function GetSource: string;
    function GetAge: TDateTime;
  end;

constructor TSourceFile.Create(const Text: string);
begin
  inherited Create;
  FText := Text;
end;

function TSourceFile.GetSource: string;
begin
  Result := FText;
end;

function TSourceFile.GetAge: TDateTime;
begin
  Result := -1;
end;

constructor TModuleCreator.Create(const Owner: IOTAModule; const CreatorType, Ancestor, FormName: string;
  Cpp: Boolean; const Framework, UnitFile: string);
begin
  inherited Create;
  FOwner := Owner;
  FCreatorType := CreatorType;
  FAncestor := Ancestor;
  FFormName := FormName;
  FCpp := Cpp;
  FFramework := Framework;
  FUnitFile := UnitFile;
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
  Result := False;
end;

function TModuleCreator.GetAncestorName: string;
begin
  Result := FAncestor;
end;

function TModuleCreator.GetImplFileName: string;
begin
  Result := FUnitFile;
end;

function TModuleCreator.GetIntfFileName: string;
begin
  if FCpp then
    Result := ChangeFileExt(FUnitFile, '.h')
  else
    Result := '';
end;

function ProjectUnitNames(const Project: IOTAProject): TArray<string>;
var
  Index: Integer;
  FileName: string;
begin
  Result := nil;
  for Index := 0 to Project.GetModuleCount - 1 do
  begin
    FileName := Project.GetModule(Index).FileName;
    if SameText(ExtractFileExt(FileName), '.pas') or SameText(ExtractFileExt(FileName), '.cpp') then
      Result := Result + [ChangeFileExt(ExtractFileName(FileName), '')];
  end;
end;

function TModuleCreator.GetFormName: string;
begin
  { A unit has no form; a name here makes the IDE fail inside CreateModule. }
  if FCreatorType = sForm then
    Result := FFormName
  else
    Result := '';
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

const
  Rule = '//---------------------------------------------------------------------------'#13#10;

function DelphiSource(const ModuleIdent, FormIdent, AncestorIdent, Framework: string): string;
var
  UsesList, Resource: string;
begin
  Resource := '{$R *.dfm}';
  if SameText(AncestorIdent, 'DataModule') then
    UsesList := 'System.SysUtils, System.Classes'
  else if SameText(Framework, 'FMX') then
  begin
    UsesList := 'System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,'#13#10 +
      '  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs';
    Resource := '{$R *.fmx}';
  end
  else
    UsesList := 'Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,'#13#10 +
      '  Vcl.Controls, Vcl.Forms, Vcl.Dialogs';
  if SameText(AncestorIdent, 'DataModule') then
    Resource := IfThen(SameText(Framework, 'FMX'), '{%CLASSGROUP ''FMX.Controls.TControl''}',
      '{%CLASSGROUP ''Vcl.Controls.TControl''}') + #13#10#13#10 + Resource;
  Result := 'unit ' + ModuleIdent + ';'#13#10#13#10'interface'#13#10#13#10'uses'#13#10'  ' + UsesList + ';'#13#10#13#10 +
    'type'#13#10'  T' + FormIdent + ' = class(T' + AncestorIdent + ')'#13#10'  private'#13#10 +
    '    { Private declarations }'#13#10'  public'#13#10'    { Public declarations }'#13#10'  end;'#13#10#13#10 +
    'var'#13#10'  ' + FormIdent + ': T' + FormIdent + ';'#13#10#13#10'implementation'#13#10#13#10 + Resource +
    #13#10#13#10'end.'#13#10;
end;

function TModuleCreator.NewImplSource(const ModuleIdent, FormIdent, AncestorIdent: string): IOTAFile;
var
  Fmx: Boolean;
begin
  Result := nil;
  if (FCreatorType = sUnit) and not FCpp then
    Exit(TSourceFile.Create('unit ' + ModuleIdent + ';'#13#10#13#10'interface'#13#10#13#10 +
      'implementation'#13#10#13#10'end.'#13#10));
  if FCreatorType <> sForm then
    Exit;
  if not FCpp then
    Exit(TSourceFile.Create(DelphiSource(ModuleIdent, FormIdent, AncestorIdent, FFramework)));
  Fmx := SameText(FFramework, 'FMX') and not SameText(AncestorIdent, 'DataModule');
  Result := TSourceFile.Create(Rule + IfThen(Fmx, '#include <fmx.h>', '#include <vcl.h>') + #13#10 +
    '#pragma hdrstop'#13#10#13#10'#include "' + ModuleIdent + '.h"'#13#10 + Rule +
    '#pragma package(smart_init)'#13#10'#pragma resource "' + IfThen(Fmx, '*.fmx', '*.dfm') + '"'#13#10 +
    'T' + FormIdent + ' *' + FormIdent + ';'#13#10 + Rule +
    '__fastcall T' + FormIdent + '::T' + FormIdent + '(TComponent* Owner)'#13#10 +
    #9': T' + AncestorIdent + '(Owner)'#13#10'{'#13#10'}'#13#10 + Rule);
end;

function TModuleCreator.NewIntfSource(const ModuleIdent, FormIdent, AncestorIdent: string): IOTAFile;
var
  Includes: string;
begin
  Result := nil;
  if not FCpp or (FCreatorType <> sForm) then
    Exit;
  if SameText(AncestorIdent, 'DataModule') then
    Includes := '#include <System.Classes.hpp>'#13#10
  else if SameText(FFramework, 'FMX') then
    Includes := '#include <System.Classes.hpp>'#13#10'#include <FMX.Controls.hpp>'#13#10 +
      '#include <FMX.Forms.hpp>'#13#10'#include <FMX.Types.hpp>'#13#10
  else
    Includes := '#include <System.Classes.hpp>'#13#10'#include <Vcl.Controls.hpp>'#13#10 +
      '#include <Vcl.StdCtrls.hpp>'#13#10'#include <Vcl.Forms.hpp>'#13#10;
  Result := TSourceFile.Create(Rule + '#ifndef ' + ModuleIdent + 'H'#13#10'#define ' + ModuleIdent +
    'H'#13#10 + Rule + Includes + Rule + 'class T' + FormIdent + ' : public T' + AncestorIdent + #13#10 +
    '{'#13#10'__published:'#9'// IDE-managed Components'#13#10'private:'#9'// User declarations'#13#10 +
    'public:'#9#9'// User declarations'#13#10#9'__fastcall T' + FormIdent + '(TComponent* Owner);'#13#10 +
    '};'#13#10 + Rule + 'extern PACKAGE T' + FormIdent + ' *' + FormIdent + ';'#13#10 + Rule +
    '#endif'#13#10);
end;

procedure TModuleCreator.FormCreated(const FormEditor: IOTAFormEditor);
begin
end;

function NewModule(const Kind, UnitName, Name: string; const Approval: IAgentApproval;
  out ResultText: string): Boolean;
var
  Project: IOTAProject;
  Creator: TModuleCreator;
  CreatorRef: IOTAModuleCreator;
  Module: IOTAModule;
  CreatorType, Ancestor, Caption, UnitFile, CreateFile, FormName, Problem: string;
  Obj: TJSONObject;
  Index: Integer;
  Cpp: Boolean;
begin
  Result := False;
  Project := CurrentProject;
  if Project = nil then
  begin
    ResultText := 'No active project.';
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
    ResultText := 'Kind must be one of form, frame, datamodule, or unit.';
    Exit;
  end;
  Cpp := SameText(Project.Personality, sCBuilderPersonality);
  if not CheckUnitName(Kind, UnitName, Cpp, ProjectUnitNames(Project), Problem) then
  begin
    ResultText := Problem;
    Exit;
  end;
  FormName := Name;
  if FormName = '' then
    FormName := LastPart(UnitName);
  { Form names are plain identifiers even where unit names are dotted. }
  if (CreatorType = sForm) and not IsValidIdent(FormName) then
  begin
    ResultText := 'Not a valid identifier: ' + FormName;
    Exit;
  end;
  UnitFile := IncludeTrailingPathDelimiter(ExtractFileDir(Project.FileName)) + UnitName + IfThen(Cpp, '.cpp', '.pas');
  { The IDE cannot create a form in a dotted unit ("'Xm.UI.XForm' is not a valid identifier"); the
    form is made under the last part and then saved as the dotted unit, as Save As would. }
  CreateFile := UnitFile;
  if (CreatorType = sForm) and UnitName.Contains('.') then
    CreateFile := ExtractFilePath(UnitFile) + LastPart(UnitName) + ExtractFileExt(UnitFile);
  if FileExists(UnitFile) or FileExists(CreateFile) or
    ((BorlandIDEServices as IOTAModuleServices).FindModule(UnitFile) <> nil) then
  begin
    ResultText := 'File already exists: ' + IfThen(FileExists(UnitFile), UnitFile, CreateFile);
    Exit;
  end;
  Caption := TrF('modulecreator.addCaption', [LowerCase(Kind), UnitName,
    ExtractFileName(Project.FileName)]);
  if (Approval = nil) or not Approval.ApproveChange(Project.FileName, '', Caption) then
  begin
    ResultText := SEditCancelled;
    Exit(True);
  end;
  Creator := TModuleCreator.Create(Project, CreatorType, Ancestor, IfThen(CreatorType = sForm, FormName, ''),
    Cpp, Project.FrameworkType, CreateFile);
  CreatorRef := Creator;
  try
    Module := (BorlandIDEServices as IOTAModuleServices).CreateModule(CreatorRef);
  except
    on E: Exception do
    begin
      ResultText := 'The IDE could not create the module: ' + E.Message;
      Exit;
    end;
  end;
  if Module = nil then
  begin
    ResultText := 'Failed to create module.';
    Exit;
  end;
  if (CreateFile <> UnitFile) and not SaveUnitAs(Module, UnitFile) then
  begin
    ResultText := 'The module was created as ' + CreateFile + ' but could not be saved as ' + UnitFile + '.';
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
