import Foundation

enum PathJail {
    /// Real path inside `root`, or nil when it escapes. "." is the root itself.
    static func resolve(root rawRoot: String, relative: String) -> String? {
        let rootURL = URL(fileURLWithPath: rawRoot).standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = rootURL.path
        let pieces = relative
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0 != "." }
        if pieces.isEmpty {
            return rootPath
        }
        if pieces.contains(where: { $0 == ".." || $0.contains("\0") }) {
            return nil
        }
        var url = rootURL
        for piece in pieces {
            url.appendPathComponent(piece)
        }
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath().path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if resolved == rootPath || resolved.hasPrefix(prefix) {
            return resolved
        }
        return nil
    }
}

enum FTPPaths {
    static func resolve(root: String, currentVirtual: String, requested: String) -> (virtual: String, actual: String)? {
        var clean = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { clean = "." }
        let combined = clean.hasPrefix("/") ? clean : (currentVirtual as NSString).appendingPathComponent(clean)
        guard let virtual = normalize(combined) else { return nil }
        let relative = String(virtual.dropFirst())
        guard let actual = PathJail.resolve(root: root, relative: relative.isEmpty ? "." : relative) else { return nil }
        return (virtual, actual)
    }

    static func normalize(_ path: String) -> String? {
        var stack: [String] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." {
                if stack.isEmpty { return nil }
                stack.removeLast()
                continue
            }
            stack.append(String(part))
        }
        return stack.isEmpty ? "/" : "/" + stack.joined(separator: "/")
    }
}

enum FTPPorts {
    static func parse(_ argument: String) -> (host: String, port: UInt16)? {
        let parts = argument.split(separator: ",").compactMap { UInt16($0) }
        guard parts.count == 6, parts[0...3].allSatisfy({ $0 < 256 }) else { return nil }
        let port = (parts[4] << 8) | parts[5]
        guard port > 0 else { return nil }
        return ("\(parts[0]).\(parts[1]).\(parts[2]).\(parts[3])", port)
    }

    static func allows(clientIP: String, host: String) -> Bool {
        normalize(clientIP) == normalize(host)
    }

    static func normalize(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let mapped = "::ffff:"
        if text.lowercased().hasPrefix(mapped) {
            text.removeFirst(mapped.count)
        }
        return text
    }
}
