import Photos
import UIKit

final class FolderCell: UICollectionViewCell {
    static let reuse = "FolderCell"

    let imageView = UIImageView()
    let iconView = UIImageView()
    let groupBadge = UIImageView()
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

        // 그룹(앨범 묶음) 표시
        groupBadge.image = UIImage(systemName: "folder.fill")
        groupBadge.tintColor = .white
        groupBadge.contentMode = .scaleAspectFit
        groupBadge.layer.shadowColor = UIColor.black.cgColor
        groupBadge.layer.shadowOpacity = 0.6
        groupBadge.layer.shadowRadius = 2
        groupBadge.layer.shadowOffset = .zero
        groupBadge.isHidden = true
        groupBadge.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabel
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(imageView)
        contentView.addSubview(iconView)
        contentView.addSubview(groupBadge)
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

            groupBadge.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 7),
            groupBadge.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -6),
            groupBadge.widthAnchor.constraint(equalToConstant: 22),
            groupBadge.heightAnchor.constraint(equalToConstant: 18),

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

/// 앨범 격자. 갤럭시 갤러리처럼 카메라·스크린샷·저장한 앱별 앨범과 내가 만든 앨범을 한 화면에 보여 줌.
/// 세 가지로 쓰임: 앨범 탭 첫 화면(.top), 그룹 안(.group), 숨긴 앨범 탭(.hidden — Face ID 로 열림)
final class FoldersViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate,
                                   UICollectionViewDragDelegate, UICollectionViewDropDelegate {
    enum Mode: Equatable {
        case top
        case group(String)
        case hidden
    }

    private let mode: Mode
    private var collectionView: UICollectionView!
    private var folders: [Folder] = []
    private var lastSignature: [String] = []
    private let messageView = UIView()
    private let messageLabel = UILabel()
    private let messageButton = UIButton(type: .system)
    private var messageAction: (() -> Void)?
    private var warnedLimited = false
    private var thumbSize = CGSize(width: 500, height: 500)
    private var columns = Prefs.albumColumns

    // 숨긴 앨범 탭 잠금
    private var unlocked = false
    private var authenticating = false

    init(mode: Mode = .top) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 순서 저장용 이름 (화면마다 따로)
    private var containerKey: String {
        switch mode {
        case .top: return "top"
        case .group(let id): return id
        case .hidden: return "hidden"
        }
    }

    private var isLocked: Bool { mode == .hidden && !unlocked }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        switch mode {
        case .top:
            navigationItem.title = "앨범"
            navigationItem.largeTitleDisplayMode = .always
            navigationItem.backButtonTitle = "앨범"
        case .group(let id):
            navigationItem.title = Groups.group(id: id)?.title ?? "그룹"
            navigationItem.largeTitleDisplayMode = .never
        case .hidden:
            navigationItem.title = "숨긴 앨범"
            navigationItem.largeTitleDisplayMode = .always
            navigationItem.backButtonTitle = "숨긴 앨범"
        }

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: makeLayout())
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        // 꾹 눌러 끌면 순서 바꾸기 (그룹 위에 놓으면 그룹에 넣기)
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        collectionView.dragInteractionEnabled = true
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
        if mode == .hidden {
            NotificationCenter.default.addObserver(self, selector: #selector(lock),
                                                   name: UIApplication.didEnterBackgroundNotification, object: nil)
        }
        reload(force: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
        // 숨기기 화면이나 그룹에서 돌아왔을 때 반영
        reload(force: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if isLocked { authenticate() }
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

    // MARK: - 안내 화면 (권한 · 잠금)

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
        messageButton.addTarget(self, action: #selector(messageButtonTapped), for: .touchUpInside)

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

    private func showMessage(_ text: String, button: String?, action: (() -> Void)?) {
        messageLabel.text = text
        messageButton.setTitle(button, for: .normal)
        messageButton.isHidden = button == nil
        messageAction = action
        messageView.isHidden = false
        view.bringSubviewToFront(messageView)
    }

    @objc private func messageButtonTapped() {
        messageAction?()
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - 숨긴 앨범 잠금

    /// 다른 탭으로 가거나 앱이 뒤로 가면 다시 잠금
    @objc func lock() {
        guard mode == .hidden, unlocked else { return }
        unlocked = false
        navigationController?.popToRootViewController(animated: false)
        if isViewLoaded { reload(force: true) }
    }

    private func authenticate() {
        guard isLocked, !authenticating else { return }
        authenticating = true
        Auth.verify(reason: "숨긴 앨범을 보려면 인증이 필요해요") { [weak self] ok in
            guard let self else { return }
            self.authenticating = false
            if ok {
                self.unlocked = true
                self.reload(force: true)
            }
        }
    }

    // MARK: - 데이터

    @objc private func libraryChanged() {
        reload(force: false)
    }

    private func groupFolder(_ group: AlbumGroup) -> Folder {
        Folder(id: group.id, title: group.title, symbol: "folder.fill", section: .user)
    }

    /// 이 화면에 보여 줄 앨범·그룹을 정렬해서 돌려줌
    private func currentFolders(_ snapshot: Snapshot) -> [Folder] {
        let hidden = Prefs.hiddenAlbums
        let groups = Groups.all()
        var list: [Folder] = []
        switch mode {
        case .top:
            var grouped = Set<String>()
            for group in groups {
                grouped.formUnion(group.members)
            }
            list = snapshot.folders.filter { !hidden.contains($0.id) && !grouped.contains($0.id) }
            for group in groups where !hidden.contains(group.id) {
                list.append(groupFolder(group))
            }
        case .group(let id):
            let members = Set(groups.first { $0.id == id }?.members ?? [])
            list = snapshot.folders.filter { members.contains($0.id) && !hidden.contains($0.id) }
        case .hidden:
            list = snapshot.folders.filter { hidden.contains($0.id) }
            for group in groups where hidden.contains(group.id) {
                list.append(groupFolder(group))
            }
        }

        switch Prefs.albumSort {
        case 1:
            list.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case 2:
            list.sort { a, b in
                let ca = self.photoCount(a, snapshot)
                let cb = self.photoCount(b, snapshot)
                if ca != cb { return ca > cb }
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
        case 3:
            // 사용자 지정: 저장해 둔 순서대로, 새로 생긴 건 뒤에
            let order = Groups.customOrder(for: containerKey)
            var rank: [String: Int] = [:]
            for (index, id) in order.enumerated() {
                rank[id] = index
            }
            var indexed: [(Int, Int, Folder)] = []
            for (index, folder) in list.enumerated() {
                indexed.append((rank[folder.id] ?? Int.max, index, folder))
            }
            indexed.sort { a, b in
                if a.0 != b.0 { return a.0 < b.0 }
                return a.1 < b.1
            }
            list = indexed.map { $0.2 }
        default:
            break   // 기본: 카메라 · 스크린샷 · 저장한 사진 … 저장한 앱 … 내 앨범 … 그룹
        }
        return list
    }

    /// 그룹 안에 든 앨범들
    private func members(of folder: Folder, _ snapshot: Snapshot) -> [Folder] {
        guard folder.isGroup, let group = Groups.group(id: folder.id) else { return [] }
        let ids = Set(group.members)
        return snapshot.folders.filter { ids.contains($0.id) }
    }

    private func photoCount(_ folder: Folder, _ snapshot: Snapshot) -> Int {
        if folder.isGroup {
            var total = 0
            for member in members(of: folder, snapshot) {
                total += snapshot.items[member.id]?.count ?? 0
            }
            return total
        }
        return snapshot.items[folder.id]?.count ?? 0
    }

    private func cover(_ folder: Folder, _ snapshot: Snapshot) -> PHAsset? {
        if folder.isGroup {
            for member in members(of: folder, snapshot) {
                if let first = snapshot.items[member.id]?.first { return first }
            }
            return nil
        }
        return snapshot.items[folder.id]?.first
    }

    private func countText(_ folder: Folder, _ snapshot: Snapshot) -> String {
        if folder.isGroup {
            return "앨범 \(members(of: folder, snapshot).count)개"
        }
        return String(snapshot.items[folder.id]?.count ?? 0)
    }

    private func signature(_ list: [Folder], _ snapshot: Snapshot) -> [String] {
        var result: [String] = []
        for folder in list {
            let coverID = cover(folder, snapshot)?.localIdentifier ?? ""
            result.append([folder.id, folder.title, coverID].joined(separator: "|"))
        }
        return result
    }

    private func reload(force: Bool) {
        guard isViewLoaded else { return }
        let library = Library.shared

        if case .group(let id) = mode {
            guard let group = Groups.group(id: id) else {
                // 그룹이 없어짐
                if navigationController?.topViewController === self {
                    navigationController?.popViewController(animated: true)
                }
                return
            }
            navigationItem.title = group.title
        }

        if isLocked {
            folders = []
            lastSignature = []
            collectionView.reloadData()
            collectionView.isHidden = true
            navigationItem.rightBarButtonItems = nil
            showMessage("숨긴 앨범은 Face ID 로 확인한 뒤에 볼 수 있어요.", button: "잠금 풀기") { [weak self] in
                self?.authenticate()
            }
            return
        }
        collectionView.isHidden = false
        if navigationItem.rightBarButtonItems == nil { refreshMenu() }

        switch library.status {
        case .denied, .restricted:
            showMessage("사진을 앨범으로 나눠 보여 주려면 사진 접근 권한이 필요해요.\n설정 › 사진에서 '전체 접근'을 골라 주세요.",
                        button: "설정 열기") { [weak self] in self?.openSettings() }
        case .notDetermined:
            showMessage("사진 접근을 허용해 주세요.", button: nil, action: nil)
        default:
            messageView.isHidden = true
        }

        if mode == .top && library.status == .limited && !warnedLimited && presentedViewController == nil && view.window != nil {
            warnedLimited = true
            let alert = UIAlertController(title: "일부 사진만 허용됨",
                                          message: "지금은 고른 사진만 보여요. 전부 앨범으로 나눠 보려면 설정 › 사진에서 '전체 접근'으로 바꿔 주세요.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "나중에", style: .cancel))
            alert.addAction(UIAlertAction(title: "설정 열기", style: .default) { [weak self] _ in self?.openSettings() })
            present(alert, animated: true)
        }

        let snapshot = library.snapshot
        let newFolders = snapshot.loaded ? currentFolders(snapshot) : []
        // 앨범 구성과 대표 사진이 그대로면 숫자만 고침 (분류 도중 표지가 깜빡이지 않게)
        let newSignature = signature(newFolders, snapshot)
        let sameShape = !force && newSignature == lastSignature
        folders = newFolders
        lastSignature = newSignature
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
            cell.countLabel.text = countText(folders[indexPath.item], snapshot)
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
        if mode == .top && snapshot.pending > 0 {
            return "사진 분류 중 \(snapshot.total - snapshot.pending) / \(snapshot.total)"
        }
        if folders.isEmpty {
            switch mode {
            case .top: return ""
            case .group: return "비어 있어요. 앨범을 꾹 눌러 '그룹으로 이동'을 고르면 여기에 들어와요"
            case .hidden: return "숨긴 앨범이 없어요"
            }
        }
        return "\(folders.count)개"
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
        let snapshot = Library.shared.snapshot
        let coverAsset = cover(folder, snapshot)
        cell.titleLabel.text = folder.title
        cell.countLabel.text = countText(folder, snapshot)
        cell.iconView.image = UIImage(systemName: folder.symbol)
        cell.iconView.isHidden = coverAsset != nil
        cell.groupBadge.isHidden = !(folder.isGroup && coverAsset != nil)
        if let coverAsset {
            let id = coverAsset.localIdentifier
            cell.assetID = id
            cell.requestID = Thumbs.manager.requestImage(for: coverAsset, targetSize: thumbSize, contentMode: .aspectFill,
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

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard indexPath.item < folders.count, let cell = cell as? FolderCell else { return }
        cell.countLabel.text = countText(folders[indexPath.item], Library.shared.snapshot)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard indexPath.item < folders.count else { return }
        let folder = folders[indexPath.item]
        if folder.isGroup {
            navigationController?.pushViewController(FoldersViewController(mode: .group(folder.id)), animated: true)
        } else {
            navigationController?.pushViewController(GridViewController(folder: folder), animated: true)
        }
    }

    // MARK: - 꾹 눌렀을 때 메뉴

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first, indexPath.item < folders.count else { return nil }
        let folder = folders[indexPath.item]
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            return UIMenu(children: self.menuElements(for: folder))
        }
    }

    private func menuElements(for folder: Folder) -> [UIMenuElement] {
        var elements: [UIMenuElement] = []

        if folder.isGroup {
            elements.append(UIAction(title: "그룹 이름 바꾸기", image: UIImage(systemName: "pencil")) { [weak self] _ in
                self?.renameGroup(folder)
            })
            elements.append(UIAction(title: "그룹 해제", image: UIImage(systemName: "folder.badge.minus"), attributes: .destructive) { [weak self] _ in
                self?.deleteGroup(folder)
            })
        } else {
            if case .group = mode {
                elements.append(UIAction(title: "그룹에서 빼기", image: UIImage(systemName: "arrow.up.left")) { [weak self] _ in
                    Groups.remove(folder.id)
                    self?.toast("'\(folder.title)' 앨범을 그룹에서 뺐어요")
                })
            }
            // 그룹으로 이동 ▸ (그룹 목록 + 새 그룹)
            var targets: [UIMenuElement] = []
            for group in Groups.all() where group.id != currentGroupID {
                targets.append(UIAction(title: group.title, image: UIImage(systemName: "folder")) { [weak self] _ in
                    Groups.add(folder.id, to: group.id)
                    self?.toast("'\(folder.title)' 앨범을 '\(group.title)' 그룹에 넣었어요")
                })
            }
            targets.append(UIAction(title: "새 그룹…", image: UIImage(systemName: "folder.badge.plus")) { [weak self] _ in
                self?.promptText(title: "그룹 만들기", placeholder: "그룹 이름", confirm: "만들기") { name in
                    Groups.create(title: name, members: [folder.id])
                }
            })
            elements.append(UIMenu(title: "그룹으로 이동", image: UIImage(systemName: "folder"), children: targets))
        }

        if mode == .hidden {
            elements.append(UIAction(title: "숨기기 해제", image: UIImage(systemName: "eye")) { [weak self] _ in
                self?.setHidden(folder, false)
            })
        } else {
            elements.append(UIAction(title: folder.isGroup ? "그룹 숨기기" : "앨범 숨기기", image: UIImage(systemName: "eye.slash")) { [weak self] _ in
                self?.setHidden(folder, true)
            })
        }

        if folder.isUser, let albumID = folder.albumID {
            elements.append(UIAction(title: "이름 바꾸기", image: UIImage(systemName: "pencil")) { [weak self] _ in
                self?.renameAlbum(folder, albumID: albumID)
            })
            elements.append(UIAction(title: "앨범 삭제", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                self?.deleteAlbum(folder, albumID: albumID)
            })
        }
        return elements
    }

    private var currentGroupID: String? {
        if case .group(let id) = mode { return id }
        return nil
    }

    private func setHidden(_ folder: Folder, _ on: Bool) {
        var hidden = Prefs.hiddenAlbums
        if on {
            hidden.insert(folder.id)
        } else {
            hidden.remove(folder.id)
        }
        Prefs.hiddenAlbums = hidden
        NotificationCenter.default.post(name: Library.didChange, object: nil)
        toast(on ? "'\(folder.title)' 을(를) 숨겼어요. '숨긴 앨범' 탭에서 볼 수 있어요" : "'\(folder.title)' 을(를) 다시 보이게 했어요")
    }

    private func renameAlbum(_ folder: Folder, albumID: String) {
        promptText(title: "앨범 이름 바꾸기", initial: folder.title, placeholder: "앨범 이름", confirm: "저장") { name in
            if let album = Library.shared.album(id: albumID) {
                Library.shared.rename(album, to: name)
            }
        }
    }

    private func deleteAlbum(_ folder: Folder, albumID: String) {
        confirm(title: "'\(folder.title)' 앨범을 삭제할까요?",
                message: "앨범만 삭제돼요. 안에 있던 사진은 그대로 남아요.", action: "앨범 삭제") {
            if let album = Library.shared.album(id: albumID) {
                Library.shared.deleteAlbum(album)
            }
        }
    }

    private func renameGroup(_ folder: Folder) {
        promptText(title: "그룹 이름 바꾸기", initial: folder.title, placeholder: "그룹 이름", confirm: "저장") { name in
            Groups.rename(folder.id, to: name)
        }
    }

    private func deleteGroup(_ folder: Folder) {
        confirm(title: "'\(folder.title)' 그룹을 해제할까요?",
                message: "그룹만 없어져요. 안에 있던 앨범은 앨범 탭 첫 화면으로 나와요.", action: "그룹 해제") {
            Groups.delete(folder.id)
        }
    }

    // MARK: - 끌어서 순서 바꾸기 · 그룹에 넣기

    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession,
                        at indexPath: IndexPath) -> [UIDragItem] {
        guard indexPath.item < folders.count else { return [] }
        let id = folders[indexPath.item].id
        let item = UIDragItem(itemProvider: NSItemProvider(object: id as NSString))
        item.localObject = id
        return [item]
    }

    /// 이 앱 안에서만 끌어 놓기
    func collectionView(_ collectionView: UICollectionView, dragSessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool {
        true
    }

    private func draggedID(_ session: UIDropSession) -> String? {
        session.localDragSession?.items.first?.localObject as? String
    }

    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession,
                        withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        guard let id = draggedID(session), folders.contains(where: { $0.id == id }) else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
        // 앨범을 그룹 한가운데에 놓으면 그 그룹에 넣기
        if !id.hasPrefix(AlbumGroup.prefix) {
            let point = session.location(in: collectionView)
            if let path = collectionView.indexPathForItem(at: point), path.item < folders.count, folders[path.item].isGroup,
               let frame = collectionView.layoutAttributesForItem(at: path)?.frame,
               frame.insetBy(dx: frame.width * 0.2, dy: frame.height * 0.2).contains(point) {
                return UICollectionViewDropProposal(operation: .move, intent: .insertIntoDestinationIndexPath)
            }
        }
        return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let item = coordinator.items.first, let id = item.dragItem.localObject as? String,
              let from = folders.firstIndex(where: { $0.id == id }) else { return }

        if coordinator.proposal.intent == .insertIntoDestinationIndexPath {
            guard let destination = coordinator.destinationIndexPath, destination.item < folders.count,
                  folders[destination.item].isGroup, !id.hasPrefix(AlbumGroup.prefix) else { return }
            let group = folders[destination.item]
            let title = folders[from].title
            Groups.add(id, to: group.id)   // 알림으로 화면이 다시 그려짐
            toast("'\(title)' 앨범을 '\(group.title)' 그룹에 넣었어요")
            return
        }

        var to = coordinator.destinationIndexPath?.item ?? (folders.count - 1)
        to = min(max(0, to), folders.count - 1)
        guard to != from else { return }

        let moved = folders.remove(at: from)
        folders.insert(moved, at: to)
        // 끌어서 옮기면 정렬이 '사용자 지정'으로 바뀜
        Groups.setCustomOrder(folders.map { $0.id }, for: containerKey)
        Prefs.albumSort = 3
        lastSignature = signature(folders, Library.shared.snapshot)
        refreshMenu()

        let source = IndexPath(item: from, section: 0)
        let target = IndexPath(item: to, section: 0)
        collectionView.performBatchUpdates({
            collectionView.moveItem(at: source, to: target)
        }, completion: nil)
        coordinator.drop(item.dragItem, toItemAt: target)
    }

    // MARK: - 위 버튼 (갤럭시 앨범 탭의 ⋮ 메뉴: 앨범 만들기 · 그룹 만들기 · 정렬 · 숨기기)

    private func refreshMenu() {
        guard !isLocked else { return }
        let sort = Prefs.albumSort
        let sortTitles = ["기본 순서", "이름순", "사진 많은 순", "사용자 지정 (꾹 눌러 끌기)"]
        var sortActions: [UIAction] = []
        for (index, name) in sortTitles.enumerated() {
            sortActions.append(UIAction(title: name, state: sort == index ? .on : .off) { [weak self] _ in
                guard let self else { return }
                if index == 3 && Groups.customOrder(for: self.containerKey).isEmpty {
                    // 처음 고르면 지금 보이는 순서에서 시작
                    Groups.setCustomOrder(self.folders.map { $0.id }, for: self.containerKey)
                }
                Prefs.albumSort = index
                self.refreshMenu()
                NotificationCenter.default.post(name: Library.didChange, object: nil)
            })
        }
        let sortMenu = UIMenu(title: "정렬", image: UIImage(systemName: "arrow.up.arrow.down"), children: sortActions)

        var sections: [UIMenu] = []
        var items: [UIBarButtonItem] = []
        switch mode {
        case .top:
            let createAlbum = UIAction(title: "앨범 만들기", image: UIImage(systemName: "plus.rectangle.on.folder")) { [weak self] _ in
                self?.newAlbum()
            }
            let createGroup = UIAction(title: "그룹 만들기", image: UIImage(systemName: "folder.badge.plus")) { [weak self] _ in
                self?.newGroup()
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
            sections.append(UIMenu(title: "", options: .displayInline, children: [createAlbum, createGroup, sortMenu]))
            sections.append(UIMenu(title: "", options: .displayInline, children: [hideMoved, reclassify, diagnostics]))
            items.append(UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(newAlbum)))
        case .group(let id):
            let rename = UIAction(title: "그룹 이름 바꾸기", image: UIImage(systemName: "pencil")) { [weak self] _ in
                guard let self, let group = Groups.group(id: id) else { return }
                self.renameGroup(self.groupFolder(group))
            }
            let dissolve = UIAction(title: "그룹 해제", image: UIImage(systemName: "folder.badge.minus"), attributes: .destructive) { [weak self] _ in
                guard let self, let group = Groups.group(id: id) else { return }
                self.deleteGroup(self.groupFolder(group))
            }
            sections.append(UIMenu(title: "", options: .displayInline, children: [sortMenu, rename, dissolve]))
        case .hidden:
            sections.append(UIMenu(title: "", options: .displayInline, children: [sortMenu]))
        }
        let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: UIMenu(children: sections))
        navigationItem.rightBarButtonItems = [more] + items
    }

    @objc private func newAlbum() {
        guard Library.shared.canRead else { return }
        promptText(title: "앨범 만들기", placeholder: "앨범 이름", confirm: "만들기") { [weak self] name in
            Library.shared.createAlbum(title: name) { ok in
                if !ok { self?.toast("앨범을 만들지 못했어요") }
            }
        }
    }

    private func newGroup() {
        promptText(title: "그룹 만들기", message: "앨범 여러 개를 담는 폴더예요. 앨범을 끌어다 놓거나 꾹 눌러 넣을 수 있어요.",
                   placeholder: "그룹 이름", confirm: "만들기") { name in
            Groups.create(title: name)
        }
    }
}
