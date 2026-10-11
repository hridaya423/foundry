import AppKit
import Foundation
import SwiftUI
import FoundryDomain
import FoundryServices

// Panel lifecycle: open, close, shutdown, and termination.
extension CommandPanelState {
    func resetForOpen() {
        let span = diagnostics.startSpan("panel.resetForOpen")
        defer { diagnostics.endSpan(span) }
        detachActiveAction()
        isPanelOpen = true
        let shouldRestore = lastClosedAt.map { now().timeIntervalSince($0) < settings.popToRootAfterSeconds } ?? false
        session.isSearchLoading = false
        clipboardHistory.start()
        widgetBoard.start()
        if settings.isAgentShelfVisible {
            agents.start()
        } else {
            agents.stopPolling()
        }
        if shouldRestore {
            session.isShowingActions = false
            session.selectedActionID = nil
            if session.query.isEmpty == false {
                session.query = ""
                session.results = []
                session.selectedResultID = nil
            }
            return
        }
        mode = .search
        router.resetTransientFeatures()
        clipboardHistory.reset()
        snippets.reset()
        session.query = ""
        quickAI.resetTransientState()
        session.selectedResultID = nil
        session.isShowingActions = false
        session.selectedActionID = nil
        // Explicit: `query = ""` only re-triggers refreshResults when it
        // actually changes, so without this an open→close→reopen cycle
        // stranded Home on an empty "Loading" state.
        session.refreshHomeResults()
    }

    func panelWillClose() {
        detachActiveAction()
        cancelPrompt()
        isPanelOpen = false
        lastClosedAt = now()
        session.homeRefreshID = UUID()
        session.isSearchLoading = false
        session.isHomeLoading = false
        searchCoordinator.cancel()
        widgetBoard.stop()
        router.resetTransientFeatures()
        clipboardHistory.stop()
        clipboardHistory.reset()
        snippets.reset()
        agents.stopPolling()
        ClipboardImagePreview.releaseCachedImages()
        AIFormattedText.releaseCachedMarkdown()
    }

    func shutdown() {
        isPanelOpen = false
        searchCoordinator.cancel()
        settings.cancelCatalogTask()
        quickAI.shutdown()
        aiSettings.shutdown()
        cancelActiveAction()
        clipboardHistory.stop()
        agents.stop()
        fileShelf.shutdown()
    }

    func prepareForTermination() async {
        await clipboardHistory.shutdown()
        shutdown()
    }
}
