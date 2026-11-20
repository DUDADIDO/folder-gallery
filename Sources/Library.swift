import Photos
import UIKit

struct Folder: Hashable {
    enum Section: Int {
        case auto = 0, apps = 1, user = 2
    }
    let id: String
    let title: String
    let symbol: String
    let section: Section

    static let albumPrefix = "album:"
    static let listPrefix = "list:"

    /// 사진 앱의 폴더(앨범을 담는 것)인지
    var isGroup: Bool { id.hasPrefix(Folder.listPrefix) }
    /// 사진 앱의 앨범인지
    var isUser: Bool { id.hasPrefix(Folder.albumPrefix) }
    /// 자동 분류 앨범(카메라·스크린샷·앱별…)인지
    var isAuto: Bool { !isGroup && !isUser }
    var albumID: String? { isUser ? String(id.dropFirst(Folder.albumPrefix.count)) : nil }
    var listID: String? { isGroup ? String(id.dropFirst(Folder.listPrefix.count)) : nil }
}

struct Snapshot {
    /// 자동 분류 앨범 + 사진 앱 앨범 전부(폴더 안에 있는 것도, 이름순)
    var folders: [Folder] = []
    /// 앨범 ID → 사진(최신순). "all" = 보관함, "unsorted" = 어느 앨범에도 없는 사진.
    /// 보관함·사진 앱 앨범·동영상·즐겨찾기는 사진 앱에서 바로 읽는 목록, 자동 분류는 배열
    var items: [String: AssetList] = [:]
    /// 사진 앱의 앨범·폴더 구조. "top" 또는 폴더 ID → 안에 든 것(사진 앱에서 정한 순서)
    var children: [String: [String]] = [:]
    /// 사진 앱의 앨범·폴더
    var nodes: [String: Folder] = [:]
    /// 사진 앱 앨범 ID → 대표 사진 (사진 앱이 정한 것)
    var covers: [String: PHAsset] = [:]
    var pending = 0
    var total = 0
    var loaded = false
    /// 켤 때 먼저 보여 주는 목록에서 아직 임시인 앨범 (자동 분류·미분류: 사진 목록이 비었거나 표지 한 장뿐).
    /// 이 앨범들은 비었다·몇 장이다를 판단하면 안 됨. 전체 목록이 오면 비어 있음
    var provisional: Set<String> = []

    static let top = "top"

    /// 이 앨범의 사진 목록이 아직 임시인지 (처음 목록이 오기 전에는 모두)
    func isProvisional(_ id: String) -> Bool {
        !loaded || provisional.contains(id)
    }

    var autoFolders: [Folder] { folders.filter { $0.isAuto } }

    /// 표지 사진: 사진 앱 앨범은 그 앨범의 대표 사진, 없으면 가장 최근 사진
    func cover(_ id: String) -> PHAsset? {
        covers[id] ?? items[id]?.first
    }

    /// 폴더 안(하위 폴더 포함)의 앨범들
    func albums(under id: String) -> [Folder] {
        var result: [Folder] = []
        for child in children[id] ?? [] {
            guard let node = nodes[child] else { continue }
            if node.isGroup {
                result.append(contentsOf: albums(under: child))
            } else {
                result.append(node)
            }
        }
        return result
    }
}

/// 사진 보관함을 읽어 앨범별 목록을 만들고, 바뀌면 알림
final class Library: NSObject, PHPhotoLibraryChangeObserver {
    static let shared = Library()
    static let didChange = Notification.Name("Library.didChange")

    private(set) var snapshot = Snapshot()                             // 메인 줄에서만
    private(set) var status: PHAuthorizationStatus = .notDetermined    // 메인 줄에서만
    let classifier = Classifier()

    private let work = DispatchQueue(label: "gallery.library", qos: .userInitiated)
    /// 날짜별 묶음 계산 (전체 목록 만들기를 기다리지 않게 따로)
    private let sectionWork = DispatchQueue(label: "gallery.sections", qos: .userInitiated)
    private var rebuildScheduled = false
    private var started = false

    /// 사진 앱에서 바로 읽는 목록 (보관함 "all", 사진 앱 앨범 "album:…", "videos", "favorites").
    /// 다시 만들 때도 그대로 두고, 사진 보관함이 바뀌면 바뀐 것만 갈아 끼움 (work 줄에서만)
    private struct HeldFetch {
        var result: PHFetchResult<PHAsset>
        var version: Int
    }
    private var heldFetches: [String: HeldFetch] = [:]
    private var nextVersion = 1
    /// 날짜별 묶음: 목록 ID → (version, 묶음) (메인 줄에서만)
    private var sectionCache: [String: (version: Int, sections: DaySections)] = [:]

    /// 앨범에 넣은 사진을 자동 분류 앨범(카메라 등)에서 숨길지
    var hideMoved: Bool {
        get { UserDefaults.standard.object(forKey: "hideMoved") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "hideMoved")
            scheduleRebuild()
        }
    }

    var canRead: Bool { status == .authorized || status == .limited }

    func start() {
        guard !started else { return }
        started = true
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    self.status = newStatus
                    self.begin()
                }
            }
        } else {
            begin()
        }
    }

    private func begin() {
        NotificationCenter.default.post(name: Library.didChange, object: nil)
        guard canRead else { return }
        PHPhotoLibrary.shared().register(self)
        classifier.onProgress = { [weak self] in
            DispatchQueue.main.async { self?.scheduleRebuild() }
        }
        // 처음 한 번은 기다리지 않음: 앨범 구조·표지만으로 된 임시 목록을 바로 보여 주고, 이어서 전체 목록을 만듦
        let hide = hideMoved
        work.async {
            let quick = self.quickBuild()
            DispatchQueue.main.async {
                // 전체 목록이 이미 들어왔으면 임시 목록으로 덮지 않음
                guard !self.snapshot.loaded else { return }
                self.snapshot = quick
                NotificationCenter.default.post(name: Library.didChange, object: nil)
            }
            self.rebuildNow(hideMoved: hide)
        }
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        work.async {
            // 들고 있는 목록마다 바뀐 게 있으면 새 결과로. 사진이 들어오거나 빠지거나 옮겨졌을 때만 version 을 바꿈
            // (즐겨찾기·편집처럼 내용만 바뀌면 version 은 그대로, 사진은 새 값)
            var replaced: [String: AssetList] = [:]
            for (key, held) in self.heldFetches {
                guard let details = changeInstance.changeDetails(for: held.result) else { continue }
                var updated = held
                updated.result = details.fetchResultAfterChanges
                let reordered = !details.hasIncrementalChanges
                    || (details.insertedIndexes?.count ?? 0) > 0
                    || (details.removedIndexes?.count ?? 0) > 0
                    || details.hasMoves
                if reordered {
                    updated.version = self.nextVersion
                    self.nextVersion += 1
                }
                self.heldFetches[key] = updated
                replaced[key] = AssetList(fetch: updated.result, version: updated.version)
            }
            DispatchQueue.main.async {
                // 사진 앱에서 바로 읽는 목록(보관함·앨범·동영상·즐겨찾기)은 전체 목록을 다시 만들기를 기다리지 않고 바로 바꿔 넣음
                // (지우거나 옮긴 것이 곧바로 보이게). 자동 분류·미분류·표지·앨범 구성은 이어지는 다시 만들기가 맞춤
                if !replaced.isEmpty, self.snapshot.loaded {
                    var snap = self.snapshot
                    var changed = false
                    for (key, list) in replaced where snap.items[key] != nil {
                        snap.items[key] = list
                        changed = true
                    }
                    if changed {
                        self.snapshot = snap
                        NotificationCenter.default.post(name: Library.didChange, object: nil)
                    }
                }
                self.scheduleRebuild()
            }
        }
    }

    /// 들고 있는 목록 (없으면 만들어 둠). work 줄에서만
    private func heldList(_ key: String, _ make: () -> PHFetchResult<PHAsset>) -> (result: PHFetchResult<PHAsset>, list: AssetList) {
        if let held = heldFetches[key] {
            return (held.result, AssetList(fetch: held.result, version: held.version))
        }
        let result = make()
        let version = nextVersion
        nextVersion += 1
        heldFetches[key] = HeldFetch(result: result, version: version)
        return (result, AssetList(fetch: result, version: version))
    }

    private static var newestFirstOptions: PHFetchOptions {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return options
    }

    /// 보관함·동영상·즐겨찾기 (사진 앱에서 바로. 지금까지 보관함 전체를 훑어 고르던 것과 같은 사진들)
    private func systemLists() -> (all: (result: PHFetchResult<PHAsset>, list: AssetList), videos: AssetList, favorites: AssetList) {
        let all = heldList("all") { PHAsset.fetchAssets(with: Library.newestFirstOptions) }
        let videos = heldList("videos") { PHAsset.fetchAssets(with: .video, options: Library.newestFirstOptions) }
        let favorites = heldList("favorites") {
            let options = Library.newestFirstOptions
            options.predicate = NSPredicate(format: "favorite == YES")
            return PHAsset.fetchAssets(with: options)
        }
        return (all, videos.list, favorites.list)
    }

    /// 사진 앱 앨범 하나의 목록 (들고 있는 것을 씀)
    private func albumList(_ id: String, _ album: PHAssetCollection) -> (result: PHFetchResult<PHAsset>, list: AssetList) {
        heldList(id) { PHAsset.fetchAssets(in: album, options: Library.newestFirstOptions) }
    }

    /// 없어진 사진 앱 앨범의 목록은 버림
    private func dropHeldAlbums(except ids: Set<String>) {
        for key in Array(heldFetches.keys) where key.hasPrefix(Folder.albumPrefix) && !ids.contains(key) {
            heldFetches[key] = nil
        }
    }

    /// 앨범 하나의 목록을 화면 차례로 (newestFirst 가 아니면 오래된 순 — 같은 저장소를 뒤집어 봄). 없으면 빈 목록
    func list(for folderID: String, newestFirst: Bool) -> AssetList {
        let base = snapshot.items[folderID] ?? .empty
        return newestFirst ? base : base.reversed()
    }

    /// 이미 계산해 둔 날짜별 묶음 (같은 목록·같은 version 일 때만)
    func cachedDaySections(_ key: String, version: Int) -> DaySections? {
        guard let cached = sectionCache[key], cached.version == version else { return nil }
        return cached.sections
    }

    /// 날짜별 묶음을 뒤에서 계산해 메인 줄로 돌려줌 (목록 ID + version 마다 한 번)
    func daySections(for list: AssetList, key: String, completion: @escaping (DaySections) -> Void) {
        let version = list.version
        if let cached = cachedDaySections(key, version: version) {
            completion(cached)
            return
        }
        sectionWork.async {
            let sections = list.daySections()
            DispatchQueue.main.async {
                self.sectionCache[key] = (version, sections)
                completion(sections)
            }
        }
    }

    func scheduleRebuild() {
        guard canRead, !rebuildScheduled else { return }
        rebuildScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.rebuildScheduled = false
            let hide = self.hideMoved
            self.work.async {
                self.rebuildNow(hideMoved: hide)
            }
        }
    }

    /// 전체 목록을 만들어 바꿔 넣음 (work 줄에서만)
    private func rebuildNow(hideMoved hide: Bool) {
        let (snap, pending) = build(hideMoved: hide)
        saveAutoSummary(snap)
        DispatchQueue.main.async {
            self.snapshot = snap
            NotificationCenter.default.post(name: Library.didChange, object: nil)
        }
        classifier.enqueue(pending)
    }

    /// 사진 앱의 앨범·폴더 구조 (사진 수와 상관없이 빠름)
    private func readStructure() -> (children: [String: [String]], nodes: [String: Folder],
                                     albums: [(id: String, album: PHAssetCollection)]) {
        var children: [String: [String]] = [:]
        var nodes: [String: Folder] = [:]
        var albumObjects: [(id: String, album: PHAssetCollection)] = []
        var pendingLists: [(id: String, result: PHFetchResult<PHCollection>)] = [
            (Snapshot.top, PHCollection.fetchTopLevelUserCollections(with: nil)),
        ]
        while !pendingLists.isEmpty {
            let (container, result) = pendingLists.removeFirst()
            var ids: [String] = []
            result.enumerateObjects { collection, _, _ in
                if let album = collection as? PHAssetCollection {
                    let id = Folder.albumPrefix + album.localIdentifier
                    nodes[id] = Folder(id: id, title: album.localizedTitle ?? "이름 없음", symbol: "rectangle.stack", section: .user)
                    albumObjects.append((id, album))
                    ids.append(id)
                } else if let list = collection as? PHCollectionList {
                    let id = Folder.listPrefix + list.localIdentifier
                    nodes[id] = Folder(id: id, title: list.localizedTitle ?? "이름 없음", symbol: "folder", section: .user)
                    pendingLists.append((id, PHCollection.fetchCollections(in: list, options: nil)))
                    ids.append(id)
                }
            }
            children[container] = ids
        }
        return (children, nodes, albumObjects)
    }

    /// 켤 때 바로 보여 줄 목록 (work 줄에서만): 사진 앱 앨범 구조·표지와 사진 앱에서 바로 읽는 목록(보관함·앨범·
    /// 동영상·즐겨찾기 — 진짜 목록), 그리고 지난번 전체 목록에서 저장해 둔 자동 분류 앨범(이름·표지).
    /// 보관함 전체를 훑지 않아서 사진 수와 상관없이 빠름. 자동 분류 앨범과 미분류는 임시 (provisional)
    private func quickBuild() -> Snapshot {
        let (children, nodes, albumObjects) = readStructure()
        var items: [String: AssetList] = [:]
        var covers: [String: PHAsset] = [:]
        var userFolders: [Folder] = []
        for (id, album) in albumObjects {
            // 사진 앱의 대표 사진. 없으면 목록의 가장 최근 사진 (Snapshot.cover)
            let keyAssets: PHFetchResult<PHAsset>? = PHAsset.fetchKeyAssets(in: album, options: nil)
            if let key = keyAssets?.firstObject {
                covers[id] = key
            }
            // 사진 목록은 사진 앱에서 바로 읽는 것이라 만들어도 빠름 (장수도 처음부터 맞음)
            items[id] = albumList(id, album).list
            if let node = nodes[id] { userFolders.append(node) }
        }
        dropHeldAlbums(except: Set(albumObjects.map { $0.id }))
        userFolders.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        let system = systemLists()
        items["all"] = system.all.list

        var folders: [Folder] = []
        // 미분류와 자동 분류 앨범은 전체 목록이 올 때까지 임시
        var provisional: Set<String> = ["unsorted"]
        let summary = loadAutoSummary()
        let coverIDs = summary.compactMap { $0.cover }
        var found: [String: PHAsset] = [:]
        if !coverIDs.isEmpty {
            PHAsset.fetchAssets(withLocalIdentifiers: coverIDs, options: nil).enumerateObjects { asset, _, _ in
                found[asset.localIdentifier] = asset
            }
        }
        for entry in summary {
            guard let section = Folder.Section(rawValue: entry.section), section != .user else { continue }
            if entry.id == "videos" || entry.id == "favorites" {
                // 동영상·즐겨찾기는 사진 앱에서 바로 읽는 진짜 목록 (임시 아님)
                let real = entry.id == "videos" ? system.videos : system.favorites
                guard !real.isEmpty else { continue }
                items[entry.id] = real
            } else if let coverID = entry.cover {
                // 표지 사진이 없어졌으면 그 앨범은 전체 목록이 올 때까지 뺌
                guard let asset = found[coverID] else { continue }
                items[entry.id] = AssetList(array: [asset], version: 0)
                provisional.insert(entry.id)
            } else {
                items[entry.id] = .empty
                provisional.insert(entry.id)
            }
            folders.append(Folder(id: entry.id, title: entry.title, symbol: entry.symbol, section: section))
        }
        folders.append(contentsOf: userFolders)
        return Snapshot(folders: folders, items: items, children: children, nodes: nodes, covers: covers,
                        pending: 0, total: system.all.list.count, loaded: true, provisional: provisional)
    }

    // MARK: - 자동 분류 앨범 요약 (다음 실행 때 임시 목록에 씀. 앨범 ID·이름·기호·구역·표지 사진 ID 만)

    private struct AutoSummary: Codable, Equatable {
        let id: String
        let title: String
        let symbol: String
        let section: Int
        let cover: String?
    }

    private static let summaryURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("auto-folders-v1.json")
    }()

    /// 마지막으로 저장한 요약 (work 줄에서만). 같으면 다시 쓰지 않음
    private var savedSummary: [AutoSummary]?

    private func loadAutoSummary() -> [AutoSummary] {
        guard let data = try? Data(contentsOf: Library.summaryURL),
              let list = try? JSONDecoder().decode([AutoSummary].self, from: data) else { return [] }
        savedSummary = list
        return list
    }

    private func saveAutoSummary(_ snap: Snapshot) {
        let list = snap.autoFolders.map { folder in
            AutoSummary(id: folder.id, title: folder.title, symbol: folder.symbol, section: folder.section.rawValue,
                        cover: snap.items[folder.id]?.first?.localIdentifier)
        }
        guard list != savedSummary, let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: Library.summaryURL, options: .atomic)
        savedSummary = list
    }

    private func build(hideMoved: Bool) -> (Snapshot, [PHAsset]) {
        // 보관함·동영상·즐겨찾기·사진 앱 앨범은 들고 있는 목록 그대로 (사진 보관함이 안 바뀌었으면 같은 version)
        let system = systemLists()
        var items: [String: AssetList] = [:]

        // 사진 앱의 앨범·폴더 구조를 그대로 읽음 (사진 앱에서 묶어 둔 폴더가 그대로 폴더)
        let (children, nodes, albumObjects) = readStructure()

        var moved = Set<String>()
        var userFolders: [Folder] = []
        var covers: [String: PHAsset] = [:]
        for (id, album) in albumObjects {
            // 사진 앱이 앨범 표지로 쓰는 사진 (순정 카드와 같은 사진이 나오게)
            let keyAssets: PHFetchResult<PHAsset>? = PHAsset.fetchKeyAssets(in: album, options: nil)
            if let key = keyAssets?.firstObject {
                covers[id] = key
            }
            let inAlbum = albumList(id, album)
            // 앨범에 든 사진은 자동 분류에서 뺄 수 있게 기억 (이 work 줄에서만 훑음)
            inAlbum.result.enumerateObjects { asset, _, _ in
                moved.insert(asset.localIdentifier)
            }
            items[id] = inAlbum.list
            if let node = nodes[id] { userFolders.append(node) }
        }
        dropHeldAlbums(except: Set(albumObjects.map { $0.id }))
        userFolders.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        var camera: [PHAsset] = [], screenshots: [PHAsset] = [], recordings: [PHAsset] = []
        var saved: [PHAsset] = [], unsorted: [PHAsset] = []
        var apps: [String: [PHAsset]] = [:]
        var pending: [PHAsset] = []
        let cache = classifier.snapshotCache()

        system.all.result.enumerateObjects { asset, _, _ in
            let inAlbum = moved.contains(asset.localIdentifier)
            if !inAlbum { unsorted.append(asset) }
            let hidden = hideMoved && inAlbum
            if asset.mediaSubtypes.contains(.photoScreenshot) {
                if !hidden { screenshots.append(asset) }
                return
            }
            guard let entry = cache[asset.localIdentifier] else {
                pending.append(asset)
                return
            }
            if hidden { return }
            switch entry.cat {
            case .camera:
                camera.append(asset)
            case .recording:
                recordings.append(asset)
            case .saved:
                // 갤럭시처럼 저장한 앱마다 앨범 하나. 앱을 모르는 것만 '저장한 사진'
                if let app = entry.app {
                    apps[app, default: []].append(asset)
                } else {
                    saved.append(asset)
                }
            }
        }

        var folders: [Folder] = []
        func add(_ id: String, _ title: String, _ symbol: String, _ list: AssetList, always: Bool = true) {
            guard always || !list.isEmpty else { return }
            folders.append(Folder(id: id, title: title, symbol: symbol, section: .auto))
            items[id] = list
        }
        // 자동 분류는 배열 목록 (차례·version 을 여기서 같이 만듦)
        add("camera", "카메라", "camera", AssetList.make(camera))
        add("screenshots", "스크린샷", "camera.viewfinder", AssetList.make(screenshots))
        add("saved", "저장한 사진", "square.and.arrow.down", AssetList.make(saved))
        add("recordings", "화면 녹화", "record.circle", AssetList.make(recordings), always: false)
        // 동영상·즐겨찾기는 사진 앱에서 바로 (예전처럼 앨범에 넣었는지와 상관없이 전부)
        add("videos", "동영상", "video", system.videos, always: false)
        add("favorites", "즐겨찾기", "heart", system.favorites, always: false)
        items["all"] = system.all.list                // 보관함 탭
        items["unsorted"] = AssetList.make(unsorted)  // 미분류 탭

        let appOrder = apps.sorted { a, b in
            a.value.count != b.value.count ? a.value.count > b.value.count : a.key < b.key
        }
        for (name, list) in appOrder {
            let folder = Folder(id: "app:" + name, title: name, symbol: "app", section: .apps)
            folders.append(folder)
            items[folder.id] = AssetList.make(list)
        }
        folders.append(contentsOf: userFolders)

        let snap = Snapshot(folders: folders, items: items, children: children, nodes: nodes, covers: covers,
                            pending: pending.count, total: system.all.result.count, loaded: true)
        return (snap, pending)
    }

    // MARK: - 바꾸기 (전부 사진 보관함에 직접 반영, 끝나면 메인 줄에서 알림)

    private func change(_ changes: @escaping () -> Void, completion: ((Bool) -> Void)?) {
        PHPhotoLibrary.shared().performChanges(changes) { ok, _ in
            DispatchQueue.main.async { completion?(ok) }
        }
    }

    func album(id: String) -> PHAssetCollection? {
        PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject
    }

    func list(id: String) -> PHCollectionList? {
        PHCollectionList.fetchCollectionLists(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// 앨범·폴더 ID("album:…", "list:…")로 사진 앱의 실제 모음을 찾음
    private func collection(for folderID: String) -> PHCollection? {
        if folderID.hasPrefix(Folder.albumPrefix) {
            return album(id: String(folderID.dropFirst(Folder.albumPrefix.count)))
        }
        if folderID.hasPrefix(Folder.listPrefix) {
            return list(id: String(folderID.dropFirst(Folder.listPrefix.count)))
        }
        return nil
    }

    /// 폴더 안의 것들(사진 앱 순서). container 는 "top" 또는 "list:…"
    private func childFetch(of container: String) -> (list: PHCollectionList?, result: PHFetchResult<PHCollection>)? {
        if container == Snapshot.top {
            return (nil, PHCollection.fetchTopLevelUserCollections(with: nil))
        }
        guard let parent = collection(for: container) as? PHCollectionList else { return nil }
        return (parent, PHCollection.fetchCollections(in: parent, options: nil))
    }

    private func listRequest(for container: String) -> PHCollectionListChangeRequest? {
        guard let fetch = childFetch(of: container) else { return nil }
        if let parent = fetch.list {
            return PHCollectionListChangeRequest(for: parent, childCollections: fetch.result)
        }
        return PHCollectionListChangeRequest(forTopLevelCollectionListUserCollections: fetch.result)
    }

    /// 지우기 — iOS 가 확인 창을 한 번 띄움. 지운 사진은 '최근 삭제된 항목'으로
    func delete(_ assets: [PHAsset], completion: ((Bool) -> Void)? = nil) {
        change({ PHAssetChangeRequest.deleteAssets(assets as NSArray) }, completion: completion)
    }

    /// 옮기기 — 대상 앨범에 넣고, 앨범에서 온 거면 원래 앨범에서 뺌(사진은 안 지워짐)
    func move(_ assets: [PHAsset], to album: PHAssetCollection, from source: PHAssetCollection?, completion: ((Bool) -> Void)? = nil) {
        change({
            PHAssetCollectionChangeRequest(for: album)?.addAssets(assets as NSArray)
            if let source, source.localIdentifier != album.localIdentifier {
                PHAssetCollectionChangeRequest(for: source)?.removeAssets(assets as NSArray)
            }
        }, completion: completion)
    }

    /// 복사 — 원래 자리는 그대로 두고 대상 앨범에도 넣음 (파일이 늘지는 않음)
    func copy(_ assets: [PHAsset], to album: PHAssetCollection, completion: ((Bool) -> Void)? = nil) {
        change({ PHAssetCollectionChangeRequest(for: album)?.addAssets(assets as NSArray) }, completion: completion)
    }

    func setFavorite(_ asset: PHAsset, _ on: Bool, completion: ((Bool) -> Void)? = nil) {
        change({ PHAssetChangeRequest(for: asset).isFavorite = on }, completion: completion)
    }

    /// 찍은 날짜·시간 바꾸기 (정보 화면의 '조정'). iOS 가 확인 창을 한 번 띄움
    func setCreationDate(_ asset: PHAsset, _ date: Date, completion: ((Bool) -> Void)? = nil) {
        change({ PHAssetChangeRequest(for: asset).creationDate = date }, completion: completion)
    }

    /// 앨범 만들기. container 가 폴더면 그 안에 만듦
    func createAlbum(title: String, in container: String = Snapshot.top, adding assets: [PHAsset] = [],
                     from source: PHAssetCollection? = nil, completion: ((Bool) -> Void)? = nil) {
        change({
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            if !assets.isEmpty {
                request.addAssets(assets as NSArray)
                if let source {
                    PHAssetCollectionChangeRequest(for: source)?.removeAssets(assets as NSArray)
                }
            }
            if container != Snapshot.top, let parent = self.collection(for: container) as? PHCollectionList {
                PHCollectionListChangeRequest(for: parent)?.addChildCollections([request.placeholderForCreatedAssetCollection] as NSArray)
            }
        }, completion: completion)
    }

    /// 폴더 만들기 (사진 앱의 폴더). members 를 주면 만들면서 그 안으로 옮김
    func createFolder(title: String, in container: String = Snapshot.top, members: [String] = [], completion: ((Bool) -> Void)? = nil) {
        change({
            let request = PHCollectionListChangeRequest.creationRequestForCollectionList(withTitle: title)
            if container != Snapshot.top, let parent = self.collection(for: container) as? PHCollectionList {
                PHCollectionListChangeRequest(for: parent)?.addChildCollections([request.placeholderForCreatedCollectionList] as NSArray)
            }
            let moving = members.compactMap { self.collection(for: $0) }
            if !moving.isEmpty {
                request.addChildCollections(moving as NSArray)
            }
        }, completion: completion)
    }

    /// 앨범·폴더를 다른 폴더 안으로(container = "list:…") 또는 맨 바깥으로("top") 옮김
    func moveCollection(_ folderID: String, into container: String, completion: ((Bool) -> Void)? = nil) {
        change({
            guard let item = self.collection(for: folderID) else { return }
            if container == Snapshot.top {
                self.listRequest(for: Snapshot.top)?.addChildCollections([item] as NSArray)
            } else if let parent = self.collection(for: container) as? PHCollectionList {
                PHCollectionListChangeRequest(for: parent)?.addChildCollections([item] as NSArray)
            }
        }, completion: completion)
    }

    /// 같은 화면 안에서 순서 바꾸기 (사진 앱의 '사용자 설정 순'에 그대로 반영)
    func reorder(in container: String, from: Int, to: Int, completion: ((Bool) -> Void)? = nil) {
        change({
            self.listRequest(for: container)?.moveChildCollections(at: IndexSet(integer: from), to: to)
        }, completion: completion)
    }

    /// 앨범에서만 빼기 (사진은 남음)
    func remove(_ assets: [PHAsset], from album: PHAssetCollection, completion: ((Bool) -> Void)? = nil) {
        change({ PHAssetCollectionChangeRequest(for: album)?.removeAssets(assets as NSArray) }, completion: completion)
    }

    func rename(_ folderID: String, to title: String, completion: ((Bool) -> Void)? = nil) {
        change({
            if let album = self.collection(for: folderID) as? PHAssetCollection {
                let request = PHAssetCollectionChangeRequest(for: album)
                request?.title = title
            } else if let list = self.collection(for: folderID) as? PHCollectionList {
                let request = PHCollectionListChangeRequest(for: list)
                request?.title = title
            }
        }, completion: completion)
    }

    /// 앨범이나 폴더를 지움 (사진은 남음. 폴더를 지우면 안의 앨범도 같이 지워짐)
    func deleteCollection(_ folderID: String, completion: ((Bool) -> Void)? = nil) {
        change({
            if let album = self.collection(for: folderID) as? PHAssetCollection {
                PHAssetCollectionChangeRequest.deleteAssetCollections([album] as NSArray)
            } else if let list = self.collection(for: folderID) as? PHCollectionList {
                PHCollectionListChangeRequest.deleteCollectionLists([list] as NSArray)
            }
        }, completion: completion)
    }

    // MARK: - 진단 (사진 내용·파일 이름·앨범 이름은 안 넣음. 장수와 판별 통계만)

    func diagnostics() -> String {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String ?? "?") + " (" + (info?["CFBundleVersion"] as? String ?? "?") + ")"
        let lists = snapshot.nodes.values.filter { $0.isGroup }.count
        let albums = snapshot.nodes.values.filter { $0.isUser }.count
        var lines = [
            "[갤러리 진단] \(version) iOS \(UIDevice.current.systemVersion)",
            "권한: \(status.rawValue)  전체 \(snapshot.total)  분류 대기 \(snapshot.pending)",
            "사진 앱 앨범 \(albums)개 · 폴더 \(lists)개 · 맨 바깥 \(snapshot.children[Snapshot.top]?.count ?? 0)개 · 미분류 \(snapshot.items["unsorted"]?.count ?? 0)장",
            "출처 정보: \(ImportProbe.state)",
            "자동 분류:",
        ]
        for folder in snapshot.autoFolders {
            lines.append("  \(snapshot.items[folder.id]?.count ?? 0)  \(folder.title)")
        }
        lines.append("판별 통계(이번 실행):")
        lines.append(classifier.statsText())
        return lines.joined(separator: "\n")
    }
}

enum Thumbs {
    static let manager = PHCachingImageManager()
    static let options: PHImageRequestOptions = {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        return options
    }()
}
