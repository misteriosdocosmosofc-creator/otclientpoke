# Ciclo de desenvolvimento Android

## Ambiente e comando

Codespace: `otc-android-build-p7j4q4rw7j762969r`, repo `otclientpoke`, branch
`codex/pokealliance-http-login`, 4 CPUs/16 GB, parada por inatividade em 15 min.
O `.devcontainer` prepara um novo ambiente; o atual ja foi provisionado.

```bash
cd /workspaces/otclientpoke
git pull --ff-only
bash tools/android-dev/build-android.sh
```

A primeira compilacao preenche os caches. Nas seguintes, preservar `android/app/.cxx`,
`android/app/build`, `android/.gradle` e `/workspaces/.otc-android`. Nao executar clean.
Gradle daemon/build cache, ccache e vcpkg binary cache ficam habilitados. O helper
usa uma ABI (`armeabi-v7a`); LuaJIT e data.zip so sao refeitos quando necessario.
Debug desativa LTO e isola `protocolgameparse.cpp` do Unity Build, mantendo PCH.
Release mantem suas configuracoes de otimizacao.

## Assinatura consistente

O Codespace usa `/workspaces/.otc-android/signing/debug.keystore`. A mesma chave esta
no secret Actions `OTCLIENT_DEBUG_KEYSTORE_BASE64`; o workflow restaura a chave em
diretorio temporario. O mesmo secret de usuario Codespaces, restrito a este repo,
restaura a chave no bootstrap de ambientes novos. O workflow passa
`OTCLIENT_DEBUG_KEYSTORE` ao Gradle. Nao versionar chave,
backups privados, preauth nem capturas. A migracao de um APK antigo com assinatura
efemera ainda pode exigir uma ultima reinstalacao com backup. Depois, usar update.

## Ordem das rodadas

1. Reproduzir o mesmo buffer preservado, com DAT e perfil equivalentes.
2. Comparar o primeiro limite de registro divergente e o fim exato do FullMap.
3. Corrigir leituras/gates comprovados e repetir todas as capturas de regressao.
4. Avisar o usuario antes de compilar o APK. Compilar incrementalmente no Codespace.
5. Instalar preservando dados, sincronizar modulos ativos e conferir hashes.
6. Armar coletor; o usuario entra manualmente. Conferir mapa, posicao, movimento,
   mensagens seguintes e estabilidade. Fechar o app apos a coleta.

## Reproducao sem servidor

`tools/pka-replay/replay.cpp` compila com um compilador C++20 comum, sem engine,
OpenGL, SDK ou rede. Usa os leitores PKA de `src/client/pkaprotocol.h`, compartilhados
com o cliente: atributos de item, extensao de outfit e cauda de criatura. Nao simula
renderizacao nem efeitos de estado da engine; por isso a validacao visual continua
necessaria. As capturas e o DAT permanecem privados fora do Git.

```bash
g++ -std=c++20 -O0 tools/pka-replay/replay.cpp -o /tmp/pka-replay
/tmp/pka-replay PAYLOAD.bin ITEM_FLAGS.txt 32 20 TRACE.jsonl
python3 tools/pka-replay/compare.py PC_CAPTURE_DIRECTORY TRACE.jsonl
```

`prepare.py` extrai flags do DAT e o payload de uma captura PC, recebendo por
`--dat-reader` o script privado de leitura de DAT usado na investigacao.
O payload comeca nos cinco bytes da posicao. O fim de FullMap e anterior ao fim
do buffer quando existem outros opcodes. `--tail` (apos TRACE.jsonl) inspeciona
mensagens posteriores conhecidas e para no primeiro opcode ainda nao mapeado.

## Lua e configuracao sem APK

No Windows, apos instalar um binario compativel:

```powershell
./tools/android-dev/sync-android-modules.ps1 -Diagnostics records -StartApp
```

O script para o aplicativo, copia somente os modulos permitidos para
`files/game_data`, compara SHA-256 e opcionalmente reabre o app. DAT/SPR e credenciais
nao entram nessa sincronizacao. Usar `-Files` para outros modulos permitidos.

## Diagnosticos em runtime

`pka-debug.otml` na raiz ativa de game_data aceita `level: off`, `summary`, `records`
ou `capture`. A copia pelo helper vale no proximo inicio do app. Tambem e possivel
alterar imediatamente no console Lua:

```lua
g_settings.set('protocol-diagnostics', 'records')
```

O ajuste de g_settings tem prioridade. `summary` e o padrao leve. `records` habilita
traces limitados de tiles/criaturas/transporte; `capture` acrescenta captura do
primeiro FullMap e grava `records/pka-session.cam` no diretorio gravavel. O primeiro
pacote de saida com autenticacao nao e gravado pelo recorder existente.

Para reproduzir a gravacao no cliente, configurar o mesmo DAT/features e perfil:

```lua
g_game.setClientVersion(860)
g_game.setProtocolVersion(854)
g_game.setPokeAllianceProtocol(true)
g_game.enableFeature(GameOpcodeU16)
g_game.playRecord('pka-session.cam')
```

## Evidencia inicial da correcao

Captura PC direta: 4443 tiles descritos, 677 pulados, 5318 itens, 23 criaturas.
O leitor compartilhado terminou em 45372 bytes relativos a posicao, equivalente
ao cursor PC 45434, e todos os limites de tiles/itens/criaturas coincidiram.
Segunda captura PC: 5320 itens/20 criaturas; fim relativo 45089, tambem identico.
Duas capturas Android antes rejeitadas completaram o FullMap offline.

Correcoes comprovadas: area PKA 32x20 em vez de 18x14; campos extras de criatura
restritos ao subtipo zero; subtipos 1 e 3 sem records; prelude subtipo 4 com sete
bytes fixos antes do gate opcional. Formatos nao exercitados continuam dependentes
de evidencia adicional; compilar nao prova renderizacao no aparelho.

## Checkpoint antes do primeiro APK no Codespace

As duas capturas Android (`39878774090`, `39872615612`) passaram pelo FullMap e
por todos os opcodes restantes ate o ultimo byte (52952 e 53095 bytes).
Os dois traces PC coincidem em todos os limites de tile/item/criatura. Os arquivos
PC preservados terminam quatro bytes antes de completar o ultimo valor U32 do
opcode 0x53; o replay acusa truncamento, sem completar esses bytes artificialmente.
Nas capturas Android esse ultimo valor esta presente e o pacote termina exato.

Alem do mapa, foram alinhados efeitos, luz global, stats, VIP, outfit, inventario,
containers (descricao extra e contagem U16) e as formas de mensagens customizadas
exercitadas pelo bootstrap. Metadados customizados sao consumidos para compatibilidade;
suas interfaces PKA completas ainda nao foram implementadas. Formas de opcode
nao observadas continuam exigindo evidencia, sobretudo atualizacoes durante movimento.

As dependencias iniciais foram compiladas no Codespace em 28 minutos. Esse custo
ficou no cache persistente; nao e uma medida do tempo das proximas correcoes.
O primeiro build da engine tambem precisa preencher seus proprios objetos.

## Medicao e ccache com PCH

Primeiro Gradle/engine: BUILD SUCCESSFUL em 7 min, apos provisionamento e dependencias.
Execucao seguinte sem mudancas: 15 s no Gradle, 16.123 s no helper completo.
Isso mede o caso sem recompilacao, nao uma correcao C++ real.

O primeiro contador do ccache mostrou 24 compilacoes sem cache por PCH. O perfil
de iteracao agora configura `pch_defines,time_macros` e Clang `-fno-pch-timestamp`,
conforme o [manual oficial do ccache](https://ccache.dev/manual/4.9.1.html#_precompiled_headers).
A permissao de macros de tempo e exclusiva desse ciclo de desenvolvimento:
nao usar __DATE__/__TIME__ como identidade confiavel do binario; registrar commit
junto ao hash SHA-256 do APK. Release conserva suas opcoes anteriores.
