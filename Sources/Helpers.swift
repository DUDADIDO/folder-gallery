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

// MARK: - 옮기기

/// 내 폴더 고르기 시트
final class FolderPickerViewController: UITableViewController {
    private let excludeAlbumID: String?
    private var folders: [Folder] = []
    var onPick: ((PHAssetCollection) -> Void)?
    var onCreate: ((String) -> Void)?

    init(excludeAlbumID: String?) {
        self.excludeAlbumID = excludeAlbumID
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "폴더로 옮기기"
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
        section == 1 && !folders.isEmpty ? "내 폴더" : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            content.text = "새 폴더 만들기"
            content.image = UIImage(systemName: "folder.badge.plus")
        } else {
            let folder = folders[indexPath.row]
            content.text = folder.title
            content.secondaryText = "\(Library.shared.snapshot.items[folder.id]?.count ?? 0)장"
            content.image = UIImage(systemName: "folder")
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            promptText(title: "새 폴더", placeholder: "폴더 이름", confirm: "만들기") { [weak self] name in
                self?.onCreate?(name)
            }
        } else if let id = folders[indexPath.row].albumID, let album = Library.shared.album(id: id) {
            onPick?(album)
        }
    }
}

enum Mover {
    /// 고른 사진을 내 폴더로 옮기는 시트를 띄움. 끝나면 done(성공 여부)
    static func present(from host: UIViewController, assets: [PHAsset], sourceAlbumID: String?, done: @escaping (Bool) -> Void) {
        guard !assets.isEmpty else { return }
        let source = sourceAlbumID.flatMap { Library.shared.album(id: $0) }
        let picker = FolderPickerViewController(excludeAlbumID: sourceAlbumID)
        picker.onPick = { [weak host] album in
            host?.dismiss(animated: true)
            Library.shared.move(assets, to: album, from: source) { ok in
                host?.toast(ok ? "\(assets.count)장을 '\(album.localizedTitle ?? "")'(으)로 옮겼어요" : "옮기지 못했어요")
                done(ok)
            }
        }
        picker.onCreate = { [weak host] name in
            host?.dismiss(animated: true)
            Library.shared.createAlbum(title: name, adding: assets, from: source) { ok in
                host?.toast(ok ? "'\(name)' 폴더를 만들고 \(assets.count)장을 옮겼어요" : "폴더를 만들지 못했어요")
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
