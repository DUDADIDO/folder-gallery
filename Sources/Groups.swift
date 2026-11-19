import Foundation
import LocalAuthentication

/// 갤럭시의 '그룹': 앨범 여러 개를 담는 폴더. 카메라·스크린샷 같은 자동 앨범도 넣을 수 있게
/// 사진 앱의 폴더가 아니라 이 앱 안에만 저장함 (사진·앨범 자체는 안 건드림)
struct AlbumGroup: Codable {
    var id: String          // "group:" + UUID — 앨범 ID 와 안 겹치게
    var title: String
    var members: [String]   // 들어 있는 앨범 ID

    static let prefix = "group:"
}

enum Groups {
    private static let key = "albumGroups"
    private static let orderKey = "albumCustomOrder"

    static func all() -> [AlbumGroup] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([AlbumGroup].self, from: data) else { return [] }
        return list
    }

    private static func save(_ list: [AlbumGroup]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
        NotificationCenter.default.post(name: Library.didChange, object: nil)
    }

    static func group(id: String) -> AlbumGroup? {
        all().first { $0.id == id }
    }

    /// 어느 그룹에든 들어 있는 앨범 ID
    static func groupedIDs() -> Set<String> {
        var result = Set<String>()
        for group in all() {
            result.formUnion(group.members)
        }
        return result
    }

    @discardableResult
    static func create(title: String, members: [String] = []) -> AlbumGroup {
        var list = all()
        // 한 앨범은 한 그룹에만
        for index in list.indices {
            list[index].members.removeAll { members.contains($0) }
        }
        let group = AlbumGroup(id: AlbumGroup.prefix + UUID().uuidString, title: title, members: members)
        list.append(group)
        save(list)
        return group
    }

    static func add(_ albumID: String, to groupID: String) {
        var list = all()
        guard list.contains(where: { $0.id == groupID }) else { return }
        for index in list.indices {
            list[index].members.removeAll { $0 == albumID }
            if list[index].id == groupID {
                list[index].members.append(albumID)
            }
        }
        save(list)
    }

    /// 그룹에서 빼서 바깥(앨범 탭 첫 화면)으로
    static func remove(_ albumID: String) {
        var list = all()
        for index in list.indices {
            list[index].members.removeAll { $0 == albumID }
        }
        save(list)
    }

    static func rename(_ groupID: String, to title: String) {
        var list = all()
        guard let index = list.firstIndex(where: { $0.id == groupID }) else { return }
        list[index].title = title
        save(list)
    }

    /// 그룹만 없앰. 안에 있던 앨범은 바깥으로 나옴
    static func delete(_ groupID: String) {
        var list = all()
        list.removeAll { $0.id == groupID }
        save(list)
    }

    // MARK: - 사용자 지정 순서 (화면별: "top" 또는 그룹 ID)

    static func customOrder(for container: String) -> [String] {
        let all = UserDefaults.standard.dictionary(forKey: orderKey) as? [String: [String]]
        return all?[container] ?? []
    }

    static func setCustomOrder(_ ids: [String], for container: String) {
        var all = (UserDefaults.standard.dictionary(forKey: orderKey) as? [String: [String]]) ?? [:]
        all[container] = ids
        UserDefaults.standard.set(all, forKey: orderKey)
    }
}

/// Face ID(안 되면 기기 암호)로 본인 확인
enum Auth {
    static func verify(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
            DispatchQueue.main.async { completion(ok) }
        }
    }
}
