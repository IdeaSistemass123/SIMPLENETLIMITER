unit uMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.Math, Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls,
  Vcl.Graphics, Vcl.Dialogs,
  ThrottleEngine, uHostResolve, uProcKill, uPing;

type
  TfrmMain = class(TForm)
  private
    FEngine: TThrottleEngine;
    FKill: TKillSwitch;
    FPing: TPingThread;
    FResolvedIPs: TArray<string>;
    FSchedState: Integer;
    FSchedLeft: Integer;
    FSchedRestore: Integer;
    FLastBytes: Int64;
    FLastRateTick: UInt64;
    FLastRate: Double;
    // controles
    cbUF: TComboBox;
    cbAmb: TComboBox;
    edHost: TEdit;
    edPorta: TEdit;
    edBanda: TEdit;
    edLat: TEdit;
    edPerda: TEdit;
    chkBlock: TCheckBox;
    chkGlobal: TCheckBox;
    lblIPs: TLabel;
    lblRunning: TLabel;
    lblNet: TLabel;
    lblLive: TLabel;
    lblStats: TLabel;
    btnResolver: TButton;
    btnStart: TButton;
    btnStop: TButton;
    btnKill: TButton;
    btnSched: TButton;
    btnSistema: TButton;
    edCutSecs: TEdit;
    edRestSecs: TEdit;
    memoLog: TMemo;
    timer: TTimer;
    schedTimer: TTimer;
    // helpers de criacao
    function NewLabel(const ACaption: string; AParent: TWinControl;
      ALeft, ATop: Integer; AWidth: Integer = 0): TLabel;
    function NewEdit(const AText: string; AParent: TWinControl;
      ALeft, ATop, AWidth: Integer): TEdit;
    function NewButton(const ACaption: string; AParent: TWinControl;
      ALeft, ATop, AWidth, AHeight: Integer; AOnClick: TNotifyEvent): TButton;
    procedure BuildUI;
    procedure SelectUF(const ACode: string);
    // logica
    procedure Log(const S: string);
    procedure ApplyConfig;
    function BuildFilter: string;
    function ResolveNow: Boolean;
    procedure UpdateUIState;
    procedure UpdateKillUI;
    // eventos
    procedure ufChange(Sender: TObject);
    procedure btnResolverClick(Sender: TObject);
    procedure btnStartClick(Sender: TObject);
    procedure btnStopClick(Sender: TObject);
    procedure btnKillClick(Sender: TObject);
    procedure btnSistemaClick(Sender: TObject);
    procedure btnSchedClick(Sender: TObject);
    procedure schedTick(Sender: TObject);
    procedure CancelSchedule(const ALog: Boolean);
    procedure UpdateSchedUI;
    procedure chkBlockClick(Sender: TObject);
    procedure cfgChange(Sender: TObject);
    procedure presetNormal(Sender: TObject);
    procedure presetLento(Sender: TObject);
    procedure presetInstavel(Sender: TObject);
    procedure presetFora(Sender: TObject);
    procedure timerTick(Sender: TObject);
    procedure formClose(Sender: TObject; var Action: TCloseAction);
    procedure formShow(Sender: TObject);
  protected
    procedure CreateParams(var Params: TCreateParams); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  frmMain: TfrmMain;

implementation

type
  TUFEntry = record
    UF: string;
    Nome: string;
    Prod: string;
    Homol: string; // vazio = usar Prod
  end;

const
  // Autorizadores NFCe (modelo 65). SVRS atende varios estados (PA inclusive).
  // Hosts conferidos por DNS. Homologacao vazia => cai no de producao (editavel).
  SVRS_P = 'nfce.svrs.rs.gov.br';
  SVRS_H = 'nfce-homologacao.svrs.rs.gov.br';

  UFs: array[0..26] of TUFEntry = (
    (UF: 'AC'; Nome: 'Acre (SVRS)';                 Prod: SVRS_P; Homol: SVRS_H),
    (UF: 'AL'; Nome: 'Alagoas (SVRS)';              Prod: SVRS_P; Homol: SVRS_H),
    (UF: 'AM'; Nome: 'Amazonas';                    Prod: 'nfce.sefaz.am.gov.br'; Homol: ''),
    (UF: 'AP'; Nome: 'Amapa (SVRS)';                Prod: SVRS_P; Homol: SVRS_H),
    (UF: 'BA'; Nome: 'Bahia';                       Prod: 'nfe.sefaz.ba.gov.br'; Homol: 'hnfe.sefaz.ba.gov.br'),
    (UF: 'CE'; Nome: 'Ceara';                       Prod: 'nfce.sefaz.ce.gov.br'; Homol: 'nfceh.sefaz.ce.gov.br'),
    (UF: 'DF'; Nome: 'Distrito Federal (SVRS)';     Prod: SVRS_P; Homol: SVRS_H),
    (UF: 'ES'; Nome: 'Espirito Santo (SVRS)';       Prod: SVRS_P; Homol: SVRS_H),
    (UF: 'GO'; Nome: 'Goias';                       Prod: 'nfe.sefaz.go.gov.br'; Homol: 'homolog.sefaz.go.gov.br'),
    (UF: 'MA'; Nome: 'Maranhao (SVRS)';             Prod: SVRS_P; Homol: SVRS_H),
    (UF: 'MG'; Nome: 'Minas Gerais';                Prod: 'nfce.fazenda.mg.gov.br'; Homol: 'hnfce.fazenda.mg.gov.br'),
    (UF: 'MS'; Nome: 'Mato Grosso do Sul';          Prod: 'nfce.sefaz.ms.gov.br'; Homol: ''),
    (UF: 'MT'; Nome: 'Mato Grosso';                 Prod: 'nfce.sefaz.mt.gov.br'; Homol: 'homologacao.sefaz.mt.gov.br'),
    (UF: 'PA'; Nome: 'Para (SVRS)';                 Prod: SVRS_P; Homol: SVRS_H),
    (UF: 'PB'; Nome: 'Paraiba (SVRS)';              Prod: SVRS_P; Homol: SVRS_H),
    (UF: 'PE'; Nome: 'Pernambuco';                  Prod: 'nfce.sefaz.pe.gov.br'; Homol: ''),
    (UF: 'PI'; Nome: 'Piaui (SVRS)';                Prod: SVRS_P; Homol: SVRS_H),
    (UF: 'PR'; Nome: 'Parana';                      Prod: 'nfce.sefa.pr.gov.br'; Homol: 'homologacao.nfce.sefa.pr.gov.br'),
    (UF: 'RJ'; Nome: 'Rio de Janeiro (SVRS)';       Prod: SVRS_P; Homol: SVRS_H),
    (UF: 'RN'; Nome: 'Rio Grande do Norte (SVRS)';  Prod: SVRS_P; Homol: SVRS_H),
    (UF: 'RO'; Nome: 'Rondonia (SVRS)';             Prod: SVRS_P; Homol: SVRS_H),
    (UF: 'RR'; Nome: 'Roraima (SVRS)';              Prod: SVRS_P; Homol: SVRS_H),
    (UF: 'RS'; Nome: 'Rio Grande do Sul';           Prod: 'nfce.sefazrs.rs.gov.br'; Homol: 'nfce-homologacao.sefazrs.rs.gov.br'),
    (UF: 'SC'; Nome: 'Santa Catarina (SVRS)';       Prod: SVRS_P; Homol: SVRS_H),
    (UF: 'SE'; Nome: 'Sergipe (SVRS)';              Prod: SVRS_P; Homol: SVRS_H),
    (UF: 'SP'; Nome: 'Sao Paulo';                   Prod: 'nfce.fazenda.sp.gov.br'; Homol: 'homologacao.nfce.fazenda.sp.gov.br'),
    (UF: 'TO'; Nome: 'Tocantins (SVRS)';            Prod: SVRS_P; Homol: SVRS_H)
  );

  // Estados do agendador de corte
  SCHED_IDLE       = 0;
  SCHED_TO_CUT     = 1;
  SCHED_TO_RESTORE = 2;

{ helpers de criacao de controles }

function TfrmMain.NewLabel(const ACaption: string; AParent: TWinControl;
  ALeft, ATop: Integer; AWidth: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := ALeft;
  Result.Top := ATop;
  if AWidth > 0 then
  begin
    Result.AutoSize := False;
    Result.Width := AWidth;
  end;
end;

function TfrmMain.NewEdit(const AText: string; AParent: TWinControl;
  ALeft, ATop, AWidth: Integer): TEdit;
begin
  Result := TEdit.Create(Self);
  Result.Parent := AParent;
  Result.Text := AText;
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Width := AWidth;
end;

function TfrmMain.NewButton(const ACaption: string; AParent: TWinControl;
  ALeft, ATop, AWidth, AHeight: Integer; AOnClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Width := AWidth;
  Result.Height := AHeight;
  Result.OnClick := AOnClick;
end;

procedure TfrmMain.BuildUI;
var
  gbAlvo, gbLim, gbStatus: TGroupBox;
  i: Integer;
begin
  Caption := 'Limitador de Internet - Testes de Contingencia NFCe';
  Position := poScreenCenter;
  BorderStyle := bsSingle;
  BorderIcons := [biSystemMenu, biMinimize];
  ClientWidth := 648;
  ClientHeight := 708;
  OnClose := formClose;
  OnShow := formShow;

  // ---- Alvo ----
  gbAlvo := TGroupBox.Create(Self);
  gbAlvo.Parent := Self;
  gbAlvo.SetBounds(12, 8, 624, 158);
  gbAlvo.Caption := ' Alvo (SEFAZ) ';

  NewLabel('Estado (UF):', gbAlvo, 16, 24);
  cbUF := TComboBox.Create(Self);
  cbUF.Parent := gbAlvo;
  cbUF.Style := csDropDownList;
  cbUF.SetBounds(16, 42, 258, 24);
  for i := 0 to High(UFs) do
    cbUF.Items.Add(Format('%s - %s', [UFs[i].UF, UFs[i].Nome]));
  cbUF.OnChange := ufChange;

  NewLabel('Ambiente:', gbAlvo, 290, 24);
  cbAmb := TComboBox.Create(Self);
  cbAmb.Parent := gbAlvo;
  cbAmb.Style := csDropDownList;
  cbAmb.SetBounds(290, 42, 170, 24);
  cbAmb.Items.Add('Producao');
  cbAmb.Items.Add('Homologacao');
  cbAmb.ItemIndex := 0;
  cbAmb.OnChange := ufChange;

  NewLabel('Host ou IP:', gbAlvo, 16, 76);
  edHost := NewEdit('', gbAlvo, 16, 94, 368);
  edHost.TextHint := 'ex.: nfce.svrs.rs.gov.br';
  NewLabel('Porta:', gbAlvo, 398, 76);
  edPorta := NewEdit('443', gbAlvo, 398, 94, 70);
  btnResolver := NewButton('Resolver IPs', gbAlvo, 484, 92, 124, 26, btnResolverClick);
  lblIPs := NewLabel('IPs: (nenhum resolvido)', gbAlvo, 16, 126, 592);
  lblIPs.WordWrap := True;
  lblIPs.Height := 28;

  // ---- Limites ----
  gbLim := TGroupBox.Create(Self);
  gbLim.Parent := Self;
  gbLim.SetBounds(12, 174, 624, 168);
  gbLim.Caption := ' Limites ';

  NewLabel('Banda (KB/s, 0 = ilimitado):', gbLim, 16, 28);
  edBanda := NewEdit('0', gbLim, 230, 24, 80);
  edBanda.OnChange := cfgChange;
  NewLabel('Latencia (ms):', gbLim, 16, 60);
  edLat := NewEdit('0', gbLim, 230, 56, 80);
  edLat.OnChange := cfgChange;
  NewLabel('Perda de pacotes (%):', gbLim, 16, 92);
  edPerda := NewEdit('0', gbLim, 230, 88, 80);
  edPerda.OnChange := cfgChange;

  chkBlock := TCheckBox.Create(Self);
  chkBlock.Parent := gbLim;
  chkBlock.SetBounds(330, 28, 280, 22);
  chkBlock.Caption := 'Bloquear so a SEFAZ (SEFAZ fora)';
  chkBlock.OnClick := chkBlockClick;

  NewLabel('Presets:', gbLim, 330, 60);
  NewButton('Normal', gbLim, 330, 80, 70, 26, presetNormal);
  NewButton('Lento', gbLim, 406, 80, 70, 26, presetLento);
  NewButton('Instavel', gbLim, 482, 80, 70, 26, presetInstavel);
  NewButton('SEFAZ fora', gbLim, 330, 112, 146, 26, presetFora);

  NewLabel('Pode ajustar os valores ao vivo com a limitacao rodando.',
    gbLim, 16, 124, 300);

  // ---- Controle da limitacao (so SEFAZ) ----
  btnStart := NewButton('Iniciar limitacao', Self, 12, 352, 170, 34, btnStartClick);
  btnStop := NewButton('Parar', Self, 192, 352, 130, 34, btnStopClick);
  lblRunning := NewLabel('PARADO', Self, 338, 362);
  lblRunning.Font.Style := [fsBold];

  chkGlobal := TCheckBox.Create(Self);
  chkGlobal.Parent := Self;
  chkGlobal.SetBounds(412, 360, 224, 20);
  chkGlobal.Caption := 'Internet GERAL do PC lenta';
  chkGlobal.Hint := 'Marcado: aplica banda/latencia/perda em TODO o trafego ' +
    'do PC. Desmarcado: limita so o link da SEFAZ (o host do alvo).';
  chkGlobal.ShowHint := True;

  // ---- Corte imediato de TODA a internet ----
  btnKill := NewButton('CORTAR INTERNET (tudo)', Self, 12, 396, 300, 38, btnKillClick);
  btnKill.Font.Style := [fsBold];
  lblNet := NewLabel('Internet: ativa', Self, 322, 406);
  lblNet.Font.Style := [fsBold];
  btnSistema := NewButton('Fechar Sistema.exe', Self, 466, 396, 170, 38, btnSistemaClick);
  btnSistema.Font.Style := [fsBold];

  // ---- Corte automatico (timer) ----
  NewLabel('Cortar em', Self, 12, 448);
  edCutSecs := NewEdit('5', Self, 78, 444, 44);
  NewLabel('s', Self, 128, 448);
  btnSched := NewButton('Agendar corte', Self, 146, 442, 156, 28, btnSchedClick);
  NewLabel('e restaurar apos', Self, 314, 448);
  edRestSecs := NewEdit('0', Self, 410, 444, 44);
  NewLabel('s (0 = ficar cortado)', Self, 460, 448);

  // ---- Status ----
  gbStatus := TGroupBox.Create(Self);
  gbStatus.Parent := Self;
  gbStatus.SetBounds(12, 480, 624, 88);
  gbStatus.Caption := ' Status (tempo real) ';
  lblLive := NewLabel('Ping: --      |      Vazao: --', gbStatus, 16, 20, 596);
  lblLive.Font.Style := [fsBold];
  lblLive.Font.Size := 11;
  lblStats := NewLabel('(limitacao parada)', gbStatus, 16, 52, 596);
  lblStats.WordWrap := True;
  lblStats.Height := 30;

  // ---- Log ----
  NewLabel('Log:', Self, 12, 576);
  memoLog := TMemo.Create(Self);
  memoLog.Parent := Self;
  memoLog.SetBounds(12, 594, 624, 104);
  memoLog.ReadOnly := True;
  memoLog.ScrollBars := ssVertical;
  memoLog.Font.Name := 'Consolas';

  timer := TTimer.Create(Self);
  timer.Interval := 500;
  timer.OnTimer := timerTick;
  timer.Enabled := True;

  schedTimer := TTimer.Create(Self);
  schedTimer.Interval := 1000;
  schedTimer.OnTimer := schedTick;
  schedTimer.Enabled := False;

  UpdateUIState;
  UpdateKillUI;
  UpdateSchedUI;
end;

procedure TfrmMain.SelectUF(const ACode: string);
var
  i: Integer;
begin
  for i := 0 to High(UFs) do
    if SameText(UFs[i].UF, ACode) then
    begin
      cbUF.ItemIndex := i;
      ufChange(nil); // setar por codigo nao dispara OnChange
      Break;
    end;
end;

{ ctor/dtor }

procedure TfrmMain.CreateParams(var Params: TCreateParams);
begin
  inherited CreateParams(Params);
  // garante botao proprio na barra de tarefas (janela de aplicativo)
  Params.ExStyle := Params.ExStyle or WS_EX_APPWINDOW;
end;

procedure TfrmMain.formShow(Sender: TObject);
begin
  // traz a janela pra frente quando abre (nao fica escondida atras)
  Application.BringToFront;
  SetForegroundWindow(Handle);
end;

constructor TfrmMain.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner); // nao tenta carregar DFM
  FEngine := TThrottleEngine.Create;
  FKill := TKillSwitch.Create;
  FPing := TPingThread.Create;
  BuildUI;
  Log('Pronto. Escolha o estado (ou digite o host), resolva os IPs e Iniciar.');
  Log('IMPORTANTE: execute como Administrador (o WinDivert precisa).');
  SelectUF('PA'); // caso do usuario: PA usa a SVRS
end;

destructor TfrmMain.Destroy;
begin
  if Assigned(FEngine) then
  begin
    FEngine.Stop;
    FEngine.Free;
  end;
  if Assigned(FKill) then
  begin
    FKill.Release;
    FKill.Free;
  end;
  if Assigned(FPing) then
    FPing.Free;
  inherited;
end;

{ logica }

procedure TfrmMain.Log(const S: string);
begin
  memoLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + '  ' + S);
end;

procedure TfrmMain.ApplyConfig;
begin
  FEngine.RateBytesPerSec := Max(0, StrToIntDef(Trim(edBanda.Text), 0)) * 1024;
  FEngine.LatencyMs := Max(0, StrToIntDef(Trim(edLat.Text), 0));
  FEngine.LossPercent := Min(100, Max(0, StrToIntDef(Trim(edPerda.Text), 0)));
  FEngine.BlockAll := chkBlock.Checked;
end;

function TfrmMain.BuildFilter: string;
var
  sb: TStringBuilder;
  i, porta: Integer;
begin
  if chkGlobal.Checked then
    Exit('(ip or ipv6) and not loopback'); // limita TODO o trafego

  porta := StrToIntDef(Trim(edPorta.Text), 0);
  sb := TStringBuilder.Create;
  try
    sb.Append('(');
    for i := 0 to High(FResolvedIPs) do
    begin
      if i > 0 then
        sb.Append(' or ');
      sb.AppendFormat('ip.SrcAddr == %0:s or ip.DstAddr == %0:s', [FResolvedIPs[i]]);
    end;
    sb.Append(')');
    if porta > 0 then
      sb.AppendFormat(' and (tcp.SrcPort == %0:d or tcp.DstPort == %0:d)', [porta]);
    Result := sb.ToString;
  finally
    sb.Free;
  end;
end;

function TfrmMain.ResolveNow: Boolean;
var
  ip: string;
  s: string;
  pp: Integer;
begin
  Result := ResolveHostIPv4(edHost.Text, FResolvedIPs);
  if Result then
  begin
    s := '';
    for ip in FResolvedIPs do
    begin
      if s <> '' then
        s := s + ', ';
      s := s + ip;
    end;
    lblIPs.Caption := 'IPs: ' + s;
    Log('Resolvido "' + Trim(edHost.Text) + '" -> ' + s);
    if Assigned(FPing) then
    begin
      pp := StrToIntDef(Trim(edPorta.Text), 443);
      if pp <= 0 then
        pp := 443;
      FPing.SetTarget(FResolvedIPs[0], pp);
    end;
  end
  else
  begin
    FResolvedIPs := nil;
    lblIPs.Caption := 'IPs: (falha ao resolver)';
    Log('FALHA ao resolver "' + Trim(edHost.Text) + '".');
  end;
end;

procedure TfrmMain.UpdateUIState;
var
  run: Boolean;
begin
  run := Assigned(FEngine) and FEngine.Running;
  cbUF.Enabled := not run;
  cbAmb.Enabled := not run;
  edHost.Enabled := not run;
  edPorta.Enabled := not run;
  btnResolver.Enabled := not run;
  chkGlobal.Enabled := not run;
  btnStart.Enabled := not run;
  btnStop.Enabled := run;
  if run then
  begin
    lblRunning.Caption := 'LIMITANDO';
    lblRunning.Font.Color := clGreen;
  end
  else
  begin
    lblRunning.Caption := 'PARADO';
    lblRunning.Font.Color := clRed;
  end;
end;

procedure TfrmMain.UpdateKillUI;
begin
  if Assigned(FKill) and FKill.Active then
  begin
    btnKill.Caption := 'RESTAURAR INTERNET';
    lblNet.Caption := 'Internet: CORTADA';
    lblNet.Font.Color := clRed;
  end
  else
  begin
    btnKill.Caption := 'CORTAR INTERNET (tudo)';
    lblNet.Caption := 'Internet: ativa';
    lblNet.Font.Color := clGreen;
  end;
end;

{ eventos }

procedure TfrmMain.ufChange(Sender: TObject);
var
  i: Integer;
  host: string;
begin
  i := cbUF.ItemIndex;
  if (i < 0) or (i > High(UFs)) then
    Exit;
  if cbAmb.ItemIndex = 1 then
  begin
    host := UFs[i].Homol;
    if host = '' then
      host := UFs[i].Prod;
  end
  else
    host := UFs[i].Prod;
  edHost.Text := host;
  FResolvedIPs := nil;
  ResolveNow;
end;

procedure TfrmMain.btnResolverClick(Sender: TObject);
begin
  ResolveNow;
end;

procedure TfrmMain.btnStartClick(Sender: TObject);
var
  filter: string;
begin
  try
    if (not chkGlobal.Checked) and (Length(FResolvedIPs) = 0) and not ResolveNow then
    begin
      ShowMessage('Nao consegui resolver o host. Escolha um estado ou informe um host/IP valido.');
      Exit;
    end;
    filter := BuildFilter;
    ApplyConfig;
    FEngine.Start(filter);
    Log('Limitacao INICIADA. Filtro: ' + filter);
  except
    on E: Exception do
    begin
      Log('ERRO: ' + E.Message);
      ShowMessage(E.Message);
    end;
  end;
  UpdateUIState;
end;

procedure TfrmMain.btnStopClick(Sender: TObject);
begin
  FEngine.Stop;
  Log('Limitacao PARADA. Pacotes em espera foram liberados.');
  UpdateUIState;
end;

procedure TfrmMain.btnKillClick(Sender: TObject);
begin
  CancelSchedule(False); // acao manual cancela qualquer agendamento pendente
  try
    if FKill.Active then
    begin
      FKill.Release;
      Log('Internet RESTAURADA.');
    end
    else
    begin
      FKill.Engage;
      Log('INTERNET CORTADA agora (todo o trafego, exceto loopback).');
    end;
  except
    on E: Exception do
    begin
      Log('ERRO: ' + E.Message);
      ShowMessage(E.Message);
    end;
  end;
  UpdateKillUI;
end;

procedure TfrmMain.btnSistemaClick(Sender: TObject);
var
  n: Integer;
begin
  n := KillProcessByName('Sistema.exe');
  if n > 0 then
    Log(Format('Sistema.exe finalizado imediatamente (%d processo(s)).', [n]))
  else
    Log('Sistema.exe nao estava em execucao.');
end;

procedure TfrmMain.UpdateSchedUI;
begin
  case FSchedState of
    SCHED_TO_CUT:
      btnSched.Caption := Format('Cancelar (corta em %ds)', [FSchedLeft]);
    SCHED_TO_RESTORE:
      btnSched.Caption := Format('Cancelar (restaura em %ds)', [FSchedLeft]);
  else
    btnSched.Caption := 'Agendar corte';
  end;
  edCutSecs.Enabled := FSchedState = SCHED_IDLE;
  edRestSecs.Enabled := FSchedState = SCHED_IDLE;
end;

procedure TfrmMain.CancelSchedule(const ALog: Boolean);
begin
  if FSchedState = SCHED_IDLE then
    Exit;
  schedTimer.Enabled := False;
  FSchedState := SCHED_IDLE;
  if ALog then
    Log('Agendamento cancelado.');
  UpdateSchedUI;
end;

procedure TfrmMain.btnSchedClick(Sender: TObject);
var
  cutS: Integer;
begin
  if FSchedState <> SCHED_IDLE then
  begin
    CancelSchedule(True);
    Exit;
  end;
  cutS := Max(1, StrToIntDef(Trim(edCutSecs.Text), 5));
  FSchedRestore := Max(0, StrToIntDef(Trim(edRestSecs.Text), 0));
  FSchedState := SCHED_TO_CUT;
  FSchedLeft := cutS;
  schedTimer.Enabled := True;
  if FSchedRestore > 0 then
    Log(Format('Agendado: cortar em %ds e restaurar %ds depois.', [cutS, FSchedRestore]))
  else
    Log(Format('Agendado: cortar a internet em %ds.', [cutS]));
  UpdateSchedUI;
end;

procedure TfrmMain.schedTick(Sender: TObject);
begin
  Dec(FSchedLeft);
  if FSchedLeft > 0 then
  begin
    UpdateSchedUI;
    Exit;
  end;

  if FSchedState = SCHED_TO_CUT then
  begin
    try
      FKill.Engage;
      Log('INTERNET CORTADA (agendada).');
    except
      on E: Exception do
      begin
        Log('ERRO ao cortar: ' + E.Message);
        ShowMessage(E.Message);
        CancelSchedule(False);
        UpdateKillUI;
        Exit;
      end;
    end;
    UpdateKillUI;
    if FSchedRestore > 0 then
    begin
      FSchedState := SCHED_TO_RESTORE;
      FSchedLeft := FSchedRestore;
      UpdateSchedUI;
    end
    else
      CancelSchedule(False);
  end
  else // SCHED_TO_RESTORE
  begin
    FKill.Release;
    Log('Internet RESTAURADA (agendada).');
    UpdateKillUI;
    CancelSchedule(False);
  end;
end;

procedure TfrmMain.chkBlockClick(Sender: TObject);
begin
  if FEngine.Running then
  begin
    FEngine.BlockAll := chkBlock.Checked;
    if chkBlock.Checked then
      Log('Bloqueio da SEFAZ LIGADO.')
    else
      Log('Bloqueio da SEFAZ DESLIGADO.');
  end;
end;

procedure TfrmMain.cfgChange(Sender: TObject);
begin
  if Assigned(FEngine) and FEngine.Running then
    ApplyConfig;
end;

procedure TfrmMain.presetNormal(Sender: TObject);
begin
  edBanda.Text := '0';
  edLat.Text := '0';
  edPerda.Text := '0';
  chkBlock.Checked := False;
  chkBlockClick(nil);
end;

procedure TfrmMain.presetLento(Sender: TObject);
begin
  edBanda.Text := '8';
  edLat.Text := '600';
  edPerda.Text := '0';
  chkBlock.Checked := False;
  chkBlockClick(nil);
end;

procedure TfrmMain.presetInstavel(Sender: TObject);
begin
  edBanda.Text := '20';
  edLat.Text := '300';
  edPerda.Text := '20';
  chkBlock.Checked := False;
  chkBlockClick(nil);
end;

procedure TfrmMain.presetFora(Sender: TObject);
begin
  chkBlock.Checked := True;
  chkBlockClick(nil);
end;

procedure TfrmMain.timerTick(Sender: TObject);
var
  st: TThrottleStats;
  ms: Integer;
  nowT: UInt64;
  dt: Double;
  pingStr, vazStr: string;
begin
  // ---- Ping (sempre) ----
  ms := -2;
  if Assigned(FPing) then
    ms := FPing.GetLast;
  if ms = -2 then
    pingStr := 'Ping: -- (sem alvo)'
  else if ms = -1 then
    pingStr := 'Ping: SEM RESPOSTA'
  else
    pingStr := Format('Ping: %d ms', [ms]);

  // ---- Vazao (so quando limitando) ----
  if Assigned(FEngine) and FEngine.Running then
  begin
    st := FEngine.GetStats;
    nowT := GetTickCount64;
    if FLastRateTick = 0 then
    begin
      FLastRateTick := nowT;
      FLastBytes := st.BytesSent;
    end;
    dt := (nowT - FLastRateTick) / 1000.0;
    if dt >= 0.4 then
    begin
      FLastRate := (st.BytesSent - FLastBytes) / dt; // bytes/s
      FLastBytes := st.BytesSent;
      FLastRateTick := nowT;
    end;
    vazStr := Format('Vazao: %.1f KB/s (%.0f kbps)', [FLastRate / 1024, FLastRate * 8 / 1000]);
    lblStats.Caption := Format(
      'Capturados: %d  |  Reinjetados: %d  |  Descartados: %d  |  Na fila: %d  |  Total: %.1f KB',
      [st.Captured, st.Sent, st.Dropped, st.Queued, st.BytesSent / 1024]);
  end
  else
  begin
    vazStr := 'Vazao: -- (parado)';
    FLastRateTick := 0;
    FLastBytes := 0;
    FLastRate := 0;
    lblStats.Caption := '(limitacao parada)';
  end;

  lblLive.Caption := pingStr + '          |          ' + vazStr;
end;

procedure TfrmMain.formClose(Sender: TObject; var Action: TCloseAction);
begin
  timer.Enabled := False;
  if Assigned(schedTimer) then
    schedTimer.Enabled := False;
  if Assigned(FEngine) then
    FEngine.Stop;
  if Assigned(FKill) then
    FKill.Release;
end;

end.
