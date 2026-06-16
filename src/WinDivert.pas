unit WinDivert;

{
  Binding Delphi para a WinDivert 2.2.x (https://reqrypt.org/windivert.html)
  Funcoes exportadas com convencao __cdecl (sem decoracao de nome).
  A WINDIVERT_ADDRESS tem exatamente 80 bytes - validado no smoke.dpr.
}

interface

uses
  Winapi.Windows;

const
  WINDIVERT_DLL = 'WinDivert.dll';

  // Camadas
  WINDIVERT_LAYER_NETWORK         = 0;
  WINDIVERT_LAYER_NETWORK_FORWARD = 1;
  WINDIVERT_LAYER_FLOW            = 2;
  WINDIVERT_LAYER_SOCKET          = 3;
  WINDIVERT_LAYER_REFLECT         = 4;

  // Flags
  WINDIVERT_FLAG_SNIFF      = $0001;
  WINDIVERT_FLAG_DROP       = $0002;
  WINDIVERT_FLAG_RECV_ONLY  = $0004;
  WINDIVERT_FLAG_SEND_ONLY  = $0008;
  WINDIVERT_FLAG_NO_INSTALL = $0010;
  WINDIVERT_FLAG_FRAGMENTS  = $0020;

  // Parametros (WinDivertSetParam)
  WINDIVERT_PARAM_QUEUE_LENGTH = 0;
  WINDIVERT_PARAM_QUEUE_TIME   = 1;
  WINDIVERT_PARAM_QUEUE_SIZE   = 2;

  // Shutdown
  WINDIVERT_SHUTDOWN_RECV = $1;
  WINDIVERT_SHUTDOWN_SEND = $2;
  WINDIVERT_SHUTDOWN_BOTH = $3;

  WINDIVERT_MTU_MAX = 40 + $FFFF; // maior pacote possivel

type
  // Dados da camada NETWORK
  TWinDivertDataNetwork = record
    IfIdx: UInt32;
    SubIfIdx: UInt32;
  end;

  // Estrutura de endereco (80 bytes). O campo Flags empacota o bitfield
  // de 32 bits do header C (Layer:8|Event:8|Sniffed:1|Outbound:1|...).
  TWinDivertAddress = record
    Timestamp: Int64;
    Flags: UInt32;
    Reserved2: UInt32;
    case Integer of
      0: (Network: TWinDivertDataNetwork);
      1: (Reserved3: array[0..63] of Byte);
  end;
  PWinDivertAddress = ^TWinDivertAddress;

// Acessores de bits (apenas leitura, uteis para diagnostico)
function WinDivertIsOutbound(const A: TWinDivertAddress): Boolean; inline;
function WinDivertIsIPv6(const A: TWinDivertAddress): Boolean; inline;

function WinDivertOpen(filter: PAnsiChar; layer: Integer; priority: SmallInt;
  flags: UInt64): THandle; cdecl; external WINDIVERT_DLL;

function WinDivertRecv(handle: THandle; pPacket: Pointer; packetLen: UINT;
  pRecvLen: PUINT; pAddr: PWinDivertAddress): BOOL; cdecl; external WINDIVERT_DLL;

function WinDivertSend(handle: THandle; pPacket: Pointer; packetLen: UINT;
  pSendLen: PUINT; pAddr: PWinDivertAddress): BOOL; cdecl; external WINDIVERT_DLL;

function WinDivertShutdown(handle: THandle; how: Integer): BOOL; cdecl;
  external WINDIVERT_DLL;

function WinDivertClose(handle: THandle): BOOL; cdecl; external WINDIVERT_DLL;

function WinDivertSetParam(handle: THandle; param: Integer; value: UInt64): BOOL;
  cdecl; external WINDIVERT_DLL;

// Helpers usados pelo smoke test (validacao da convencao de chamada)
function WinDivertHelperNtohs(x: UInt16): UInt16; cdecl; external WINDIVERT_DLL;
function WinDivertHelperHtons(x: UInt16): UInt16; cdecl; external WINDIVERT_DLL;

implementation

function WinDivertIsOutbound(const A: TWinDivertAddress): Boolean;
begin
  Result := ((A.Flags shr 17) and 1) <> 0;
end;

function WinDivertIsIPv6(const A: TWinDivertAddress): Boolean;
begin
  Result := ((A.Flags shr 20) and 1) <> 0;
end;

end.
