import Foundation

enum DeckImportError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

private final class XMLNode {
    let name: String
    let attributes: [String: String]
    var text = ""
    var children: [XMLNode] = []
    init(_ name: String, _ attributes: [String: String]) { self.name = name; self.attributes = attributes }
    func descendants(_ name: String) -> [XMLNode] {
        children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(name) }
    }
}

private final class XMLTree: NSObject, XMLParserDelegate {
    var root: XMLNode?
    var stack: [XMLNode] = []
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if stack.count > 128 { parser.abortParsing(); return }
        let node = XMLNode(name.components(separatedBy: ":").last!, attributes)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) { if !stack.isEmpty { stack.removeLast() } }
    static func parse(_ data: Data) throws -> XMLNode {
        guard data.count <= 8 * 1024 * 1024 else { throw DeckImportError.invalid("XMLが大きすぎます") }
        let tree = XMLTree()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = tree
        guard parser.parse(), let root = tree.root else { throw DeckImportError.invalid("pptx内のXMLを読み取れません") }
        return root
    }
}

enum PPTXImporter {
    /// Read ZIP entries to stdout, never extract paths from the archive onto disk.
    private static func entry(_ path: String, in archive: URL, required: Bool = true) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archive.path, path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        var data = Data()
        while true {
            let chunk = pipe.fileHandleForReading.readData(ofLength: 65536)
            if chunk.isEmpty { break }
            data.append(chunk)
            if data.count > 8 * 1024 * 1024 {
                process.terminate()
                try? pipe.fileHandleForReading.close()
                process.waitUntilExit()
                throw DeckImportError.invalid("pptx内のデータが大きすぎます")
            }
        }
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            if !required { return Data() }
            throw DeckImportError.invalid("pptxの必須データがありません: \(path)")
        }
        return data
    }

    private static func relationships(_ path: String, archive: URL, required: Bool = true) throws -> [String: (String, String)] {
        let data = try entry(path, in: archive, required: required)
        if data.isEmpty { return [:] }
        let root = try XMLTree.parse(data)
        var result: [String: (String, String)] = [:]
        for node in root.descendants("Relationship") {
            guard node.attributes["TargetMode"] != "External", let id = node.attributes["Id"],
                  let target = node.attributes["Target"], let type = node.attributes["Type"] else { continue }
            result[id] = (target, type)
        }
        return result
    }

    static func resolve(_ target: String, relativeTo part: String) throws -> String {
        guard !target.contains(":"), !target.contains("\\"), !target.contains("*"), !target.contains("?"), !target.contains("["), !target.contains("\0") else {
            throw DeckImportError.invalid("不正なpptx内参照です")
        }
        var components = target.hasPrefix("/") ? [] : Array(part.split(separator: "/").dropLast()).map(String.init)
        for component in target.split(separator: "/") {
            if component == "." { continue }
            if component == ".." {
                guard !components.isEmpty else { throw DeckImportError.invalid("不正な相対パスです") }
                components.removeLast()
            } else { components.append(String(component)) }
        }
        let path = components.joined(separator: "/")
        guard path.hasPrefix("ppt/"), path.hasSuffix(".xml") else { throw DeckImportError.invalid("pptx外の参照には対応していません") }
        return path
    }

    static func load(_ url: URL) throws -> ImportedDeck {
        guard url.pathExtension.lowercased() == "pptx" else { throw DeckImportError.invalid(".pptxを選択してください") }
        // NSOpenPanel grants scoped access; unzip reads our private snapshot.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = directory.appendingPathComponent("deck.pptx")
        try FileManager.default.copyItem(at: url, to: archive)
        let root = try XMLTree.parse(entry("ppt/presentation.xml", in: archive))
        let rels = try relationships("ppt/_rels/presentation.xml.rels", archive: archive)
        let list = root.descendants("sldId")
        guard !list.isEmpty, list.count <= 500 else { throw DeckImportError.invalid("1〜500枚のpptxに対応しています") }
        var slides: [ImportedSlide] = []
        var seen = Set<Int>()
        for (index, node) in list.enumerated() {
            guard let idText = node.attributes["id"], let id = Int(idText), seen.insert(id).inserted,
                  let rid = node.attributes["r:id"], let (target, type) = rels[rid], type.hasSuffix("/slide") else {
                throw DeckImportError.invalid("スライドの対応関係を確認できません")
            }
            let slidePath = try resolve(target, relativeTo: "ppt/presentation.xml")
            let parts = slidePath.split(separator: "/").map(String.init)
            let relPath = parts.dropLast().joined(separator: "/") + "/_rels/" + parts.last! + ".rels"
            let slideRels = try relationships(relPath, archive: archive, required: false)
            var notes = ""
            if let noteRel = slideRels.values.first(where: { $0.1.hasSuffix("/notesSlide") }) {
                let notePath = try resolve(noteRel.0, relativeTo: slidePath)
                let noteRoot = try XMLTree.parse(entry(notePath, in: archive))
                // Only the notes body placeholder: exclude slide numbers, headers and slide thumbnail text.
                notes = noteRoot.descendants("sp").filter { shape in
                    shape.descendants("ph").contains { $0.attributes["type"] == "body" }
                }.flatMap { $0.descendants("p") }.map { paragraph in
                    paragraph.descendants("t").map(\.text).joined()
                }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                guard notes.utf8.count <= 64 * 1024 else { throw DeckImportError.invalid("1枚のノートは64KB以内にしてください") }
            }
            slides.append(ImportedSlide(id: id, index: index + 1, notes: notes))
        }
        return ImportedDeck(url: url, slides: slides)
    }
}
