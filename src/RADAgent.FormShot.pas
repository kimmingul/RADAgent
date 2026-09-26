unit RADAgent.FormShot;

{ rad.form_screenshot: a PNG of a form as the designer shows it, so the model can check layout
  (overlaps, alignment, clipped captions) instead of guessing from coordinates. VCL forms paint
  themselves into a bitmap (PaintTo); FMX forms are not VCL controls, so the designer is shown and
  its form window is copied from the screen. Main thread only. }

interface

{ ImagePng is base64 PNG; Text describes what was captured (or the problem). }
function FormScreenshot(const Path: string; out ImagePng, Text: string): Boolean;

implementation

uses
  System.SysUtils, System.Classes, System.NetEncoding, System.TypInfo, Winapi.Windows, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, ToolsAPI, RADAgent.FormDesigner;

var
  GFound, GLastVisible: HWND;
  GVisible: Integer;
  GWanted, GWantedCaption: string;

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
    Result := StringReplace(StringReplace(Result, #13, '', [rfReplaceAll]), #10, '', [rfReplaceAll]);
  finally
    Stream.Free;
    Wic.Free;
  end;
end;

function FindFmxForm(Wnd: HWND; Param: LPARAM): BOOL; stdcall;
var
  Name: array[0..255] of Char;
begin
  Result := True;
  if IsWindowVisible(Wnd) and (GetClassName(Wnd, Name, Length(Name)) > 0) and
    ((string(Name) = 'FMTForm') or (string(Name) = 'FMTControlForm')) then
  begin
    Inc(GVisible);
    GLastVisible := Wnd;
    GetWindowText(Wnd, Name, Length(Name));
    if SameText(string(Name), GWanted) or ((GWantedCaption <> '') and (string(Name) = GWantedCaption)) then
    begin
      GFound := Wnd;
      Result := False;
    end;
  end;
end;

{ The part of Wnd not clipped by its parents (the designer scrolls a form larger than its view). }
function VisibleBounds(Wnd: HWND): TRect;
var
  Parent: HWND;
  Client: TRect;
begin
  GetWindowRect(Wnd, Result);
  Parent := GetParent(Wnd);
  while Parent <> 0 do
  begin
    GetClientRect(Parent, Client);
    MapWindowPoints(Parent, 0, Client, 2);
    IntersectRect(Result, Result, Client);
    Parent := GetParent(Parent);
  end;
end;

{ True when another program's window lies over some of Bounds (sampled on a 4 x 4 grid). }
function CoveredByOthers(const Bounds: TRect): Boolean;
var
  X, Y: Integer;
  Pid: DWORD;
begin
  for X := 1 to 4 do
    for Y := 1 to 4 do
    begin
      GetWindowThreadProcessId(WindowFromPoint(Point(Bounds.Left + Bounds.Width * X div 5,
        Bounds.Top + Bounds.Height * Y div 5)), Pid);
      if Pid <> GetCurrentProcessId then
        Exit(True);
    end;
  Result := False;
end;

{ The designer's FMX window (class FMTForm titled with the form's Caption, or its name when the
  caption is empty; FMTControlForm titled with a frame's name; else the only visible one). The
  GPU draws it, so it is copied from the screen: the IDE's own floating windows over it (the chat)
  step aside meanwhile; windows of other programs cannot, and Covered says so. }
function CaptureFmxDesigner(const Editor: IOTAFormEditor; Root: TComponent;
  Bitmap: Vcl.Graphics.TBitmap; out Covered: Boolean): Boolean;
var
  Bounds, Other: TRect;
  ScreenDc: HDC;
  Hidden: TArray<HWND>;
  Index: Integer;
  Wnd: HWND;
begin
  Result := False;
  Covered := False;
  { A module opened without an editor tab (after a reload) shows no designer until it is shown. }
  Editor.Module.Show;
  Editor.Show;
  Application.ProcessMessages;
  GFound := 0;
  GVisible := 0;
  GLastVisible := 0;
  GWanted := Root.Name;
  GWantedCaption := '';
  if GetPropInfo(Root, 'Caption') <> nil then
    GWantedCaption := GetStrProp(Root, 'Caption');
  EnumChildWindows(Application.MainForm.Handle, @FindFmxForm, 0);
  if (GFound = 0) and (GVisible = 1) then
    GFound := GLastVisible;
  if GFound = 0 then
    Exit;
  Bounds := VisibleBounds(GFound);
  if Bounds.IsEmpty then
    Exit;
  Hidden := nil;
  for Index := 0 to Screen.CustomFormCount - 1 do
  begin
    Wnd := Screen.CustomForms[Index].Handle;
    { Floating windows only (GetParent answers the owner of a popup, so the style decides). }
    if (Screen.CustomForms[Index] <> Application.MainForm) and IsWindowVisible(Wnd) and
      (GetWindowLong(Wnd, GWL_STYLE) and WS_CHILD = 0) and GetWindowRect(Wnd, Other) and
      IntersectRect(Other, Other, Bounds) then
    begin
      ShowWindow(Wnd, SW_HIDE);
      Hidden := Hidden + [Wnd];
    end;
  end;
  try
    if Hidden <> nil then
    begin
      Application.ProcessMessages;
      Sleep(150);
    end;
    Covered := CoveredByOthers(Bounds);
    Bitmap.SetSize(Bounds.Width, Bounds.Height);
    ScreenDc := GetDC(0);
    try
      Result := BitBlt(Bitmap.Canvas.Handle, 0, 0, Bounds.Width, Bounds.Height, ScreenDc, Bounds.Left,
        Bounds.Top, SRCCOPY);
    finally
      ReleaseDC(0, ScreenDc);
    end;
  finally
    for Wnd in Hidden do
      ShowWindow(Wnd, SW_SHOWNA);
  end;
end;

function FormScreenshot(const Path: string; out ImagePng, Text: string): Boolean;
var
  Editor: IOTAFormEditor;
  Root: TComponent;
  Bitmap: Vcl.Graphics.TBitmap;
  Problem: string;
  Covered: Boolean;
begin
  Result := False;
  ImagePng := '';
  Editor := FindFormEditor(Path, Problem);
  Root := nil;
  if Editor <> nil then
    Root := RootOf(Editor);
  if Root = nil then
  begin
    if Problem = '' then
      Problem := 'Failed to open form designer.';
    Text := Problem;
    Exit;
  end;
  Bitmap := Vcl.Graphics.TBitmap.Create;
  try
    Bitmap.PixelFormat := pf24bit;
    if (Root is TWinControl) and TWinControl(Root).HandleAllocated then
    begin
      Bitmap.SetSize(TWinControl(Root).ClientWidth, TWinControl(Root).ClientHeight);
      TWinControl(Root).PaintTo(Bitmap.Canvas, 0, 0);
      Text := Format('%s (%s), %d x %d, as painted by the VCL designer.',
        [Root.Name, Root.ClassName, Bitmap.Width, Bitmap.Height]);
    end
    else if CaptureFmxDesigner(Editor, Root, Bitmap, Covered) then
    begin
      Text := Format('%s (%s), %d x %d visible, as shown by the FMX designer.',
        [Root.Name, Root.ClassName, Bitmap.Width, Bitmap.Height]);
      if Covered then
        Text := Text + ' Another program''s window covers part of the IDE, so parts of the image ' +
          'may show that window instead of the form.';
    end
    else
    begin
      Text := 'Could not capture the designer.';
      Exit;
    end;
    ImagePng := PngBase64(Bitmap);
    Result := True;
  finally
    Bitmap.Free;
  end;
end;

end.
