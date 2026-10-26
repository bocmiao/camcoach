// SPDX-License-Identifier: Apache-2.0
import Combine
import Foundation

/// 一个导进来的调色包。
///
/// 只存文件名和展示名，不存解析结果：.cube 解析出来是几十万个 Float，
/// 全塞进 @Published 里会让每次界面刷新都跟着拷一遍。
/// 真正的数据在 LUTStore 的缓存里，要用的时候才解析第一次。
struct LUTEntry: Identifiable, Equatable {
    let name: String
    let file: String
    var id: String { name }
}

enum LUTError: LocalizedError {
    case unreadable
    case oneDimensional
    case malformed

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "这个文件读不出来。"
        case .oneDimensional:
            return "这是 1D LUT（一行颜色表），这里只支持 3D LUT。"
        case .malformed:
            return "文件格式不对：没找到 LUT_3D_SIZE，或者颜色行数和它对不上。"
        }
    }
}

/// 管理导入的 .cube 文件。
///
/// 两个线程都要用它：界面线程读列表，取景循环（后台队列）取 cube 数据渲染。
/// 所以列表走 @Published，cube 缓存走锁，两条路不交叉。
final class LUTStore: ObservableObject {

    static let shared = LUTStore()

    @Published private(set) var entries: [LUTEntry] = []

    private let lock = NSLock()
    /// 名字 → 文件名。只在锁内读写。
    private var byName: [String: String] = [:]
    /// 名字 → 解析好的 cube（尺寸 + Float32 数据）。只在锁内读写。
    private var cubes: [String: (size: Int, data: Data)] = [:]

    private let dirURL: URL

    private init() {
        // 放 Documents 而不是 Caches：用户自己找来的 LUT 被系统清掉
        // 是一件很难解释的事，这东西一份也就几十 KB，不值得省。
        let base = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask)[0]
        dirURL = base.appendingPathComponent("luts", isDirectory: true)
        reload()
    }

    // MARK: - 列表

    /// 重新扫一遍磁盘。启动时调一次，导入/删除后也调。
    func reload() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dirURL, includingPropertiesForKeys: nil) else {
            apply(list: [])
            return
        }

        var list: [LUTEntry] = []
        for url in files where url.pathExtension.lowercased() == "cube" {
            list.append(LUTEntry(name: url.deletingPathExtension().lastPathComponent,
                                 file: url.lastPathComponent))
        }
        list.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        apply(list: list)
    }

    private func apply(list: [LUTEntry]) {
        var map: [String: String] = [:]
        for e in list { map[e.name] = e.file }
        lock.lock()
        byName = map
        // 列表变了，缓存里可能有已经被删掉的名字，整块清掉重来。
        // 几十 KB 的事，不值得做增量。
        cubes.removeAll()
        lock.unlock()

        // @Published 必须在主线程改。
        if Thread.isMainThread {
            entries = list
        } else {
            DispatchQueue.main.async { self.entries = list }
        }
    }

    // MARK: - 渲染时取数据

    /// 取一个调色包的 cube 数据。**可能在后台线程调用**，所以这里只碰锁内的东西。
    ///
    /// 第一次访问某个包才解析，之后走缓存——取景是 10fps，
    /// 每帧重解析 33³ 的表撑不住。
    func cube(named name: String) -> (size: Int, data: Data)? {
        lock.lock()
        if let hit = cubes[name] {
            lock.unlock()
            return hit
        }
        let file = byName[name]
        lock.unlock()

        guard let file = byName[name] else { return nil }
        let url = dirURL.appendingPathComponent(file)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        guard let parsed = LUTStore.parse(text) else { return nil }

        lock.lock()
        cubes[name] = parsed
        lock.unlock()
        return parsed
    }

    // MARK: - 导入与删除

    /// 把一个 .cube 文件收进来。
    ///
    /// 先完整解析一遍再落盘：格式不对的文件不应该留在列表里，
    /// 否则用户选了它、画面没反应，还以为是自己操作错了。
    @discardableResult
    func importFile(at url: URL) throws -> LUTEntry {
        // 从「文件」App 选来的 URL 是沙盒外的，不开始访问域就读不到。
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw LUTError.unreadable
        }
        if text.uppercased().contains("LUT_1D_SIZE") {
            throw LUTError.oneDimensional
        }
        guard LUTStore.parse(text) != nil else {
            throw LUTError.malformed
        }

        let base = url.deletingPathExtension().lastPathComponent
        let name = uniqueName(base)

        try FileManager.default.createDirectory(at: dirURL,
                                                withIntermediateDirectories: true)
        let target = dirURL.appendingPathComponent(name + ".cube")
        try text.write(to: target, atomically: true, encoding: .utf8)

        reload()
        return LUTEntry(name: name, file: name + ".cube")
    }

    /// 删掉一个调色包。ID 传的是 `lut:名字` 这种形式，这里兼容两种写法。
    func remove(id: String) {
        var name = id
        if name.hasPrefix(Filters.lutPrefix) {
            name = String(name.dropFirst(Filters.lutPrefix.count))
        }
        let url = dirURL.appendingPathComponent(name + ".cube")
        try? FileManager.default.removeItem(at: url)
        reload()
    }

    private func uniqueName(_ wanted: String) -> String {
        // 名字里带路径分隔符会在创建文件时炸，直接换成下划线。
        let cleaned = wanted
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "调色包" : cleaned

        var candidate = base
        var n = 2
        while FileManager.default.fileExists(
            atPath: dirURL.appendingPathComponent(candidate + ".cube").path) {
            candidate = "\(base) \(n)"
            n += 1
        }
        return candidate
    }

    // MARK: - 解析

    /// 解析 .cube 文本，转成 CIColorCube 要的 Float32 数组。
    ///
    /// 两条容易错的地方，都在这儿一次说清：
    ///
    /// 一、**颜色行的顺序是「红变得最快」**。标准 .cube 里
    ///     最内层循环是 R，往外是 G，最外层是 B。CIColorCube 也是这个顺序，
    ///     所以行序可以直接照搬，不要重排——重排了颜色会把青和红对调。
    ///
    /// 二、**每个点要补一个 alpha = 1**。CIColorCube 要求的是
    ///     premultiplied alpha 的 RGBA，只给 RGB 会被当成 4 字节一组读错位。
    static func parse(_ text: String) -> (size: Int, data: Data)? {
        var size = 0
        var values: [Float] = []
        var reserved = false

        // 有些软件导出的 .cube 开头带 BOM，不去掉的话第一行认不出来。
        let clean = text.replacingOccurrences(of: "\u{FEFF}", with: "")

        for raw in clean.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }

            let head = line.uppercased()
            if head.hasPrefix("TITLE") || head.hasPrefix("DOMAIN_MIN")
                || head.hasPrefix("DOMAIN_MAX") {
                // TITLE 是注释性质。DOMAIN_MIN/MAX 不是 0…1 的 LUT 极罕见，
                // 真碰上会颜色偏，但比整个不认好。
                continue
            }
            if head.hasPrefix("LUT_3D_SIZE") {
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if parts.count >= 2, let n = Int(parts[1]), n >= 2, n <= 65 {
                    size = n
                    values.reserveCapacity(n * n * n * 4)
                    reserved = true
                }
                continue
            }
            if head.hasPrefix("LUT_1D_SIZE") { return nil }

            if !reserved {
                // 还没读到尺寸就开始出颜色行，说明这文件不是标准 3D LUT。
                // 不 reserve 也不会错，只是慢一点。
                reserved = true
                values.reserveCapacity(33 * 33 * 33 * 4)
            }

            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 3 else { continue }
            guard let r = Float(parts[0]),
                  let g = Float(parts[1]),
                  let b = Float(parts[2]) else { continue }
            values.append(r)
            values.append(g)
            values.append(b)
            values.append(1.0)
        }

        guard size >= 2 else { return nil }
        // 行数必须正好对上，多一行少一行都说明文件被截断过，
        // 这种文件渲染出来是整片偏色，不如直接拒掉。
        guard values.count == size * size * size * 4 else { return nil }

        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        return (size, data)
    }
}
