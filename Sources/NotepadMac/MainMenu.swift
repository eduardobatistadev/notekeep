import AppKit
import EditorCore

/// Builds the menu bar in code (no nib), following Notepad++'s menu layout
/// with macOS shortcuts.
@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let appName = ProcessInfo.processInfo.processName
        let main = NSMenu()

        main.addItem(submenu(appName, [
            item("Sobre o \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Ocultar \(appName)", #selector(NSApplication.hide(_:)), "h"),
            item("Ocultar outros", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Mostrar todos", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Encerrar \(appName)", #selector(NSApplication.terminate(_:)), "q"),
        ]))

        let recentMenu = NSMenu(title: "Abrir recente")
        recentMenu.addItem(item("Limpar menu", #selector(NSDocumentController.clearRecentDocuments(_:))))
        let recentItem = NSMenuItem(title: "Abrir recente", action: nil, keyEquivalent: "")
        recentItem.submenu = recentMenu
        // NSDocumentController fills the menu that holds "Clear Menu".

        main.addItem(submenu("Arquivo", [
            item("Novo", #selector(NSDocumentController.newDocument(_:)), "n"),
            item("Abrir…", #selector(NSDocumentController.openDocument(_:)), "o"),
            recentItem,
            .separator(),
            item("Fechar", #selector(NSWindow.performClose(_:)), "w"),
            item("Salvar", #selector(NSDocument.save(_:)), "s"),
            item("Salvar como…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift]),
            item("Reverter para o salvo", #selector(NSDocument.revertToSaved(_:))),
            .separator(),
            item("Configurar página…", #selector(NSApplication.runPageLayout(_:)), "p", [.command, .shift]),
            item("Imprimir…", #selector(NSView.printView(_:)), "p"),
        ]))

        main.addItem(submenu("Editar", [
            item("Desfazer", Selector(("undo:")), "z"),
            item("Refazer", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Recortar", #selector(NSText.cut(_:)), "x"),
            item("Copiar", #selector(NSText.copy(_:)), "c"),
            item("Colar", #selector(NSText.paste(_:)), "v"),
            item("Selecionar tudo", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Duplicar linha", #selector(EditorTextView.duplicateLine(_:)), "d"),
            item("Excluir linha", #selector(EditorTextView.deleteLine(_:)), "k", [.command, .shift]),
            item("Mover linha para cima", #selector(EditorTextView.moveLineUp(_:)), arrow(NSUpArrowFunctionKey), [.option]),
            item("Mover linha para baixo", #selector(EditorTextView.moveLineDown(_:)), arrow(NSDownArrowFunctionKey), [.option]),
            item("Comentar/descomentar", #selector(EditorTextView.toggleComment(_:)), "/"),
            .separator(),
            item("MAIÚSCULAS", #selector(NSResponder.uppercaseWord(_:)), "u", [.command, .shift]),
            item("minúsculas", #selector(NSResponder.lowercaseWord(_:)), "u"),
            item("Remover espaços no fim das linhas", #selector(EditorTextView.trimTrailingWhitespace(_:))),
            item("Ordenar linhas (A→Z)", #selector(EditorTextView.sortLinesAscending(_:))),
            item("Ordenar linhas (Z→A)", #selector(EditorTextView.sortLinesDescending(_:))),
        ]))

        main.addItem(submenu("Pesquisar", [
            item("Localizar e substituir…", #selector(AppDelegate.showFindPanel(_:)), "f"),
            item("Localizar próximo", #selector(AppDelegate.findNextMatch(_:)), "g"),
            item("Localizar anterior", #selector(AppDelegate.findPreviousMatch(_:)), "g", [.command, .shift]),
            item("Usar seleção para localizar", #selector(EditorWindowController.useSelectionForFind(_:)), "e"),
            .separator(),
            item("Ir para a linha…", #selector(EditorWindowController.goToLine(_:)), "l"),
        ]))

        main.addItem(submenu("Exibir", [
            item("Quebra automática de linha", #selector(EditorWindowController.toggleWordWrap(_:)), "w", [.command, .option]),
            item("Números de linha", #selector(EditorWindowController.toggleLineNumbers(_:))),
            .separator(),
            item("Aumentar fonte", #selector(EditorWindowController.makeTextLarger(_:)), "+"),
            item("Diminuir fonte", #selector(EditorWindowController.makeTextSmaller(_:)), "-"),
            item("Tamanho padrão", #selector(EditorWindowController.makeTextStandardSize(_:)), "0"),
            .separator(),
            item("Entrar em tela cheia", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ]))

        let encodingItems = FileEncoding.allCases.enumerated().map { index, encoding in
            item(encoding.displayName, #selector(EditorWindowController.setEncoding(_:)), tag: index)
        }
        let reopenItems = FileEncoding.allCases.enumerated().map { index, encoding in
            item(encoding.displayName, #selector(EditorWindowController.reopenWithEncoding(_:)), tag: index)
        }
        let lineEndingItems = LineEnding.allCases.enumerated().map { index, ending in
            item(ending.displayName, #selector(EditorWindowController.setLineEnding(_:)), tag: index)
        }
        main.addItem(submenu("Codificação", [header("Salvar como")] + encodingItems + [
            .separator(),
            submenu("Reabrir com codificação", reopenItems),
            .separator(),
            header("Fim de linha"),
        ] + lineEndingItems))

        let languageItems = Language.allCases.enumerated().map { index, language in
            item(language.displayName, #selector(EditorWindowController.setLanguage(_:)), tag: index)
        }
        main.addItem(submenu("Linguagem", languageItems))

        let windowMenu = submenu("Janela", [
            item("Minimizar", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Mostrar aba anterior", #selector(NSWindow.selectPreviousTab(_:)), "{", [.command, .shift]),
            item("Mostrar próxima aba", #selector(NSWindow.selectNextTab(_:)), "}", [.command, .shift]),
            .separator(),
            item("Trazer tudo para a frente", #selector(NSApplication.arrangeInFront(_:))),
        ])
        main.addItem(windowMenu)
        NSApp.windowsMenu = windowMenu.submenu

        let helpMenu = submenu("Ajuda", [])
        main.addItem(helpMenu)
        NSApp.helpMenu = helpMenu.submenu

        return main
    }

    private static func arrow(_ key: Int) -> String {
        String(Character(UnicodeScalar(UInt16(key))!))
    }

    private static func item(
        _ title: String,
        _ action: Selector?,
        _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = [.command],
        tag: Int = 0
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.tag = tag
        return item
    }

    private static func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) {
            return NSMenuItem.sectionHeader(title: title)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
