# Limitador de Internet — Testes de Contingência NFCe

Substituto caseiro do NetLimiter, focado em **testar contingência da NFCe**:
limita banda, injeta latência, descarta pacotes ou derruba a conexão — tudo
**só com o host/IP da SEFAZ**, sem afetar o resto da internet da máquina.

Motor: **WinDivert 2.2** (mesma base do `clumsy`). É user-mode; o driver
`.sys` já vem assinado pela Microsoft/autor. Não precisa de driver próprio.

## Como funciona

Abre um handle WinDivert na camada NETWORK com um filtro tipo
`(ip.SrcAddr==X or ip.DstAddr==X) and (tcp.SrcPort==443 or tcp.DstPort==443)`.
Dois threads:

- **Captura** (`WinDivertRecv`): aplica a política e enfileira ou descarta.
- **Liberação** (`WinDivertSend`): reinjeta o pacote no instante calculado.

Banda = serialização (cada pacote ocupa o link por `bytes/taxa` segundos).
Latência = atraso fixo na reinjeção. Perda = descarte aleatório. Bloqueio =
não reinjeta nada (a SEFAZ "some").

## Atalhos e ícone

O exe já tem ícone próprio embutido (`MAINICON`, gerado por `src\mkico.ps1`).
Há atalhos prontos no **Menu Iniciar** e na **Área de Trabalho**
("Limitador SEFAZ NFCe") — basta procurar "Limitador" no Iniciar. Como o exe
pede elevação pelo manifest, o atalho já dispara o UAC.

Recriar atalhos (ex.: se mover a pasta) e regenerar o ícone:

```
powershell -ExecutionPolicy Bypass -File src\mkico.ps1   # regenera app.ico
src\make-shortcuts.ps1                                    # recria atalhos
```

## Rodar

> **Tem que ser como Administrador** (o WinDivert instala/abre o driver).
> O .exe já pede elevação pelo manifest — basta dar duplo clique e aceitar o UAC.

1. Abra `bin\SefazThrottle.exe` (aceite o UAC).
2. Escolha o **Estado (UF)** no combo — o host da SEFAZ é preenchido e resolvido
   automaticamente (PA, RJ, SC… caem na **SVRS** `nfce.svrs.rs.gov.br`). Dá pra
   trocar **Produção/Homologação** ou digitar um host/IP na mão. Porta = 443.
3. Ajuste **Banda / Latência / Perda** ou use um **preset**:
   - **Lento** — 8 KB/s, 600 ms (rede degradada)
   - **Instável** — 20 KB/s, 300 ms, 20% perda
   - **SEFAZ fora** — bloqueia tudo (dispara timeout → contingência)
   - **Normal** — sem limite
4. **Iniciar limitação**. Dá pra mexer nos valores ao vivo.
5. Emita a NFCe no Sistema e observe o comportamento de contingência.
6. **Parar** (ou fechar) — os pacotes em espera são liberados; a SEFAZ volta.

### Botão CORTAR INTERNET (corte imediato)

O botão vermelho **CORTAR INTERNET (tudo)** derruba na hora **todo** o tráfego
da máquina (IPv4+IPv6, menos loopback) — não só a SEFAZ. É um kill-switch:
clicou, parou; clica de novo (**RESTAURAR INTERNET**) e volta na hora. Usa um
handle WinDivert com `FLAG_DROP`, então é instantâneo e não depende da
limitação estar rodando.

> Diferença: o preset **SEFAZ fora** bloqueia **só** o host da SEFAZ (resto da
> internet continua). O botão **CORTAR INTERNET** mata **tudo**.

### Corte agendado (timer)

Linha **"Cortar em [5] s → Agendar corte"**: clica e a internet cai sozinha
daqui a N segundos (o botão vira contagem regressiva **Cancelar (corta em 4s…)**).
Serve pra começar a emitir a NFCe e a conexão cair **no meio** sem você ter
que voltar e clicar.

Campo opcional **"e restaurar após [N] s"** (0 = ficar cortado): faz a sequência
completa automática — espera, corta, espera, restaura. Bom pra teste sem mãos.
Qualquer clique manual em CORTAR/RESTAURAR cancela o agendamento.

### Botão Fechar Sistema.exe

Mata **na hora** (force-kill, `TerminateProcess`) todos os processos
`Sistema.exe` em execução — sem confirmação. Útil pra testar recuperação do ERP
após queda abrupta. Mostra no log quantos processos foram finalizados.

## "Liguei o Lento e o speed test não mudou"

Normal: o limite vale **só pro host do alvo (a SEFAZ)**. Um speed test fala com
outros servidores, então não é afetado. Pra confirmar que está funcionando,
olhe o **Status** — o contador *Capturados* só sobe quando há tráfego pra SEFAZ.

Pra ver com um speed test (ou degradar a máquina toda), marque
**"Limitar TUDO (ignora o host)"** antes de Iniciar: aí banda/latência/perda
valem pra todo o tráfego (menos loopback). Lembre de desmarcar pra voltar ao
modo focado na SEFAZ.

## Fluxo de teste de contingência sugerido

| Cenário | Config | O que valida |
|---|---|---|
| SEFAZ lenta | preset **Lento** | comportamento sob rede ruim, timeouts parciais |
| SEFAZ intermitente | preset **Instável** | reenvio / retentativa |
| SEFAZ fora | preset **SEFAZ fora** | detecção de indisponibilidade → contingência offline |

Dica: o IP da SEFAZ pode ter mais de um endereço e mudar com o tempo —
clique **Resolver IPs** de novo se trocar de estado/ambiente.

## Recompilar

```
cd src
build.bat
```

Usa `dcc32` do Delphi Tokyo (19.0) + `brcc32` pro manifest. Saída em `bin\`.
Se der **F2039 (arquivo travado)**, é o antivírus segurando o .exe — feche o
app / renomeie o .exe antigo e rode de novo.

## Estrutura

```
src\
  WinDivert.pas       binding cdecl da WinDivert 2.2 (struct de 80 bytes)
  ThrottleEngine.pas  motor: threads de captura/liberação, banda/latência/perda/bloqueio
  uHostResolve.pas    host -> IPs (Winsock)
  uMain.pas           UI (montada em código, sem DFM)
  SefazThrottle.dpr   programa
  smoke.dpr           teste do binding (não precisa de admin)
  app.manifest/app.rc manifest de elevação (requireAdministrator)
bin\
  SefazThrottle.exe   + WinDivert.dll + WinDivert32.sys + WinDivert64.sys
lib\                  fontes/headers/licença originais do WinDivert
```

## Limitações / notas

- IPv4 + TCP por porta (cobre HTTPS da SEFAZ). Filtro pode ser ampliado.
- Limita **por IP**, não por processo. Se outro app falar com o mesmo IP da
  SEFAZ, também é afetado (na prática, só o Sistema fala com a SEFAZ).
- WinDivert é LGPLv3 (ok para ferramenta interna).
- Os 3 arquivos do WinDivert (`.dll` + 2 `.sys`) precisam ficar **junto** do .exe.
