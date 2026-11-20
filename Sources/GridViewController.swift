import Photos
import UIKit

final class AssetCell: UICollectionViewCell {
    static let reuse = "AssetCell"

    let imageView = UIImageView()
    /// 확대 전환이 쓰는 그림 판 (사진 + 길이 글자). 셀 자체는 격자가 자리·변형을 다시 덮어쓰므로 셀 대신 이걸 넘김
    private let thumbView = UIView()
    private let dim = UIView()
    private let badge = UIImageView()
    private let durationLabel = UILabel()

    var assetID: String?
    var requestID: PHImageRequestID = PHInvalidImageRequestID

    /// 확대 전환이 시작하고 돌아올 view
    var zoomSourceView: UIView { thumbView }

    /// 선택 모드인지 (빈 동그라미를 보여 줄지)
    var selecting = false {
        didSet { updateBadge() }
    }

    override var isSelected: Bool {
        didSet { updateBadge() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        thumbView.clipsToBounds = true
        thumbView.frame = contentView.bounds   // 처음 한 번만 (아직 변형이 없을 때)
        contentView.addSubview(thumbView)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .secondarySystemBackground
        imageView.frame = thumbView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        thumbView.addSubview(imageView)

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
        thumbView.addSubview(durationLabel)

        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.isHidden = true
        contentView.addSubview(badge)

        NSLayoutConstraint.activate([
            durationLabel.trailingAnchor.constraint(equalTo: thumbView.trailingAnchor, constant: -5),
            durationLabel.bottomAnchor.constraint(equalTo: thumbView.bottomAnchor, constant: -4),
            badge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            badge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            badge.widthAnchor.constraint(equalToConstant: 24),
            badge.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 확대 전환 중에는 시스템이 thumbView 에 변형을 걸 수 있어서 frame 대신 크기와 중심만 (같으면 건드리지 않음)
        let bounds = contentView.bounds
        let size = CGRect(origin: .zero, size: bounds.size)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        if thumbView.bounds != size { thumbView.bounds = size }
        if thumbView.center != center { thumbView.center = center }
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

/// 앨범에 들어가면 맨 위에 나오는 정사각형 대표 사진 + 이름 + 장수 (순정 사진 앱 모양)
final class HeroHeaderView: UICollectionReusableView {
    static let reuse = "HeroHeaderView"

    let imageView = UIImageView()
    let titleLabel = UILabel()
    let countLabel = UILabel()
    private let glyph = UIImageView(image: UIImage(systemName: "rectangle.stack"))
    private let shade = CAGradientLayer()
    var assetID: String?
    var requestID: PHImageRequestID = PHInvalidImageRequestID

    /// 표지 위 글자(이름·앨범 모양·장수)의 투명도. 확대 전환 동안 카드처럼 사진만 남길 때 씀
    var overlayAlpha: CGFloat {
        get { titleLabel.alpha }
        set {
            titleLabel.alpha = newValue
            countLabel.alpha = newValue
            glyph.alpha = newValue
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        // 확대 전환 동안만 둥글게 함 (평소에는 0). 앨범 카드와 같은 매끄러운 모서리
        layer.cornerCurve = .continuous
        backgroundColor = .systemGray5
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)
        shade.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.6).cgColor]
        layer.addSublayer(shade)
        titleLabel.font = .systemFont(ofSize: 34, weight: .bold)
        titleLabel.textColor = .white
        addSubview(titleLabel)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.6
        countLabel.font = .systemFont(ofSize: 15, weight: .medium)
        countLabel.textColor = .white
        addSubview(countLabel)
        glyph.tintColor = .white
        glyph.contentMode = .scaleAspectFit
        glyph.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        addSubview(glyph)
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
        // 왼쪽 아래: 이름, 그 아래 작은 앨범 모양 + "10개의 항목"
        glyph.frame = CGRect(x: 20, y: bounds.height - 36, width: 16, height: 16)
        countLabel.frame = CGRect(x: 41, y: bounds.height - 39, width: bounds.width - 61, height: 22)
        titleLabel.frame = CGRect(x: 20, y: bounds.height - 82, width: bounds.width - 40, height: 42)
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
    private var layoutAnchor: IndexPath?   // 칸 수를 바꾸는 동안 가운데 남길 사진
    private let columnChoices = [3, 4, 5, 7]
    private var columns = 4
    /// 화면 전환(확대 전환 포함) 중인지. 이때 온 보관함 변경은 전환이 끝난 뒤에 반영
    private var transitioning = false
    private var reloadPending = false
    /// 선택 모드가 '밀어서 뒤로'를 막을 때 쓰는 이름표 (앨범 화면 자체가 막는 것과 따로)
    private let selectionSwipeToken = NSObject()
    /// 화면 바탕. 확대 전환 동안 사라지게 하려고 화면·격자 자체의 바탕색 대신 따로 둠 (화면 자체는 건드리지 않음)
    private let backdrop = UIView()
    /// 확대 전환 동안 표지만 남긴 상태인지 (사진 칸·바탕·표지 글자를 숨기고 표지 모서리를 카드처럼 둥글게)
    private var zoomCollapsed = false

    /// 이 화면이 보여 주는 앨범 ID ("all" = 보관함)
    var folderID: String { folder.id }
    /// 앨범 카드에서 확대 전환으로 열린 앨범 화면인지 (여는 쪽에서 정함)
    var opensWithZoom = false
    /// 앨범 카드의 모서리 반지름 ÷ 카드 한 변 (여는 쪽이 실제 카드에서 재서 넣음).
    /// 확대 전환 동안 표지 모서리를 표지 한 변 × 이 값으로 해서, 카드 크기로 줄었을 때 카드와 같은 모서리가 되게
    var zoomCornerRatio: CGFloat = 0

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
        // 앨범 안에서도 순정처럼 아래 탭 막대를 그대로 둠 (닫히는 확대 전환 끝에서 화면이 덜컥이지 않게)
        let saved = isRoot ? Prefs.gridColumns : Prefs.albumGridColumns
        columns = columnChoices.contains(saved) ? saved : (isRoot ? 4 : 5)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 바탕은 맨 아래 backdrop 이 그림. 확대 전환 동안 이것만 사라지면 표지 밖으로 뒤의 앨범 목록이 보임
        view.backgroundColor = .clear
        backdrop.backgroundColor = .systemBackground
        backdrop.frame = view.bounds
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(backdrop)
        navigationItem.largeTitleDisplayMode = isRoot ? .always : .never

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: makeLayout())
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
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
        holdReloadsDuringTransition()
        blockSwipeAnywhereIfAlbum()
        expandCoverAlongsideOpening(animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 전환을 취소하고 돌아왔을 때도 다시 막음
        blockSwipeAnywhereIfAlbum()
        // 열림이 끝났거나 닫기를 취소하고 돌아옴: 숨긴 것이 남지 않게
        if zoomCollapsed { setZoomCollapsed(false) }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        holdReloadsDuringTransition()
        navigationController?.setBackSwipe(blocked: nil, by: self)
        // 선택 모드인 채로 닫히면(앨범이 지워짐 등) 뒤 화면에 막힌 채로 남지 않게
        if isMovingFromParent { navigationController?.setBackSwipe(blocked: nil, by: selectionSwipeToken) }
        collapseToCoverAlongsideClosing()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if selecting { setSelecting(false) }
        // 화면에서 내려간 뒤에 되돌려 둠 (다시 보일 때 숨긴 채로 남지 않게)
        if zoomCollapsed { setZoomCollapsed(false) }
    }

    // MARK: - 확대 전환 동안 표지만 (카드가 커지고 줄어드는 것처럼)

    /// 확대 전환은 이 화면 전체를 카드 크기로 줄이고 키움. 표지 밖(흰 바탕·사진 칸)이 카드 아래로 늘어져 보이다가
    /// 마지막에 진짜 카드로 바뀌며 덜컥이지 않게, 전환 동안은 표지만 남기고 표지 모서리를 카드 비율대로 둥글게 함.
    /// 표지가 맨 위 제자리에 있을 때만 (위로 넘겨 둔 격자는 표지가 화면 밖이라 숨기면 아무것도 안 남음)
    private var coverIsInZoomRect: Bool {
        guard opensWithZoom, !isRoot, isViewLoaded, collectionView != nil, !sections.isEmpty else { return false }
        return collectionView.contentOffset.y <= -collectionView.adjustedContentInset.top + 1
    }

    /// 열릴 때: 표지만 있는 상태에서 시작해 전환과 함께 나머지가 나타나고 모서리가 펴짐
    private func expandCoverAlongsideOpening(animated: Bool) {
        guard animated, isMovingToParent, let coordinator = transitionCoordinator, coverIsInZoomRect else { return }
        UIView.performWithoutAnimation {
            setZoomCollapsed(true)
            // 처음 보일 칸들을 지금 만들어 둠 (전환 도중에 만들어지는 칸이 바로 다 보이며 튀어나오지 않게)
            view.layoutIfNeeded()
        }
        let queued = coordinator.animate(alongsideTransition: { _ in
            self.setZoomCollapsed(false)
        }, completion: { _ in
            self.setZoomCollapsed(false)
        })
        if !queued {
            UIView.performWithoutAnimation { setZoomCollapsed(false) }
        }
    }

    /// 닫힐 때: 전환과 함께 표지만 남기고 모서리가 카드처럼 둥글어짐. 닫기를 취소하면 되돌림
    private func collapseToCoverAlongsideClosing() {
        guard isMovingFromParent, let coordinator = transitionCoordinator,
              opensWithZoom, !isRoot, isViewLoaded, collectionView != nil, !sections.isEmpty else { return }
        // 아래로 넘겨 둔 채로 닫으면 표지가 화면 밖이라, 먼저 맨 위로 돌려놓고(표지가 제자리에 오게) 줄임.
        // 닫기를 취소하면 보던 자리로 되돌림
        let top = CGPoint(x: collectionView.contentOffset.x, y: -collectionView.adjustedContentInset.top)
        let saved = collectionView.contentOffset
        let scrolled = saved.y > top.y + 1
        coordinator.animate(alongsideTransition: { _ in
            if scrolled {
                UIView.performWithoutAnimation {
                    self.collectionView.setContentOffset(top, animated: false)
                    self.collectionView.layoutIfNeeded()
                }
            }
            self.setZoomCollapsed(true)
        }, completion: { context in
            if context.isCancelled {
                UIView.performWithoutAnimation {
                    self.setZoomCollapsed(false)
                    if scrolled { self.collectionView.setContentOffset(saved, animated: false) }
                }
            }
        })
    }

    private func setZoomCollapsed(_ on: Bool) {
        zoomCollapsed = on
        guard isViewLoaded, collectionView != nil else { return }
        let alpha: CGFloat = on ? 0 : 1
        backdrop.alpha = alpha
        emptyLabel.alpha = alpha
        for cell in collectionView.visibleCells {
            applyZoomCollapse(to: cell)
        }
        let kind = UICollectionView.elementKindSectionHeader
        for path in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
            if let hero = collectionView.supplementaryView(forElementKind: kind, at: path) as? HeroHeaderView {
                applyZoomCollapse(to: hero)
            }
        }
    }

    /// 칸 자체의 alpha 는 격자 배치가 다시 덮어쓰므로 contentView 를 씀 (새로 만들어지거나 다시 쓰이는 칸도 지금 상태로)
    private func applyZoomCollapse(to cell: UICollectionViewCell) {
        let alpha: CGFloat = zoomCollapsed ? 0 : 1
        if cell.contentView.alpha != alpha { cell.contentView.alpha = alpha }
    }

    private func applyZoomCollapse(to hero: HeroHeaderView) {
        hero.overlayAlpha = zoomCollapsed ? 0 : 1
        let side = hero.bounds.width > 0 ? hero.bounds.width : zoomCoverRect().width
        let radius = zoomCollapsed ? side * zoomCornerRatio : 0
        if hero.layer.cornerRadius != radius { hero.layer.cornerRadius = radius }
    }

    /// 앨범 화면(카드에서 확대 전환으로 열림)에서는 iOS 26 의 '어디서나 밀어서 뒤로'를 끔.
    /// 격자 한가운데를 옆으로 쓸어도 닫히지 않게. 왼쪽 가장자리에서 밀기와 위에서 아래로 끌기는 그대로
    private func blockSwipeAnywhereIfAlbum() {
        guard opensWithZoom, navigationController?.topViewController === self else { return }
        navigationController?.setBackSwipe(blocked: .anywhere, by: self)
    }

    /// 화면 전환이 진행 중이면 끝날 때까지 다시 그리기를 미룸 (확대 전환이 잡고 있는 칸이 바뀌거나 다시 배치되지 않게)
    private func holdReloadsDuringTransition() {
        guard let coordinator = transitionCoordinator else { return }
        transitioning = true
        let queued = coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self else { return }
            self.transitioning = false
            if self.reloadPending {
                self.reloadPending = false
                self.reloadFromLibrary(force: false)
            }
        }
        // 전환에 끼워 넣지 못했으면 끝났다는 알림이 안 오므로 미루지 않음
        if !queued { transitioning = false }
    }

    /// 앨범 화면을 닫는 확대 전환을 시작해도 되는지. 왼쪽 가장자리에서 오른쪽으로 밀기, 또는 맨 위에서 아래로 끌기만.
    /// (가운데를 옆으로 쓸기는 안 됨)
    func allowsZoomDismiss(location: CGPoint, velocity: CGPoint) -> Bool {
        if selecting { return false }
        if location.x <= 44 && velocity.x > 0 && velocity.x > abs(velocity.y) { return true }
        guard ZoomGesture.isDownward(velocity), isViewLoaded, collectionView != nil else { return false }
        let top = -collectionView.adjustedContentInset.top
        return collectionView.contentOffset.y <= top + 1
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
        if isRoot {
            Prefs.gridColumns = columns
        } else {
            Prefs.albumGridColumns = columns
        }
        Thumbs.manager.stopCachingImagesForAllAssets()
        view.setNeedsLayout()
        // 칸이 커지고 작아지는 것이 보이게 움직이면서 바꿈. 보던 사진이 가운데 남도록 아래 함수에서 자리를 잡음
        layoutAnchor = anchor
        collectionView.setCollectionViewLayout(makeLayout(), animated: true) { [weak self] _ in
            self?.layoutAnchor = nil
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        targetContentOffsetForProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
        guard let anchor = layoutAnchor, anchor.section < sections.count, anchor.item < sections[anchor.section].range.count,
              let frame = collectionView.collectionViewLayout.layoutAttributesForItem(at: anchor)?.frame else {
            return proposedContentOffset
        }
        let visible = collectionView.bounds.height
        let top = -collectionView.adjustedContentInset.top
        let content = collectionView.collectionViewLayout.collectionViewContentSize.height
        let bottom = max(top, content + collectionView.adjustedContentInset.bottom - visible)
        let y = min(max(top, frame.midY - visible / 2), bottom)
        return CGPoint(x: proposedContentOffset.x, y: y)
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
            // 앨범 표지는 정사각형 (앨범 카드와 같은 모양이라 확대 전환이 딱 맞음)
            let headerHeight: CGFloat = hero ? width : 42
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
        if transitioning {
            reloadPending = true
            return
        }
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
        var new = snapshot.items[folder.id] ?? []
        // 앨범 안은 순정처럼 오래된 항목 순이 기본
        if !newestFirst { new.reverse() }
        let newIDs = new.map(\.localIdentifier)
        if !force && newIDs == assetIDs {
            assets = new   // 순서는 같아도 즐겨찾기·편집 상태가 바뀐 새 값으로
            refreshHero()   // 이름·표지가 바뀌었을 수 있음
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

    /// 앨범 화면은 최신순인지 (보관함·미분류 탭은 늘 최신순)
    private var newestFirst: Bool {
        isRoot || Prefs.newestFirstAlbums.contains(folder.id)
    }

    /// 앨범 카드에서 열리고 닫히는 확대 전환이 맞출 자리: 화면 맨 위의 정사각형 (이 화면 좌표).
    /// 표지의 스크롤 위치를 따라가지 않음 — 따라가면 위로 넘겨 둔 격자에서는 화면 밖 자리가 되고,
    /// 맨 위에서 당겨 늘어나는(고무줄) 동안에는 매 순간 자리가 바뀌어 전환 끝에서 튐.
    /// 맨 위에 있을 때는 표지와 정확히 같은 자리라 열릴 때는 그대로 표지에 맞음
    func zoomCoverRect() -> CGRect {
        var size = isViewLoaded ? view.bounds.size : .zero
        if size.width <= 0 { size = navigationController?.view.bounds.size ?? .zero }
        let side = min(size.width, size.height > 0 ? size.height : size.width)
        return CGRect(x: 0, y: 0, width: size.width, height: side)
    }

    /// 확대 전환이 시작하고 돌아올 자리 (그 사진 칸의 그림 판). 화면 밖이면 nil
    private func thumbnailView(forAssetID id: String) -> UIView? {
        guard let flat = assetIDs.firstIndex(of: id) else { return nil }
        for (section, entry) in sections.enumerated() where entry.range.contains(flat) {
            let path = IndexPath(item: flat - entry.range.lowerBound, section: section)
            return (collectionView.cellForItem(at: path) as? AssetCell)?.zoomSourceView
        }
        return nil
    }

    /// '모든 사진에서 보기': 그 사진이 화면 가운데 오게 스크롤 (보관함 탭에서 씀)
    func reveal(assetID id: String) {
        loadViewIfNeeded()
        if selecting { setSelecting(false) }
        if !assetIDs.contains(id) { reloadFromLibrary(force: false) }
        guard let flat = assetIDs.firstIndex(of: id),
              let section = sections.firstIndex(where: { $0.range.contains(flat) }) else { return }
        let path = IndexPath(item: flat - sections[section].range.lowerBound, section: section)
        view.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(at: path, at: .centeredVertically, animated: false)
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
        applyZoomCollapse(to: cell)
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
            applyZoomCollapse(to: hero)
            return hero
        }
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: DayHeaderView.reuse,
                                                                     for: indexPath) as! DayHeaderView
        configure(header, section: indexPath.section)
        return header
    }

    private func refreshHero() {
        guard !isRoot, isViewLoaded, collectionView != nil else { return }
        let kind = UICollectionView.elementKindSectionHeader
        for path in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
            if let hero = collectionView.supplementaryView(forElementKind: kind, at: path) as? HeroHeaderView {
                configureHero(hero)
            }
        }
    }

    private func configureHero(_ hero: HeroHeaderView) {
        let snapshot = Library.shared.snapshot
        hero.titleLabel.text = snapshot.nodes[folder.id]?.title ?? folder.title
        hero.countLabel.text = "\(assets.count)개의 항목"
        // 사진 앱 앨범은 그 앨범의 대표 사진, 아니면 가장 최근 사진 (앨범 카드와 같은 사진)
        guard let cover = snapshot.cover(folder.id) ?? assets.last else { return }
        let id = cover.localIdentifier
        guard hero.assetID != id else { return }
        if hero.requestID != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(hero.requestID)
        }
        hero.assetID = id
        let scale = traitCollection.displayScale
        let size = CGSize(width: view.bounds.width * scale, height: view.bounds.width * scale)
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
            viewer.fallbackBounds = view.bounds
            if #available(iOS 18.0, *) {
                let options = UIViewController.Transition.ZoomOptions()
                // 분명히 아래로 끌 때만 닫기 시작 (옆으로 빨리 넘기는 것이 닫기로 잡히지 않게).
                // 정보 칸이 떠 있거나 확대 중일 때도 막음
                options.interactiveDismissShouldBegin = { [weak viewer] context in
                    guard let viewer else { return false }
                    return viewer.allowsInteractiveDismiss(location: ZoomGesture.point(context.location),
                                                           velocity: ZoomGesture.point(context.velocity))
                }
                // 흰 화면 전체가 아니라 사진이 보이는 자리만 썸네일과 맞춤. 뒤의 격자는 어둡게 하지 않음
                // (바탕은 보기 화면이 스스로 서서히 나타나고 사라지게 함)
                options.alignmentRectProvider = { [weak viewer] _ in
                    viewer?.zoomAlignmentRect() ?? .zero
                }
                options.dimmingColor = .clear
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
        // 확대 전환 동안 새로 나오는 칸이 다 보이며 튀어나오지 않게, 끝난 뒤에는 숨긴 채로 남지 않게
        applyZoomCollapse(to: cell)
    }

    func collectionView(_ collectionView: UICollectionView, willDisplaySupplementaryView view: UICollectionReusableView,
                        forElementKind elementKind: String, at indexPath: IndexPath) {
        if let hero = view as? HeroHeaderView { applyZoomCollapse(to: hero) }
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
        // 선택하는 동안은 아래 탭 막대 대신 선택 막대 (앨범 안에서도)
        if #available(iOS 18.0, *) {
            tabBarController?.setTabBarHidden(on, animated: true)
        }
        // 옆으로 끌어 선택하는 동안 '밀어서 뒤로'가 잡히지 않게 (보기 화면·앨범 화면이 막는 것과는 따로 기억)
        navigationController?.setBackSwipe(blocked: on ? UINavigationController.BackSwipeBlock.all : nil, by: selectionSwipeToken)
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
            if isRoot {
                navigationItem.rightBarButtonItem = select
            } else {
                // 순정 앨범 화면처럼: [정렬 ⋯] [선택]
                var items: [UIBarButtonItem] = [select, UIBarButtonItem.fixedSpace(8)]
                if folder.isUser {
                    items.append(UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: makeAlbumMenu()))
                }
                items.append(UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal.decrease"), menu: makeSortMenu()))
                navigationItem.rightBarButtonItems = items
            }
        }
        refreshVisibleHeaders()
    }

    // MARK: - 앨범 화면의 위 버튼 (정렬 · ⋯)

    private func makeSortMenu() -> UIMenu {
        let newest = Prefs.newestFirstAlbums.contains(folder.id)
        let oldestAction = UIAction(title: "오래된 항목 순으로", image: UIImage(systemName: "clock.arrow.circlepath"),
                                    state: newest ? .off : .on) { [weak self] _ in
            self?.setNewestFirst(false)
        }
        let newestAction = UIAction(title: "최신 항목 순으로", image: UIImage(systemName: "clock"),
                                    state: newest ? .on : .off) { [weak self] _ in
            self?.setNewestFirst(true)
        }
        return UIMenu(title: "정렬", children: [oldestAction, newestAction])
    }

    private func setNewestFirst(_ on: Bool) {
        var set = Prefs.newestFirstAlbums
        if on {
            set.insert(folder.id)
        } else {
            set.remove(folder.id)
        }
        Prefs.newestFirstAlbums = set
        reloadFromLibrary(force: true)
        updateChrome()
    }

    /// 사진 앱 앨범에서 실제로 할 수 있는 것만: 이름 변경 · 앨범 삭제
    private func makeAlbumMenu() -> UIMenu {
        let id = folder.id
        let rename = UIAction(title: "이름 변경", image: UIImage(systemName: "pencil")) { [weak self] _ in
            guard let self else { return }
            let current = Library.shared.snapshot.nodes[id]?.title ?? self.folder.title
            self.promptText(title: "이름 변경", initial: current, placeholder: "이름", confirm: "저장") { name in
                Library.shared.rename(id, to: name)
            }
        }
        let delete = UIAction(title: "앨범 삭제", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            guard let self else { return }
            let title = Library.shared.snapshot.nodes[id]?.title ?? self.folder.title
            self.confirm(title: "'\(title)' 을(를) 삭제할까요?", message: "앨범만 삭제돼요. 사진은 삭제되지 않아요.", action: "삭제") {
                Library.shared.deleteCollection(id)
            }
        }
        return UIMenu(children: [rename, delete])
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
