import CoreLocation
import ImageIO
import MapKit
import Photos
import UIKit
import UniformTypeIdentifiers

// MARK: - 날짜 글자 (순정 사진 앱처럼: 오늘 · 어제 · 요일 · 올해는 연도 생략)

enum DateText {
    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = format
        return formatter
    }

    private static let fullDay = formatter("yyyy년 M월 d일")
    private static let yearlessDay = formatter("M월 d일")
    private static let weekday = formatter("EEEE")
    private static let clock = formatter("a h:mm")
    private static let longDate = formatter("yyyy년 M월 d일 EEEE a h:mm")

    /// 오늘 / 어제 / 월요일(지난 며칠) / 10월 10일(올해) / 2025년 9월 26일
    static func day(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 99
        if days == 0 { return "오늘" }
        if days == 1 { return "어제" }
        if days > 1 && days < 7 { return weekday.string(from: date) }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return yearlessDay.string(from: date)
        }
        return fullDay.string(from: date)
    }

    /// 오후 4:51
    static func time(_ date: Date) -> String {
        clock.string(from: date)
    }

    /// 2025년 9월 26일 오후 4:51 (위의 규칙대로 줄임)
    static func dayAndTime(_ date: Date) -> String {
        day(date) + " " + time(date)
    }

    /// 정보 카드의 첫 줄: 2025년 9월 26일 금요일 오후 4:49
    static func long(_ date: Date) -> String {
        longDate.string(from: date)
    }
}

// MARK: - 장소 이름 (역지오코딩, 결과는 기억해 둠. 위치 권한은 필요 없음)

final class PlaceNames {
    static let shared = PlaceNames()

    private let geocoder = CLGeocoder()
    private var names: [String: String] = [:]                    // "" = 이름을 못 찾음
    private var waiting: [String: [(String?) -> Void]] = [:]
    private var queue: [(key: String, location: CLLocation)] = []
    private var busy = false
    private var inFlight: String?

    private func cacheKey(_ location: CLLocation) -> String {
        String(format: "%.4f,%.4f", location.coordinate.latitude, location.coordinate.longitude)
    }

    /// 이미 알아본 곳인지 (이름이 없다는 결과도 포함)
    func isKnown(_ location: CLLocation) -> Bool {
        names[cacheKey(location)] != nil
    }

    /// 기억해 둔 이름 (없으면 nil)
    func cachedName(_ location: CLLocation) -> String? {
        guard let name = names[cacheKey(location)], !name.isEmpty else { return nil }
        return name
    }

    /// 이름을 알아봄. 기억해 둔 것이 있으면 바로 부름. 메인 줄에서만 씀
    func lookup(_ location: CLLocation, completion: @escaping (String?) -> Void) {
        let key = cacheKey(location)
        if let name = names[key] {
            completion(name.isEmpty ? nil : name)
            return
        }
        waiting[key, default: []].append(completion)
        if inFlight == key { return }
        queue.removeAll { $0.key == key }
        queue.append((key, location))
        // 빨리 넘기면 줄이 길어지므로 가장 최근 것 몇 개만 남김 (애플 서버는 요청 횟수를 제한함)
        while queue.count > 4 {
            let dropped = queue.removeFirst()
            waiting[dropped.key] = nil
        }
        next()
    }

    private func next() {
        guard !busy, let item = queue.popLast() else { return }
        busy = true
        inFlight = item.key
        geocoder.reverseGeocodeLocation(item.location, preferredLocale: Locale(identifier: "ko_KR")) { [weak self] placemarks, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                self.inFlight = nil
                var name: String?
                if let placemark = placemarks?.first {
                    name = PlaceNames.describe(placemark)
                    self.names[item.key] = name ?? ""
                } else if error == nil {
                    self.names[item.key] = ""
                }
                // 오류(네트워크·요청 제한)면 기억하지 않아서 다음에 다시 알아봄
                let callbacks = self.waiting.removeValue(forKey: item.key) ?? []
                for callback in callbacks {
                    callback(name)
                }
                self.next()
            }
        }
    }

    /// 순정처럼: 건물·장소 이름이 있으면 그것, 없으면 "부산광역시 - 신호동"
    static func describe(_ placemark: CLPlacemark) -> String? {
        if let place = placemark.areasOfInterest?.first, !place.isEmpty {
            return place
        }
        let city = placemark.administrativeArea ?? placemark.locality
        let district = placemark.subLocality ?? placemark.locality
        if let name = placemark.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
           name.range(of: #"\d+(-\d+)?$"#, options: .regularExpression) == nil,   // "…동 123-4" 같은 주소는 뺌
           !name.contains("대한민국"),
           name != city, name != district, name != placemark.thoroughfare, name != placemark.country {
            return name
        }
        var parts: [String] = []
        if let city, !city.isEmpty { parts.append(city) }
        if let district, !district.isEmpty, district != city { parts.append(district) }
        return parts.isEmpty ? nil : parts.joined(separator: " - ")
    }
}

// MARK: - 촬영 정보 (원본 파일에서 읽음)

struct PhotoDetails {
    var make: String?
    var model: String?
    var lensModel: String?
    var format: String?
    var fileSize: Int?
    var iso: Int?
    var focal: Double?
    var focal35: Double?
    var bias: Double?
    var aperture: Double?
    var shutter: Double?
}

private final class DataBox {
    private let lock = NSLock()
    private var stored = Data()
    private var total = 0
    private let cap: Int

    init(cap: Int) {
        self.cap = cap
    }

    func append(_ chunk: Data) {
        lock.lock()
        total += chunk.count
        if stored.count < cap { stored.append(chunk) }
        lock.unlock()
    }

    var data: Data {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return total
    }

    var truncated: Bool {
        lock.lock(); defer { lock.unlock() }
        return total > stored.count
    }
}

enum DetailsLoader {
    /// 사진 ID → 읽은 정보 (메인 줄에서만)
    private static var cache: [String: PhotoDetails] = [:]
    private static var waiting: [String: [(PhotoDetails) -> Void]] = [:]
    /// 앞부분만 읽어도 촬영 정보는 나옴. 큰 파일(ProRAW 등)을 통째로 메모리에 올리지 않게
    private static let readCap = 16 * 1024 * 1024

    static func cached(_ asset: PHAsset) -> PhotoDetails? {
        cache[asset.localIdentifier]
    }

    /// 원본 파일(iCloud 에만 있으면 받아서)을 읽어 촬영 정보와 파일 크기를 알아냄. completion 은 메인 줄
    static func load(_ asset: PHAsset, completion: @escaping (PhotoDetails) -> Void) {
        let id = asset.localIdentifier
        if let hit = cache[id] {
            completion(hit)
            return
        }
        if waiting[id] != nil {
            waiting[id]?.append(completion)
            return
        }
        waiting[id] = [completion]

        let finish: (PhotoDetails) -> Void = { details in
            DispatchQueue.main.async {
                cache[id] = details
                let callbacks = waiting.removeValue(forKey: id) ?? []
                for callback in callbacks {
                    callback(details)
                }
            }
        }

        let resources = PHAssetResource.assetResources(for: asset)
        let isVideo = asset.mediaType == .video
        let preferred: [PHAssetResourceType] = isVideo ? [.video, .fullSizeVideo] : [.photo, .fullSizePhoto, .alternatePhoto]
        var chosen: PHAssetResource?
        for type in preferred {
            if let match = resources.first(where: { $0.type == type }) {
                chosen = match
                break
            }
        }
        var start = PhotoDetails()
        if let resource = chosen ?? resources.first {
            start.format = formatName(resource.uniformTypeIdentifier)
        }
        let base = start
        guard !isVideo, let resource = chosen ?? resources.first else {
            // 영상은 파일 전체를 읽지 않음 (크기가 클 수 있음)
            finish(base)
            return
        }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        let box = DataBox(cap: readCap)
        PHAssetResourceManager.default().requestData(for: resource, options: options, dataReceivedHandler: { chunk in
            box.append(chunk)
        }, completionHandler: { error in
            DispatchQueue.global(qos: .userInitiated).async {
                var details = base
                let data = box.data
                var parsed = false
                if error == nil, !data.isEmpty {
                    details.fileSize = box.count
                    parsed = parse(data, into: &details)
                }
                if parsed {
                    finish(details)
                } else {
                    // 원본을 못 읽었거나(오류) 앞부분만으로 모자람 → 사진 앱이 주는 이미지 데이터로 다시
                    fallback(asset, base: details, finish: finish)
                }
            }
        })
    }

    private static func fallback(_ asset: PHAsset, base: PhotoDetails, finish: @escaping (PhotoDetails) -> Void) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .original
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, _ in
            DispatchQueue.global(qos: .userInitiated).async {
                var details = base
                if let data {
                    if details.fileSize == nil { details.fileSize = data.count }
                    if details.format == nil, let uti { details.format = formatName(uti) }
                    _ = parse(data, into: &details)
                }
                finish(details)
            }
        }
    }

    /// JPEG / HEIF / PNG …
    static func formatName(_ uti: String) -> String? {
        guard let type = UTType(uti) else { return nil }
        if type.conforms(to: .heic) || type.conforms(to: .heif) { return "HEIF" }
        if type.conforms(to: .jpeg) { return "JPEG" }
        if type.conforms(to: .rawImage) { return "RAW" }
        guard let ext = type.preferredFilenameExtension, !ext.isEmpty else { return nil }
        return ext.uppercased()
    }

    /// 읽은 게 하나라도 있으면 true
    @discardableResult
    private static func parse(_ data: Data, into details: inout PhotoDetails) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return false }
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        func text(_ value: Any?) -> String? {
            guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else { return nil }
            return string
        }
        func number(_ value: Any?) -> Double? {
            (value as? NSNumber)?.doubleValue
        }
        details.make = text(tiff?[kCGImagePropertyTIFFMake])
        details.model = text(tiff?[kCGImagePropertyTIFFModel])
        details.lensModel = text(exif?[kCGImagePropertyExifLensModel])
        if let iso = (exif?[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first {
            details.iso = iso.intValue
        }
        details.focal = number(exif?[kCGImagePropertyExifFocalLength])
        details.focal35 = number(exif?[kCGImagePropertyExifFocalLenIn35mmFilm])
        details.bias = number(exif?[kCGImagePropertyExifExposureBiasValue])
        details.aperture = number(exif?[kCGImagePropertyExifFNumber])
        details.shutter = number(exif?[kCGImagePropertyExifExposureTime])
        return true
    }

    // MARK: 글자로

    /// Apple iPhone 14 Pro
    static func cameraText(_ details: PhotoDetails) -> String? {
        let make = details.make ?? ""
        let model = details.model ?? ""
        if model.isEmpty { return make.isEmpty ? nil : make }
        if make.isEmpty || model.lowercased().hasPrefix(make.lowercased()) { return model }
        return make + " " + model
    }

    /// 메인 카메라 — 24 mm ƒ1.78
    static func lensText(_ details: PhotoDetails) -> String? {
        let lens = details.lensModel ?? ""
        let lower = lens.lowercased()
        var name: String?
        if (details.make ?? "").lowercased() == "apple" && lower.contains("iphone") {
            if lower.contains("front") {
                name = "전면 카메라"
            } else if let focal = details.focal35 {
                name = focal <= 18 ? "울트라 와이드 카메라" : (focal <= 50 ? "메인 카메라" : "망원 카메라")
            } else {
                name = "후면 카메라"
            }
        } else if !lens.isEmpty {
            name = lens
        }
        var specs: [String] = []
        if let focal = details.focal35 ?? details.focal { specs.append("\(Int(focal.rounded())) mm") }
        if let aperture = details.aperture { specs.append("ƒ" + String(format: "%g", aperture)) }
        switch (name, specs.isEmpty) {
        case (nil, true): return nil
        case (nil, false): return specs.joined(separator: " ")
        case (let name?, true): return name
        case (let name?, false): return name + " — " + specs.joined(separator: " ")
        }
    }

    /// ISO · 초점 거리(35mm 환산) · ev · ƒ · 셔터. 하나도 없으면 nil
    static func exifValues(_ details: PhotoDetails) -> [String]? {
        var values: [String?] = []
        values.append(details.iso.map { "ISO \($0)" })
        values.append((details.focal35 ?? details.focal).map { "\(Int($0.rounded())) mm" })
        values.append(details.bias.map { value in
            (value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)) + " ev"
        })
        values.append(details.aperture.map { "ƒ" + String(format: "%g", $0) })
        values.append(details.shutter.flatMap { value in
            guard value > 0 else { return nil }
            return value < 1 ? "1/\(Int((1 / value).rounded())) s" : String(format: "%g s", value)
        })
        guard values.contains(where: { $0 != nil }) else { return nil }
        return values.map { $0 ?? "-" }
    }
}

// MARK: - 정보 카드 (사진 바로 아래에 이어지는 부분)

/// 정보 카드에서 누른 것 (보기 화면이 처리)
enum InfoAction {
    /// 날짜·시간 조정
    case adjustDate
    /// 장소를 지도 앱에서 열기
    case openPlace
    /// 저장한 앱의 자동 분류 앨범 열기 (앨범 ID)
    case openSource(String)
    /// 보관함 탭에서 이 사진 보기
    case showInLibrary
    /// 위치가 없는 사진에 장소 넣기
    case addLocation
}

/// 누를 수 있는 줄 (누르는 동안 살짝 어두워짐)
private final class TapRow: UIControl {
    private let action: () -> Void

    init(content: UIView, vertical: CGFloat, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        content.isUserInteractionEnabled = false
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: vertical),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -vertical),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: InfoPanelView.textInset),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -InfoPanelView.textInset),
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? .systemFill : .clear }
    }

    @objc private func tapped() {
        action()
    }
}

/// 지도 위의 핀: 그 사진을 흰 테두리의 작은 둥근 네모에 넣고 아래에 꼬리 (꼬리 끝이 찍은 자리)
private final class PhotoPinView: UIView {
    static let side: CGFloat = 48
    static let tail: CGFloat = 7

    private let imageView = UIImageView()
    private let tailLayer = CAShapeLayer()

    init(image: UIImage?) {
        super.init(frame: CGRect(x: 0, y: 0, width: PhotoPinView.side, height: PhotoPinView.side + PhotoPinView.tail))
        let body = UIView(frame: CGRect(x: 0, y: 0, width: PhotoPinView.side, height: PhotoPinView.side))
        body.backgroundColor = .white
        body.layer.cornerRadius = 6
        body.layer.cornerCurve = .continuous
        addSubview(body)
        imageView.image = image
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .systemGray5
        imageView.layer.cornerRadius = 4
        imageView.layer.cornerCurve = .continuous
        imageView.frame = body.bounds.insetBy(dx: 3, dy: 3)
        body.addSubview(imageView)

        let path = UIBezierPath()
        let mid = PhotoPinView.side / 2
        path.move(to: CGPoint(x: mid - 6, y: PhotoPinView.side - 0.5))
        path.addLine(to: CGPoint(x: mid, y: PhotoPinView.side + PhotoPinView.tail))
        path.addLine(to: CGPoint(x: mid + 6, y: PhotoPinView.side - 0.5))
        path.close()
        tailLayer.path = path.cgPath
        tailLayer.fillColor = UIColor.white.cgColor
        layer.addSublayer(tailLayer)

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.22
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: PhotoPinView.side, height: PhotoPinView.side + PhotoPinView.tail)
    }
}

/// 순정 사진 앱의 정보 화면처럼 둥근 회색 카드들. 사진 페이지 안에서 사진 아래에 붙음.
/// 순서(순정과 같음): 날짜·파일 이름 / 카메라·형식 / 렌즈·크기 / 촬영 값 → 지도·장소 → 저장한 앱 → 모든 사진에서 보기 → (이 앱만) 들어 있는 앨범.
/// 캡션·키워드는 사진 앱 공개 API 로 읽고 쓸 수 없어서 넣지 않음
final class InfoPanelView: UIView {
    private(set) var asset: PHAsset
    private let stack = UIStackView()
    private var details: PhotoDetails?
    private var placeName: String?
    private var mapImage: UIImage?
    private var mapPoint: CGPoint = .zero
    private var mapWidth: CGFloat = 0
    private var mapLoading = false
    private var snapshotter: MKMapSnapshotter?
    private var pinImage: UIImage?
    private var albumNames: [String]?
    /// 내용이 바뀌어 높이가 달라졌을 때
    var onContentChange: (() -> Void)?
    /// 카드 안의 버튼·줄을 눌렀을 때
    var onAction: ((InfoAction) -> Void)?

    /// 화면 가장자리 ~ 카드 (순정 화면에서 잰 값)
    static let sideInset: CGFloat = 17
    /// 카드 가장자리 ~ 글자
    static let textInset: CGFloat = 16
    static let cardSpacing: CGFloat = 18
    static let cornerRadius: CGFloat = 24
    private static let mapHeight: CGFloat = 160

    init(asset: PHAsset) {
        self.asset = asset
        super.init(frame: .zero)
        backgroundColor = .clear
        stack.axis = .vertical
        stack.spacing = InfoPanelView.cardSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: InfoPanelView.sideInset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -InfoPanelView.sideInset),
        ])
        details = DetailsLoader.cached(asset)
        if let location = asset.location {
            placeName = PlaceNames.shared.cachedName(location)
        }
        rebuild()
        load()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 사진 정보가 바뀌었을 때 (날짜 조정 등). 같은 사진의 새 값
    func update(asset fresh: PHAsset) {
        guard fresh.localIdentifier == asset.localIdentifier else { return }
        asset = fresh
        rebuild()
    }

    private func load() {
        loadAlbumNames()
        if details == nil {
            DetailsLoader.load(asset) { [weak self] found in
                guard let self else { return }
                self.details = found
                self.rebuild()
            }
        }
        if let location = asset.location, placeName == nil, !PlaceNames.shared.isKnown(location) {
            PlaceNames.shared.lookup(location) { [weak self] name in
                guard let self, let name else { return }
                self.placeName = name
                self.rebuild()
            }
        }
        if asset.location != nil {
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            Thumbs.manager.requestImage(for: asset, targetSize: CGSize(width: 150, height: 150), contentMode: .aspectFill,
                                        options: options) { [weak self] image, _ in
                guard let self, let image else { return }
                self.pinImage = image
                if self.mapImage != nil { self.rebuild() }
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        startMapIfNeeded(width: bounds.width - InfoPanelView.sideInset * 2)
    }

    /// 이 사진이 든 사진 앱 앨범 이름 (앨범 목록을 하나하나 훑지 않고 사진 앱에 물음. 뒤에서)
    private func loadAlbumNames() {
        let asset = self.asset
        DispatchQueue.global(qos: .userInitiated).async {
            let collections = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
            var ids: [String] = []
            collections.enumerateObjects { collection, _, _ in
                ids.append(Folder.albumPrefix + collection.localIdentifier)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.asset.localIdentifier == asset.localIdentifier else { return }
                // 앨범 목록에 있는 것만 (이름순 — 예전과 같은 차례)
                let nodes = Library.shared.snapshot.nodes
                self.albumNames = ids.compactMap { nodes[$0]?.title }
                    .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                self.rebuild()
            }
        }
    }

    /// 작은 지도 그림 (MapKit 스냅숏, 위치 권한 필요 없음)
    private func startMapIfNeeded(width: CGFloat) {
        guard let location = asset.location, width > 40, !mapLoading, abs(width - mapWidth) > 1 else { return }
        mapLoading = true
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 700, longitudinalMeters: 700)
        options.size = CGSize(width: width, height: InfoPanelView.mapHeight)
        options.traitCollection = traitCollection
        let snapshotter = MKMapSnapshotter(options: options)
        self.snapshotter = snapshotter   // 끝날 때까지 붙잡아 둠
        snapshotter.start { [weak self] snapshot, _ in
            guard let self else { return }
            self.mapLoading = false
            self.snapshotter = nil
            // 실패해도 같은 너비로는 다시 요청하지 않음 (오프라인일 때 배치할 때마다 반복 요청하지 않게)
            self.mapWidth = width
            guard let snapshot else { return }
            self.mapImage = snapshot.image
            self.mapPoint = snapshot.point(for: location.coordinate)
            self.rebuild()
        }
    }

    // MARK: 카드 만들기

    private func label(_ text: String, size: CGFloat = 17, weight: UIFont.Weight = .regular, color: UIColor = .label) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    private func padded(_ content: UIView, vertical: CGFloat) -> UIView {
        let box = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: vertical),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -vertical),
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: InfoPanelView.textInset),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -InfoPanelView.textInset),
        ])
        return box
    }

    /// 가는 선 두께 (화면에 붙기 전이면 0.5)
    private var hairline: CGFloat {
        let scale = traitCollection.displayScale
        return scale > 0 ? 1 / scale : 0.5
    }

    /// 카드 끝에서 끝까지 이어지는 가는 가로선
    private func separator() -> UIView {
        let line = UIView()
        line.backgroundColor = .separator
        line.heightAnchor.constraint(equalToConstant: hairline).isActive = true
        return line
    }

    /// 줄들을 가는 선으로 나눈 둥근 카드
    private func card(_ rows: [UIView], separators: Bool = true) -> UIView {
        let column = UIStackView()
        column.axis = .vertical
        for (index, row) in rows.enumerated() {
            if index > 0 && separators { column.addArrangedSubview(separator()) }
            column.addArrangedSubview(row)
        }
        column.backgroundColor = .secondarySystemBackground
        column.layer.cornerRadius = InfoPanelView.cornerRadius
        column.layer.cornerCurve = .continuous
        column.clipsToBounds = true
        return column
    }

    /// 한 줄짜리 카드 (모든 사진에서 보기 · 저장한 앱 · 앨범)
    private func singleRowCard(_ content: UIView, action: (() -> Void)?) -> UIView {
        if let action {
            return card([TapRow(content: content, vertical: 15, action: action)])
        }
        return card([padded(content, vertical: 15)])
    }

    /// 파란 글자 버튼 ("조정")
    private func adjustButton(_ action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle("조정", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17)
        button.tintColor = .systemBlue
        button.contentHorizontalAlignment = .trailing
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    /// 형식 배지 (JPEG · HEIF …)
    private func badge(_ text: String) -> UIView {
        let box = UIView()
        box.backgroundColor = .tertiarySystemFill
        box.layer.cornerRadius = 6
        box.layer.cornerCurve = .continuous
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -3),
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -7),
        ])
        box.setContentHuggingPriority(.required, for: .horizontal)
        box.setContentCompressionResistancePriority(.required, for: .horizontal)
        return box
    }

    /// Live Photo 배지 (동그라미 안에 Live 모양)
    private func liveBadge() -> UIView {
        let box = UIView()
        box.backgroundColor = .tertiarySystemFill
        box.layer.cornerRadius = 11
        let glyph = UIImageView(image: UIImage(systemName: "livephoto"))
        glyph.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        glyph.tintColor = .secondaryLabel
        glyph.contentMode = .center
        glyph.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(glyph)
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: 22),
            box.heightAnchor.constraint(equalToConstant: 22),
            glyph.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        ])
        box.setContentHuggingPriority(.required, for: .horizontal)
        box.setContentCompressionResistancePriority(.required, for: .horizontal)
        return box
    }

    /// 촬영 값 다섯 칸. 칸 사이에 짧은 세로선, 첫 칸은 왼쪽·끝 칸은 오른쪽 정렬
    private func exifRow(_ values: [String]) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fillEqually
        var labels: [UILabel] = []
        for value in values {
            let item = label(value, size: 13, color: .secondaryLabel)
            item.numberOfLines = 1
            item.adjustsFontSizeToFitWidth = true
            item.minimumScaleFactor = 0.7
            // 순정처럼 다섯 칸 모두 칸 가운데에
            item.textAlignment = .center
            row.addArrangedSubview(item)
            labels.append(item)
        }
        let box = padded(row, vertical: 12)
        for item in labels.dropLast() {
            let line = UIView()
            line.backgroundColor = .separator
            line.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(line)
            NSLayoutConstraint.activate([
                line.centerXAnchor.constraint(equalTo: item.trailingAnchor),
                line.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                line.widthAnchor.constraint(equalToConstant: hairline),
                line.heightAnchor.constraint(equalToConstant: 18),
            ])
        }
        return box
    }

    /// 카드 위쪽을 채우는 지도 + 그 자리에 사진 핀. 누르면 지도 앱에서 열기
    private func mapView() -> UIView {
        let container = UIControl()
        container.backgroundColor = .tertiarySystemFill
        container.clipsToBounds = true
        container.heightAnchor.constraint(equalToConstant: InfoPanelView.mapHeight).isActive = true
        container.addAction(UIAction { [weak self] _ in self?.onAction?(.openPlace) }, for: .touchUpInside)
        guard let mapImage else { return container }
        let imageView = UIImageView(image: mapImage)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)
        let pin = PhotoPinView(image: pinImage)
        pin.isUserInteractionEnabled = false
        pin.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(pin)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.widthAnchor.constraint(equalToConstant: mapImage.size.width),
            imageView.heightAnchor.constraint(equalToConstant: mapImage.size.height),
            pin.widthAnchor.constraint(equalToConstant: PhotoPinView.side),
            pin.heightAnchor.constraint(equalToConstant: PhotoPinView.side + PhotoPinView.tail),
            // 꼬리 끝이 찍은 자리
            pin.centerXAnchor.constraint(equalTo: container.leadingAnchor, constant: mapPoint.x),
            pin.bottomAnchor.constraint(equalTo: container.topAnchor, constant: mapPoint.y),
        ])
        return container
    }

    private func rebuild() {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let isVideo = asset.mediaType == .video
        let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
        let isLive = asset.mediaType == .image && asset.mediaSubtypes.contains(.photoLive)
        let resources = PHAssetResource.assetResources(for: asset)
        let primaryType: PHAssetResourceType = isVideo ? .video : .photo
        let primary = resources.first { $0.type == primaryType } ?? resources.first
        let fileName = primary?.originalFilename ?? ""
        let entry = Library.shared.classifier.entry(for: asset.localIdentifier)

        // 1) 날짜·파일 이름 / 카메라·형식 / 렌즈·크기 / 촬영 값
        var rows: [UIView] = []

        let header = UIStackView()
        header.axis = .vertical
        header.spacing = 2
        let dateText = asset.creationDate.map { DateText.long($0) } ?? "날짜 없음"
        let dateLabel = label(dateText)
        let dateLine = UIStackView(arrangedSubviews: [dateLabel])
        dateLine.axis = .horizontal
        dateLine.alignment = .firstBaseline
        dateLine.spacing = 8
        // 날짜 조정은 사진 앱이 허락하는 사진만 (공유 앨범 사진 등은 안 됨)
        if asset.canPerform(.properties) {
            dateLine.addArrangedSubview(adjustButton { [weak self] in self?.onAction?(.adjustDate) })
        }
        header.addArrangedSubview(dateLine)
        if !fileName.isEmpty {
            // 순정의 iCloud 표시는 공개 API 로 상태를 알 수 없어서 넣지 않음
            header.addArrangedSubview(label((fileName as NSString).deletingPathExtension, size: 15, color: .secondaryLabel))
        }
        let headerBox = UIView()
        header.translatesAutoresizingMaskIntoConstraints = false
        headerBox.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: headerBox.topAnchor, constant: 14),
            header.bottomAnchor.constraint(equalTo: headerBox.bottomAnchor, constant: -15),
            header.leadingAnchor.constraint(equalTo: headerBox.leadingAnchor, constant: InfoPanelView.textInset),
            header.trailingAnchor.constraint(equalTo: headerBox.trailingAnchor, constant: -InfoPanelView.textInset),
        ])
        rows.append(headerBox)

        var cameraText = details.flatMap { DetailsLoader.cameraText($0) } ?? ""
        if cameraText.isEmpty {
            if isScreenshot {
                cameraText = "스크린샷"
            } else if isVideo {
                cameraText = entry?.cat == .recording ? "화면 녹화" : "동영상"
            } else {
                cameraText = details == nil ? "정보를 불러오는 중…" : "카메라 정보 없음"
            }
        }
        var format = details?.format ?? ""
        if format.isEmpty { format = (fileName as NSString).pathExtension.uppercased() }
        if format == "JPG" { format = "JPEG" }
        if format == "HEIC" { format = "HEIF" }
        let cameraLabel = label(cameraText, color: details == nil && !isScreenshot && !isVideo ? .secondaryLabel : .label)
        cameraLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let cameraRow = UIStackView(arrangedSubviews: [cameraLabel])
        cameraRow.axis = .horizontal
        cameraRow.alignment = .center
        cameraRow.spacing = 6
        if !format.isEmpty { cameraRow.addArrangedSubview(badge(format)) }
        if isLive { cameraRow.addArrangedSubview(liveBadge()) }
        rows.append(padded(cameraRow, vertical: 12))

        let pixels = Double(asset.pixelWidth * asset.pixelHeight) / 1_000_000
        var sizeParts = [pixels >= 1 ? "\(Int(pixels.rounded()))MP" : String(format: "%.1fMP", pixels),
                         "\(asset.pixelWidth) × \(asset.pixelHeight)"]
        if let bytes = details?.fileSize {
            // 순정처럼 숫자와 단위를 붙여서 (3.3MB)
            let text = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            sizeParts.append(text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00A0}", with: ""))
        }
        if isVideo {
            let total = Int(asset.duration.rounded())
            sizeParts.append(String(format: "%d:%02d", total / 60, total % 60))
        }
        let lensColumn = UIStackView()
        lensColumn.axis = .vertical
        lensColumn.spacing = 4
        if !isVideo, let details {
            if let lens = DetailsLoader.lensText(details) {
                lensColumn.addArrangedSubview(label(lens, size: 15, color: .secondaryLabel))
            } else if !isScreenshot {
                lensColumn.addArrangedSubview(label("렌즈 정보 없음", size: 15, color: .secondaryLabel))
            }
        }
        lensColumn.addArrangedSubview(label(sizeParts.joined(separator: " • "), size: 15, color: .secondaryLabel))
        rows.append(padded(lensColumn, vertical: 14))

        if !isVideo, let details {
            if let values = DetailsLoader.exifValues(details) {
                rows.append(exifRow(values))
            } else if !isScreenshot {
                rows.append(exifRow(Array(repeating: "-", count: 5)))
            }
        }
        stack.addArrangedSubview(card(rows))

        // 2) 지도 + 장소 이름 (파란 글자 + 꺾쇠, 누르면 지도 앱에서). 위치 조정은 넣지 않음
        if let location = asset.location {
            let place = placeName ?? String(format: "%.5f, %.5f", location.coordinate.latitude, location.coordinate.longitude)
            let placeLabel = label(place, color: .systemBlue)
            placeLabel.numberOfLines = 1
            placeLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
            chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            chevron.tintColor = .tertiaryLabel
            chevron.setContentHuggingPriority(.required, for: .horizontal)
            chevron.setContentCompressionResistancePriority(.required, for: .horizontal)
            let placeRow = UIStackView(arrangedSubviews: [placeLabel, chevron, UIView()])
            placeRow.axis = .horizontal
            placeRow.alignment = .center
            placeRow.spacing = 6
            let row = TapRow(content: placeRow, vertical: 12) { [weak self] in self?.onAction?(.openPlace) }
            stack.addArrangedSubview(card([mapView(), row], separators: false))
        }

        if asset.location == nil, asset.canPerform(.properties) {
            stack.addArrangedSubview(singleRowCard(label("위치 추가…", color: .systemBlue)) { [weak self] in
                self?.onAction?(.addLocation)
            })
        }

        // 3) 어디서 저장됐는지: "[앱 이름(굵게)]에서 저장됨 ›" (앱 아이콘은 공개 API 로 못 얻어서 뺌)
        if let app = entry?.app {
            let text = NSMutableAttributedString(string: app, attributes: [
                .font: UIFont.systemFont(ofSize: 17, weight: .semibold), .foregroundColor: UIColor.label,
            ])
            text.append(NSAttributedString(string: "에서 저장됨", attributes: [
                .font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.secondaryLabel,
            ]))
            let sourceLabel = UILabel()
            sourceLabel.attributedText = text
            sourceLabel.numberOfLines = 0
            sourceLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            // 그 앱의 자동 분류 앨범이 있고 숨기지 않았을 때만 눌러서 열 수 있음 (숨긴 앨범은 Face ID 를 거쳐야 하므로)
            let folderID = "app:" + app
            let canOpen = Library.shared.snapshot.folders.contains { $0.id == folderID }
                && !Prefs.hiddenAlbums.contains(folderID)
            let sourceRow = UIStackView(arrangedSubviews: [sourceLabel])
            sourceRow.axis = .horizontal
            sourceRow.alignment = .center
            sourceRow.spacing = 6
            if canOpen {
                let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
                chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
                chevron.tintColor = .tertiaryLabel
                chevron.setContentHuggingPriority(.required, for: .horizontal)
                sourceRow.addArrangedSubview(chevron)
            }
            sourceRow.addArrangedSubview(UIView())
            var open: (() -> Void)?
            if canOpen {
                open = { [weak self] in self?.onAction?(.openSource(folderID)) }
            }
            stack.addArrangedSubview(singleRowCard(sourceRow, action: open))
        }

        // 4) 모든 사진에서 보기
        stack.addArrangedSubview(singleRowCard(label("모든 사진에서 보기", color: .systemBlue)) { [weak self] in
            self?.onAction?(.showInLibrary)
        })

        // 5) 들어 있는 앨범 (이 앱에서 더한 것. 맨 끝). 찾는 것은 load() 가 뒤에서
        let albums = albumNames ?? []
        let albumText: String
        if albumNames == nil {
            albumText = "앨범 확인 중"
        } else {
            albumText = albums.isEmpty ? "앨범 없음 (미분류)" : "앨범  " + albums.joined(separator: ", ")
        }
        stack.addArrangedSubview(singleRowCard(label(albumText, color: albums.isEmpty ? .secondaryLabel : .label), action: nil))

        onContentChange?()
    }
}

// MARK: - 날짜·시간 조정 시트

/// 정보 카드의 "조정" → 날짜와 시간을 고르는 시트. "조정" 을 누르면 onSave
final class DateAdjustViewController: UIViewController {
    private let original: Date
    private let picker = UIDatePicker()
    var onSave: ((Date) -> Void)?

    init(date: Date) {
        original = date
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let adjustedValue = UILabel()

    /// "2026. 11. 17. 오후 9:47:06" (순정 표기)
    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        title = "날짜 및 시간 조정"
        // 순정 iOS 27: 왼쪽 X, 오른쪽 파란 "조정"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "조정", style: .done, target: self, action: #selector(saveTapped))

        func row(_ title: String, _ value: UILabel, valueColor: UIColor) -> UIView {
            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.font = .preferredFont(forTextStyle: .body)
            value.font = .preferredFont(forTextStyle: .body)
            value.textColor = valueColor
            value.textAlignment = .right
            value.adjustsFontSizeToFitWidth = true
            value.minimumScaleFactor = 0.7
            let stack = UIStackView(arrangedSubviews: [titleLabel, value])
            stack.spacing = 12
            titleLabel.setContentHuggingPriority(.required, for: .horizontal)
            titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
            return stack
        }
        func divider() -> UIView {
            let line = UIView()
            line.backgroundColor = .separator
            line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale).isActive = true
            return line
        }
        func card(_ views: [UIView]) -> UIView {
            let stack = UIStackView(arrangedSubviews: views)
            stack.axis = .vertical
            stack.translatesAutoresizingMaskIntoConstraints = false
            let card = UIView()
            card.backgroundColor = .secondarySystemGroupedBackground
            card.layer.cornerRadius = 26
            card.layer.cornerCurve = .continuous
            card.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 4),
                stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -4),
                stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
                stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            ])
            return card
        }

        // 위 카드: 원본 / 조정 후
        let originalValue = UILabel()
        originalValue.text = Self.stamp.string(from: original)
        adjustedValue.text = Self.stamp.string(from: original)
        let top = card([row("원본", originalValue, valueColor: .tertiaryLabel), divider(),
                        row("조정 후", adjustedValue, valueColor: .secondaryLabel)])

        // 아래 카드: 달력 + 시간, 시간대
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .inline
        picker.locale = Locale(identifier: "ko_KR")
        picker.date = original
        picker.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.adjustedValue.text = Self.stamp.string(from: self.picker.date)
        }, for: .valueChanged)
        let zoneValue = UILabel()
        zoneValue.text = Self.zoneName(TimeZone.current)
        let bottom = card([picker, divider(), row("시간대", zoneValue, valueColor: .secondaryLabel)])

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)
        let content = UIStackView(arrangedSubviews: [top, bottom])
        content.axis = .vertical
        content.spacing = 28
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            content.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -16),
        ])
    }

    /// 시간대 도시 이름 (순정처럼 "서울")
    private static func zoneName(_ zone: TimeZone) -> String {
        let known = ["Asia/Seoul": "서울", "Asia/Tokyo": "도쿄", "America/Los_Angeles": "로스앤젤레스",
                     "America/New_York": "뉴욕", "Europe/London": "런던", "Europe/Paris": "파리"]
        if let name = known[zone.identifier] { return name }
        return zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") }
            ?? zone.localizedName(for: .generic, locale: Locale(identifier: "ko_KR")) ?? zone.identifier
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        let date = picker.date
        let onSave = self.onSave
        dismiss(animated: true) {
            onSave?(date)
        }
    }
}

// MARK: - 위치 추가 시트 (순정처럼: 장소를 검색해서 고름)

final class LocationSearchViewController: UITableViewController, UISearchBarDelegate, MKLocalSearchCompleterDelegate {
    var onPick: ((CLLocation) -> Void)?
    private let completer = MKLocalSearchCompleter()
    private var results: [MKLocalSearchCompletion] = []
    /// 순정 iOS 27: 제목 바로 밑에 검색창 (아래쪽 검색이 아님)
    private let searchBar = UISearchBar()
    private var searching = false

    init() {
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if title == nil { title = "위치 조정" }
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(cancel))
        view.backgroundColor = .systemBackground
        searchBar.placeholder = "새로운 위치 입력"
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        // 순정처럼 비어 있을 때 오른쪽에 마이크 (누르면 입력 시작, 받아쓰기는 키보드의 마이크)
        searchBar.setImage(UIImage(systemName: "mic.fill"), for: .bookmark, state: .normal)
        searchBar.showsBookmarkButton = true
        // 순정처럼 양옆 여백을 더 두고, 위아래에 가는 선
        let header = UIView(frame: CGRect(x: 0, y: 0, width: 393, height: 64))
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(searchBar)
        var constraints = [
            searchBar.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -8),
            searchBar.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ]
        for top in [true, false] {
            let line = UIView()
            line.backgroundColor = .separator
            line.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(line)
            constraints += [
                line.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
                line.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
                line.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
                top ? line.topAnchor.constraint(equalTo: header.topAnchor) : line.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            ]
        }
        NSLayoutConstraint.activate(constraints)
        tableView.tableHeaderView = header
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "place")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 바로 입력할 수 있게
        DispatchQueue.main.async { self.searchBar.becomeFirstResponder() }
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    func searchBarBookmarkButtonClicked(_ searchBar: UISearchBar) {
        searchBar.becomeFirstResponder()
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchBar.showsBookmarkButton = searchText.isEmpty
        let text = searchText.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            results = []
            tableView.reloadData()
        } else {
            completer.queryFragment = text
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results
        tableView.reloadData()
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        results.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "place", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        let result = results[indexPath.row]
        content.text = result.title
        content.secondaryText = result.subtitle
        content.secondaryTextProperties.color = .secondaryLabel
        content.image = UIImage(systemName: "mappin.circle.fill")
        content.imageProperties.tintColor = .systemRed
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !searching else { return }
        searching = true
        let request = MKLocalSearch.Request(completion: results[indexPath.row])
        MKLocalSearch(request: request).start { [weak self] response, _ in
            guard let self else { return }
            self.searching = false
            guard let coordinate = response?.mapItems.first?.placemark.coordinate else { return }
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let onPick = self.onPick
            self.searchBar.resignFirstResponder()
            self.dismiss(animated: true) { onPick?(location) }
        }
    }
}
