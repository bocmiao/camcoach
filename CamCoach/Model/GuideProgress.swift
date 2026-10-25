// SPDX-License-Identifier: Apache-2.0
import Combine
import Foundation

/// 上手清单的勾选状态。
///
/// 存在 UserDefaults 里，重装 App 才会丢。不用文件是因为这份数据量很小，
/// 也不值得单独维护目录和迁移逻辑。
final class GuideProgress: ObservableObject {

    static let shared = GuideProgress()

    @Published private(set) var done: Set<String>

    private let storageKey = "camcoach.guide.done.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.done = Set(defaults.stringArray(forKey: storageKey) ?? [])
    }

    func isDone(_ id: String) -> Bool {
        done.contains(id)
    }

    func toggle(_ id: String) {
        if done.contains(id) {
            done.remove(id)
        } else {
            done.insert(id)
        }
        persist()
    }

    func reset() {
        done = []
        defaults.removeObject(forKey: storageKey)
    }

    /// 只算清单里真实存在的条目，免得数据删了以后进度虚高。
    func doneCount(among ids: [String]) -> Int {
        ids.reduce(0) { $0 + (done.contains($1) ? 1 : 0) }
    }

    private func persist() {
        defaults.set(Array(done), forKey: storageKey)
    }
}
