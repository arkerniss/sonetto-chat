import Foundation
import Combine

struct APIConnectionConfiguration {
    let baseURL: URL
    let apiKey: String
}

struct ChatConfiguration {
    let baseURL: URL
    let apiKey: String
    let model: String
    let systemPrompt: String
    let temperature: Double?
    let topP: Double?
    let maxTokens: Int?
    let stream: Bool

    init(
        baseURL: URL,
        apiKey: String,
        model: String,
        systemPrompt: String,
        temperature: Double?,
        topP: Double? = nil,
        maxTokens: Int? = nil,
        stream: Bool = true
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.stream = stream
    }
}

/// A single named provider profile. The API key itself is NOT stored here — it
/// lives in the keychain keyed by `id` — so this struct stays safe to persist
/// as plain JSON in UserDefaults.
struct ProviderProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var baseURLString: String
    var model: String
    var selectedModels: [String]
    var systemPrompt: String
    var temperature: Double

    init(
        id: UUID = UUID(),
        name: String,
        baseURLString: String = "https://api.openai.com/v1",
        model: String = "gpt-4o-mini",
        selectedModels: [String] = [],
        systemPrompt: String = "You are a helpful assistant.",
        temperature: Double = 0.7
    ) {
        self.id = id
        self.name = name
        self.baseURLString = baseURLString
        self.model = model
        self.selectedModels = selectedModels
        self.systemPrompt = systemPrompt
        self.temperature = temperature
    }

    /// Keychain account used to store this provider's API key.
    var keychainAccount: String {
        "provider.\(id.uuidString)"
    }
}

/// User-selectable color scheme. `system` defers to the device setting.
enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon.stars"
        }
    }
}

enum SettingsError: LocalizedError {
    case invalidBaseURL
    case missingAPIKey
    case missingModel

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "接口地址无效"
        case .missingAPIKey:
            return "请先填写 API Key"
        case .missingModel:
            return "请先填写模型名称"
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    /// All configured providers. Never empty — a default is created on first run.
    @Published private(set) var providers: [ProviderProfile]
    /// ID of the provider currently used for chat.
    @Published var activeProviderID: UUID

    /// Preferred color scheme for the whole app.
    @Published var appearance: AppearanceMode {
        didSet {
            guard appearance != oldValue else { return }
            defaults.set(appearance.rawValue, forKey: Self.appearanceKey)
        }
    }

    /// In-memory cache of each provider's API key (mirrored to the keychain).
    private var apiKeys: [UUID: String]

    private static let providersKey = "providerProfiles"
    private static let activeProviderKey = "activeProviderID"
    private static let appearanceKey = "appearanceMode"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let loaded = Self.loadProviders(from: defaults)
        providers = loaded.providers
        activeProviderID = loaded.activeID
        appearance = (defaults.string(forKey: Self.appearanceKey)).flatMap { AppearanceMode(rawValue: $0) } ?? .system

        var keys: [UUID: String] = [:]
        for provider in loaded.providers {
            keys[provider.id] = KeychainStore.readAPIKey(account: provider.keychainAccount) ?? ""
        }
        apiKeys = keys

        if loaded.didMigrate {
            persist()
        }
    }

    // MARK: - Active provider

    var activeProvider: ProviderProfile {
        providers.first(where: { $0.id == activeProviderID }) ?? providers[0]
    }

    private var activeIndex: Int {
        providers.firstIndex(where: { $0.id == activeProviderID }) ?? 0
    }

    /// Forwarding accessors so existing call sites keep operating on the active
    /// provider without knowing about the multi-provider model.
    var baseURLString: String {
        get { activeProvider.baseURLString }
        set { mutateActive { $0.baseURLString = newValue } }
    }

    var apiKey: String {
        get { apiKeys[activeProviderID] ?? "" }
        set { apiKeys[activeProviderID] = newValue }
    }

    var model: String {
        get { activeProvider.model }
        set { mutateActive { $0.model = newValue } }
    }

    var selectedModels: [String] {
        get { activeProvider.selectedModels }
        set { mutateActive { $0.selectedModels = newValue } }
    }

    var systemPrompt: String {
        get { activeProvider.systemPrompt }
        set { mutateActive { $0.systemPrompt = newValue } }
    }

    var temperature: Double {
        get { activeProvider.temperature }
        set { mutateActive { $0.temperature = newValue } }
    }

    private func mutateActive(_ transform: (inout ProviderProfile) -> Void) {
        objectWillChange.send()
        var provider = providers[activeIndex]
        transform(&provider)
        providers[activeIndex] = provider
    }

    // MARK: - Provider management

    func setActiveProvider(_ id: UUID) {
        guard providers.contains(where: { $0.id == id }) else {
            return
        }
        activeProviderID = id
        defaults.set(id.uuidString, forKey: Self.activeProviderKey)
    }

    @discardableResult
    func addProvider(name: String? = nil) -> ProviderProfile {
        let resolvedName = (name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? defaultProviderName()
        let provider = ProviderProfile(name: resolvedName)
        providers.append(provider)
        apiKeys[provider.id] = ""
        persist()
        return provider
    }

    func deleteProvider(_ id: UUID) {
        guard providers.count > 1, let index = providers.firstIndex(where: { $0.id == id }) else {
            return
        }

        let removed = providers.remove(at: index)
        apiKeys[removed.id] = nil
        KeychainStore.deleteAPIKey(account: removed.keychainAccount)

        if activeProviderID == removed.id {
            activeProviderID = providers[min(index, providers.count - 1)].id
        }
        persist()
    }

    func provider(withID id: UUID) -> ProviderProfile? {
        providers.first(where: { $0.id == id })
    }

    func apiKey(forID id: UUID) -> String {
        apiKeys[id] ?? ""
    }

    /// Persist an edited provider draft (used by the provider editor).
    func updateProvider(_ provider: ProviderProfile, apiKey: String) {
        guard let index = providers.firstIndex(where: { $0.id == provider.id }) else {
            return
        }
        providers[index] = provider
        apiKeys[provider.id] = apiKey
        persist()
        KeychainStore.saveAPIKey(
            apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            account: provider.keychainAccount
        )
    }

    private func defaultProviderName() -> String {
        var index = providers.count + 1
        var candidate = "供应商 \(index)"
        let existingNames = Set(providers.map(\.name))
        while existingNames.contains(candidate) {
            index += 1
            candidate = "供应商 \(index)"
        }
        return candidate
    }

    // MARK: - Persistence

    /// 备份恢复:整体替换(rikkahub 同款语义)。旧供应商的 keychain 条目先清掉,
    /// 避免留下孤儿 key。
    func restore(
        providers newProviders: [ProviderProfile],
        apiKeys newKeys: [UUID: String],
        activeProviderID newActiveID: UUID,
        appearance newAppearance: AppearanceMode
    ) {
        guard !newProviders.isEmpty else {
            return
        }

        for provider in providers where newKeys[provider.id] == nil {
            KeychainStore.deleteAPIKey(account: provider.keychainAccount)
        }

        providers = newProviders
        apiKeys = newKeys
        activeProviderID = newProviders.contains(where: { $0.id == newActiveID })
            ? newActiveID
            : newProviders[0].id
        appearance = newAppearance

        persist()
        for provider in newProviders {
            KeychainStore.saveAPIKey(
                (newKeys[provider.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                account: provider.keychainAccount
            )
        }
    }

    func save() {
        // Normalize the active provider's model list, then persist everything.
        let normalizedModel = activeProvider.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSelectedModels = Self.normalizedModelList(activeProvider.selectedModels, ensuring: normalizedModel)
        mutateActive {
            $0.model = normalizedModel
            $0.selectedModels = normalizedSelectedModels
            $0.baseURLString = $0.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        persist()

        for provider in providers {
            KeychainStore.saveAPIKey(
                (apiKeys[provider.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                account: provider.keychainAccount
            )
        }
    }

    private func persist() {
        if let encoded = try? JSONEncoder().encode(providers) {
            defaults.set(encoded, forKey: Self.providersKey)
        }
        defaults.set(activeProviderID.uuidString, forKey: Self.activeProviderKey)
    }

    private static func loadProviders(
        from defaults: UserDefaults
    ) -> (providers: [ProviderProfile], activeID: UUID, didMigrate: Bool) {
        if let data = defaults.data(forKey: providersKey),
           let decoded = try? JSONDecoder().decode([ProviderProfile].self, from: data),
           !decoded.isEmpty {
            let activeID: UUID = {
                if let raw = defaults.string(forKey: activeProviderKey),
                   let parsed = UUID(uuidString: raw),
                   decoded.contains(where: { $0.id == parsed }) {
                    return parsed
                }
                return decoded[0].id
            }()
            return (decoded, activeID, false)
        }

        // Migrate from the legacy single-provider layout, or seed a default.
        let migrated = migrateLegacyProvider(from: defaults)
        return (migrated, migrated[0].id, true)
    }

    /// Build a single provider from the old flat UserDefaults keys (and the
    /// legacy keychain account), copying the API key under the new account.
    private static func migrateLegacyProvider(from defaults: UserDefaults) -> [ProviderProfile] {
        let savedModel = defaults.string(forKey: "model") ?? "gpt-4o-mini"
        let provider = ProviderProfile(
            name: "默认供应商",
            baseURLString: defaults.string(forKey: "baseURLString") ?? "https://api.openai.com/v1",
            model: savedModel,
            selectedModels: normalizedModelList(
                defaults.stringArray(forKey: "selectedModels") ?? [],
                ensuring: savedModel
            ),
            systemPrompt: defaults.string(forKey: "systemPrompt") ?? "You are a helpful assistant.",
            temperature: defaults.object(forKey: "temperature") as? Double ?? 0.7
        )

        if let legacyKey = KeychainStore.readAPIKey(), !legacyKey.isEmpty {
            KeychainStore.saveAPIKey(legacyKey, account: provider.keychainAccount)
        }

        return [provider]
    }

    // MARK: - Configuration builders

    func makeConfiguration() throws -> ChatConfiguration {
        try makeConfiguration(
            baseURLString: baseURLString,
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            temperature: temperature
        )
    }

    func makeConfiguration(
        baseURLString: String,
        apiKey: String,
        model: String,
        systemPrompt: String,
        temperature: Double?,
        topP: Double? = nil,
        maxTokens: Int? = nil,
        stream: Bool = true
    ) throws -> ChatConfiguration {
        let connection = try makeConnectionConfiguration(
            baseURLString: baseURLString,
            apiKey: apiKey
        )
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedModel.isEmpty else {
            throw SettingsError.missingModel
        }

        return ChatConfiguration(
            baseURL: connection.baseURL,
            apiKey: connection.apiKey,
            model: normalizedModel,
            systemPrompt: systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            temperature: temperature,
            topP: topP,
            maxTokens: maxTokens,
            stream: stream
        )
    }

    func makeConnectionConfiguration() throws -> APIConnectionConfiguration {
        try makeConnectionConfiguration(
            baseURLString: baseURLString,
            apiKey: apiKey
        )
    }

    func makeConnectionConfiguration(
        baseURLString: String,
        apiKey: String
    ) throws -> APIConnectionConfiguration {
        let normalizedBaseURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let baseURL = URL(string: normalizedBaseURL),
              let scheme = baseURL.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              baseURL.host != nil else {
            throw SettingsError.invalidBaseURL
        }

        guard !normalizedKey.isEmpty else {
            throw SettingsError.missingAPIKey
        }

        return APIConnectionConfiguration(
            baseURL: baseURL,
            apiKey: normalizedKey
        )
    }

    nonisolated static func normalizedModelList(_ models: [String], ensuring primaryModel: String? = nil) -> [String] {
        var normalizedModels: [String] = []

        func append(_ rawModel: String) {
            let normalizedModel = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedModel.isEmpty, !normalizedModels.contains(normalizedModel) else {
                return
            }

            normalizedModels.append(normalizedModel)
        }

        if let primaryModel {
            append(primaryModel)
        }

        models.forEach(append)
        return normalizedModels
    }
}
