unit RADAgent.SettingsUi;

{ Top-aligned control builders shared by the settings pages. VCL only. }

interface

uses
  System.Classes, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls;

function AddHeading(Parent: TWinControl; const Caption: string): TLabel;
function AddNote(Parent: TWinControl; const Caption: string): TLabel;
function AddCombo(Parent: TWinControl; Style: TComboBoxStyle): TComboBox;
function AddEdit(Parent: TWinControl): TEdit;
function AddCheck(Parent: TWinControl; const Caption: string): TCheckBox;
{ Report-style list with a check box per item and one column. }
function AddCheckList(Parent: TWinControl; Height: Integer): TListView;
{ A row with a caption on the left and Control filling the rest. }
function AddRow(Parent: TWinControl; const Caption: string; Control: TControl): TPanel;
{ Stacks an already created control below the previous ones. }
procedure AddStacked(Parent: TWinControl; Control: TControl);
function AddButtons(Parent: TWinControl): TPanel;
function AddButton(Row: TPanel; const Caption: string; Handler: TNotifyEvent): TButton;

implementation

uses
  System.Math, Vcl.Graphics;

var
  GOrder: Integer;

{ alTop controls stack in creation order only if each starts below the previous one. }
procedure Stack(Control: TControl; Parent: TWinControl);
begin
  Inc(GOrder, 1000);
  Control.Top := GOrder;
  Control.Align := alTop;
  Control.AlignWithMargins := True;
  Control.Margins.SetBounds(8, 4, 8, 2);
  Control.Parent := Parent;
end;

procedure AddStacked(Parent: TWinControl; Control: TControl);
begin
  Stack(Control, Parent);
end;

function AddHeading(Parent: TWinControl; const Caption: string): TLabel;
begin
  Result := TLabel.Create(Parent);
  Result.Caption := Caption;
  Result.Font.Style := [fsBold];
  Stack(Result, Parent);
  Result.Margins.Top := 10;
end;

function AddNote(Parent: TWinControl; const Caption: string): TLabel;
begin
  Result := TLabel.Create(Parent);
  Result.Font.Color := clGrayText;
  { AutoSize would measure before the page has its width; three lines fit every note. }
  Result.AutoSize := False;
  Result.WordWrap := True;
  Result.Height := 48;
  Result.Caption := Caption;
  Stack(Result, Parent);
end;

function AddCombo(Parent: TWinControl; Style: TComboBoxStyle): TComboBox;
begin
  Result := TComboBox.Create(Parent);
  Result.Style := Style;
  Result.DropDownCount := 20;
  Stack(Result, Parent);
end;

function AddEdit(Parent: TWinControl): TEdit;
begin
  Result := TEdit.Create(Parent);
  Stack(Result, Parent);
end;

function AddCheck(Parent: TWinControl; const Caption: string): TCheckBox;
begin
  Result := TCheckBox.Create(Parent);
  Result.Caption := Caption;
  Stack(Result, Parent);
end;

function AddCheckList(Parent: TWinControl; Height: Integer): TListView;
begin
  Result := TListView.Create(Parent);
  Result.Height := Height;
  Result.ViewStyle := vsReport;
  Result.Checkboxes := True;
  Result.ShowColumnHeaders := False;
  Result.ReadOnly := True;
  Result.RowSelect := True;
  Stack(Result, Parent);
  Result.Columns.Add.Width := -2;
end;

function AddRow(Parent: TWinControl; const Caption: string; Control: TControl): TPanel;
var
  Text: TLabel;
begin
  Result := TPanel.Create(Parent);
  Result.BevelOuter := bvNone;
  Result.Height := 26;
  Result.ParentBackground := True;
  Stack(Result, Parent);
  Text := TLabel.Create(Result);
  Text.Parent := Result;
  Text.Align := alLeft;
  Text.AutoSize := False;
  Text.Width := 150;
  Text.Layout := tlCenter;
  Text.Caption := Caption;
  Control.Parent := Result;
  Control.AlignWithMargins := False;
  Control.Align := alClient;
end;

function AddButtons(Parent: TWinControl): TPanel;
begin
  Result := TPanel.Create(Parent);
  Result.BevelOuter := bvNone;
  Result.Height := 28;
  Result.ParentBackground := True;
  Stack(Result, Parent);
end;

function AddButton(Row: TPanel; const Caption: string; Handler: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Row);
  Result.Caption := Caption;
  Result.Width := Max(90, Length(Caption) * 14 + 24);
  Result.Left := 10000;
  Result.Align := alLeft;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(0, 0, 6, 0);
  Result.OnClick := Handler;
  Result.Parent := Row;
end;

end.
