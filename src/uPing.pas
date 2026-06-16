unit uPing;

{ Mede latencia ao alvo via TCP connect (porta do alvo, ex.: 443) numa thread.
  TCP-ping (e nao ICMP) de proposito: o handshake passa pelo filtro do WinDivert,
  entao reflete a latencia/banda injetada e o bloqueio (vira "sem resposta"). }

interface

uses
  System.Classes, System.SyncObjs;

type
  TPingThread = class(TThread)
  private
    FLock: TCriticalSection;
    FStop: TEvent;
    FIP: AnsiString;
    FPort: Word;
    FLastMs: Integer;     // >=0 ms; -1 sem resposta; -2 sem alvo
    FIntervalMs: Integer;
    function CurrentTarget(out AIP: AnsiString; out APort: Word): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetTarget(const AIP: string; APort: Word);
    function GetLast: Integer;
  end;

implementation

uses
  Winapi.Windows, Winapi.WinSock, System.SysUtils;

function TcpPing(const AIP: AnsiString; APort: Word; TimeoutMs: Integer): Integer;
var
  sock: TSocket;
  addr: TSockAddrIn;
  fds: TFDSet;
  tv: TTimeVal;
  nb: u_long;
  t0, t1, freq: Int64;
  so_err, optlen: Integer;
begin
  Result := -1;
  sock := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if sock = INVALID_SOCKET then
    Exit;
  try
    nb := 1;
    ioctlsocket(sock, FIONBIO, nb); // non-blocking

    FillChar(addr, SizeOf(addr), 0);
    addr.sin_family := AF_INET;
    addr.sin_port := htons(APort);
    addr.sin_addr.S_addr := inet_addr(PAnsiChar(AIP));

    QueryPerformanceCounter(t0);
    if connect(sock, PSockAddr(@addr)^, SizeOf(addr)) = 0 then
    begin
      QueryPerformanceCounter(t1);
      QueryPerformanceFrequency(freq);
      Exit(Round((t1 - t0) * 1000 / freq));
    end;
    if WSAGetLastError <> WSAEWOULDBLOCK then
      Exit(-1);

    FD_ZERO(fds);
    FD_SET(sock, fds);
    tv.tv_sec := TimeoutMs div 1000;
    tv.tv_usec := (TimeoutMs mod 1000) * 1000;
    if select(0, nil, @fds, nil, @tv) <= 0 then
      Exit(-1); // timeout ou erro

    optlen := SizeOf(so_err);
    so_err := 0;
    getsockopt(sock, SOL_SOCKET, SO_ERROR, PAnsiChar(@so_err), optlen);
    if so_err <> 0 then
      Exit(-1);

    QueryPerformanceCounter(t1);
    QueryPerformanceFrequency(freq);
    Result := Round((t1 - t0) * 1000 / freq);
  finally
    closesocket(sock);
  end;
end;

{ TPingThread }

constructor TPingThread.Create;
begin
  FLock := TCriticalSection.Create;
  FStop := TEvent.Create(nil, False, False, '');
  FLastMs := -2;
  FIntervalMs := 1500;
  inherited Create(False); // campos prontos antes de iniciar a thread
end;

destructor TPingThread.Destroy;
begin
  Terminate;
  FStop.SetEvent; // acorda o wait pra sair rapido
  inherited;      // faz o WaitFor
  FStop.Free;
  FLock.Free;
end;

procedure TPingThread.SetTarget(const AIP: string; APort: Word);
begin
  FLock.Enter;
  try
    FIP := AnsiString(AIP);
    FPort := APort;
    FLastMs := -2; // reseta ate medir o novo alvo
  finally
    FLock.Leave;
  end;
end;

function TPingThread.CurrentTarget(out AIP: AnsiString; out APort: Word): Boolean;
begin
  FLock.Enter;
  try
    AIP := FIP;
    APort := FPort;
    Result := AIP <> '';
  finally
    FLock.Leave;
  end;
end;

function TPingThread.GetLast: Integer;
begin
  FLock.Enter;
  try
    Result := FLastMs;
  finally
    FLock.Leave;
  end;
end;

procedure TPingThread.Execute;
var
  wsa: TWSAData;
  ip: AnsiString;
  port: Word;
  ms: Integer;
begin
  WSAStartup($0202, wsa);
  try
    while not Terminated do
    begin
      if CurrentTarget(ip, port) then
      begin
        ms := TcpPing(ip, port, 3000);
        FLock.Enter;
        try
          FLastMs := ms;
        finally
          FLock.Leave;
        end;
      end;
      FStop.WaitFor(FIntervalMs);
    end;
  finally
    WSACleanup;
  end;
end;

end.
