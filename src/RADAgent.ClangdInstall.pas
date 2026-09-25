unit RADAgent.ClangdInstall;

{ Downloads the latest clangd release for Windows (github.com/clangd/clangd, LLVM, Apache-2.0)
  into %LOCALAPPDATA%\RADAgent\clangd\<version> and reports the clangd.exe path. The download
  runs on a background thread; Done is called on the main thread. No ToolsAPI. }

interface

uses
  System.SysUtils;

type
  { Path is clangd.exe, or '' with Problem set. }
  TClangdDone = reference to procedure(const Path, Version, Problem: string);

procedure InstallClangd(const Done: TClangdDone);
{ %LOCALAPPDATA%\RADAgent\clangd }
function ClangdInstallRoot: string;

implementation

uses
  System.Classes, System.IOUtils, System.JSON, System.Zip, System.Net.HttpClient,
  System.Net.URLClient;

const
  LatestRelease = 'https://api.github.com/repos/clangd/clangd/releases/latest';

function ClangdInstallRoot: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'RADAgent'), 'clangd');
end;

function Download(Client: THTTPClient; const Url: string; Target: TStream): Integer;
begin
  Result := Client.Get(Url, Target, [TNetHeader.Create('User-Agent', 'RADAgent')]).StatusCode;
end;

procedure Fetch(out Path, Version, Problem: string);
var
  Client: THTTPClient;
  Text: TStringStream;
  Data: TMemoryStream;
  Root: TJSONValue;
  Assets: TJSONArray;
  Asset: TJSONValue;
  Url, Name, Dir: string;
  Found: TArray<string>;
  Zip: TZipFile;
begin
  Path := '';
  Version := '';
  Problem := '';
  Client := THTTPClient.Create;
  Text := TStringStream.Create('', TEncoding.UTF8);
  Data := TMemoryStream.Create;
  Root := nil;
  try
    if Download(Client, LatestRelease, Text) <> 200 then
    begin
      Problem := 'GitHub release list unavailable.';
      Exit;
    end;
    Root := TJSONObject.ParseJSONValue(Text.DataString);
    if not (Root is TJSONObject) then
    begin
      Problem := 'Unexpected release list.';
      Exit;
    end;
    Version := TJSONObject(Root).GetValue<string>('tag_name', '');
    Url := '';
    if TJSONObject(Root).GetValue('assets') is TJSONArray then
    begin
      Assets := TJSONArray(TJSONObject(Root).GetValue('assets'));
      for Asset in Assets do
      begin
        Name := Asset.GetValue<string>('name', '');
        if Name.StartsWith('clangd-windows-') and Name.EndsWith('.zip') then
          Url := Asset.GetValue<string>('browser_download_url', '');
      end;
    end;
    if (Url = '') or (Version = '') then
    begin
      Problem := 'No Windows clangd in the latest release.';
      Exit;
    end;
    Dir := TPath.Combine(ClangdInstallRoot, Version);
    Found := nil;
    if TDirectory.Exists(Dir) then
      Found := TDirectory.GetFiles(Dir, 'clangd.exe', TSearchOption.soAllDirectories);
    if Length(Found) = 0 then
    begin
      if Download(Client, Url, Data) <> 200 then
      begin
        Problem := 'Download failed: ' + Url;
        Exit;
      end;
      Data.Position := 0;
      TDirectory.CreateDirectory(Dir);
      Zip := TZipFile.Create;
      try
        Zip.Open(Data, zmRead);
        Zip.ExtractAll(Dir);
      finally
        Zip.Free;
      end;
      Found := TDirectory.GetFiles(Dir, 'clangd.exe', TSearchOption.soAllDirectories);
    end;
    if Length(Found) = 0 then
      Problem := 'clangd.exe not found in ' + Dir
    else
      Path := Found[0];
  finally
    Root.Free;
    Data.Free;
    Text.Free;
    Client.Free;
  end;
end;

procedure InstallClangd(const Done: TClangdDone);
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      Path, Version, Problem: string;
    begin
      try
        Fetch(Path, Version, Problem);
      except
        on E: Exception do
          Problem := E.Message;
      end;
      TThread.Queue(TThread(nil),
        procedure
        begin
          Done(Path, Version, Problem);
        end);
    end).Start;
end;

end.
