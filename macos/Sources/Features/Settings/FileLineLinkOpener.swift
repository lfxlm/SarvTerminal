import AppKit
import Foundation

/// Which editor opens `path/file.go:154`-style links clicked in the terminal.
/// Presets cover the common URL-scheme editors; `.custom` lets the user set
/// any URL template with `${file}` / `${line}` / `${column}` placeholders.
enum FileLinkEditor: String, CaseIterable, Identifiable {
    static let storageKey = "SarvFileLinkEditor"
    static let customTemplateKey = "SarvFileLinkEditorTemplate"

    case systemDefault
    case vscode
    case cursor
    case zed
    case goland
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .systemDefault: return loc(.file_link_editor_default)
        case .vscode: return "Visual Studio Code"
        case .cursor: return "Cursor"
        case .zed: return "Zed"
        case .goland: return "GoLand"
        case .custom: return loc(.file_link_editor_custom)
        }
    }

    /// URL template with `${file}`/`${line}`/`${column}` placeholders.
    /// nil means "open with the system default app" (line info is dropped).
    var urlTemplate: String? {
        switch self {
        case .systemDefault:
            return nil
        case .vscode:
            return "vscode://file${file}:${line}:${column}"
        case .cursor:
            return "cursor://file${file}:${line}:${column}"
        case .zed:
            return "zed://file${file}:${line}:${column}"
        case .goland:
            return "goland://open?file=${file}&line=${line}"
        case .custom:
            let t = UserDefaults.standard.string(forKey: Self.customTemplateKey) ?? ""
            return t.isEmpty ? nil : t
        }
    }

    static var current: FileLinkEditor {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? ""
        return FileLinkEditor(rawValue: raw) ?? .systemDefault
    }
}

/// Parses and opens terminal links of the form `/abs/path/file.go:154[:3]`
/// (compiler/stack-trace output) as well as plain `/abs/path/file.go` paths.
/// The raw text isn't an existing file until the `:line[:col]` suffix is
/// stripped, which is why the default NSWorkspace open silently fails on these.
enum FileLineLink {
    struct Target {
        let path: String
        let line: Int?
        let column: Int?
    }

    /// Splits `raw` into a path and an optional trailing `:line[:col]`.
    /// Existence is NOT checked here — the caller decides whether to open
    /// the target or warn that no such file exists locally.
    static func parse(_ raw: String) -> Target? {
        var path = raw
        var line: Int?
        var column: Int?

        if let match = raw.range(of: #":(\d+)(?::(\d+))?$"#, options: .regularExpression) {
            let numbers = raw[match.lowerBound...].dropFirst().split(separator: ":")
            if let first = numbers.first, let l = Int(first) {
                path = String(raw[raw.startIndex..<match.lowerBound])
                line = l
                column = numbers.count > 1 ? Int(numbers[1]) : nil
            }
        }

        guard !path.isEmpty else { return nil }
        return Target(path: path, line: line, column: column)
    }

    /// True when `raw` resembles a file path rather than arbitrary prose. Every
    /// link the engine hands us is either a scheme URL (handled before this) or
    /// path-like, but this guards against exotic OSC8 URIs.
    static func looksLikePath(_ raw: String) -> Bool {
        if raw.isEmpty { return false }
        if raw.hasPrefix("/") || raw.hasPrefix("./") || raw.hasPrefix("../")
            || raw.hasPrefix("~/") || raw == "~" {
            return true
        }
        if raw.contains("/") { return true }
        // Bare `name.ext` or `name.ext:line[:col]` (e.g. `work_task.go:154`).
        // The extension must start with a letter so version numbers like
        // `1.2.3` in prose aren't treated as paths.
        return raw.range(
            of: #"^[\w][\w.+-]*\.[a-zA-Z][\w+-]*(:\d+(:\d+)?)?$"#,
            options: .regularExpression
        ) != nil
    }

    /// Opens the target in the configured editor at the given line. Falls
    /// back to the system default app for the bare file when the editor
    /// scheme can't be opened (editor not installed, bad template, …).
    @discardableResult
    static func open(_ target: Target) -> Bool {
        if let template = FileLinkEditor.current.urlTemplate {
            // Plain files have no line info; open at line 1 so the configured
            // editor still receives the file (all preset templates accept a
            // `:line` component).
            let t: Target = target.line != nil
                ? target
                : Target(path: target.path, line: 1, column: nil)
            if let url = buildURL(template: template, target: t),
               NSWorkspace.shared.open(url) {
                return true
            }
        }
        // System default — the line number is lost, but the file opens.
        return NSWorkspace.shared.open(URL(fileURLWithPath: target.path))
    }

    private static func buildURL(template: String, target: Target) -> URL? {
        let escapedPath = target.path.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed) ?? target.path
        var s = template
        s = s.replacingOccurrences(of: "${file}", with: escapedPath)
        s = s.replacingOccurrences(of: "${line}", with: String(target.line ?? 1))
        s = s.replacingOccurrences(of: "${column}", with: String(target.column ?? 1))
        return URL(string: s)
    }
}

/// Shown when the user clicks a link that looks like a file path but no such
/// file exists on this machine (e.g. a path from a remote server's log output).
/// Offers to copy the path so it can be used elsewhere.
enum MissingPathAlert {
    static func show(path: String) {
        let alert = NSAlert()
        alert.messageText = loc(.path_not_found_title)
        alert.informativeText = "\(loc(.path_not_found_message))\n\n\(path)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: loc(.copy_path))
        alert.addButton(withTitle: loc(.cancel))
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        }
    }
}
