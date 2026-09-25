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
  System.SysUtils, System.Classes, System.NetEncoding, Winapi.Windows, Vcl.Graphics, Vcl.Controls,
  Vcl.Forms, ToolsAPI, RADAgent.FormDesigner;

var
  GFound: HWND;
  GWanted: string;

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
  if IsWindowVisible(Wnd) and (GetClassName(Wnd, Name, Length(Name)) > 0) and (string(Name) = 'FMTForm') then
  begin
    GetWindowText(Wnd, Name, Length(Name));
    if SameText(string(Name), GWanted) then
    begin
      GFound := Wnd;
      Result := False;
    end;
  end;
end;

{ The designer's FMX form window (class FMTForm, titled with the form's name), copied from the
  screen where the GPU-drawn content is. }
function CaptureFmxDesigner(const Editor: IOTAFormEditor; const RootName: string;
  Bitmap: Vcl.Graphics.TBitmap): Boolean;
var
  Bounds: TRect;
  ScreenDc: HDC;
begin
  Result := False;
  Editor.Show;
  Application.ProcessMessages;
  GFound := 0;
  GWanted := RootName;
  EnumChildWindows(Application.MainForm.Handle, @FindFmxForm, 0);
  if GFound = 0 then
    Exit;
  GetWindowRect(GFound, Bounds);
  Bitmap.SetSize(Bounds.Width, Bounds.Height);
  ScreenDc := GetDC(0);
  try
    Result := BitBlt(Bitmap.Canvas.Handle, 0, 0, Bounds.Width, Bounds.Height, ScreenDc, Bounds.Left,
      Bounds.Top, SRCCOPY);
  finally
    ReleaseDC(0, ScreenDc);
  end;
end;

function FormScreenshot(const Path: string; out ImagePng, Text: string): Boolean;
var
  Editor: IOTAFormEditor;
  Root: TComponent;
  Bitmap: Vcl.Graphics.TBitmap;
  Problem: string;
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
    else if CaptureFmxDesigner(Editor, Root.Name, Bitmap) then
      Text := Format('%s (%s), %d x %d, as shown by the FMX designer.',
        [Root.Name, Root.ClassName, Bitmap.Width, Bitmap.Height])
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
