import SwiftUI
import PineappleCore

@MainActor
struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var apiKey = ""
    @State private var keyExists = false
    @State private var keyMessage = ""
    @State private var settingsError: String?
    @State private var fastModel = ""
    @State private var deepModel = ""
    private var settings: UserSettings { store.snapshot.settings }
    var body: some View {
        Form {
            Section("DeepSeek") {
                SecureField(keyExists ? "已保存，输入新 Key 可替换" : "填写 API Key", text: $apiKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                HStack {
                    Button("保存 API Key") {
                        do { try KeychainService.save(apiKey); keyExists = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            apiKey = ""; keyMessage = keyExists ? "已安全保存到本机钥匙串" : "已删除 API Key" }
                        catch { settingsError = error.localizedDescription }
                    }.disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                    if keyExists {
                        Button("删除 Key", role: .destructive) {
                            do { try KeychainService.remove(); keyExists = false; keyMessage = "已删除 API Key" }
                            catch { settingsError = error.localizedDescription }
                        }
                    }
                }
                if !keyMessage.isEmpty { Text(keyMessage).font(.caption).foregroundStyle(.secondary) }
                Picker("AI 默认模式", selection: setting(\.aiMode)) {
                    ForEach(AIMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                Text("自动模式根据问题选择速度或深度。导入词书、困难题与错误诊断始终使用深度模式。API Key 不进入备份。")
                    .font(.footnote).foregroundStyle(.secondary)
                DisclosureGroup("模型配置") {
                    TextField("快速模型", text: $fastModel).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("深度模型", text: $deepModel).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("保存模型配置") {
                        store.updateSettings { $0.fastModel = fastModel.trimmingCharacters(in: .whitespacesAndNewlines)
                            $0.deepModel = deepModel.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }.disabled(fastModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || deepModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("接口固定连接 DeepSeek 官方 HTTPS 服务。模型可用性以你的账户为准。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("英式发音") {
                Picker("默认声音", selection: setting(\.voiceGender)) {
                    ForEach(VoiceGender.allCases) { gender in Text(gender.title).tag(gender) }
                }
                Text(store.speech.description(gender: settings.voiceGender)).font(.caption).foregroundStyle(.secondary)
                Button { store.speech.speak("A little practice, every day.", gender: settings.voiceGender)
                    if let message = store.speech.errorMessage { settingsError = message; store.speech.errorMessage = nil }
                } label: { Label("试听英式发音", systemImage: "speaker.wave.2") }
                Text("只使用 en-GB 语音。设备没有指定性别的声音时，会选择可用的英国英语声音。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("学习与复习") {
                Picker("主词书", selection: setting(\.mainBookID)) {
                    Text("暂不选择").tag(nil as UUID?)
                    ForEach(store.snapshot.books) { book in Text(book.name).tag(Optional(book.id)) }
                }
                Stepper("每日新词：\(settings.dailyNewGoal)", value: setting(\.dailyNewGoal), in: 1...200)
                Toggle("困难模式", isOn: setting(\.hardMode))
                Stepper(settings.mistakeRemovalStreak == 0 ? "错题自动移除：关闭" : "错题连续正确 \(settings.mistakeRemovalStreak) 次后移出",
                        value: setting(\.mistakeRemovalStreak), in: 0...20)
                Stepper("累计错误 \(settings.confusingWrongThreshold) 次标记易错", value: setting(\.confusingWrongThreshold), in: 1...100)
                Stepper("无操作 \(settings.idleTimeoutSeconds) 秒暂停计时", value: setting(\.idleTimeoutSeconds), in: 30...600, step: 30)
            }
            Section("单词卡显示模块") {
                ForEach(CardModule.allCases) { module in
                    Toggle(module.title, isOn: Binding(get: { settings.cardModules.contains(module) }, set: { enabled in
                        store.updateSettings { if enabled { $0.cardModules.insert(module) } else { $0.cardModules.remove(module) } }
                    }))
                }
            }
            Section("Collins 可选词典") {
                Toggle("Collins 功能", isOn: setting(\.collinsEnabled)).disabled(!CollinsRegistry.isConfigured)
                Text(CollinsRegistry.isConfigured ? "已配置授权词典接口。" : "尚未配置授权 Collins API，词卡将隐藏该模块。预留的词典接口可在取得授权后接入。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("数据") {
                NavigationLink { DataTransferView() } label: { Label("数据迁出 / 迁入", systemImage: "externaldrive") }
                Text("定期将完整备份保存到文件 App、iCloud Drive 或通过 AirDrop 传到另一台设备。本机自动保护副本不能替代设备外备份。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("关于") {
                LabeledContent("菠萝单词", value: "1.0.0")
                LabeledContent("数据版本", value: "1")
                Text("为长期学习而做。没有账户、服务器或广告；本地功能可以离线使用。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .alert("设置提示", isPresented: Binding(get: { settingsError != nil }, set: { if !$0 { settingsError = nil } })) {
            Button("知道了", role: .cancel) { settingsError = nil }
        } message: { Text(settingsError ?? "") }
        .onAppear {
            fastModel = settings.fastModel; deepModel = settings.deepModel
            do { keyExists = !(try KeychainService.read() ?? "").isEmpty } catch { settingsError = error.localizedDescription }
        }
        .onDisappear { apiKey = ""; store.speech.stop() }
    }
    private func setting<T>(_ keyPath: WritableKeyPath<UserSettings, T>) -> Binding<T> {
        Binding(get: { store.snapshot.settings[keyPath: keyPath] }, set: { newValue in store.updateSettings { $0[keyPath: keyPath] = newValue } })
    }
}
