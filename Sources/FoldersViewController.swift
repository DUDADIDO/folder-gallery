import Photos
import UIKit

final class FolderCell: UICollectionViewCell {
    static let reuse = "FolderCell"

    let imageView = UIImageView()
    let iconView = UIImageView()
    let titleLabel = UILabel()
    let countLabel = UILabel()

    var assetID: String?
    var requestID: PHImageRequestID = PHInvalidImageRequestID

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.layer.cornerCurve = .continuous
        imageView.backgroundColor = .secondarySystemBackground
        imageView.translatesAutoresizingMaskIntoConstraints = false

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .tertiaryLabel
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabel
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(imageView)
        contentView.addSubview(iconView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(countLabel)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),

            iconView.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),

            countLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
            countLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            countLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if requestID != PHInvalidImageRequestID {
            Thumbs.manager.cancelImageRequest(requestID)
            requestID = PHInvalidImageRequestID
        }
        imageView.image = nil
        assetID = nil
    }
}

final class SectionHeaderView: UICollectionReusableView {
    static let reuse = "SectionHeaderView"

    let detail = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabel
        detail.translatesAutoresizingMaskIntoConstraints = false
        addSubview(detail)
        NSLayoutConstraint.activate([
            detail.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            detail.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// 앨범 탭. 갤럭시 갤러리처럼 카메라·스크린샷·저장한 앱별 앨범과 내가 만든 앨범을 한 격자에 보여 줌
final class FoldersViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {
    private var collectionView: UICollectionView!
    private var folders: [Folder] = []
    private var lastSignature: [String] = []
    private let messageView = UIView()
    private let messageLabel = UILabel()
    private let messageButton = UIButton(type: .system)
    private var warnedLimited = false
    private var thumbSize = CGSize(width: 500, height: 500)
    private var columns = Prefs.albumColumns

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "앨범"
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.backButtonTitle = "앨범"

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: makeLayout())
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(FolderCell.self, forCellWithReuseIdentifier: FolderCell.reuse)
        collectionView.register(SectionHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: SectionHeaderView.reuse)
        collectionView.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:))))
        view.addSubview(collectionView)

        setUpMessageView()
        refreshMenu()

        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: Library.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        reload(force: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
        // 숨기기 화면에서 돌아왔을 때 반영
        reload(force: false)
    }

    private func makeLayout() -> UICollectionViewLayout {
        let columns = self.columns
        return UICollectionViewCompositionalLayout { _, environment in
            // 칸 크기를 화면 너비에서 직접 계산
            let inset: CGFloat = 16
            let gap: CGFloat = 12
            let width = environment.container.effectiveContentSize.width
            let side = max(40, floor((width - inset * 2 - gap * CGFloat(columns - 1)) / CGFloat(columns)))
            let height = side + 44
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(side),
                                                                                 heightDimension: .absolute(height)))
            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(height))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            group.interItemSpacing = .fixed(gap)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 14
            section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: inset, bottom: 24, trailing: inset)
            let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(28))
            section.boundarySupplementaryItems = [
                NSCollectionLayoutBoundarySupplementaryItem(layoutSize: headerSize,
                                                            elementKind: UICollectionView.elementKindSectionHeader,
                                                            alignment: .top),
            ]
            return section
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let side = max(120, view.bounds.width / 2) * traitCollection.displayScale
        thumbSize = CGSize(width: side, height: side)
    }

    /// 벌리면 크게(2칸), 오므리면 작게(4칸)
    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .ended else { return }
        var next = columns
        if gesture.scale > 1.25 {
            next = max(2, columns - 1)
        } else if gesture.scale < 0.8 {
            next = min(4, columns + 1)
        }
        guard next != columns else { return }
        columns = next
        Prefs.albumColumns = next
        collectionView.setCollectionViewLayout(makeLayout(), animated: true)
    }

    // MARK: - 권한 안내

    private func setUpMessageView() {
        messageView.backgroundColor = .systemBackground
        messageView.frame = view.bounds
        messageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        messageView.isHidden = true
        view.addSubview(messageView)

        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.textColor = .secondaryLabel
        messageLabel.font = .systemFont(ofSize: 16)
        messageButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        messageButton.setTitle("설정 열기", for: .normal)
        messageButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [messageLabel, messageButton])
        stack.axis = .vertical
        stack.spacing = 18
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        messageView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: messageView.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: messageView.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: messageView.trailingAnchor, constant: -32),
        ])
    }

    @objc private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - 데이터

    @objc private func libraryChanged() {
        reload(force: false)
    }

    /// 숨긴 앨범을 빼고 정렬한 목록
    private func visibleFolders(_ snapshot: Snapshot) -> [Folder] {
        let hidden = Prefs.hiddenAlbums
        var list = snapshot.folders.filter { !hidden.contains($0.id) }
        switch Prefs.albumSort {
        case 1:
            list.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case 2:
            list.sort { a, b in
                let ca = snapshot.items[a.id]?.count ?? 0
                let cb = snapshot.items[b.id]?.count ?? 0
                if ca != cb { return ca > cb }
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
        default:
            break   // 기본: 카메라 · 스크린샷 · 저장한 사진 … 저장한 앱 … 내 앨범
        }
        return list
    }

    private func reload(force: Bool) {
        guard isViewLoaded else { return }
        let library = Library.shared
        switch library.status {
        case .denied, .restricted:
            messageLabel.text = "사진을 앨범으로 나눠 보여 주려면 사진 접근 권한이 필요해요.\n설정 › 사진에서 '전체 접근'을 골라 주세요."
            messageButton.isHidden = false
            messageView.isHidden = false
        case .notDetermined:
            messageLabel.text = "사진 접근을 허용해 주세요."
            messageButton.isHidden = true
            messageView.isHidden = false
        default:
            messageView.isHidden = true
        }

        if library.status == .limited && !warnedLimited && presentedViewController == nil && view.window != nil {
            warnedLimited = true
            let alert = UIAlertController(title: "일부 사진만 허용됨",
                                          message: "지금은 고른 사진만 보여요. 전부 앨범으로 나눠 보려면 설정 › 사진에서 '전체 접근'으로 바꿔 주세요.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "나중에", style: .cancel))
            alert.addAction(UIAlertAction(title: "설정 열기", style: .default) { [weak self] _ in self?.openSettings() })
            present(alert, animated: true)
        }

        let snapshot = library.snapshot
        let newFolders = snapshot.loaded ? visibleFolders(snapshot) : []
        // 앨범 구성과 대표 사진이 그대로면 숫자만 고침 (분류 도중 표지가 깜빡이지 않게)
        var signature: [String] = []
        for folder in newFolders {
            let cover = snapshot.items[folder.id]?.first?.localIdentifier ?? ""
            signature.append([folder.id, folder.title, cover].joined(separator: "|"))
        }
        let sameShape = !force && signature == lastSignature
        folders = newFolders
        lastSignature = signature
        if sameShape {
            refreshVisibleText()
        } else {
            collectionView.reloadData()
        }
    }

    private func refreshVisibleText() {
        let snapshot = Library.shared.snapshot
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard indexPath.item < folders.count, let cell = collectionView.cellForItem(at: indexPath) as? FolderCell else { continue }
            cell.countLabel.text = String(snapshot.items[folders[indexPath.item].id]?.count ?? 0)
        }
        let kind = UICollectionView.elementKindSectionHeader
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
            if let header = collectionView.supplementaryView(forElementKind: kind, at: indexPath) as? SectionHeaderView {
                header.detail.text = headerText()
            }
        }
    }

    private func headerText() -> String {
        let snapshot = Library.shared.snapshot
        guard snapshot.loaded else { return "" }
        if snapshot.pending > 0 {
            return "사진 분류 중 \(snapshot.total - snapshot.pending) / \(snapshot.total)"
        }
        let hiddenCount = snapshot.folders.count - folders.count
        if hiddenCount > 0 {
            return "앨범 \(folders.count)개 · 숨긴 앨범 \(hiddenCount)개"
        }
        return "앨범 \(folders.count)개"
    }

    // MARK: - 격자

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        1
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        folders.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FolderCell.reuse, for: indexPath) as! FolderCell
        let folder = folders[indexPath.item]
        let list = Library.shared.snapshot.items[folder.id] ?? []
        cell.titleLabel.text = folder.title
        cell.countLabel.text = String(list.count)
        cell.iconView.image = UIImage(systemName: folder.symbol)
        cell.iconView.isHidden = !list.isEmpty
        if let cover = list.first {
            let id = cover.localIdentifier
            cell.assetID = id
            cell.requestID = Thumbs.manager.requestImage(for: cover, targetSize: thumbSize, contentMode: .aspectFill,
                                                         options: Thumbs.options) { [weak cell] image, _ in
                guard let cell, cell.assetID == id, let image else { return }
                cell.imageView.image = image
            }
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: SectionHeaderView.reuse,
                                                                     for: indexPath) as! SectionHeaderView
        header.detail.text = headerText()
        return header
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard indexPath.item < folders.count else { return }
        navigationController?.pushViewController(GridViewController(folder: folders[indexPath.item]), animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first, indexPath.item < folders.count else { return nil }
        let folder = folders[indexPath.item]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            var actions: [UIAction] = []
            actions.append(UIAction(title: "앨범 숨기기", image: UIImage(systemName: "eye.slash")) { _ in
                self?.hide(folder)
            })
            if folder.isUser, let albumID = folder.albumID {
                actions.append(UIAction(title: "이름 바꾸기", image: UIImage(systemName: "pencil")) { _ in
                    self?.rename(folder, albumID: albumID)
                })
                actions.append(UIAction(title: "앨범 삭제", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    self?.delete(folder, albumID: albumID)
                })
            }
            return UIMenu(children: actions)
        }
    }

    private func hide(_ folder: Folder) {
        var hidden = Prefs.hiddenAlbums
        hidden.insert(folder.id)
        Prefs.hiddenAlbums = hidden
        reload(force: false)
        toast("'\(folder.title)' 앨범을 숨겼어요. ⋯ › 숨기기에서 다시 보이게 할 수 있어요")
    }

    private func rename(_ folder: Folder, albumID: String) {
        promptText(title: "앨범 이름 바꾸기", initial: folder.title, placeholder: "앨범 이름", confirm: "저장") { name in
            if let album = Library.shared.album(id: albumID) {
                Library.shared.rename(album, to: name)
            }
        }
    }

    private func delete(_ folder: Folder, albumID: String) {
        confirm(title: "'\(folder.title)' 앨범을 삭제할까요?",
                message: "앨범만 삭제돼요. 안에 있던 사진은 그대로 남아요.", action: "앨범 삭제") {
            if let album = Library.shared.album(id: albumID) {
                Library.shared.deleteAlbum(album)
            }
        }
    }

    // MARK: - 위 버튼 (갤럭시 앨범 탭의 ⋮ 메뉴: 앨범 만들기 · 정렬 · 숨기기)

    private func refreshMenu() {
        let sort = Prefs.albumSort
        let sortTitles = ["기본 순서", "이름순", "사진 많은 순"]
        var sortActions: [UIAction] = []
        for (index, name) in sortTitles.enumerated() {
            sortActions.append(UIAction(title: name, state: sort == index ? .on : .off) { [weak self] _ in
                Prefs.albumSort = index
                self?.refreshMenu()
                self?.reload(force: false)
            })
        }
        let sortMenu = UIMenu(title: "정렬", image: UIImage(systemName: "arrow.up.arrow.down"), children: sortActions)

        let create = UIAction(title: "앨범 만들기", image: UIImage(systemName: "plus.rectangle.on.folder")) { [weak self] _ in
            self?.newFolder()
        }
        let hide = UIAction(title: "숨기기 / 숨기기 해제", image: UIImage(systemName: "eye.slash")) { [weak self] _ in
            self?.navigationController?.pushViewController(HiddenAlbumsViewController(), animated: true)
        }
        let hideMoved = UIAction(title: "내 앨범에 넣은 사진은 자동 앨범에서 빼기", state: Library.shared.hideMoved ? .on : .off) { [weak self] _ in
            Library.shared.hideMoved.toggle()
            self?.refreshMenu()
        }
        let reclassify = UIAction(title: "사진 다시 분류", image: UIImage(systemName: "arrow.clockwise")) { [weak self] _ in
            Library.shared.classifier.reset()
            self?.toast("다시 분류하고 있어요")
        }
        let diagnostics = UIAction(title: "진단 복사", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
            UIPasteboard.general.string = Library.shared.diagnostics()
            self?.toast("진단 내용을 복사했어요")
        }
        let top = UIMenu(title: "", options: .displayInline, children: [create, sortMenu, hide])
        let bottom = UIMenu(title: "", options: .displayInline, children: [hideMoved, reclassify, diagnostics])
        let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: UIMenu(children: [top, bottom]))
        let add = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(newFolder))
        navigationItem.rightBarButtonItems = [more, add]
    }

    @objc private func newFolder() {
        guard Library.shared.canRead else { return }
        promptText(title: "앨범 만들기", placeholder: "앨범 이름", confirm: "만들기") { [weak self] name in
            Library.shared.createAlbum(title: name) { ok in
                if !ok { self?.toast("앨범을 만들지 못했어요") }
            }
        }
    }
}

/// 갤럭시의 '숨기기 / 숨기기 해제': 스위치를 켠 앨범은 앨범 탭에서 안 보임 (사진은 그대로)
final class HiddenAlbumsViewController: UITableViewController {
    private var folders: [Folder] = []
    private var hidden = Prefs.hiddenAlbums

    init() {
        super.init(style: .insetGrouped)
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "숨기기 / 숨기기 해제"
        navigationItem.largeTitleDisplayMode = .never
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.allowsSelection = false
        folders = Library.shared.snapshot.folders
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        folders.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "켜 둔 앨범은 앨범 탭에서 숨겨져요. 사진은 지워지지 않고 보관함에는 그대로 보여요."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let folder = folders[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = folder.title
        content.secondaryText = String(Library.shared.snapshot.items[folder.id]?.count ?? 0)
        content.image = UIImage(systemName: folder.symbol)
        cell.contentConfiguration = content
        let toggle = UISwitch()
        toggle.isOn = hidden.contains(folder.id)
        toggle.tag = indexPath.row
        toggle.addTarget(self, action: #selector(toggled(_:)), for: .valueChanged)
        cell.accessoryView = toggle
        return cell
    }

    @objc private func toggled(_ sender: UISwitch) {
        guard sender.tag < folders.count else { return }
        let id = folders[sender.tag].id
        if sender.isOn {
            hidden.insert(id)
        } else {
            hidden.remove(id)
        }
        Prefs.hiddenAlbums = hidden
    }
}
