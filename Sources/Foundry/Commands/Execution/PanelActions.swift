import AppKit
import Foundation
import FoundryDomain
import FoundryServices

/// Actions that only route the panel (or touch panel state) — generic
/// navigation and meta actions, not feature behaviour.

struct OpenQuickAIAction: ResultAction, Equatable {
    let prompt: String

    var icon: String? { "sparkles" }
    var resultSection: ResultSection? { prompt.isEmpty ? nil : .fallback }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        .open(route: .quickAI(initialPrompt: prompt))
    }
}

struct OpenEmojiPickerAction: ResultAction, Equatable {
    var icon: String? { "face.smiling" }
    func perform(_ ctx: ActionContext) async -> CommandOutcome { .open(route: .emojiPicker) }
}

struct OpenFileShelfAction: ResultAction, Equatable {
    var icon: String? { "tray.full" }
    func perform(_ ctx: ActionContext) async -> CommandOutcome { .open(route: .fileShelf) }
}

struct OpenClipboardHistoryAction: ResultAction, Equatable {
    var icon: String? { "doc.on.clipboard" }
    func perform(_ ctx: ActionContext) async -> CommandOutcome { .open(route: .clipboardHistory) }
}

struct OpenSnippetsAction: ResultAction, Equatable {
    var icon: String? { "curlybraces" }
    func perform(_ ctx: ActionContext) async -> CommandOutcome { .open(route: .snippets) }
}

struct EditSnippetAction: ResultAction, Equatable {
    let id: String

    var icon: String? { "pencil" }
    var shortcut: ActionShortcut? { ActionShortcut(key: "e", modifiers: [.command]) }
    var resultSection: ResultSection? { .snippets }
    func perform(_ ctx: ActionContext) async -> CommandOutcome { .open(route: .snippet(id: id, then: .select)) }
}

struct EditQuicklinkAction: ResultAction, Equatable {
    var icon: String? { "pencil" }
    var shortcut: ActionShortcut? { ActionShortcut(key: "e", modifiers: [.command]) }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        ctx.panel.presentSettings(.quicklinks)
        return .stayOpen(message: nil)
    }
}

struct OpenFileConverterAction: ResultAction, Equatable {
    let path: String?

    init(path: String? = nil) { self.path = path }

    var icon: String? { "arrow.triangle.2.circlepath" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        .open(route: .fileConversion(path: path))
    }
}


struct OpenTranslatorAction: ResultAction, Equatable {
    let text: String?
    let language: String?

    init(text: String? = nil, language: String? = nil) {
        self.text = text
        self.language = language
    }

    var icon: String? { "globe" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        .open(route: .translator(text: text, language: language))
    }
}

struct OpenDeveloperToolsAction: ResultAction, Equatable {
    let tool: String?

    init(tool: String? = nil) { self.tool = tool }

    var icon: String? { "hammer" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        .open(route: .developerTools(tool: tool))
    }
}

struct OpenSettingsAction: ResultAction, Equatable {
    var icon: String? { "slider.horizontal.3" }
    var shortcut: ActionShortcut? { ActionShortcut(key: ",", modifiers: [.shift, .command]) }
    func perform(_ ctx: ActionContext) async -> CommandOutcome { .open(route: .settings) }
}

struct OpenCommandSettingsAction: ResultAction, Equatable {
    let link: SettingsDeepLink

    init(_ link: SettingsDeepLink) { self.link = link }

    var icon: String? { "slider.horizontal.3" }
    var shortcut: ActionShortcut? { ActionShortcut(key: ",", modifiers: [.shift, .command]) }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        ctx.panel.presentSettings(link)
        return .stayOpen(message: nil)
    }
}

struct OpenWelcomeGuideAction: ResultAction, Equatable {
    var icon: String? { "sparkles.rectangle.stack" }
    func perform(_ ctx: ActionContext) async -> CommandOutcome { .open(route: .welcomeGuide) }
}

struct OpenMediaDownloadsAction: ResultAction, Equatable {
    var icon: String? { "arrow.down.circle" }
    func perform(_ ctx: ActionContext) async -> CommandOutcome { .open(route: .mediaDownloads) }
}

struct FillQueryAction: ResultAction, Equatable {
    let text: String

    init(_ text: String) { self.text = text }

    var icon: String? { "text.cursor" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        .open(route: .query(text))
    }
}

struct ToggleFavoriteAction: ResultAction, Equatable {
    let commandID: String

    var icon: String? { "star" }
    var shortcut: ActionShortcut? { ActionShortcut(key: "d", modifiers: [.command]) }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        let nowFavorite = ctx.panel.toggleFavorite(commandID)
        return .stayOpen(message: nowFavorite ? "Added to Favorites" : "Removed from Favorites")
    }
}

struct ResetRankingAction: ResultAction, Equatable {
    let commandID: String

    var icon: String? { "arrow.counterclockwise" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        ctx.resetRanking(commandID)
        return ctx.finish(.stayOpen(message: String(localized: "Ranking reset")), feedback: .success(String(localized: "Ranking reset")))
    }
}

struct CelebrateAction: ResultAction, Equatable {
    var icon: String? { "party.popper.fill" }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        ctx.panel.celebrate()
        return ctx.finish(.stayOpen(message: nil), feedback: .success(String(localized: "🎉")))
    }
}

struct QuitAction: ResultAction, Equatable {
    var icon: String? { "power" }
    var style: ActionStyle { .destructive }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        NSApp.terminate(nil)
        return .success(message: String(localized: "Quitting Foundry"))
    }
}

struct LogAction: ResultAction, Equatable {
    let message: String

    init(_ message: String) { self.message = message }

    func perform(_ ctx: ActionContext) async -> CommandOutcome {
        ctx.diagnostics.log(message)
        return .success(message: nil)
    }
}
