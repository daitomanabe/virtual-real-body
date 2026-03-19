import Foundation

enum LygiaResolver {
    static let lygiaRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("../external/lygia")
        .standardizedFileURL

    private static let includePattern = #"#include\s+"([^"]+)""#

    static func resolve(source: String, sourceURL: URL? = nil, visited: inout Set<String>) throws -> String {
        let regex = try NSRegularExpression(pattern: includePattern)
        let nsRange = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches = regex.matches(in: source, range: nsRange).reversed()
        var resolved = source

        for match in matches {
            guard let range = Range(match.range(at: 0), in: resolved),
                  let includeRange = Range(match.range(at: 1), in: resolved)
            else { continue }

            let includePath = String(resolved[includeRange])
            let resolvedURL = resolveURL(for: includePath, sourceURL: sourceURL)
            let key = resolvedURL.standardizedFileURL.path
            if visited.contains(key) {
                resolved.replaceSubrange(range, with: "")
                continue
            }
            visited.insert(key)
            let nested = try String(contentsOf: resolvedURL)
            let nestedResolved = try resolve(source: nested, sourceURL: resolvedURL, visited: &visited)
            resolved.replaceSubrange(range, with: nestedResolved)
        }

        return resolved
    }

    static func resolve(url: URL) throws -> String {
        var visited: Set<String> = [url.standardizedFileURL.path]
        return try resolve(source: String(contentsOf: url), sourceURL: url, visited: &visited)
    }

    private static func resolveURL(for includePath: String, sourceURL: URL?) -> URL {
        if includePath.hasPrefix("lygia/") {
            return lygiaRoot.appendingPathComponent(String(includePath.dropFirst("lygia/".count)))
        }
        if let sourceURL {
            return sourceURL.deletingLastPathComponent().appendingPathComponent(includePath)
        }
        return URL(fileURLWithPath: includePath, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL
    }
}
