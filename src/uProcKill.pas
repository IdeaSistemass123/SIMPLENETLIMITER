unit uProcKill;

{ Finaliza imediatamente (force-kill) todos os processos com o nome dado.
  Usa o snapshot de processos do Windows (TlHelp32) + TerminateProcess. }

interface

function KillProcessByName(const AExeName: string): Integer;

implementation

uses
  Winapi.Windows, Winapi.TlHelp32, System.SysUtils;

function KillProcessByName(const AExeName: string): Integer;
var
  snap: THandle;
  pe: TProcessEntry32W;
  hProc: THandle;
begin
  Result := 0;
  snap := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if snap = INVALID_HANDLE_VALUE then
    Exit;
  try
    pe.dwSize := SizeOf(pe);
    if Process32FirstW(snap, pe) then
      repeat
        if SameText(string(pe.szExeFile), AExeName) then
        begin
          hProc := OpenProcess(PROCESS_TERMINATE, False, pe.th32ProcessID);
          if hProc <> 0 then
          try
            if TerminateProcess(hProc, 1) then
              Inc(Result);
          finally
            CloseHandle(hProc);
          end;
        end;
      until not Process32NextW(snap, pe);
  finally
    CloseHandle(snap);
  end;
end;

end.
