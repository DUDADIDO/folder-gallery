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
    // 유리는 이 막대의 캡슐 한 장만 씀 (유리 두 장을 겹치면 하얗게 떠서 깜빡임).
    // 캡슐이 늘어나 탭 막대 캡슐 자리·모양이 된 그 프레임에 진짜 탭 막대와 바꿔 끼움

    private var morphingShape = false

    private func setCapsule(_ frame: CGRect) {
        capsule.frame = frame
        capsule.layer.cornerRadius = frame.height / 2
    }

    /// 막대 → 탭 막대 모양. target 은 탭 막대 캡슐 자리, searchTarget 은 탭 막대 검색 자리 (이 막대 좌표).
    /// swap 은 모양이 같아졌을 때(진짜 탭 막대로 바꿔 끼울 때) 한 번
    func morphToTabs(target: CGRect, searchTarget: CGRect?, swap: @escaping () -> Void, done: @escaping () -> Void) {
        morphingShape = true
        let anim = UIViewPropertyAnimator(duration: 0.3, dampingRatio: 0.9) {
            self.setCapsule(target)
            if let searchTarget { self.searchButton.frame = searchTarget }
            self.segments.alpha = 0
        }
        anim.addCompletion { _ in
            swap()
            done()
        }
        anim.startAnimation()
    }

    /// 탭 막대 모양 → 막대. from 은 탭 막대 캡슐 자리, searchFrom 은 탭 막대 검색 자리 (이 막대 좌표)
    func morphFromTabs(from: CGRect, searchFrom: CGRect?) {
        morphingShape = true
        let capsuleHome = capsule.frame, searchHome = searchButton.frame
        setCapsule(from)
        if let searchFrom { searchButton.frame = searchFrom }
        segments.alpha = 0
        let anim = UIViewPropertyAnimator(duration: 0.32, dampingRatio: 0.9) {
            self.setCapsule(capsuleHome)
            self.searchButton.frame = searchHome
        }
        // 거의 다 줄어들 즈음 년·월·전체가 나타남
        anim.addAnimations({ self.segments.alpha = 1 }, delayFactor: 0.4)
        anim.addCompletion { [weak self] _ in self?.endMorph() }
        anim.startAnimation()
    }

    /// 바뀌는 중 모양을 지우고 평소대로
    func endMorph() {
        morphingShape = false
        segments.alpha = 1
        setNeedsLayout()
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
        if morphingShape { return }   // 모양이 바뀌는 중에는 애니메이션이 정한 자리 그대로
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
    }
}

// MARK: - 년 · 월 보기

final class MomentsViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {
    private(set) var mode: LibraryMode
    private var data = MomentsData()
    private var collectionView: UICollectionView!

    /// 연도 카드를 누름 → 그해 첫 달로 월 보기
    var onPickYear: ((Int) -> Void)?
    /// 날짜 칸을 누름 → 그날 첫 사진으로 전체 보기. 누른 칸 자리(이 화면 좌표)·그림·모서리도 같이 (날아가는 애니메이션)
    var onPickDay: ((String, CGRect, UIImage?, CGFloat) -> Void)?

    /// 지금 보이는 날 칸들 (사진 id, 이 화면 좌표 자리, 칸, 모서리)
    func visibleCovers() -> [(id: String, day: [Int], frame: CGRect, cell: MomentCell)] {
        guard isViewLoaded, mode == .months else { return [] }
        collectionView.layoutIfNeeded()
        return collectionView.indexPathsForVisibleItems.compactMap { path in
            guard let cell = collectionView.cellForItem(at: path) as? MomentCell, let id = cell.assetID,
                  data.months.indices.contains(path.section), data.months[path.section].days.indices.contains(path.item) else { return nil }
            let month = data.months[path.section]
            return (id, [month.year, month.month, month.days[path.item].day], cell.convert(cell.bounds, to: view), cell)
        }
    }

    /// 그날 칸이 화면 가운데쯤 오게 (없으면 그 달)
    func centerDay(year: Int, month: Int, day: Int) {
        guard mode == .months, let section = monthIndex(year: year, month: month) else { return }
        let item = data.months[section].days.firstIndex { $0.day == day } ?? 0
        collectionView.layoutIfNeeded()
        guard let attributes = collectionView.layoutAttributesForItem(at: IndexPath(item: item, section: section)) else { return }
        let inset = collectionView.adjustedContentInset
        let maxY = max(-inset.top, collectionView.contentSize.height + inset.bottom - collectionView.bounds.height)
        let y = min(maxY, max(-inset.top, attributes.frame.midY - collectionView.bounds.height / 2))
        collectionView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        collectionView.layoutIfNeeded()
    }

    /// 월 보기에서 그 달이 화면 가운데쯤 오게
    func centerMonth(_ month: Int) {
        guard mode == .months, data.months.indices.contains(month) else { return }
        collectionView.layoutIfNeeded()
        let path = IndexPath(item: 0, section: month)
        guard let attributes = collectionView.layoutAttributesForItem(at: path) else { return }
        let inset = collectionView.adjustedContentInset
        let maxY = max(-inset.top, collectionView.contentSize.height + inset.bottom - collectionView.bounds.height)
        let y = min(maxY, max(-inset.top, attributes.frame.midY - collectionView.bounds.height / 2))
        collectionView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        collectionView.layoutIfNeeded()
    }

    /// 그 해·달의 위치
    func monthIndex(year: Int, month: Int) -> Int? {
        data.months.firstIndex { $0.year == year && $0.month == month }
    }

    /// 연도 카드를 눌러 월로 넘어갈 때: 그 사진이 같은 자리에 머물고 나머지만 겹쳐 바뀜 (순정)
    private struct Anchor { let assetID: String; let y: CGFloat; let image: UIImage?; let snapshot: UIView? }
    private var anchor: Anchor?

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
        if mode == .months, let anchor, let month = scrollToMonth, month < data.months.count {
            self.anchor = nil
            // 누른 연도 카드의 사진이 들어 있는 날 칸을, 카드가 있던 높이에 맞춰 놓음
            let item = data.months[month].days.firstIndex { $0.cover.localIdentifier == anchor.assetID } ?? 0
            let path = IndexPath(item: item, section: month)
            if let attributes = collectionView.layoutAttributesForItem(at: path) {
                let inset = collectionView.adjustedContentInset
                let maxY = max(-inset.top, collectionView.contentSize.height + inset.bottom - collectionView.bounds.height)
                let y = min(maxY, max(-inset.top, attributes.frame.minY - anchor.y))
                collectionView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
                collectionView.layoutIfNeeded()
                (collectionView.cellForItem(at: path) as? MomentCell)?.prefill(anchor.image)
            }
            // 앞 화면(연도 카드들)을 위에 얹어 0.27초 동안 겹쳐 사라지게
            if let snapshot = anchor.snapshot {
                snapshot.frame = view.bounds
                view.addSubview(snapshot)
                UIView.animate(withDuration: 0.27, delay: 0, options: [.curveEaseInOut]) {
                    snapshot.alpha = 0
                } completion: { _ in snapshot.removeFromSuperview() }
            }
        } else if mode == .months, let month = scrollToMonth, month < data.months.count {
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
            let year = data.years[indexPath.item]
            // 대표 사진이 있는 달로 (순정: 누른 카드의 사진이 그 달 카드로 이어짐)
            let month = data.months.firstIndex { $0.year == year.year && $0.month == year.coverMonth } ?? year.firstMonthIndex
            if let cell = collectionView.cellForItem(at: indexPath) as? MomentCell {
                let frame = cell.convert(cell.bounds, to: view)
                anchor = Anchor(assetID: year.cover.localIdentifier, y: frame.minY,
                                image: cell.image, snapshot: view.snapshotView(afterScreenUpdates: false))
            }
            onPickYear?(month)
        } else {
            let day = data.months[indexPath.section].days[indexPath.item]
            let cell = collectionView.cellForItem(at: indexPath) as? MomentCell
            let frame = cell.map { $0.convert($0.bounds, to: view) } ?? .zero
            onPickDay?(day.firstID, frame, cell?.image, cell?.contentView.layer.cornerRadius ?? 0)
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
    private(set) var assetID: String?

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

    /// 지금 보이는 그림 (넘어가는 애니메이션이 이어 씀)
    var image: UIImage? { imageView.image }

    /// 넘어오는 애니메이션: 받기 전에 앞 화면의 같은 사진을 미리 (회색 칸이 보이지 않게)
    func prefill(_ image: UIImage?) {
        if imageView.image == nil { imageView.image = image }
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
