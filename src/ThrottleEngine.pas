unit ThrottleEngine;

{
  Motor de limitacao de banda/latencia/perda baseado em WinDivert.

  Abre um handle WinDivert na camada NETWORK com um filtro (so o trafego do
  alvo). Dois threads:
    - Captura : WinDivertRecv -> aplica politica -> enfileira (ou descarta)
    - Liberacao: aguarda o instante de liberacao -> WinDivertSend (reinjeta)

  Banda: cada pacote "ocupa" o link por (bytes/taxa) segundos; o proximo so
  pode sair depois (serializacao = teto de throughput). Latencia: soma um
  atraso fixo. Perda: descarta uma fracao aleatoria. Bloqueio: descarta tudo.

  Como a latencia e fixa e a serializacao e monotonica, o instante de
  liberacao nunca decresce na ordem de captura -> a fila e simples FIFO.
}

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.SyncObjs,
  System.Generics.Collections, WinDivert;

type
  TThrottleStats = record
    Captured: Int64;
    Sent: Int64;
    Dropped: Int64;
    BytesSent: Int64;
    Queued: Integer;
  end;

  TThrottleEngine = class;

  TCaptureThread = class(TThread)
  private
    FEngine: TThrottleEngine;
  protected
    procedure Execute; override;
  public
    constructor Create(AEngine: TThrottleEngine);
  end;

  TReleaseThread = class(TThread)
  private
    FEngine: TThrottleEngine;
  protected
    procedure Execute; override;
  public
    constructor Create(AEngine: TThrottleEngine);
  end;

  TPendingPacket = record
    Data: TBytes;
    Len: UINT;
    Addr: TWinDivertAddress;
    ReleaseAt: UInt64;
  end;

  // Corte imediato de TODO o trafego (kill-switch). Usa um handle WinDivert
  // com FLAG_DROP: enquanto aberto, o driver descarta tudo (exceto loopback)
  // sem copiar pro user-mode -> liga/desliga instantaneo, sem threads.
  TKillSwitch = class
  private
    FHandle: THandle;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Engage;
    procedure Release;
    function Active: Boolean;
  end;

  TThrottleEngine = class
  private
    FHandle: THandle;
    FCapture: TCaptureThread;
    FRelease: TReleaseThread;
    FQueue: TQueue<TPendingPacket>;
    FLock: TCriticalSection;
    FWake: TEvent;
    FRunning: Boolean;
    // Configuracao (escrita pela UI, lida pelos threads; campos de 32 bits
    // / boolean: leitura/escrita atomica em x86, suficiente para o uso)
    FRateBytesPerSec: Integer; // 0 = ilimitado
    FLatencyMs: Integer;
    FLossPercent: Integer;
    FBlockAll: Boolean;
    FMaxBacklogMs: Integer;
    // Estado do agendador (somente o thread de captura toca)
    FNextSlot: UInt64;
    // Estatisticas (atomicas)
    FStats: TThrottleStats;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start(const Filter: string);
    procedure Stop;
    function GetStats: TThrottleStats;
    property RateBytesPerSec: Integer read FRateBytesPerSec write FRateBytesPerSec;
    property LatencyMs: Integer read FLatencyMs write FLatencyMs;
    property LossPercent: Integer read FLossPercent write FLossPercent;
    property BlockAll: Boolean read FBlockAll write FBlockAll;
    property MaxBacklogMs: Integer read FMaxBacklogMs write FMaxBacklogMs;
    property Running: Boolean read FRunning;
  end;

implementation

{ TKillSwitch }

constructor TKillSwitch.Create;
begin
  inherited Create;
  FHandle := INVALID_HANDLE_VALUE;
end;

destructor TKillSwitch.Destroy;
begin
  Release;
  inherited;
end;

function TKillSwitch.Active: Boolean;
begin
  Result := FHandle <> INVALID_HANDLE_VALUE;
end;

procedure TKillSwitch.Engage;
begin
  if Active then
    Exit;
  FHandle := WinDivertOpen('(ip or ipv6) and not loopback',
    WINDIVERT_LAYER_NETWORK, 1000, WINDIVERT_FLAG_DROP);
  if FHandle = INVALID_HANDLE_VALUE then
    raise Exception.CreateFmt(
      'Nao consegui cortar a internet (WinDivertOpen erro %d). Rode como Administrador.',
      [GetLastError]);
end;

procedure TKillSwitch.Release;
begin
  if Active then
  begin
    WinDivertClose(FHandle);
    FHandle := INVALID_HANDLE_VALUE;
  end;
end;

{ TCaptureThread }

constructor TCaptureThread.Create(AEngine: TThrottleEngine);
begin
  FEngine := AEngine;          // setado ANTES de iniciar o thread
  inherited Create(False);
end;

procedure TCaptureThread.Execute;
var
  E: TThrottleEngine;
  buf: TBytes;
  recvLen: UINT;
  addr: TWinDivertAddress;
  pkt: TPendingPacket;
  nowMs, rel, txMs: UInt64;
begin
  E := FEngine;
  SetLength(buf, WINDIVERT_MTU_MAX);
  while not Terminated do
  begin
    recvLen := 0;
    FillChar(addr, SizeOf(addr), 0);
    if not WinDivertRecv(E.FHandle, @buf[0], Length(buf), @recvLen, @addr) then
    begin
      // 232 = ERROR_NO_DATA: handle foi shutdown -> fim
      if GetLastError = ERROR_NO_DATA then
        Break;
      if Terminated then
        Break;
      Sleep(1);
      Continue;
    end;
    if recvLen = 0 then
      Continue;
    TInterlocked.Increment(E.FStats.Captured);

    // Bloqueio total (SEFAZ fora): nao reinjeta -> pacote some
    if E.FBlockAll then
    begin
      TInterlocked.Increment(E.FStats.Dropped);
      Continue;
    end;

    // Perda aleatoria
    if (E.FLossPercent > 0) and (Random(100) < E.FLossPercent) then
    begin
      TInterlocked.Increment(E.FStats.Dropped);
      Continue;
    end;

    nowMs := GetTickCount64;
    rel := nowMs + UInt64(E.FLatencyMs);

    if E.FRateBytesPerSec > 0 then
    begin
      if rel < E.FNextSlot then
        rel := E.FNextSlot;
      txMs := (UInt64(recvLen) * 1000) div UInt64(E.FRateBytesPerSec);
      E.FNextSlot := rel + txMs;
      // Buffer do link cheio: descarta excedente (tail drop) e nao acumula
      if (rel - nowMs) > UInt64(E.FMaxBacklogMs) then
      begin
        E.FNextSlot := E.FNextSlot - txMs;
        TInterlocked.Increment(E.FStats.Dropped);
        Continue;
      end;
    end;

    pkt.Len := recvLen;
    SetLength(pkt.Data, recvLen);
    Move(buf[0], pkt.Data[0], recvLen);
    pkt.Addr := addr;
    pkt.ReleaseAt := rel;

    E.FLock.Enter;
    try
      E.FQueue.Enqueue(pkt);
    finally
      E.FLock.Leave;
    end;
    E.FWake.SetEvent;
  end;
end;

{ TReleaseThread }

constructor TReleaseThread.Create(AEngine: TThrottleEngine);
begin
  FEngine := AEngine;
  inherited Create(False);
end;

procedure TReleaseThread.Execute;
var
  E: TThrottleEngine;
  pkt: TPendingPacket;
  cnt: Integer;
  nowMs: UInt64;
  waitMs: Cardinal;
  sendLen: UINT;
begin
  E := FEngine;
  while True do
  begin
    cnt := 0;
    E.FLock.Enter;
    try
      cnt := E.FQueue.Count;
      if cnt > 0 then
        pkt := E.FQueue.Peek;
    finally
      E.FLock.Leave;
    end;

    if cnt = 0 then
    begin
      if Terminated then
        Break;
      E.FWake.WaitFor(200);
      Continue;
    end;

    // Se ainda nao chegou a hora (e nao estamos parando), espera um pouco
    nowMs := GetTickCount64;
    if (not Terminated) and (nowMs < pkt.ReleaseAt) then
    begin
      if (pkt.ReleaseAt - nowMs) > 200 then
        waitMs := 200
      else
        waitMs := Cardinal(pkt.ReleaseAt - nowMs);
      E.FWake.WaitFor(waitMs);
      Continue;
    end;

    // Hora de enviar (ou estamos parando -> esvazia imediatamente)
    E.FLock.Enter;
    try
      if E.FQueue.Count > 0 then
        pkt := E.FQueue.Dequeue
      else
        cnt := 0;
    finally
      E.FLock.Leave;
    end;
    if cnt = 0 then
      Continue;

    sendLen := 0;
    if WinDivertSend(E.FHandle, @pkt.Data[0], pkt.Len, @sendLen, @pkt.Addr) then
    begin
      TInterlocked.Increment(E.FStats.Sent);
      TInterlocked.Add(E.FStats.BytesSent, Int64(pkt.Len));
    end;
    // Falha no send (handle fechando) -> ignora
  end;
end;

{ TThrottleEngine }

constructor TThrottleEngine.Create;
begin
  inherited Create;
  FHandle := INVALID_HANDLE_VALUE;
  FQueue := TQueue<TPendingPacket>.Create;
  FLock := TCriticalSection.Create;
  FWake := TEvent.Create(nil, False, False, ''); // auto-reset
  FMaxBacklogMs := 1500;
  Randomize;
end;

destructor TThrottleEngine.Destroy;
begin
  Stop;
  FWake.Free;
  FLock.Free;
  FQueue.Free;
  inherited;
end;

procedure TThrottleEngine.Start(const Filter: string);
var
  fa: AnsiString;
begin
  if FRunning then
    Exit;
  fa := AnsiString(Filter);
  FHandle := WinDivertOpen(PAnsiChar(fa), WINDIVERT_LAYER_NETWORK, 0, 0);
  if FHandle = INVALID_HANDLE_VALUE then
    raise Exception.CreateFmt(
      'WinDivertOpen falhou (erro %d).'#13#10 +
      'Verifique: executou como Administrador? O filtro e valido? Ha um IP resolvido?',
      [GetLastError]);

  WinDivertSetParam(FHandle, WINDIVERT_PARAM_QUEUE_LENGTH, 16384);
  WinDivertSetParam(FHandle, WINDIVERT_PARAM_QUEUE_SIZE, 33554432);
  WinDivertSetParam(FHandle, WINDIVERT_PARAM_QUEUE_TIME, 2000);

  FNextSlot := GetTickCount64;
  FillChar(FStats, SizeOf(FStats), 0);
  FQueue.Clear;

  FCapture := TCaptureThread.Create(Self);
  FRelease := TReleaseThread.Create(Self);
  FRunning := True;
end;

procedure TThrottleEngine.Stop;
begin
  if not FRunning then
    Exit;

  if FCapture <> nil then
    FCapture.Terminate;
  if FRelease <> nil then
    FRelease.Terminate;

  // Desbloqueia o WinDivertRecv (que esta travado esperando pacote)
  if FHandle <> INVALID_HANDLE_VALUE then
    WinDivertShutdown(FHandle, WINDIVERT_SHUTDOWN_RECV);
  FWake.SetEvent;

  if FCapture <> nil then
  begin
    FCapture.WaitFor;
    FreeAndNil(FCapture);
  end;
  if FRelease <> nil then
  begin
    FWake.SetEvent;
    FRelease.WaitFor; // esvazia a fila (reinjeta o que sobrou) antes de sair
    FreeAndNil(FRelease);
  end;

  if FHandle <> INVALID_HANDLE_VALUE then
  begin
    WinDivertClose(FHandle);
    FHandle := INVALID_HANDLE_VALUE;
  end;

  FRunning := False;
end;

function TThrottleEngine.GetStats: TThrottleStats;
begin
  Result.Captured := TInterlocked.Read(FStats.Captured);
  Result.Sent := TInterlocked.Read(FStats.Sent);
  Result.Dropped := TInterlocked.Read(FStats.Dropped);
  Result.BytesSent := TInterlocked.Read(FStats.BytesSent);
  FLock.Enter;
  try
    Result.Queued := FQueue.Count;
  finally
    FLock.Leave;
  end;
end;

end.
