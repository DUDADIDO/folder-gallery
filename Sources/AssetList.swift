import Foundation
import Photos

/// 날짜별 묶음 (보관함·미분류 격자의 머리글). range 는 목록 안의 차례
typealias DaySections = [(day: Date, range: Range<Int>)]

/// 사진 목록. 순정 사진 앱처럼 필요할 때 필요한 만큼만 읽음:
/// 보관함·사진 앱 앨범·동영상·즐겨찾기는 PHFetchResult 그대로 (전체를 배열로 꺼내지 않음),
/// 자동 분류 앨범(카메라·저장한 사진·앱별…)과 미분류는 아직 배열 (Library 가 뒤에서 만듦).
/// 뒤집은 목록(오래된 순)은 같은 저장소를 차례만 바꿔 읽음.
/// version 은 들어 있는 사진이나 순서가 바뀔 때만 바뀜. 즐겨찾기·편집처럼 내용만 바뀌면 그대로지만
/// 새 목록은 새 PHAsset 을 줌. 한 번 만든 목록은 바뀌지 않으므로 어느 줄에서 읽어도 됨
final class AssetList {
    /// 배열 목록의 ID → 차례 (저장소 차례). 뒤집은 목록과 같이 씀.
    /// 보통 Library 가 뒤에서 미리 만들어 둠. 없으면 처음 필요할 때 한 번 만듦
    private final class IDIndex {
        private let lock = NSLock()
        private var map: [String: Int]?

        init(_ map: [String: Int]?) {
            self.map = map
        }

        func index(of id: String, in items: [PHAsset]) -> Int? {
            lock.lock(); defer { lock.unlock() }
            if map == nil {
                var built: [String: Int] = [:]
                built.reserveCapacity(items.count)
                for (index, asset) in items.enumerated() {
                    built[asset.localIdentifier] = index
                }
                map = built
            }
            return map?[id]
        }
    }

    private let fetch: PHFetchResult<PHAsset>?
    private let items: [PHAsset]
    private let ids: IDIndex
    private let isReversed: Bool
    /// 들어 있는 사진·순서가 같으면 같은 값 (같은 목록인지 사진을 하나하나 비교하지 않고 알 수 있게)
    let version: Int

    static let empty = AssetList(array: [], version: 0)

    init(fetch: PHFetchResult<PHAsset>, version: Int) {
        self.fetch = fetch
        items = []
        ids = IDIndex(nil)
        isReversed = false
        self.version = version
    }

    init(array: [PHAsset], version: Int, idMap: [String: Int]? = nil) {
        fetch = nil
        items = array
        ids = IDIndex(idMap)
        isReversed = false
        self.version = version
    }

    private init(fetch: PHFetchResult<PHAsset>?, items: [PHAsset], ids: IDIndex, reversed: Bool, version: Int) {
        self.fetch = fetch
        self.items = items
        self.ids = ids
        self.isReversed = reversed
        self.version = version
    }

    /// 배열 목록: ID → 차례와 version(ID 들의 해시)을 한 번 훑어서 같이 만듦 (Library 의 work 줄에서)
    static func make(_ array: [PHAsset]) -> AssetList {
        var hasher = Hasher()
        var map: [String: Int] = [:]
        map.reserveCapacity(array.count)
        for (index, asset) in array.enumerated() {
            let id = asset.localIdentifier
            hasher.combine(id)
            map[id] = index
        }
        hasher.combine(array.count)
        return AssetList(array: array, version: hasher.finalize(), idMap: map)
    }

    var count: Int {
        if let fetch { return fetch.count }
        return items.count
    }

    var isEmpty: Bool { count == 0 }

    /// 보이는 차례 → 저장소 차례 (뒤집은 목록이면 거꾸로. 거꾸로의 거꾸로는 그대로라 반대 방향에도 씀)
    private func storageIndex(_ index: Int) -> Int {
        isReversed ? count - 1 - index : index
    }

    subscript(index: Int) -> PHAsset {
        let at = storageIndex(index)
        if let fetch { return fetch.object(at: at) }
        return items[at]
    }

    var first: PHAsset? { isEmpty ? nil : self[0] }
    var last: PHAsset? { isEmpty ? nil : self[count - 1] }

    /// 같은 저장소를 거꾸로 보는 목록 (복사하지 않음). version 은 그대로
    func reversed() -> AssetList {
        AssetList(fetch: fetch, items: items, ids: ids, reversed: !isReversed, version: version)
    }

    func index(of asset: PHAsset) -> Int? {
        if let fetch {
            let found = fetch.index(of: asset)
            guard found != NSNotFound, found >= 0, found < fetch.count else { return nil }
            return storageIndex(found)
        }
        guard let found = ids.index(of: asset.localIdentifier, in: items) else { return nil }
        return storageIndex(found)
    }

    /// ID 로 차례 찾기. near 를 주면 그 둘레(±2)를 먼저 봄 (넘기기처럼 바로 옆을 찾을 때 훑지 않게)
    func index(ofID id: String, near hint: Int? = nil) -> Int? {
        let total = count
        if let hint {
            for delta in [0, 1, -1, 2, -2] {
                let at = hint + delta
                if at >= 0, at < total, self[at].localIdentifier == id { return at }
            }
        }
        if fetch != nil {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
            return index(of: asset)
        }
        guard let found = ids.index(of: id, in: items) else { return nil }
        return storageIndex(found)
    }

    /// 여러 ID 의 차례를 한 번에 (고른 사진 되살리기). 없는 것은 뺌
    func indexes(ofIDs identifiers: [String]) -> [Int] {
        guard !identifiers.isEmpty else { return [] }
        if fetch != nil {
            var result: [Int] = []
            PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil).enumerateObjects { asset, _, _ in
                if let at = self.index(of: asset) { result.append(at) }
            }
            return result
        }
        return identifiers.compactMap { id in
            self.ids.index(of: id, in: self.items).map { self.storageIndex($0) }
        }
    }

    /// 전부 배열로 (정리하기처럼 정말 전부가 필요할 때만)
    func array() -> [PHAsset] {
        var result: [PHAsset]
        if let fetch {
            result = fetch.count > 0 ? fetch.objects(at: IndexSet(integersIn: 0..<fetch.count)) : []
        } else {
            result = items
        }
        if isReversed { result.reverse() }
        return result
    }

    /// 날짜별 묶음 (최신순 목록). limit 을 주면 그 앞까지만 날짜를 정확히 나누고,
    /// 나머지는 한 묶음으로 둠 (머리글은 그 첫 사진의 날 — 경계도 보통 날짜 머리글처럼 보임)
    func daySections(limit: Int? = nil) -> DaySections {
        let total = count
        guard total > 0 else { return [] }
        let end = min(total, limit ?? total)
        let calendar = Calendar.current
        var result: DaySections = []
        var start = 0
        var current: Date?
        var dayEnd = Date.distantPast   // current 날의 끝. 최신순이라 같은 날이 이어서 나옴
        for index in 0..<end {
            let date = self[index].creationDate ?? .distantPast
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
        if let current { result.append((current, start..<end)) }
        if end < total {
            let day = calendar.startOfDay(for: self[end].creationDate ?? .distantPast)
            if let lastSection = result.last, lastSection.day == day {
                // 경계가 같은 날 한가운데면 그 날에 이어 붙임 (같은 날 머리글이 두 번 나오지 않게)
                result[result.count - 1] = (day, lastSection.range.lowerBound..<total)
            } else {
                result.append((day, end..<total))
            }
        }
        return result
    }
}
