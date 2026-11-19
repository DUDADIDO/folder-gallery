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

    /// 앨범 묶음(그룹)인지
    var isGroup: Bool { id.hasPrefix(AlbumGroup.prefix) }
    /// 내가 만든 앨범(사진 앱 앨범)인지
    var isUser: Bool { section == .user && !isGroup }
    /// 내 폴더(사진 앱 앨범)일 때 앨범 ID
    var albumID: String? { isUser ? String(id.dropFirst("album:".count)) : nil }
}

struct Snapshot {
    var folders: [Folder] = []
    var items: [String: [PHAsset]] = [:]
    var pending = 0
    var total = 0
    var loaded = false
}

/// 사진 보관함을 읽어 폴더별 목록을 만들고, 바뀌면 알림
final class Library: NSObject, PHPhotoLibraryChangeObserver {
    static let shared = Library()
    static let didChange = Notification.Name("Library.didChange")

    private(set) var snapshot = Snapshot()                             // 메인 줄에서만
    private(set) var status: PHAuthorizationStatus = .notDetermined    // 메인 줄에서만
    let classifier = Classifier()

    private let work = DispatchQueue(label: "gallery.library", qos: .userInitiated)
    private var rebuildScheduled = false
    private var started = false

    /// 내 폴더로 옮긴 사진을 자동 폴더(카메라 등)에서 숨길지
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

        // 내 폴더 = 사진 앱의 일반 앨범
        var albums: [PHAssetCollection] = []
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
            .enumerateObjects { collection, _, _ in albums.append(collection) }
        albums.sort { ($0.localizedTitle ?? "").localizedStandardCompare($1.localizedTitle ?? "") == .orderedAscending }

        var userFolders: [Folder] = []
        var moved = Set<String>()
        for album in albums {
            let inAlbum = PHAsset.fetchAssets(in: album, options: newestFirst)
            var list: [PHAsset] = []
            list.reserveCapacity(inAlbum.count)
            inAlbum.enumerateObjects { asset, _, _ in
                list.append(asset)
                moved.insert(asset.localIdentifier)
            }
            let folder = Folder(id: "album:" + album.localIdentifier, title: album.localizedTitle ?? "이름 없음",
                                symbol: "folder", section: .user)
            userFolders.append(folder)
            items[folder.id] = list
        }

        var camera: [PHAsset] = [], screenshots: [PHAsset] = [], recordings: [PHAsset] = []
        var saved: [PHAsset] = [], videos: [PHAsset] = [], favorites: [PHAsset] = []
        var apps: [String: [PHAsset]] = [:]
        var pending: [PHAsset] = []
        let cache = classifier.snapshotCache()

        for asset in all {
            if asset.mediaType == .video { videos.append(asset) }
            if asset.isFavorite { favorites.append(asset) }
            let hidden = hideMoved && moved.contains(asset.localIdentifier)
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
        items["all"] = all   // 보관함 탭

        let appOrder = apps.sorted { a, b in
            a.value.count != b.value.count ? a.value.count > b.value.count : a.key < b.key
        }
        for (name, list) in appOrder {
            let folder = Folder(id: "app:" + name, title: name, symbol: "app", section: .apps)
            folders.append(folder)
            items[folder.id] = list
        }
        folders.append(contentsOf: userFolders)

        let snap = Snapshot(folders: folders, items: items, pending: pending.count, total: all.count, loaded: true)
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

    /// 지우기 — iOS 가 확인 창을 한 번 띄움. 지운 사진은 '최근 삭제된 항목'으로
    func delete(_ assets: [PHAsset], completion: ((Bool) -> Void)? = nil) {
        change({ PHAssetChangeRequest.deleteAssets(assets as NSArray) }, completion: completion)
    }

    /// 옮기기 — 대상 폴더에 넣고, 내 폴더에서 온 거면 원래 폴더에서 뺌(사진은 안 지워짐)
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

    func createAlbum(title: String, adding assets: [PHAsset] = [], from source: PHAssetCollection? = nil, completion: ((Bool) -> Void)? = nil) {
        change({
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            if !assets.isEmpty {
                request.addAssets(assets as NSArray)
                if let source {
                    PHAssetCollectionChangeRequest(for: source)?.removeAssets(assets as NSArray)
                }
            }
        }, completion: completion)
    }

    /// 폴더에서만 빼기 (사진은 남음)
    func remove(_ assets: [PHAsset], from album: PHAssetCollection, completion: ((Bool) -> Void)? = nil) {
        change({ PHAssetCollectionChangeRequest(for: album)?.removeAssets(assets as NSArray) }, completion: completion)
    }

    func rename(_ album: PHAssetCollection, to title: String, completion: ((Bool) -> Void)? = nil) {
        change({
            let request = PHAssetCollectionChangeRequest(for: album)
            request?.title = title
        }, completion: completion)
    }

    /// 폴더만 지움 (안의 사진은 남음)
    func deleteAlbum(_ album: PHAssetCollection, completion: ((Bool) -> Void)? = nil) {
        change({ PHAssetCollectionChangeRequest.deleteAssetCollections([album] as NSArray) }, completion: completion)
    }

    // MARK: - 진단 (사진 내용·파일 이름은 안 넣음. 장수와 판별 통계만)

    func diagnostics() -> String {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String ?? "?") + " (" + (info?["CFBundleVersion"] as? String ?? "?") + ")"
        var lines = [
            "[갤러리 진단] \(version) iOS \(UIDevice.current.systemVersion)",
            "권한: \(status.rawValue)  전체 \(snapshot.total)  분류 대기 \(snapshot.pending)",
            "출처 정보: \(ImportProbe.state)",
            "폴더:",
        ]
        for folder in snapshot.folders {
            let count = snapshot.items[folder.id]?.count ?? 0
            let name = folder.section == .user ? "(내 폴더)" : folder.title
            lines.append("  \(count)  \(name)")
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
