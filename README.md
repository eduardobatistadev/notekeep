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
- Ainda não implementados: localizar em arquivos, macros, dobra de código,
  edição em múltiplos cursores, plugins e restauração de sessão com textos não salvos.
