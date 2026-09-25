unit RADAgent.Skills;

{ The RAD Studio skills in the BPL (src\skills, RCDATA): Delphi or C++Builder conventions, component
  usage and project layout. The one that fits the project is written to %TEMP%\RADAgent\skills\<lang>
  and that folder joins omp's skills.customDirectories, after the user's own folders. No ToolsAPI. }

interface

type
  TSkillSet = record
    { Folder for skills.customDirectories ('' when the resource is missing) and the skill name. }
    Dir, Name: string;
  end;

{ Language: 'delphi' or 'cpp'. }
function WriteSkill(const Language: string): TSkillSet;
{ The --config JSON: rad.* devices, plus UserDirs followed by Skills.Dir when there is one. }
function HostConfigJson(const Skills: TSkillSet; const UserDirs: TArray<string>): string;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils, System.JSON, Winapi.Windows, RADAgent.Options;

function WriteSkill(const Language: string): TSkillSet;
var
  Resource: string;
  Stream: TResourceStream;
  Target: string;
begin
  Result := Default(TSkillSet);
  if Language = 'cpp' then
  begin
    Resource := 'SKILL_CPP';
    Result.Name := 'radstudio-cpp';
  end
  else
  begin
    Resource := 'SKILL_DELPHI';
    Result.Name := 'radstudio-delphi';
  end;
  if FindResource(HInstance, PChar(Resource), RT_RCDATA) = 0 then
    Exit;
  Result.Dir := AgentTempRoot + 'skills\' + Language;
  Target := TPath.Combine(TPath.Combine(Result.Dir, Result.Name), 'SKILL.md');
  ForceDirectories(ExtractFileDir(Target));
  Stream := TResourceStream.Create(HInstance, Resource, RT_RCDATA);
  try
    try
      Stream.SaveToFile(Target);
    except
      { Another IDE is writing the same file: its content is the same. }
      if not FileExists(Target) then
        Result.Dir := '';
    end;
  finally
    Stream.Free;
  end;
end;

function HostConfigJson(const Skills: TSkillSet; const UserDirs: TArray<string>): string;
var
  Root: TJSONObject;
  Dirs: TJSONArray;
  Dir: string;
begin
  Root := TJSONObject.ParseJSONValue(OmpHostConfig) as TJSONObject;
  try
    if Skills.Dir <> '' then
    begin
      { An overlay replaces the list, so the user's folders are repeated first. }
      Dirs := TJSONArray.Create;
      for Dir in UserDirs do
        if Dir <> '' then
          Dirs.Add(Dir);
      Dirs.Add(Skills.Dir);
      Root.AddPair('skills', TJSONObject.Create(TJSONPair.Create('customDirectories', Dirs)));
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

end.
