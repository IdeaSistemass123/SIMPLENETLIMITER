program SefazThrottle;

{$APPTYPE GUI}

uses
  Vcl.Forms,
  WinDivert in 'WinDivert.pas',
  uHostResolve in 'uHostResolve.pas',
  uProcKill in 'uProcKill.pas',
  uPing in 'uPing.pas',
  ThrottleEngine in 'ThrottleEngine.pas',
  uMain in 'uMain.pas';

{$R app.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskBar := True;
  Application.Title := 'Limitador SEFAZ / NFCe';
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
