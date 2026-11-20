import Photos
import UIKit

final class Flag {
    var on = false
}

extension UIViewController {
    /// 글자 입력 창 (폴더 이름 등)
    func promptText(title: String, message: String? = nil, initial: String = "", placeholder: String = "",
                    confirm: String = "확인", done: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = initial
            field.placeholder = placeholder
            field.clearButtonMode = .whileEditing
            field.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: confirm, style: .default) { [weak alert] _ in
            let text = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { done(text) }
        })
        present(alert, animated: true)
    }

    func confirm(title: String, message: String?, action: String, destructive: Bool = true, done: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: action, style: destructive ? .destructive : .default) { _ in done() })
        present(alert, animated: true)
    }

    /// 잠깐 떴다 사라지는 안내
    func toast(_ text: String) {
        let host: UIView = view.window ?? view
        let label = PaddedLabel()
        label.text = text
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.layer.cornerRadius = 14
        label.layer.masksToBounds = true
        label.alpha = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor, constant: -72),
            label.widthAnchor.constraint(lessThanOrEqualTo: host.widthAnchor, constant: -48),
        ])
        UIView.animate(withDuration: 0.2, animations: { label.alpha = 1 }, completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 1.6, options: [], animations: { label.alpha = 0 }, completion: { _ in
                label.removeFromSuperview()
            })
        })
    }
}

final class PaddedLabel: UILabel {
    private let insets = UIEdgeInsets(top: 9, left: 16, bottom: 9, right: 16)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}

// MARK: - 앨범으로 이동 · 복사

enum Prefs {
    private static let defaults = UserDefaults.standard

    /// 사진 격자 칸 수
    static var gridColumns: Int {
        get { defaults.integer(forKey: "gridColumns") }
        set { defaults.set(newValue, forKey: "gridColumns") }
    }

    /// 앨범 안 사진 격자 칸 수 (순정처럼 기본 5. 보관함·미분류 탭은 gridColumns)
    static var albumGridColumns: Int {
        get {
            let value = defaults.integer(forKey: "albumGridColumns")
            return value > 0 ? value : 3   // 순정 iOS 27 앨범 기본 3칸
        }
        set { defaults.set(newValue, forKey: "albumGridColumns") }
    }

    /// 최신 항목 순으로 보는 앨범 ID (나머지는 순정처럼 오래된 항목 순)
    /// 화면(폴더 ID)마다 정렬 (GridSort 의 rawValue)
    static var gridSorts: [String: String] {
        get { defaults.dictionary(forKey: "gridSorts") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "gridSorts") }
    }

    static var newestFirstAlbums: Set<String> {
        get { Set(defaults.stringArray(forKey: "newestFirstAlbums") ?? []) }
        set { defaults.set(Array(newValue), forKey: "newestFirstAlbums") }
    }

    /// 'Live 끔' 으로 둔 사진 ID (사진 자체는 안 바꾸고 이 앱에서만)
    static var liveOffAssets: Set<String> {
        get { Set(defaults.stringArray(forKey: "liveOffAssets") ?? []) }
        set { defaults.set(Array(newValue), forKey: "liveOffAssets") }
    }

    /// 앨범 격자 칸 수 (기본 3)
    static var albumColumns: Int {
        get {
            let value = defaults.integer(forKey: "albumColumns")
            return (2...4).contains(value) ? value : 3
        }
        set { defaults.set(newValue, forKey: "albumColumns") }
    }

    /// 앨범 정렬: 0 기본, 1 이름, 2 장수 많은 순
    static var albumSort: Int {
        get { defaults.integer(forKey: "albumSort") }
        set { defaults.set(newValue, forKey: "albumSort") }
    }

    /// 숨긴 앨범 ID
    static var hiddenAlbums: Set<String> {
        get { Set(defaults.stringArray(forKey: "hiddenAlbums") ?? []) }
        set { defaults.set(Array(newValue), forKey: "hiddenAlbums") }
    }
}

/// 내 앨범 고르기 시트
final class FolderPickerViewController: UITableViewController {
    private let excludeAlbumID: String?
    private var folders: [Folder] = []
    var onPick: ((PHAssetCollection) -> Void)?
    var onCreate: ((String) -> Void)?

    init(title: String, excludeAlbumID: String?) {
        self.excludeAlbumID = excludeAlbumID
        super.init(style: .insetGrouped)
        self.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(close))
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        folders = Library.shared.snapshot.folders.filter { $0.isUser && $0.albumID != excludeAlbumID }
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : folders.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 1 && !folders.isEmpty ? "내 앨범" : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            content.text = "앨범 만들기"
            content.image = UIImage(systemName: "plus.rectangle.on.folder")
        } else {
            let folder = folders[indexPath.row]
            let snapshot = Library.shared.snapshot
            let count = snapshot.items[folder.id]?.count ?? 0
            content.text = folder.title
            // 켤 때의 임시 목록이면 장수를 모름 (사진 앱 앨범은 처음부터 진짜 목록이라 보통 나옴)
            content.secondaryText = snapshot.isProvisional(folder.id) ? nil : String(count)
            content.image = UIImage(systemName: "folder")
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            promptText(title: "앨범 만들기", placeholder: "앨범 이름", confirm: "만들기") { [weak self] name in
                self?.onCreate?(name)
            }
        } else if let id = folders[indexPath.row].albumID, let album = Library.shared.album(id: id) {
            onPick?(album)
        }
    }
}

enum Mover {
    /// 고른 사진을 내 앨범으로 이동(copy: false)하거나 복사(copy: true)하는 시트. 끝나면 done(성공 여부)
    static func present(from host: UIViewController, assets: [PHAsset], sourceAlbumID: String?, copy: Bool,
                        done: @escaping (Bool) -> Void) {
        guard !assets.isEmpty else { return }
        // 복사는 원래 앨범에서 빼지 않음
        let source: PHAssetCollection? = copy ? nil : sourceAlbumID.flatMap { Library.shared.album(id: $0) }
        let verb = copy ? "복사" : "이동"
        let count = assets.count
        let picker = FolderPickerViewController(title: "앨범으로 " + verb, excludeAlbumID: sourceAlbumID)
        picker.onPick = { [weak host] album in
            host?.dismiss(animated: true)
            let name = album.localizedTitle ?? ""
            let finish: (Bool) -> Void = { ok in
                host?.toast(ok ? "\(count)장을 '\(name)' 앨범으로 \(verb)했어요" : "\(verb)하지 못했어요")
                done(ok)
            }
            if copy {
                Library.shared.copy(assets, to: album, completion: finish)
            } else {
                Library.shared.move(assets, to: album, from: source, completion: finish)
            }
        }
        picker.onCreate = { [weak host] name in
            host?.dismiss(animated: true)
            Library.shared.createAlbum(title: name, adding: assets, from: source) { ok in
                host?.toast(ok ? "'\(name)' 앨범을 만들고 \(count)장을 \(verb)했어요" : "앨범을 만들지 못했어요")
                done(ok)
            }
        }
        let nav = UINavigationController(rootViewController: picker)
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        host.present(nav, animated: true)
    }
}

// MARK: - 공유

enum Sharer {
    /// 원본 파일을 임시 폴더에 꺼낸 뒤 공유 시트를 띄움
    static func share(_ assets: [PHAsset], from host: UIViewController, barButtonItem: UIBarButtonItem?) {
        guard !assets.isEmpty else { return }
        let total = assets.count
        let cancelled = Flag()
        let progress = UIAlertController(title: "공유 준비 중", message: "0 / \(total)", preferredStyle: .alert)
        progress.addAction(UIAlertAction(title: "취소", style: .cancel) { _ in cancelled.on = true })
        // 알림창이 다 뜬 뒤에 시작 (뜨는 도중에 닫으면 닫기가 무시될 수 있음)
        host.present(progress, animated: true) {
            DispatchQueue.global(qos: .userInitiated).async {
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("share", isDirectory: true)
                try? FileManager.default.removeItem(at: root)
                var urls: [URL] = []
                for (index, asset) in assets.enumerated() {
                    if cancelled.on { break }
                    let dir = root.appendingPathComponent(String(index), isDirectory: true)
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    if let url = export(asset, to: dir) { urls.append(url) }
                    DispatchQueue.main.async { progress.message = "\(index + 1) / \(total)" }
                }
                let result = urls
                DispatchQueue.main.async {
                    if cancelled.on { return }
                    progress.dismiss(animated: true) {
                        present(result, from: host, barButtonItem: barButtonItem)
                    }
                }
            }
        }
    }

    private static func present(_ urls: [URL], from host: UIViewController, barButtonItem: UIBarButtonItem?) {
        guard !urls.isEmpty else {
            host.toast("공유할 파일을 준비하지 못했어요")
            return
        }
        let sheet = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        if let popover = sheet.popoverPresentationController {
            if let barButtonItem {
                popover.barButtonItem = barButtonItem
            } else {
                popover.sourceView = host.view
                popover.sourceRect = CGRect(x: host.view.bounds.midX, y: host.view.bounds.maxY - 60, width: 1, height: 1)
            }
        }
        host.present(sheet, animated: true)
    }

    private static func export(_ asset: PHAsset, to dir: URL) -> URL? {
        let resources = PHAssetResource.assetResources(for: asset)
        let isVideo = asset.mediaType == .video
        let originalType: PHAssetResourceType = isVideo ? .video : .photo
        let editedType: PHAssetResourceType = isVideo ? .fullSizeVideo : .fullSizePhoto
        let original = resources.first { $0.type == originalType }
        // 편집한 사진은 편집본을 보냄
        let edited = resources.first { $0.type == editedType }
        guard let resource = edited ?? original ?? resources.first else { return nil }

        var name = original?.originalFilename ?? resource.originalFilename
        if resource.originalFilename != name {
            let base = (name as NSString).deletingPathExtension
            let ext = (resource.originalFilename as NSString).pathExtension
            name = ext.isEmpty ? base : base + "." + ext
        }
        if name.isEmpty { name = isVideo ? "video.mov" : "photo.jpg" }
        let url = dir.appendingPathComponent(name)

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        let ok = Flag()
        let done = DispatchSemaphore(value: 0)
        PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
            ok.on = (error == nil)
            done.signal()
        }
        // iCloud 에만 있는 원본을 못 받아 오면 끝없이 기다리지 않게
        if done.wait(timeout: .now() + 120) == .timedOut { return nil }
        return ok.on ? url : nil
    }
}

/// 확대 전환(iOS 18) 끌기의 위치·속도를 CGPoint 로.
/// UIZoomTransitionInteractionContext.velocity 가 SDK 에 따라 CGVector 일 수도 CGPoint 일 수도 있어서 둘 다 받음
enum ZoomGesture {
    static func point(_ value: CGVector) -> CGPoint { CGPoint(x: value.dx, y: value.dy) }
    static func point(_ value: CGPoint) -> CGPoint { value }

    /// 분명히 아래로 끄는 중인지 (옆으로 넘기기는 절대 아님)
    static func isDownward(_ velocity: CGPoint) -> Bool {
        velocity.y > 0 && velocity.y >= abs(velocity.x) * 1.5
    }
}

/// '밀어서 뒤로'를 막고 있는 화면들 (화면마다 따로 기억해서, 한 화면이 풀어도 다른 화면이 막은 건 그대로)
private final class BackSwipeBlockers {
    /// 막은 화면(약하게 잡음) → 막은 정도
    let table = NSMapTable<AnyObject, NSNumber>.weakToStrongObjects()
}

private var backSwipeBlockersKey: UInt8 = 0

extension UINavigationController {
    enum BackSwipeBlock: Int {
        /// iOS 26 의 '화면 어디서나 밀어서 뒤로'만 막음 (왼쪽 가장자리에서 밀기는 그대로)
        case anywhere = 1
        /// 가장자리 + 어디서나 둘 다 막음
        case all = 2
    }

    /// owner 가 '밀어서 뒤로'를 막거나(kind) 풀어 줌(nil). 막은 화면이 하나도 없을 때만 다시 켜짐
    func setBackSwipe(blocked kind: BackSwipeBlock?, by owner: AnyObject) {
        let blockers: BackSwipeBlockers
        if let existing = objc_getAssociatedObject(self, &backSwipeBlockersKey) as? BackSwipeBlockers {
            blockers = existing
        } else {
            blockers = BackSwipeBlockers()
            objc_setAssociatedObject(self, &backSwipeBlockersKey, blockers, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        if let kind {
            blockers.table.setObject(NSNumber(value: kind.rawValue), forKey: owner)
        } else {
            blockers.table.removeObject(forKey: owner)
        }
        var strongest = 0
        for key in blockers.table.keyEnumerator().allObjects {
            if let value = blockers.table.object(forKey: key as AnyObject) {
                strongest = max(strongest, value.intValue)
            }
        }
        interactivePopGestureRecognizer?.isEnabled = strongest < BackSwipeBlock.all.rawValue
        // iOS 26 에만 있는 것이라 예전 SDK 로도 빌드되게 이름으로 찾음
        let contentPop = NSSelectorFromString("interactiveContentPopGestureRecognizer")
        if responds(to: contentPop), let recognizer = perform(contentPop)?.takeUnretainedValue() as? UIGestureRecognizer {
            recognizer.isEnabled = strongest < BackSwipeBlock.anywhere.rawValue
        }
    }

    /// 둘러보는 화면(격자·앨범 목록)이 다 보인 뒤의 안전장치: 아래 막대는 숨기고 탭 막대는 보이게.
    /// 이미 맞으면 아무것도 안 함. screen 이 맨 위가 아니거나, 탭 막대를 스스로 숨기는 화면이 쌓여 있으면 건드리지 않음
    func ensureBrowsingBars(of screen: UIViewController) {
        guard topViewController === screen else { return }
        if !isToolbarHidden { setToolbarHidden(true, animated: false) }
        guard !viewControllers.contains(where: { $0.hidesBottomBarWhenPushed }) else { return }
        if #available(iOS 18.0, *), let tabs = tabBarController, tabs.isTabBarHidden {
            tabs.setTabBarHidden(false, animated: false)
        }
    }
}
