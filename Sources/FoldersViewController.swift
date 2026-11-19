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
        imageView.layer.cornerRadius = 14
        imageView.layer.cornerCurve = .continuous
        imageView.backgroundColor = .secondarySystemBackground
        imageView.translatesAutoresizingMaskIntoConstraints = false

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .tertiaryLabel
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.font = .systemFont(ofSize: 13)
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
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),

            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 7),
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

    let label = UILabel()
    let detail = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabel
        detail.textAlignment = .right
        detail.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        addSubview(detail)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            detail.trailingAnchor.constraint(equalTo: trailingAnchor),
            detail.firstBaselineAnchor.constraint(equalTo: label.firstBaselineAnchor),
            detail.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// 첫 화면: 폴더 목록 (자동 분류 · 앱별 · 내 폴더)
final class FoldersViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {
    private var collectionView: UICollectionView!
    private var groups: [(section: Folder.Section, folders: [Folder])] = []
    private let messageView = UIView()
    private let messageLabel = UILabel()
    private let messageButton = UIButton(type: .system)
    private var warnedLimited = false
    private var lastSignature: [String] = []
    private var thumbSize = CGSize(width: 500, height: 500)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "갤러리"
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .always
        navigationItem.backButtonTitle = "폴더"

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: makeLayout())
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(FolderCell.self, forCellWithReuseIdentifier: FolderCell.reuse)
        collectionView.register(SectionHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: SectionHeaderView.reuse)
        view.addSubview(collectionView)

        setUpMessageView()
        refreshMenu()

        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: Library.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        reload()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
    }

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { _, environment in
            let inset: CGFloat = 16
            let gap: CGFloat = 14
            let width = environment.container.effectiveContentSize.width
            let columns = width > 700 ? 4 : (width > 500 ? 3 : 2)
            let itemWidth = floor((width - inset * 2 - gap * CGFloat(columns - 1)) / CGFloat(columns))
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                                                                 heightDimension: .fractionalHeight(1)))
            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(max(60, itemWidth) + 48))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, repeatingSubitem: item, count: columns)
            group.interItemSpacing = .fixed(gap)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 16
            section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: inset, bottom: 26, trailing: inset)
            let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(40))
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
        reload()
    }

    private func reload() {
        let library = Library.shared
        switch library.status {
        case .denied, .restricted:
            messageLabel.text = "사진을 폴더로 나눠 보여 주려면 사진 접근 권한이 필요해요.\n설정 › 사진에서 '전체 접근'을 골라 주세요."
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
                                          message: "지금은 고른 사진만 보여요. 폴더로 전부 나눠 보려면 설정 › 사진에서 '전체 접근'으로 바꿔 주세요.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "나중에", style: .cancel))
            alert.addAction(UIAlertAction(title: "설정 열기", style: .default) { [weak self] _ in self?.openSettings() })
            present(alert, animated: true)
        }

        let snapshot = library.snapshot
        var result: [(section: Folder.Section, folders: [Folder])] = []
        for section in [Folder.Section.auto, .apps, .user] {
            let list = snapshot.folders.filter { $0.section == section }
            if !list.isEmpty || section == .user { result.append((section, list)) }
        }
        let newGroups = snapshot.loaded ? result : []
        // 폴더 구성과 대표 사진이 그대로면 숫자만 고침 (분류 도중 표지가 깜빡이지 않게)
        var signature: [String] = []
        for group in newGroups {
            for folder in group.folders {
                let cover = snapshot.items[folder.id]?.first?.localIdentifier ?? ""
                signature.append([folder.id, folder.title, cover].joined(separator: "|"))
            }
        }
        let sameShape = signature == lastSignature && newGroups.count == groups.count
        groups = newGroups
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
            guard indexPath.section < groups.count, indexPath.item < groups[indexPath.section].folders.count,
                  let cell = collectionView.cellForItem(at: indexPath) as? FolderCell else { continue }
            let folder = groups[indexPath.section].folders[indexPath.item]
            cell.countLabel.text = "\(snapshot.items[folder.id]?.count ?? 0)"
        }
        let kind = UICollectionView.elementKindSectionHeader
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
            guard indexPath.section < groups.count,
                  let header = collectionView.supplementaryView(forElementKind: kind, at: indexPath) as? SectionHeaderView else { continue }
            header.detail.text = headerDetail(groups[indexPath.section].section)
        }
    }

    private func headerTitle(_ section: Folder.Section) -> String {
        switch section {
        case .auto: return "자동 분류"
        case .apps: return "저장한 앱"
        case .user: return "내 폴더"
        }
    }

    private func headerDetail(_ section: Folder.Section) -> String {
        let snapshot = Library.shared.snapshot
        switch section {
        case .auto:
            if snapshot.pending > 0 {
                return "분류 중 \(snapshot.total - snapshot.pending) / \(snapshot.total)"
            }
            return "\(snapshot.total)장"
        case .apps:
            return ""
        case .user:
            return groups.first { $0.section == .user }?.folders.isEmpty == true ? "+ 를 눌러 폴더를 만들어요" : ""
        }
    }

    // MARK: - 격자

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        groups.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        groups[section].folders.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FolderCell.reuse, for: indexPath) as! FolderCell
        let folder = groups[indexPath.section].folders[indexPath.item]
        let list = Library.shared.snapshot.items[folder.id] ?? []
        cell.titleLabel.text = folder.title
        cell.countLabel.text = "\(list.count)"
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
        let section = groups[indexPath.section].section
        header.label.text = headerTitle(section)
        header.detail.text = headerDetail(section)
        return header
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        let folder = groups[indexPath.section].folders[indexPath.item]
        navigationController?.pushViewController(GridViewController(folder: folder), animated: true)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first,
              indexPath.section < groups.count, indexPath.item < groups[indexPath.section].folders.count else { return nil }
        let folder = groups[indexPath.section].folders[indexPath.item]
        guard folder.isUser, let albumID = folder.albumID else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            let rename = UIAction(title: "이름 바꾸기", image: UIImage(systemName: "pencil")) { _ in
                self?.promptText(title: "폴더 이름 바꾸기", initial: folder.title, placeholder: "폴더 이름", confirm: "저장") { name in
                    if let album = Library.shared.album(id: albumID) {
                        Library.shared.rename(album, to: name)
                    }
                }
            }
            let delete = UIAction(title: "폴더 지우기", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                self?.confirm(title: "'\(folder.title)' 폴더를 지울까요?",
                              message: "폴더만 지워져요. 안에 있던 사진은 그대로 남아요.", action: "폴더 지우기") {
                    if let album = Library.shared.album(id: albumID) {
                        Library.shared.deleteAlbum(album)
                    }
                }
            }
            return UIMenu(children: [rename, delete])
        }
    }

    // MARK: - 위 버튼

    private func refreshMenu() {
        let library = Library.shared
        let hide = UIAction(title: "옮긴 사진은 자동 폴더에서 숨기기", state: library.hideMoved ? .on : .off) { [weak self] _ in
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
        let menu = UIMenu(children: [hide, reclassify, diagnostics])
        let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: menu)
        let add = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(newFolder))
        navigationItem.rightBarButtonItems = [more, add]
    }

    @objc private func newFolder() {
        guard Library.shared.canRead else { return }
        promptText(title: "새 폴더", placeholder: "폴더 이름", confirm: "만들기") { [weak self] name in
            Library.shared.createAlbum(title: name) { ok in
                if !ok { self?.toast("폴더를 만들지 못했어요") }
            }
        }
    }
}
