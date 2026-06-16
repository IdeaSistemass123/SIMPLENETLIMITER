unit uHostResolve;

{ Resolve um host (ex.: nfce.fazenda.sp.gov.br) para uma lista de IPs IPv4.
  Se o texto ja for um IP, retorna ele mesmo. Usa Winsock classico. }

interface

uses
  System.SysUtils, System.Classes;

function ResolveHostIPv4(const Host: string; out IPs: TArray<string>): Boolean;

implementation

uses
  Winapi.Windows, Winapi.WinSock;

type
  TPAnsiCharArray = array[0..1023] of PAnsiChar;
  PPAnsiCharArray = ^TPAnsiCharArray;

function ResolveHostIPv4(const Host: string; out IPs: TArray<string>): Boolean;
var
  wsa: TWSAData;
  he: PHostEnt;
  arr: PPAnsiCharArray;
  list: TStringList;
  i: Integer;
  addr: TInAddr;
  ansiHost: AnsiString;
begin
  IPs := nil;
  Result := False;
  if WSAStartup($0202, wsa) <> 0 then
    Exit(False);
  try
    ansiHost := AnsiString(Trim(Host));
    if ansiHost = '' then
      Exit(False);

    // Ja e um IP literal? (compara como unsigned; INADDR_NONE = $FFFFFFFF)
    addr.S_addr := inet_addr(PAnsiChar(ansiHost));
    if (Cardinal(addr.S_addr) <> $FFFFFFFF) or (ansiHost = '255.255.255.255') then
    begin
      SetLength(IPs, 1);
      IPs[0] := string(ansiHost);
      Exit(True);
    end;

    he := gethostbyname(PAnsiChar(ansiHost));
    if (he = nil) or (he^.h_addrtype <> AF_INET) then
      Exit(False);

    list := TStringList.Create;
    try
      list.Duplicates := dupIgnore;
      list.Sorted := True;
      arr := PPAnsiCharArray(he^.h_addr_list);
      i := 0;
      while (arr <> nil) and (arr^[i] <> nil) and (i < 64) do
      begin
        addr := PInAddr(arr^[i])^;
        list.Add(string(AnsiString(inet_ntoa(addr))));
        Inc(i);
      end;
      IPs := list.ToStringArray;
      Result := Length(IPs) > 0;
    finally
      list.Free;
    end;
  finally
    WSACleanup;
  end;
end;

end.
