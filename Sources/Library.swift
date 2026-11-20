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
    /// 앨범 ID → 사진(최신순). "all" = 보관함, "unsorted" = 어느 앨범에도 없는 사진
    var items: [String: [PHAsset]] = [:]
    /// 사진 앱의 앨범·폴더 구조. "top" 또는 폴더 ID → 안에 든 것(사진 앱에서 정한 순서)
    var children: [String: [String]] = [:]
    /// 사진 앱의 앨범·폴더
    var nodes: [String: Folder] = [:]
    /// 사진 앱 앨범 ID → 대표 사진 (사진 앱이 정한 것)
    var covers: [String: PHAsset] = [:]
    var pending = 0
    var total = 0
    var loaded = false

    static let top = "top"

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
    private var rebuildScheduled = false
    private var started = false

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
        scheduleRebuild()
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { self.scheduleRebuild() }
    }

    func scheduleRebuild() {
        guard canRead, !rebuildScheduled else { return }
        rebuildScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.rebuildScheduled = false
            let hide = self.hideMoved
            self.work.async {
                let (snap, pending) = self.build(hideMoved: hide)
                DispatchQueue.main.async {
                    self.snapshot = snap
                    NotificationCenter.default.post(name: Library.didChange, object: nil)
                }
                self.classifier.enqueue(pending)
            }
        }
    }

    private func build(hideMoved: Bool) -> (Snapshot, [PHAsset]) {
        let newestFirst = PHFetchOptions()
        newestFirst.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let fetched = PHAsset.fetchAssets(with: newestFirst)
        var all: [PHAsset] = []
        all.reserveCapacity(fetched.count)
        fetched.enumerateObjects { asset, _, _ in all.append(asset) }

        var items: [String: [PHAsset]] = [:]

        // 사진 앱의 앨범·폴더 구조를 그대로 읽음 (사진 앱에서 묶어 둔 폴더가 그대로 폴더)
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

        var moved = Set<String>()
        var userFolders: [Folder] = []
        var covers: [String: PHAsset] = [:]
        for (id, album) in albumObjects {
            // 사진 앱이 앨범 표지로 쓰는 사진 (순정 카드와 같은 사진이 나오게)
            let keyAssets: PHFetchResult<PHAsset>? = PHAsset.fetchKeyAssets(in: album, options: nil)
            if let key = keyAssets?.firstObject {
                covers[id] = key
            }
            let inAlbum = PHAsset.fetchAssets(in: album, options: newestFirst)
            var list: [PHAsset] = []
            list.reserveCapacity(inAlbum.count)
            inAlbum.enumerateObjects { asset, _, _ in
                list.append(asset)
                moved.insert(asset.localIdentifier)
            }
            items[id] = list
            if let node = nodes[id] { userFolders.append(node) }
        }
        userFolders.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        var camera: [PHAsset] = [], screenshots: [PHAsset] = [], recordings: [PHAsset] = []
        var saved: [PHAsset] = [], videos: [PHAsset] = [], favorites: [PHAsset] = [], unsorted: [PHAsset] = []
        var apps: [String: [PHAsset]] = [:]
        var pending: [PHAsset] = []
        let cache = classifier.snapshotCache()

        for asset in all {
            if asset.mediaType == .video { videos.append(asset) }
            if asset.isFavorite { favorites.append(asset) }
            let inAlbum = moved.contains(asset.localIdentifier)
            if !inAlbum { unsorted.append(asset) }
            let hidden = hideMoved && inAlbum
            if asset.mediaSubtypes.contains(.photoScreenshot) {
                if !hidden { screenshots.append(asset) }
                continue
            }
            guard let entry = cache[asset.localIdentifier] else {
                pending.append(asset)
                continue
            }
            if hidden { continue }
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
        func add(_ id: String, _ title: String, _ symbol: String, _ list: [PHAsset], always: Bool = true) {
            guard always || !list.isEmpty else { return }
            folders.append(Folder(id: id, title: title, symbol: symbol, section: .auto))
            items[id] = list
        }
        add("camera", "카메라", "camera", camera)
        add("screenshots", "스크린샷", "camera.viewfinder", screenshots)
        add("saved", "저장한 사진", "square.and.arrow.down", saved)
        add("recordings", "화면 녹화", "record.circle", recordings, always: false)
        add("videos", "동영상", "video", videos, always: false)
        add("favorites", "즐겨찾기", "heart", favorites, always: false)
        items["all"] = all             // 보관함 탭
        items["unsorted"] = unsorted   // 미분류 탭

        let appOrder = apps.sorted { a, b in
            a.value.count != b.value.count ? a.value.count > b.value.count : a.key < b.key
        }
        for (name, list) in appOrder {
            let folder = Folder(id: "app:" + name, title: name, symbol: "app", section: .apps)
            folders.append(folder)
            items[folder.id] = list
        }
        folders.append(contentsOf: userFolders)

        let snap = Snapshot(folders: folders, items: items, children: children, nodes: nodes, covers: covers,
                            pending: pending.count, total: all.count, loaded: true)
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
