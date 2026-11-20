import Foundation
import Photos

/// 날짜별 묶음 (보관함·미분류 격자의 머리글). range 는 목록 안의 차례
typealias DaySections = [(day: Date, range: Range<Int>)]

/// 사진 목록. 순정 사진 앱처럼 필요할 때 필요한 만큼만 읽음:
/// 보관함·사진 앱 앨범·동영상·즐겨찾기는 PHFetchResult 그대로 (전체를 배열로 꺼내지 않음),
/// 자동 분류 앨범(카메라·저장한 사진·앱별…)과 미분류는 배열 (Library 가 뒤에서 만듦),
/// 켤 때는 지난번에 저장해 둔 사진 ID 목록 (보이는 부분만 조금씩 사진 앱에서 읽음).
/// 뒤집은 목록(오래된 순)은 같은 저장소를 차례만 바꿔 읽음.
/// version 은 들어 있는 사진이나 순서가 바뀔 때만 바뀜. 즐겨찾기·편집처럼 내용만 바뀌면 그대로지만
/// 새 목록은 새 PHAsset 을 줌. 한 번 만든 목록은 바뀌지 않으므로 어느 줄에서 읽어도 됨
final class AssetList {
    /// ID → 차례 (저장소 차례). 뒤집은 목록과 같이 씀.
    /// 배열 목록은 보통 Library 가 뒤에서 미리 만들어 둠. 없으면 처음 필요할 때 한 번 만듦
    private final class IDIndex {
        private let lock = NSLock()
        private var map: [String: Int]?

        init(_ map: [String: Int]?) {
            self.map = map
        }

        func index(of id: String, build: () -> [String: Int]) -> Int? {
            lock.lock(); defer { lock.unlock() }
            if map == nil { map = build() }
            return map?[id]
        }
    }

    /// 사진 ID 목록 (켤 때 저장해 둔 것). 사진은 500장씩 필요할 때 사진 앱에서 읽어 둠.
    /// 그사이 지워진 사진은 차례를 밀 수 없어서 옆 사진으로 대신함 (곧 전체 목록이 바로잡음)
    private final class IDStore {
        static let chunkSize = 500
        let ids: [String]
        /// 읽을 수 있는 사진이 하나도 없을 때 대신 줄 사진 (보관함의 아무 사진)
        let placeholder: PHAsset
        private let lock = NSLock()
        private var chunks: [Int: [PHAsset?]] = [:]

        init(ids: [String], placeholder: PHAsset) {
            self.ids = ids
            self.placeholder = placeholder
        }

        private var chunkCount: Int {
            (ids.count + IDStore.chunkSize - 1) / IDStore.chunkSize
        }

        /// 한 묶음(최대 500장)만 사진 앱에서 읽음. 읽는 동안은 잠그지 않음 (두 번 읽어도 결과는 같음)
        func chunk(_ number: Int) -> [PHAsset?] {
            lock.lock()
            if let cached = chunks[number] {
                lock.unlock()
                return cached
            }
            lock.unlock()
            let start = number * IDStore.chunkSize
            let end = min(ids.count, start + IDStore.chunkSize)
            guard number >= 0, start < end else { return [] }
            let slice = Array(ids[start..<end])
            var byID: [String: PHAsset] = [:]
            PHAsset.fetchAssets(withLocalIdentifiers: slice, options: nil).enumerateObjects { asset, _, _ in
                byID[asset.localIdentifier] = asset
            }
            let resolved = slice.map { byID[$0] }
            lock.lock()
            chunks[number] = resolved
            lock.unlock()
            return resolved
        }

        /// 저장소 차례의 사진. 없어진 사진이면 가장 가까운 사진
        func asset(at index: Int) -> PHAsset {
            let size = IDStore.chunkSize
            let number = index / size
            let local = chunk(number)
            let offset = index - number * size
            if offset >= 0, offset < local.count, let asset = local[offset] { return asset }
            if local.count > 1 {
                for delta in 1..<local.count {
                    if offset - delta >= 0, offset - delta < local.count, let asset = local[offset - delta] { return asset }
                    if offset + delta >= 0, offset + delta < local.count, let asset = local[offset + delta] { return asset }
                }
            }
            // 묶음이 통째로 없어짐: 옆 묶음에서
            let total = chunkCount
            if total > 1 {
                for delta in 1..<total {
                    if number - delta >= 0, let asset = chunk(number - delta).last(where: { $0 != nil }) ?? nil { return asset }
                    if number + delta < total, let asset = chunk(number + delta).first(where: { $0 != nil }) ?? nil { return asset }
                }
            }
            return placeholder
        }

        /// 전부 (없어진 사진은 뺌)
        func allAssets() -> [PHAsset] {
            var result: [PHAsset] = []
            result.reserveCapacity(ids.count)
            for number in 0..<chunkCount {
                result.append(contentsOf: chunk(number).compactMap { $0 })
            }
            return result
        }
    }

    private let fetch: PHFetchResult<PHAsset>?
    private let items: [PHAsset]
    private let store: IDStore?
    private let ids: IDIndex
    private let isReversed: Bool
    /// 들어 있는 사진·순서가 같으면 같은 값 (같은 목록인지 사진을 하나하나 비교하지 않고 알 수 있게)
    let version: Int

    static let empty = AssetList(array: [], version: 0)

    init(fetch: PHFetchResult<PHAsset>, version: Int) {
        self.fetch = fetch
        items = []
        store = nil
        ids = IDIndex(nil)
        isReversed = false
        self.version = version
    }

    init(array: [PHAsset], version: Int, idMap: [String: Int]? = nil) {
        fetch = nil
        items = array
        store = nil
        ids = IDIndex(idMap)
        isReversed = false
        self.version = version
    }

    private init(fetch: PHFetchResult<PHAsset>?, items: [PHAsset], store: IDStore?, ids: IDIndex, reversed: Bool, version: Int) {
        self.fetch = fetch
        self.items = items
        self.store = store
        self.ids = ids
        self.isReversed = reversed
        self.version = version
    }

    /// 배열 목록: ID → 차례와 version(ID 들의 해시)을 한 번 훑어서 같이 만듦 (Library 의 work 줄에서).
    /// version 계산은 make(identifiers:) 와 똑같아야 함 (같은 사진들이면 같은 version)
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

    /// 사진 ID 목록 (켤 때 저장해 둔 것). 사진은 읽지 않음. version 은 make 와 같은 방법
    static func make(identifiers: [String], placeholder: PHAsset) -> AssetList {
        var hasher = Hasher()
        for id in identifiers {
            hasher.combine(id)
        }
        hasher.combine(identifiers.count)
        return AssetList(fetch: nil, items: [], store: IDStore(ids: identifiers, placeholder: placeholder),
                         ids: IDIndex(nil), reversed: false, version: hasher.finalize())
    }

    /// 사진 앱에서 바로 읽는 목록인지 (아니면 배열·ID 목록: 지우거나 옮길 때 Library 가 직접 뺌)
    var isFetchBacked: Bool { fetch != nil }

    var count: Int {
        if let fetch { return fetch.count }
        if let store { return store.ids.count }
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
        if let store { return store.asset(at: at) }
        return items[at]
    }

    /// 그 차례의 사진 ID (ID 목록은 사진을 읽지 않음)
    private func identifier(at index: Int) -> String {
        if let store { return store.ids[storageIndex(index)] }
        return self[index].localIdentifier
    }

    var first: PHAsset? { isEmpty ? nil : self[0] }
    var last: PHAsset? { isEmpty ? nil : self[count - 1] }

    /// 같은 저장소를 거꾸로 보는 목록 (복사하지 않음). version 은 그대로
    func reversed() -> AssetList {
        AssetList(fetch: fetch, items: items, store: store, ids: ids, reversed: !isReversed, version: version)
    }

    /// 저장소의 ID → 차례 (처음 필요할 때 한 번 만듦)
    private func storageIndex(ofID id: String) -> Int? {
        if let store {
            return ids.index(of: id) {
                var built: [String: Int] = [:]
                built.reserveCapacity(store.ids.count)
                for (index, value) in store.ids.enumerated() where built[value] == nil {
                    built[value] = index
                }
                return built
            }
        }
        let items = self.items
        return ids.index(of: id) {
            var built: [String: Int] = [:]
            built.reserveCapacity(items.count)
            for (index, asset) in items.enumerated() {
                built[asset.localIdentifier] = index
            }
            return built
        }
    }

    func index(of asset: PHAsset) -> Int? {
        if let fetch {
            let found = fetch.index(of: asset)
            guard found != NSNotFound, found >= 0, found < fetch.count else { return nil }
            return storageIndex(found)
        }
        guard let found = storageIndex(ofID: asset.localIdentifier) else { return nil }
        return storageIndex(found)
    }

    /// ID 로 차례 찾기. near 를 주면 그 둘레(±2)를 먼저 봄 (넘기기처럼 바로 옆을 찾을 때 훑지 않게)
    func index(ofID id: String, near hint: Int? = nil) -> Int? {
        let total = count
        if let hint {
            for delta in [0, 1, -1, 2, -2] {
                let at = hint + delta
                if at >= 0, at < total, identifier(at: at) == id { return at }
            }
        }
        if fetch != nil {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
            return index(of: asset)
        }
        guard let found = storageIndex(ofID: id) else { return nil }
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
            self.storageIndex(ofID: id).map { self.storageIndex($0) }
        }
    }

    /// 전부 배열로 (정리하기처럼 정말 전부가 필요할 때만). ID 목록이면 없어진 사진은 뺌
    func array() -> [PHAsset] {
        var result: [PHAsset]
        if let fetch {
            result = fetch.count > 0 ? fetch.objects(at: IndexSet(integersIn: 0..<fetch.count)) : []
        } else if let store {
            result = store.allAssets()
        } else {
            result = items
        }
        if isReversed { result.reverse() }
        return result
    }

    /// 저장할 사진 ID (저장소 차례, 뒤집었으면 보이는 차례). 사진 앱에서 바로 읽는 목록이면 nil
    func identifiers() -> [String]? {
        guard fetch == nil else { return nil }
        var result = store?.ids ?? items.map(\.localIdentifier)
        if isReversed { result.reverse() }
        return result
    }

    /// 이 ID 들을 뺀 새 목록 (배열·ID 목록만. version 은 make 와 같은 방법). 뺄 것이 없으면 nil
    func removing(_ drop: Set<String>) -> AssetList? {
        guard fetch == nil, !drop.isEmpty else { return nil }
        let result: AssetList
        if let store {
            let kept = store.ids.filter { !drop.contains($0) }
            guard kept.count != store.ids.count else { return nil }
            result = AssetList.make(identifiers: kept, placeholder: store.placeholder)
        } else {
            let kept = items.filter { !drop.contains($0.localIdentifier) }
            guard kept.count != items.count else { return nil }
            result = AssetList.make(kept)
        }
        return isReversed ? result.reversed() : result
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
