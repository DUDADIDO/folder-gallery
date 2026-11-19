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

/// 앨범에 들어가면 맨 위에 나오는 큰 대표 사진 + 이름 + 장수 (순정 사진 앱 모양)
final class HeroHeaderView: UICollectionReusableView {
    static let reuse = "HeroHeaderView"

    let imageView = UIImageView()
    let titleLabel = UILabel()
    let countLabel = UILabel()
    private let shade = CAGradientLayer()
    var assetID: String?
    var requestID: PHImageRequestID = PHInvalidImageRequestID

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = .systemGray5
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)
        shade.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.6).cgColor]
        layer.addSublayer(shade)
        titleLabel.font = .systemFont(ofSize: 34, weight: .bold)
        titleLabel.textColor = .white
        addSubview(titleLabel)
        countLabel.font = .systemFont(ofSize: 17, weight: .medium)
        countLabel.textColor = .white
        addSubview(countLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageView.frame = bounds
        shade.frame = CGRect(x: 0, y: bounds.height * 0.5, width: bounds.width, height: bounds.height * 0.5)
        CATransaction.commit()
        countLabel.frame = CGRect(x: 20, y: bounds.height - 44, width: bounds.width - 40, height: 24)
        titleLabel.frame = CGRect(x: 20, y: bounds.height - 88, width: bounds.width - 40, height: 42)
    }
}

/// 사진 격자. 보관함·미분류 탭은 날짜별로, 앨범 안은 순정 사진 앱처럼 큰 대표 사진 아래 이어서 보여 줌.
/// 길게 누르거나 '선택' 뒤 옆으로 끌면 여러 장 선택
final class GridViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDataSourcePrefetching {
    private let folder: Folder
    private var assets: [PHAsset] = []
    private var assetIDs: [String] = []
    private var sections: [(day: Date, range: Range<Int>)] = []
    private var collectionView: UICollectionView!
    private let emptyLabel = UILabel()
    private var selecting = false
    private var thumbSize = CGSize(width: 240, height: 240)
    private let isRoot: Bool
    private var selectedPerSection: [Int: Int] = [:]
    private let columnChoices = [3, 4, 5, 7]
    private var columns = 4

    private lazy var shareItem = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(shareSelected))
    private lazy var moreItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: makeMoreMenu())
    private lazy var deleteItem = UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain, target: self, action: #selector(deleteSelected))

    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    init(folder: Folder, isRoot: Bool = false) {
        self.folder = folder
        self.isRoot = isRoot
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = !isRoot
        let saved = Prefs.gridColumns
        columns = columnChoices.contains(saved) ? saved : 4
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = isRoot ? .always : .never

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
        collectionView.register(HeroHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: HeroHeaderView.reuse)
        if !isRoot {
            // 대표 사진이 화면 맨 위(상태 막대 아래)까지 차게
            collectionView.contentInsetAdjustmentBehavior = .never
        }
        view.addSubview(collectionView)

        emptyLabel.text = "사진이 없어요"
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.font = .systemFont(ofSize: 16)

        let press = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        press.minimumPressDuration = 0.35
        collectionView.addGestureRecognizer(press)

        // 두 손가락으로 벌리고 오므려 칸 수 바꾸기
        collectionView.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:))))

        toolbarItems = [shareItem, UIBarButtonItem.flexibleSpace(), moreItem, UIBarButtonItem.flexibleSpace(), deleteItem]

        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: Library.didChange, object: nil)
        reloadFromLibrary(force: true)
        updateChrome()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let scale = traitCollection.displayScale
        let side = max(40, view.bounds.width / CGFloat(columns)) * scale
        thumbSize = CGSize(width: side, height: side)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.setToolbarHidden(!selecting, animated: animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if selecting { setSelecting(false) }
    }

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .ended, let index = columnChoices.firstIndex(of: columns) else { return }
        var next = index
        if gesture.scale > 1.25 {
            next = max(0, index - 1)                         // 벌리면 크게
        } else if gesture.scale < 0.8 {
            next = min(columnChoices.count - 1, index + 1)   // 오므리면 작게
        }
        guard next != index else { return }
        // 보고 있던 자리를 기억했다가 칸 수를 바꾼 뒤 그 사진으로 돌아감
        let anchor = collectionView.indexPathForItem(at: gesture.location(in: collectionView))
            ?? collectionView.indexPathsForVisibleItems.min()
        columns = columnChoices[next]
        Prefs.gridColumns = columns
        Thumbs.manager.stopCachingImagesForAllAssets()
        view.setNeedsLayout()
        collectionView.setCollectionViewLayout(makeLayout(), animated: false)
        collectionView.layoutIfNeeded()
        if let anchor, anchor.section < sections.count, anchor.item < sections[anchor.section].range.count {
            collectionView.scrollToItem(at: anchor, at: .centeredVertically, animated: false)
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        guard !isRoot, isViewLoaded, collectionView != nil else { return }
        collectionView.contentInset.bottom = view.safeAreaInsets.bottom
        collectionView.verticalScrollIndicatorInsets = UIEdgeInsets(top: view.safeAreaInsets.top, left: 0,
                                                                    bottom: view.safeAreaInsets.bottom, right: 0)
    }

    private func makeLayout() -> UICollectionViewLayout {
        let columns = self.columns
        let hero = !isRoot
        return UICollectionViewCompositionalLayout { _, environment in
            // 칸 크기를 화면 너비에서 직접 계산 (비율 지정은 칸이 화면 전체 너비로 잡힘)
            let spacing: CGFloat = 2
            let width = environment.container.effectiveContentSize.width
            let side = max(20, floor((width - spacing * CGFloat(columns - 1)) / CGFloat(columns)))
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(side),
                                                                                 heightDimension: .absolute(side)))
            let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(side))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
            group.interItemSpacing = .fixed(spacing)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = spacing
            let headerHeight: CGFloat = hero ? min(width * 1.15, 460) : 42
            let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(headerHeight))
            let header = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: headerSize,
                                                                     elementKind: UICollectionView.elementKindSectionHeader,
                                                                     alignment: .top)
            section.boundarySupplementaryItems = [header]
            return section
        }
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
        if !force && newIDs == assetIDs {
            assets = new   // 순서는 같아도 즐겨찾기·편집 상태가 바뀐 새 값으로
            return
        }

        let keep = Set(selectedAssets().map(\.localIdentifier))
        assets = new
        assetIDs = newIDs
        buildSections()
        collectionView.reloadData()
        if !Library.shared.canRead {
            emptyLabel.text = "사진 접근 권한이 필요해요.\n앨범 탭에서 설정을 열 수 있어요."
            collectionView.backgroundView = emptyLabel
        } else {
            emptyLabel.text = "사진이 없어요"
            collectionView.backgroundView = (assets.isEmpty && snapshot.loaded) ? emptyLabel : nil
        }

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
        if !isRoot {
            // 앨범 안: 날짜로 나누지 않고 한 덩어리
            sections = assets.isEmpty ? [] : [(day: Date(), range: 0..<assets.count)]
            return
        }
        let calendar = Calendar.current
        var result: [(day: Date, range: Range<Int>)] = []
        var start = 0
        var current: Date?
        var dayEnd = Date.distantPast   // current 날의 끝. 최신순이라 같은 날이 이어서 나옴
        for (index, asset) in assets.enumerated() {
            let date = asset.creationDate ?? .distantPast
            var day = current ?? .distantFuture
            if current == nil || date < day || date >= dayEnd {
                day = calendar.startOfDay(for: date)
                dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)
            }
            if day != current {
                if let current { result.append((current, start..<index)) }
                current = day
                start = index
            }
        }
        if let current { result.append((current, start..<assets.count)) }
        sections = result
    }

    /// 확대 전환이 시작하고 돌아올 자리 (그 사진의 칸). 화면 밖이면 nil
    private func thumbnailView(forAssetID id: String) -> UIView? {
        guard let flat = assetIDs.firstIndex(of: id) else { return nil }
        for (section, entry) in sections.enumerated() where entry.range.contains(flat) {
            let path = IndexPath(item: flat - entry.range.lowerBound, section: section)
            return collectionView.cellForItem(at: path)
        }
        return nil
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
        if !isRoot {
            let hero = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: HeroHeaderView.reuse,
                                                                       for: indexPath) as! HeroHeaderView
            configureHero(hero)
            return hero
        }
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: DayHeaderView.reuse,
                                                                     for: indexPath) as! DayHeaderView
        configure(header, section: indexPath.section)
        return header
    }

    private func configureHero(_ hero: HeroHeaderView) {
        hero.titleLabel.text = folder.title
        hero.countLabel.text = "\(assets.count)개의 항목"
        guard let cover = assets.first else { return }
        let id = cover.localIdentifier
        guard hero.assetID != id else { return }
        if hero.requestID != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(hero.requestID)
        }
        hero.assetID = id
        let scale = traitCollection.displayScale
        let size = CGSize(width: view.bounds.width * scale, height: view.bounds.width * 1.15 * scale)
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        hero.requestID = PHImageManager.default().requestImage(for: cover, targetSize: size, contentMode: .aspectFill,
                                                               options: options) { [weak hero] image, _ in
            guard let hero, hero.assetID == id, let image else { return }
            hero.imageView.image = image
        }
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
            if #available(iOS 18.0, *) {
                let options = UIViewController.Transition.ZoomOptions()
                // 정보 칸이 떠 있거나 확대 중일 때는 끌어내려 닫기를 막음
                options.interactiveDismissShouldBegin = { [weak viewer] _ in
                    viewer?.allowsInteractiveDismiss ?? true
                }
                viewer.preferredTransition = .zoom(options: options, sourceViewProvider: { [weak self, weak viewer] _ in
                    guard let self, let id = viewer?.visibleAssetID else { return nil }
                    return self.thumbnailView(forAssetID: id)
                })
            }
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
        selecting   // 길게 누르거나 '선택'으로 들어온 뒤에만. 아니면 두 손가락 벌리기가 선택으로 잡힘
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
        if isRoot, #available(iOS 18.0, *) {
            tabBarController?.setTabBarHidden(on, animated: true)
        }
        // 옆으로 끌어 선택하는 동안 '밀어서 뒤로'가 잡히지 않게
        navigationController?.setBackSwipeEnabled(!on)
        navigationController?.setToolbarHidden(!on, animated: true)
        updateChrome()
    }

    /// 미분류 사진을 한 장씩 넘기며 정리. 모든 사진을 보게 되니 Face ID 로 확인
    @objc private func startSorter() {
        let list = assets
        guard !list.isEmpty else { return }
        Auth.verify(reason: "사진 정리를 시작하려면 인증이 필요해요") { [weak self] ok in
            guard ok, let self else { return }
            self.navigationController?.pushViewController(SorterViewController(assets: list), animated: true)
        }
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
        return count > 0 && (selectedPerSection[section] ?? 0) == count
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
        // 선택 목록은 한 번만 읽어서 날짜별 개수를 세어 둠 (머리글마다 다시 세지 않게)
        let selectedPaths = selecting ? (collectionView.indexPathsForSelectedItems ?? []) : []
        var perSection: [Int: Int] = [:]
        for path in selectedPaths {
            perSection[path.section, default: 0] += 1
        }
        selectedPerSection = perSection
        if selecting {
            let count = selectedPaths.count
            navigationItem.title = count == 0 ? "항목 선택" : "\(count)장 선택"
            navigationItem.hidesBackButton = true
            navigationItem.leftBarButtonItem = UIBarButtonItem(title: "취소", style: .plain, target: self, action: #selector(cancelSelecting))
            let allSelected = count == assets.count && count > 0
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: allSelected ? "전체 해제" : "전체 선택", style: .plain,
                                                                target: self, action: #selector(toggleAll))
            for item in [shareItem, moreItem, deleteItem] {
                item.isEnabled = count > 0
            }
        } else {
            // 앨범 안에서는 이름이 큰 대표 사진 위에 있어서 위 막대 제목은 비움
            navigationItem.title = isRoot ? folder.title : nil
            navigationItem.hidesBackButton = false
            if folder.id == "unsorted" {
                let sort = UIBarButtonItem(title: "정리하기", style: .plain, target: self, action: #selector(startSorter))
                sort.isEnabled = !assets.isEmpty
                navigationItem.leftBarButtonItem = sort
            } else {
                navigationItem.leftBarButtonItem = nil
            }
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

    /// 갤럭시의 '더보기': 앨범으로 이동 · 앨범으로 복사
    private func makeMoreMenu() -> UIMenu {
        var actions: [UIAction] = [
            UIAction(title: "앨범으로 이동", image: UIImage(systemName: "folder")) { [weak self] _ in self?.sendSelected(copy: false) },
            UIAction(title: "앨범으로 복사", image: UIImage(systemName: "plus.rectangle.on.folder")) { [weak self] _ in self?.sendSelected(copy: true) },
        ]
        if folder.isUser {
            actions.append(UIAction(title: "이 앨범에서 빼기", image: UIImage(systemName: "minus.circle")) { [weak self] _ in
                self?.removeSelectedFromAlbum()
            })
        }
        return UIMenu(children: actions)
    }

    private func sendSelected(copy: Bool) {
        Mover.present(from: self, assets: selectedAssets(), sourceAlbumID: folder.albumID, copy: copy) { [weak self] ok in
            if ok { self?.setSelecting(false) }
        }
    }

    private func removeSelectedFromAlbum() {
        let list = selectedAssets()
        guard !list.isEmpty, let id = folder.albumID, let album = Library.shared.album(id: id) else { return }
        Library.shared.remove(list, from: album) { [weak self] ok in
            if ok {
                self?.setSelecting(false)
                self?.toast("\(list.count)장을 앨범에서 뺐어요. 사진은 그대로 있어요")
            }
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
