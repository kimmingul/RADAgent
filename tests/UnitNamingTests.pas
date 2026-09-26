unit UnitNamingTests;

{ Tests for RADAgent.UnitNaming: which unit names rad.new_module and rad.rename_unit accept. }

interface

uses
  TestCheck;

procedure RunUnitNamingTests(const Check: TCheckProc);

implementation

uses
  System.SysUtils, RADAgent.UnitNaming;

procedure RunUnitNamingTests(const Check: TCheckProc);
var
  Dotted, Plain: TArray<string>;
  Problem: string;
begin
  Dotted := ['Nanum.Csv.Types', 'Nanum.UI.CsvGrid', 'Nanum.App.Settings', 'Unit2'];
  Plain := ['Unit1', 'Helpers'];
  Check(not CheckUnitName('form', '', False, Dotted, Problem), 'a unit name is required');
  Check(not CheckUnitName('form', 'Nanum.UI.Unit3', False, Dotted, Problem) and Problem.Contains('Nanum.UI.'),
    'UnitN is refused, with an example in the project namespace');
  Check(not CheckUnitName('form', 'Nanum.UI.Pivot', False, Dotted, Problem), 'a form unit ends in Form or Dialog');
  Check(CheckUnitName('form', 'Nanum.UI.PivotSaveDialog', False, Dotted, Problem), 'a dialog form is accepted');
  Check(CheckUnitName('frame', 'Nanum.UI.CsvGridFrame', False, Dotted, Problem), 'a frame ends in Frame');
  Check(not CheckUnitName('frame', 'Nanum.UI.CsvGridForm', False, Dotted, Problem), 'a frame named Form is refused');
  Check(not CheckUnitName('form', 'UI.MainForm', False, Dotted, Problem) and Problem.Contains('Nanum.'),
    'most units share Nanum.: a new one uses it too');
  Check(CheckUnitName('unit', 'Nanum.Csv.Reader', False, Dotted, Problem), 'a plain unit needs no suffix');
  Check(CheckUnitName('form', 'MainForm', False, Plain, Problem), 'no shared root: a plain name is fine');
  Check(not CheckUnitName('form', 'App.MainForm', True, Plain, Problem), 'C++Builder file names have no dots');
  Check(LastPart('Nanum.UI.PivotSaveDialog') = 'PivotSaveDialog', 'the form name is the last part');
end;

end.
