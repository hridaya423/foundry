import Foundation
import SwiftUI
import FoundryServices

@MainActor
final class AISettingsState: ObservableObject {
    @Published var isOllamaEnabled: Bool
    @Published var ollamaHost: String
    @Published var ollamaModel: String
    @Published var ollamaHostError: String?
    @Published var ollamaModelError: String?
    @Published var aiProfiles: [AIProviderProfile]
    @Published var defaultAIProfileID: UUID?
    @Published var fallbackAIProfileIDs: [UUID]
    @Published var selectedAIProfileID: UUID?
    @Published var aiCredentialInput = ""
    @Published var aiProfileStatus: String?
    @Published var aiProfileTestingID: UUID?
    @Published var aiAvailableModels: [AIModel] = []
    @Published var aiModelsLoading = false
    @Published var codexLoginState: CodexLoginState
    @Published var codexDeviceAuthorization: OpenAIDeviceAuthorization?
    @Published var acceptedCodexPrivateBackendWarning: Bool
    @Published var settingsPersistenceError: String?

    private let configService: ConfigService
    private let diagnostics: DiagnosticsService
    private let aiCredentialStore: AICredentialStore
    private let codexOAuthService: OpenAICodexOAuthService
    private var aiProfileTestTask: Task<Void, Never>?
    private var aiModelTask: Task<Void, Never>?
    private var codexOAuthTask: Task<Void, Never>?

    init(
        config: ConfigService,
        diagnostics: DiagnosticsService,
        credentialStore: any AICredentialStore = KeychainAICredentialStore(),
        codexOAuthService: OpenAICodexOAuthService = .shared
    ) {
        self.configService = config
        self.diagnostics = diagnostics
        self.aiCredentialStore = credentialStore
        self.codexOAuthService = codexOAuthService
        self.isOllamaEnabled = config.current.ai.isOllamaEnabled
        self.ollamaHost = config.current.ai.ollamaHost
        self.ollamaModel = config.current.ai.ollamaModel
        self.ollamaHostError = nil
        self.ollamaModelError = nil
        self.aiProfiles = config.current.ai.profiles
        self.defaultAIProfileID = config.current.ai.defaultProfileID
        self.fallbackAIProfileIDs = config.current.ai.fallbackProfileIDs
        self.selectedAIProfileID = config.current.ai.defaultProfileID ?? config.current.ai.profiles.first?.id
        self.codexLoginState = .disconnected
        self.codexDeviceAuthorization = nil
        self.acceptedCodexPrivateBackendWarning = config.current.ai.acceptedCodexPrivateBackendWarning
        self.settingsPersistenceError = nil
    }

    var selectedAIProfile: AIProviderProfile? {
        guard let selectedAIProfileID else { return nil }
        return aiProfiles.first { $0.id == selectedAIProfileID }
    }

    func setOllamaEnabled(_ isEnabled: Bool) {
        let previous = isOllamaEnabled
        isOllamaEnabled = isEnabled
        var ai = configService.current.ai
        ai.isOllamaEnabled = isEnabled
        do {
            try configService.updateAIConfig(ai)
            settingsPersistenceError = nil
        } catch {
            isOllamaEnabled = previous
            showSettingsPersistenceError(error)
        }
    }

    func setOllamaHost(_ host: String) {
        let previous = ollamaHost
        ollamaHost = host
        guard let value = Self.validatedOllamaHost(host) else {
            ollamaHostError = "Enter an absolute http or https URL."
            return
        }
        ollamaHostError = nil
        var ai = configService.current.ai
        ai.ollamaHost = value
        do {
            try configService.updateAIConfig(ai)
            ollamaHost = value
            settingsPersistenceError = nil
        } catch {
            ollamaHost = previous
            showSettingsPersistenceError(error)
        }
    }

    func setOllamaModel(_ model: String) {
        let previous = ollamaModel
        ollamaModel = model
        let value = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else {
            ollamaModelError = "Enter an Ollama model name."
            return
        }
        ollamaModelError = nil
        var ai = configService.current.ai
        ai.ollamaModel = value
        do {
            try configService.updateAIConfig(ai)
            ollamaModel = value
            settingsPersistenceError = nil
        } catch {
            ollamaModel = previous
            showSettingsPersistenceError(error)
        }
    }

    func selectAIProfile(_ id: UUID) {
        selectedAIProfileID = id
        aiCredentialInput = ""
        aiProfileStatus = nil
        refreshAIModels()
    }

    func addAIProfile(presetID: String) {
        guard let preset = AIProviderPreset.find(presetID) else { return }
        let profile = preset.makeProfile()
        aiProfiles.append(profile)
        selectedAIProfileID = profile.id
        aiCredentialInput = ""
        aiProfileStatus = nil
        refreshAIModels()
        do {
            try configService.updateAIProfile(profile)
            settingsPersistenceError = nil
        } catch {
            aiProfiles.removeAll { $0.id == profile.id }
            showSettingsPersistenceError(error)
        }
    }

    func removeSelectedAIProfile() {
        guard let profile = selectedAIProfile, profile.kind != .appleFoundationModels else { return }
        let previousProfiles = aiProfiles
        let previousDefault = defaultAIProfileID
        let previousFallbacks = fallbackAIProfileIDs
        aiProfiles.removeAll { $0.id == profile.id }
        fallbackAIProfileIDs.removeAll { $0 == profile.id }
        if defaultAIProfileID == profile.id { defaultAIProfileID = aiProfiles.first(where: { $0.enabled })?.id }
        selectedAIProfileID = defaultAIProfileID ?? aiProfiles.first?.id
        aiCredentialInput = ""
        do {
            try configService.removeAIProfile(id: profile.id)
            try aiCredentialStore.delete(for: profile.id)
            settingsPersistenceError = nil
        } catch {
            aiProfiles = previousProfiles
            defaultAIProfileID = previousDefault
            fallbackAIProfileIDs = previousFallbacks
            selectedAIProfileID = profile.id
            showSettingsPersistenceError(error)
        }
    }

    func setAIProfileEnabled(_ enabled: Bool, id: UUID) {
        updateAIProfile(id: id) { profile in
            profile.enabled = enabled
        }
    }

    func setAIProfileName(_ name: String, id: UUID) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else { return }
        updateAIProfile(id: id) { profile in
            profile.name = value
        }
    }

    func setAIProfileEndpoint(_ endpoint: String, id: UUID) {
        guard let value = AIEndpointPolicy.normalized(endpoint) else {
            aiProfileStatus = "Enter an absolute HTTP or HTTPS endpoint without embedded credentials."
            return
        }
        updateAIProfile(id: id) { profile in
            profile.endpoint = value
        }
        if AIEndpointPolicy.requiresPlainHTTPWarning(value) {
            aiProfileStatus = "This endpoint uses unencrypted HTTP. Use it only on a network you trust."
        } else {
            aiProfileStatus = nil
        }
    }

    func setAIProfileModel(_ model: String, id: UUID) {
        let value = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else {
            aiProfileStatus = "Enter a model name."
            return
        }
        updateAIProfile(id: id) { profile in
            profile.model = value
        }
        aiProfileStatus = nil
    }

    func setDefaultAIProfile(_ id: UUID) {
        let previous = defaultAIProfileID
        defaultAIProfileID = id
        do {
            try configService.setDefaultAIProfile(id: id)
            settingsPersistenceError = nil
        } catch {
            defaultAIProfileID = previous
            showSettingsPersistenceError(error)
        }
    }

    func setAIFallback(_ enabled: Bool, id: UUID) {
        let previous = fallbackAIProfileIDs
        if enabled {
            fallbackAIProfileIDs.append(contentsOf: fallbackAIProfileIDs.contains(id) ? [] : [id])
        } else {
            fallbackAIProfileIDs.removeAll { $0 == id }
        }
        do {
            try configService.setAIFallbackProfiles(fallbackAIProfileIDs)
            settingsPersistenceError = nil
        } catch {
            fallbackAIProfileIDs = previous
            showSettingsPersistenceError(error)
        }
    }

    func setAIProfileAPIKey(_ value: String, id: UUID) {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if key.isEmpty {
                try aiCredentialStore.delete(for: id)
                aiProfileStatus = "Credential removed."
            } else {
                try aiCredentialStore.save(.apiKey(key), for: id)
                aiProfileStatus = "Credential stored in Keychain."
            }
            aiCredentialInput = ""
        } catch {
            aiProfileStatus = "Could not update the Keychain credential."
            diagnostics.log("AI credential update failed: \(error.localizedDescription)")
        }
    }

    func setCodexPrivateBackendWarningAccepted(_ accepted: Bool) {
        let previous = acceptedCodexPrivateBackendWarning
        acceptedCodexPrivateBackendWarning = accepted
        var ai = configService.current.ai
        ai.acceptedCodexPrivateBackendWarning = accepted
        do {
            try configService.updateAIConfig(ai)
            settingsPersistenceError = nil
        } catch {
            acceptedCodexPrivateBackendWarning = previous
            showSettingsPersistenceError(error)
        }
    }

    func loginCodexBrowser() {
        guard acceptedCodexPrivateBackendWarning, let profile = selectedAIProfile, profile.kind == .openAISubscription else {
            aiProfileStatus = "Review and accept the private Codex backend warning before signing in."
            return
        }
        codexOAuthTask?.cancel()
        codexDeviceAuthorization = nil
        persistCodexLoginMethod(.browser)
        codexLoginState = .waitingForBrowser
        aiProfileStatus = "Complete ChatGPT sign-in in your browser."
        codexOAuthTask = Task { [weak self] in
            do {
                _ = try await self?.codexOAuthService.browserLogin(profileID: profile.id)
                guard Task.isCancelled == false else { return }
                self?.codexLoginState = .connected
                self?.aiProfileStatus = "ChatGPT subscription connected."
                self?.updateAIProfile(id: profile.id) { $0.enabled = true }
            } catch {
                guard Task.isCancelled == false else { return }
                self?.codexLoginState = .failed(error.localizedDescription)
                self?.aiProfileStatus = error.localizedDescription
            }
        }
    }

    func requestCodexDeviceLogin() {
        guard acceptedCodexPrivateBackendWarning, selectedAIProfile?.kind == .openAISubscription else {
            aiProfileStatus = "Review and accept the private Codex backend warning before signing in."
            return
        }
        codexOAuthTask?.cancel()
        persistCodexLoginMethod(.device)
        codexLoginState = .starting
        aiProfileStatus = "Requesting a device code..."
        codexOAuthTask = Task { [weak self] in
            do {
                let authorization = try await self?.codexOAuthService.requestDeviceAuthorization()
                guard let authorization, Task.isCancelled == false else { return }
                self?.codexDeviceAuthorization = authorization
                self?.codexLoginState = .waitingForDeviceApproval
                self?.aiProfileStatus = "Open \(authorization.verificationURL) and enter \(authorization.userCode)."
            } catch {
                guard Task.isCancelled == false else { return }
                self?.codexLoginState = .failed(error.localizedDescription)
                self?.aiProfileStatus = error.localizedDescription
            }
        }
    }

    func completeCodexDeviceLogin() {
        guard let authorization = codexDeviceAuthorization, let profile = selectedAIProfile, profile.kind == .openAISubscription else { return }
        codexLoginState = .exchangingCode
        aiProfileStatus = "Waiting for ChatGPT device approval..."
        codexOAuthTask?.cancel()
        codexOAuthTask = Task { [weak self] in
            do {
                _ = try await self?.codexOAuthService.completeDeviceLogin(authorization, profileID: profile.id)
                guard Task.isCancelled == false else { return }
                self?.codexDeviceAuthorization = nil
                self?.codexLoginState = .connected
                self?.aiProfileStatus = "ChatGPT subscription connected."
                self?.updateAIProfile(id: profile.id) { $0.enabled = true }
            } catch {
                guard Task.isCancelled == false else { return }
                self?.codexLoginState = .failed(error.localizedDescription)
                self?.aiProfileStatus = error.localizedDescription
            }
        }
    }

    func cancelCodexLogin() {
        codexOAuthTask?.cancel()
        codexOAuthTask = nil
        Task { await codexOAuthService.cancelCurrentLogin() }
        codexDeviceAuthorization = nil
        codexLoginState = .cancelled
        aiProfileStatus = "ChatGPT login cancelled."
    }

    func logoutCodex() {
        guard let profile = selectedAIProfile, profile.kind == .openAISubscription else { return }
        Task { [weak self] in
            do {
                try await self?.codexOAuthService.signOut(profileID: profile.id)
                self?.codexLoginState = .disconnected
                self?.aiProfileStatus = "ChatGPT subscription disconnected."
                self?.updateAIProfile(id: profile.id) { $0.enabled = false }
            } catch {
                self?.aiProfileStatus = "Could not remove the ChatGPT credential."
            }
        }
    }

    func aiProfileHasCredential(_ profile: AIProviderProfile) -> Bool {
        if profile.authentication == .oauth {
            do {
                guard let credential = try aiCredentialStore.credential(for: profile.id), case let .oauth(value) = credential else { return false }
                return value.isUsable
            } catch { return false }
        }
        guard profile.authentication == .apiKey || profile.authentication == .optionalAPIKey else { return profile.authentication == .none }
        do {
            return try aiCredentialStore.credential(for: profile.id) != nil
        } catch {
            return false
        }
    }

    func testSelectedAIProfile() {
        guard let profile = selectedAIProfile else { return }
        aiProfileTestTask?.cancel()
        aiProfileTestingID = profile.id
        aiProfileStatus = "Testing connection..."
        aiProfileTestTask = Task { [weak self] in
            let result = await AITransportRouter.test(profile: profile)
            guard Task.isCancelled == false else { return }
            await MainActor.run {
                guard let self else { return }
                self.aiProfileTestingID = nil
                self.aiProfileStatus = result.message
            }
        }
    }

    func refreshAIModels() {
        guard let profile = selectedAIProfile, profile.capabilities.modelDiscovery else {
            aiAvailableModels = []
            return
        }
        aiModelTask?.cancel()
        aiModelsLoading = true
        aiModelTask = Task { [weak self] in
            let models = await AITransportRouter.models(profile: profile)
            guard Task.isCancelled == false else { return }
            await MainActor.run {
                guard let self else { return }
                self.aiAvailableModels = models
                self.aiModelsLoading = false
                if models.isEmpty == false {
                    self.aiProfileStatus = "Found \(models.count) model\(models.count == 1 ? "" : "s")."
                }
            }
        }
    }

    func shutdown() {
        aiProfileTestTask?.cancel()
        aiProfileTestTask = nil
        aiModelTask?.cancel()
        aiModelTask = nil
        codexOAuthTask?.cancel()
        codexOAuthTask = nil
        Task { await codexOAuthService.cancelCurrentLogin() }
    }

    static func validatedOllamaHost(_ host: String) -> String? {
        let value = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return value
    }

    private func persistCodexLoginMethod(_ method: OpenAICodexLoginMethod) {
        var ai = configService.current.ai
        ai.codexLoginMethod = method
        try? configService.updateAIConfig(ai)
    }

    private func updateAIProfile(id: UUID, change: (inout AIProviderProfile) -> Void) {
        guard let index = aiProfiles.firstIndex(where: { $0.id == id }) else { return }
        let previous = aiProfiles[index]
        var profile = previous
        change(&profile)
        aiProfiles[index] = profile
        do {
            try configService.updateAIProfile(profile)
            settingsPersistenceError = nil
        } catch {
            aiProfiles[index] = previous
            showSettingsPersistenceError(error)
        }
    }

    private func showSettingsPersistenceError(_ error: Error) {
        settingsPersistenceError = "Preferences could not be saved. Your previous settings were kept."
        diagnostics.log("Settings persistence failed: \(error.localizedDescription)")
    }
}
