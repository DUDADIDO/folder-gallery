import Photos
import UIKit

// MARK: - 보관함 보기 단위 (순정 iOS 27: 끝까지 오므리면 아래에 [년 | 월 | 전체])

enum LibraryMode: Int {
    case years, months, all
}

/// 날짜별로 묶은 보관함 (오래된 것이 앞). 뒤에서 한 번 계산
struct MomentsData {
    struct Day {
        let day: Int
        let cover: PHAsset
        /// 보관함 목록에서 이 날 첫 사진의 ID (전체 보기로 갈 때)
        let firstID: String
        let count: Int
    }

    struct Month {
        let year: Int
        let month: Int
        let days: [Day]
    }

    struct Year {
        let year: Int
        let cover: PHAsset
        /// 표지 사진의 달 ("5월"처럼 표지 아래 작게)
        let coverMonth: Int
        /// months 안의 첫 달 차례
        let firstMonthIndex: Int
    }

    var months: [Month] = []
    var years: [Year] = []

    /// assets 는 오래된 것이 앞
    static func build(_ assets: [PHAsset]) -> MomentsData {
        let calendar = Calendar.current
        var months: [Month] = []
        var currentKey: (Int, Int)?
        var days: [Day] = []
        var dayKey = -1
        var dayFirst: PHAsset?
        var dayBest: PHAsset?
        var dayCount = 0

        func closeDay() {
            guard let first = dayFirst, let best = dayBest else { return }
            days.append(Day(day: dayKey, cover: best, firstID: first.localIdentifier, count: dayCount))
            dayFirst = nil
            dayBest = nil
            dayCount = 0
        }
        func closeMonth() {
            closeDay()
            if let key = currentKey, !days.isEmpty {
                months.append(Month(year: key.0, month: key.1, days: days))
            }
            days = []
        }

        for asset in assets {
            guard let date = asset.creationDate else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            let key = (parts.year ?? 0, parts.month ?? 0)
            if currentKey == nil || currentKey! != key {
                closeMonth()
                currentKey = key
                dayKey = -1
            }
            let day = parts.day ?? 0
            if day != dayKey {
                closeDay()
                dayKey = day
                dayFirst = asset
                dayBest = asset
            }
            dayCount += 1
            // 대표 사진: 그날 즐겨찾기가 있으면 그것, 아니면 첫 사진 (동영상보다 사진)
            if let best = dayBest, !best.isFavorite, asset.isFavorite || (best.mediaType == .video && asset.mediaType == .image) {
                dayBest = asset
            }
        }
        closeMonth()

        var years: [Year] = []
        var index = 0
        while index < months.count {
            let year = months[index].year
            var end = index
            while end < months.count, months[end].year == year { end += 1 }
            // 표지: 그해 사진이 가장 많은 달의 가장 많은 날
            let busiest = (index..<end).max { a, b in
                months[a].days.reduce(0) { $0 + $1.count } < months[b].days.reduce(0) { $0 + $1.count }
            } ?? index
            let day = months[busiest].days.max { $0.count < $1.count } ?? months[busiest].days[0]
            years.append(Year(year: year, cover: day.cover, coverMonth: months[busiest].month, firstMonthIndex: index))
            index = end
        }
        return MomentsData(months: months, years: years)
    }
}

// MARK: - 아래의 [보관함] [년 | 월 | 전체] [검색] 막대

final class LibraryModeBar: UIView {
    let segments = UISegmentedControl(items: ["년", "월", "전체"])
    let libraryButton = UIButton(type: .system)
    let searchButton = UIButton(type: .system)
    private let capsule: UIVisualEffectView

    var onMode: ((LibraryMode) -> Void)?
    var onLibrary: (() -> Void)?
    var onSearch: (() -> Void)?

    override init(frame: CGRect) {
        if #available(iOS 26.0, *) {
            capsule = UIVisualEffectView(effect: UIGlassEffect())
        } else {
            capsule = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        }
        super.init(frame: frame)
        capsule.layer.cornerCurve = .continuous
        capsule.clipsToBounds = true
        addSubview(capsule)

        libraryButton.setImage(UIImage(systemName: "photo.on.rectangle.angled.fill",
                                       withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)), for: .normal)
        libraryButton.tintColor = .systemBlue
        libraryButton.accessibilityLabel = "보관함"
        libraryButton.addAction(UIAction { [weak self] _ in self?.onLibrary?() }, for: .primaryActionTriggered)
        capsule.contentView.addSubview(libraryButton)

        segments.selectedSegmentIndex = LibraryMode.all.rawValue
        segments.addAction(UIAction { [weak self] _ in
            guard let self, let mode = LibraryMode(rawValue: self.segments.selectedSegmentIndex) else { return }
            self.onMode?(mode)
        }, for: .valueChanged)
        capsule.contentView.addSubview(segments)

        var search: UIButton.Configuration
        if #available(iOS 26.0, *) {
            search = .glass()
        } else {
            search = .gray()
        }
        search.image = UIImage(systemName: "magnifyingglass", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold))
        search.baseForegroundColor = .label
        search.cornerStyle = .capsule
        searchButton.configuration = search
        searchButton.accessibilityLabel = "검색"
        searchButton.addAction(UIAction { [weak self] _ in self?.onSearch?() }, for: .primaryActionTriggered)
        addSubview(searchButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: 탭 막대와 서로 바뀌는 모양 (순정 iOS 27)
    // 사진 아이콘 동그라미가 늘어나 탭 막대 캡슐이 되고, 돌아올 때는 거꾸로 줄어듦.
    // 진짜 탭 막대는 시스템 것이라, 늘어난 동그라미가 그 자리·모양에 닿은 뒤 서로 바꿔 끼움

    /// 늘고 줄어드는 유리 동그라미. 미리 만들어 계속 둠 (새로 만든 유리는 처음 나타날 때 시스템이 0.3초쯤 서서히 그려서
    /// 돌아올 때 줄어드는 모습이 안 보였음). 평소에는 거의 투명하게 사진 아이콘 자리에
    private lazy var bubbleView: UIVisualEffectView = {
        let v = makeBubble()
        v.isUserInteractionEnabled = false
        v.alpha = 0.011
        return v
    }()
    private var bubble: UIVisualEffectView?

    private func makeBubble() -> UIVisualEffectView {
        let v: UIVisualEffectView
        if #available(iOS 26.0, *) {
            v = UIVisualEffectView(effect: UIGlassEffect())
        } else {
            v = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        }
        v.layer.cornerCurve = .continuous
        v.clipsToBounds = true
        let icon = UIImageView(image: libraryButton.image(for: .normal))
        icon.tintColor = .systemBlue
        icon.contentMode = .center
        icon.tag = 1
        v.contentView.addSubview(icon)
        addSubview(v)
        return v
    }

    /// 동그라미(사진 아이콘 자리) — 이 막대 좌표
    private var circleFrame: CGRect {
        convert(libraryButton.frame, from: libraryButton.superview).insetBy(dx: -2, dy: -2)
    }

    private func place(_ v: UIVisualEffectView, _ frame: CGRect) {
        v.frame = frame
        v.layer.cornerRadius = frame.height / 2
        if let icon = v.contentView.viewWithTag(1) {
            // 아이콘은 왼쪽 동그라미 자리 그대로 (탭 막대의 '보관함' 쪽)
            icon.frame = CGRect(x: 0, y: 0, width: min(frame.width, frame.height + 8), height: frame.height)
        }
    }

    /// 막대 → 탭 막대 모양. target 은 탭 막대 캡슐 자리, searchTarget 은 탭 막대 검색 자리 (이 막대 좌표).
    /// swap 은 캡슐이 거의 다 늘어났을 때(진짜 탭 막대로 바꿔 끼울 때), done 은 다 끝났을 때
    func morphToTabs(target: CGRect, searchTarget: CGRect?, swap: @escaping () -> Void, done: @escaping () -> Void) {
        let b = bubbleView
        bubble = b
        bringSubviewToFront(b)
        b.alpha = 1
        let circle = circleFrame
        place(b, circle)
        libraryButton.alpha = 0
        // 순정: 누르면 동그라미가 살짝 부풀고(0.08초) 곧 오른쪽으로 늘어나 탭 막대 캡슐이 됨
        UIView.animate(withDuration: 0.08, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
            self.place(b, circle.insetBy(dx: -5, dy: -5))
        } completion: { _ in
            let anim = UIViewPropertyAnimator(duration: 0.3, dampingRatio: 0.85) {
                self.place(b, target)
                if let searchTarget { self.searchButton.frame = searchTarget }
            }
            anim.addAnimations({ self.segments.alpha = 0; self.capsule.alpha = 0 }, delayFactor: 0)
            anim.addCompletion { _ in done() }
            anim.startAnimation()
            // 늘어나는 도중에 탭 막대 글자가 나타남 (끝까지 기다리면 빈 캡슐이 잠깐 멈춰 보임)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { swap() }
        }
    }

    /// 탭 막대 모양 → 막대. from 은 탭 막대 캡슐 자리, searchFrom 은 탭 막대 검색 자리 (이 막대 좌표)
    func morphFromTabs(from: CGRect, searchFrom: CGRect?) {
        let b = bubbleView
        bubble = b
        bringSubviewToFront(b)
        b.alpha = 1
        let searchHome = searchButton.frame
        place(b, from)
        if let searchFrom { searchButton.frame = searchFrom }
        libraryButton.alpha = 0
        segments.alpha = 0
        capsule.alpha = 0
        let anim = UIViewPropertyAnimator(duration: 0.34, dampingRatio: 0.86) {
            self.place(b, self.circleFrame)
            self.searchButton.frame = searchHome
        }
        // 동그라미로 거의 다 줄어들 즈음 년·월·전체가 나타남
        anim.addAnimations({
            self.segments.alpha = 1
            self.capsule.alpha = 1
        }, delayFactor: 0.35)
        anim.addCompletion { [weak self] _ in self?.endMorph() }
        anim.startAnimation()
    }

    /// 바뀌는 중 모양을 지우고 평소대로
    func endMorph() {
        bubble = nil
        place(bubbleView, circleFrame)
        bubbleView.alpha = 0.011
        libraryButton.alpha = 1
        segments.alpha = 1
        capsule.alpha = 1
    }

    /// 아이패드: 보관함·검색 단추 없이 [년 | 월 | 모든 사진]만 (순정)
    var segmentsOnly = false {
        didSet {
            libraryButton.isHidden = segmentsOnly
            searchButton.isHidden = segmentsOnly
            segments.setTitle(segmentsOnly ? "모든 사진" : "전체", forSegmentAt: LibraryMode.all.rawValue)
            setNeedsLayout()
        }
    }

    var mode: LibraryMode {
        get { LibraryMode(rawValue: segments.selectedSegmentIndex) ?? .all }
        set { segments.selectedSegmentIndex = newValue.rawValue }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 순정 배치: 왼쪽 큰 캡슐(보관함 아이콘 + 년|월|전체), 오른쪽 둥근 검색
        let height = bounds.height
        if segmentsOnly {
            capsule.frame = bounds
            capsule.layer.cornerRadius = height / 2
            segments.frame = CGRect(x: 8, y: 8, width: bounds.width - 16, height: height - 16)
            return
        }
        searchButton.frame = CGRect(x: bounds.width - height, y: 0, width: height, height: height)
        let capsuleWidth = bounds.width - height - 12
        capsule.frame = CGRect(x: 0, y: 0, width: capsuleWidth, height: height)
        capsule.layer.cornerRadius = height / 2
        libraryButton.frame = CGRect(x: 6, y: 4, width: height - 8, height: height - 8)
        let segmentX = libraryButton.frame.maxX + 6
        segments.frame = CGRect(x: segmentX, y: 8, width: capsuleWidth - segmentX - 8, height: height - 16)
        // 바뀌는 중이 아니면 유리 동그라미를 사진 아이콘 자리에 미리 둠 (이미 그려진 상태로 기다리게)
        if bubble == nil { place(bubbleView, circleFrame) }
    }
}

// MARK: - 년 · 월 보기

final class MomentsViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {
    private(set) var mode: LibraryMode
    private var data = MomentsData()
    private var collectionView: UICollectionView!

    /// 연도 카드를 누름 → 그해 첫 달로 월 보기
    var onPickYear: ((Int) -> Void)?
    /// 날짜 칸을 누름 → 그날 첫 사진으로 전체 보기
    var onPickDay: ((String) -> Void)?

    init(mode: LibraryMode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: makeLayout())
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(MomentCell.self, forCellWithReuseIdentifier: MomentCell.reuse)
        collectionView.register(MonthHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: MonthHeaderView.reuse)
        view.addSubview(collectionView)
        setContentScrollView(collectionView, for: [.top, .bottom])
    }

    func show(_ data: MomentsData, mode: LibraryMode, scrollToMonth: Int? = nil) {
        self.data = data
        self.mode = mode
        loadViewIfNeeded()
        collectionView.setCollectionViewLayout(makeLayout(), animated: false)
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        if mode == .months, let month = scrollToMonth, month < data.months.count {
            let path = IndexPath(item: 0, section: month)
            if let attributes = collectionView.layoutAttributesForSupplementaryElement(ofKind: UICollectionView.elementKindSectionHeader, at: path) {
                let y = attributes.frame.minY - collectionView.adjustedContentInset.top
                collectionView.setContentOffset(CGPoint(x: 0, y: max(-collectionView.adjustedContentInset.top, y)), animated: false)
            }
        } else {
            // 순정처럼 최신(맨 아래)부터
            let inset = collectionView.adjustedContentInset
            let y = max(-inset.top, collectionView.contentSize.height + inset.bottom - collectionView.bounds.height)
            collectionView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        }
    }

    private func makeLayout() -> UICollectionViewLayout {
        let mode = self.mode
        return UICollectionViewCompositionalLayout { [weak self] section, environment in
            let width = environment.container.effectiveContentSize.width
            if mode == .years {
                // 연도 카드: 거의 화면 너비, 가로로 조금 긴 비율, 카드 사이 넓게
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
                let group = NSCollectionLayoutGroup.vertical(layoutSize: .init(widthDimension: .fractionalWidth(1),
                                                                              heightDimension: .absolute(((width - 24) * 0.68).rounded())),
                                                             subitems: [item])
                let layout = NSCollectionLayoutSection(group: group)
                layout.interGroupSpacing = 20
                layout.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 12, bottom: 16, trailing: 12)
                return layout
            }
            // 월 (순정 iOS 27 녹화와 비교): 달마다 배치가 다름
            // 하루: 가로로 긴 큰 카드 하나 / 이틀: 반반 / 사흘 이상: 짝수 달은 가로로 긴 큰 카드 + 3칸 줄,
            // 홀수 달은 왼쪽 작은 두 칸 + 오른쪽 2×2, 그 뒤로 3칸 줄
            let gap: CGFloat = 4
            let inset: CGFloat = 12
            let full = width - inset * 2
            let side = floor((full - gap * 2) / 3)
            let wideHeight = (full * 0.62).rounded()
            let count = self?.data.months.indices.contains(section) == true ? self!.data.months[section].days.count : 0
            var groups: [NSCollectionLayoutGroup] = []
            func item(_ w: CGFloat, _ h: CGFloat) -> NSCollectionLayoutItem {
                NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(w), heightDimension: .absolute(h)))
            }
            func rowsOfThree(_ n: Int) {
                guard n > 0 else { return }
                for start in stride(from: 0, to: n, by: 3) {
                    let k = min(3, n - start)
                    let row = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .absolute(full), heightDimension: .absolute(side)),
                                                                 subitems: Array(repeating: item(side, side), count: k))
                    row.interItemSpacing = .fixed(gap)
                    groups.append(row)
                }
            }
            if count == 1 {
                groups.append(NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .absolute(full), heightDimension: .absolute(wideHeight)),
                                                                 subitems: [item(full, wideHeight)]))
            } else if count == 2 {
                let half = floor((full - gap) / 2)
                let pair = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .absolute(full), heightDimension: .absolute(half)),
                                                              subitems: [item(half, half), item(half, half)])
                pair.interItemSpacing = .fixed(gap)
                groups.append(pair)
            } else if count >= 3 {
                if section % 2 == 0 {
                    groups.append(NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .absolute(full), heightDimension: .absolute(wideHeight)),
                                                                     subitems: [item(full, wideHeight)]))
                    rowsOfThree(count - 1)
                } else {
                    let bigSide = side * 2 + gap
                    let column = NSCollectionLayoutGroup.vertical(layoutSize: .init(widthDimension: .absolute(side), heightDimension: .absolute(bigSide)),
                                                                  subitems: [item(side, side), item(side, side)])
                    column.interItemSpacing = .fixed(gap)
                    let hero = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .absolute(full), heightDimension: .absolute(bigSide)),
                                                                  subitems: [column, item(bigSide, bigSide)])
                    hero.interItemSpacing = .fixed(gap)
                    groups.append(hero)
                    rowsOfThree(count - 3)
                }
            }
            let total = groups.reduce(CGFloat(0)) { $0 + $1.layoutSize.heightDimension.dimension } + CGFloat(max(0, groups.count - 1)) * gap
            let whole = NSCollectionLayoutGroup.vertical(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(max(1, total))),
                                                         subitems: groups.isEmpty ? [NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(1)))] : groups)
            whole.interItemSpacing = .fixed(gap)
            let layout = NSCollectionLayoutSection(group: whole)
            layout.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: inset, bottom: 28, trailing: inset)
            let header = NSCollectionLayoutBoundarySupplementaryItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(44)),
                                                                     elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
            layout.boundarySupplementaryItems = [header]
            return layout
        }
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        mode == .years ? 1 : data.months.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        mode == .years ? data.years.count : data.months[section].days.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: MomentCell.reuse, for: indexPath) as! MomentCell
        let scale = traitCollection.displayScale
        if mode == .years {
            let year = data.years[indexPath.item]
            cell.configure(asset: year.cover, title: "\(year.year)년", subtitle: "\(year.coverMonth)월", large: true,
                           size: CGSize(width: collectionView.bounds.width * scale, height: collectionView.bounds.width * 0.7 * scale))
        } else {
            let day = data.months[indexPath.section].days[indexPath.item]
            let side = collectionView.bounds.width * (indexPath.item < 3 ? 0.7 : 0.34)
            cell.configure(asset: day.cover, title: "\(day.day)일", subtitle: nil, large: false,
                           size: CGSize(width: side * scale, height: side * scale))
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: MonthHeaderView.reuse,
                                                                     for: indexPath) as! MonthHeaderView
        if data.months.indices.contains(indexPath.section) {
            let month = data.months[indexPath.section]
            header.label.text = "\(month.year)년 \(month.month)월"
        }
        return header
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        if mode == .years {
            onPickYear?(data.years[indexPath.item].firstMonthIndex)
        } else {
            onPickDay?(data.months[indexPath.section].days[indexPath.item].firstID)
        }
    }
}

/// 년·월 보기의 칸: 사진이 꽉 차고 왼쪽 위에 흰 글자
final class MomentCell: UICollectionViewCell {
    static let reuse = "MomentCell"
    private let imageView = UIImageView()
    private let shade = CAGradientLayer()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private var requestID: PHImageRequestID = PHInvalidImageRequestID
    private var assetID: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.clipsToBounds = true
        contentView.layer.cornerCurve = .continuous
        contentView.backgroundColor = .secondarySystemBackground
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)
        shade.colors = [UIColor.black.withAlphaComponent(0.35).cgColor, UIColor.clear.cgColor]
        contentView.layer.addSublayer(shade)
        for label in [titleLabel, subtitleLabel] {
            label.textColor = .white
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = 0.3
            label.layer.shadowRadius = 3
            label.layer.shadowOffset = .zero
            contentView.addSubview(label)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(asset: PHAsset, title: String, subtitle: String?, large: Bool, size: CGSize) {
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: large ? 22 : 13, weight: .bold)
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        subtitleLabel.isHidden = subtitle == nil
        contentView.layer.cornerRadius = large ? 26 : 10
        let id = asset.localIdentifier
        guard assetID != id else { return }
        assetID = id
        imageView.image = nil
        if requestID != PHInvalidImageRequestID { PHImageManager.default().cancelImageRequest(requestID) }
        requestID = Thumbs.manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: Thumbs.options) { [weak self] image, _ in
            guard let self, self.assetID == id, let image else { return }
            self.imageView.image = image
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = contentView.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shade.frame = CGRect(x: 0, y: 0, width: contentView.bounds.width, height: min(90, contentView.bounds.height * 0.5))
        CATransaction.commit()
        let large = contentView.layer.cornerRadius > 20
        let pad: CGFloat = large ? 18 : 7
        titleLabel.sizeToFit()
        titleLabel.frame.origin = CGPoint(x: pad, y: pad - (large ? 2 : 3))
        subtitleLabel.sizeToFit()
        subtitleLabel.frame.origin = CGPoint(x: pad, y: titleLabel.frame.maxY)
    }
}

final class MonthHeaderView: UICollectionReusableView {
    static let reuse = "MonthHeaderView"
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 17, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
