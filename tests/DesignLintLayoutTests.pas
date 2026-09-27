unit DesignLintLayoutTests;

{ Tests for RADAgent.DesignLintLayout: the button order rule sees right-aligned dialog buttons. }

interface

uses
  TestCheck;

procedure RunDesignLintLayoutTests(const Check: TCheckProc);

implementation

uses
  System.SysUtils, System.Classes, System.Generics.Collections, Vcl.Controls, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.Forms, RADAgent.DesignLintRules, RADAgent.DesignLintLayout;

function OrderFindings(OkFirst: Boolean; const Preset: string): Integer;
var
  Form: TForm;
  Bar: TPanel;
  Ok, Cancel: TButton;
  Items: TList<TComponent>;
  Findings: TList<TDesignLintFinding>;
  Ctx: TDesignRulesContext;
  Finding: TDesignLintFinding;
begin
  Form := TForm.CreateNew(nil);
  Items := TList<TComponent>.Create;
  Findings := TList<TDesignLintFinding>.Create;
  try
    Form.SetBounds(0, 0, 400, 200);
    Bar := TPanel.Create(Form);
    Bar.Name := 'ButtonBar';
    Bar.Parent := Form;
    Bar.Align := alBottom;
    Ok := TButton.Create(Form);
    Ok.Name := 'OkButton';
    Ok.Default := True;
    Cancel := TButton.Create(Form);
    Cancel.Name := 'CancelButton';
    Cancel.Cancel := True;
    { alRight places the first one aligned at the far right. }
    if OkFirst then
    begin
      Cancel.Parent := Bar;
      Cancel.Align := alRight;
      Ok.Parent := Bar;
      Ok.Align := alRight;
      Ok.Left := Cancel.Left - Ok.Width;
    end
    else
    begin
      Ok.Parent := Bar;
      Ok.Align := alRight;
      Cancel.Parent := Bar;
      Cancel.Align := alRight;
      Cancel.Left := Ok.Left - Cancel.Width;
    end;
    Items.AddRange([Form, Bar, Ok, Cancel]);
    Ctx := Default(TDesignRulesContext);
    Ctx.Framework := 'VCL';
    Ctx.PixelsPerInch := 96;
    CheckLayout(Form, Items, Ctx, Preset, Findings);
    Result := 0;
    for Finding in Findings do
      if Finding.Rule = 'button-order' then
        Inc(Result);
  finally
    Findings.Free;
    Items.Free;
    Form.Free;
  end;
end;

procedure RunDesignLintLayoutTests(const Check: TCheckProc);
begin
  Check(OrderFindings(True, 'fluent-windows11') = 0, 'right-aligned OK, Cancel: Windows order holds');
  Check(OrderFindings(False, 'fluent-windows11') = 1, 'right-aligned Cancel, OK is reported for Windows');
  Check(OrderFindings(False, 'apple-macos') = 0, 'Cancel, OK is the macOS order');
end;

end.
