unit RADAgent.AppShot;

{ rad.app_screenshot: launch the built application executable, wait for its main window,
  capture a screenshot as PNG base64, and close the application cleanly. Main thread only. }

interface

uses
  System.SysUtils;

function ProjectExecutable(out ExePath, Problem: string): Boolean;

function AppScreenshot(const ExePath, Args, WindowTitle: string; WaitMs: Integer;
  const ProjectDir: string; out ImagePng, Text: string): Boolean; overload;

function AppScreenshot(const ExePath, Args, WindowTitle: string; WaitMs: Integer;
  out ImagePng, Text: string): Boolean; overload;

implementation

uses
  System.Classes, System.IOUtils, System.StrUtils, System.NetEncoding, Winapi.Windows,
  Winapi.Messages, Vcl.Graphics, ToolsAPI, RADAgent.IdeContext;

const
  PW_RENDERFULLCONTENT = 2;

function PrintWindow(hWnd: HWND; hdcBlt: HDC; nFlags: UINT): BOOL; stdcall; external 'user32.dll';

function PngBase64(Bitmap: Vcl.Graphics.TBitmap): string;
var
  Wic: TWICImage;
  Stream: TBytesStream;
begin
  Wic := TWICImage.Create;
  Stream := TBytesStream.Create;
  try
    Wic.Assign(Bitmap);
    Wic.ImageFormat := wifPng;
    Wic.SaveToStream(Stream);
    Result := TNetEncoding.Base64.EncodeBytesToString(Copy(Stream.Bytes, 0, Stream.Size));
    Result := Result.Replace(#13, '').Replace(#10, '');
  finally
    Stream.Free;
    Wic.Free;
  end;
end;

function IsSingleColor(Bitmap: Vcl.Graphics.TBitmap): Boolean;
var
  X, Y: Integer;
  First: TRGBTriple;
  Row: PRGBTriple;
begin
  Result := True;
  if (Bitmap.Width <= 0) or (Bitmap.Height <= 0) then Exit;
  First := PRGBTriple(Bitmap.ScanLine[0])^;
  for Y := 0 to Bitmap.Height - 1 do
  begin
    Row := Bitmap.ScanLine[Y];
    for X := 0 to Bitmap.Width - 1 do
    begin
      if (Row.rgbtRed <> First.rgbtRed) or (Row.rgbtGreen <> First.rgbtGreen) or
         (Row.rgbtBlue <> First.rgbtBlue) then Exit(False);
      Inc(Row);
    end;
  end;
end;

type
  PEnumContext = ^TEnumContext;
  TEnumContext = record
    TargetPid: DWORD;
    TargetTitle: string;
    KnownTargetWnd: HWND;
    TargetWnd: HWND;
    TargetCaption: string;
    TargetRect: TRect;
    OtherCaptions: TArray<string>;
    FoundCandidate: Boolean;
  end;

function EnumWindowsProc(Wnd: HWND; lParam: LPARAM): BOOL; stdcall;
var
  Ctx: PEnumContext;
  Pid: DWORD;
  R: TRect;
  W, H: Integer;
  Buf: array[0..511] of Char;
  Caption: string;
begin
  Result := True;
  Ctx := PEnumContext(lParam);
  GetWindowThreadProcessId(Wnd, Pid);
  if (Pid <> Ctx.TargetPid) or (not IsWindowVisible(Wnd)) or
     ((GetWindowLong(Wnd, GWL_STYLE) and WS_CHILD) <> 0) then Exit;

  GetWindowRect(Wnd, R);
  W := R.Right - R.Left;
  H := R.Bottom - R.Top;
  if (W <= 0) or (H <= 0) then Exit;

  if GetWindowText(Wnd, Buf, Length(Buf)) > 0 then Caption := string(Buf) else Caption := '';

  if (Ctx.KnownTargetWnd <> 0) and (Wnd = Ctx.KnownTargetWnd) then
  begin
    Ctx.TargetWnd := Wnd;
    Ctx.TargetCaption := Caption;
    Ctx.FoundCandidate := True;
  end
  else if (Ctx.KnownTargetWnd = 0) and (not Ctx.FoundCandidate) and (W >= 100) and (H >= 100) and
          ((Ctx.TargetTitle = '') or ContainsText(Caption, Ctx.TargetTitle)) then
  begin
    Ctx.TargetWnd := Wnd;
    Ctx.TargetCaption := Caption;
    Ctx.FoundCandidate := True;
  end
  else
  begin
    if Caption = '' then Caption := '(untitled)';
    Ctx.OtherCaptions := Ctx.OtherCaptions + [Format('"%s"', [Caption])];
  end;
end;

function CloseWindowsProc(Wnd: HWND; lParam: LPARAM): BOOL; stdcall;
var
  Pid: DWORD;
begin
  Result := True;
  GetWindowThreadProcessId(Wnd, Pid);
  if (Pid = DWORD(lParam)) and ((GetWindowLong(Wnd, GWL_STYLE) and WS_CHILD) = 0) then
    PostMessage(Wnd, WM_CLOSE, 0, 0);
end;

function IsBuildStale(const ExePath, ProjectDir: string; out NewestSrc: string): Boolean;
var
  ExeTime, NewestTime, SrcTime: TDateTime;
  Ext, Path: string;
begin
  Result := False;
  NewestSrc := '';
  if (ProjectDir = '') or (not TDirectory.Exists(ProjectDir)) or (not TFile.Exists(ExePath)) then Exit;
  try
    ExeTime := TFile.GetLastWriteTime(ExePath);
    NewestTime := 0;
    for Ext in ['*.pas', '*.dfm', '*.fmx'] do
      for Path in TDirectory.GetFiles(ProjectDir, Ext, TSearchOption.soAllDirectories) do
        if not (ContainsText(Path, '\.git\') or ContainsText(Path, '\__history\') or
                ContainsText(Path, '\__recovery\')) then
        begin
          SrcTime := TFile.GetLastWriteTime(Path);
          if SrcTime > NewestTime then begin NewestTime := SrcTime; NewestSrc := Path; end;
        end;
    Result := (NewestTime > 0) and (NewestTime > ExeTime);
  except
    Result := False;
  end;
end;

function ProjectExecutable(out ExePath, Problem: string): Boolean;
var
  Project: IOTAProject;
  Options: IOTAProjectOptions;
  Configs: IOTAProjectOptionsConfigurations;
  Config: IOTABuildConfiguration;
  Plat, Target, OutDir, BaseName, AppType: string;

  function Fail(const Msg: string): Boolean;
  begin
    Problem := Msg;
    Result := False;
  end;

begin
  ExePath := '';
  Problem := '';
  if GetCurrentThreadId <> MainThreadID then
    Exit(Fail('ProjectExecutable must be called on the main thread.'));

  Project := CurrentProject;
  if Project = nil then Exit(Fail('No active project.'));

  Plat := Project.CurrentPlatform;
  if not (SameText(Plat, 'Win32') or SameText(Plat, 'Win64') or SameText(Plat, 'Win64x')) then
    Exit(Fail(Format('Project platform "%s" is not Win32 or Win64.', [Plat])));

  AppType := Project.ApplicationType;
  if (AppType <> '') and
     not (SameText(AppType, sApplication) or SameText(AppType, sConsole) or
          SameText(AppType, sCppConsoleExe) or SameText(AppType, sCppGuiApplication) or
          SameText(AppType, sCppVCLApplication)) then
    Exit(Fail(Format('Project is not an application (type: %s).', [AppType])));

  Options := Project.ProjectOptions;
  if Options = nil then Exit(Fail('Project has no options.'));

  Target := Options.TargetName;
  if Target = '' then
  begin
    BaseName := ChangeFileExt(ExtractFileName(Project.FileName), '');
    OutDir := '';
    if Supports(Options, IOTAProjectOptionsConfigurations, Configs) and (Configs.ActiveConfiguration <> nil) then
    begin
      Config := Configs.ActiveConfiguration;
      OutDir := Config.GetValue('DCC_ExeOutput');
      if OutDir = '' then OutDir := Config.GetValue('BCC_OutputDir');
    end;
    if OutDir = '' then OutDir := Format('.\%s\%s', [Plat, Project.CurrentConfiguration]);
    Target := TPath.Combine(OutDir, BaseName + '.exe');
  end;

  if TPath.IsRelativePath(Target) then Target := TPath.Combine(ExtractFilePath(Project.FileName), Target);
  Target := ExpandFileName(Target);

  if not SameText(ExtractFileExt(Target), '.exe') then
    Exit(Fail(Format('Project output "%s" is not an executable application.', [ExtractFileName(Target)])));
  if not TFile.Exists(Target) then
    Exit(Fail(Format('Executable not found at "%s". Build the project first.', [Target])));

  ExePath := Target;
  Result := True;
end;

function AppScreenshot(const ExePath, Args, WindowTitle: string; WaitMs: Integer;
  out ImagePng, Text: string): Boolean;
begin
  Result := AppScreenshot(ExePath, Args, WindowTitle, WaitMs, '', ImagePng, Text);
end;

function AppScreenshot(const ExePath, Args, WindowTitle: string; WaitMs: Integer;
  const ProjectDir: string; out ImagePng, Text: string): Boolean;
var
  SI: TStartupInfo;
  PI: TProcessInformation;
  CmdLine, TargetCaption, CapDesc, NewestSrc: string;
  StartTime, SettleStart: UInt64;
  ActualWait, W, H: Integer;
  TargetWnd: HWND;
  Ctx: TEnumContext;
  ExitCode: DWORD;
  R: TRect;
  Buf: array[0..511] of Char;
  Bitmap: Vcl.Graphics.TBitmap;
  PrintSuccess, CapturedViaScreen, Terminated: Boolean;
  ScreenDc: HDC;

  function Fail(const Msg: string): Boolean;
  begin
    Text := Msg;
    Result := False;
  end;

begin
  ImagePng := '';
  Text := '';

  if GetCurrentThreadId <> MainThreadID then
    Exit(Fail('AppScreenshot must be called on the main thread.'));
  if not TFile.Exists(ExePath) then
    Exit(Fail(Format('Executable not found: "%s".', [ExePath])));

  CmdLine := '"' + ExePath + '"';
  if Trim(Args) <> '' then CmdLine := CmdLine + ' ' + Trim(Args);
  UniqueString(CmdLine);

  ZeroMemory(@SI, SizeOf(SI));
  SI.cb := SizeOf(SI);
  ZeroMemory(@PI, SizeOf(PI));

  if not CreateProcess(nil, PChar(CmdLine), nil, nil, False, 0, nil,
    PChar(ExtractFilePath(ExePath)), SI, PI) then
    Exit(Fail(Format('Failed to start process: %s', [SysErrorMessage(GetLastError)])));

  Terminated := False;
  try
    StartTime := GetTickCount64;
    TargetWnd := 0;

    while (GetTickCount64 - StartTime < 30000) do
    begin
      if WaitForSingleObject(PI.hProcess, 0) = WAIT_OBJECT_0 then
      begin
        GetExitCodeProcess(PI.hProcess, ExitCode);
        Exit(Fail(Format('Process exited with code %d before a window appeared.', [ExitCode])));
      end;
      ZeroMemory(@Ctx, SizeOf(Ctx));
      Ctx.TargetPid := PI.dwProcessId;
      Ctx.TargetTitle := WindowTitle;
      EnumWindows(@EnumWindowsProc, LPARAM(@Ctx));
      if Ctx.FoundCandidate and (Ctx.TargetWnd <> 0) then
      begin
        TargetWnd := Ctx.TargetWnd;
        Break;
      end;
      Sleep(50);
    end;

    if TargetWnd = 0 then
      Exit(Fail('Timeout (30 s) waiting for application window to appear.'));

    if WaitMs <= 0 then ActualWait := 1500
    else if WaitMs > 15000 then ActualWait := 15000
    else ActualWait := WaitMs;

    SettleStart := GetTickCount64;
    while (GetTickCount64 - SettleStart < DWORD(ActualWait)) do
    begin
      if WaitForSingleObject(PI.hProcess, 0) = WAIT_OBJECT_0 then
        Exit(Fail('Process terminated before screenshot could be captured.'));
      if GetTickCount64 - StartTime >= 30000 then Break;
      Sleep(50);
    end;

    if not IsWindow(TargetWnd) then
      Exit(Fail('Target window was destroyed before screenshot could be captured.'));

    ZeroMemory(@Ctx, SizeOf(Ctx));
    Ctx.TargetPid := PI.dwProcessId;
    Ctx.KnownTargetWnd := TargetWnd;
    EnumWindows(@EnumWindowsProc, LPARAM(@Ctx));

    GetWindowRect(TargetWnd, R);
    W := R.Right - R.Left;
    H := R.Bottom - R.Top;
    if (W <= 0) or (H <= 0) then
      Exit(Fail(Format('Invalid window dimensions (%d x %d).', [W, H])));

    if GetWindowText(TargetWnd, Buf, Length(Buf)) > 0 then TargetCaption := string(Buf)
    else TargetCaption := Ctx.TargetCaption;

    Bitmap := Vcl.Graphics.TBitmap.Create;
    try
      Bitmap.PixelFormat := pf24bit;
      Bitmap.SetSize(W, H);
      PrintSuccess := PrintWindow(TargetWnd, Bitmap.Canvas.Handle, PW_RENDERFULLCONTENT);
      CapturedViaScreen := False;

      if (not PrintSuccess) or IsSingleColor(Bitmap) then
      begin
        ShowWindow(TargetWnd, SW_RESTORE);
        SetForegroundWindow(TargetWnd);
        BringWindowToTop(TargetWnd);
        Sleep(150);

        GetWindowRect(TargetWnd, R);
        W := R.Right - R.Left;
        H := R.Bottom - R.Top;
        if (W > 0) and (H > 0) then
        begin
          Bitmap.SetSize(W, H);
          ScreenDc := GetDC(0);
          try
            BitBlt(Bitmap.Canvas.Handle, 0, 0, W, H, ScreenDc, R.Left, R.Top, SRCCOPY);
          finally
            ReleaseDC(0, ScreenDc);
          end;
          CapturedViaScreen := True;
        end;
      end;

      ImagePng := PngBase64(Bitmap);
      Result := True;
    finally
      Bitmap.Free;
    end;

    if TargetCaption <> '' then CapDesc := Format('"%s"', [TargetCaption]) else CapDesc := '(untitled)';
    Text := Format('Captured window %s (%d x %d).', [CapDesc, W, H]);

    if Length(Ctx.OtherCaptions) = 0 then Text := Text + ' No other visible windows.'
    else Text := Text + Format(' Other visible windows (%d): %s.',
      [Length(Ctx.OtherCaptions), string.Join(', ', Ctx.OtherCaptions)]);

    if CapturedViaScreen then
      Text := Text + ' Captured from screen DC (PrintWindow returned a single color).';

    if IsBuildStale(ExePath, ProjectDir, NewestSrc) then
      Text := Text + Format(' Stale build: %s is newer than the executable (compile first).',
        [ExtractFileName(NewestSrc)]);
  finally
    EnumWindows(@CloseWindowsProc, LPARAM(PI.dwProcessId));
    if WaitForSingleObject(PI.hProcess, 3000) <> WAIT_OBJECT_0 then
    begin
      TerminateProcess(PI.hProcess, 1);
      WaitForSingleObject(PI.hProcess, 1000);
      Terminated := True;
    end;
    CloseHandle(PI.hProcess);
    CloseHandle(PI.hThread);

    if Terminated then Text := Text + ' Process did not close within 3 s and was terminated.';
  end;
end;

end.
