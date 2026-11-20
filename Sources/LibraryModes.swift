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

    var mode: LibraryMode {
        get { LibraryMode(rawValue: segments.selectedSegmentIndex) ?? .all }
        set { segments.selectedSegmentIndex = newValue.rawValue }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 순정 배치: 왼쪽 큰 캡슐(보관함 아이콘 + 년|월|전체), 오른쪽 둥근 검색
        let height = bounds.height
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
            // 월: 첫 칸 2×2 + 오른쪽 세로 두 칸, 그 뒤로 한 줄 3칸
            let gap: CGFloat = 4
            let inset: CGFloat = 12
            let side = floor((width - inset * 2 - gap * 2) / 3)
            let count = self?.data.months.indices.contains(section) == true ? self!.data.months[section].days.count : 0
            var groups: [NSCollectionLayoutGroup] = []
            if count > 0 {
                let big = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(side * 2 + gap), heightDimension: .absolute(side * 2 + gap)))
                let small = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .absolute(side), heightDimension: .absolute(side)))
                let rightCount = min(2, count - 1)
                var heroItems: [NSCollectionLayoutItem] = [big]
                if rightCount > 0 {
                    let column = NSCollectionLayoutGroup.vertical(layoutSize: .init(widthDimension: .absolute(side), heightDimension: .absolute(side * 2 + gap)),
                                                                  repeatingSubitem: small, count: rightCount)
                    column.interItemSpacing = .fixed(gap)
                    groups.append(NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(side * 2 + gap)),
                                                                     subitems: [big, column]))
                    groups[0].interItemSpacing = .fixed(gap)
                } else {
                    groups.append(NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(side * 2 + gap)),
                                                                     subitems: heroItems))
                }
                heroItems.removeAll()
                let rest = count - 1 - rightCount
                if rest > 0 {
                    let rows = (rest + 2) / 3
                    let row = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(side)),
                                                                 repeatingSubitem: small, count: 3)
                    row.interItemSpacing = .fixed(gap)
                    for _ in 0..<rows { groups.append(row) }
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
            let side = indexPath.item == 0 ? collectionView.bounds.width * 0.66 : collectionView.bounds.width / 3
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
        label.font = .systemFont(ofSize: 22, weight: .bold)
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
