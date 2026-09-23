object TDelphiAgentChatFrame: TDelphiAgentChatFrame
  Left = 0
  Top = 0
  Width = 480
  Height = 640
  TabOrder = 0
  object memLog: TMemo
    Align = alClient
    ReadOnly = True
    ScrollBars = ssVertical
    TabOrder = 0
  end
  object pnlBottom: TPanel
    Align = alBottom
    Height = 72
    BevelOuter = bvNone
    TabOrder = 1
    object edtInput: TEdit
      Align = alClient
      TabOrder = 0
    end
    object pnlButtons: TPanel
      Align = alRight
      Width = 160
      BevelOuter = bvNone
      TabOrder = 1
      object btnSend: TButton
        Caption = #48372#45236#44592
        Default = True
      end
      object btnCancel: TButton
        Caption = #51473#51648
      end
    end
  end
  object lblStatus: TLabel
    Align = alBottom
    AutoSize = False
    Height = 22
    Caption = #45824#44592
  end
end
