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
function IsClangdInstalling: Boolean;
{ %LOCALAPPDATA%\RADAgent\clangd }
function ClangdInstallRoot: string;

implementation

uses
  System.Classes, System.IOUtils, System.JSON, System.Zip, System.Net.HttpClient,
  System.Net.URLClient;

const
  LatestRelease = 'https://api.github.com/repos/clangd/clangd/releases/latest';

type
  TClangdDownloadThread = class(TThread)
  private
    FDone: TClangdDone;
    FClient: THTTPClient;
    FPath, FVersion, FProblem: string;
    procedure DoReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64; var AAbort: Boolean);
    procedure DoCompleted;
  protected
    procedure Execute; override;
  public
    constructor Create(const Done: TClangdDone);
    destructor Destroy; override;
  end;

var
  GDownloadThread: TClangdDownloadThread = nil;

function ClangdInstallRoot: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'RADAgent'), 'clangd');
end;

function IsClangdInstalling: Boolean;
begin
  Result := (GDownloadThread <> nil) and not GDownloadThread.Finished;
end;

function Download(Client: THTTPClient; const Url: string; Target: TStream): Integer;
begin
  Result := Client.Get(Url, Target, [TNetHeader.Create('User-Agent', 'RADAgent')]).StatusCode;
end;

constructor TClangdDownloadThread.Create(const Done: TClangdDone);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FDone := Done;
  FClient := THTTPClient.Create;
  FClient.ConnectionTimeout := 15000;
  FClient.ResponseTimeout := 60000;
  FClient.OnReceiveData := DoReceiveData;
end;

destructor TClangdDownloadThread.Destroy;
begin
  FClient.Free;
  inherited Destroy;
end;

procedure TClangdDownloadThread.DoReceiveData(const Sender: TObject; AContentLength, AReadCount: Int64;
  var AAbort: Boolean);
begin
  if Terminated then
    AAbort := True;
end;

procedure TClangdDownloadThread.DoCompleted;
begin
  if Assigned(FDone) then
    FDone(FPath, FVersion, FProblem);
end;

procedure TClangdDownloadThread.Execute;
var
  Text: TStringStream;
  Data: TMemoryStream;
  Root, Asset: TJSONValue;
  Assets: TJSONArray;
  Url, Name, Dir: string;
  Found: TArray<string>;
  Zip: TZipFile;
begin
  FPath := '';
  FVersion := '';
  FProblem := '';
  Text := TStringStream.Create('', TEncoding.UTF8);
  Data := TMemoryStream.Create;
  Root := nil;
  try
    try
      if Terminated then
        Exit;
      if Download(FClient, LatestRelease, Text) <> 200 then
      begin
        if Terminated then
          FProblem := 'Download cancelled.'
        else
          FProblem := 'GitHub release list unavailable.';
        Exit;
      end;
      if Terminated then
        Exit;
      Root := TJSONObject.ParseJSONValue(Text.DataString);
      if not (Root is TJSONObject) then
      begin
        FProblem := 'Unexpected release list.';
        Exit;
      end;
      FVersion := TJSONObject(Root).GetValue<string>('tag_name', '');
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
      if (Url = '') or (FVersion = '') then
      begin
        FProblem := 'No Windows clangd in the latest release.';
        Exit;
      end;
      Dir := TPath.Combine(ClangdInstallRoot, FVersion);
      Found := nil;
      if TDirectory.Exists(Dir) then
        Found := TDirectory.GetFiles(Dir, 'clangd.exe', TSearchOption.soAllDirectories);
      if Length(Found) = 0 then
      begin
        if Terminated then
          Exit;
        if Download(FClient, Url, Data) <> 200 then
        begin
          if Terminated then
            FProblem := 'Download cancelled.'
          else
            FProblem := 'Download failed: ' + Url;
          Exit;
        end;
        if Terminated then
          Exit;
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
        FProblem := 'clangd.exe not found in ' + Dir
      else
        FPath := Found[0];
    except
      on E: Exception do
        if Terminated then
          FProblem := 'Download cancelled.'
        else
          FProblem := E.Message;
    end;
  finally
    Root.Free;
    Data.Free;
    Text.Free;
  end;

  if Terminated and (FProblem = '') then
    FProblem := 'Download cancelled.';

  if not Terminated then
    Queue(Self, DoCompleted);
end;

procedure InstallClangd(const Done: TClangdDone);
begin
  if IsClangdInstalling then
    Exit;
  if GDownloadThread <> nil then
  begin
    GDownloadThread.WaitFor;
    FreeAndNil(GDownloadThread);
  end;
  GDownloadThread := TClangdDownloadThread.Create(Done);
  GDownloadThread.Start;
end;

initialization

finalization
  if GDownloadThread <> nil then
  begin
    GDownloadThread.Terminate;
    GDownloadThread.WaitFor;
    TThread.RemoveQueuedEvents(GDownloadThread);
    FreeAndNil(GDownloadThread);
  end;

end.
