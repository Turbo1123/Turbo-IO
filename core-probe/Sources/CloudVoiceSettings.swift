import UIKit
import Security

enum CloudVoiceKeys {
    static var asrHost: String { CloudASRHostSettings.current() }
    static var asrService: String { CloudASRHostSettings.service(for: asrHost) }
    static let llmService = "RayNeo.CloudLLM.https.api.deepseek.com.chat.completions"
    static let enabledKey = "cloudVoiceConsent.v1"
    static func get(_ service: String) -> String? {
        var item: CFTypeRef?
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:service, kSecAttrAccount as String:"user-api-key",
            kSecReturnData as String:true, kSecMatchLimit as String:kSecMatchLimitOne]
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data:data,encoding:.utf8)
    }
    static var ready: Bool { CloudASRHostSettings.normalize(asrHost) != nil && Self.get(asrService) != nil && Self.get(llmService) != nil }
    static func save(_ value: String, service: String) -> Bool {
        let key = value.trimmingCharacters(in:.whitespacesAndNewlines)
        guard key.hasPrefix("sk-"), key.utf8.count <= 512,
              !key.contains(where: { $0.isWhitespace }) else { return false }
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,
            kSecAttrService as String:service, kSecAttrAccount as String:"user-api-key"]
        let attributes: [String:Any] = [kSecValueData as String:Data(key.utf8),
            kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            return SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary,nil) == errSecSuccess
        }
        return result == errSecSuccess
    }
}

final class CloudVoiceSettingsController: UIViewController {
    var changed: ((Bool) -> Void)?
    private let asr = UITextField(), llm = UITextField(), host = UITextField(), note = UILabel()
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .systemBackground
        let stack = UIStackView(); stack.axis = .vertical; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        let title = UILabel(); title.text = "云端语音测试"; title.font = .preferredFont(forTextStyle:.title1)
        stack.addArrangedSubview(title)
        note.numberOfLines = 0
        note.text = "阿里云 ASR → DeepSeek V4 Flash\n关闭思考 · 流式输出 · 云端 VAD\n唤醒后音频发往已指定阿里云空间，识别文字发往 DeepSeek。两边均可能计费。无 TTS、无工具执行。密钥仅存本机 Keychain，日志不记音频或正文。"
        stack.addArrangedSubview(note)
        host.placeholder = "你的阿里云 ASR Host（不含协议/路径）"
        host.text = CloudASRHostSettings.current(); host.borderStyle = .roundedRect
        host.autocapitalizationType = .none; host.autocorrectionType = .no
        stack.addArrangedSubview(host)
        for (field, identifier, placeholder) in [(asr,"cloud-asr-key","阿里云 API Key"),(llm,"cloud-llm-key","DeepSeek API Key")] {
            field.isSecureTextEntry = true; field.accessibilityIdentifier = identifier
            field.placeholder = placeholder; field.borderStyle = .roundedRect
            field.autocapitalizationType = .none; field.autocorrectionType = .no
            field.textContentType = .password
            stack.addArrangedSubview(field)
        }
        for (title, action) in [("保存并启用云对话",#selector(save)),("关闭云端，回到随机测试",#selector(disable)),("返回",#selector(back))] {
            let button = UIButton(type:.system); button.setTitle(title,for:.normal)
            button.heightAnchor.constraint(equalToConstant:44).isActive = true
            button.addTarget(self,action:action,for:.touchUpInside); stack.addArrangedSubview(button)
        }
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo:view.safeAreaLayoutGuide.topAnchor,constant:24),
            stack.leadingAnchor.constraint(equalTo:view.leadingAnchor,constant:20),stack.trailingAnchor.constraint(equalTo:view.trailingAnchor,constant:-20)])
    }
    @objc private func save() {
        let a = asr.text ?? "", b = llm.text ?? ""
        guard let target = CloudASRHostSettings.normalize(host.text ?? "") else { note.text = "请填写有效的阿里云 ASR 主机名。未启用云上传。"; return }
        let service = CloudASRHostSettings.service(for: target)
        let okA = a.isEmpty ? CloudVoiceKeys.get(service) != nil : CloudVoiceKeys.save(a,service:service)
        let okB = b.isEmpty ? CloudVoiceKeys.get(CloudVoiceKeys.llmService) != nil : CloudVoiceKeys.save(b,service:CloudVoiceKeys.llmService)
        asr.text = ""; llm.text = ""
        guard okA && okB else { note.text = "密钥未完整保存，请检查输入。未启用云上传。"; return }
        CloudASRHostSettings.save(target)
        UserDefaults.standard.set(true,forKey:CloudVoiceKeys.enabledKey)
        changed?(true); dismiss(animated:true)
    }
    @objc private func disable() {
        UserDefaults.standard.set(false,forKey:CloudVoiceKeys.enabledKey)
        changed?(false); dismiss(animated:true)
    }
    @objc private func back() { dismiss(animated:true) }
}
