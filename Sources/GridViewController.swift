import MapKit
import Photos
import PhotosUI
import UIKit

final class AssetCell: UICollectionViewCell {
    static let reuse = "AssetCell"

    let imageView = UIImageView()
    /// 확대 전환이 쓰는 그림 판 (사진 + 길이 글자). 셀 자체는 격자가 자리·변형을 다시 덮어쓰므로 셀 대신 이걸 넘김
    private let thumbView = UIView()
    private let dim = UIView()
    private let badge = UIImageView()
    private let durationLabel = UILabel()
    /// 즐겨찾기 표시 (순정처럼 왼쪽 아래 작은 흰 하트)
    private let heart = UIImageView(image: UIImage(systemName: "heart.fill",
                                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)))

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

    /// 크기는 배치(PhotoGridLayout)가 정함. 셀마다 오토레이아웃으로 크기를 재지 않게 (칸이 1000개 넘으면 이게 제일 느렸음)
    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        super.preferredLayoutAttributesFitting(layoutAttributes)
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

        // 순정 iOS 27: 고른 칸은 살짝 밝아짐 (어두워지지 않음)
        dim.backgroundColor = UIColor.white.withAlphaComponent(0.3)
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

        heart.tintColor = .white
        heart.layer.shadowColor = UIColor.black.cgColor
        heart.layer.shadowOpacity = 0.6
        heart.layer.shadowRadius = 2
        heart.layer.shadowOffset = .zero
        heart.isHidden = true
        heart.translatesAutoresizingMaskIntoConstraints = false
        thumbView.addSubview(heart)

        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.isHidden = true
        contentView.addSubview(badge)

        NSLayoutConstraint.activate([
            durationLabel.trailingAnchor.constraint(equalTo: thumbView.trailingAnchor, constant: -5),
            durationLabel.bottomAnchor.constraint(equalTo: thumbView.bottomAnchor, constant: -4),
            heart.leadingAnchor.constraint(equalTo: thumbView.leadingAnchor, constant: 5),
            heart.bottomAnchor.constraint(equalTo: thumbView.bottomAnchor, constant: -5),
            // 순정처럼 오른쪽 아래
            badge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            badge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            badge.widthAnchor.constraint(equalToConstant: 22),
            badge.heightAnchor.constraint(equalToConstant: 22),
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

    /// 종횡비 격자: 사진 전체가 칸 안에 (잘리지 않게)
    var aspectFit = false {
        didSet {
            imageView.contentMode = aspectFit ? .scaleAspectFit : .scaleAspectFill
            imageView.backgroundColor = aspectFit ? .clear : .secondarySystemBackground
        }
    }

    func setFavorite(_ on: Bool) {
        heart.isHidden = !on
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

    /// 순정 iOS 27: 고르지 않은 칸에는 아무 표시 없음. 고른 칸만 밝게 + 흰 테두리 파란 체크
    private func updateBadge() {
        let on = selecting && isSelected
        dim.isHidden = !on
        badge.isHidden = !on
        // 순정: 고른 비디오는 길이 대신 체크만
        durationLabel.alpha = on ? 0 : 1
        guard on else { return }
        let config = UIImage.SymbolConfiguration(paletteColors: [.white, .systemBlue])
            .applying(UIImage.SymbolConfiguration(pointSize: 19, weight: .regular))
        badge.image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: config)
        badge.backgroundColor = .white
        badge.layer.cornerRadius = 11
        badge.contentMode = .center
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
    /// 오른쪽 아래 재생(슬라이드쇼) 버튼 — 순정처럼 반투명 원
    let playButton = UIButton(type: .system)
    var onPlay: (() -> Void)?
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
            playButton.alpha = newValue
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
        titleLabel.font = .systemFont(ofSize: 40, weight: .bold)
        titleLabel.textColor = .white
        addSubview(titleLabel)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.6
        countLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        countLabel.textColor = .white
        addSubview(countLabel)
        glyph.tintColor = .white
        glyph.contentMode = .scaleAspectFit
        glyph.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        addSubview(glyph)
        var config = UIButton.Configuration.filled()
        config.image = UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .bold))
        config.baseForegroundColor = .white
        config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.3)
        config.cornerStyle = .capsule
        playButton.configuration = config
        playButton.addAction(UIAction { [weak self] _ in self?.onPlay?() }, for: .primaryActionTriggered)
        addSubview(playButton)
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
        // 순정 iOS 27: 왼쪽 16, 이름 40pt 굵게, 그 아래 앨범 모양 + "항목 N개", 오른쪽 아래 재생 버튼
        glyph.frame = CGRect(x: 16, y: bounds.height - 38, width: 18, height: 18)
        countLabel.frame = CGRect(x: 40, y: bounds.height - 41, width: bounds.width - 120, height: 24)
        titleLabel.frame = CGRect(x: 16, y: bounds.height - 92, width: bounds.width - 100, height: 50)
        playButton.frame = CGRect(x: bounds.width - 16 - 44, y: bounds.height - 18 - 44, width: 44, height: 44)
    }
}

/// 사진 격자 배치. 칸 수(1·3·5·7)마다 자리를 한 번 계산해 두고 (묶음마다 맨 위 높이만 — 사진 수와 상관없이 빠름),
/// 두 손가락으로 벌리고 오므리는 동안은 한 배치(칸 수)를 그대로 두고 사진 줄만 크게·작게 그림 (zoom).
/// 사진은 제자리에서 커지고 작아질 뿐 다른 자리로 옮겨 가지 않음 — 배치가 바뀌는 순간은 격자 화면이 짧게 겹쳐 바꿈.
/// 1칸은 사진마다 원래 비율로 화면 너비를 꽉 채움. 묶음마다 맨 위에 머리글(날짜) 또는 정사각형 앨범 표지
final class PhotoGridLayout: UICollectionViewLayout {
    /// 보관함을 끝까지 오므린 칸 수
    static let denseColumns = 25
    /// 앨범 표지 높이 ÷ 화면 너비 (순정 iOS 27 앨범 화면: iPhone 14 Pro 393pt 너비에 약 480pt)
    static let coverRatio: CGFloat = 1.22
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

    /// 사진이 놓이는 너비와 왼쪽 시작. 순정 iOS 27 은 가로 화면에서도 사진이 양끝까지 꽉 참 (노치 쪽도)
    private var width: CGFloat {
        collectionView?.bounds.width ?? 0
    }

    private var originX: CGFloat { 0 }

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
        // 칸 너비는 나눈 값 그대로 (내림하면 25칸에서 오른쪽에 20pt 가까이 빔). 자리는 itemFrame 에서 화소에 맞춤
        let side = perRow == 1 ? width : max(perRow >= PhotoGridLayout.denseColumns ? 8 : 20,
                                             (width - spacing * CGFloat(perRow - 1)) / CGFloat(perRow))
        let header = headerHeight ?? (width * PhotoGridLayout.coverRatio).rounded()
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
        return (width * PhotoGridLayout.coverRatio).rounded()
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
        // 칸 끝을 화소에 맞춤 (칸마다 1화소쯤 다를 수 있지만 사이 간격은 같고 오른쪽 끝까지 꽉 참)
        let minX = pixel(geometry.x + CGFloat(column) * step)
        let maxX = column == geometry.columns - 1 ? geometry.x + geometry.width
            : pixel(geometry.x + CGFloat(column) * step + geometry.side)
        let minY = pixel(geometry.tops[section] + geometry.header + CGFloat(row) * step)
        let maxY = pixel(geometry.tops[section] + geometry.header + CGFloat(row) * step + geometry.side)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func pixel(_ value: CGFloat) -> CGFloat {
        let scale = collectionView?.traitCollection.displayScale ?? 3
        return (value * scale).rounded() / scale
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
            // 머리글 높이가 0 이면(보관함·미분류) 머리글을 아예 안 둠 (빈 머리글의 글자가 사진 위로 삐져나오지 않게)
            if geometry.header <= 0 { headers.removeAll() }
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
        if geometry.header <= 0 { headers.removeAll() }
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
    /// 보관함·미분류 위의 제목 (순정 iOS 27 처럼 사진 위에 어두운 그라데이션 + 흰 큰 제목 + 날짜·개수)
    private let titleOverlay = LibraryTitleOverlay()
    /// 보관함 아래 [년 | 월 | 전체] (끝까지 오므렸거나 년·월 보기일 때)
    private let modeBar = LibraryModeBar()
    private var moments: MomentsViewController?
    private var momentsData: MomentsData?
    private var momentsVersion = -1
    /// 처음 보일 때 최신 사진(맨 끝)으로 내려가야 하는지 (자리가 잡힌 뒤에)
    private var needsScrollToLatest = true
    /// 보관함의 필터 (순정 필터 메뉴처럼: 모든 항목 · 즐겨찾기 · 비디오)
    private var libraryFilter: LibraryFilter = .all
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
    private var dragSelectRecognizer: UIPanGestureRecognizer?
    /// 끌어 고르기: 시작 차례, 고르는지(아니면 빼는지), 시작 전 고른 것, 지금 칠한 범위
    private var dragSelect: (start: Int, selecting: Bool, before: Set<Int>, range: ClosedRange<Int>)?
    private var dragScrollLink: CADisplayLink?
    private var dragScrollSpeed: CGFloat = 0

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
    /// 순정 iOS 27 선택 막대 가운데: "선택된 항목 표시(N개)" — 누르면 고른 것만 보기 / 다시 누르면 전체
    private lazy var showSelectedItem = UIBarButtonItem(title: "항목 선택", style: .plain, target: self, action: #selector(toggleShowSelected))
    /// 고른 것만 보는 중이면 그때의 전체 목록 (돌아갈 때 씀)
    private var listBeforeShowingSelected: AssetList?
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
        // 보관함은 순정처럼 끝까지 오므리면 아주 촘촘한 칸(그때 아래에 [년 | 월 | 전체])
        levels = folder.id == "all" ? [1, 3, 5, 7, PhotoGridLayout.denseColumns] : (isRoot ? [1, 3, 5, 7] : [1, 3, 5])
        super.init(nibName: nil, bundle: nil)
        // 앨범 안에서도 순정처럼 아래 탭 막대를 그대로 둠 (닫히는 확대 전환 끝에서 화면이 덜컥이지 않게)
        var saved = isRoot ? Prefs.gridColumns : Prefs.albumGridColumns
        if saved == 4 { saved = 3 }   // 예전의 4칸은 3칸으로
        // 순정 iOS 27 은 보관함·앨범 모두 3칸이 기본
        columns = levels.contains(saved) ? saved : 3
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
        // 보관함·미분류의 큰 제목은 시스템 막대가 아니라 사진 위에 직접 그림 (순정 iOS 27)
        navigationItem.largeTitleDisplayMode = .never

        // 앨범 표지는 정사각형 (앨범 카드와 같은 모양이라 확대 전환이 딱 맞음)
        // 보관함·미분류는 날짜 머리글 없이 한 덩어리 (순정 iOS 27: 날짜는 제목 밑에 지금 보이는 곳 기준으로)
        gridLayout.headerHeight = isRoot ? 0 : nil
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
        collectionView.register(AddTileCell.self, forCellWithReuseIdentifier: AddTileCell.reuse)
        collectionView.register(DayHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: DayHeaderView.reuse)
        collectionView.register(HeroHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: HeroHeaderView.reuse)
        // 앨범: 대표 사진이 화면 맨 위까지. 보관함·미분류: 순정 iOS 27 처럼 사진이 제목 뒤 맨 위까지 (아래만 띄움)
        collectionView.contentInsetAdjustmentBehavior = .never
        view.addSubview(collectionView)
        // 맨 아래에 backdrop 이 먼저 깔려 있어 UIKit 이 이 스크롤뷰를 스스로 못 찾음.
        // 알려 줘야 스크롤할 때 큰 제목이 접히고, 위·아래 막대 밑의 흐림(가장자리 효과)이 생김
        setContentScrollView(collectionView, for: [.top, .bottom])
        if isRoot {
            titleOverlay.title = folder.title
            if folder.id == "all" {
                modeBar.isHidden = true
                modeBar.onMode = { [weak self] mode in self?.setLibraryMode(mode) }
                modeBar.onLibrary = { [weak self] in self?.leaveDense() }
                modeBar.onSearch = { [weak self] in self?.presentSearch() }
                view.addSubview(modeBar)
            }
            view.addSubview(titleOverlay)
            // 위쪽은 우리 그라데이션이 맡음 (시스템 가장자리 효과가 겹치면 막대 아래로 딱딱한 선이 생김)
            if #available(iOS 26.0, *) {
                collectionView.topEdgeEffect.isHidden = true
            }
        }

        emptyLabel.text = "사진이 없어요"
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.font = .systemFont(ofSize: 16)

        // 길게 누르면 순정 iOS 27 처럼 사진 미리보기 + 메뉴 (collectionView(_:contextMenuConfigurationForItemsAt:point:))

        // 두 손가락으로 벌리고 오므려 칸 수 바꾸기 (손가락을 따라 칸이 커지고 작아짐)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        pinch.delegate = self
        collectionView.addGestureRecognizer(pinch)
        pinchRecognizer = pinch

        // 고르는 중 옆으로 끌면 여러 장 고르기 (순정: 지나간 차례 전체, 위아래 끝에서 저절로 스크롤)
        let drag = UIPanGestureRecognizer(target: self, action: #selector(dragSelected(_:)))
        drag.maximumNumberOfTouches = 1
        drag.delegate = self
        collectionView.addGestureRecognizer(drag)
        collectionView.panGestureRecognizer.require(toFail: drag)
        // 고르지 않을 때는 꺼 둠 (꺼져 있어야 '어디서나 밀어서 뒤로'·스크롤과 부딪히지 않음)
        drag.isEnabled = false
        dragSelectRecognizer = drag

        // 아래 막대 버튼(공유·⋯·휴지통)은 선택하는 동안에만 붙임 (setSelecting).
        // 평소에도 붙어 있으면 보기 화면을 닫을 때 보기 화면의 아래 막대가 이 버튼들로 바뀌며 사라짐

        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: Library.didChange, object: nil)
        reloadFromLibrary(force: true)
        updateChrome()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateThumbSize()
        if isRoot {
            layoutTitleOverlay()
            alignShortContentToBottom()
            updateModeBar()
            updateYearChip()
            if needsScrollToLatest, !list.isEmpty, view.bounds.height > 0 {
                needsScrollToLatest = false
                scrollToLatest()
            }
        }
    }

    // MARK: - 보관함 위 제목 (순정 iOS 27)

    /// 위 막대 버튼 줄의 높이에 제목을 맞추고, 그 아래로 날짜·개수, 그 밑까지 어두운 그라데이션
    // MARK: - 년 · 월 · 전체 (순정 iOS 27)

    /// 순정 iOS 27: 년·월 보기이거나, 보관함을 스크롤해 최신 끝에서 떨어져 있으면 [년 | 월 | 전체].
    /// 최신 끝에 닿으면 탭 막대로 돌아감
    private var modeBarVisible: Bool {
        guard folder.id == "all", !selecting, collectionView != nil else { return false }
        if moments != nil { return true }
        guard !list.isEmpty else { return false }
        // 한 화면에 다 들어와 스크롤할 수 없으면 끝까지 오므렸을 때 늘 보이게 (안 그러면 년·월로 갈 길이 없음)
        if columns == PhotoGridLayout.denseColumns,
           collectionView.contentSize.height <= collectionView.bounds.height - collectionView.adjustedContentInset.bottom { return true }
        let inset = collectionView.adjustedContentInset
        let maxOffset = max(-inset.top, collectionView.contentSize.height + inset.bottom - collectionView.bounds.height)
        let away = newestFirst ? collectionView.contentOffset.y - (-inset.top) : maxOffset - collectionView.contentOffset.y
        // 켜고 끄는 문턱을 다르게 (탭 막대가 숨으면 아래 여백이 바뀌어 스크롤 끝이 움직임 → 다시 켜지고 꺼지며 맴돌지 않게)
        return modeBar.isHidden ? away > 80 : away > 16
    }

    /// 끝까지 오므린 칸에서 제목 아래의 연도 칩 (지금 보이는 연도)
    private let yearChip: UILabel = {
        let label = ChipLabel()
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .label
        label.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.85)
        label.layer.cornerRadius = 11
        label.layer.cornerCurve = .continuous
        label.clipsToBounds = true
        label.isHidden = true
        return label
    }()

    /// 촘촘한 칸에서 해가 바뀌는 첫 사진마다 붙는 연도 칩 (순정 iOS 27)
    private var yearStarts: [(flat: Int, year: Int)] = []
    private var yearStartsVersion = -1
    private var yearStartsLoading = false
    private var boundaryChips: [Int: UILabel] = [:]

    private func updateBoundaryChips() {
        guard folder.id == "all", collectionView != nil else { return }
        let dense = columns == PhotoGridLayout.denseColumns && moments == nil && !list.isEmpty
        guard dense else {
            boundaryChips.values.forEach { $0.removeFromSuperview() }
            boundaryChips.removeAll()
            return
        }
        if yearStartsVersion != list.version {
            guard !yearStartsLoading else { return }
            yearStartsLoading = true
            let current = list
            let version = list.version
            DispatchQueue.global(qos: .userInitiated).async {
                var starts: [(Int, Int)] = []
                var last = Int.min
                let calendar = Calendar.current
                for (index, asset) in current.array().enumerated() {
                    guard let date = asset.creationDate else { continue }
                    let year = calendar.component(.year, from: date)
                    if year != last { starts.append((index, year)); last = year }
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.yearStartsLoading = false
                    guard self.list.version == version else { return }
                    self.yearStarts = starts.map { (flat: $0.0, year: $0.1) }
                    self.yearStartsVersion = version
                    self.updateBoundaryChips()
                }
            }
            return
        }
        let visible = collectionView.bounds
        var keep = Set<Int>()
        // 한 줄에 해가 여럿 바뀌면 그 줄의 마지막 해 하나만, 줄 왼쪽에 (칩끼리 겹치지 않게)
        var perRow: [CGFloat: (flat: Int, year: Int)] = [:]
        for start in yearStarts {
            guard let path = indexPath(forFlat: start.flat),
                  let frame = gridLayout.layoutAttributesForItem(at: path)?.frame, frame.intersects(visible.insetBy(dx: 0, dy: -40)) else { continue }
            perRow[frame.minY] = start
        }
        for (rowY, start) in perRow {
            keep.insert(start.flat)
            let frame = CGRect(x: collectionView.safeAreaInsets.left, y: rowY, width: 0, height: 0)
            let chip = boundaryChips[start.flat] ?? {
                let label = ChipLabel()
                label.font = .systemFont(ofSize: 13, weight: .semibold)
                label.textColor = .label
                label.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.85)
                label.layer.cornerRadius = 11
                label.layer.cornerCurve = .continuous
                label.clipsToBounds = true
                label.text = "\(start.year)년"
                label.sizeToFit()
                collectionView.addSubview(label)
                boundaryChips[start.flat] = label
                return label
            }()
            chip.frame = CGRect(x: frame.minX + 6, y: frame.minY + 4, width: chip.bounds.width, height: 22)
            chip.layer.zPosition = 10
        }
        for (flat, chip) in boundaryChips where !keep.contains(flat) {
            chip.removeFromSuperview()
            boundaryChips[flat] = nil
        }
    }

    private func updateYearChip() {
        updateBoundaryChips()
        guard folder.id == "all", collectionView != nil else { return }
        // 한 화면에 다 들어오면(아래에 붙은 짧은 목록) 칩 없이
        let show = columns == PhotoGridLayout.denseColumns && moments == nil && !list.isEmpty
            && collectionView.contentInset.top < 1
        yearChip.isHidden = !show
        guard show else { return }
        let inset = collectionView.adjustedContentInset
        let probeY = collectionView.contentOffset.y + max(inset.top, titleOverlay.frame.maxY) + 4
        let path = collectionView.indexPathForItem(at: CGPoint(x: 10, y: probeY)) ?? collectionView.indexPathsForVisibleItems.min()
        guard let path, let date = list[flatIndex(path)].creationDate else { return }
        let text = "\(Calendar.current.component(.year, from: date))년"
        if yearChip.text != text { yearChip.text = text }
        yearChip.sizeToFit()
        yearChip.frame = CGRect(x: view.safeAreaInsets.left + 12, y: titleOverlay.frame.maxY + 4,
                                width: yearChip.bounds.width, height: 22)
        if yearChip.superview == nil { view.addSubview(yearChip) }
        view.bringSubviewToFront(yearChip)
    }

    private func updateModeBar() {
        guard folder.id == "all", isViewLoaded else { return }
        // 칸 수를 바꾸는 중에는 건드리지 않음 (탭 막대를 숨기고 보이면 화면 전체가 다시 배치돼 1000칸 넘게 다시 그림)
        // 끝나면 commitPinch 가 다시 부름
        if isPinching { return }
        // 고르는 중에는 둘 다 숨기고 선택 막대만 (순정)
        let show = modeBarVisible && !selecting
        if modeBar.isHidden == show {
            modeBar.isHidden = !show
        }
        // 탭 막대는 늘 막대와 반대로 (다른 곳에서 탭 막대를 다시 보이게 해도 맞춤)
        let hideTabs = show || selecting
        if #available(iOS 18.0, *), let tabs = tabBarController,
           navigationController?.topViewController === self, tabs.isTabBarHidden != hideTabs {
            tabs.setTabBarHidden(hideTabs, animated: true)
        }
        if show {
            let height: CGFloat = 56
            let bottom = view.bounds.height - max(view.safeAreaInsets.bottom, 20) - 4
            modeBar.frame = CGRect(x: 16, y: bottom - height, width: view.bounds.width - 32, height: height)
            view.bringSubviewToFront(modeBar)
        }
    }

    private func setLibraryMode(_ mode: LibraryMode, month: Int? = nil) {
        modeBar.mode = mode
        if mode == .all {
            moments?.willMove(toParent: nil)
            moments?.view.removeFromSuperview()
            moments?.removeFromParent()
            moments = nil
            titleOverlay.isHidden = false
            navigationItem.rightBarButtonItems?.forEach { $0.isHidden = false }
            updateModeBar()
            return
        }
        let child: MomentsViewController
        if let existing = moments {
            child = existing
        } else {
            child = MomentsViewController(mode: mode)
            child.onPickYear = { [weak self] month in self?.setLibraryMode(.months, month: month) }
            child.onPickDay = { [weak self] id in self?.openDay(id) }
            addChild(child)
            child.view.frame = view.bounds
            child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.insertSubview(child.view, belowSubview: modeBar)
            child.didMove(toParent: self)
            moments = child
        }
        // 순정 년·월 보기에는 큰 제목·위 버튼이 없음
        titleOverlay.isHidden = true
        navigationItem.rightBarButtonItems?.forEach { $0.isHidden = true }
        updateModeBar()
        let version = list.version
        if let data = momentsData, momentsVersion == version {
            child.show(data, mode: mode, scrollToMonth: month)
            return
        }
        let current = list
        DispatchQueue.global(qos: .userInitiated).async {
            let data = MomentsData.build(current.array())
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.momentsData = data
                self.momentsVersion = version
                if self.moments === child { child.show(data, mode: child === self.moments ? self.modeBar.mode : mode, scrollToMonth: month) }
            }
        }
    }

    private func presentSearch() {
        // 탭 막대에 검색 탭이 있으면 그 탭으로 (순정처럼 같은 검색 화면)
        if let tabs = tabBarController,
           let index = tabs.viewControllers?.firstIndex(where: { ($0 as? UINavigationController)?.viewControllers.first is SearchViewController }) {
            tabs.selectedIndex = index
            return
        }
        if #available(iOS 26.0, *), let tabs = tabBarController, let search = tabs.tabs.first(where: { $0 is UISearchTab }) {
            tabs.selectedTab = search
            return
        }
        let search = SearchViewController()
        search.onOpenFolder = { [weak self] id in self?.openFolderFromSearch(id) }
        let nav = UINavigationController(rootViewController: search)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    /// 검색에서 앨범을 고름: 앨범 탭으로 가서 그 앨범을 엶
    private func openFolderFromSearch(_ id: String) {
        guard let folder = Library.shared.snapshot.folders.first(where: { $0.id == id }),
              let tabs = tabBarController, let viewControllers = tabs.viewControllers, viewControllers.count > 1,
              let albums = viewControllers[1] as? UINavigationController else { return }
        tabs.selectedIndex = 1
        albums.popToRootViewController(animated: false)
        albums.pushViewController(GridViewController(folder: folder), animated: true)
    }

    /// 월 보기에서 날짜를 누름 → 전체 보기(3칸)에서 그날로
    private func openDay(_ id: String) {
        setLibraryMode(.all)
        setColumnsDirectly(3)
        reveal(assetID: id)
        updateModeBar()
    }

    /// 아래 막대의 보관함 아이콘 → 보통 칸으로 돌아가고 탭 막대가 다시 보임
    private func leaveDense() {
        let anchor = collectionView.indexPathsForVisibleItems.sorted().dropFirst(collectionView.indexPathsForVisibleItems.count / 2).first
            .map { list[flatIndex($0)].localIdentifier }
        setLibraryMode(.all)
        setColumnsDirectly(7)
        if let anchor { reveal(assetID: anchor) }
        updateModeBar()
    }

    private func setColumnsDirectly(_ value: Int) {
        guard levels.contains(value), value != columns else { return }
        finishPinchNow()
        columns = value
        gridLayout.columns = value
        Prefs.gridColumns = value
        updateThumbSize()
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        alignShortContentToBottom()
        scrollToLatest()
        updateYearChip()
    }

    /// 사진이 한 화면보다 적으면 순정처럼 최신이 있는 아래쪽에 붙임 (제목 밑에 가리지 않게)
    private func alignShortContentToBottom() {
        guard isRoot, !newestFirst, collectionView != nil else { return }
        collectionView.layoutIfNeeded()
        let visible = collectionView.bounds.height - collectionView.contentInset.bottom
        let top = max(0, visible - collectionView.contentSize.height)
        if abs(collectionView.contentInset.top - top) > 0.5 {
            collectionView.contentInset.top = top
            if top > 0 { collectionView.contentOffset.y = -top }
        }
    }

    private func layoutTitleOverlay() {
        let barFrame = navigationController.map { view.convert($0.navigationBar.frame, from: $0.view) }
            ?? CGRect(x: 0, y: view.safeAreaInsets.top, width: view.bounds.width, height: 54)
        titleOverlay.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: barFrame.maxY + 46)
        titleOverlay.titleCenterY = barFrame.midY
        titleOverlay.leading = view.safeAreaInsets.left + 20
        updateTitleOverlay()
    }

    /// 순정처럼 제목·그라데이션은 사진이 밑에 있을 때만 (선택 중에는 위 막대 제목으로)
    private func updateTitleOverlay() {
        guard isRoot, isViewLoaded, collectionView != nil else { return }
        // 순정 iOS 27: 선택 중에도 제목·부제는 그대로
        titleOverlay.subtitle = overlaySubtitle()
        let dark = !list.isEmpty
        if titleOverlay.dark != dark {
            titleOverlay.dark = dark
            setNeedsStatusBarAppearanceUpdate()
        }
    }

    /// 맨 끝(최신 쪽)에 있으면 개수, 아니면 제목 밑에 보이는 사진의 날짜
    private func overlaySubtitle() -> String? {
        guard !list.isEmpty else { return nil }
        let latestAtBottom = !newestFirst
        let offset = collectionView.contentOffset.y
        let inset = collectionView.adjustedContentInset
        let maxOffset = max(-inset.top, collectionView.contentSize.height + inset.bottom - collectionView.bounds.height)
        let atLatest = latestAtBottom ? offset >= maxOffset - 8 : offset <= -inset.top + 8
        if atLatest {
            return "\(list.count.formatted())개의 항목"
        }
        // 순정 iOS 27: 제목 밑 첫 줄에 여러 날이 섞이면 "11월 17일~19일"처럼 범위로
        let y = offset + inset.top + 4
        let width = collectionView.bounds.width
        var dates: [Date] = []
        for x in stride(from: CGFloat(4), to: width, by: max(8, width / CGFloat(max(1, columns)))) {
            if let path = collectionView.indexPathForItem(at: CGPoint(x: x, y: y)),
               let date = list[flatIndex(path)].creationDate { dates.append(date) }
        }
        if dates.isEmpty, let path = collectionView.indexPathsForVisibleItems.min(),
           let date = list[flatIndex(path)].creationDate { dates.append(date) }
        guard let first = dates.min(), let last = dates.max() else { return nil }
        return LibraryTitleOverlay.rangeText(first, last)
    }

    /// 최신 사진이 있는 끝으로 (오래된 순이면 맨 아래)
    private func scrollToLatest() {
        scrollToLatest(animated: false)
    }

    func scrollToLatest(animated: Bool) {
        guard isViewLoaded, collectionView != nil, !list.isEmpty else { return }
        collectionView.layoutIfNeeded()
        let inset = collectionView.adjustedContentInset
        let y = newestFirst ? -inset.top
            : max(-inset.top, collectionView.contentSize.height + inset.bottom - collectionView.bounds.height)
        collectionView.setContentOffset(CGPoint(x: collectionView.contentOffset.x, y: y), animated: animated)
        updateTitleOverlay()
    }

    private var isAtLatest: Bool {
        guard collectionView != nil, !list.isEmpty else { return true }
        let inset = collectionView.adjustedContentInset
        let offset = collectionView.contentOffset.y
        if newestFirst { return offset <= -inset.top + 8 }
        let maxOffset = max(-inset.top, collectionView.contentSize.height + inset.bottom - collectionView.bounds.height)
        return offset >= maxOffset - 8
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        // 사진 위 어두운 그라데이션에서는 흰 글자 (순정처럼)
        isRoot && titleOverlay.dark ? .lightContent : .default
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        warmDenseCache()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === collectionView, !decelerate else { return }
        warmDenseCache()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard isRoot, scrollView === collectionView else { return }
        updateModeBar()
        updateYearChip()
        let text = overlaySubtitle()
        if text != titleOverlay.subtitle { titleOverlay.subtitle = text }
    }

    /// 썸네일을 받을 크기: 지금 칸 수의 한 칸 (1칸이면 화면 너비). 칸 수가 정해질 때만 바뀜 (손가락을 움직이는 동안은 그대로)
    private func updateThumbSize() {
        // 촘촘한 칸(1000칸 넘게 보임)에서는 셀 미리 만들기를 끔: 안 보이는 칸을 1000개 더 만들고 그 그림까지 받느라 느려짐
        if collectionView != nil { collectionView.isPrefetchingEnabled = columns < PhotoGridLayout.denseColumns }
        let scale = traitCollection.displayScale
        // 촘촘한 칸은 한 변 16pt 남짓이라 작게 (큰 그림을 받아 줄이는 일을 줄임)
        thumbSize = columns >= PhotoGridLayout.denseColumns ? denseThumbSize
            : CGSize(width: max(40, view.bounds.width / CGFloat(columns)) * scale, height: max(40, view.bounds.width / CGFloat(columns)) * scale)
        warmDenseCache()
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
        DispatchQueue.main.async { [weak self] in self?.runActionAfterOpening() }
        // 전환을 취소하고 돌아왔을 때도 다시 막음
        blockSwipeAnywhereIfAlbum()
        // 열림이 끝났거나 닫기를 취소하고 돌아옴: 숨긴 것이 남지 않게
        if zoomCollapsed { setZoomCollapsed(false) }
        // 선택 중이 아니면 아래 막대는 숨기고 탭 막대는 보이게 (어긋난 채로 남지 않게. 맞으면 건드리지 않음)
        if !selecting { navigationController?.ensureBrowsingBars(of: self) }
        updateModeBar()
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

    /// 예전엔 앨범 화면에서 '어디서나 밀어서 뒤로'를 껐지만, 순정 iOS 27 은 앨범 한가운데를 옆으로 쓸어도 뒤로 감.
    /// 그래서 이제 막지 않음 (선택 중·보기 화면이 막는 것은 따로 그대로)
    private func blockSwipeAnywhereIfAlbum() {
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
        // 순정 iOS 27: 앨범 어디서든 오른쪽으로 쓸면 닫힘 (가장자리만이 아님)
        if velocity.x > 0 && velocity.x > abs(velocity.y) { return true }
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
        if gestureRecognizer === dragSelectRecognizer, let pan = gestureRecognizer as? UIPanGestureRecognizer {
            // 고르는 중, 옆으로 먼저 움직일 때만 (위아래는 스크롤)
            guard selecting, !transitioning else { return false }
            let velocity = pan.velocity(in: collectionView)
            guard abs(velocity.x) > abs(velocity.y) else { return false }
            let point = pan.location(in: collectionView)
            guard let path = collectionView.indexPathForItem(at: point) else { return false }
            return flatIndex(path) < list.count
        }
        guard gestureRecognizer === pinchRecognizer else { return true }
        // 선택 중에는 칸 수를 바꾸지 않음 (두 손가락으로 끌어 고르기·길게 누르기와 부딪히지 않게). 화면 전환 중에도
        return !selecting && !transitioning && !sections.isEmpty && collectionView != nil
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // 스크롤이 먼저 잡혀도 벌리기가 시작될 수 있게. 벌리기가 시작되면 스크롤을 끔 (beginPinch)
        gestureRecognizer === pinchRecognizer && otherGestureRecognizer === collectionView?.panGestureRecognizer
    }

    @objc private func dragSelected(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard let path = collectionView.indexPathForItem(at: gesture.location(in: collectionView)) else { return }
            let start = flatIndex(path)
            let before = Set((collectionView.indexPathsForSelectedItems ?? []).map(flatIndex))
            dragSelect = (start, !before.contains(start), before, start...start)
            applyDragSelect(to: start)
        case .changed:
            updateDragSelect(gesture)
            // 위아래 끝 가까이면 저절로 스크롤
            let y = gesture.location(in: view).y
            let top = view.safeAreaInsets.top + 60
            let bottom = view.bounds.height - view.safeAreaInsets.bottom - 80
            dragScrollSpeed = y < top ? -(top - y) * 0.5 : (y > bottom ? (y - bottom) * 0.5 : 0)
            if dragScrollSpeed != 0, dragScrollLink == nil {
                let link = CADisplayLink(target: self, selector: #selector(dragAutoScroll))
                link.add(to: .main, forMode: .common)
                dragScrollLink = link
            } else if dragScrollSpeed == 0 {
                dragScrollLink?.invalidate()
                dragScrollLink = nil
            }
        default:
            dragScrollLink?.invalidate()
            dragScrollLink = nil
            dragSelect = nil
            updateChrome()
        }
    }

    @objc private func dragAutoScroll() {
        guard let gesture = dragSelectRecognizer, dragSelect != nil else { return }
        let inset = collectionView.adjustedContentInset
        let minY = -inset.top
        let maxY = max(minY, collectionView.contentSize.height + inset.bottom - collectionView.bounds.height)
        let y = min(max(minY, collectionView.contentOffset.y + dragScrollSpeed), maxY)
        collectionView.contentOffset.y = y
        updateDragSelect(gesture)
    }

    private func updateDragSelect(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: collectionView)
        guard let path = collectionView.indexPathForItem(at: point) ?? nearestItem(to: point) else { return }
        let flat = flatIndex(path)
        guard flat < list.count else { return }
        applyDragSelect(to: flat)
    }

    private func applyDragSelect(to flat: Int) {
        guard var state = dragSelect else { return }
        let range = min(state.start, flat)...max(state.start, flat)
        let touched = min(range.lowerBound, state.range.lowerBound)...max(range.upperBound, state.range.upperBound)
        for index in touched {
            let want = range.contains(index) ? state.selecting : state.before.contains(index)
            guard let path = indexPath(forFlat: index) else { continue }
            let has = collectionView.cellForItem(at: path)?.isSelected
                ?? (collectionView.indexPathsForSelectedItems?.contains(path) ?? false)
            if want && !has {
                collectionView.selectItem(at: path, animated: false, scrollPosition: [])
            } else if !want && has {
                collectionView.deselectItem(at: path, animated: false)
            }
        }
        state.range = range
        dragSelect = state
        updateChrome()
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
        if let path = collectionView.indexPathForItem(at: point), !isAddTile(path) { return path }
        var best: (path: IndexPath, distance: CGFloat)?
        for path in collectionView.indexPathsForVisibleItems where !isAddTile(path) {
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
            if newColumns != PhotoGridLayout.denseColumns {
                Thumbs.manager.stopCachingImagesForAllAssets()
                warmedAround = nil
            }
            DenseThumbs.shared.cancelWarm()
            updateThumbSize()
            // 칸이 커졌으면 보이는 칸만 더 큰 썸네일로 (작아졌으면 지금 그림으로 충분)
            if grew { reloadVisibleThumbnails() }
            alignShortContentToBottom()
            updateModeBar()
            updateYearChip()
        }
        // 칸 수가 그대로여도 (취소) 미뤄 둔 막대 상태를 맞춤
        updateModeBar()
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

    /// 돌릴 때: 최신 끝에 있었으면 끝에 그대로, 아니면 화면 맨 위 사진이 그대로 맨 위에 (순정)
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard isViewLoaded, collectionView != nil, !sections.isEmpty else { return }
        finishPinchNow()
        let wasAtLatest = isAtLatest
        let topItem = collectionView.indexPathsForVisibleItems
            .compactMap { path in gridLayout.layoutAttributesForItem(at: path).map { (path, $0.frame.minY) } }
            .filter { $0.1 >= collectionView.contentOffset.y + collectionView.adjustedContentInset.top - 1 }
            .min { $0.1 < $1.1 }?.0
        coordinator.animate(alongsideTransition: { [weak self] _ in
            guard let self else { return }
            self.collectionView.layoutIfNeeded()
            if wasAtLatest {
                self.scrollToLatest()
            } else if let topItem, let frame = self.gridLayout.layoutAttributesForItem(at: topItem)?.frame {
                let inset = self.collectionView.adjustedContentInset
                let maxOffset = max(-inset.top, self.collectionView.contentSize.height + inset.bottom - self.collectionView.bounds.height)
                self.collectionView.contentOffset.y = min(max(-inset.top, frame.minY - inset.top), maxOffset)
            }
        }, completion: { [weak self] _ in
            guard let self, wasAtLatest else { return }
            self.scrollToLatest()
            self.updateModeBar()
        })
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        guard isViewLoaded, collectionView != nil else { return }
        let wasAtLatest = isRoot && !needsScrollToLatest && isAtLatest
        collectionView.contentInset.bottom = view.safeAreaInsets.bottom
        collectionView.verticalScrollIndicatorInsets = UIEdgeInsets(top: view.safeAreaInsets.top, left: 0,
                                                                    bottom: view.safeAreaInsets.bottom, right: 0)
        if wasAtLatest { scrollToLatest() }
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
        let new = provisional ? AssetList.empty : arranged(Library.shared.list(for: listID, newestFirst: newestFirst))
        if !force && new.version == list.version {
            list = new   // 들어 있는 사진·순서는 같고, 즐겨찾기·편집 상태가 바뀐 새 값으로
            refreshHero()   // 이름·표지가 바뀌었을 수 있음
            return
        }

        // 고른 사진은 ID 로 기억했다가 새 목록에서 찾아 다시 고름 (목록 전체를 훑지 않음)
        let keep = selectedAssets().map(\.localIdentifier)
        // 최신 쪽 끝을 보고 있었으면 새 사진이 들어와도 끝에 머묾 (순정처럼)
        let stayAtLatest = isRoot && !needsScrollToLatest && isAtLatest
        list = new
        buildSections()
        gridLayout.setSections(layoutCounts)
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
        if stayAtLatest { scrollToLatest() }
        updateChrome()
    }

    /// 날짜별 묶음. 앨범 안은 한 덩어리. 보관함·미분류는 앞의 몇천 장만 바로 날짜로 나누고(메인 줄에서 전부 읽지 않게)
    /// 나머지는 한 묶음으로 둔 뒤, 전체 묶음을 Library 가 뒤에서 계산해 오면 바꿔 넣음
    private func buildSections() {
        // 날짜로 나누지 않고 한 덩어리 (앨범 안, 그리고 순정 iOS 27 처럼 보관함·미분류도)
        // 내 앨범은 비어 있어도 표지와 '+' 칸이 보이게 한 덩어리를 둠
        sections = list.isEmpty && !showsAddTile ? [] : [(day: Date(), range: 0..<list.count)]
    }

    // MARK: - 내 앨범 끝의 '+' 칸 (순정 iOS 27: 누르면 사진을 골라 이 앨범에 넣음)

    /// 사진 앱에서 만든 내 앨범이고, 고른 것만 보는 중이 아닐 때
    private var showsAddTile: Bool {
        // 순정처럼 선택 중에는 숨김
        !isRoot && folder.albumID != nil && listBeforeShowingSelected == nil && !selecting
    }

    /// 배치에 넘기는 칸 수 (마지막 묶음에 '+' 칸 하나 더)
    private var layoutCounts: [Int] {
        var counts = sections.map { $0.range.count }
        if showsAddTile, !counts.isEmpty { counts[counts.count - 1] += 1 }
        return counts
    }

    private func isAddTile(_ indexPath: IndexPath) -> Bool {
        showsAddTile && indexPath.section == sections.count - 1 && indexPath.item == sections[indexPath.section].range.count
    }

    /// 앨범 목록의 꾹 누른 메뉴에서 고른 것 (열린 뒤 한 번 실행)
    enum OpenAction { case addPhotos, slideshow }
    var actionAfterOpening: OpenAction?

    private func runActionAfterOpening(tries: Int = 0) {
        guard let action = actionAfterOpening else { return }
        // 확대 전환이 다 끝나고 화면에 올라온 뒤에 띄움 (전환 중에는 띄우는 게 무시됨)
        if (transitionCoordinator != nil || view.window == nil || presentedViewController != nil
            || navigationController?.transitionCoordinator != nil), tries < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.runActionAfterOpening(tries: tries + 1) }
            return
        }
        actionAfterOpening = nil
        switch action {
        case .addPhotos: presentAddPicker()
        case .slideshow: startSlideshow()
        }
    }

    private func presentAddPicker() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 0
        config.selection = .ordered
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    /// 최신순인지. 순정 iOS 27 처럼 보관함·미분류·앨범 모두 오래된 순(최신이 맨 아래)이 기본, 정렬 메뉴로 바꿈
    private var newestFirst: Bool {
        sortMode == .newest
    }

    /// 순정 iOS 27 정렬: 내 앨범은 '사용자 설정 순서'(앨범에 넣은 순서)가 기본, 나머지는 오래된 항목 순
    private var sortMode: GridSort {
        if let raw = Prefs.gridSorts[folder.id], let mode = GridSort(rawValue: raw),
           mode != .custom || folder.albumID != nil { return mode }
        if Prefs.newestFirstAlbums.contains(folder.id) { return .newest }
        return !isRoot && folder.albumID != nil ? .custom : .oldest
    }

    /// 사용자 설정 순서·필터를 반영한 목록
    private func arranged(_ base: AssetList) -> AssetList {
        var result = base
        if sortMode == .custom, let id = folder.albumID, let album = Library.shared.album(id: id) {
            // 사진 앱 앨범의 순서 그대로 (정렬 없이 읽으면 앨범 순서)
            let fetched = PHAsset.fetchAssets(in: album, options: nil)
            var array: [PHAsset] = []
            array.reserveCapacity(fetched.count)
            fetched.enumerateObjects { asset, _, _ in array.append(asset) }
            result = AssetList.make(array)
        }
        // 보관함의 즐겨찾기·비디오는 listID 로 이미 걸러짐. 나머지 필터는 여기서
        let needsFilter: Bool
        switch libraryFilter {
        case .all: needsFilter = false
        case .notInAlbum: needsFilter = folder.id != "all"
        case .favorites, .videos: needsFilter = folder.id != "all"
        case .photos, .screenshots, .live: needsFilter = true
        }
        // 보기 옵션: 스크린샷을 보관함에서 빼기 (순정 보기 옵션 › 보기: 스크린샷)
        let hideScreens = folder.id == "all" && !Prefs.libraryShowsScreenshots && libraryFilter != .screenshots
        guard needsFilter || hideScreens else { return result }
        let filter = libraryFilter
        return AssetList.make(result.array().filter {
            (!needsFilter || filter.matches($0)) && !(hideScreens && $0.mediaSubtypes.contains(.photoScreenshot))
        })
    }

    /// 실제로 읽는 목록 (보관함은 필터에 따라 즐겨찾기·비디오 목록으로)
    private var listID: String {
        guard folder.id == "all" else { return folder.id }
        switch libraryFilter {
        case .favorites: return "favorites"
        case .videos: return "videos"
        case .notInAlbum: return "unsorted"
        default: return "all"
        }
    }

    /// 앨범 카드에서 열리고 닫히는 확대 전환이 맞출 자리: 화면 맨 위의 정사각형 (이 화면 좌표).
    /// 표지의 스크롤 위치를 따라가지 않음 — 따라가면 위로 넘겨 둔 격자에서는 화면 밖 자리가 되고,
    /// 맨 위에서 당겨 늘어나는(고무줄) 동안에는 매 순간 자리가 바뀌어 전환 끝에서 튐.
    /// 맨 위에 있을 때는 표지와 정확히 같은 자리라 열릴 때는 그대로 표지에 맞음
    func zoomCoverRect() -> CGRect {
        var size = isViewLoaded ? view.bounds.size : .zero
        if size.width <= 0 { size = navigationController?.view.bounds.size ?? .zero }
        let cover = (size.width * PhotoGridLayout.coverRatio).rounded()
        let height = min(cover, size.height > 0 ? size.height : cover)
        return CGRect(x: 0, y: 0, width: size.width, height: height)
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
        sections[section].range.count + (showsAddTile && section == sections.count - 1 ? 1 : 0)
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if isAddTile(indexPath) {
            return collectionView.dequeueReusableCell(withReuseIdentifier: AddTileCell.reuse, for: indexPath)
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AssetCell.reuse, for: indexPath) as! AssetCell
        let asset = assetAt(indexPath)
        let id = asset.localIdentifier
        if cell.assetID != id { cell.imageView.image = nil }
        cell.assetID = id
        cell.selecting = selecting
        applyZoomCollapse(to: cell)
        // 끝까지 오므린 보관함(25칸)은 칸이 1000개 넘게 보여서 하트·길이는 그리지 않음 (순정도 안 보임)
        let dense = isDense
        cell.setDuration(!dense && asset.mediaType == .video ? asset.duration : nil)
        cell.setFavorite(!dense && asset.isFavorite)
        cell.aspectFit = Prefs.aspectGrid && columns > 1
        loadThumbnail(into: cell, asset: asset)
        return cell
    }

    /// 지금 칸 수에 맞는 크기로 썸네일을 받음 (받는 동안은 지금 그림을 그대로 둠)
    private func loadThumbnail(into cell: AssetCell, asset: PHAsset) {
        let id = asset.localIdentifier
        if isDense, let ready = DenseThumbs.shared.image(for: id) {
            if cell.requestID != PHInvalidImageRequestID {
                Thumbs.manager.cancelImageRequest(cell.requestID)
                cell.requestID = PHInvalidImageRequestID
            }
            cell.imageView.image = ready
            return
        }
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
            // 촘촘한 칸에서 빼 둔 하트·길이를 다시
            cell.setDuration(asset.mediaType == .video ? asset.duration : nil)
            cell.setFavorite(asset.isFavorite)
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
        hero.countLabel.text = "\(list.count.formatted())개의 항목"
        hero.playButton.isHidden = list.isEmpty || selecting
        hero.onPlay = { [weak self] in self?.startSlideshow() }
        // 사진 앱 앨범은 그 앨범의 대표 사진, 아니면 가장 최근 사진 (앨범 카드와 같은 사진)
        guard let cover = snapshot.cover(folder.id) ?? list.last else { return }
        let id = cover.localIdentifier
        guard hero.assetID != id else { return }
        if hero.requestID != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(hero.requestID)
        }
        hero.assetID = id
        let scale = traitCollection.displayScale
        let size = CGSize(width: view.bounds.width * scale, height: view.bounds.width * PhotoGridLayout.coverRatio * scale)
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

    /// 끝까지 오므린 칸의 썸네일 크기 (미리 받아 두는 것과 똑같아야 캐시에서 바로 나옴)
    private var denseThumbSize: CGSize {
        let side = 20 * traitCollection.displayScale
        return CGSize(width: side, height: side)
    }

    /// 끝까지 오므리기 바로 전 칸 수(7칸)에 머물면, 오므렸을 때 보일 근처 사진들의 작은 썸네일을 미리 받아 둠.
    /// 오므리는 순간 1000장 넘게 한꺼번에 요청하느라 칸이 늦게 차던 것을 줄임 (순정은 0.9초 안에 다 참)
    private var warmedAround: Int?
    private func warmDenseCache() {
        guard folder.id == "all", collectionView != nil, levels.count >= 2, !list.isEmpty,
              columns == levels[levels.count - 2], levels.last == PhotoGridLayout.denseColumns else { return }
        let paths = collectionView.indexPathsForVisibleItems
        guard let center = paths.map(flatIndex).sorted().dropFirst(paths.count / 2).first else { return }
        // 조금 움직인 정도면 다시 하지 않음
        if let last = warmedAround, abs(last - center) < 300 { return }
        warmedAround = center
        DenseThumbs.shared.warm(warmAssets(around: center), size: denseThumbSize)
    }

    private func warmAssets(around center: Int) -> [PHAsset] {
        // 촘촘한 화면 한 장(약 25 × 50칸)보다 조금 넓게. 가까운 것부터
        let lower = max(0, center - 900), upper = min(list.count, center + 900)
        guard lower < upper else { return [] }
        return (lower..<upper).sorted { abs($0 - center) < abs($1 - center) }.map { list[$0] }
    }

    /// 보관함을 끝까지 오므린 상태 (칸 수를 바꾸는 중에 그 배치를 그리는 때도)
    private var isDense: Bool {
        (gridLayout.zoom?.columns ?? columns) >= PhotoGridLayout.denseColumns
    }

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        // 촘촘할 때는 미리 받아 두지 않음 (한 번에 수백 장을 캐시에 올리느라 오히려 느려짐)
        guard !isDense else { return }
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

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        // '+' 칸은 고를 수 없고, 선택 중이 아닐 때 누르면 사진 고르기
        if isAddTile(indexPath) {
            if !selecting, !isPinching { presentAddPicker() }
            return false
        }
        return true
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if selecting {
            updateChrome()
        } else {
            collectionView.deselectItem(at: indexPath, animated: false)
            // 칸 수를 바꾸는 중에는 열지 않음
            guard !isPinching else { return }
            openViewer(flat: flatIndex(indexPath))
        }
    }

    private func openViewer(flat: Int) {
        guard flat >= 0, flat < list.count else { return }
        do {
            let viewer = ViewerViewController(list: list, index: flat, folderID: folder.id,
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
        false   // 이 배치에서는 시스템 것이 안 잡혀서 직접 만든 끌어 고르기(dragSelected)를 씀. 길게 누르거나 '선택'으로 들어온 뒤에만. 아니면 두 손가락 벌리기가 선택으로 잡힘
    }

    func collectionView(_ collectionView: UICollectionView, didBeginMultipleSelectionInteractionAt indexPath: IndexPath) {
        if !selecting { setSelecting(true) }
    }

    func collectionViewDidEndMultipleSelectionInteraction(_ collectionView: UICollectionView) {
        updateChrome()
    }

    // MARK: - 길게 누르기 (순정 iOS 27: 사진 미리보기 + 메뉴)

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                        point: CGPoint) -> UIContextMenuConfiguration? {
        // 선택 중에는 끌어서 여러 장 고르기가 우선
        guard !selecting, !isPinching, let path = indexPaths.first, path.section < sections.count,
              path.item < sections[path.section].range.count else { return nil }
        let flat = flatIndex(path)
        let asset = list[flat]
        return UIContextMenuConfiguration(identifier: flat as NSNumber, previewProvider: {
            AssetPreviewController(asset: asset)
        }, actionProvider: { [weak self] _ in
            self?.makeAssetMenu([asset], single: true)
        })
    }

    /// 미리보기를 누르면 그 사진을 엶
    func collectionView(_ collectionView: UICollectionView, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
                        animator: UIContextMenuInteractionCommitAnimating) {
        guard let flat = (configuration.identifier as? NSNumber)?.intValue, flat < list.count else { return }
        animator.preferredCommitStyle = .pop
        animator.addCompletion { [weak self] in
            self?.openViewer(flat: flat)
        }
    }

    /// 사진 메뉴 (길게 누르기 · 선택 중 ⋯ 공용). single 이면 공유·정보 조정·삭제까지 (순정 길게 누르기 메뉴)
    private func makeAssetMenu(_ assets: [PHAsset], single: Bool) -> UIMenu {
        let top = UIMenu(options: .displayInline, preferredElementSize: .medium, children: [
            UIAction(title: "복사", image: UIImage(systemName: "doc.on.doc.fill")) { [weak self] _ in self?.copyAssets(assets) },
            UIAction(title: "복제", image: UIImage(systemName: "plus.square.fill.on.square.fill")) { [weak self] _ in self?.duplicateAssets(assets) },
            UIAction(title: "가리기", image: UIImage(systemName: "eye.slash.fill")) { [weak self] _ in self?.hideAssets(assets) },
        ])
        let allFavorite = !assets.isEmpty && assets.allSatisfy(\.isFavorite)
        var middle: [UIMenuElement] = []
        if single {
            middle.append(UIAction(title: "공유", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                guard let self else { return }
                Sharer.share(assets, from: self, barButtonItem: nil) { [weak self] in self?.send(assets, copy: true) }
            })
        }
        middle.append(UIAction(title: allFavorite ? "즐겨찾기 해제" : "즐겨찾기",
                               image: UIImage(systemName: allFavorite ? "heart.slash" : "heart")) { [weak self] _ in
            self?.favoriteAssets(assets, !allFavorite)
        })
        var addActions: [UIAction] = [
            UIAction(title: "앨범에 추가", image: UIImage(systemName: "rectangle.stack.badge.plus")) { [weak self] _ in self?.send(assets, copy: true) },
            UIAction(title: "앨범으로 이동", image: UIImage(systemName: "folder")) { [weak self] _ in self?.send(assets, copy: false) },
        ]
        if folder.isUser {
            addActions.append(UIAction(title: "이 앨범에서 빼기", image: UIImage(systemName: "minus.circle")) { [weak self] _ in
                self?.removeFromAlbum(assets)
            })
        }
        var lower: [UIMenuElement] = [UIMenu(title: "추가 대상", image: UIImage(systemName: "photo.on.rectangle.angled"), children: addActions)]
        if single, let asset = assets.first, asset.canPerform(.properties) {
            lower.append(UIMenu(title: "정보 조정", image: UIImage(systemName: "info.circle"), children: [
                UIAction(title: "날짜 및 시간 조정", image: UIImage(systemName: "calendar.badge.clock")) { [weak self] _ in self?.adjustDate(asset) },
                UIAction(title: "위치 조정", image: UIImage(systemName: "mappin.circle")) { [weak self] _ in self?.adjustLocation(asset) },
            ]))
        }
        var children: [UIMenuElement] = [top, UIMenu(options: .displayInline, children: middle),
                                          UIMenu(options: .displayInline, children: lower)]
        if single {
            children.append(UIMenu(options: .displayInline, children: [
                UIAction(title: "삭제", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                    self?.deleteAssets(assets)
                },
            ]))
        } else {
            let allSelected = assets.count == list.count && !assets.isEmpty
            children.append(UIMenu(options: .displayInline, children: [
                UIAction(title: allSelected ? "전체 해제" : "전체 선택",
                         image: UIImage(systemName: allSelected ? "circle.dashed" : "checkmark.circle")) { [weak self] _ in
                    self?.toggleAll()
                },
            ]))
        }
        return UIMenu(children: children)
    }

    private func adjustDate(_ asset: PHAsset) {
        let sheet = DateAdjustViewController(date: asset.creationDate ?? Date())
        sheet.onSave = { [weak self] date in
            Library.shared.setCreationDate(asset, date) { ok in
                if !ok { self?.toast("날짜를 바꾸지 못했어요") }
            }
        }
        presentSheet(sheet)
    }

    private func adjustLocation(_ asset: PHAsset) {
        let sheet = LocationSearchViewController()
        sheet.onPick = { [weak self] location in
            Library.shared.setLocation(asset, location) { ok in
                if !ok { self?.toast("위치를 넣지 못했어요") }
            }
        }
        presentSheet(sheet)
    }

    private func presentSheet(_ root: UIViewController) {
        let nav = UINavigationController(rootViewController: root)
        if let presentation = nav.sheetPresentationController {
            presentation.detents = [.large()]
            presentation.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    private func setSelecting(_ on: Bool) {
        guard selecting != on else { return }
        finishPinchNow()
        if !on {
            for path in collectionView.indexPathsForSelectedItems ?? [] {
                collectionView.deselectItem(at: path, animated: false)
            }
            // 고른 것만 보던 중이면 전체로
            if listBeforeShowingSelected != nil {
                listBeforeShowingSelected = nil
                reloadFromLibrary(force: true)
            }
        }
        selecting = on
        if !isRoot, folder.albumID != nil {
            // '+' 칸이 생기거나 사라짐 (고른 사진은 다시 고름)
            let keep = on ? [] : selectedAssets().map(\.localIdentifier)
            buildSections()
            gridLayout.setSections(layoutCounts)
            collectionView.reloadData()
            for flat in list.indexes(ofIDs: keep) {
                if let path = indexPath(forFlat: flat) { collectionView.selectItem(at: path, animated: false, scrollPosition: []) }
            }
        }
        collectionView.isEditing = on
        dragSelectRecognizer?.isEnabled = on
        for cell in collectionView.visibleCells {
            (cell as? AssetCell)?.selecting = on
        }
        // 선택하는 동안은 아래 탭 막대 대신 선택 막대 (앨범 안에서도)
        if #available(iOS 18.0, *) {
            tabBarController?.setTabBarHidden(on, animated: true)
        }
        updateModeBar()
        // 옆으로 끌어 선택하는 동안 '밀어서 뒤로'가 잡히지 않게 (보기 화면·앨범 화면이 막는 것과는 따로 기억)
        navigationController?.setBackSwipe(blocked: on ? UINavigationController.BackSwipeBlock.all : nil, by: selectionSwipeToken)
        if on {
            toolbarItems = [shareItem, UIBarButtonItem.flexibleSpace(), showSelectedItem, UIBarButtonItem.flexibleSpace(), deleteItem]
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
            // 순정 iOS 27: 제목은 그대로 두고(보관함은 사진 위 제목), 오른쪽에 [정렬·필터 ⋯] [닫기 X]
            // 제목은 비움 (보관함은 사진 위 제목, 앨범은 표지의 이름이 그대로 보임)
            navigationItem.title = nil
            navigationItem.hidesBackButton = true
            if isRoot {
                navigationItem.leftBarButtonItem = nil
            } else {
                // 순정 앨범 화면: 왼쪽 위 "전체 선택" / "전체 해제"
                let allSelected = count == list.count && count > 0
                navigationItem.leftBarButtonItem = UIBarButtonItem(title: allSelected ? "전체 해제" : "전체 선택", style: .plain,
                                                                   target: self, action: #selector(toggleAll))
            }
            let close = UIBarButtonItem(image: UIImage(systemName: "xmark"), style: .plain, target: self, action: #selector(cancelSelecting))
            let more = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: makeMoreMenu())
            more.isEnabled = count > 0
            var right: [UIBarButtonItem] = [close, UIBarButtonItem.fixedSpace(8), more]
            if isRoot {
                right.append(UIBarButtonItem(image: UIImage(systemName: libraryFilter == .all ? "line.3.horizontal.decrease"
                                                             : "line.3.horizontal.decrease.circle.fill"), menu: makeLibraryMenu()))
            }
            navigationItem.rightBarButtonItems = right
            showSelectedItem.title = listBeforeShowingSelected != nil ? "모든 항목 표시"
                : (count == 0 ? "항목 선택" : "선택된 항목 표시(\(count)개)")
            showSelectedItem.isEnabled = count > 0 || listBeforeShowingSelected != nil
            for item in [shareItem, deleteItem] {
                item.isEnabled = count > 0
            }
        } else {
            // 앨범 안에서는 이름이 큰 대표 사진 위에, 보관함·미분류는 사진 위 제목에 있어서 위 막대 제목은 비움
            navigationItem.title = nil
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
                // 순정 iOS 27 보관함처럼: [정렬·필터] [선택]
                navigationItem.rightBarButtonItems = [
                    select, UIBarButtonItem.fixedSpace(8),
                    UIBarButtonItem(image: UIImage(systemName: libraryFilter == .all ? "line.3.horizontal.decrease"
                                                    : "line.3.horizontal.decrease.circle.fill"), menu: makeLibraryMenu()),
                ]
            } else {
                // 순정 앨범 화면처럼: [정렬 ⋯] [선택]
                // 순정 iOS 27 앨범 화면: 왼쪽부터 [⋯] [정렬] [선택], 각각 따로 떨어진 원
                let filterIcon = libraryFilter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill"
                var items: [UIBarButtonItem] = [select, UIBarButtonItem.fixedSpace(8),
                                                UIBarButtonItem(image: UIImage(systemName: filterIcon), menu: makeLibraryMenu())]
                if folder.isUser {
                    items.append(UIBarButtonItem.fixedSpace(8))
                    items.append(UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: makeAlbumMenu()))
                }
                navigationItem.rightBarButtonItems = items
            }
        }
        refreshVisibleHeaders()
        refreshHero()
        updateTitleOverlay()
        setNeedsStatusBarAppearanceUpdate()
    }

    /// 보관함·미분류의 정렬·필터 메뉴 (보관함에만 필터)
    /// 순정 iOS 27 의 정렬·필터 메뉴: "필터:" 모든 항목 · 즐겨찾기 · 미디어 유형 › / 정렬 ›(지금 순서가 부제)
    private func makeLibraryMenu() -> UIMenu {
        func action(_ filter: LibraryFilter, _ title: String, _ symbol: String) -> UIAction {
            UIAction(title: title, image: UIImage(systemName: symbol), state: libraryFilter == filter ? .on : .off) { [weak self] _ in
                self?.setLibraryFilter(filter)
            }
        }
        let media = UIMenu(title: "미디어 유형", image: UIImage(systemName: "photo.on.rectangle.angled"), children: [
            action(.photos, "사진", "photo"),
            action(.videos, "비디오", "video"),
            action(.live, "Live Photo", "livephoto"),
            action(.screenshots, "스크린샷", "camera.viewfinder"),
        ])
        var filterItems: [UIMenuElement] = [action(.all, "모든 항목", "square.grid.3x3"), action(.favorites, "즐겨찾기", "heart")]
        if folder.id == "all" {
            filterItems.append(action(.notInAlbum, "앨범에 포함되지 않음", "rectangle.stack.badge.minus"))
        }
        filterItems.append(media)
        let filters = UIMenu(title: "필터:", options: .displayInline, children: filterItems)
        // 순정 보기 옵션: 확대 · 축소 · 종횡비 격자 / 보기: 스크린샷
        var viewItems: [UIMenuElement] = [
            UIAction(title: "확대", image: UIImage(systemName: "plus.magnifyingglass"),
                     attributes: levels.first == columns ? .disabled : []) { [weak self] _ in self?.stepColumns(-1) },
            UIAction(title: "축소", image: UIImage(systemName: "minus.magnifyingglass"),
                     attributes: levels.last == columns ? .disabled : []) { [weak self] _ in self?.stepColumns(1) },
            UIAction(title: "종횡비 격자", image: UIImage(systemName: "aspectratio"),
                     state: Prefs.aspectGrid ? .on : .off) { [weak self] _ in
                Prefs.aspectGrid.toggle()
                self?.collectionView.reloadData()
                self?.updateChrome()
            },
        ]
        if folder.id == "all" {
            viewItems.append(UIMenu(title: "보기:", options: .displayInline, children: [
                UIAction(title: "스크린샷", image: UIImage(systemName: "camera.viewfinder"),
                         state: Prefs.libraryShowsScreenshots ? .on : .off) { [weak self] _ in
                    Prefs.libraryShowsScreenshots.toggle()
                    self?.reloadFromLibrary(force: true)
                    self?.updateChrome()
                },
            ]))
        }
        let viewOptions = UIMenu(title: "보기 옵션", children: viewItems)
        return UIMenu(children: [filters, UIMenu(options: .displayInline, children: [makeSortMenu(), viewOptions])])
    }

    /// 보기 옵션의 확대(-1) · 축소(+1): 칸 수 한 단계
    private func stepColumns(_ step: Int) {
        guard let index = levels.firstIndex(of: columns), levels.indices.contains(index + step) else { return }
        setColumnsDirectly(levels[index + step])
        updateModeBar()
        updateChrome()
    }

    private func setLibraryFilter(_ filter: LibraryFilter) {
        guard filter != libraryFilter else { return }
        libraryFilter = filter
        needsScrollToLatest = true
        reloadFromLibrary(force: true)
        view.setNeedsLayout()
        updateChrome()
    }

    // MARK: - 앨범 화면의 위 버튼 (정렬 · ⋯)

    private func makeSortMenu() -> UIMenu {
        let mode = sortMode
        var actions = [
            UIAction(title: "오래된 항목 순으로", image: UIImage(systemName: "clock.arrow.circlepath"),
                     state: mode == .oldest ? .on : .off) { [weak self] _ in self?.setSort(.oldest) },
            UIAction(title: "최신 항목 순", image: UIImage(systemName: "clock"),
                     state: mode == .newest ? .on : .off) { [weak self] _ in self?.setSort(.newest) },
        ]
        if !isRoot, folder.albumID != nil {
            actions.append(UIAction(title: "사용자 설정 순서", image: UIImage(systemName: "person"),
                                    state: mode == .custom ? .on : .off) { [weak self] _ in self?.setSort(.custom) })
        }
        let menu = UIMenu(title: "정렬", image: nil, children: actions)
        menu.subtitle = mode == .custom ? "사용자 설정 순서" : (mode == .newest ? "최신 항목 순" : "오래된 항목 순")
        return menu
    }

    private func setSort(_ mode: GridSort) {
        var sorts = Prefs.gridSorts
        sorts[folder.id] = mode.rawValue
        Prefs.gridSorts = sorts
        var set = Prefs.newestFirstAlbums
        set.remove(folder.id)
        Prefs.newestFirstAlbums = set
        needsScrollToLatest = isRoot
        reloadFromLibrary(force: true)
        if isRoot { view.setNeedsLayout() }
        updateChrome()
    }

    /// 앨범 표지의 재생 버튼: 앨범 처음부터 슬라이드쇼
    private func startSlideshow() {
        guard !list.isEmpty else { return }
        let current = list
        let show = SlideshowViewController(count: current.count, start: 0) { index in
            index < current.count ? current[index] : nil
        }
        show.modalPresentationStyle = .fullScreen
        show.modalTransitionStyle = .crossDissolve
        present(show, animated: true)
    }

    /// 사진 앱 앨범에서 실제로 할 수 있는 것만: 이름 변경 · 앨범 삭제
    private func makeAlbumMenu() -> UIMenu {
        let id = folder.id
        let renameHandler: UIActionHandler = { [weak self] _ in
            guard let self else { return }
            let current = Library.shared.snapshot.nodes[id]?.title ?? self.folder.title
            self.promptText(title: "이름 변경", initial: current, placeholder: "이름", confirm: "저장") { name in
                Library.shared.rename(id, to: name)
            }
        }
        let delete = UIAction(title: "앨범 삭제", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
            // iOS 가 직접 묻는 확인창 하나만 (순정처럼 한 번)
            Library.shared.deleteCollection(id)
        }
        // 순정 iOS 27 앨범 ⋯ 메뉴: [표지·이름·장수(누르면 이름 변경)] / 사진 추가 · 지도 보기 · 슬라이드쇼 시작 / 앨범 삭제
        // 장수·표지가 바뀌므로 열 때마다 새로 만듦
        let header = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else { completion([]); return }
            let title = Library.shared.snapshot.nodes[id]?.title ?? self.folder.title
            let item = UIAction(title: title, subtitle: "\(self.list.count.formatted())개의 항목",
                                image: self.albumMenuThumbnail(), handler: renameHandler)
            completion([item])
        }
        let actions = UIMenu(options: .displayInline, children: [
            UIAction(title: "사진 추가", image: UIImage(systemName: "plus")) { [weak self] _ in self?.presentAddPicker() },
            UIAction(title: "지도 보기", image: UIImage(systemName: "map")) { [weak self] _ in self?.showAlbumMap() },
            UIAction(title: "슬라이드쇼 시작", image: UIImage(systemName: "play.rectangle")) { [weak self] _ in self?.startSlideshow() },
        ])
        return UIMenu(children: [UIMenu(options: .displayInline, children: [header]), actions,
                                 UIMenu(options: .displayInline, children: [delete])])
    }

    /// 메뉴 머리의 작은 표지 (표지 그림을 둥근 정사각형으로)
    private func albumMenuThumbnail() -> UIImage? {
        let kind = UICollectionView.elementKindSectionHeader
        let hero = collectionView.indexPathsForVisibleSupplementaryElements(ofKind: kind).lazy
            .compactMap { self.collectionView.supplementaryView(forElementKind: kind, at: $0) as? HeroHeaderView }.first
        guard let image = hero?.imageView.image else { return UIImage(systemName: "rectangle.stack") }
        let side: CGFloat = 40
        let format = UIGraphicsImageRendererFormat.default()
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side), cornerRadius: 8).addClip()
            let scale = max(side / image.size.width, side / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
        }.withRenderingMode(.alwaysOriginal)
    }

    /// 지도 보기: 앨범 사진의 위치를 지도에
    private func showAlbumMap() {
        let map = AssetMapViewController(assets: list.array(), title: Library.shared.snapshot.nodes[folder.id]?.title ?? folder.title)
        let nav = UINavigationController(rootViewController: map)
        present(nav, animated: true)
    }

    // MARK: - 아래 막대

    @objc private func shareSelected() {
        let assets = selectedAssets()
        Sharer.share(assets, from: self, barButtonItem: shareItem) { [weak self] in self?.send(assets, copy: true) }
    }

    /// 갤럭시의 '더보기': 앨범으로 이동 · 앨범으로 복사
    /// 순정 iOS 27 선택 중 ⋯ 메뉴: 위 줄(복사·복제·가리기) / 즐겨찾기 / 추가 대상 › / 전체 선택
    private func makeMoreMenu() -> UIMenu {
        makeAssetMenu(selectedAssets(), single: false)
    }

    @objc private func toggleShowSelected() {
        if let before = listBeforeShowingSelected {
            // 모든 항목으로 돌아감 (고른 것은 그대로)
            let keep = selectedAssets().map(\.localIdentifier)
            listBeforeShowingSelected = nil
            list = before
            reloadShown(keeping: keep)
            return
        }
        let chosen = selectedAssets()
        guard !chosen.isEmpty else { return }
        listBeforeShowingSelected = list
        list = AssetList.make(chosen)
        reloadShown(keeping: chosen.map(\.localIdentifier))
    }

    /// 지금 list 로 격자를 다시 그리고 keep 을 다시 고름
    private func reloadShown(keeping keep: [String]) {
        buildSections()
        gridLayout.setSections(layoutCounts)
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        for flat in list.indexes(ofIDs: keep) {
            if let path = indexPath(forFlat: flat) {
                collectionView.selectItem(at: path, animated: false, scrollPosition: [])
            }
        }
        scrollToLatest()
        updateChrome()
    }

    private func copyAssets(_ assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        var items: [[String: Any]] = []
        let group = DispatchGroup()
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .current
        for asset in assets where asset.mediaType == .image {
            group.enter()
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, _ in
                if let data { items.append([uti ?? "public.jpeg": data]) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            UIPasteboard.general.items = items
        }
    }

    private func duplicateAssets(_ assets: [PHAsset]) {
        setSelecting(false)
        for asset in assets {
            Library.shared.duplicate(asset) { [weak self] ok in
                if !ok { self?.toast("복제하지 못한 항목이 있어요") }
            }
        }
    }

    private func hideAssets(_ assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        Library.shared.setHidden(assets, true) { [weak self] ok in
            if ok { self?.setSelecting(false) }
        }
    }

    private func favoriteAssets(_ assets: [PHAsset], _ on: Bool) {
        for asset in assets {
            Library.shared.setFavorite(asset, on)
        }
        setSelecting(false)
    }

    private func send(_ assets: [PHAsset], copy: Bool) {
        Mover.present(from: self, assets: assets, sourceAlbumID: folder.albumID, copy: copy) { [weak self] ok in
            if ok { self?.setSelecting(false) }
        }
    }

    private func removeFromAlbum(_ list: [PHAsset]) {
        guard !list.isEmpty, let id = folder.albumID, let album = Library.shared.album(id: id) else { return }
        Library.shared.remove(list, from: album) { [weak self] ok in
            if ok {
                self?.setSelecting(false)
                self?.toast("\(list.count)장을 앨범에서 뺐어요. 사진은 그대로 있어요")
            }
        }
    }

    @objc private func deleteSelected() {
        deleteAssets(selectedAssets())
    }

    private func deleteAssets(_ list: [PHAsset]) {
        guard !list.isEmpty else { return }
        Library.shared.delete(list) { [weak self] ok in
            if ok { self?.setSelecting(false) }
        }
    }
}

// MARK: - 보관함 필터

enum LibraryFilter {
    case all, favorites, videos, photos, screenshots, live, notInAlbum

    func matches(_ asset: PHAsset) -> Bool {
        switch self {
        case .all, .notInAlbum: return true
        case .favorites: return asset.isFavorite
        case .videos: return asset.mediaType == .video
        case .photos: return asset.mediaType == .image
        case .screenshots: return asset.mediaSubtypes.contains(.photoScreenshot)
        case .live: return asset.mediaSubtypes.contains(.photoLive)
        }
    }
}

/// 격자 정렬 (순정 iOS 27: 오래된 항목 순 · 최신 항목 순 · 사용자 설정 순서(내 앨범만))
enum GridSort: String {
    case oldest, newest, custom
}

// MARK: - 보관함 위 제목 (순정 iOS 27: 사진 위 어두운 그라데이션 + 흰 큰 제목 + 날짜·개수)

final class LibraryTitleOverlay: UIView {
    /// 순정처럼 제목 뒤 사진이 흐려짐 (위는 많이, 아래로 갈수록 없어짐)
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let blurMask = CAGradientLayer()
    private let gradient = CAGradientLayer()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    var titleCenterY: CGFloat = 86 { didSet { setNeedsLayout() } }
    var leading: CGFloat = 20 { didSet { setNeedsLayout() } }

    var title: String? {
        get { titleLabel.text }
        set { titleLabel.text = newValue }
    }

    var subtitle: String? {
        get { subtitleLabel.text }
        set {
            subtitleLabel.text = newValue
            subtitleLabel.isHidden = newValue == nil
            // 글자 길이가 바뀌면 너비도 다시 (안 그러면 앞 글자 길이로 잘림)
            setNeedsLayout()
        }
    }

    /// 사진 위(어두운 그라데이션 + 흰 글자)인지, 빈 화면(검은 글자)인지
    var dark = true {
        didSet { applyStyle() }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일"
        return formatter
    }()

    static func dateText(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    /// 같은 날: 2026년 11월 18일 / 같은 달: 2026년 11월 17일~19일 / 같은 해: 2026년 10월 30일~11월 2일 / 그 밖: 2025년 12월~2026년 1월
    static func rangeText(_ first: Date, _ last: Date) -> String {
        let calendar = Calendar.current
        let a = calendar.dateComponents([.year, .month, .day], from: first)
        let b = calendar.dateComponents([.year, .month, .day], from: last)
        guard let ay = a.year, let am = a.month, let ad = a.day, let by = b.year, let bm = b.month, let bd = b.day else {
            return dateText(first)
        }
        if ay == by && am == bm && ad == bd { return "\(ay)년 \(am)월 \(ad)일" }
        if ay == by && am == bm { return "\(ay)년 \(am)월 \(ad)일~\(bd)일" }
        if ay == by { return "\(ay)년 \(am)월 \(ad)일~\(bm)월 \(bd)일" }
        return "\(ay)년 \(am)월~\(by)년 \(bm)월"
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        blurMask.colors = [UIColor.black.cgColor, UIColor.black.withAlphaComponent(0.6).cgColor, UIColor.clear.cgColor]
        blurMask.locations = [0, 0.5, 1]
        blur.layer.mask = blurMask
        addSubview(blur)
        layer.addSublayer(gradient)
        titleLabel.font = .systemFont(ofSize: 34, weight: .bold)
        titleLabel.adjustsFontForContentSizeCategory = false
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        applyStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func applyStyle() {
        gradient.isHidden = !dark
        blur.isHidden = !dark
        // 순정 iOS 27 보관함과 비교해 맞춘 진하기
        gradient.colors = [UIColor.black.withAlphaComponent(0.5).cgColor, UIColor.black.withAlphaComponent(0.28).cgColor,
                           UIColor.black.withAlphaComponent(0).cgColor]
        gradient.locations = [0, 0.55, 1]
        titleLabel.textColor = dark ? .white : .label
        subtitleLabel.textColor = dark ? .white : .secondaryLabel
        for label in [titleLabel, subtitleLabel] {
            label.layer.shadowColor = UIColor.black.cgColor
            label.layer.shadowOpacity = dark ? 0.25 : 0
            label.layer.shadowRadius = 6
            label.layer.shadowOffset = .zero
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        blur.frame = bounds
        blurMask.frame = blur.bounds
        CATransaction.commit()
        titleLabel.sizeToFit()
        subtitleLabel.sizeToFit()
        let maxWidth = bounds.width - leading - 140   // 오른쪽 버튼 자리는 비움
        titleLabel.frame = CGRect(x: leading, y: titleCenterY - titleLabel.bounds.height / 2,
                                  width: min(titleLabel.bounds.width, maxWidth), height: titleLabel.bounds.height)
        subtitleLabel.frame = CGRect(x: leading + 1, y: titleLabel.frame.maxY - 2,
                                     width: min(subtitleLabel.bounds.width, bounds.width - leading * 2),
                                     height: subtitleLabel.bounds.height)
    }
}

// MARK: - 길게 누를 때의 사진 미리보기 (사진 비율 그대로, 둥근 모서리)

final class AssetPreviewController: UIViewController {
    private let asset: PHAsset
    private let imageView = UIImageView()

    init(asset: PHAsset) {
        self.asset = asset
        super.init(nibName: nil, bundle: nil)
        let screen = UIScreen.main.bounds.size
        // 순정처럼 메뉴가 한 화면에 다 들어오게 (3:4 사진이 화면 높이의 절반 남짓)
        let maxWidth = screen.width - 48, maxHeight = screen.height * 0.46
        let ratio = asset.pixelWidth > 0 && asset.pixelHeight > 0
            ? CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight) : 1
        var size = CGSize(width: maxWidth, height: maxWidth / ratio)
        if size.height > maxHeight { size = CGSize(width: maxHeight * ratio, height: maxHeight) }
        preferredContentSize = size
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.frame = view.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(imageView)
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        let scale = UIScreen.main.scale
        let target = CGSize(width: preferredContentSize.width * scale, height: preferredContentSize.height * scale)
        PHImageManager.default().requestImage(for: asset, targetSize: target, contentMode: .aspectFill, options: options) { [weak self] image, _ in
            if let image { self?.imageView.image = image }
        }
    }
}

// MARK: - '+' 칸 사진 고르기

extension GridViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        let ids = results.compactMap(\.assetIdentifier)
        guard !ids.isEmpty, let albumID = folder.albumID, let album = Library.shared.album(id: albumID) else { return }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [PHAsset] = []
        fetched.enumerateObjects { asset, _, _ in assets.append(asset) }
        guard !assets.isEmpty else { return }
        Library.shared.move(assets, to: album, from: nil) { [weak self] ok in
            self?.toast(ok ? "\(assets.count)개 항목을 추가했어요" : "추가하지 못했어요")
        }
    }
}

/// 내 앨범 끝의 '+' 칸 (순정처럼 옅은 회색 바탕에 파란 +)
final class AddTileCell: UICollectionViewCell {
    static let reuse = "AddTileCell"

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemBackground
        let plus = UIImageView(image: UIImage(systemName: "plus",
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)))
        plus.tintColor = .systemBlue
        plus.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(plus)
        NSLayoutConstraint.activate([
            plus.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            plus.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        isAccessibilityElement = true
        accessibilityLabel = "사진 추가"
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { contentView.alpha = isHighlighted ? 0.6 : 1 }
    }
}

// MARK: - 앨범 지도 (위치가 있는 사진을 지도에 핀으로)

final class AssetMapViewController: UIViewController {
    private let assets: [PHAsset]
    private let mapView = MKMapView()

    init(assets: [PHAsset], title: String) {
        self.assets = assets.filter { $0.location != nil }
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        mapView.frame = view.bounds
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(mapView)
        let pins = assets.compactMap { asset -> MKPointAnnotation? in
            guard let location = asset.location else { return nil }
            let pin = MKPointAnnotation()
            pin.coordinate = location.coordinate
            return pin
        }
        mapView.addAnnotations(pins)
        if pins.isEmpty {
            let label = UILabel()
            label.text = "위치 정보가 있는 사진이 없어요"
            label.textColor = .secondaryLabel
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            ])
        } else {
            mapView.showAnnotations(pins, animated: false)
        }
    }
}

/// 안쪽 여백이 있는 글자 (연도 칩)
final class ChipLabel: UILabel {
    var insets = UIEdgeInsets(top: 2, left: 9, bottom: 2, right: 9)
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
    override func sizeThatFits(_ size: CGSize) -> CGSize { intrinsicContentSize }
}

/// 끝까지 오므린 보관함(25칸)용 아주 작은 썸네일을 메모리에 들고 있음.
/// 오므리는 순간 사진 앱에 1000장 넘게 요청하면 2~3초에 걸쳐 칸이 채워져서, 7칸에 있을 때 근처 것을 미리 받아 둠
final class DenseThumbs {
    static let shared = DenseThumbs()
    private var images: [String: UIImage] = [:]
    private var order: [String] = []
    private var pending = Set<String>()
    private let limit = 4000   // 60×60 화소 × 4000장 ≈ 55MB 이하
    private let manager = PHImageManager.default()
    private let options: PHImageRequestOptions = {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat   // 한 번만 옴
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        return options
    }()

    private init() {
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil,
                                               queue: .main) { [weak self] _ in self?.clear() }
    }

    func image(for id: String) -> UIImage? { images[id] }

    private var queue: [PHAsset] = []
    private var size = CGSize.zero
    private var generation = 0

    /// 없는 것만 받음 (메인 스레드에서 부름). 지금 화면의 썸네일이 먼저 오게 조금 기다렸다가, 조금씩 나눠서
    func warm(_ assets: [PHAsset], size: CGSize) {
        generation += 1
        let mine = generation
        queue = assets
        self.size = size
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.drain(mine) }
    }

    private func drain(_ mine: Int) {
        guard mine == generation, !queue.isEmpty else { return }
        let batch = queue.prefix(150)
        queue.removeFirst(batch.count)
        request(Array(batch), size: size)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.drain(mine) }
    }

    /// 칸 수가 바뀌어 더 받을 필요 없음
    func cancelWarm() {
        generation += 1
        queue.removeAll()
    }

    private func request(_ assets: [PHAsset], size: CGSize) {
        for asset in assets {
            let id = asset.localIdentifier
            guard images[id] == nil, !pending.contains(id) else { continue }
            pending.insert(id)
            manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { [weak self] image, _ in
                guard let self else { return }
                self.pending.remove(id)
                guard let image else { return }
                self.store(image, for: id)
            }
        }
    }

    private func store(_ image: UIImage, for id: String) {
        if images[id] == nil { order.append(id) }
        images[id] = image
        if order.count > limit {
            let drop = order.prefix(order.count - limit)
            drop.forEach { images[$0] = nil }
            order.removeFirst(drop.count)
        }
    }

    /// 메모리가 부족하면 비움
    func clear() {
        images.removeAll()
        order.removeAll()
    }
}
