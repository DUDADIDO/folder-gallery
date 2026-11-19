import Photos
import UIKit

final class AssetCell: UICollectionViewCell {
    static let reuse = "AssetCell"

    let imageView = UIImageView()
    private let dim = UIView()
    private let badge = UIImageView()
    private let durationLabel = UILabel()

    var assetID: String?
    var requestID: PHImageRequestID = PHInvalidImageRequestID

    /// 선택 모드인지 (빈 동그라미를 보여 줄지)
    var selecting = false {
        didSet { updateBadge() }
    }

    override var isSelected: Bool {
        didSet { updateBadge() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .secondarySystemBackground
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(imageView)

        dim.backgroundColor = UIColor.black.withAlphaComponent(0.28)
        dim.frame = contentView.bounds
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dim.isHidden = true
        contentView.addSubview(dim)

        durationLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        durationLabel.textColor = .white
        durationLabel.layer.shadowColor = UIColor.black.cgColor
        durationLabel.layer.shadowOpacity = 0.8
        durationLabel.layer.shadowRadius = 2
        durationLabel.layer.shadowOffset = .zero
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(durationLabel)

        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.isHidden = true
        contentView.addSubview(badge)

        NSLayoutConstraint.activate([
            durationLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            durationLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            badge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            badge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            badge.widthAnchor.constraint(equalToConstant: 24),
            badge.heightAnchor.constraint(equalToConstant: 24),
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
    }

    func setDuration(_ seconds: TimeInterval?) {
        guard let seconds else {
            durationLabel.text = nil
            return
        }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        durationLabel.text = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private func updateBadge() {
        dim.isHidden = !(selecting && isSelected)
        badge.isHidden = !selecting
        guard selecting else { return }
        if isSelected {
            let config = UIImage.SymbolConfiguration(paletteColors: [.white, .systemBlue])
            badge.image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: config)
        } else {
            let config = UIImage.SymbolConfiguration(paletteColors: [.white])
            badge.image = UIImage(systemName: "circle", withConfiguration: config)
        }
    }
}

final class DayHeaderView: UICollectionReusableView {
    static let reuse = "DayHeaderView"

    let label = UILabel()
    let button = UIButton(type: .system)
    var onToggle: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.systemBackground.withAlphaComponent(0.92)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        button.titleLabel?.font = .systemFont(ofSize: 15)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(tapped), for: .touchUpInside)
        addSubview(label)
        addSubview(button)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func tapped() {
        onToggle?()
    }
}

/// 폴더 안 사진 격자. 길게 누르거나 옆으로 끌면 여러 장 선택
final class GridViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
    private let folder: Folder
    private var assets: [PHAsset] = []
    private var assetIDs: [String] = []
    private var sections: [(day: Date, range: Range<Int>)] = []
    private var collectionView: UICollectionView!
    private let emptyLabel = UILabel()
    private var selecting = false
    private var thumbSize = CGSize(width: 240, height: 240)
    private let columns = 4

    private lazy var shareItem = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(shareSelected))
    private lazy var moveItem = UIBarButtonItem(image: UIImage(systemName: "folder"), style: .plain, target: self, action: #selector(moveSelected))
    private lazy var deleteItem = UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain, target: self, action: #selector(deleteSelected))

    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    init(folder: Folder) {
        self.folder = folder
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: makeLayout())
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .systemBackground
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.alwaysBounceVertical = true
        collectionView.allowsSelection = true
        collectionView.allowsMultipleSelection = false
        collectionView.allowsMultipleSelectionDuringEditing = true
        collectionView.register(AssetCell.self, forCellWithReuseIdentifier: AssetCell.reuse)
        collectionView.register(DayHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: DayHeaderView.reuse)
        view.addSubview(collectionView)

        emptyLabel.text = "사진이 없어요"
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.font = .systemFont(ofSize: 16)

        let press = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        press.minimumPressDuration = 0.35
        collectionView.addGestureRecognizer(press)

        toolbarItems = [shareItem, UIBarButtonItem.flexibleSpace(), moveItem, UIBarButtonItem.flexibleSpace(), deleteItem]

        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: Library.didChange, object: nil)
        reloadFromLibrary(force: true)
        updateChrome()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let scale = traitCollection.displayScale
        let side = max(60, view.bounds.width / CGFloat(columns)) * scale
        thumbSize = CGSize(width: side, height: side)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.setToolbarHidden(!selecting, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if selecting { setSelecting(false) }
    }

    private func makeLayout() -> UICollectionViewLayout {
        let spacing: CGFloat = 2
        let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                                                             heightDimension: .fractionalHeight(1)))
        let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1),
                                               heightDimension: .fractionalWidth(1 / CGFloat(columns)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, repeatingSubitem: item, count: columns)
        group.interItemSpacing = .fixed(spacing)
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = spacing
        let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(42))
        let header = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: headerSize,
                                                                 elementKind: UICollectionView.elementKindSectionHeader,
                                                                 alignment: .top)
        section.boundarySupplementaryItems = [header]
        return UICollectionViewCompositionalLayout(section: section)
    }

    // MARK: - 데이터

    @objc private func libraryChanged() {
        reloadFromLibrary(force: false)
    }

    private func reloadFromLibrary(force: Bool) {
        let snapshot = Library.shared.snapshot
        if snapshot.loaded && !snapshot.folders.contains(where: { $0.id == folder.id }) && folder.isUser {
            // 폴더가 지워짐
            if navigationController?.topViewController === self {
                navigationController?.popViewController(animated: true)
            }
            return
        }
        let new = snapshot.items[folder.id] ?? []
        let newIDs = new.map(\.localIdentifier)
        if !force && newIDs == assetIDs { return }

        let keep = Set(selectedAssets().map(\.localIdentifier))
        assets = new
        assetIDs = newIDs
        buildSections()
        collectionView.reloadData()
        collectionView.backgroundView = assets.isEmpty ? emptyLabel : nil

        if selecting && !keep.isEmpty {
            for (s, section) in sections.enumerated() {
                for (offset, index) in section.range.enumerated() where keep.contains(assetIDs[index]) {
                    collectionView.selectItem(at: IndexPath(item: offset, section: s), animated: false, scrollPosition: [])
                }
            }
        }
        updateChrome()
    }

    private func buildSections() {
        let calendar = Calendar.current
        var result: [(day: Date, range: Range<Int>)] = []
        var start = 0
        var current: Date?
        for (index, asset) in assets.enumerated() {
            let day = calendar.startOfDay(for: asset.creationDate ?? .distantPast)
            if day != current {
                if let current { result.append((current, start..<index)) }
                current = day
                start = index
            }
        }
        if let current { result.append((current, start..<assets.count)) }
        sections = result
    }

    private func flatIndex(_ indexPath: IndexPath) -> Int {
        sections[indexPath.section].range.lowerBound + indexPath.item
    }

    private func assetAt(_ indexPath: IndexPath) -> PHAsset {
        assets[flatIndex(indexPath)]
    }

    private func selectedAssets() -> [PHAsset] {
        guard selecting, let paths = collectionView?.indexPathsForSelectedItems else { return [] }
        return paths.sorted().compactMap { path in
            guard path.section < sections.count, path.item < sections[path.section].range.count else { return nil }
            return assetAt(path)
        }
    }

    private func dayTitle(_ day: Date) -> String {
        // 촬영 날짜가 없는 사진은 아주 옛날 날짜로 묶여 있음
        day < Date(timeIntervalSince1970: -30_000_000_000) ? "날짜 없음" : dayFormatter.string(from: day)
    }

    // MARK: - 격자

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        sections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].range.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AssetCell.reuse, for: indexPath) as! AssetCell
        let asset = assetAt(indexPath)
        let id = asset.localIdentifier
        if cell.assetID != id { cell.imageView.image = nil }
        cell.assetID = id
        cell.selecting = selecting
        cell.setDuration(asset.mediaType == .video ? asset.duration : nil)
        cell.requestID = Thumbs.manager.requestImage(for: asset, targetSize: thumbSize, contentMode: .aspectFill,
                                                     options: Thumbs.options) { [weak cell] image, _ in
            guard let cell, cell.assetID == id, let image else { return }
            cell.imageView.image = image
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: DayHeaderView.reuse,
                                                                     for: indexPath) as! DayHeaderView
        configure(header, section: indexPath.section)
        return header
    }

    private func configure(_ header: DayHeaderView, section: Int) {
        guard section < sections.count else { return }
        header.label.text = dayTitle(sections[section].day)
        header.button.isHidden = !selecting
        header.button.setTitle(isSectionFullySelected(section) ? "선택 해제" : "모두 선택", for: .normal)
        header.onToggle = { [weak self] in self?.toggleSection(section) }
    }

    private func refreshVisibleHeaders() {
        let kind = UICollectionView.elementKindSectionHeader
        for path in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
            if let header = collectionView.supplementaryView(forElementKind: kind, at: path) as? DayHeaderView {
                configure(header, section: path.section)
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let list = indexPaths.compactMap { path -> PHAsset? in
            guard path.section < sections.count, path.item < sections[path.section].range.count else { return nil }
            return assetAt(path)
        }
        Thumbs.manager.startCachingImages(for: list, targetSize: thumbSize, contentMode: .aspectFill, options: Thumbs.options)
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let list = indexPaths.compactMap { path -> PHAsset? in
            guard path.section < sections.count, path.item < sections[path.section].range.count else { return nil }
            return assetAt(path)
        }
        Thumbs.manager.stopCachingImages(for: list, targetSize: thumbSize, contentMode: .aspectFill, options: Thumbs.options)
    }

    // MARK: - 누르기·선택

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if selecting {
            updateChrome()
        } else {
            collectionView.deselectItem(at: indexPath, animated: false)
            let viewer = ViewerViewController(assets: assets, index: flatIndex(indexPath), sourceAlbumID: folder.albumID)
            navigationController?.pushViewController(viewer, animated: true)
        }
    }

    /// 미리 만들어 둔 셀은 visibleCells 에 없어서, 화면에 나올 때 선택 모드를 다시 맞춤
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? AssetCell)?.selecting = selecting
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        if selecting { updateChrome() }
    }

    /// 옆으로 끌어서 여러 장 선택 (iOS 기본 동작, 화면 끝에서 자동 스크롤)
    func collectionView(_ collectionView: UICollectionView, shouldBeginMultipleSelectionInteractionAt indexPath: IndexPath) -> Bool {
        true
    }

    func collectionView(_ collectionView: UICollectionView, didBeginMultipleSelectionInteractionAt indexPath: IndexPath) {
        if !selecting { setSelecting(true) }
    }

    func collectionViewDidEndMultipleSelectionInteraction(_ collectionView: UICollectionView) {
        updateChrome()
    }

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, !selecting else { return }
        let point = gesture.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point) else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        setSelecting(true)
        collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        updateChrome()
    }

    private func setSelecting(_ on: Bool) {
        guard selecting != on else { return }
        if !on {
            for path in collectionView.indexPathsForSelectedItems ?? [] {
                collectionView.deselectItem(at: path, animated: false)
            }
        }
        selecting = on
        collectionView.isEditing = on
        for cell in collectionView.visibleCells {
            (cell as? AssetCell)?.selecting = on
        }
        navigationController?.setToolbarHidden(!on, animated: true)
        updateChrome()
    }

    @objc private func startSelecting() {
        setSelecting(true)
    }

    @objc private func cancelSelecting() {
        setSelecting(false)
    }

    @objc private func toggleAll() {
        let selected = collectionView.indexPathsForSelectedItems?.count ?? 0
        if selected == assets.count {
            for path in collectionView.indexPathsForSelectedItems ?? [] {
                collectionView.deselectItem(at: path, animated: false)
            }
        } else {
            for (s, section) in sections.enumerated() {
                for item in 0..<section.range.count {
                    collectionView.selectItem(at: IndexPath(item: item, section: s), animated: false, scrollPosition: [])
                }
            }
        }
        updateChrome()
    }

    private func isSectionFullySelected(_ section: Int) -> Bool {
        guard selecting, section < sections.count else { return false }
        let count = sections[section].range.count
        let selected = (collectionView.indexPathsForSelectedItems ?? []).filter { $0.section == section }.count
        return count > 0 && selected == count
    }

    private func toggleSection(_ section: Int) {
        guard selecting, section < sections.count else { return }
        let full = isSectionFullySelected(section)
        for item in 0..<sections[section].range.count {
            let path = IndexPath(item: item, section: section)
            if full {
                collectionView.deselectItem(at: path, animated: false)
            } else {
                collectionView.selectItem(at: path, animated: false, scrollPosition: [])
            }
        }
        updateChrome()
    }

    /// 제목·버튼을 지금 상태에 맞춤
    private func updateChrome() {
        guard isViewLoaded else { return }
        if selecting {
            let count = collectionView.indexPathsForSelectedItems?.count ?? 0
            title = count == 0 ? "항목 선택" : "\(count)장 선택"
            navigationItem.hidesBackButton = true
            navigationItem.leftBarButtonItem = UIBarButtonItem(title: "취소", style: .plain, target: self, action: #selector(cancelSelecting))
            let allSelected = count == assets.count && count > 0
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: allSelected ? "전체 해제" : "전체 선택", style: .plain,
                                                                target: self, action: #selector(toggleAll))
            for item in [shareItem, moveItem, deleteItem] {
                item.isEnabled = count > 0
            }
        } else {
            title = folder.title
            navigationItem.hidesBackButton = false
            navigationItem.leftBarButtonItem = nil
            let select = UIBarButtonItem(title: "선택", style: .plain, target: self, action: #selector(startSelecting))
            select.isEnabled = !assets.isEmpty
            navigationItem.rightBarButtonItem = select
        }
        refreshVisibleHeaders()
    }

    // MARK: - 아래 막대

    @objc private func shareSelected() {
        Sharer.share(selectedAssets(), from: self, barButtonItem: shareItem)
    }

    @objc private func moveSelected() {
        Mover.present(from: self, assets: selectedAssets(), sourceAlbumID: folder.albumID) { [weak self] ok in
            if ok { self?.setSelecting(false) }
        }
    }

    @objc private func deleteSelected() {
        let list = selectedAssets()
        guard !list.isEmpty else { return }
        Library.shared.delete(list) { [weak self] ok in
            if ok { self?.setSelecting(false) }
        }
    }
}
