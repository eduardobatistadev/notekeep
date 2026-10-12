# NotepadMac

Editor de texto nativo para macOS inspirado no Notepad++, escrito do zero em
Swift/AppKit. Não contém código do Notepad++.

## Compilar e executar

Requer Xcode (ou Command Line Tools) com Swift 5.10+ e macOS 13+.

```sh
./scripts/build-app.sh          # gera build/NotepadMac.app (universal, assinatura ad-hoc)
open build/NotepadMac.app
swift test                      # testes do núcleo (EditorCore)
```

Para instalar, copie `build/NotepadMac.app` para `/Applications`.

## Funcionalidades

| Notepad++                         | NotepadMac                                                    |
| --------------------------------- | ------------------------------------------------------------- |
| Abas                              | Abas nativas do macOS (⌘T / ⇧⌘{ ⇧⌘})                          |
| Realce de sintaxe                 | 22 linguagens, detectadas pela extensão ou shebang            |
| Localizar/substituir com regex    | ⌘F — regex, maiúsculas, palavra inteira, contar, `$1`, `\n`   |
| Codificação (UTF-8, BOM, ANSI…)   | Detecta e preserva; converter ou reabrir com outra            |
| Conversão de fim de linha         | Detecta e preserva CRLF / LF / CR; converte pelo menu         |
| Duplicar / excluir / mover linha  | ⌘D, ⇧⌘K, ⌥↑, ⌥↓                                               |
| Comentar bloco                    | ⌘/ (linha ou bloco, conforme a linguagem)                     |
| MAIÚSCULAS / minúsculas           | ⇧⌘U / ⌘U                                                      |
| Ordenar linhas, remover espaços   | Menu Editar                                                   |
| Ir para linha                     | ⌘L                                                            |
| Números de linha, quebra de linha | Menu Exibir; zoom com ⌘+ / ⌘- / ⌘0                            |
| Barra de status                   | Tamanho, linhas, Ln/Col, seleção, linguagem, EOL, codificação |
| Snapshot de sessão e backup       | ⌘Q fecha sem perguntar; as abas voltam com o texto não salvo  |

## Sessão (como no Notepad++)

Com **Arquivo ▸ Lembrar abas ao encerrar** ligado (padrão), encerrar o app (⌘Q)
não pede para salvar nada: a lista de abas e o texto não salvo de cada uma
são gravados e, ao abrir de novo, tudo volta como estava — ordem e aba
selecionada, texto não salvo (ainda marcado como alterado), cursor, rolagem,
codificação, fim de linha e linguagem. Um backup periódico a cada 7 s cobre
travamentos e encerramentos forçados. Os arquivos originais só mudam quando
você salva.

O botão vermelho da janela faz o mesmo quando é a última janela aberta, como
o X do Notepad++. Fechar uma aba isolada (⌘W) com alterações continua
perguntando, assim como o botão vermelho quando há outras janelas abertas. Com a opção
desligada, o app volta a perguntar ao encerrar e a sessão gravada é apagada.

Os dados ficam em `~/Library/Application Support/NotepadMac/Session/`
(`session.json` e `backups/`).

## Arquitetura

- `Sources/EditorCore` — lógica pura e testada: codificações, fins de linha,
  índice de linhas, busca, tokenização de sintaxe e operações de linha.
- `Sources/NotepadMac` — app AppKit baseado em `NSDocument`: cada documento
  mantém o texto normalizado em LF e restaura codificação e fim de linha ao
  salvar. As cores de sintaxe são atributos temporários do layout, por isso
  não entram no desfazer nem marcam o documento como alterado.

## Limitações conhecidas

- Arquivos acima de ~4 MB abrem sem realce de sintaxe.
- Arquivos com fins de linha mistos são unificados no estilo predominante ao salvar.
- O realce reprocessa o documento inteiro após cada pausa na digitação.
- A sessão guarda caminhos de arquivo: um arquivo renomeado ou movido fora do
  app não é reencontrado (um arquivo apagado com texto não salvo volta como
  aba alterada, e salvar o recria no mesmo caminho).
- Ainda não implementados: localizar em arquivos, macros, dobra de código,
  edição em múltiplos cursores e plugins.
