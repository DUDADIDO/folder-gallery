import Photos
import UIKit

extension Prefs {
    /// 앨범 화면을 목록으로 볼지 (순정 사진 앱의 '목록 보기')
    static var albumListMode: Bool {
        get { UserDefaults.standard.bool(forKey: "albumListMode") }
        set { UserDefaults.standard.set(newValue, forKey: "albumListMode") }
    }
}

/// 앨범·폴더 한 칸. 순정 사진 앱처럼 앨범은 사진 위에 이름, 폴더는 흰 카드에 사진 넉 장
final class AlbumCell: UICollectionViewCell {
    static let reuse = "AlbumCell"

    enum Style {
        case card   // 격자: 큰 카드
        case row    // 목록: 왼쪽에 작은 그림, 오른쪽에 이름
    }

    var style: Style = .card {
        didSet { if style != oldValue { setNeedsLayout() } }
    }
    private(set) var isFolder = false

    private let card = UIView()
    private let coverView = UIImageView()
    private let placeholder = UIImageView()
    private let shade = CAGradientLayer()
    private var tiles: [UIImageView] = []
    private let titleLabel = UILabel()
    private let countIcon = UIImageView()
    private let countLabel = UILabel()
    private let separator = UIView()

    private var requests: [PHImageRequestID] = []
    private var token = 0

    /// 확대 전환이 시작하고 돌아올 둥근 카드 (모서리가 둥글어야 닫힐 때 네모 귀퉁이가 안 보임)
    var cardView: UIView { card }

    /// 꾹 눌렀을 때·끌 때 떠오르는 모양 (카드의 둥근 모서리 그대로).
    /// card.frame 은 변형이 걸려 있으면 믿을 수 없어서 크기와 중심으로 셈
    var liftPath: UIBezierPath {
        let size = card.bounds.size
        let rect = CGRect(x: card.center.x - size.width / 2, y: card.center.y - size.height / 2,
                          width: size.width, height: size.height)
        return UIBezierPath(roundedRect: rect, cornerRadius: card.layer.cornerRadius)
    }

    /// card 를 rect(contentView 좌표)에 놓음. 확대 전환이 card 에 변형을 걸고 있어도 안전하게
    /// frame 대신 크기와 중심만, 그것도 바뀌었을 때만 씀
    private func setCardCorner(_ radius: CGFloat) {
        if card.layer.cornerRadius != radius { card.layer.cornerRadius = radius }
    }

    private func placeCard(_ rect: CGRect) {
        let bounds = CGRect(origin: .zero, size: rect.size)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if card.bounds != bounds { card.bounds = bounds }
        if card.center != center { card.center = center }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(card)
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        card.addSubview(coverView)

        placeholder.image = UIImage(systemName: "photo.on.rectangle")
        placeholder.tintColor = .tertiaryLabel
        placeholder.contentMode = .scaleAspectFit
        card.addSubview(placeholder)

        shade.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.38).cgColor]
        card.layer.addSublayer(shade)

        for _ in 0..<4 {
            let tile = UIImageView()
            tile.contentMode = .scaleAspectFill
            tile.clipsToBounds = true
            tile.backgroundColor = .systemGray6
            tile.layer.cornerCurve = .continuous
            card.addSubview(tile)
            tiles.append(tile)
        }

        titleLabel.font = .systemFont(ofSize: 17, weight: .medium)
        contentView.addSubview(titleLabel)

        countIcon.image = UIImage(systemName: "rectangle.stack.fill")
        countIcon.tintColor = .secondaryLabel
        countIcon.contentMode = .scaleAspectFit
        contentView.addSubview(countIcon)
        countLabel.font = .systemFont(ofSize: 15)
        countLabel.textColor = .secondaryLabel
        contentView.addSubview(countLabel)

        separator.backgroundColor = .separator
        contentView.addSubview(separator)

        contentView.layer.shadowColor = UIColor.black.cgColor
        contentView.layer.shadowOpacity = 0.08
        contentView.layer.shadowRadius = 10
        contentView.layer.shadowOffset = CGSize(width: 0, height: 4)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelRequests()
        coverView.image = nil
        for tile in tiles {
            tile.image = nil
        }
    }

    private func cancelRequests() {
        token += 1
        for id in requests {
            Thumbs.manager.cancelImageRequest(id)
        }
        requests = []
    }

    /// covers: 앨범이면 대표 사진 1장, 폴더면 안의 앨범 대표 사진 최대 4장
    /// 장수 글자만 바꿈 (표지는 그대로)
    func setCountText(_ text: String) {
        if countLabel.text != text { countLabel.text = text }
    }

    func configure(title: String, countText: String, isFolder: Bool, covers: [PHAsset], thumbSize: CGSize) {
        cancelRequests()
        self.isFolder = isFolder
        titleLabel.text = title
        countLabel.text = countText
        coverView.image = nil
        for tile in tiles {
            tile.image = nil
        }
        let current = token
        if isFolder {
            for (index, asset) in covers.prefix(4).enumerated() {
                let tile = tiles[index]
                let id = Thumbs.manager.requestImage(for: asset, targetSize: thumbSize, contentMode: .aspectFill,
                                                     options: Thumbs.options) { [weak self, weak tile] image, _ in
                    guard let self, self.token == current, let image else { return }
                    tile?.image = image
                }
                requests.append(id)
            }
        } else if let asset = covers.first {
            let id = Thumbs.manager.requestImage(for: asset, targetSize: thumbSize, contentMode: .aspectFill,
                                                 options: Thumbs.options) { [weak self] image, _ in
                guard let self, self.token == current, let image else { return }
                self.coverView.image = image
            }
            requests.append(id)
        }
        placeholder.isHidden = isFolder || !covers.isEmpty
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // 이 칸의 card 는 확대 전환의 출발·도착 view 라서, 전환 중에 이 배치가 돌아도 card 를 흔들지 않게
        // card 자체는 placeCard(크기+중심, 바뀐 것만)로만, 모서리도 바뀌었을 때만 씀. 안쪽 view 는 card 안 좌표로
        let bounds = contentView.bounds
        switch style {
        case .card:
            placeCard(bounds)
            // 순정 iOS 27 모음의 앨범 카드: 한 변의 약 13% 둥글게 (115pt 카드에 15pt)
            setCardCorner(max(12, (bounds.width * 0.13).rounded()))
            contentView.layer.shadowOpacity = 0.08
            separator.isHidden = true
            countIcon.isHidden = true
            countLabel.isHidden = true
            titleLabel.font = .systemFont(ofSize: 17, weight: .medium)
            if isFolder {
                // 흰 카드 + 사진 넉 장 + 아래 이름
                card.backgroundColor = .secondarySystemGroupedBackground
                coverView.isHidden = true
                shade.isHidden = true
                let pad: CGFloat = 8, gap: CGFloat = 6, footer: CGFloat = 34
                let tileWidth = (bounds.width - pad * 2 - gap) / 2
                let tileHeight = max(10, (bounds.height - pad - footer - gap) / 2)
                for (index, tile) in tiles.enumerated() {
                    tile.isHidden = false
                    tile.layer.cornerRadius = 6
                    let column = CGFloat(index % 2), row = CGFloat(index / 2)
                    tile.frame = CGRect(x: pad + column * (tileWidth + gap), y: pad + row * (tileHeight + gap),
                                        width: tileWidth, height: tileHeight)
                }
                titleLabel.textColor = .label
                titleLabel.frame = CGRect(x: 12, y: bounds.height - footer + 4, width: bounds.width - 24, height: 24)
            } else {
                // 사진이 카드 전체, 아래에 흰 이름
                card.backgroundColor = .systemGray5
                coverView.isHidden = false
                coverView.frame = CGRect(origin: .zero, size: bounds.size)
                for tile in tiles {
                    tile.isHidden = true
                }
                shade.isHidden = false
                shade.frame = CGRect(x: 0, y: bounds.height * 0.55, width: bounds.width, height: bounds.height * 0.45)
                placeholder.frame = CGRect(x: bounds.midX - 22, y: bounds.midY - 30, width: 44, height: 36)
                titleLabel.textColor = .white
                // 순정처럼 왼쪽 아래에 흰 이름
                titleLabel.frame = CGRect(x: 10, y: bounds.height - 34, width: bounds.width - 20, height: 24)
            }
        case .row:
            contentView.layer.shadowOpacity = 0
            let side = bounds.height - 16
            placeCard(CGRect(x: 0, y: 8, width: side, height: side))
            setCardCorner(16)
            shade.isHidden = true
            separator.isHidden = false
            separator.frame = CGRect(x: 0, y: bounds.height - 0.5, width: bounds.width, height: 0.5)
            if isFolder {
                card.backgroundColor = .systemGray6
                coverView.isHidden = true
                let gap: CGFloat = 2
                let tileSide = (side - gap) / 2
                for (index, tile) in tiles.enumerated() {
                    tile.isHidden = false
                    tile.layer.cornerRadius = 0
                    let column = CGFloat(index % 2), row = CGFloat(index / 2)
                    tile.frame = CGRect(x: column * (tileSide + gap), y: row * (tileSide + gap), width: tileSide, height: tileSide)
                }
            } else {
                card.backgroundColor = .systemGray5
                coverView.isHidden = false
                coverView.frame = CGRect(x: 0, y: 0, width: side, height: side)
                for tile in tiles {
                    tile.isHidden = true
                }
                placeholder.frame = CGRect(x: side / 2 - 16, y: side / 2 - 14, width: 32, height: 28)
            }
            let textX = side + 14
            titleLabel.font = .systemFont(ofSize: 17)
            titleLabel.textColor = .label
            titleLabel.frame = CGRect(x: textX, y: bounds.midY - 24, width: bounds.width - textX, height: 24)
            countIcon.isHidden = !isFolder
            countLabel.isHidden = false
            var countX = textX
            if isFolder {
                countIcon.frame = CGRect(x: textX, y: bounds.midY + 3, width: 18, height: 16)
                countX += 24
            }
            countLabel.frame = CGRect(x: countX, y: bounds.midY, width: bounds.width - countX, height: 22)
        }
    }
}

final class SectionHeaderView: UICollectionReusableView {
    static let reuse = "SectionHeaderView"

    let label = UILabel()
    let detail = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 22, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabel
        detail.textAlignment = .right
        detail.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        addSubview(detail)
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

/// 앨범 화면. 사진 앱에서 만든 앨범·폴더를 그 구조와 순서 그대로 보여 주고,
/// 맨 위에 자동 분류 앨범(카메라·스크린샷·저장한 앱별…)을 따로 보여 줌.
/// 세 가지로 쓰임: 앨범 탭 첫 화면(.top), 폴더 안(.folder), 숨긴 앨범 탭(.hidden — Face ID 로 열림)
final class FoldersViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate,
                                   UICollectionViewDragDelegate, UICollectionViewDropDelegate {
    enum Mode: Equatable {
        case top
        case folder(String)   // "list:…"
        case hidden
    }

    private struct Group {
        var title: String
        var folders: [Folder]
        var isAuto: Bool
    }

    private let mode: Mode
    private var collectionView: UICollectionView!
    private var groups: [Group] = []
    private var lastSignature: [String] = []
    private var listMode = Prefs.albumListMode
    private let messageView = UIView()
    private let messageLabel = UILabel()
    private let messageButton = UIButton(type: .system)
    private var messageAction: (() -> Void)?
    private var warnedLimited = false
    private var thumbSize = CGSize(width: 500, height: 500)
    /// 화면 전환(확대 전환 포함) 중인지. 이때 온 변경은 끝난 뒤에 반영
    private var transitioning = false
    private var reloadPending = false

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

    /// 이 화면이 보여 주는 사진 앱 폴더 ("top" 또는 "list:…")
    private var container: String {
        if case .folder(let id) = mode { return id }
        return Snapshot.top
    }

    private var isLocked: Bool { mode == .hidden && !unlocked }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        // 순정 iOS 27 모음처럼: 탭 첫 화면(앨범·숨긴 앨범)은 왼쪽 큰 제목, 폴더 안은 작은 제목
        navigationItem.largeTitleDisplayMode = mode == .top || mode == .hidden ? .always : .never
        switch mode {
        case .top:
            navigationItem.title = "앨범"
        case .folder(let id):
            navigationItem.title = Library.shared.snapshot.nodes[id]?.title ?? "폴더"
        case .hidden:
            navigationItem.title = "숨긴 앨범"
        }

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: makeLayout())
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // 순정 '앨범' 화면처럼 흰 바탕
        collectionView.backgroundColor = .systemBackground
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        // 꾹 눌러 끌면 순서 바꾸기 (폴더 위에 놓으면 폴더에 넣기)
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        collectionView.dragInteractionEnabled = true
        collectionView.register(AlbumCell.self, forCellWithReuseIdentifier: AlbumCell.reuse)
        collectionView.register(SectionHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: SectionHeaderView.reuse)
        view.addSubview(collectionView)
        // 큰 제목이 스크롤을 따라 접히게
        setContentScrollView(collectionView)

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
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.setToolbarHidden(true, animated: animated)
        // 앨범 화면이 카드로 줄어들며 닫히는 중에는 다시 그리지 않음 (전환이 잡고 있는 카드가 바뀌거나 다시 배치되면
        // 끝에서 카드가 커졌다가 덜컥 돌아옴). 전환이 끝나면 그때 반영
        if holdReloadsDuringTransition() {
            reloadPending = true
        } else {
            reload(force: false)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        _ = holdReloadsDuringTransition()
    }

    /// 화면 전환이 진행 중이면 끝날 때까지 보관함 변경 반영을 미룸. 미루기 시작했으면 true
    private func holdReloadsDuringTransition() -> Bool {
        guard let coordinator = transitionCoordinator else { return false }
        transitioning = true
        let queued = coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self else { return }
            self.transitioning = false
            if self.reloadPending {
                self.reloadPending = false
                self.reload(force: false)
            }
        }
        // 전환에 끼워 넣지 못했으면 끝났다는 알림이 안 오므로 미루지 않음 (안 그러면 계속 미뤄진 채로 남음)
        if !queued {
            transitioning = false
            return false
        }
        return true
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 아래 막대는 숨기고 탭 막대는 보이게 (어긋난 채로 남지 않게. 맞으면 건드리지 않음)
        navigationController?.ensureBrowsingBars(of: self)
        if isLocked { authenticate() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let side = max(120, view.bounds.width / 2) * traitCollection.displayScale
        thumbSize = CGSize(width: side, height: side)
    }

    // MARK: - 배치 (순정 사진 앱: 두 칸 큰 카드, 또는 목록)

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, environment in
            // 순정 iOS 27: 양옆 16, 카드 사이 8. 자동 분류 줄은 모음의 앨범 줄처럼 한 화면에 3칸 (약 115pt)
            let inset: CGFloat = 16
            let gap: CGFloat = 8
            let width = environment.container.effectiveContentSize.width
            let cardSide = max(80, floor((width - inset * 2 - gap * 2) / 3))
            let auto = self?.groups.indices.contains(index) == true && self?.groups[index].isAuto == true
            let list = self?.listMode ?? false

            let section: NSCollectionLayoutSection
            if auto {
                // 자동 분류: 옆으로 넘기는 작은 카드
                let side = cardSide
                let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(side),
                                                                                     heightDimension: .absolute(side)))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(side),
                                                                                                  heightDimension: .absolute(side)),
                                                               subitems: [item])
                section = NSCollectionLayoutSection(group: group)
                section.interGroupSpacing = gap
                section.orthogonalScrollingBehavior = .continuous
                section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: inset, bottom: 22, trailing: inset)
            } else if list {
                let height: CGFloat = 100
                let rowWidth = max(100, width - inset * 2)
                let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(rowWidth),
                                                                                     heightDimension: .absolute(height)))
                let group = NSCollectionLayoutGroup.vertical(layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(rowWidth),
                                                                                                heightDimension: .absolute(height)),
                                                             subitems: [item])
                section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: inset, bottom: 24, trailing: inset)
            } else {
                // 순정 iOS 27 '앨범' 화면: 두 칸 (양옆 16, 사이 8 — iPhone 14 Pro 에서 약 176pt)
                let side = max(80, floor((width - inset * 2 - gap) / 2))
                let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(side),
                                                                                     heightDimension: .absolute(side)))
                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(side))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
                group.interItemSpacing = .fixed(gap)
                section = NSCollectionLayoutSection(group: group)
                section.interGroupSpacing = gap
                section.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: inset, bottom: 24, trailing: inset)
            }
            let titled = self?.groups.indices.contains(index) == true && self?.groups[index].title.isEmpty == false
            if titled {
                let headerSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(40))
                section.boundarySupplementaryItems = [
                    NSCollectionLayoutBoundarySupplementaryItem(layoutSize: headerSize,
                                                                elementKind: UICollectionView.elementKindSectionHeader,
                                                                alignment: .top),
                ]
            } else {
                section.contentInsets.top = 16
            }
            return section
        }
    }

    // MARK: - 안내 화면 (권한 · 잠금)

    private func setUpMessageView() {
        messageView.backgroundColor = .systemGroupedBackground
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
        if transitioning {
            reloadPending = true
            return
        }
        reload(force: false)
    }

    private func photoCount(_ folder: Folder, _ snapshot: Snapshot) -> Int {
        if folder.isGroup {
            var total = 0
            for album in snapshot.albums(under: folder.id) {
                total += snapshot.items[album.id]?.count ?? 0
            }
            return total
        }
        return snapshot.items[folder.id]?.count ?? 0
    }

    private func newestDate(_ folder: Folder, _ snapshot: Snapshot) -> Date {
        if folder.isGroup {
            var newest = Date.distantPast
            for album in snapshot.albums(under: folder.id) {
                if let date = snapshot.items[album.id]?.first?.creationDate, date > newest { newest = date }
            }
            return newest
        }
        return snapshot.items[folder.id]?.first?.creationDate ?? .distantPast
    }

    /// 정렬 0: 사용자 설정 순(사진 앱 순서 그대로)
    private func sorted(_ list: [Folder], _ snapshot: Snapshot) -> [Folder] {
        switch Prefs.albumSort {
        case 1:
            return list.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case 2:
            return list.sorted { a, b in
                let ca = self.photoCount(a, snapshot)
                let cb = self.photoCount(b, snapshot)
                if ca != cb { return ca > cb }
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
        case 3:
            return list.sorted { self.newestDate($0, snapshot) > self.newestDate($1, snapshot) }
        default:
            return list
        }
    }

    private func currentGroups(_ snapshot: Snapshot) -> [Group] {
        let hidden = Prefs.hiddenAlbums
        func nodes(in container: String) -> [Folder] {
            (snapshot.children[container] ?? []).compactMap { snapshot.nodes[$0] }
        }
        switch mode {
        case .top:
            let auto = snapshot.autoFolders.filter { !hidden.contains($0.id) }
            let mine = sorted(nodes(in: Snapshot.top).filter { !hidden.contains($0.id) }, snapshot)
            var result: [Group] = []
            if !auto.isEmpty { result.append(Group(title: "자동 분류", folders: auto, isAuto: true)) }
            result.append(Group(title: "나의 앨범", folders: mine, isAuto: false))
            return result
        case .folder(let id):
            let mine = sorted(nodes(in: id).filter { !hidden.contains($0.id) }, snapshot)
            return [Group(title: "", folders: mine, isAuto: false)]
        case .hidden:
            var list = snapshot.autoFolders.filter { hidden.contains($0.id) }
            list.append(contentsOf: snapshot.nodes.values.filter { hidden.contains($0.id) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
            return [Group(title: "", folders: list, isAuto: false)]
        }
    }

    /// 앨범이면 대표 사진 1장, 폴더면 안의 앨범 대표 사진 최대 4장
    private func covers(_ folder: Folder, _ snapshot: Snapshot) -> [PHAsset] {
        if folder.isGroup {
            var result: [PHAsset] = []
            for album in snapshot.albums(under: folder.id) {
                if let cover = snapshot.cover(album.id) { result.append(cover) }
                if result.count == 4 { break }
            }
            return result
        }
        if let cover = snapshot.cover(folder.id) { return [cover] }
        return []
    }

    private func countText(_ folder: Folder, _ snapshot: Snapshot) -> String {
        if folder.isGroup {
            return String(snapshot.children[folder.id]?.count ?? 0)
        }
        // 켤 때의 임시 목록(자동 분류)은 장수를 모름: 전체 목록이 온 뒤에 (틀린 숫자를 보이지 않게)
        if snapshot.isProvisional(folder.id) { return "" }
        return String(snapshot.items[folder.id]?.count ?? 0)
    }

    private func signature(_ groups: [Group], _ snapshot: Snapshot) -> [String] {
        var result: [String] = []
        for group in groups {
            result.append("#" + group.title)
            for folder in group.folders {
                let ids = covers(folder, snapshot).map { $0.localIdentifier }.joined(separator: ",")
                result.append([folder.id, folder.title, ids].joined(separator: "|"))
            }
        }
        return result
    }

    private func reload(force: Bool) {
        guard isViewLoaded else { return }
        let library = Library.shared
        let snapshot = library.snapshot

        if case .folder(let id) = mode, snapshot.loaded {
            guard let node = snapshot.nodes[id] else {
                // 폴더가 없어짐 (켤 때의 목록도 사진 앱 구조는 진짜라 그대로 판단)
                if navigationController?.topViewController === self {
                    navigationController?.popViewController(animated: true)
                }
                return
            }
            navigationItem.title = node.title
        }

        if isLocked {
            groups = []
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

        let newGroups = snapshot.loaded ? currentGroups(snapshot) : []
        // 구성과 대표 사진이 그대로면 다시 그리지 않음 (분류 도중 표지가 깜빡이지 않게)
        let newSignature = signature(newGroups, snapshot)
        let sameShape = !force && newSignature == lastSignature
        groups = newGroups
        lastSignature = newSignature
        if sameShape {
            refreshVisibleText()
        } else {
            collectionView.reloadData()
        }
    }

    private func folder(at indexPath: IndexPath) -> Folder? {
        guard indexPath.section < groups.count, indexPath.item < groups[indexPath.section].folders.count else { return nil }
        return groups[indexPath.section].folders[indexPath.item]
    }

    private func refreshVisibleText() {
        let kind = UICollectionView.elementKindSectionHeader
        for indexPath in collectionView.indexPathsForVisibleSupplementaryElements(ofKind: kind) {
            if let header = collectionView.supplementaryView(forElementKind: kind, at: indexPath) as? SectionHeaderView {
                configure(header, section: indexPath.section)
            }
        }
        // 장수만 바꿈 (표지는 다시 받지 않음. 임시 목록에서 전체 목록으로 바뀔 때 숫자가 나타나게)
        let snapshot = Library.shared.snapshot
        for indexPath in collectionView.indexPathsForVisibleItems {
            guard let folder = folder(at: indexPath),
                  let cell = collectionView.cellForItem(at: indexPath) as? AlbumCell else { continue }
            cell.setCountText(countText(folder, snapshot))
        }
    }

    private func configure(_ header: SectionHeaderView, section: Int) {
        guard section < groups.count else { return }
        let group = groups[section]
        let snapshot = Library.shared.snapshot
        header.label.text = group.title
        if group.isAuto && snapshot.pending > 0 {
            header.detail.text = "분류 중 \(snapshot.total - snapshot.pending) / \(snapshot.total)"
        } else if group.folders.isEmpty {
            switch mode {
            case .top: header.detail.text = "+ 로 앨범이나 폴더를 만들어요"
            case .folder: header.detail.text = "비어 있어요"
            case .hidden: header.detail.text = "숨긴 앨범이 없어요"
            }
        } else {
            header.detail.text = ""
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
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AlbumCell.reuse, for: indexPath) as! AlbumCell
        let group = groups[indexPath.section]
        let folder = group.folders[indexPath.item]
        let snapshot = Library.shared.snapshot
        cell.style = (listMode && !group.isAuto) ? .row : .card
        cell.configure(title: folder.title, countText: countText(folder, snapshot), isFolder: folder.isGroup,
                       covers: covers(folder, snapshot), thumbSize: thumbSize)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: SectionHeaderView.reuse,
                                                                     for: indexPath) as! SectionHeaderView
        configure(header, section: indexPath.section)
        return header
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard let folder = folder(at: indexPath) else { return }
        let next: UIViewController = folder.isGroup ? FoldersViewController(mode: .folder(folder.id)) : GridViewController(folder: folder)
        // 꾹 누른 메뉴의 '사진 추가'·'슬라이드쇼'는 앨범을 연 뒤에 실행
        (next as? GridViewController)?.actionAfterOpening = pendingOpenAction
        pendingOpenAction = nil
        // 앨범은 카드에서 커지며 열림. 폴더는 순정처럼 오른쪽에서 밀려 들어옴
        if !folder.isGroup, #available(iOS 18.0, *) {
            let id = folder.id
            let options = UIViewController.Transition.ZoomOptions()
            // 카드(정사각형)를 앨범 화면 맨 위의 정사각형 표지에 맞춤. 닫힐 때 끝에서 크기가 덜컥 바뀌지 않게
            let grid = next as? GridViewController
            if let grid {
                grid.opensWithZoom = true
                // 전환 동안 표지 모서리를 이 카드와 같은 비율로 (목록 보기·자동 분류 카드는 비율이 다름)
                if let card = (collectionView.cellForItem(at: indexPath) as? AlbumCell)?.cardView {
                    grid.zoomCornerRatio = Self.cornerRatio(of: card)
                }
                options.alignmentRectProvider = { [weak grid] _ in
                    grid?.zoomCoverRect() ?? .zero
                }
                // 닫기는 오른쪽으로 쓸기(어디서든, 순정처럼) 또는 맨 위에서 아래로 끌기
                options.interactiveDismissShouldBegin = { [weak grid] context in
                    guard let grid else { return false }
                    return grid.allowsZoomDismiss(location: ZoomGesture.point(context.location),
                                                  velocity: ZoomGesture.point(context.velocity))
                }
            }
            next.preferredTransition = .zoom(options: options, sourceViewProvider: { [weak self, weak grid] _ in
                let card = self?.cardView(forFolderID: id)
                // 닫힐 때 돌아갈 카드가 그사이 바뀌었을 수 있어 (회전 등) 그 카드에서 다시 잼
                if let card, let grid, card.bounds.width > 0 {
                    grid.zoomCornerRatio = FoldersViewController.cornerRatio(of: card)
                }
                return card
            })
        }
        navigationController?.pushViewController(next, animated: true)
    }

    /// 카드 모서리 반지름 ÷ 카드 한 변 (짧은 쪽). 크기를 아직 모르면 0
    private static func cornerRatio(of card: UIView) -> CGFloat {
        let side = min(card.bounds.width, card.bounds.height)
        return side > 0 ? card.layer.cornerRadius / side : 0
    }

    /// 확대 전환이 시작하고 돌아올 자리 (그 앨범 카드)
    private func cardView(forFolderID id: String) -> UIView? {
        for (section, group) in groups.enumerated() {
            if let item = group.folders.firstIndex(where: { $0.id == id }) {
                return (collectionView.cellForItem(at: IndexPath(item: item, section: section)) as? AlbumCell)?.cardView
            }
        }
        return nil
    }

    private func liftPreview(at indexPath: IndexPath) -> UITargetedPreview? {
        guard let cell = collectionView.cellForItem(at: indexPath) as? AlbumCell else { return nil }
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = cell.liftPath
        return UITargetedPreview(view: cell.contentView, parameters: parameters)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfiguration configuration: UIContextMenuConfiguration,
                        highlightPreviewForItemAt indexPath: IndexPath) -> UITargetedPreview? {
        liftPreview(at: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfiguration configuration: UIContextMenuConfiguration,
                        dismissalPreviewForItemAt indexPath: IndexPath) -> UITargetedPreview? {
        liftPreview(at: indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, dragPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? {
        guard let cell = collectionView.cellForItem(at: indexPath) as? AlbumCell else { return nil }
        let parameters = UIDragPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = cell.liftPath
        return parameters
    }

    func collectionView(_ collectionView: UICollectionView, dropPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? {
        guard let cell = collectionView.cellForItem(at: indexPath) as? AlbumCell else { return nil }
        let parameters = UIDragPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = cell.liftPath
        return parameters
    }

    // MARK: - 꾹 눌렀을 때 메뉴

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first, let folder = folder(at: indexPath) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            return UIMenu(children: self.menuElements(for: folder, at: indexPath))
        }
    }

    /// 순정 iOS 27 의 앨범 카드 메뉴 짜임: [이름 · 사진 추가] / [슬라이드쇼 · 삭제] / 우리 앱만의 [폴더로 이동 · 숨기기]
    private func menuElements(for folder: Folder, at indexPath: IndexPath) -> [UIMenuElement] {
        var elements: [UIMenuElement] = []
        let snapshot = Library.shared.snapshot
        var top: [UIMenuElement] = []
        var middle: [UIMenuElement] = []

        if !folder.isAuto {
            top.append(UIAction(title: folder.isGroup ? "폴더 이름 변경" : "앨범 이름 변경", image: UIImage(systemName: "pencil")) { [weak self] _ in
                self?.promptText(title: "이름 변경", initial: folder.title, placeholder: "이름", confirm: "저장") { name in
                    Library.shared.rename(folder.id, to: name)
                }
            })
        }
        if !folder.isGroup {
            if !folder.isAuto, folder.albumID != nil {
                top.append(UIAction(title: "사진 추가", image: UIImage(systemName: "plus")) { [weak self] _ in
                    self?.open(at: indexPath, then: .addPhotos)
                })
            }
            middle.append(UIAction(title: "슬라이드쇼 재생", image: UIImage(systemName: "play.rectangle")) { [weak self] _ in
                self?.open(at: indexPath, then: .slideshow)
            })
        }
        if !folder.isAuto {
            middle.append(UIAction(title: folder.isGroup ? "폴더 삭제" : "앨범 삭제", image: UIImage(systemName: "trash"),
                                   attributes: .destructive) { [weak self] _ in
                self?.deleteCollection(folder)
            })
        }

        if !folder.isAuto {

            // 폴더로 이동 ▸ (사진 앱의 폴더 목록)
            var targets: [UIMenuElement] = []
            let parent = snapshot.children.first { $0.value.contains(folder.id) }?.key
            if let parent, parent != Snapshot.top {
                targets.append(UIAction(title: "폴더 밖으로", image: UIImage(systemName: "arrow.up.left")) { _ in
                    Library.shared.moveCollection(folder.id, into: Snapshot.top)
                })
            }
            let lists = snapshot.nodes.values.filter { $0.isGroup && $0.id != folder.id && $0.id != parent }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            for list in lists {
                targets.append(UIAction(title: list.title, image: UIImage(systemName: "folder")) { [weak self] _ in
                    Library.shared.moveCollection(folder.id, into: list.id) { ok in
                        self?.toast(ok ? "'\(folder.title)' 을(를) '\(list.title)' 폴더로 옮겼어요" : "옮기지 못했어요")
                    }
                })
            }
            targets.append(UIAction(title: "새로운 폴더…", image: UIImage(systemName: "folder.badge.plus")) { [weak self] _ in
                guard let self else { return }
                self.promptText(title: "새로운 폴더", placeholder: "폴더 이름", confirm: "만들기") { name in
                    Library.shared.createFolder(title: name, in: self.container, members: [folder.id])
                }
            })
            elements.append(UIMenu(title: "폴더로 이동", image: UIImage(systemName: "folder"), children: targets))
        }

        if mode == .hidden {
            elements.append(UIAction(title: "숨기기 해제", image: UIImage(systemName: "eye")) { [weak self] _ in
                self?.setHidden(folder, false)
            })
        } else {
            elements.append(UIAction(title: "숨기기", image: UIImage(systemName: "eye.slash")) { [weak self] _ in
                self?.setHidden(folder, true)
            })
        }

        var sections: [UIMenuElement] = []
        if !top.isEmpty { sections.append(UIMenu(options: .displayInline, children: top)) }
        if !middle.isEmpty { sections.append(UIMenu(options: .displayInline, children: middle)) }
        if !elements.isEmpty { sections.append(UIMenu(options: .displayInline, children: elements)) }
        return sections
    }

    /// 메뉴에서 고른 동작을 앨범을 연 뒤에 실행
    private var pendingOpenAction: GridViewController.OpenAction?

    private func open(at indexPath: IndexPath, then action: GridViewController.OpenAction) {
        pendingOpenAction = action
        // 메뉴가 다 닫힌 뒤 카드에서 열리게
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            self.collectionView(self.collectionView, didSelectItemAt: indexPath)
        }
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

    private func deleteCollection(_ folder: Folder) {
        let message = folder.isGroup
            ? "폴더와 그 안의 앨범이 삭제돼요. 사진은 삭제되지 않아요."
            : "앨범만 삭제돼요. 사진은 삭제되지 않아요."
        confirm(title: "'\(folder.title)' 을(를) 삭제할까요?", message: message, action: "삭제") {
            Library.shared.deleteCollection(folder.id)
        }
    }

    // MARK: - 끌어서 순서 바꾸기 · 폴더에 넣기 (사진 앱의 앨범·폴더만)

    /// 끌어 옮길 수 있는 칸인지 (자동 분류와 숨긴 앨범 탭은 안 됨)
    private func canArrange(section: Int) -> Bool {
        mode != .hidden && section < groups.count && !groups[section].isAuto
    }

    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession,
                        at indexPath: IndexPath) -> [UIDragItem] {
        guard canArrange(section: indexPath.section), let folder = folder(at: indexPath) else { return [] }
        let item = UIDragItem(itemProvider: NSItemProvider(object: folder.id as NSString))
        item.localObject = folder.id
        return [item]
    }

    func collectionView(_ collectionView: UICollectionView, dragSessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool {
        true
    }

    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession,
                        withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        guard let id = session.localDragSession?.items.first?.localObject as? String else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
        // 폴더 한가운데에 놓으면 그 폴더에 넣기
        let point = session.location(in: collectionView)
        if let path = collectionView.indexPathForItem(at: point), canArrange(section: path.section),
           let target = folder(at: path), target.isGroup, target.id != id,
           let frame = collectionView.layoutAttributesForItem(at: path)?.frame,
           frame.insetBy(dx: frame.width * 0.2, dy: frame.height * 0.2).contains(point) {
            return UICollectionViewDropProposal(operation: .move, intent: .insertIntoDestinationIndexPath)
        }
        // 순서 바꾸기는 '사용자 설정 순'일 때, 같은 칸 안에서만
        guard Prefs.albumSort == 0, let destination = destinationIndexPath, canArrange(section: destination.section) else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
        return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
    }

    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let item = coordinator.items.first, let id = item.dragItem.localObject as? String else { return }
        let snapshot = Library.shared.snapshot

        if coordinator.proposal.intent == .insertIntoDestinationIndexPath {
            guard let destination = coordinator.destinationIndexPath, let target = folder(at: destination),
                  target.isGroup, target.id != id else { return }
            let title = snapshot.nodes[id]?.title ?? ""
            Library.shared.moveCollection(id, into: target.id) { [weak self] ok in
                self?.toast(ok ? "'\(title)' 을(를) '\(target.title)' 폴더로 옮겼어요" : "옮기지 못했어요")
            }
            return
        }

        guard let destination = coordinator.destinationIndexPath, canArrange(section: destination.section),
              let from = groups[destination.section].folders.firstIndex(where: { $0.id == id }) else { return }
        let section = destination.section
        let to = min(max(0, destination.item), groups[section].folders.count - 1)
        guard to != from else { return }

        // 화면부터 옮기고
        let moved = groups[section].folders.remove(at: from)
        groups[section].folders.insert(moved, at: to)
        lastSignature = signature(groups, snapshot)
        let source = IndexPath(item: from, section: section)
        let target = IndexPath(item: to, section: section)
        collectionView.performBatchUpdates({
            collectionView.moveItem(at: source, to: target)
        }, completion: nil)
        coordinator.drop(item.dragItem, toItemAt: target)

        // 사진 앱의 실제 순서에 반영 (숨긴 것이 섞여 있을 수 있어 ID 로 자리를 찾음)
        var order = snapshot.children[container] ?? []
        guard let realFrom = order.firstIndex(of: id) else { return }
        order.remove(at: realFrom)
        var realTo = order.count
        if to + 1 < groups[section].folders.count {
            let nextID = groups[section].folders[to + 1].id
            realTo = order.firstIndex(of: nextID) ?? order.count
        }
        Library.shared.reorder(in: container, from: realFrom, to: realTo)
    }

    // MARK: - 위 버튼 (순정 사진 앱의 + 와 ⋯)

    private func refreshMenu() {
        guard !isLocked else { return }

        // ⋯ : 앨범 표시 / 목록 보기, 정렬
        let showCards = UIAction(title: "앨범 표시", image: UIImage(systemName: "photo"), state: listMode ? .off : .on) { [weak self] _ in
            self?.setListMode(false)
        }
        let showList = UIAction(title: "목록 보기", image: UIImage(systemName: "list.bullet"), state: listMode ? .on : .off) { [weak self] _ in
            self?.setListMode(true)
        }
        let viewMenu = UIMenu(title: "", options: .displayInline, children: [showCards, showList])
        viewMenu.preferredElementSize = .medium

        let sort = Prefs.albumSort
        let sortTitles = ["사용자 설정 순으로 정렬", "이름순으로 정렬", "사진 많은 순으로 정렬", "최근 사진 순으로 정렬"]
        var sortActions: [UIAction] = []
        for (index, name) in sortTitles.enumerated() {
            sortActions.append(UIAction(title: name, state: sort == index ? .on : .off) { [weak self] _ in
                Prefs.albumSort = index
                self?.refreshMenu()
                NotificationCenter.default.post(name: Library.didChange, object: nil)
            })
        }
        let sortMenu = UIMenu(title: "", options: .displayInline, children: sortActions)

        var sections: [UIMenu] = [viewMenu, sortMenu]
        if mode == .top {
            let hideMoved = UIAction(title: "앨범에 넣은 사진은 자동 분류에서 빼기", state: Library.shared.hideMoved ? .on : .off) { [weak self] _ in
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
            sections.append(UIMenu(title: "자동 분류", children: [hideMoved, reclassify, diagnostics]))
        }
        let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: UIMenu(children: sections))

        var items = [more]
        if mode != .hidden {
            // + : 새로운 앨범 / 새로운 폴더
            let newAlbum = UIAction(title: "새로운 앨범", image: UIImage(systemName: "rectangle.stack.badge.plus")) { [weak self] _ in
                self?.createAlbum()
            }
            let newFolder = UIAction(title: "새로운 폴더", image: UIImage(systemName: "folder.badge.plus")) { [weak self] _ in
                self?.createFolder()
            }
            items.append(UIBarButtonItem(image: UIImage(systemName: "plus"), menu: UIMenu(children: [newAlbum, newFolder])))
        }
        navigationItem.rightBarButtonItems = items
    }

    private func setListMode(_ on: Bool) {
        guard listMode != on else { return }
        listMode = on
        Prefs.albumListMode = on
        refreshMenu()
        UIView.transition(with: collectionView, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.collectionView.setCollectionViewLayout(self.makeLayout(), animated: false)
            self.collectionView.reloadData()
        }, completion: nil)
    }

    private func createAlbum() {
        guard Library.shared.canRead else { return }
        promptText(title: "새로운 앨범", placeholder: "앨범 이름", confirm: "저장") { [weak self] name in
            guard let self else { return }
            Library.shared.createAlbum(title: name, in: self.container) { ok in
                if !ok { self.toast("앨범을 만들지 못했어요") }
            }
        }
    }

    private func createFolder() {
        guard Library.shared.canRead else { return }
        promptText(title: "새로운 폴더", placeholder: "폴더 이름", confirm: "저장") { [weak self] name in
            guard let self else { return }
            Library.shared.createFolder(title: name, in: self.container) { ok in
                if !ok { self.toast("폴더를 만들지 못했어요") }
            }
        }
    }
}
