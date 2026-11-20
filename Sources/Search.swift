import CoreLocation
import Photos
import UIKit

// MARK: - 검색 (순정 iOS 27 짜임: 큰 "검색" 제목 · 최근 항목 · 아래쪽 검색창)
// 사진 속 내용(사람·사물)으로 찾는 것은 공개 API 가 없어서, 날짜 · 앨범 · 종류 · 장소 이름으로 찾음

/// 검색 결과 한 덩어리
struct SearchHit {
    enum Kind { case album, date, type, place }
    let kind: Kind
    let title: String
    let subtitle: String
    /// 앨범이면 폴더 ID (누르면 그 앨범), 아니면 사진들
    let folderID: String?
    let assets: [PHAsset]
}

enum PhotoSearch {
    private static let recentKey = "recentSearches"

    static var recent: [String] {
        get { UserDefaults.standard.stringArray(forKey: recentKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(10)), forKey: recentKey) }
    }

    static func remember(_ text: String) {
        var list = recent.filter { $0 != text }
        list.insert(text, at: 0)
        recent = list
    }

    /// assets 는 보관함 전체 (오래된 것이 앞)
    static func search(_ raw: String, assets: [PHAsset], folders: [Folder]) -> [SearchHit] {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        var hits: [SearchHit] = []
        let lower = text.lowercased()

        // 앨범 이름
        for folder in folders where folder.title.lowercased().contains(lower) {
            let count = Library.shared.snapshot.items[folder.id]?.count ?? 0
            hits.append(SearchHit(kind: .album, title: folder.title, subtitle: "앨범 · \(count.formatted())개의 항목",
                                  folderID: folder.id, assets: []))
        }

        // 종류
        let types: [(String, [String], (PHAsset) -> Bool)] = [
            ("동영상", ["동영상", "비디오", "영상", "video"], { $0.mediaType == .video }),
            ("스크린샷", ["스크린샷", "screenshot", "캡처"], { $0.mediaSubtypes.contains(.photoScreenshot) }),
            ("즐겨찾기", ["즐겨찾기", "좋아요", "favorite"], { $0.isFavorite }),
            ("Live Photo", ["live", "라이브"], { $0.mediaSubtypes.contains(.photoLive) }),
            ("인물 사진", ["인물", "portrait"], { $0.mediaSubtypes.contains(.photoDepthEffect) }),
            ("파노라마", ["파노라마", "panorama"], { $0.mediaSubtypes.contains(.photoPanorama) }),
        ]
        for (name, words, test) in types where words.contains(where: { $0.hasPrefix(lower) || lower.hasPrefix($0) }) {
            let found = assets.filter(test)
            if !found.isEmpty {
                hits.append(SearchHit(kind: .type, title: name, subtitle: "\(found.count.formatted())개의 항목", folderID: nil, assets: found))
            }
        }

        // 날짜: 2025년 · 9월 · 26일 · 2025년 9월 · 오늘 · 어제 · 올해 · 작년
        if let match = dateMatcher(text) {
            let found = assets.filter { $0.creationDate.map(match.test) ?? false }
            if !found.isEmpty {
                hits.append(SearchHit(kind: .date, title: match.title, subtitle: "\(found.count.formatted())개의 항목", folderID: nil, assets: found))
            }
        }

        // 장소: 이미 알아 둔 장소 이름에서만 (새로 알아보지는 않음)
        var places: [String: [PHAsset]] = [:]
        for asset in assets {
            guard let location = asset.location, let name = PlaceNames.shared.cachedName(location),
                  name.lowercased().contains(lower) else { continue }
            places[name, default: []].append(asset)
        }
        for (name, found) in places.sorted(by: { $0.value.count > $1.value.count }).prefix(8) {
            hits.append(SearchHit(kind: .place, title: name, subtitle: "장소 · \(found.count.formatted())개의 항목", folderID: nil, assets: found))
        }
        return hits
    }

    private struct DateMatch {
        let title: String
        let test: (Date) -> Bool
    }

    private static func dateMatcher(_ text: String) -> DateMatch? {
        let calendar = Calendar.current
        let now = Date()
        let thisYear = calendar.component(.year, from: now)
        if text == "오늘" { return DateMatch(title: "오늘") { calendar.isDateInToday($0) } }
        if text == "어제" { return DateMatch(title: "어제") { calendar.isDateInYesterday($0) } }
        if text == "올해" { return DateMatch(title: "\(thisYear)년") { calendar.component(.year, from: $0) == thisYear } }
        if text == "작년" { return DateMatch(title: "\(thisYear - 1)년") { calendar.component(.year, from: $0) == thisYear - 1 } }

        func number(before suffix: String) -> Int? {
            guard let range = text.range(of: "(\\d+)\\s*" + suffix, options: .regularExpression) else { return nil }
            return Int(text[range].filter(\.isNumber))
        }
        var year = number(before: "년")
        let month = number(before: "월")
        let day = number(before: "일")
        // "2025" 처럼 숫자만
        if year == nil, month == nil, day == nil, let value = Int(text), value >= 1900, value <= thisYear + 1 { year = value }
        guard year != nil || month != nil || day != nil else { return nil }
        if let month, !(1...12).contains(month) { return nil }
        if let day, !(1...31).contains(day) { return nil }
        var parts: [String] = []
        if let year { parts.append("\(year)년") }
        if let month { parts.append("\(month)월") }
        if let day { parts.append("\(day)일") }
        return DateMatch(title: parts.joined(separator: " ")) { date in
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return (year == nil || c.year == year) && (month == nil || c.month == month) && (day == nil || c.day == day)
        }
    }
}

final class SearchViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let searchBar = UISearchBar()
    private var hits: [SearchHit] = []
    private var assets: [PHAsset] = []
    private var searchToken = 0

    /// 앨범 결과를 누름 (그 앨범을 엶)
    var onOpenFolder: ((String) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "검색"
        navigationItem.largeTitleDisplayMode = .always
        navigationController?.navigationBar.prefersLargeTitles = true
        // 따로 띄웠을 때만 닫기 (검색 탭 안에서는 없음)
        if navigationController?.presentingViewController != nil {
            navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            })
        }

        // 순정 검색 화면처럼 흰 바탕
        tableView.backgroundColor = .systemBackground
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .interactive
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "hit")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        // 순정처럼 검색창은 아래 (키보드 바로 위)
        searchBar.placeholder = "보관함 검색..."
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: searchBar.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            searchBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -4),
        ])

        let list = Library.shared.list(for: "all", newestFirst: false)
        DispatchQueue.global(qos: .userInitiated).async {
            let all = list.array()
            DispatchQueue.main.async { [weak self] in self?.assets = all }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchBar.becomeFirstResponder()
    }

    private var showingRecent: Bool { (searchBar.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        searchToken += 1
        let token = searchToken
        let folders = Library.shared.snapshot.folders
        let current = assets
        DispatchQueue.global(qos: .userInitiated).async {
            let found = PhotoSearch.search(searchText, assets: current, folders: folders)
            DispatchQueue.main.async { [weak self] in
                guard let self, token == self.searchToken else { return }
                self.hits = found
                self.tableView.reloadData()
            }
        }
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if showingRecent { return PhotoSearch.recent.isEmpty ? nil : "최근 검색" }
        return hits.isEmpty ? "결과 없음" : "결과"
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        showingRecent ? PhotoSearch.recent.count : hits.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "hit", for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        if showingRecent {
            content.text = PhotoSearch.recent[indexPath.row]
            content.image = UIImage(systemName: "clock.arrow.circlepath")
            content.secondaryText = nil
        } else {
            let hit = hits[indexPath.row]
            content.text = hit.title
            content.secondaryText = hit.subtitle
            content.secondaryTextProperties.color = .secondaryLabel
            switch hit.kind {
            case .album: content.image = UIImage(systemName: "rectangle.stack")
            case .date: content.image = UIImage(systemName: "calendar")
            case .type: content.image = UIImage(systemName: "photo.on.rectangle.angled")
            case .place: content.image = UIImage(systemName: "mappin.and.ellipse")
            }
        }
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if showingRecent {
            let text = PhotoSearch.recent[indexPath.row]
            searchBar.text = text
            self.searchBar(searchBar, textDidChange: text)
            return
        }
        let hit = hits[indexPath.row]
        if let text = searchBar.text { PhotoSearch.remember(text) }
        if let folderID = hit.folderID {
            if navigationController?.presentingViewController != nil {
                dismiss(animated: true) { [onOpenFolder] in onOpenFolder?(folderID) }
            } else {
                searchBar.resignFirstResponder()
                onOpenFolder?(folderID)
            }
            return
        }
        navigationController?.pushViewController(SearchResultsViewController(title: hit.title, assets: hit.assets), animated: true)
    }
}

/// 검색 결과 사진 (3칸, 누르면 보기 화면)
final class SearchResultsViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {
    private let assets: [PHAsset]
    private var collectionView: UICollectionView!

    init(title: String, assets: [PHAsset]) {
        self.assets = assets
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 2
        layout.minimumLineSpacing = 2
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(AssetCell.self, forCellWithReuseIdentifier: AssetCell.reuse)
        view.addSubview(collectionView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let side = floor((view.bounds.width - 4) / 3)
        (collectionView.collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize = CGSize(width: side, height: side)
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { assets.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AssetCell.reuse, for: indexPath) as! AssetCell
        let asset = assets[indexPath.item]
        let id = asset.localIdentifier
        cell.assetID = id
        cell.imageView.image = nil
        cell.setDuration(asset.mediaType == .video ? asset.duration : nil)
        cell.setFavorite(asset.isFavorite)
        let scale = traitCollection.displayScale
        let side = view.bounds.width / 3 * scale
        cell.requestID = Thumbs.manager.requestImage(for: asset, targetSize: CGSize(width: side, height: side),
                                                     contentMode: .aspectFill, options: Thumbs.options) { [weak cell] image, _ in
            guard let cell, cell.assetID == id, let image else { return }
            cell.imageView.image = image
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let viewer = ViewerViewController(list: AssetList.make(assets), index: indexPath.item, folderID: "search",
                                          newestFirst: false, sourceAlbumID: nil)
        viewer.fallbackBounds = view.bounds
        navigationController?.pushViewController(viewer, animated: true)
    }
}
