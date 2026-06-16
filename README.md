# SimpleNetLimiter

**Limitador de internet open-source (Delphi + WinDivert) feito para testar contingência de NFC-e.**
Uma alternativa gratuita e direta ao NetLimiter, focada em degradar/derrubar **só o link da SEFAZ** (ou a internet inteira, se você quiser) para validar como o seu sistema se comporta quando a SEFAZ fica lenta ou cai.

![Platform](https://img.shields.io/badge/plataforma-Windows-blue)
![Language](https://img.shields.io/badge/linguagem-Delphi-red)
![Engine](https://img.shields.io/badge/engine-WinDivert%202.2-green)
![License](https://img.shields.io/badge/licen%C3%A7a-MIT-lightgrey)

---

## Por que existe

Para emitir NFC-e o sistema conversa com o webservice da SEFAZ. Quando esse webservice fica **lento** ou **indisponível**, o sistema deve entrar em **contingência** (emissão offline, reenvio etc.). Testar isso de verdade exige simular uma rede ruim — e ferramentas como o NetLimiter fazem isso, mas são pagas.

O **SimpleNetLimiter** reproduz o essencial: intercepta os pacotes de rede e **segura, atrasa, descarta ou bloqueia** — direcionado ao host da SEFAZ, sem precisar derrubar a internet inteira da máquina.

---

## Recursos

- 🎯 **Limita só a SEFAZ** — por IP + porta (HTTPS/443). O resto da internet continua normal.
- 🌐 **Modo "internet geral lenta"** — um checkbox aplica o limite em **todo** o tráfego do PC (bom para validar com um speed test).
- 🐢 **Banda (KB/s), latência (ms) e perda de pacotes (%)** — ajustáveis ao vivo.
- ⚡ **Presets**: Normal · Lento · Instável · SEFAZ fora.
- ✂️ **CORTAR INTERNET** — kill-switch instantâneo (liga/desliga) que derruba todo o tráfego na hora.
- ⏱️ **Corte agendado** — "cortar em N segundos" (com contagem regressiva) e, opcional, "restaurar após M segundos".
- ☠️ **Fechar Sistema.exe** — encerra o ERP imediatamente, para testar recuperação após queda abrupta.
- 📊 **Ping e vazão em tempo real** — latência (TCP) até o alvo e throughput (KB/s · kbps) passando pelo limitador.
- 🗺️ **Combobox dos 27 estados** — seleciona a UF e já preenche/resolve o host da NFC-e (estados que usam a **SVRS** — PA, RJ, SC, ES, DF... — caem em `nfce.svrs.rs.gov.br`).
- 🇧🇷 **Produção ou Homologação** — alterna o ambiente da SEFAZ.

---

## Como funciona

O motor é o **[WinDivert](https://reqrypt.org/windivert.html) 2.2** (user-mode, com driver `.sys` assinado — a mesma base do `clumsy`). É aberto um handle na camada NETWORK com um filtro que casa **só o tráfego do alvo**, por exemplo:

```
(ip.SrcAddr == 4.201.99.36 or ip.DstAddr == 4.201.99.36)
  and (tcp.SrcPort == 443 or tcp.DstPort == 443)
```

Dois threads tratam os pacotes:

- **Captura** (`WinDivertRecv`) — aplica a política (perda/banda/latência/bloqueio) e enfileira.
- **Liberação** (`WinDivertSend`) — reinjeta o pacote no instante calculado.

A **banda** é uma serialização (cada pacote ocupa o link por `bytes ÷ taxa` segundos), a **latência** é um atraso fixo na reinjeção, a **perda** descarta uma fração aleatória e o **bloqueio** simplesmente não reinjeta. O **kill-switch** usa um handle com `FLAG_DROP` (o driver descarta tudo, instantâneo, sem cópia para user-mode).

---

## Requisitos

- **Windows** (x64 ou x86).
- Rodar **como Administrador** — o WinDivert precisa instalar/abrir o driver. O `.exe` já pede elevação pelo manifest (mostra o escudo do UAC).
- Para **compilar**: Delphi (testado no **Tokyo / Studio 19.0**, Win32). O `build.bat` usa o `dcc32` + `brcc32` da linha de comando.

---

## Compilar

```bat
cd src
build.bat
```

Saída em `bin\` (já com `WinDivert.dll` + os `.sys` copiados ao lado). O `build.bat` também gera o `smoke.exe`, um teste de fumaça do binding (valida a convenção de chamada e o layout das structs sem precisar de admin).

Recriar o ícone ou os atalhos:

```bat
powershell -ExecutionPolicy Bypass -File src\mkico.ps1   :: regenera app.ico
powershell -ExecutionPolicy Bypass -File src\make-shortcuts.ps1  :: Menu Iniciar + Desktop
```

---

## Usar

1. Abra `bin\SefazThrottle.exe` (ou o atalho **"Limitador SEFAZ NFCe"**) e **aceite o UAC**.
2. Escolha o **Estado (UF)** — o host da SEFAZ é preenchido e resolvido automaticamente. Alterne **Produção/Homologação** se precisar.
3. Use um **preset** (ex.: *Lento*) ou ajuste banda/latência/perda; clique **Iniciar limitação**.
4. Emita a NFC-e no seu sistema e observe a contingência. Acompanhe **Ping** e **Vazão** no painel de status.
5. **Parar** (ou fechar) libera os pacotes em espera e a SEFAZ volta ao normal.

```
┌────────────────────────────────────────────────────────────┐
│ Alvo (SEFAZ)                                                 │
│  Estado: [PA - Para (SVRS) ▾]   Ambiente: [Produção ▾]       │
│  Host: [nfce.svrs.rs.gov.br      ] Porta:[443] [Resolver IPs]│
│  IPs: 4.201.99.36                                            │
├────────────────────────────────────────────────────────────┤
│ Limites                                                      │
│  Banda(KB/s):[8]  Latência(ms):[600]  Perda(%):[0]           │
│  [Normal][Lento][Instável]   ☐ Bloquear só a SEFAZ           │
├────────────────────────────────────────────────────────────┤
│ [Iniciar limitação] [Parar]   LIMITANDO  ☐ Internet GERAL    │
│ [ CORTAR INTERNET (tudo) ]  Internet:ativa  [Fechar Sistema] │
│  Cortar em [5] s [Agendar corte]  e restaurar após [0] s     │
├────────────────────────────────────────────────────────────┤
│ Status (tempo real)                                          │
│  Ping: 240 ms      |      Vazão: 8,1 KB/s (65 kbps)          │
└────────────────────────────────────────────────────────────┘
```

### "Liguei o Lento e o speed test não mudou"

Normal: por padrão o limite vale **só para o host da SEFAZ**. Um speed test fala com outros servidores, então não é afetado. Para ver com um speed test (ou degradar a máquina toda), marque **"Internet GERAL do PC lenta"** antes de iniciar.

### Cenários de teste de contingência

| Cenário | Como | O que valida |
|---|---|---|
| SEFAZ lenta | preset **Lento** | comportamento sob rede degradada, timeouts parciais |
| SEFAZ intermitente | preset **Instável** | reenvio / retentativa |
| SEFAZ fora | preset **SEFAZ fora** ou **CORTAR INTERNET** | detecção de indisponibilidade → contingência offline |
| Queda abrupta | **Corte agendado** + **Fechar Sistema.exe** | recuperação da NFC-e pendente ao reabrir |

---

## Estrutura

```
src/
  WinDivert.pas       binding cdecl da WinDivert 2.2 (struct de 80 bytes)
  ThrottleEngine.pas  motor (threads de captura/liberação) + kill-switch
  uPing.pas           TCP-ping em thread (latência ao alvo)
  uHostResolve.pas    host -> IPs (Winsock)
  uProcKill.pas       fechar processo por nome (Sistema.exe)
  uMain.pas           interface (montada em código, sem DFM)
  SefazThrottle.dpr   programa
  smoke.dpr           teste do binding (não precisa de admin)
  app.manifest/.rc    manifest de elevação + ícone (MAINICON)
  build.bat           compila tudo e copia o runtime do WinDivert
  mkico.ps1           gera o ícone (app.ico)
  make-shortcuts.ps1  cria atalhos no Menu Iniciar e Desktop
lib/                  WinDivert.dll + WinDivert32/64.sys + windivert.h + LICENSE
bin/                  saída do build (não versionada)
```

---

## Aviso legal

Ferramenta de **teste**, para uso na **sua própria máquina/rede e nos seus próprios sistemas** (idealmente em ambiente de homologação). Interceptar/derrubar tráfego de terceiros sem autorização é indevido. Use com responsabilidade.

---

## Licença

- Código deste repositório: **MIT** (veja [LICENSE](LICENSE)).
- **WinDivert** (binários em `lib/`): **LGPLv3 / GPLv2** por Basil00 (veja [lib/LICENSE](lib/LICENSE)). A redistribuição é permitida sob esses termos.
