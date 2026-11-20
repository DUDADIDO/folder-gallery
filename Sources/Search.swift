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

    /// 추천: 지난 계절 ("2025년 가을")
    static func seasonSuggestion(now: Date = Date()) -> String {
        let calendar = Calendar.current
        var c = calendar.dateComponents([.year, .month], from: calendar.date(byAdding: .month, value: -3, to: now) ?? now)
        let month = c.month ?? 1
        let name = [3, 4, 5].contains(month) ? "봄" : ([6, 7, 8].contains(month) ? "여름" : ([9, 10, 11].contains(month) ? "가을" : "겨울"))
        if name == "겨울", month <= 2 { c.year = (c.year ?? 0) - 1 }
        return "\(c.year ?? 0)년 \(name)"
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

        // 계절: "2025년 가을", "가을"
        let seasons: [(String, [Int])] = [("봄", [3, 4, 5]), ("여름", [6, 7, 8]), ("가을", [9, 10, 11]), ("겨울", [12, 1, 2])]
        if let season = seasons.first(where: { text.hasSuffix($0.0) }) {
            let yearText = text.dropLast(season.0.count).filter(\.isNumber)
            let year = Int(yearText)
            let title = (year.map { "\($0)년 " } ?? "") + season.0
            return DateMatch(title: title) { date in
                let c = calendar.dateComponents([.year, .month], from: date)
                guard let month = c.month, season.1.contains(month) else { return false }
                guard let year else { return true }
                // 겨울은 12월이 그해, 1·2월은 다음 해
                let seasonYear = (season.0 == "겨울" && month <= 2) ? (c.year ?? 0) - 1 : (c.year ?? 0)
                return seasonYear == year
            }
        }

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
            DispatchQueue.main.async { [weak self] in self?.assets = all; self?.refreshHome() }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchBar.becomeFirstResponder()
        refreshHome()
    }

    // MARK: 첫 화면 (순정: 최근 항목 사진 카드 + 추천 칩)

    private let homeHeader = SearchHomeHeader()

    private func refreshHome() {
        guard showingRecent else { tableView.tableHeaderView = nil; return }
        let recent = PhotoSearch.recent.prefix(6)
        let folders = Library.shared.snapshot.folders
        let current = assets
        let suggestion = PhotoSearch.seasonSuggestion()
        DispatchQueue.global(qos: .userInitiated).async {
            let cards: [(String, PHAsset?)] = recent.map { text in
                let hit = PhotoSearch.search(text, assets: current, folders: folders).first
                return (text, hit?.assets.last ?? hit.flatMap { $0.folderID }.flatMap { Library.shared.snapshot.cover($0) })
            }
            let hasSuggestion = !PhotoSearch.search(suggestion, assets: current, folders: []).isEmpty
            DispatchQueue.main.async { [weak self] in
                guard let self, self.showingRecent else { return }
                self.homeHeader.configure(cards: cards, suggestions: hasSuggestion ? [suggestion] : [])
                self.homeHeader.onPick = { [weak self] text in
                    guard let self else { return }
                    self.searchBar.text = text
                    self.searchBar(self.searchBar, textDidChange: text)
                }
                self.homeHeader.onClear = { [weak self] in
                    PhotoSearch.recent = []
                    self?.refreshHome()
                    self?.tableView.reloadData()
                }
                let width = self.tableView.bounds.width
                self.homeHeader.frame = CGRect(x: 0, y: 0, width: width, height: self.homeHeader.preferredHeight)
                self.tableView.tableHeaderView = self.homeHeader
            }
        }
    }

    private var showingRecent: Bool { (searchBar.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            refreshHome()
        } else {
            tableView.tableHeaderView = nil
        }
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
        if showingRecent { return nil }
        return hits.isEmpty ? "결과 없음" : "결과"
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        showingRecent ? 0 : hits.count
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

/// 검색 첫 화면 머리: "최근 항목 [지우기]" + 사진 카드 줄 + 추천 칩
final class SearchHomeHeader: UIView {
    var onPick: ((String) -> Void)?
    var onClear: (() -> Void)?
    private let title = UILabel()
    private let clear = UIButton(type: .system)
    private let scroll = UIScrollView()
    private let chips = UIStackView()
    private var hasCards = false

    var preferredHeight: CGFloat { (hasCards ? 44 + 132 : 0) + (chips.arrangedSubviews.isEmpty ? 0 : 60) + 8 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        title.text = "최근 항목"
        title.font = .systemFont(ofSize: 22, weight: .bold)
        addSubview(title)
        var config = UIButton.Configuration.gray()
        config.title = "지우기"
        config.cornerStyle = .capsule
        config.buttonSize = .small
        clear.configuration = config
        clear.addAction(UIAction { [weak self] _ in self?.onClear?() }, for: .primaryActionTriggered)
        addSubview(clear)
        scroll.showsHorizontalScrollIndicator = false
        addSubview(scroll)
        chips.axis = .horizontal
        chips.spacing = 8
        addSubview(chips)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(cards: [(String, PHAsset?)], suggestions: [String]) {
        scroll.subviews.forEach { $0.removeFromSuperview() }
        hasCards = !cards.isEmpty
        title.isHidden = !hasCards
        clear.isHidden = !hasCards
        var x: CGFloat = 16
        for (text, asset) in cards {
            let card = UIButton(type: .custom)
            card.frame = CGRect(x: x, y: 0, width: 132, height: 132)
            card.layer.cornerRadius = 16
            card.layer.cornerCurve = .continuous
            card.clipsToBounds = true
            card.backgroundColor = .secondarySystemBackground
            let image = UIImageView(frame: card.bounds)
            image.contentMode = .scaleAspectFill
            image.clipsToBounds = true
            card.addSubview(image)
            let shade = CAGradientLayer()
            shade.frame = CGRect(x: 0, y: 72, width: 132, height: 60)
            shade.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.5).cgColor]
            card.layer.addSublayer(shade)
            let label = UILabel(frame: CGRect(x: 10, y: 100, width: 112, height: 22))
            label.text = "‘\(text)’"
            label.font = .systemFont(ofSize: 15, weight: .semibold)
            label.textColor = .white
            card.addSubview(label)
            if let asset {
                Thumbs.manager.requestImage(for: asset, targetSize: CGSize(width: 300, height: 300), contentMode: .aspectFill,
                                            options: Thumbs.options) { result, _ in image.image = result }
            }
            card.addAction(UIAction { [weak self] _ in self?.onPick?(text) }, for: .primaryActionTriggered)
            scroll.addSubview(card)
            x += 140
        }
        scroll.contentSize = CGSize(width: x + 8, height: 132)
        chips.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for text in suggestions {
            var config = UIButton.Configuration.filled()
            config.title = text
            config.baseBackgroundColor = .secondarySystemBackground
            config.baseForegroundColor = .label
            config.cornerStyle = .capsule
            let chip = UIButton(configuration: config)
            chip.layer.shadowColor = UIColor.black.cgColor
            chip.layer.shadowOpacity = 0.12
            chip.layer.shadowRadius = 8
            chip.layer.shadowOffset = CGSize(width: 0, height: 2)
            chip.addAction(UIAction { [weak self] _ in self?.onPick?(text) }, for: .primaryActionTriggered)
            chips.addArrangedSubview(chip)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var y: CGFloat = 0
        if hasCards {
            title.frame = CGRect(x: 16, y: 4, width: 200, height: 30)
            clear.sizeToFit()
            clear.frame = CGRect(x: bounds.width - 16 - clear.bounds.width, y: 4, width: clear.bounds.width, height: 30)
            y = 44
            scroll.frame = CGRect(x: 0, y: y, width: bounds.width, height: 132)
            y += 132
        }
        chips.frame = CGRect(x: 16, y: y + 16, width: chips.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width, height: 36)
    }
}
