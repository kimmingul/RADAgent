unit RADAgent.BrandIcons;

{ Provider and model logos in VCL lists (settings, /model picker). The logos are sprite strips
  (resources\brands\Brands-<dark|light>-<16|32>.png, RCDATA), one square per brand in the order of
  RADAgent.BrandTable. Owner-drawn combo boxes and list boxes keep the brand of each row in
  Items.Objects (brand + 1; nil = no logo). Main thread only. }

interface

uses
  System.Classes, System.Types, Vcl.Graphics, Vcl.StdCtrls, Vcl.Controls;

{ Draws the brand in R (square, the height of R), for a dark or light background. }
procedure DrawBrand(Canvas: TCanvas; Brand: Integer; const R: TRect);
{ Adds a row that shows Brand's logo before its text. }
procedure AddBrandItem(Items: TStrings; const Text: string; Brand: Integer);
{ Turns the combo into an owner-drawn list with logos (keeps Items). EmptyText is drawn greyed
  for an empty row (e.g. "inherit the global value"). }
procedure MakeBrandCombo(Combo: TComboBox; const EmptyText: string = '');
procedure MakeBrandList(List: TListBox);

type
  { An editable combo (csDropDown) whose list rows show logos; the edit part stays plain text so
    values such as "provider/model:high" can still be typed. }
  TBrandCombo = class(TComboBox)
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  end;

implementation

uses
  System.SysUtils, System.Math, Winapi.Windows, Winapi.Wincodec, Winapi.ActiveX,
  RADAgent.BrandTable;

type
  TBrandDrawer = class(TComponent)
  public
    EmptyText: string;
    procedure ComboDraw(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
    procedure ListDraw(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
  end;

var
  GSheets: array[Boolean, Boolean] of Vcl.Graphics.TBitmap; { [Dark, Large] }

function LoadSheet(const Name: string): Vcl.Graphics.TBitmap;
var
  Stream: TResourceStream;
  Wic: TWICImage;
  Converter: IWICFormatConverter;
  Width, Height: UINT;
  Row: Integer;
begin
  Result := nil;
  if FindResource(HInstance, PChar(Name), RT_RCDATA) = 0 then
    Exit;
  Wic := TWICImage.Create;
  Stream := TResourceStream.Create(HInstance, Name, RT_RCDATA);
  try
    Wic.LoadFromStream(Stream);
    if Failed(TWICImage.ImagingFactory.CreateFormatConverter(Converter)) or
      Failed(Converter.Initialize(Wic.Handle, GUID_WICPixelFormat32bppPBGRA, WICBitmapDitherTypeNone,
      nil, 0, WICBitmapPaletteTypeCustom)) then
      Exit;
    Converter.GetSize(Width, Height);
    Result := Vcl.Graphics.TBitmap.Create;
    Result.PixelFormat := pf32bit;
    Result.AlphaFormat := afPremultiplied;
    Result.SetSize(Width, Height);
    { Bottom-up DIB: copy row by row. }
    for Row := 0 to Integer(Height) - 1 do
    begin
      var Rect: WICRect;
      Rect.X := 0;
      Rect.Y := Row;
      Rect.Width := Width;
      Rect.Height := 1;
      Converter.CopyPixels(@Rect, Width * 4, Width * 4, Result.ScanLine[Row]);
    end;
  finally
    Stream.Free;
    Wic.Free;
  end;
end;

function Sheet(Dark, Large: Boolean): Vcl.Graphics.TBitmap;
const
  Names: array[Boolean, Boolean] of string = (('BRANDS_LIGHT16', 'BRANDS_LIGHT32'),
    ('BRANDS_DARK16', 'BRANDS_DARK32'));
begin
  if GSheets[Dark, Large] = nil then
    GSheets[Dark, Large] := LoadSheet(Names[Dark, Large]);
  Result := GSheets[Dark, Large];
end;

function IsDark(Color: TColor): Boolean;
var
  Rgb: Longint;
begin
  Rgb := ColorToRGB(Color);
  Result := (GetRValue(Rgb) * 299 + GetGValue(Rgb) * 587 + GetBValue(Rgb) * 114) div 1000 < 128;
end;

procedure DrawBrand(Canvas: TCanvas; Brand: Integer; const R: TRect);
var
  Size, Cell: Integer;
  Bits: Vcl.Graphics.TBitmap;
  Blend: TBlendFunction;
begin
  if Brand < 0 then
    Exit;
  Size := R.Height;
  Bits := Sheet(IsDark(Canvas.Brush.Color), Size > 20);
  if Bits = nil then
    Exit;
  Cell := Bits.Height;
  if (Brand + 1) * Cell > Bits.Width then
    Exit;
  Blend.BlendOp := AC_SRC_OVER;
  Blend.BlendFlags := 0;
  Blend.SourceConstantAlpha := 255;
  Blend.AlphaFormat := AC_SRC_ALPHA;
  Winapi.Windows.AlphaBlend(Canvas.Handle, R.Left, R.Top, Size, Size, Bits.Canvas.Handle,
    Brand * Cell, 0, Cell, Cell, Blend);
end;

procedure AddBrandItem(Items: TStrings; const Text: string; Brand: Integer);
begin
  Items.AddObject(Text, TObject(NativeInt(Brand + 1)));
end;

function ItemBrand(Items: TStrings; Index: Integer): Integer;
begin
  Result := Integer(NativeInt(Items.Objects[Index])) - 1;
end;

procedure DrawRow(Canvas: TCanvas; Brand: Integer; const Text, EmptyText: string; Rect: TRect);
var
  Icon: TRect;
  Size: Integer;
begin
  Canvas.FillRect(Rect);
  Size := Min(Rect.Height - 2, MulDiv(16, Canvas.Font.PixelsPerInch, 96));
  Icon := System.Types.Rect(Rect.Left + 3, Rect.Top + (Rect.Height - Size) div 2, 0, 0);
  Icon.Width := Size;
  Icon.Height := Size;
  DrawBrand(Canvas, Brand, Icon);
  Rect.Left := Icon.Left + Size + 5;
  if (Text = '') and (EmptyText <> '') then
  begin
    if Canvas.Brush.Color <> clHighlight then
      Canvas.Font.Color := clGrayText;
    DrawText(Canvas.Handle, PChar(EmptyText), -1, Rect, DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS);
  end
  else
    DrawText(Canvas.Handle, PChar(Text), -1, Rect, DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or DT_NOPREFIX);
end;

procedure TBrandDrawer.ComboDraw(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
var
  Combo: TComboBox;
begin
  Combo := TComboBox(Control);
  DrawRow(Combo.Canvas, ItemBrand(Combo.Items, Index), Combo.Items[Index], EmptyText, Rect);
end;

procedure TBrandDrawer.ListDraw(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
var
  List: TListBox;
begin
  List := TListBox(Control);
  DrawRow(List.Canvas, ItemBrand(List.Items, Index), List.Items[Index], EmptyText, Rect);
end;

procedure MakeBrandCombo(Combo: TComboBox; const EmptyText: string);
var
  Drawer: TBrandDrawer;
begin
  Drawer := TBrandDrawer.Create(Combo);
  Drawer.EmptyText := EmptyText;
  if not (Combo is TBrandCombo) then
    Combo.Style := csOwnerDrawFixed;
  Combo.ItemHeight := MulDiv(20, Combo.CurrentPPI, 96);
  Combo.OnDrawItem := Drawer.ComboDraw;
end;

procedure MakeBrandList(List: TListBox);
var
  Drawer: TBrandDrawer;
begin
  Drawer := TBrandDrawer.Create(List);
  List.Style := lbOwnerDrawFixed;
  List.ItemHeight := MulDiv(20, List.CurrentPPI, 96);
  List.OnDrawItem := Drawer.ListDraw;
end;

procedure TBrandCombo.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  if Style = csDropDown then
    Params.Style := Params.Style or CBS_OWNERDRAWFIXED;
end;

procedure FreeSheets;
var
  Dark, Large: Boolean;
begin
  for Dark := False to True do
    for Large := False to True do
      FreeAndNil(GSheets[Dark, Large]);
end;

initialization

finalization
  FreeSheets;

end.
