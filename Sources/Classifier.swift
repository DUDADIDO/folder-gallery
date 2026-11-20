import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

/// 사진 한 장이 어디서 왔는지. 스크린샷은 iOS 가 직접 알려 줘서 여기 안 들어감.
enum Cat: Int, Codable {
    case camera = 1      // 아이폰 카메라로 찍은 것
    case saved = 2       // 앱·웹에서 저장하거나 받은 것
    case recording = 3   // 화면 녹화
}

struct Entry: Codable {
    var cat: Cat
    var app: String?     // 저장한 앱 이름 (알 수 있을 때만)
}

private final class Box<T> {
    var value: T
    init(_ value: T) { self.value = value }
}

/// 사진 앱 정보 창의 "…에서 저장됨" 과 같은 정보. 공개 API 가 아니라서 있을 때만 쓰고,
/// 읽다가 앱이 죽으면 다음 실행부터는 끔(표시 파일로 확인).
enum ImportProbe {
    private static let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private static let running = dir.appendingPathComponent("probe-running")
    private static let strikesKey = "probeStrikes"
    /// 분류 묶음이 이만큼 연달아 끝나지 못하면(앱이 죽었으면) 끔. 한 번은 그냥 앱을 끈 것일 수 있음
    private static let maxStrikes = 2
    private static var marked = false
    private(set) static var hits = 0

    private(set) static var usable: Bool = {
        let fm = FileManager.default
        let defaults = UserDefaults.standard
        if fm.fileExists(atPath: running.path) {
            defaults.set(defaults.integer(forKey: strikesKey) + 1, forKey: strikesKey)
            try? fm.removeItem(at: running)
        }
        return defaults.integer(forKey: strikesKey) < maxStrikes
    }()

    static var state: String {
        let strikes = UserDefaults.standard.integer(forKey: strikesKey)
        return usable ? "on(hits \(hits), strikes \(strikes))" : "off(strikes \(strikes))"
    }

    /// 분류 묶음이 무사히 끝났을 때
    static func endBatch() {
        if marked {
            marked = false
            try? FileManager.default.removeItem(at: running)
            UserDefaults.standard.set(0, forKey: strikesKey)
        }
    }

    /// '사진 다시 분류' 때 다시 시도
    static func reenable() {
        try? FileManager.default.removeItem(at: running)
        marked = false
        UserDefaults.standard.set(0, forKey: strikesKey)
        usable = true
    }

    /// 분류 줄(직렬)에서만 부름
    static func read(_ asset: PHAsset) -> (by: Int?, bundle: String?, name: String?)? {
        guard usable else { return nil }
        if !marked {
            marked = true
            FileManager.default.createFile(atPath: running.path, contents: nil)
        }

        let sel = NSSelectorFromString("importProperties")
        guard asset.responds(to: sel),
              let obj = asset.perform(sel)?.takeUnretainedValue() as? NSObject else { return nil }

        func string(_ key: String) -> String? {
            let s = NSSelectorFromString(key)
            guard obj.responds(to: s) else { return nil }
            return obj.perform(s)?.takeUnretainedValue() as? String
        }
        var by: Int?
        if obj.responds(to: NSSelectorFromString("importedBy")) {
            by = (obj.value(forKey: "importedBy") as? NSNumber)?.intValue
        }
        let bundle = string("importedByBundleIdentifier")
        let name = string("importedByDisplayName")
        if by != nil || bundle != nil { hits += 1 }
        return (by, bundle, name)
    }
}

final class Classifier {
    var onProgress: (() -> Void)?

    private let queue = DispatchQueue(label: "gallery.classifier", qos: .utility)
    private let lock = NSLock()
    private var cache: [String: Entry] = [:]
    private var queued = Set<String>()
    private var stats: [String: Int] = [:]
    private let url: URL

    /// 애플 앱 중 '저장한 곳'으로 보여 줄 것
    private let appleSources: [String: String] = [
        "com.apple.mobilesafari": "Safari",
        "com.apple.MobileSMS": "메시지",
        "com.apple.mobilemail": "Mail",
        "com.apple.sharingd": "AirDrop",
        "com.apple.DocumentsApp": "파일",
    ]

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("classify-v1.json")
        // 저장해 둔 분류는 처음 쓸 때 읽음 (보통 work 줄의 전체 목록 만들기. 켤 때 메인 줄을 막지 않게)
        _ = ImportProbe.usable
    }

    /// 저장해 둔 분류를 아직 안 읽었으면 읽음. lock 을 잡은 채로만 부름
    private var cacheLoaded = false
    private func loadCacheIfNeeded() {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        if let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            // 읽기 전에 들어온 것이 있으면 그쪽이 새것
            cache = saved.merging(cache) { _, new in new }
        }
    }

    func snapshotCache() -> [String: Entry] {
        lock.lock(); defer { lock.unlock() }
        loadCacheIfNeeded()
        return cache
    }

    func entry(for id: String) -> Entry? {
        lock.lock(); defer { lock.unlock() }
        loadCacheIfNeeded()
        return cache[id]
    }

    func statsText() -> String {
        lock.lock(); let s = stats; lock.unlock()
        return s.sorted { $0.value > $1.value }.prefix(25).map { "  \($0.value)  \($0.key)" }.joined(separator: "\n")
    }

    func enqueue(_ assets: [PHAsset]) {
        lock.lock()
        loadCacheIfNeeded()
        // 이미 분류했거나 줄 서 있는 건 뺌
        let fresh = assets.filter { cache[$0.localIdentifier] == nil && queued.insert($0.localIdentifier).inserted }
        lock.unlock()
        guard !fresh.isEmpty else { return }
        queue.async { self.process(fresh) }
    }

    /// 전부 다시 분류
    func reset() {
        lock.lock()
        // 다 지우므로 저장해 둔 것은 더 읽지 않음
        cacheLoaded = true
        cache = [:]
        stats = [:]
        lock.unlock()
        queue.async {
            ImportProbe.reenable()
            self.save()
            self.onProgress?()
        }
    }

    private func process(_ assets: [PHAsset]) {
        var last = Date()
        var n = 0
        for asset in assets {
            autoreleasepool {
                let entry = classify(asset)
                lock.lock()
                loadCacheIfNeeded()
                cache[asset.localIdentifier] = entry
                queued.remove(asset.localIdentifier)
                lock.unlock()
            }
            n += 1
            if n % 2000 == 0 || Date().timeIntervalSince(last) > 5 {
                last = Date()
                save()
                onProgress?()
            }
        }
        ImportProbe.endBatch()
        save()
        onProgress?()
    }

    private func save() {
        // 안 읽은 채로 저장하면 저장해 둔 것을 빈 것으로 덮으므로 먼저 읽음
        lock.lock(); loadCacheIfNeeded(); let copy = cache; lock.unlock()
        if let data = try? JSONEncoder().encode(copy) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func note(_ key: String) {
        lock.lock(); stats[key, default: 0] += 1; lock.unlock()
    }

    // MARK: - 판별

    private func classify(_ asset: PHAsset) -> Entry {
        let resources = PHAssetResource.assetResources(for: asset)
        let isVideo = asset.mediaType == .video
        let primaryType: PHAssetResourceType = isVideo ? .video : .photo
        let primary = resources.first { $0.type == primaryType } ?? resources.first
        let name = primary?.originalFilename ?? ""
        let uti = primary?.uniformTypeIdentifier ?? ""

        if isVideo && name.hasPrefix("RPReplay") {
            note("rule:recording")
            return Entry(cat: .recording, app: nil)
        }

        // 1) 사진 앱이 기록해 둔 출처 (있을 때만)
        if let info = ImportProbe.read(asset) {
            let bundle = info.bundle ?? ""
            if info.by != nil || !bundle.isEmpty {
                note("import:by=\(info.by.map { String($0) } ?? "-") \(bundle.isEmpty ? "-" : bundle)")
            }
            if bundle == "com.apple.camera" {
                return Entry(cat: .camera, app: nil)
            }
            if !bundle.isEmpty {
                if let apple = appleSources[bundle] {
                    return Entry(cat: .saved, app: apple)
                }
                if !bundle.hasPrefix("com.apple.") {
                    let display = (info.name?.isEmpty == false) ? info.name! : bundle
                    return Entry(cat: .saved, app: display)
                }
            }
            if let by = info.by, by == 1 || by == 2 {
                return Entry(cat: .camera, app: nil)
            }
        }

        // 2) 사진 종류·파일 형식으로 추정
        if isVideo {
            let sub = asset.mediaSubtypes
            if sub.contains(.videoHighFrameRate) || sub.contains(.videoTimelapse) || sub.contains(.videoCinematic) {
                note("rule:video-subtype")
                return Entry(cat: .camera, app: nil)
            }
            if name.range(of: #"^IMG_E?\d{4,}\.MOV$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                note("rule:video-name")
                return Entry(cat: .camera, app: nil)
            }
            note("rule:video-saved")
            return Entry(cat: .saved, app: nil)
        }

        if resources.contains(where: { $0.type == .pairedVideo }) {
            note("rule:live")
            return Entry(cat: .camera, app: nil)
        }
        let sub = asset.mediaSubtypes
        if sub.contains(.photoLive) || sub.contains(.photoHDR) || sub.contains(.photoPanorama) || sub.contains(.photoDepthEffect) {
            note("rule:photo-subtype")
            return Entry(cat: .camera, app: nil)
        }
        if let type = UTType(uti) {
            if type.conforms(to: .heic) || type.conforms(to: .heif) || type.conforms(to: .rawImage) {
                note("rule:heic-raw")
                return Entry(cat: .camera, app: nil)
            }
            if type.conforms(to: .jpeg), let res = primary {
                if let apple = jpegMadeByApple(res) {
                    note(apple ? "rule:jpeg-apple" : "rule:jpeg-other")
                    return Entry(cat: apple ? .camera : .saved, app: nil)
                }
                // 원본이 기기에 없음(iCloud) → 위치 정보가 있으면 찍은 사진으로 봄
                note("rule:jpeg-unread")
                return Entry(cat: asset.location != nil ? .camera : .saved, app: nil)
            }
        }
        note("rule:other-saved")
        return Entry(cat: .saved, app: nil)
    }

    /// JPEG 앞부분만 읽어 촬영 기기 제조사가 Apple 인지 확인. 못 읽으면 nil
    private func jpegMadeByApple(_ resource: PHAssetResource) -> Bool? {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false
        let limit = 256 * 1024
        let buffer = Box(Data())
        let bufferLock = NSLock()
        let done = DispatchSemaphore(value: 0)

        let request = PHAssetResourceManager.default().requestData(for: resource, options: options, dataReceivedHandler: { chunk in
            bufferLock.lock()
            let before = buffer.value.count
            if before < limit { buffer.value.append(chunk) }
            let reached = before < limit && buffer.value.count >= limit
            bufferLock.unlock()
            if reached { done.signal() }
        }, completionHandler: { _ in
            done.signal()
        })
        _ = done.wait(timeout: .now() + 4)
        PHAssetResourceManager.default().cancelDataRequest(request)

        bufferLock.lock()
        let data = buffer.value
        bufferLock.unlock()
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let make = (tiff?[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        return make.caseInsensitiveCompare("Apple") == .orderedSame
    }
}
