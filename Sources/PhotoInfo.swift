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

/// 순정 사진 앱의 정보 화면처럼 둥근 회색 카드들. 사진 페이지 안에서 사진 아래에 붙음
final class InfoPanelView: UIView {
    private let asset: PHAsset
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

    private static let mapHeight: CGFloat = 170

    init(asset: PHAsset) {
        self.asset = asset
        super.init(frame: .zero)
        backgroundColor = .clear
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
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

    private func load() {
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
            Thumbs.manager.requestImage(for: asset, targetSize: CGSize(width: 120, height: 120), contentMode: .aspectFill,
                                        options: options) { [weak self] image, _ in
                guard let self, let image else { return }
                self.pinImage = image
                if self.mapImage != nil { self.rebuild() }
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        startMapIfNeeded(width: bounds.width - 28)
    }

    /// 작은 지도 그림 (MapKit 스냅숏, 위치 권한 필요 없음)
    private func startMapIfNeeded(width: CGFloat) {
        guard let location = asset.location, width > 40, !mapLoading, abs(width - mapWidth) > 1 else { return }
        mapLoading = true
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 700, longitudinalMeters: 700)
        options.size = CGSize(width: width, height: InfoPanelView.mapHeight)
        let snapshotter = MKMapSnapshotter(options: options)
        self.snapshotter = snapshotter   // 끝날 때까지 붙잡아 둠
        snapshotter.start { [weak self] snapshot, _ in
            guard let self else { return }
            self.mapLoading = false
            self.snapshotter = nil
            guard let snapshot else { return }
            self.mapWidth = width
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

    private func padded(_ content: UIView, vertical: CGFloat = 13) -> UIView {
        let box = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: vertical),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -vertical),
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -18),
        ])
        return box
    }

    private func separator() -> UIView {
        let line = UIView()
        line.backgroundColor = .separator
        line.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return line
    }

    /// 줄들을 얇은 선으로 나눈 둥근 카드
    private func card(_ rows: [UIView], separators: Bool = true) -> UIView {
        let column = UIStackView()
        column.axis = .vertical
        for (index, row) in rows.enumerated() {
            if index > 0 && separators { column.addArrangedSubview(separator()) }
            column.addArrangedSubview(row)
        }
        column.backgroundColor = .secondarySystemBackground
        column.layer.cornerRadius = 24
        column.layer.cornerCurve = .continuous
        column.clipsToBounds = true
        return column
    }

    private func badge(_ text: String) -> UIView {
        let label = PaddedLabel()
        label.text = text
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabel
        label.backgroundColor = .tertiarySystemFill
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }

    private func mapView() -> UIView {
        let container = UIView()
        container.backgroundColor = .tertiarySystemFill
        container.heightAnchor.constraint(equalToConstant: InfoPanelView.mapHeight).isActive = true
        guard let mapImage else { return container }
        let imageView = UIImageView(image: mapImage)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)
        // 순정처럼 핀 자리에 그 사진을 작게
        let pin = UIImageView(image: pinImage ?? UIImage(systemName: "mappin.circle.fill"))
        pin.contentMode = .scaleAspectFill
        pin.clipsToBounds = true
        pin.tintColor = .systemRed
        pin.backgroundColor = .white
        pin.layer.borderColor = UIColor.white.cgColor
        pin.layer.borderWidth = 2
        pin.layer.cornerRadius = 6
        pin.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(pin)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.widthAnchor.constraint(equalToConstant: mapImage.size.width),
            imageView.heightAnchor.constraint(equalToConstant: mapImage.size.height),
            pin.widthAnchor.constraint(equalToConstant: 38),
            pin.heightAnchor.constraint(equalToConstant: 38),
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
        let resources = PHAssetResource.assetResources(for: asset)
        let primaryType: PHAssetResourceType = isVideo ? .video : .photo
        let primary = resources.first { $0.type == primaryType } ?? resources.first
        let fileName = primary?.originalFilename ?? ""
        let entry = Library.shared.classifier.entry(for: asset.localIdentifier)

        // 1) 날짜 · 파일 이름 / 카메라 · 형식 / 렌즈 · 크기 / 촬영 값
        var rows: [UIView] = []

        let header = UIStackView()
        header.axis = .vertical
        header.spacing = 3
        if let date = asset.creationDate {
            header.addArrangedSubview(label(DateText.long(date), weight: .medium))
        }
        if !fileName.isEmpty {
            header.addArrangedSubview(label((fileName as NSString).deletingPathExtension, size: 15, color: .secondaryLabel))
        }
        rows.append(padded(header))

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
        let cameraRow = UIStackView(arrangedSubviews: [cameraLabel])
        cameraRow.axis = .horizontal
        cameraRow.alignment = .center
        cameraRow.spacing = 8
        if !format.isEmpty { cameraRow.addArrangedSubview(badge(format)) }
        rows.append(padded(cameraRow))

        let megapixels = Double(asset.pixelWidth * asset.pixelHeight) / 1_000_000
        var sizeParts = [megapixels >= 10 ? "\(Int(megapixels.rounded()))MP" : String(format: "%.1fMP", megapixels),
                         "\(asset.pixelWidth) × \(asset.pixelHeight)"]
        if let bytes = details?.fileSize {
            sizeParts.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
        }
        if isVideo {
            let total = Int(asset.duration.rounded())
            sizeParts.append(String(format: "%d:%02d", total / 60, total % 60))
        }
        let lensColumn = UIStackView()
        lensColumn.axis = .vertical
        lensColumn.spacing = 3
        if !isVideo, let details, let lens = DetailsLoader.lensText(details) {
            lensColumn.addArrangedSubview(label(lens, size: 15, color: .secondaryLabel))
        }
        lensColumn.addArrangedSubview(label(sizeParts.joined(separator: " • "), size: 15, color: .secondaryLabel))
        rows.append(padded(lensColumn))

        if !isVideo, let details, let values = DetailsLoader.exifValues(details) {
            let exifRow = UIStackView()
            exifRow.axis = .horizontal
            exifRow.distribution = .fillEqually
            for value in values {
                let item = label(value, size: 13, color: .secondaryLabel)
                item.textAlignment = .center
                item.numberOfLines = 1
                item.adjustsFontSizeToFitWidth = true
                item.minimumScaleFactor = 0.7
                exifRow.addArrangedSubview(item)
            }
            rows.append(padded(exifRow, vertical: 11))
        }
        stack.addArrangedSubview(card(rows))

        // 2) 지도 + 장소 이름
        if let location = asset.location {
            let place = placeName ?? String(format: "%.5f, %.5f", location.coordinate.latitude, location.coordinate.longitude)
            stack.addArrangedSubview(card([mapView(), padded(label(place, size: 15, weight: .medium))], separators: false))
        }

        // 3) 어디서 저장됐는지 (알 수 있을 때)
        if let app = entry?.app {
            stack.addArrangedSubview(card([padded(label(app + "에서 저장됨"))]))
        } else if entry?.cat == .camera {
            stack.addArrangedSubview(card([padded(label("카메라로 촬영"))]))
        }

        // 4) 들어 있는 앨범 (이 앱에서 더한 것)
        if albumNames == nil {
            let snapshot = Library.shared.snapshot
            let id = asset.localIdentifier
            var names: [String] = []
            for folder in snapshot.folders where folder.isUser {
                if snapshot.items[folder.id]?.contains(where: { $0.localIdentifier == id }) == true {
                    names.append(folder.title)
                }
            }
            albumNames = names
        }
        let albums = albumNames ?? []
        let albumText = albums.isEmpty ? "앨범 없음 (미분류)" : "앨범  " + albums.joined(separator: ", ")
        stack.addArrangedSubview(card([padded(label(albumText, color: albums.isEmpty ? .secondaryLabel : .label))]))

        onContentChange?()
    }
}
