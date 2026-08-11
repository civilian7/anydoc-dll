program AnydocDemo;

uses
  Vcl.Forms,
  Main in 'Main.pas' {frmMain},
  SCAnydoc in '..\src\SCAnydoc.pas';

// PerMonitorV2 DPI 매니페스트 (AnydocDemo.rc -> AnydocDemo.res)
{$R AnydocDemo.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.Title := 'anydoc Demo';
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
