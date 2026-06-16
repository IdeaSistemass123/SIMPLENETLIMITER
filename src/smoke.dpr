program smoke;

{$APPTYPE CONSOLE}

{ Teste de fumaca: valida que a WinDivert.dll carrega, que a convencao de
  chamada (cdecl) esta correta e que a struct de endereco tem 80 bytes.
  NAO precisa de Administrador (so chama o helper de byte-order). }

uses
  System.SysUtils,
  WinDivert in 'WinDivert.pas';

var
  v: UInt16;
  ok: Boolean;
begin
  ok := True;

  v := WinDivertHelperNtohs($1234);
  Writeln(Format('WinDivertHelperNtohs($1234) = $%s (esperado $3412)', [IntToHex(v, 4)]));
  if v <> $3412 then
  begin
    Writeln('  >> FALHA: convencao de chamada incorreta');
    ok := False;
  end;

  Writeln(Format('SizeOf(TWinDivertAddress) = %d (esperado 80)', [SizeOf(TWinDivertAddress)]));
  if SizeOf(TWinDivertAddress) <> 80 then
  begin
    Writeln('  >> FALHA: layout da struct incorreto');
    ok := False;
  end;

  if ok then
    Writeln('RESULTADO: OK - binding valido')
  else
  begin
    Writeln('RESULTADO: FALHA');
    ExitCode := 1;
  end;
end.
