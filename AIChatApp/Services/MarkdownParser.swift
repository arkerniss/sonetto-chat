import Foundation
import SwiftUI

/// 仿 rikkahub 的消息渲染管线:先把 AI 回复按块(代码块/标题/列表/引用/表格/
/// 分割线/段落)切分,再用自定义的行内解析器处理加粗、斜体、行内代码、链接。
///
/// 不直接用 `AttributedString(markdown:)` 的原因有二:
/// 1. `.full` 语法会把段落之间的换行全部吞掉,长回复糊成一行;
/// 2. CommonMark 的 flanking 规则在中文标点紧贴 `**` 时会让加粗失效
///    (例如 `**标题:**正文`),而这是 AI 中文输出里的高频形态。
/// 自己按 `**` 配对解析就没有 flanking 问题。
enum MarkdownBlock: Equatable {
    case paragraph(AttributedString)
    case heading(level: Int, text: AttributedString)
    case codeBlock(language: String, code: String)
    case quote([AttributedString])
    case list([MarkdownListItem])
    case table(header: [AttributedString], rows: [[AttributedString]])
    case divider
}

struct MarkdownListItem: Equatable {
    var level: Int
    var marker: String
    var text: AttributedString
}

enum MarkdownParser {
    static func parse(_ content: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var listItems: [MarkdownListItem] = []
        var quoteLines: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(inline(paragraphLines.joined(separator: "\n"))))
            paragraphLines = []
        }

        func flushList() {
            guard !listItems.isEmpty else { return }
            blocks.append(.list(listItems))
            listItems = []
        }

        func flushQuote() {
            guard !quoteLines.isEmpty else { return }
            blocks.append(.quote(quoteLines.map(inline)))
            quoteLines = []
        }

        func flushAll() {
            flushParagraph()
            flushList()
            flushQuote()
        }

        let lines = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 代码块:```lang ... ```。流式输出时结尾可能还没闭合,照常渲染。
            if trimmed.hasPrefix("```") {
                flushAll()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                index += 1
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count {
                    index += 1
                }
                blocks.append(.codeBlock(language: language, code: codeLines.joined(separator: "\n")))
                continue
            }

            if trimmed.isEmpty {
                flushAll()
                index += 1
                continue
            }

            if let heading = headingBlock(trimmed) {
                flushAll()
                blocks.append(heading)
                index += 1
                continue
            }

            if isDivider(trimmed) {
                flushAll()
                blocks.append(.divider)
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushList()
                quoteLines.append(String(trimmed.dropFirst().drop(while: { $0 == " " })))
                index += 1
                continue
            }

            if let item = listItem(line) {
                flushParagraph()
                flushQuote()
                listItems.append(item)
                index += 1
                continue
            }

            if index + 1 < lines.count, isTableHeader(line, separator: lines[index + 1]) {
                flushAll()
                let header = tableCells(line).map(inline)
                index += 2
                var rows: [[AttributedString]] = []
                while index < lines.count, lines[index].contains("|"),
                      !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    var cells = tableCells(lines[index]).map(inline)
                    // Grid 要求每行列数一致,按表头列数补齐/截断
                    while cells.count < header.count {
                        cells.append(AttributedString())
                    }
                    rows.append(Array(cells.prefix(header.count)))
                    index += 1
                }
                blocks.append(.table(header: header, rows: rows))
                continue
            }

            paragraphLines.append(line)
            index += 1
        }

        flushAll()
        return blocks
    }

    // MARK: - 块级识别

    private static func headingBlock(_ trimmed: String) -> MarkdownBlock? {
        guard trimmed.hasPrefix("#") else {
            return nil
        }
        let hashes = trimmed.prefix(while: { $0 == "#" })
        guard hashes.count <= 6 else {
            return nil
        }
        let rest = trimmed.dropFirst(hashes.count)
        guard rest.first == " " else {
            return nil
        }
        return .heading(level: hashes.count, text: inline(rest.trimmingCharacters(in: .whitespaces)))
    }

    private static func isDivider(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else {
            return false
        }
        return trimmed.allSatisfy { $0 == "-" }
            || trimmed.allSatisfy { $0 == "*" }
            || trimmed.allSatisfy { $0 == "_" }
    }

    private static let unorderedBullets = ["•", "◦", "▪"]

    private static func listItem(_ line: String) -> MarkdownListItem? {
        if let match = line.wholeMatch(of: #/^([ \t]*)[-*+][ \t]+(.+)$/#) {
            let level = indentLevel(match.output.1)
            return MarkdownListItem(
                level: level,
                marker: unorderedBullets[min(level, unorderedBullets.count - 1)],
                text: inline(String(match.output.2))
            )
        }
        if let match = line.wholeMatch(of: #/^([ \t]*)(\d{1,3})[.、)][ \t]+(.+)$/#) {
            return MarkdownListItem(
                level: indentLevel(match.output.1),
                marker: "\(match.output.2).",
                text: inline(String(match.output.3))
            )
        }
        return nil
    }

    private static func indentLevel(_ indent: Substring) -> Int {
        let width = indent.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) }
        return min(width / 2, 3)
    }

    private static func isTableHeader(_ line: String, separator: String) -> Bool {
        guard line.contains("|") else {
            return false
        }
        let sep = separator.trimmingCharacters(in: .whitespaces)
        guard sep.contains("-"), sep.contains("|") else {
            return false
        }
        return sep.allSatisfy { "-:| \t".contains($0) }
    }

    private static func tableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }
        return trimmed
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - 行内解析

    static func inline(_ raw: String) -> AttributedString {
        // rikkahub 在叶节点把 <br> 转成换行,这里在行内解析前做同样的事
        let text = raw.replacingOccurrences(
            of: "<br\\s*/?>",
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )
        return render(Substring(text), style: InlineStyle())
    }

    private struct InlineStyle {
        var bold = false
        var italic = false
        var strikethrough = false
    }

    private static func render(_ text: Substring, style: InlineStyle) -> AttributedString {
        var out = AttributedString()
        var plainStart = text.startIndex
        var i = text.startIndex

        func flushPlain(upTo end: Substring.Index) {
            guard plainStart < end else {
                return
            }
            out += styled(String(text[plainStart..<end]), style: style)
        }

        func emphasis(markerLength: Int, marker: String, transform: (inout InlineStyle) -> Void) -> Bool {
            let innerStart = text.index(i, offsetBy: markerLength)
            guard innerStart < text.endIndex,
                  let close = text.range(of: marker, range: innerStart..<text.endIndex),
                  close.lowerBound > innerStart else {
                return false
            }
            flushPlain(upTo: i)
            var nested = style
            transform(&nested)
            out += render(text[innerStart..<close.lowerBound], style: nested)
            i = close.upperBound
            plainStart = i
            return true
        }

        while i < text.endIndex {
            let ch = text[i]
            let rest = text[i...]

            if ch == "`" {
                let afterTick = text.index(after: i)
                if afterTick < text.endIndex,
                   let close = text[afterTick...].firstIndex(of: "`"),
                   close > afterTick {
                    flushPlain(upTo: i)
                    out += codeSpan(String(text[afterTick..<close]))
                    i = text.index(after: close)
                    plainStart = i
                    continue
                }
            } else if rest.hasPrefix("***") {
                if emphasis(markerLength: 3, marker: "***", transform: { $0.bold = true; $0.italic = true }) {
                    continue
                }
            } else if rest.hasPrefix("**") {
                if emphasis(markerLength: 2, marker: "**", transform: { $0.bold = true }) {
                    continue
                }
            } else if rest.hasPrefix("__") {
                if emphasis(markerLength: 2, marker: "__", transform: { $0.bold = true }) {
                    continue
                }
            } else if rest.hasPrefix("~~") {
                if emphasis(markerLength: 2, marker: "~~", transform: { $0.strikethrough = true }) {
                    continue
                }
            } else if ch == "*" {
                let innerStart = text.index(after: i)
                if innerStart < text.endIndex, text[innerStart] != " ",
                   let close = text[innerStart...].firstIndex(of: "*"),
                   close > innerStart {
                    flushPlain(upTo: i)
                    var nested = style
                    nested.italic = true
                    out += render(text[innerStart..<close], style: nested)
                    i = text.index(after: close)
                    plainStart = i
                    continue
                }
            } else if ch == "[" {
                let labelStart = text.index(after: i)
                if labelStart < text.endIndex,
                   let labelEnd = text.range(of: "](", range: labelStart..<text.endIndex),
                   let urlEnd = text[labelEnd.upperBound...].firstIndex(of: ")") {
                    flushPlain(upTo: i)
                    var link = render(text[labelStart..<labelEnd.lowerBound], style: style)
                    if let url = URL(string: String(text[labelEnd.upperBound..<urlEnd])) {
                        link.link = url
                        link.foregroundColor = .accentColor
                        link.underlineStyle = .single
                    }
                    out += link
                    i = text.index(after: urlEnd)
                    plainStart = i
                    continue
                }
            }

            i = text.index(after: i)
        }

        flushPlain(upTo: text.endIndex)
        return out
    }

    private static func styled(_ string: String, style: InlineStyle) -> AttributedString {
        var attributed = AttributedString(string)
        var intent: InlinePresentationIntent = []
        if style.bold {
            intent.insert(.stronglyEmphasized)
        }
        if style.italic {
            intent.insert(.emphasized)
        }
        if !intent.isEmpty {
            attributed.inlinePresentationIntent = intent
        }
        if style.strikethrough {
            attributed.strikethroughStyle = .single
        }
        return attributed
    }

    /// 行内代码:等宽字体 + 浅背景 + 主题色,前后各补一个空格(rikkahub 同款)
    private static func codeSpan(_ code: String) -> AttributedString {
        var attributed = AttributedString(" \(code) ")
        attributed.font = .system(.callout, design: .monospaced)
        attributed.foregroundColor = .accentColor
        attributed.backgroundColor = Color.primary.opacity(0.08)
        return attributed
    }
}
