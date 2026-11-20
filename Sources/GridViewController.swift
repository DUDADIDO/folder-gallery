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

/// 사진 격자 배치. 칸 수(1·3·5·7)마다 자리를 한 번 계산해 두고 (묶음마다 맨 위 높이만 — 사진 수와 상관없이 빠름),
/// 두 손가락으로 벌리고 오므리는 동안은 한 배치(칸 수)를 그대로 두고 사진 줄만 크게·작게 그림 (zoom).
/// 사진은 제자리에서 커지고 작아질 뿐 다른 자리로 옮겨 가지 않음 — 배치가 바뀌는 순간은 격자 화면이 짧게 겹쳐 바꿈.
/// 1칸은 사진마다 원래 비율로 화면 너비를 꽉 채움. 묶음마다 맨 위에 머리글(날짜) 또는 정사각형 앨범 표지
final class PhotoGridLayout: UICollectionViewLayout {
    /// 칸 크기를 바꾸는 중인 상태: columns 배치의 사진 줄(높이·사이)을 scale 배로. 머리글 높이는 그대로
    struct Zoom {
        /// 그리는 배치의 칸 수
        var columns: Int
        /// 지금 칸 한 변 ÷ 그 칸 수의 원래 한 변
        var scale: CGFloat
        /// 가로로 키우고 줄이는 중심 (격자 좌표의 x). 넘치는 칸은 화면 밖으로 잘림 (옆으로 스크롤하지 않음)
        var anchorX: CGFloat
    }

    private struct Geometry {
        let columns: Int
        /// 왼쪽 시작
        let x: CGFloat
        let width: CGFloat
        let side: CGFloat
        let header: CGFloat
        /// 묶음마다 맨 위(머리글 위). 마지막에 전체 높이가 하나 더 있음
        var tops: [CGFloat] = []
        /// 1칸일 때만: 사진(평평한 차례)마다 위·높이
        var itemTops: [CGFloat] = []
        var itemHeights: [CGFloat] = []

        var height: CGFloat { tops.last ?? 0 }
    }

    static let spacing: CGFloat = 2

    /// 지금 칸 수 (칸 크기를 바꾸는 중이 아닐 때)
    var columns = 5 {
        didSet { if columns != oldValue { invalidateLayout() } }
    }
    /// 칸 크기를 바꾸는 중이면 그 상태 (이때는 columns 대신 zoom.columns 배치)
    var zoom: Zoom? {
        didSet { invalidateLayout() }
    }
    /// 머리글 높이. nil 이면 앨범 표지 (화면 너비만 한 정사각형)
    var headerHeight: CGFloat? = 42 {
        didSet { cache.removeAll() }
    }
    /// 1칸에서 쓰는 사진 비율 (너비 ÷ 높이). 평평한 차례로 물음
    var aspect: (Int) -> CGFloat = { _ in 1 }

    private var counts: [Int] = []
    private var starts: [Int] = []
    private var cache: [Int: Geometry] = [:]
    private var cachedWidth: CGFloat = -1
    private var cachedOriginX: CGFloat = 0

    /// 묶음마다 사진 수 (다시 불러올 때마다)
    func setSections(_ counts: [Int]) {
        self.counts = counts
        var starts: [Int] = []
        starts.reserveCapacity(counts.count)
        var total = 0
        for count in counts {
            starts.append(total)
            total += count
        }
        self.starts = starts
        cache.removeAll()
        invalidateLayout()
    }

    /// 사진이 놓이는 너비와 왼쪽 시작 (가로 화면에서 노치 쪽 안전 영역은 비움)
    private var width: CGFloat {
        guard let view = collectionView else { return 0 }
        return max(0, view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right)
    }

    private var originX: CGFloat {
        collectionView?.safeAreaInsets.left ?? 0
    }

    private func geometry(_ columns: Int) -> Geometry {
        let width = self.width
        let originX = self.originX
        if width != cachedWidth || originX != cachedOriginX {
            cache.removeAll()
            cachedWidth = width
            cachedOriginX = originX
        }
        if let cached = cache[columns] { return cached }
        let spacing = PhotoGridLayout.spacing
        let perRow = max(1, columns)
        let side = perRow == 1 ? width : max(20, floor((width - spacing * CGFloat(perRow - 1)) / CGFloat(perRow)))
        let header = headerHeight ?? width
        var geometry = Geometry(columns: perRow, x: originX, width: width, side: side, header: header)
        geometry.tops.reserveCapacity(counts.count + 1)
        var y: CGFloat = 0
        if perRow == 1 {
            // 1칸만 사진마다 높이가 달라서 사진 수만큼 한 번 계산 (그 칸 수를 처음 쓸 때만)
            let total = (starts.last ?? 0) + (counts.last ?? 0)
            geometry.itemTops.reserveCapacity(total)
            geometry.itemHeights.reserveCapacity(total)
        }
        for (section, count) in counts.enumerated() {
            geometry.tops.append(y)
            y += header
            if perRow == 1 {
                let base = starts[section]
                for item in 0..<count {
                    // 아주 길거나 납작한 사진은 적당히 자름 (가로 5:1 ~ 세로 1:2.5)
                    let ratio = min(5, max(0.4, aspect(base + item)))
                    let height = max(20, (width / ratio).rounded())
                    geometry.itemTops.append(y)
                    geometry.itemHeights.append(height)
                    y += height + (item < count - 1 ? spacing : 0)
                }
            } else if count > 0 {
                let rows = (count + perRow - 1) / perRow
                y += CGFloat(rows) * side + CGFloat(rows - 1) * spacing
            }
        }
        geometry.tops.append(y)
        cache[columns] = geometry
        return geometry
    }

    /// 그 칸 수에서 사진 한 칸의 너비 (1칸은 화면 너비)
    func side(columns: Int) -> CGFloat {
        geometry(columns).side
    }

    /// 그 칸 수에서 사진 줄을 scale 배로 했을 때의 전체 높이 (scale 1 이 원래 높이)
    func contentHeight(columns: Int, scale: CGFloat) -> CGFloat {
        let geometry = self.geometry(columns)
        return zoomedTop(counts.count, geometry, scale)
    }

    /// 그 칸 수에서 사진 줄을 scale 배로 했을 때 사진의 세로 자리 (가로는 원래 자리. 세로 위치를 맞추는 데만 씀)
    func itemFrame(_ indexPath: IndexPath, columns: Int, scale: CGFloat) -> CGRect? {
        let geometry = self.geometry(columns)
        guard indexPath.section < counts.count, indexPath.item >= 0, indexPath.item < counts[indexPath.section] else { return nil }
        let frame = itemFrame(section: indexPath.section, item: indexPath.item, geometry)
        return CGRect(x: frame.minX, y: zoomedY(frame.minY, section: indexPath.section, geometry, scale),
                      width: frame.width, height: frame.height * scale)
    }

    /// 앨범 표지의 높이 (맨 위 묶음의 머리글. 칸 크기를 바꿔도 그대로). 날짜 머리글이면 nil
    var coverHeight: CGFloat? {
        guard headerHeight == nil, !counts.isEmpty else { return nil }
        return width
    }

    /// 사진 줄을 scale 배로 했을 때 묶음 section 의 맨 위 (머리글은 그대로). section 이 묶음 수면 전체 높이
    private func zoomedTop(_ section: Int, _ geometry: Geometry, _ scale: CGFloat) -> CGFloat {
        let headers = CGFloat(section) * geometry.header
        return headers + (geometry.tops[section] - headers) * scale
    }

    /// 원래 배치의 y (section 묶음 안) → 사진 줄을 scale 배로 한 배치의 y
    private func zoomedY(_ y: CGFloat, section: Int, _ geometry: Geometry, _ scale: CGFloat) -> CGFloat {
        let top = zoomedTop(section, geometry, scale)
        let body = geometry.tops[section] + geometry.header
        if y <= body { return top + (y - geometry.tops[section]) }
        return top + geometry.header + (y - body) * scale
    }

    /// 사진 줄을 scale 배로 한 배치의 y → 원래 배치의 y (보이는 범위를 찾는 데 씀)
    private func unzoomedY(_ y: CGFloat, _ geometry: Geometry, _ scale: CGFloat) -> CGFloat {
        let count = counts.count
        guard count > 0, scale > 0 else { return y }
        // 맨 위가 y 보다 위(같음 포함)인 마지막 묶음
        var low = 0, high = count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if zoomedTop(mid, geometry, scale) <= y { low = mid } else { high = mid - 1 }
        }
        let local = y - zoomedTop(low, geometry, scale)
        if local <= geometry.header { return geometry.tops[low] + local }
        return geometry.tops[low] + geometry.header + (local - geometry.header) / scale
    }

    /// 칸 크기를 바꾸는 중의 사진 자리: 세로는 사진 줄만 scale 배, 가로는 anchorX 를 중심으로 scale 배
    private func zoomedItemFrame(section: Int, item: Int, _ geometry: Geometry, _ zoom: Zoom) -> CGRect {
        let frame = itemFrame(section: section, item: item, geometry)
        let scale = zoom.scale
        return CGRect(x: zoom.anchorX + (frame.minX - zoom.anchorX) * scale,
                      y: zoomedY(frame.minY, section: section, geometry, scale),
                      width: frame.width * scale, height: frame.height * scale)
    }

    private func itemFrame(section: Int, item: Int, _ geometry: Geometry) -> CGRect {
        if geometry.columns == 1 {
            let flat = starts[section] + item
            return CGRect(x: geometry.x, y: geometry.itemTops[flat], width: geometry.width, height: geometry.itemHeights[flat])
        }
        let step = geometry.side + PhotoGridLayout.spacing
        let row = item / geometry.columns, column = item % geometry.columns
        return CGRect(x: geometry.x + CGFloat(column) * step, y: geometry.tops[section] + geometry.header + CGFloat(row) * step,
                      width: geometry.side, height: geometry.side)
    }

    private func headerFrame(section: Int, _ geometry: Geometry) -> CGRect {
        CGRect(x: geometry.x, y: geometry.tops[section], width: geometry.width, height: geometry.header)
    }

    /// rect 에 걸치는 사진·머리글. 묶음과 줄을 반으로 나눠 찾아서 보이는 만큼만 셈
    private func elements(in rect: CGRect, _ geometry: Geometry, items: inout [IndexPath], headers: inout [Int]) {
        let sectionCount = counts.count
        guard sectionCount > 0, rect.maxY > 0, rect.minY < geometry.height else { return }
        // 끝(tops[s + 1])이 rect 위쪽보다 아래인 첫 묶음
        var low = 0, high = sectionCount
        while low < high {
            let mid = (low + high) / 2
            if geometry.tops[mid + 1] > rect.minY { high = mid } else { low = mid + 1 }
        }
        var section = low
        let step = geometry.side + PhotoGridLayout.spacing
        while section < sectionCount && geometry.tops[section] < rect.maxY {
            if headerFrame(section: section, geometry).intersects(rect) { headers.append(section) }
            let count = counts[section]
            if count > 0 {
                if geometry.columns == 1 {
                    let base = starts[section]
                    var lo = base, hi = base + count
                    while lo < hi {
                        let mid = (lo + hi) / 2
                        if geometry.itemTops[mid] + geometry.itemHeights[mid] > rect.minY { hi = mid } else { lo = mid + 1 }
                    }
                    var flat = lo
                    while flat < base + count && geometry.itemTops[flat] < rect.maxY {
                        items.append(IndexPath(item: flat - base, section: section))
                        flat += 1
                    }
                } else {
                    let top = geometry.tops[section] + geometry.header
                    let rows = (count + geometry.columns - 1) / geometry.columns
                    let firstRow = max(0, Int(floor((rect.minY - top) / step)))
                    let lastRow = min(rows - 1, Int(floor((rect.maxY - top) / step)))
                    if firstRow <= lastRow {
                        let first = firstRow * geometry.columns
                        let end = min(count, (lastRow + 1) * geometry.columns)
                        if first < end {
                            for item in first..<end {
                                items.append(IndexPath(item: item, section: section))
                            }
                        }
                    }
                }
            }
            section += 1
        }
    }

    override func prepare() {
        super.prepare()
        if width != cachedWidth || originX != cachedOriginX {
            cache.removeAll()
            cachedWidth = width
            cachedOriginX = originX
        }
    }

    override var collectionViewContentSize: CGSize {
        let fullWidth = collectionView?.bounds.width ?? 0
        if let zoom {
            return CGSize(width: fullWidth, height: contentHeight(columns: zoom.columns, scale: zoom.scale))
        }
        return CGSize(width: fullWidth, height: geometry(columns).height)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard !counts.isEmpty else { return [] }
        var items: [IndexPath] = []
        var headers: [Int] = []
        guard let zoom else {
            let geometry = self.geometry(columns)
            elements(in: rect, geometry, items: &items, headers: &headers)
            var result = headers.map { headerAttributes(section: $0, geometry, zoom: nil) }
            result.append(contentsOf: items.map { itemAttributes($0, geometry, zoom: nil) })
            return result
        }
        // 칸 크기를 바꾸는 중: rect 를 원래 배치의 세로 범위로 되돌려 같은 줄들을 찾고, 바뀐 자리가 rect 에 걸치는 것만
        let geometry = self.geometry(zoom.columns)
        let top = unzoomedY(rect.minY, geometry, zoom.scale)
        let bottom = unzoomedY(rect.maxY, geometry, zoom.scale)
        let search = CGRect(x: geometry.x, y: top, width: max(1, geometry.width), height: max(1, bottom - top))
        elements(in: search, geometry, items: &items, headers: &headers)
        var result: [UICollectionViewLayoutAttributes] = []
        result.reserveCapacity(items.count + headers.count)
        for section in headers {
            let attributes = headerAttributes(section: section, geometry, zoom: zoom)
            if attributes.frame.intersects(rect) { result.append(attributes) }
        }
        for path in items {
            let attributes = itemAttributes(path, geometry, zoom: zoom)
            if attributes.frame.intersects(rect) { result.append(attributes) }
        }
        return result
    }

    private func itemAttributes(_ path: IndexPath, _ geometry: Geometry, zoom: Zoom?) -> UICollectionViewLayoutAttributes {
        let attributes = UICollectionViewLayoutAttributes(forCellWith: path)
        if let zoom {
            attributes.frame = zoomedItemFrame(section: path.section, item: path.item, geometry, zoom)
        } else {
            attributes.frame = itemFrame(section: path.section, item: path.item, geometry)
        }
        return attributes
    }

    private func headerAttributes(section: Int, _ geometry: Geometry, zoom: Zoom?) -> UICollectionViewLayoutAttributes {
        let attributes = UICollectionViewLayoutAttributes(forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                                          with: IndexPath(item: 0, section: section))
        if let zoom {
            // 머리글은 높이 그대로 사진 줄 바로 위에 붙어 감
            attributes.frame = CGRect(x: geometry.x, y: zoomedTop(section, geometry, zoom.scale),
                                      width: geometry.width, height: geometry.header)
        } else {
            attributes.frame = headerFrame(section: section, geometry)
        }
        attributes.zIndex = 1
        return attributes
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.section < counts.count, indexPath.item >= 0, indexPath.item < counts[indexPath.section] else { return nil }
        if let zoom {
            return itemAttributes(indexPath, geometry(zoom.columns), zoom: zoom)
        }
        return itemAttributes(indexPath, geometry(columns), zoom: nil)
    }

    override func layoutAttributesForSupplementaryView(ofKind elementKind: String,
                                                       at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard elementKind == UICollectionView.elementKindSectionHeader, indexPath.section < counts.count else { return nil }
        if let zoom {
            return headerAttributes(section: indexPath.section, geometry(zoom.columns), zoom: zoom)
        }
        return headerAttributes(section: indexPath.section, geometry(columns), zoom: nil)
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.width != collectionView?.bounds.width
    }

    override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
        super.invalidateLayout(with: context)
        // 안전 영역(가로 화면의 노치)이 바뀌었으면 다시 계산
        if originX != cachedOriginX { cache.removeAll() }
    }
}

/// 사진 격자. 보관함·미분류 탭은 날짜별로, 앨범 안은 순정 사진 앱처럼 큰 대표 사진 아래 이어서 보여 줌.
/// 길게 누르거나 '선택' 뒤 옆으로 끌면 여러 장 선택
final class GridViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate,
                                UICollectionViewDataSourcePrefetching, UIGestureRecognizerDelegate {
    private let folder: Folder
    /// 보여 주는 사진 목록 (화면 차례). 같은 목록인지는 list.version 으로 앎 (사진을 하나하나 비교하지 않음)
    private var list: AssetList = .empty
    private var sections: DaySections = []
    /// 처음에 바로 날짜로 나누는 사진 수. 그 뒤는 한 묶음으로 두고, 전체는 뒤에서 계산해 바꿔 넣음
    private static let exactSectionLimit = 3000
    private var collectionView: UICollectionView!
    private let gridLayout = PhotoGridLayout()
    private let emptyLabel = UILabel()
    private var selecting = false
    private var thumbSize = CGSize(width: 240, height: 240)
    private let isRoot: Bool
    private var selectedPerSection: [Int: Int] = [:]
    /// 두 손가락으로 오갈 수 있는 칸 수 (순정처럼: 앨범 안 5 → 3 → 1, 보관함·미분류 7 → 5 → 3 → 1)
    private let levels: [Int]
    private var columns = 5
    private var pinchRecognizer: UIPinchGestureRecognizer?

    /// 두 손가락으로 칸 수를 바꾸는 중의 상태
    private struct PinchState {
        /// 지금 기준 칸 수 (levels 안의 차례). 한 번에 여러 단계를 넘어가면 바뀜
        var base: Int
        /// 기준 칸 수일 때의 손가락 벌림 (gesture.scale)
        var startScale: CGFloat
        /// 벌리거나 오므려서 가는 칸 수 (levels 안의 차례). 더 갈 곳이 없으면 nil
        var target: Int?
        /// 기준(0) ~ 가는 칸 수(1)
        var progress: CGFloat
        /// 손가락 아래 사진과 그 사진 안에서 손가락의 세로 위치 (0 위 ~ 1 아래)
        var anchor: IndexPath
        var anchorFraction: CGFloat
        /// 손가락의 세로 위치 (격자 화면 위쪽 기준)
        var fingerY: CGFloat
        /// 손가락 사이의 가로 위치 (격자 좌표). 칸이 이 점을 중심으로 옆으로 커지고 작아짐
        var fingerX: CGFloat
        /// 지금 격자가 그리는 배치 (levels 안의 차례. base 아니면 target). 늘 한 배치만 또렷하게
        var shown: Int
    }
    private var pinch: PinchState?
    /// 배치가 바뀌는 순간 떠 둔 바로 전 화면. 바뀐 격자 위에서 짧게 사라짐 (손가락을 따라 커지고 작아지며).
    /// clip 은 격자 위에 놓이고 앨범 표지 아래부터만 보이게 자름.
    /// rect·finger 는 뜰 때의 자리와 손가락 (이 화면 좌표), side 는 그때의 칸 한 변
    private struct PinchFade {
        let clip: UIView
        let image: UIView
        let rect: CGRect
        let finger: CGPoint
        let side: CGFloat
    }
    private var pinchFade: PinchFade?
    /// 손을 뗀 뒤 가까운 칸 수로 자리 잡는 움직임
    private var settleLink: CADisplayLink?
    private var settle: (from: CGFloat, to: CGFloat, start: CFTimeInterval, duration: CFTimeInterval)?
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
        levels = isRoot ? [1, 3, 5, 7] : [1, 3, 5]
        super.init(nibName: nil, bundle: nil)
        // 앨범 안에서도 순정처럼 아래 탭 막대를 그대로 둠 (닫히는 확대 전환 끝에서 화면이 덜컥이지 않게)
        var saved = isRoot ? Prefs.gridColumns : Prefs.albumGridColumns
        if saved == 4 { saved = 3 }   // 예전의 4칸은 3칸으로
        columns = levels.contains(saved) ? saved : (isRoot ? 3 : 5)
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

        // 앨범 표지는 정사각형 (앨범 카드와 같은 모양이라 확대 전환이 딱 맞음)
        gridLayout.headerHeight = isRoot ? 42 : nil
        gridLayout.columns = columns
        gridLayout.aspect = { [weak self] flat in
            guard let self, flat >= 0, flat < self.list.count else { return 1 }
            let asset = self.list[flat]
            guard asset.pixelWidth > 0, asset.pixelHeight > 0 else { return 1 }
            return CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
        }
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: gridLayout)
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

        // 두 손가락으로 벌리고 오므려 칸 수 바꾸기 (손가락을 따라 칸이 커지고 작아짐)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        pinch.delegate = self
        collectionView.addGestureRecognizer(pinch)
        pinchRecognizer = pinch

        // 아래 막대 버튼(공유·⋯·휴지통)은 선택하는 동안에만 붙임 (setSelecting).
        // 평소에도 붙어 있으면 보기 화면을 닫을 때 보기 화면의 아래 막대가 이 버튼들로 바뀌며 사라짐

        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: Library.didChange, object: nil)
        reloadFromLibrary(force: true)
        updateChrome()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateThumbSize()
    }

    /// 썸네일을 받을 크기: 지금 칸 수의 한 칸 (1칸이면 화면 너비). 칸 수가 정해질 때만 바뀜 (손가락을 움직이는 동안은 그대로)
    private func updateThumbSize() {
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
        // 선택 중이 아니면 아래 막대는 숨기고 탭 막대는 보이게 (어긋난 채로 남지 않게. 맞으면 건드리지 않음)
        if !selecting { navigationController?.ensureBrowsingBars(of: self) }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 칸 수를 바꾸던 중이면 가까운 칸 수로 바로 마침
        finishPinchNow()
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
        if selecting || isPinching { return false }
        if location.x <= 44 && velocity.x > 0 && velocity.x > abs(velocity.y) { return true }
        guard ZoomGesture.isDownward(velocity), isViewLoaded, collectionView != nil else { return false }
        let top = -collectionView.adjustedContentInset.top
        return collectionView.contentOffset.y <= top + 1
    }

    // MARK: - 두 손가락으로 칸 수 바꾸기 (순정처럼 손가락을 따라 칸이 커지고 작아지다가, 놓으면 가까운 칸 수로)

    /// 칸 수를 바꾸는 중(손가락이 닿아 있거나, 놓은 뒤 자리 잡는 중)인지
    private var isPinching: Bool {
        pinch != nil || settleLink != nil
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pinchRecognizer else { return true }
        // 선택 중에는 칸 수를 바꾸지 않음 (두 손가락으로 끌어 고르기·길게 누르기와 부딪히지 않게). 화면 전환 중에도
        return !selecting && !transitioning && !sections.isEmpty && collectionView != nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // 스크롤이 먼저 잡혀도 벌리기가 시작될 수 있게. 벌리기가 시작되면 스크롤을 끔 (beginPinch)
        gestureRecognizer === pinchRecognizer && otherGestureRecognizer === collectionView?.panGestureRecognizer
    }

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            beginPinch(gesture)
        case .changed:
            updatePinch(gesture)
        case .ended:
            endPinch(velocity: gesture.velocity, cancelled: false)
        case .cancelled, .failed:
            endPinch(velocity: 0, cancelled: true)
        default:
            break
        }
    }

    private func beginPinch(_ gesture: UIPinchGestureRecognizer) {
        finishPinchNow()
        guard let base = levels.firstIndex(of: columns), !sections.isEmpty else { return }
        collectionView.layoutIfNeeded()
        let point = gesture.location(in: collectionView)
        guard let anchor = nearestItem(to: point), let frame = gridLayout.layoutAttributesForItem(at: anchor)?.frame else { return }
        // 미끄러지던 스크롤을 그 자리에서 멈추고, 칸 수를 바꾸는 동안은 스크롤이 끼어들지 않게
        collectionView.setContentOffset(collectionView.contentOffset, animated: false)
        collectionView.panGestureRecognizer.isEnabled = false
        let fraction = frame.height > 0 ? min(1, max(0, (point.y - frame.minY) / frame.height)) : 0.5
        pinch = PinchState(base: base, startScale: max(0.01, gesture.scale), target: nil, progress: 0,
                           anchor: anchor, anchorFraction: fraction,
                           fingerY: point.y - collectionView.contentOffset.y, fingerX: point.x, shown: base)
        applyPinch()
    }

    /// 손가락 아래의 사진 (사이 틈이나 머리글 위면 가장 가까운 사진)
    private func nearestItem(to point: CGPoint) -> IndexPath? {
        if let path = collectionView.indexPathForItem(at: point) { return path }
        var best: (path: IndexPath, distance: CGFloat)?
        for path in collectionView.indexPathsForVisibleItems {
            guard let frame = gridLayout.layoutAttributesForItem(at: path)?.frame else { continue }
            let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
            let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
            let distance = dx * dx + dy * dy
            if best == nil || distance < (best?.distance ?? 0) { best = (path, distance) }
        }
        return best?.path
    }

    private func updatePinch(_ gesture: UIPinchGestureRecognizer) {
        guard var state = pinch, settleLink == nil else { return }
        let point = gesture.location(in: collectionView)
        state.fingerY = point.y - collectionView.contentOffset.y
        state.fingerX = point.x
        // 칸 한 변이 손가락 벌림에 그대로 비례하게: 기준 칸 수의 한 변 × (지금 벌림 ÷ 기준 벌림)
        var scale = gesture.scale / state.startScale
        while true {
            let step = scale > 1 ? -1 : (scale < 1 ? 1 : 0)   // 벌리면 칸 수가 적은 쪽(크게)
            let target = state.base + step
            guard step != 0, levels.indices.contains(target) else {
                state.target = nil
                state.progress = 0
                break
            }
            let ratio = levelSide(target) / levelSide(state.base)
            let progress = abs(ratio - 1) > 0.001 ? (scale - 1) / (ratio - 1) : 0
            if progress >= 1, levels.indices.contains(target + step) {
                // 다음 단계를 지나침: 그 칸 수를 새 기준으로 해서 이어감 (한 번에 5 → 3 → 1)
                state.base = target
                state.startScale *= ratio
                scale = gesture.scale / state.startScale
                continue
            }
            state.target = target
            state.progress = min(1, max(0, progress))
            break
        }
        // 그리는 배치: 가는 칸 수로는 0.3 을 넘으면, 기준으로는 0.2 밑으로 내려가면 바꿈 (그 사이에서 깜빡이지 않게)
        var shown = state.shown
        if let target = state.target {
            if state.shown == target {
                if state.progress < 0.2 { shown = state.base }
            } else if state.shown == state.base {
                if state.progress > 0.3 { shown = target }
            } else {
                // 한 번에 여러 단계를 넘어감 등: 가까운 쪽으로
                shown = state.progress > 0.3 ? target : state.base
            }
        } else {
            shown = state.base
        }
        if shown != state.shown { switchShown(to: shown, &state) }
        pinch = state
        applyPinch()
    }

    /// 지금 칸 한 변: 기준 칸 수와 가는 칸 수 사이를 progress 만큼 (가는 칸 수가 없으면 기준 그대로)
    private func pinchSide(_ state: PinchState) -> CGFloat {
        let baseSide = levelSide(state.base)
        guard let target = state.target else { return baseSide }
        let progress = min(1, max(0, state.progress))
        return baseSide + (levelSide(target) - baseSide) * progress
    }

    /// 그리는 배치를 바꿈: 바꾸기 바로 전 화면을 떠서 위에 얹고 짧게 사라지게 함 (순정처럼 0.2초 남짓, 손가락과 상관없이)
    private func switchShown(to index: Int, _ state: inout PinchState) {
        removePinchFade()
        let frame = collectionView.frame
        var top = frame.minY
        if let cover = gridLayout.coverHeight {
            top = max(top, frame.minY + cover - collectionView.contentOffset.y)
        }
        let rect = CGRect(x: frame.minX, y: top, width: frame.width, height: frame.maxY - top)
        let finger = CGPoint(x: frame.minX + state.fingerX - collectionView.contentOffset.x, y: frame.minY + state.fingerY)
        let side = pinchSide(state)
        state.shown = index
        // 이 화면에서 뜸 (바탕까지 함께라 그림이 불투명함). 아직 그려지지 않은 바뀐 배치가 아니라 지금 보이는 화면
        guard rect.width > 1, rect.height > 1,
              let image = view.resizableSnapshotView(from: rect, afterScreenUpdates: false, withCapInsets: .zero) else { return }
        let clip = UIView()
        clip.clipsToBounds = true
        clip.isUserInteractionEnabled = false
        clip.backgroundColor = .clear
        image.isUserInteractionEnabled = false
        clip.addSubview(image)
        view.insertSubview(clip, aboveSubview: collectionView)
        let fade = PinchFade(clip: clip, image: image, rect: rect, finger: finger, side: side)
        pinchFade = fade
        placePinchFade(fade, state)
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut], animations: {
            clip.alpha = 0
        }, completion: { [weak self] _ in
            clip.removeFromSuperview()
            if self?.pinchFade?.clip === clip { self?.pinchFade = nil }
        })
    }

    private func levelSide(_ index: Int) -> CGFloat {
        max(1, gridLayout.side(columns: levels[index]))
    }

    /// 지금 상태를 격자에 반영 (순정처럼): 격자는 늘 한 배치(shown)만 또렷하게 그리고,
    /// 칸 한 변은 기준 칸 수와 가는 칸 수 사이를 progress 만큼 (넘치면 화면 옆으로 잘리고, 작으면 옆이 빔).
    /// 손가락 아래 사진은 손가락 아래에 그대로. 배치가 바뀌는 순간만 switchShown 이 짧게 겹쳐 바꿈
    private func applyPinch() {
        guard let state = pinch else { return }
        let shown = levels.indices.contains(state.shown) ? state.shown : state.base
        let columns = levels[shown]
        let scale = pinchSide(state) / levelSide(shown)
        gridLayout.zoom = PhotoGridLayout.Zoom(columns: columns, scale: scale, anchorX: state.fingerX)
        setPinchOffset(anchoredOffset(columns: columns, scale: scale, state))
        if let fade = pinchFade { placePinchFade(fade, state) }
    }

    private func setPinchOffset(_ y: CGFloat) {
        collectionView.contentOffset = CGPoint(x: collectionView.contentOffset.x, y: y)
        collectionView.layoutIfNeeded()
    }

    /// 사라지는 중인 전 화면을 손가락을 따라 (뜰 때의 손가락 자리를 중심으로, 그때보다 칸이 커진 만큼) 옮김.
    /// 자르는 판은 지금 앨범 표지 아래부터 (표지를 덮지 않게)
    private func placePinchFade(_ fade: PinchFade, _ state: PinchState) {
        let frame = collectionView.frame
        var clipTop = frame.minY
        if let cover = gridLayout.coverHeight {
            clipTop = max(clipTop, frame.minY + cover - collectionView.contentOffset.y)
        }
        clipTop = min(clipTop, frame.maxY)
        fade.clip.frame = CGRect(x: frame.minX, y: clipTop, width: frame.width, height: frame.maxY - clipTop)
        let scale = pinchSide(state) / max(1, fade.side)
        let finger = CGPoint(x: frame.minX + state.fingerX - collectionView.contentOffset.x, y: frame.minY + state.fingerY)
        let center = CGPoint(x: finger.x + (fade.rect.midX - fade.finger.x) * scale,
                             y: finger.y + (fade.rect.midY - fade.finger.y) * scale)
        fade.image.transform = CGAffineTransform(scaleX: scale, y: scale)
        fade.image.center = CGPoint(x: center.x - frame.minX, y: center.y - clipTop)
    }

    private func removePinchFade() {
        pinchFade?.clip.removeFromSuperview()
        pinchFade = nil
    }

    /// 그 칸 수의 사진 줄이 scale 배일 때 손가락 아래 사진의 같은 점이 손가락 아래에 오는 스크롤 위치 (내용 끝을 넘지 않게)
    private func anchoredOffset(columns: Int, scale: CGFloat, _ state: PinchState) -> CGFloat {
        let insets = collectionView.adjustedContentInset
        let top = -insets.top
        let height = gridLayout.contentHeight(columns: columns, scale: scale)
        let bottom = max(top, height + insets.bottom - collectionView.bounds.height)
        guard let frame = gridLayout.itemFrame(state.anchor, columns: columns, scale: scale) else {
            return min(max(top, collectionView.contentOffset.y), bottom)
        }
        let y = frame.minY + frame.height * state.anchorFraction - state.fingerY
        return min(max(top, y), bottom)
    }

    private func endPinch(velocity: CGFloat, cancelled: Bool) {
        collectionView.panGestureRecognizer.isEnabled = true
        guard var state = pinch, settleLink == nil else { return }
        guard let target = state.target else {
            commitPinch(toTarget: false)
            return
        }
        // 지금 그리는 배치로 마침. 아직 기준 배치인데 빠르게 벌리거나 오므리며 놓았으면(조금 더 갔을 자리가 0.3 을 넘음)
        // 가는 배치로 바꾸고(짧게 겹쳐) 그쪽으로
        if !cancelled, state.shown != target {
            let ratio = levelSide(target) / levelSide(state.base)
            let speed = abs(ratio - 1) > 0.001 ? velocity / state.startScale / (ratio - 1) : 0   // 초당 진행
            if state.progress + speed * 0.15 > 0.3 {
                switchShown(to: target, &state)
                pinch = state
                applyPinch()
            }
        }
        let finish = state.shown == target
        let goal: CGFloat = finish ? 1 : 0
        let distance = abs(goal - state.progress)
        guard distance > 0.001 else {
            commitPinch(toTarget: finish)
            return
        }
        settle = (from: state.progress, to: goal, start: CACurrentMediaTime(), duration: 0.16 + 0.14 * Double(distance))
        let link = CADisplayLink(target: self, selector: #selector(settleTick))
        link.add(to: .main, forMode: .common)
        settleLink = link
    }

    @objc private func settleTick() {
        guard var state = pinch, let settle else {
            commitPinch(toTarget: false)
            return
        }
        let elapsed = (CACurrentMediaTime() - settle.start) / max(0.01, settle.duration)
        let x = CGFloat(min(1, max(0, elapsed)))
        let eased = 1 - pow(1 - x, 3)
        state.progress = settle.from + (settle.to - settle.from) * eased
        pinch = state
        applyPinch()
        if x >= 1 { commitPinch(toTarget: settle.to >= 1) }
    }

    /// 칸 수를 정함 (손가락 아래 사진은 그 자리 그대로). 바뀌었으면 저장하고 그 크기에 맞는 썸네일을 다시 받음
    private func commitPinch(toTarget: Bool) {
        settleLink?.invalidate()
        settleLink = nil
        settle = nil
        // 떠 둔 그림은 어떻게 끝나든 치움
        removePinchFade()
        guard let state = pinch else { return }
        pinch = nil
        let index = (toTarget ? state.target : nil) ?? state.base
        let newColumns = levels[index]
        let offset = anchoredOffset(columns: newColumns, scale: 1, state)
        gridLayout.zoom = nil
        gridLayout.columns = newColumns
        collectionView.contentOffset = CGPoint(x: collectionView.contentOffset.x, y: offset)
        collectionView.layoutIfNeeded()
        collectionView.panGestureRecognizer.isEnabled = true
        if newColumns != columns {
            let grew = newColumns < columns
            columns = newColumns
            if isRoot {
                Prefs.gridColumns = columns
            } else {
                Prefs.albumGridColumns = columns
            }
            Thumbs.manager.stopCachingImagesForAllAssets()
            updateThumbSize()
            // 칸이 커졌으면 보이는 칸만 더 큰 썸네일로 (작아졌으면 지금 그림으로 충분)
            if grew { reloadVisibleThumbnails() }
        }
        if reloadPending && !transitioning {
            reloadPending = false
            reloadFromLibrary(force: false)
        }
    }

    /// 칸 수를 바꾸던 중이면 가까운 쪽으로 바로 마침 (다시 불러오기·화면 전환·선택 전에)
    private func finishPinchNow() {
        guard let state = pinch else {
            settleLink?.invalidate()
            settleLink = nil
            settle = nil
            removePinchFade()
            return
        }
        // 자리 잡는 중이면 그 끝으로, 아니면 지금 그리는 배치로
        let toTarget = settle.map { $0.to >= 1 } ?? (state.target != nil && state.shown == state.target)
        commitPinch(toTarget: toTarget)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        guard !isRoot, isViewLoaded, collectionView != nil else { return }
        collectionView.contentInset.bottom = view.safeAreaInsets.bottom
        collectionView.verticalScrollIndicatorInsets = UIEdgeInsets(top: view.safeAreaInsets.top, left: 0,
                                                                    bottom: view.safeAreaInsets.bottom, right: 0)
    }

    // MARK: - 데이터

    @objc private func libraryChanged() {
        // 화면 전환 중이나 칸 수를 바꾸는 중에는 끝난 뒤에 반영
        if transitioning || isPinching {
            reloadPending = true
            return
        }
        reloadFromLibrary(force: false)
    }

    private func reloadFromLibrary(force: Bool) {
        finishPinchNow()
        let snapshot = Library.shared.snapshot
        if snapshot.loaded && !snapshot.folders.contains(where: { $0.id == folder.id }) && folder.isUser {
            // 폴더가 지워짐
            if navigationController?.topViewController === self {
                navigationController?.popViewController(animated: true)
            }
            return
        }
        // 임시 목록(켤 때 먼저 보여 주는 자동 분류·미분류)은 사진 목록이 없거나 표지 한 장뿐이라 전체 목록이 올 때까지 비워 둠
        let provisional = snapshot.isProvisional(folder.id)
        // 앨범 안은 순정처럼 오래된 항목 순이 기본 (같은 저장소를 뒤집어 봄)
        let new = provisional ? AssetList.empty : Library.shared.list(for: folder.id, newestFirst: newestFirst)
        if !force && new.version == list.version {
            list = new   // 들어 있는 사진·순서는 같고, 즐겨찾기·편집 상태가 바뀐 새 값으로
            refreshHero()   // 이름·표지가 바뀌었을 수 있음
            return
        }

        // 고른 사진은 ID 로 기억했다가 새 목록에서 찾아 다시 고름 (목록 전체를 훑지 않음)
        let keep = selectedAssets().map(\.localIdentifier)
        list = new
        buildSections()
        gridLayout.setSections(sections.map { $0.range.count })
        collectionView.reloadData()
        if !Library.shared.canRead {
            emptyLabel.text = "사진 접근 권한이 필요해요.\n앨범 탭에서 설정을 열 수 있어요."
            collectionView.backgroundView = emptyLabel
        } else {
            emptyLabel.text = "사진이 없어요"
            collectionView.backgroundView = (list.isEmpty && !provisional) ? emptyLabel : nil
        }

        if selecting && !keep.isEmpty {
            for flat in list.indexes(ofIDs: keep) {
                guard let path = indexPath(forFlat: flat) else { continue }
                collectionView.selectItem(at: path, animated: false, scrollPosition: [])
            }
        }
        updateChrome()
    }

    /// 날짜별 묶음. 앨범 안은 한 덩어리. 보관함·미분류는 앞의 몇천 장만 바로 날짜로 나누고(메인 줄에서 전부 읽지 않게)
    /// 나머지는 한 묶음으로 둔 뒤, 전체 묶음을 Library 가 뒤에서 계산해 오면 바꿔 넣음
    private func buildSections() {
        if !isRoot {
            // 앨범 안: 날짜로 나누지 않고 한 덩어리
            sections = list.isEmpty ? [] : [(day: Date(), range: 0..<list.count)]
            return
        }
        if let cached = Library.shared.cachedDaySections(folder.id, version: list.version) {
            sections = cached
            return
        }
        let limit = GridViewController.exactSectionLimit
        sections = list.daySections(limit: limit)
        guard list.count > limit else { return }
        let version = list.version
        Library.shared.daySections(for: list, key: folder.id) { [weak self] full in
            self?.applyFullSections(full, version: version)
        }
    }

    /// 뒤에서 계산한 전체 날짜별 묶음으로 바꿈. 앞부분은 같아서 보통 아무것도 안 움직이고,
    /// 이미 뒷부분까지 내려가 있으면 화면 맨 위의 사진을 제자리에 둠
    private func applyFullSections(_ full: DaySections, version: Int) {
        guard isViewLoaded, collectionView != nil, isRoot, list.version == version else { return }
        if transitioning || isPinching {
            // 화면 전환·칸 수 바꾸기가 끝난 뒤에
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.applyFullSections(full, version: version)
            }
            return
        }
        let selectedFlats = (collectionView.indexPathsForSelectedItems ?? []).map { flatIndex($0) }
        var anchor: (flat: Int, offset: CGFloat)?
        if let top = collectionView.indexPathsForVisibleItems.min(),
           let frame = gridLayout.layoutAttributesForItem(at: top)?.frame {
            anchor = (flatIndex(top), frame.minY - collectionView.contentOffset.y)
        }
        sections = full
        gridLayout.setSections(sections.map { $0.range.count })
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        if let anchor, let path = indexPath(forFlat: anchor.flat),
           let frame = gridLayout.layoutAttributesForItem(at: path)?.frame {
            let y = frame.minY - anchor.offset
            if abs(y - collectionView.contentOffset.y) > 0.5 {
                collectionView.contentOffset = CGPoint(x: collectionView.contentOffset.x, y: y)
            }
        }
        for flat in selectedFlats {
            if let path = indexPath(forFlat: flat) {
                collectionView.selectItem(at: path, animated: false, scrollPosition: [])
            }
        }
        if selecting { updateChrome() }
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

    /// 목록 안의 차례 → 칸 자리 (묶음을 반으로 나눠 찾음)
    private func indexPath(forFlat flat: Int) -> IndexPath? {
        guard flat >= 0, flat < list.count, !sections.isEmpty else { return nil }
        var low = 0, high = sections.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if sections[mid].range.lowerBound <= flat { low = mid } else { high = mid - 1 }
        }
        let range = sections[low].range
        guard range.contains(flat) else { return nil }
        return IndexPath(item: flat - range.lowerBound, section: low)
    }

    /// 그 사진의 칸 자리 (없으면 nil). near 는 그 사진이 있을 만한 차례 (보기 화면의 지금 차례)
    private func indexPath(forAssetID id: String, near hint: Int? = nil) -> IndexPath? {
        guard let flat = list.index(ofID: id, near: hint) else { return nil }
        return indexPath(forFlat: flat)
    }

    /// 사진 전환이 시작하고 돌아올 자리 (그 사진 칸의 그림 판). 화면 밖이면 nil
    func thumbnailView(forAssetID id: String) -> UIView? {
        guard isViewLoaded, collectionView != nil, let path = indexPath(forAssetID: id) else { return nil }
        return (collectionView.cellForItem(at: path) as? AssetCell)?.zoomSourceView
    }

    /// 사진 전환(PhotoTransitionAnimator)이 쓸 칸의 그림 판과 그 썸네일. near 는 보기 화면의 지금 차례 (찾기 빠르게).
    /// reveal 이면(닫힐 때) 그 칸이 화면 밖이거나 막대에 가려 있으면 먼저 그 칸이 가운데 오게 스크롤함 (순정처럼)
    func transitionSource(forAssetID id: String, near hint: Int? = nil, reveal: Bool) -> (view: UIView, image: UIImage?)? {
        guard isViewLoaded, collectionView != nil, let path = indexPath(forAssetID: id, near: hint) else { return nil }
        if reveal, let frame = gridLayout.layoutAttributesForItem(at: path)?.frame {
            collectionView.layoutIfNeeded()
            let visible = view.bounds.inset(by: view.safeAreaInsets)
            let rect = collectionView.convert(frame, to: view)
            if !visible.contains(rect) {
                collectionView.scrollToItem(at: path, at: .centeredVertically, animated: false)
                collectionView.layoutIfNeeded()
            }
        }
        guard let cell = collectionView.cellForItem(at: path) as? AssetCell else { return nil }
        return (cell.zoomSourceView, cell.imageView.image)
    }

    /// '모든 사진에서 보기': 그 사진이 화면 가운데 오게 스크롤 (보관함 탭에서 씀)
    func reveal(assetID id: String) {
        loadViewIfNeeded()
        if selecting { setSelecting(false) }
        if list.index(ofID: id) == nil { reloadFromLibrary(force: false) }
        guard let path = indexPath(forAssetID: id) else { return }
        view.layoutIfNeeded()
        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(at: path, at: .centeredVertically, animated: false)
    }

    private func flatIndex(_ indexPath: IndexPath) -> Int {
        sections[indexPath.section].range.lowerBound + indexPath.item
    }

    private func assetAt(_ indexPath: IndexPath) -> PHAsset {
        list[flatIndex(indexPath)]
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
        loadThumbnail(into: cell, asset: asset)
        return cell
    }

    /// 지금 칸 수에 맞는 크기로 썸네일을 받음 (받는 동안은 지금 그림을 그대로 둠)
    private func loadThumbnail(into cell: AssetCell, asset: PHAsset) {
        let id = asset.localIdentifier
        if cell.requestID != PHInvalidImageRequestID {
            Thumbs.manager.cancelImageRequest(cell.requestID)
        }
        cell.requestID = Thumbs.manager.requestImage(for: asset, targetSize: thumbSize, contentMode: .aspectFill,
                                                     options: Thumbs.options) { [weak cell] image, info in
            guard let cell, cell.assetID == id, let image else { return }
            // 먼저 오는 흐린 그림이 이미 있는 더 선명한 그림을 덮지 않게
            let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            if degraded, let current = cell.imageView.image,
               current.size.width * current.scale >= image.size.width * image.scale { return }
            cell.imageView.image = image
        }
    }

    /// 칸이 커진 뒤 보이는 칸만 새 크기로 다시 받음 (손가락을 움직이는 동안이 아니라 칸 수가 정해질 때 한 번)
    private func reloadVisibleThumbnails() {
        for path in collectionView.indexPathsForVisibleItems {
            guard path.section < sections.count, path.item < sections[path.section].range.count,
                  let cell = collectionView.cellForItem(at: path) as? AssetCell else { continue }
            let asset = assetAt(path)
            guard cell.assetID == asset.localIdentifier else { continue }
            loadThumbnail(into: cell, asset: asset)
        }
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
        hero.countLabel.text = "\(list.count)개의 항목"
        // 사진 앱 앨범은 그 앨범의 대표 사진, 아니면 가장 최근 사진 (앨범 카드와 같은 사진)
        guard let cover = snapshot.cover(folder.id) ?? list.last else { return }
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
            // 칸 수를 바꾸는 중에는 열지 않음
            guard !isPinching else { return }
            let viewer = ViewerViewController(list: list, index: flatIndex(indexPath), folderID: folder.id,
                                              newestFirst: newestFirst, sourceAlbumID: folder.albumID)
            viewer.fallbackBounds = view.bounds
            // 열고 닫는 전환은 내비게이션 delegate(PhotoNavigationDelegate)의 우리 전환:
            // 사진만 이 칸에서 화면에 맞춘 자리로 커지고, 둘레(바탕·줄)는 제자리에서 서서히 (막대는 시스템이 숨기고 보임).
            // 시스템 확대 전환(preferredTransition = .zoom)은 보기 화면 전체를 카드처럼 키워서 쓰지 않음
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
        guard gesture.state == .began, !selecting, !isPinching else { return }
        let point = gesture.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point) else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        setSelecting(true)
        collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        updateChrome()
    }

    private func setSelecting(_ on: Bool) {
        guard selecting != on else { return }
        finishPinchNow()
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
        if on {
            toolbarItems = [shareItem, UIBarButtonItem.flexibleSpace(), moreItem, UIBarButtonItem.flexibleSpace(), deleteItem]
        }
        navigationController?.setToolbarHidden(!on, animated: true)
        if !on {
            // 막대가 다 내려간 뒤에 버튼을 뗌 (내려가는 동안 빈 막대가 보이지 않게). 그사이 다시 선택하면 그대로 둠
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, !self.selecting else { return }
                self.toolbarItems = nil
            }
        }
        updateChrome()
    }

    /// 미분류 사진을 한 장씩 넘기며 정리. 모든 사진을 보게 되니 Face ID 로 확인
    @objc private func startSorter() {
        let current = list
        guard !current.isEmpty else { return }
        Auth.verify(reason: "사진 정리를 시작하려면 인증이 필요해요") { [weak self] ok in
            guard ok, let self else { return }
            self.navigationController?.pushViewController(SorterViewController(assets: current.array()), animated: true)
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
        if selected == list.count {
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
            let allSelected = count == list.count && count > 0
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
                sort.isEnabled = !list.isEmpty
                navigationItem.leftBarButtonItem = sort
            } else {
                navigationItem.leftBarButtonItem = nil
            }
            let select = UIBarButtonItem(title: "선택", style: .plain, target: self, action: #selector(startSelecting))
            select.isEnabled = !list.isEmpty
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
