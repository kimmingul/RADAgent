unit MainForm;

interface

uses
  System.SysUtils, System.Classes, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls;

type
  TForm1 = class(TForm)
    Button1: TButton;
    Label1: TLabel;
    procedure Button1Click(Sender: TObject);
  private
    function Total(Count: Integer): Integer;
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

function TForm1.Total(Count: Integer): Integer;
var
  Index: Integer;
begin
  Result := 0;
  for Index := 1 to Count do
    Result := Result + Index;
end;

procedure TForm1.Button1Click(Sender: TObject);
var
  Answer: Integer;
begin
  Answer := Total(10);
  Label1.Caption := 'Total=' + IntToStr(Answer);
end;

end.
