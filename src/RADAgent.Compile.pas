unit RADAgent.Compile;

{ Active project build. BuildProject only. Progress dialog is hidden for the call. }

interface

uses
  RADAgent.RpcProtocol;

function BuildActiveProjectJson: string;
procedure InstallCompileNotifier;
procedure RemoveCompileNotifier;

implementation

uses
  System.SysUtils, System.Variants, Winapi.Windows, Vcl.Forms, ToolsAPI, RADAgent.IdeContext, RADAgent.Lang,
  RADAgent.CppDiagnostics;

const
  HideProgressDialog = True;
  ErrorInsightWaitMs = 8000;

type
  TCompileNotifier = class(TNotifierObject, IOTACompileNotifier)
  protected
    procedure AfterSave;
    procedure BeforeSave;
    procedure Destroyed;
    procedure Modified;
    procedure ProjectCompileStarted(const Project: IOTAProject; Mode: TOTACompileMode);
    procedure ProjectCompileFinished(const Project: IOTAProject; Result: TOTACompileResult);
    procedure ProjectGroupCompileStarted(Mode: TOTACompileMode);
    procedure ProjectGroupCompileFinished(Result: TOTACompileResult);
  end;

var
  GNotifier: IOTACompileNotifier;
  GNotifierIndex: Integer;

procedure TCompileNotifier.AfterSave;
begin
end;

procedure TCompileNotifier.BeforeSave;
begin
end;

procedure TCompileNotifier.Destroyed;
begin
end;

procedure TCompileNotifier.Modified;
begin
end;

procedure TCompileNotifier.ProjectCompileStarted(const Project: IOTAProject; Mode: TOTACompileMode);
begin
end;

procedure TCompileNotifier.ProjectCompileFinished(const Project: IOTAProject; Result: TOTACompileResult);
begin
end;

procedure TCompileNotifier.ProjectGroupCompileStarted(Mode: TOTACompileMode);
begin
end;

procedure TCompileNotifier.ProjectGroupCompileFinished(Result: TOTACompileResult);
begin
end;

procedure InstallCompileNotifier;
var
  Services: IOTACompileServices;
begin
  if GNotifierIndex >= 0 then
    Exit;
  GNotifier := TCompileNotifier.Create;
  Services := BorlandIDEServices as IOTACompileServices;
  GNotifierIndex := Services.AddNotifier(GNotifier);
end;

procedure RemoveCompileNotifier;
var
  Services: IOTACompileServices;
begin
  if (GNotifierIndex < 0) or (BorlandIDEServices = nil) then
    Exit;
  if Supports(BorlandIDEServices, IOTACompileServices, Services) then
    Services.RemoveNotifier(GNotifierIndex);
  GNotifierIndex := -1;
  GNotifier := nil;
end;

function OptionByName(const Options: IOTAOptions; const Name: string): Boolean;
var
  Names: TOTAOptionNameArray;
  Index: Integer;
begin
  Names := Options.GetOptionNames;
  for Index := 0 to High(Names) do
    if SameText(Names[Index].Name, Name) then
      Exit(True);
  Result := False;
end;

procedure SuppressProgress(const Restore: TProc);
var
  Environment: IOTAEnvironmentOptions;
  Previous: Variant;
  HasOption: Boolean;
begin
  HasOption := False;
  Previous := Null;
  if HideProgressDialog and Supports(BorlandIDEServices, IOTAServices) then
  begin
    Environment := (BorlandIDEServices as IOTAServices).GetEnvironmentOptions;
    if OptionByName(Environment, 'ShowCompilerProgress') then
    begin
      HasOption := True;
      Previous := Environment.Values['ShowCompilerProgress'];
      Environment.Values['ShowCompilerProgress'] := False;
    end;
  end;
  try
    Restore();
  finally
    if HasOption then
      Environment.Values['ShowCompilerProgress'] := Previous;
  end;
end;

{ Error Insight per source file. GetErrors('') returns nothing; the file name is required. }
function CollectErrors: TArray<TAgentCompileError>;
var
  Modules: IOTAModuleServices;
  Module: IOTAModule;
  ModuleErrors: IOTAModuleErrors;
  Found: TOTAErrors;
  ModuleIndex, FileIndex, ErrorIndex, Count: Integer;
  FileName: string;
  Item: TAgentCompileError;
begin
  SetLength(Result, 0);
  Modules := BorlandIDEServices as IOTAModuleServices;
  for ModuleIndex := 0 to Modules.ModuleCount - 1 do
  begin
    Module := Modules.Modules[ModuleIndex];
    if not Supports(Module, IOTAModuleErrors, ModuleErrors) then
      Continue;
    for FileIndex := 0 to Module.ModuleFileCount - 1 do
    begin
      FileName := Module.ModuleFileEditors[FileIndex].FileName;
      Found := ModuleErrors.GetErrors(FileName);
      for ErrorIndex := 0 to High(Found) do
      begin
        if Found[ErrorIndex].Severity <> 1 then
          Continue;
        Item.FileName := FileName;
        Item.Line := Found[ErrorIndex].Start.Line;
        Item.Col := Found[ErrorIndex].Start.CharIndex + 1;
        Item.Msg := Found[ErrorIndex].Text;
        Count := Length(Result);
        SetLength(Result, Count + 1);
        Result[Count] := Item;
      end;
    end;
  end;
end;

{ Error Insight lags the build by a few seconds after an edit. Pump messages until it reports. }
function CollectErrorsAfterFailure: TArray<TAgentCompileError>;
var
  Deadline: UInt64;
begin
  Result := CollectErrors;
  Deadline := GetTickCount64 + ErrorInsightWaitMs;
  while (Length(Result) = 0) and (GetTickCount64 < Deadline) do
  begin
    Application.ProcessMessages;
    Sleep(100);
    Result := CollectErrors;
  end;
end;

function BuildActiveProjectJson: string;
var
  Project: IOTAProject;
  Configs: IOTAProjectOptionsConfigurations;
  ConfigName, PlatformName: string;
  Ok, IsCpp: Boolean;
  Errors: TArray<TAgentCompileError>;
  Messages: IOTAMessageServices;
begin
  if GetCurrentThreadId <> MainThreadID then
    raise Exception.Create('ToolsAPI is main-thread only');
  Project := CurrentProject;
  ConfigName := '';
  PlatformName := '';
  if Project = nil then
  begin
    ReportNoProject;
    SetLength(Errors, 1);
    Errors[0].FileName := '';
    Errors[0].Line := 0;
    Errors[0].Col := 0;
    Errors[0].Msg := 'No active project.';
    Exit(BuildCompileResultJson(False, '', '', Errors));
  end;
  if Supports(Project.ProjectOptions, IOTAProjectOptionsConfigurations, Configs) then
  begin
    ConfigName := Configs.ActiveConfigurationName;
    PlatformName := Configs.ActivePlatformName;
  end;
  Messages := BorlandIDEServices as IOTAMessageServices;
  Messages.ClearCompilerMessages;
  Ok := False;
  SuppressProgress(
    procedure
    begin
      Ok := Project.ProjectBuilder.BuildProject(cmOTABuild, True);
    end);
  IsCpp := SameText(Project.Personality, sCBuilderPersonality);
  if Ok then
  begin
    Messages.AddToolMessage('', Tr('compile.buildSuccess'), 'RAD Agent', 0, 0);
    SetLength(Errors, 0);
    if IsCpp then
      NoteCppBuildOk(Project.FileName, ConfigName, PlatformName);
  end
  else
  begin
    { Error Insight has nothing for C++; its compiler is asked again instead. }
    if IsCpp then
      Errors := CppBuildErrors(Project, PlatformName, ConfigName)
    else
      Errors := CollectErrorsAfterFailure;
    if Length(Errors) = 0 then
    begin
      SetLength(Errors, 1);
      Errors[0].FileName := Project.FileName;
      Errors[0].Line := 0;
      Errors[0].Col := 0;
      Errors[0].Msg := 'Build failed; no compiler error found in the sources (see the IDE Messages view, e.g. a linker error).';
    end;
    Messages.AddToolMessage(Project.FileName, Tr('compile.buildFailed'), 'RAD Agent', 0, 0);
  end;
  Result := BuildCompileResultJson(Ok, ConfigName, PlatformName, Errors);
end;

initialization
  GNotifierIndex := -1;

end.
