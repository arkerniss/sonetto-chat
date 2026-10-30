import Foundation
import UIKit

/// 系统提示词与消息模板里可用的变量。点击插入到光标处,发送时替换为实际值。
enum PromptVariable: String, CaseIterable {
    // 系统提示词变量(单花括号)
    case curDate = "{cur_date}"
    case curTime = "{cur_time}"
    case curDatetime = "{cur_datetime}"
    case modelId = "{model_id}"
    case modelName = "{model_name}"
    case locale = "{locale}"
    case timezone = "{timezone}"
    case systemVersion = "{system_version}"
    case deviceInfo = "{device_info}"
    case assistantName = "{assistant_name}"

    var label: String {
        switch self {
        case .curDate: return "日期"
        case .curTime: return "时间"
        case .curDatetime: return "日期时间"
        case .modelId: return "模型 ID"
        case .modelName: return "模型名称"
        case .locale: return "语言环境"
        case .timezone: return "时区"
        case .systemVersion: return "系统版本"
        case .deviceInfo: return "设备"
        case .assistantName: return "助手名称"
        }
    }
}

/// 消息模板专用变量(双花括号)。
enum MessageTemplateVariable: String, CaseIterable {
    case role = "{{ role }}"
    case message = "{{ message }}"
    case time = "{{ time }}"
    case date = "{{ date }}"

    var label: String {
        switch self {
        case .role: return "角色"
        case .message: return "消息"
        case .time: return "时间"
        case .date: return "日期"
        }
    }
}

/// 提示词 / 模板 / 正则的处理引擎。
enum PromptKit {
    // MARK: - 系统提示词变量替换

    static func substituteSystemPrompt(
        _ prompt: String,
        assistant: Assistant,
        modelID: String
    ) -> String {
        guard !prompt.isEmpty else { return prompt }

        let now = Date()
        let values: [PromptVariable: String] = [
            .curDate: dateString(now, format: "yyyy-MM-dd"),
            .curTime: dateString(now, format: "HH:mm"),
            .curDatetime: dateString(now, format: "yyyy-MM-dd HH:mm"),
            .modelId: modelID,
            .modelName: modelID,
            .locale: Locale.current.identifier,
            .timezone: TimeZone.current.identifier,
            .systemVersion: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            .deviceInfo: UIDevice.current.model,
            .assistantName: assistant.name
        ]

        var result = prompt
        for variable in PromptVariable.allCases {
            if let value = values[variable] {
                result = result.replacingOccurrences(of: variable.rawValue, with: value)
            }
        }
        return result
    }

    // MARK: - 消息模板

    /// 把模板套用到一条消息上。未知变量保持原样。
    static func applyMessageTemplate(
        _ template: String,
        role: ChatMessage.Role,
        message: String
    ) -> String {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        // 模板为空或就是默认 {{ message }} 时直接返回原文,省去正则开销
        if trimmed.isEmpty { return message }

        let now = Date()
        let values: [String: String] = [
            "role": role.rawValue,
            "message": message,
            "time": dateString(now, format: "HH:mm"),
            "date": dateString(now, format: "yyyy-MM-dd")
        ]

        guard let regex = try? NSRegularExpression(pattern: "\\{\\{\\s*(\\w+)\\s*\\}\\}") else {
            return template.replacingOccurrences(of: "{{ message }}", with: message)
        }

        let nsTemplate = template as NSString
        var output = template
        // 从后往前替换,避免索引位移
        let matches = regex.matches(in: template, range: NSRange(location: 0, length: nsTemplate.length))
        for match in matches.reversed() {
            let keyRange = match.range(at: 1)
            let key = nsTemplate.substring(with: keyRange)
            guard let value = values[key] else { continue } // 未知变量保持原样
            output = (output as NSString).replacingCharacters(in: match.range, with: value)
        }
        return output
    }

    // MARK: - 正则规则

    /// 应用正则规则。`forDisplay` = true 用于界面显示,false 用于发送给模型。
    static func applyRegexRules(
        _ rules: [AssistantRegex],
        to text: String,
        role: ChatMessage.Role,
        forDisplay: Bool
    ) -> String {
        var output = text
        for rule in rules where rule.enabled && !rule.pattern.isEmpty {
            // 作用域:角色匹配
            let roleMatches = (role == .user && rule.applyToUser) || (role == .assistant && rule.applyToAssistant)
            guard roleMatches else { continue }
            // visualOnly 只在显示时生效;replaceOnly 只在发送时生效
            if rule.visualOnly && !forDisplay { continue }
            if rule.replaceOnly && forDisplay { continue }

            guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            let range = NSRange(location: 0, length: (output as NSString).length)
            output = regex.stringByReplacingMatches(
                in: output,
                range: range,
                withTemplate: rule.replacement
            )
        }
        return output
    }

    // MARK: - 工具

    private static func dateString(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
