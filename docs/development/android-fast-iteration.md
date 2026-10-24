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

Objetos de runtime `Thing`/`Item` devem manter alinhamento natural. No ARMv7,
`#pragma pack(1)` em `Thing` causou SIGBUS/BUS_ADRALN no primeiro movimento:
`Position::isInRange` copiou a posicao por `vldr` a partir de endereco desalinhado.
Para crashes nativos, preservar logcat crash e CAM antes de reabrir; simbolizar
com o ELF do mesmo APK/build. Frames repetidos no unwinder isoladamente nao
comprovam recursao. Reproduzir a CAM na engine para exercitar o estado/movimento,
alem do leitor offline de bytes, antes da proxima entrada real.

Regressao de 23/10/2026: a mesma CAM de 13 mensagens reproduziu SIGBUS no APK
anterior e completou os dois movimentos +25 s online no APK `77e2ebcb9`, sem
fatal nativo. O replay nao valida estabilidade de uma conexao real prolongada.
O screenshot revelou tambem sprites corrompidos: o SPR PKA usa RGBA, confirmado
em todos os 586208 sprites nao vazios, enquanto o loader estava em RGB.
`game_things/things.lua` habilita alpha apenas no par DAT/SPR conhecido do
perfil 860, pelas assinaturas. Essa correcao Lua usa sync com hash, sem novo APK.
No segundo replay o mapa, criaturas e itens renderizaram legiveis por 25 s.
Remover/restaurar qualquer hook temporario de replay antes do teste real e
conferir o arquivo original por hash. Manter CAMs e screenshots privados.

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

### Encerramento durante o login

EOF antes de entrar no mundo deve acionar `onConnectionError`, para encerrar a
janela de conexao. EOF depois de uma sessao ou de uma resposta explicita de erro,
atualizacao, fila ou fim de sessao preserva o fluxo dessa resposta. O estado de
resposta e reinicializado em cada login/replay; nao substituir a mensagem original
do servidor por uma segunda caixa generica de EOF.

Reproducao de 23/10: a CAM privada de apenas challenge seguida por EOF, executada
sem rede com o login da CharacterList redirecionado ao PacketPlayer, deixou o APK
`980d1a5b8` com `errors=0`, `loadBoxDestroyed=false`, `online=false` e
`logging=false`. Isso reproduz a janela travada, sem demonstrar a causa do EOF
real. O ticket HTTPS tinha cerca de 100 s na tentativa real; seu prazo de validade
nao foi estabelecido: a tentativa aceita as 16:03 usava um ticket recebido as
13:03, entao a idade de 100 s nao e prova de expiracao. O log de entrada registra somente tamanho e idade do
ticket, sem valor. Depois do replay, restaurar o rc, fechar e reabrir o app no
fluxo normal antes do teste real, para nao misturar estado de replay e login.

APK `91d6ded02`: cinco cenarios na engine passaram (erro explicito, EOF sem
resposta, fila, fim de sessao e atualizacao). No EOF sem resposta houve um unico
`onConnectionError`, com a janela de conexao destruida; os demais preservaram a
resposta especifica, sem erro de conexao duplicado. O EOF foi testado depois do
erro explicito, exercitando tambem o reset do estado entre tentativas.
O roteiro privado falhou na limpeza antes de iniciar o replay de movimento;
esse trecho nao constitui validacao de movimento deste APK. O roteiro foi
corrigido, rc/config foram restaurados byte a byte e o app foi reaberto no fluxo
normal para uma tentativa manual. O serializador de login continua reproduzindo
exatamente os blocos XTEA/RSA da fixture PC e os quatro campos preauth ativos
conferem com a captura autenticada. A causa do encerramento real segue pendente.

### Outfit com lookType zero

Uma reentrada posterior trouxe outro FullMap: centro (3961,3859,6), 133 criaturas,
incluindo um Kecleon com lookType zero. O leitor pulava a string de extensao
nesse ramo e perdia o alinhamento, gerando erro 71. A funcao DX atual
`0x140797580..0x140797bf3` confirma que os dois U64 pertencem ao ramo de criatura,
mas a string controlada pelo bit 42 fica depois dos dois ramos de lookType.
O helper compartilhado recebe o tipo de outfit original, antes da validacao DAT.

A mesma captura falha sem a correcao no cursor relativo 19411; corrigida, termina
o mapa em 29375 (1746 tiles descritos, 3374 pulados, 2576 itens, 133 criaturas) e
toda a cauda/bootstrap em 60499, exatamente o fim do buffer. As capturas Android
anterior (fim 43636) e PC (fim 45372, 4443 tiles/5318 itens/23 criaturas) mantem
seus limites. Fixtures permanecem privadas.

### Minimap no celular

O modo ampliado do minimapa precisa ter fechamento por toque. O atalho Escape
isolado deixava o usuario sem controle visivel no Android. O botao X fica visivel
apenas nesse modo; ao fechar, o widget retorna ao painel original. Logout e
terminacao do modulo tambem restauram o painel antes de salvar/destruir a UI.
Validacao no aparelho com replay offline: X visivel, toque em (1485,90), retorno
ao cenario com o cliente ainda online. O roteiro abre o minimapa de proposito;
isso nao altera a abertura normal nem deve permanecer no rc ativo.

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

Quando o servidor atualizar o cliente original, confirmar a mensagem de rejeicao
na gravacao real em `files/.otclient/records/`; nao tratar stdout de um `adb cat`
que falhou como arquivo CAM. Comparar o login original bem-sucedido antes de
alterar padding, RSA ou protocolo por tamanho de pacote.

O perfil PKA atualizado em 23/10/2026 usa RSA-1024 com marcador `0xff`, tamanho e
SHA-256 hexadecimal de um bloco XTEA anexado. As credenciais desse bloco usam o
ticket de `session.sessionkey` recebido por HTTPS; o marcador de versao continua
em Lua. `src/client/pkalogin.h` e compartilhado com `tools/pka-login-check.cpp`.
O verificador recebe uma pasta de fixture PRIVADA e compara o ciphertext XTEA e
o plaintext RSA com uma captura original autenticada, sem imprimir os campos.
Nunca incluir essas fixtures/chaves no Git. Uma alteracao somente do marcador
Lua pode usar sync; alteracao do envelope nativo exige APK incremental.

No Windows, apos instalar um binario compativel:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/android-dev/sync-android-modules.ps1 -Diagnostics records -StartApp
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
restritos ao subtipo zero; prelude dos subtipos 1, 3 e 4 com sete bytes fixos
antes do gate opcional, campo extra apenas para 3/4, depois flag, records e string.
A interpretacao anterior de que 1/3 omitiam a cauda era incorreta: no PC esses
subtipos chegam ao prelude por fallthrough. Formatos nao exercitados dependem
de evidencia adicional; compilar nao prova renderizacao no aparelho.

Movimento: os tres bytes U16/U8 no inicio de cada tile sao metadados do Tile,
nao um item ground. O PC armazena os campos e insere a lista real em stack zero.
Um item artificial deslocava todas as referencias de movimento em uma posicao.
A sessao de 23/10/2026 registrou esse desvio e uma cauda de criatura subtipo 1
incompleta no mapa sul (0x67), provocando erro local de protocolo 71.
Com o leitor corrigido, as 29 faixas de mapa da sessao passaram offline, inclusive
o pacote antes rejeitado; FullMap/bootstrap novos e a referencia PC tambem passam.

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

## APK instalado e replay da engine no Android

APK nativo: commit `e69beb46935507c34bd0294cfac944607e4d543e`,
SHA-256 `8aafcf1bf27a4bfdc4ffce6e791f379794b4d9ab7b7d2542f0e58a9f744b85dd`.
Certificado debug SHA-256:
`089676d21a425ef8973d8a32db902bfe7e7b31080439276d585bfd6ee8069c08`.
Depois da migracao inicial, update via `adb install -r` entre os dois APKs com essa
chave concluiu com sucesso e preservou os dados. DAT/SPR restaurados e hashes
conferidos; o cliente confirmou uso dos assets 860 nos caminhos padrao.

A recompilacao com opcoes PCH levou 3min37s. Reavaliacao forcada do mesmo parser,
sem mudar conteudo, teve um hit direto de ccache: Gradle 10s, helper 11.349s.
Isso comprova reuso de cache, nao representa uma mudanca de codigo com cache miss.

A fixture PC preparada (`pka-bootstrap.cam`) foi executada na engine do LG K41S:
FullMap start=65, end=45432, consumed=45367, remaining=0, 32x20.
O jogador ficou online/known=true em (3320,2049,7), tile central com 11 objetos.
Esse teste nao abriu conexao com o servidor e nao valida movimento real.
A fixture contem login+FullMap e termina em 30s; EOF nesse ponto e intencional.
Ela omite a negociacao de extended opcodes, por isso as tentativas de envio dos
modulos 1/201 emitiram avisos locais. Nao atribuir isso a rejeicao do servidor.
O helper foi corrigido para so ocultar CharacterList se a janela existir/estiver visivel.
O hook temporario de inicializacao foi removido depois da captura; o replay passa
a depender de execucao explicita. Renderizacao visual depende da observacao no aparelho.

## Reentrada, minimapa e luz: checkpoint 23/10/2026

APK `1436579ee026425b6790051156d64a7562b5d59d`, SHA-256
`d815097c731aaf60f8177caa57b8e572c227e909bbb4f1a4f2eff0ef6ec3ea89`,
instalado com a mesma chave persistente. A gravacao da reentrada antes rejeitada
com lookType zero passou na engine Android: FullMap start63/end29433,
31124 bytes restantes consumidos pelo bootstrap. Jogador conhecido, camera e
centro em (3961,3859,6). A sessao anterior de 90 mensagens tambem terminou na
posicao esperada (3324,2058,7), sem nova excecao de protocolo.

A primeira captura dessa nova cena ficou preta. Comparacao da MESMA gravacao,
sem alterar parser, assets ou camera, mostrou cenario legivel ao desativar
`setDrawLights`: a iluminacao era responsavel pelo escurecimento nesse teste.
Por pedido do usuario, o perfil local foi ajustado para ambientLight100 e
enableLightsfalse; isso e preferencia local, nao mudanca global de protocolo.
Capturas privadas `outfit-new-map.png`/`outfit-new-map-no-lights.png` preservam
a comparacao. Esse resultado nao substitui o teste de nova conexao real.

O botao X do minimapa ampliado foi validado por toque em replay, retornando
ao jogo. Hooks de reproducao e configuracao temporaria foram restaurados e
conferidos byte a byte antes de iniciar o fluxo normal. O teste real desse APK
continua pendente neste checkpoint; a sessao real anterior de nove minutos
pertence ao APK91d6ded02, nao a este.

Validacao real posterior: usuario confirmou "Entrou, cenario claro, andou e o X
funcionou". FullMap real as18:11:54 concluiu start63/end29462/remaining7765;
snapshot inicial preservou185mensagens recebidas, cenario claro e nenhum marcador
de excecao de protocolo/crash. A CAM desse snapshot cobre17,455s; a confirmacao
posterior do usuario valida o teste solicitado separadamente. Copia final sofreu
timeout ADB; manter a evidencia inicial e o log continuo. Usuario pediu pausa por
creditos; proxima bateria de assets/protocolo fica para a retomada. O EOF remoto
original das16:45 continua sem causa conclusiva, embora novas entradas tenham
sido aceitas e a ultima falha local de FullMap tenha sido corrigida e retestada.

## Cobertura do catalogo e subtipos de liquidos (23/10/2026)

A varredura em `tools/pka-replay/audit_assets.py` percorreu 59034 definicoes
(51897 itens,3998 outfits,2888 efeitos,251 projeteis), com1693400 referencias de
sprite, ate EOF exato do DAT. Decodificou os586208 sprites nao vazios em RGBA,
sem RLE invalido nem referencia acima do limite do SPR. O sprite1 tem offset
zero e e referenciado; camadas vazias sao permitidas, nao substituir por outro
asset. Isso valida estrutura/CPU, nao a renderizacao de todas as animacoes na GPU.

Comparacao de metadados na engine143 percorreu o mesmo catalogo. A primeira
expectativa de teste incluiu a flag chargeable antiga (raw8), gerando36 diferencas.
A verificacao do DX original mostrou que essa flag nao acrescenta contagem no
pacote: corrigir a EXPECTATIVA, sem habilitar uma leitura de carga inexistente.
O reprodutor/prepare agora excluem esse bit dos wire flags.

Encontrada uma diferenca real: `FUN_140799cd0` no DX atualizado testa os flags
5/10/11 (stackable/fluid/splash); o helper0x1407054d0 confirma o indice11. Os tres
casos chamam o leitorU16 0x14082ce40. O OTC PKA consumia U16 apenas em stackable,
deixando recipientes/poças com um byte sobrando. Fixture recebida sintetica de
item869/subtipo0x1234 seguido de inventario sentinela reproduziu opcode falso
0x7800 no byte8 com o leitor antigo. Correcao usa U16 para os tres casos PKA;
os demais perfis mantem a escolha existente por feature.

Leitor corrigido passou721pacotes gerados:51897IDs de item (modos de texto0/1/3),
3998IDs de outfit, ramo invisivel/lookType0 e sentinelas seguintes. Suite dos
helpers passou180casos com opcionais/listas e rejeitou9380prefixos truncados.
Regressoes FullMap preservaram os limites29375(reentrada),43636(Android antigo)
e45372(referenciaPC); bootstrap Android foi consumido ate o fim. Evidencias e
fixtures ficam privadas em android-artifacts/asset-coverage-20261023/.

Ferramentas/restricoes detalhadas em [pka-replay README](../../tools/pka-replay/README.md).
Teste Android do subtipo e do catalogo completo no APK corrigido permanece
pendente neste checkpoint. ADB desconectou apos o teste inicial de metadados;
rc/config foram restaurados byte a byte e app fechado antes da desconexao.
