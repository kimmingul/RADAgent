object Form1: TForm1
  Left = 0
  Top = 0
  Caption = 'DelphiAgent Smoke'
  ClientHeight = 120
  ClientWidth = 320
  Position = poScreenCenter
  TextHeight = 15
  object Label1: TLabel
    Left = 16
    Top = 64
    Width = 40
    Height = 15
    Caption = 'Total=?'
  end
  object Button1: TButton
    Left = 16
    Top = 16
    Width = 120
    Height = 32
    Caption = 'Run'
    TabOrder = 0
    OnClick = Button1Click
  end
end
