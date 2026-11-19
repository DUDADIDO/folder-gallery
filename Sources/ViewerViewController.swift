import AVFoundation
import AVKit
import CoreLocation
import Photos
import UIKit

/// 사진 한 장 (확대 가능). 영상은 재생 버튼
final class AssetPageViewController: UIViewController, UIScrollViewDelegate {
    let asset: PHAsset
    var onSingleTap: (() -> Void)?

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let playButton = UIButton(type: .system)
    private var requestID: PHImageRequestID = PHInvalidImageRequestID
    private var loadedSize: CGSize = .zero
    private var loadingVideo = false

    /// 확대해서 보는 중인지 (이때는 아래로 쓸어 닫기를 안 함)
    var isZoomed: Bool { scrollView.zoomScale > 1.01 }

    init(asset: PHAsset) {
        self.asset = asset
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if requestID != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(requestID)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.frame = view.bounds
        view.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        imageView.frame = scrollView.bounds
        scrollView.addSubview(imageView)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        singleTap.require(toFail: doubleTap)
        scrollView.addGestureRecognizer(singleTap)

        if asset.mediaType == .video {
            let config = UIImage.SymbolConfiguration(pointSize: 64, weight: .regular)
            playButton.setImage(UIImage(systemName: "play.circle.fill", withConfiguration: config), for: .normal)
            playButton.tintColor = .white
            playButton.layer.shadowColor = UIColor.black.cgColor
            playButton.layer.shadowOpacity = 0.5
            playButton.layer.shadowRadius = 6
            playButton.layer.shadowOffset = .zero
            playButton.addTarget(self, action: #selector(play), for: .touchUpInside)
            playButton.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(playButton)
            NSLayoutConstraint.activate([
                playButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                playButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
            scrollView.maximumZoomScale = 1
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if scrollView.frame.size != view.bounds.size {
            scrollView.zoomScale = 1
            scrollView.frame = view.bounds
            imageView.frame = scrollView.bounds
            scrollView.contentSize = scrollView.bounds.size
        }
        loadImageIfNeeded()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        scrollView.zoomScale = 1
    }

    private func loadImageIfNeeded() {
        let size = view.bounds.size
        guard size.width > 0, size.height > 0, loadedSize != size else { return }
        loadedSize = size
        if requestID != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(requestID)
        }
        // 확대해도 볼 만하게 화면의 2.5배까지
        let scale = traitCollection.displayScale * 2.5
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        requestID = PHImageManager.default().requestImage(for: asset, targetSize: target, contentMode: .aspectFit,
                                                          options: options) { [weak self] image, _ in
            if let image { self?.imageView.image = image }
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        guard asset.mediaType != .video else { return }
        if scrollView.zoomScale > 1.01 {
            scrollView.setZoomScale(1, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let targetScale: CGFloat = 2.5
            let width = scrollView.bounds.width / targetScale
            let height = scrollView.bounds.height / targetScale
            scrollView.zoom(to: CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height), animated: true)
        }
    }

    @objc private func singleTapped() {
        onSingleTap?()
    }

    @objc private func play() {
        guard !loadingVideo else { return }
        loadingVideo = true
        // 무음 스위치가 켜져 있어도 영상 소리가 나게
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.loadingVideo = false
                guard let item, self.presentedViewController == nil else { return }
                let player = AVPlayerViewController()
                player.player = AVPlayer(playerItem: item)
                self.present(player, animated: true) {
                    player.player?.play()
                }
            }
        }
    }
}

/// 세로로 쓸 때만 시작하는 제스처 문지기 (좌우 넘기기·확대와 안 부딪히게)
final class VerticalPanGate: NSObject, UIGestureRecognizerDelegate {
    var canBegin: (() -> Bool)?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: pan.view)
        guard abs(velocity.y) > abs(velocity.x) * 1.5 else { return false }
        return canBegin?() ?? true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // 확대(두 손가락)와는 같이 잡히지 않게
        !(otherGestureRecognizer is UIPinchGestureRecognizer)
    }
}

/// 좌우로 넘겨 보는 화면. 사진 앱처럼 아래로 쓸면 닫히고 위로 쓸면 정보가 나옴
final class ViewerViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    private var assets: [PHAsset]
    private var currentID: String
    private let sourceAlbumID: String?
    private var chromeHidden = false
    private let panGate = VerticalPanGate()
    private weak var pannedView: UIView?   // 쓸기 시작할 때 잡은 사진 화면

    private lazy var shareItem = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(shareCurrent))
    private lazy var favoriteItem = UIBarButtonItem(image: UIImage(systemName: "heart"), style: .plain, target: self, action: #selector(toggleFavorite))
    private lazy var infoItem = UIBarButtonItem(image: UIImage(systemName: "info.circle"), style: .plain, target: self, action: #selector(showInfo))
    private lazy var moreItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: makeMoreMenu())
    private lazy var deleteItem = UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain, target: self, action: #selector(deleteCurrent))

    private let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy. M. d. a h:mm"
        return formatter
    }()

    init(assets: [PHAsset], index: Int, sourceAlbumID: String?) {
        self.assets = assets
        self.currentID = assets.indices.contains(index) ? assets[index].localIdentifier : (assets.first?.localIdentifier ?? "")
        self.sourceAlbumID = sourceAlbumID
        super.init(transitionStyle: .scroll, navigationOrientation: .horizontal, options: [.interPageSpacing: 16])
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never
        dataSource = self
        delegate = self
        let space = { UIBarButtonItem.flexibleSpace() }
        toolbarItems = [shareItem, space(), favoriteItem, space(), infoItem, space(), moreItem, space(), deleteItem]
        if let index = currentIndex {
            setViewControllers([makePage(index)], direction: .forward, animated: false)
        }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        panGate.canBegin = { [weak self] in
            guard let page = self?.viewControllers?.first as? AssetPageViewController else { return false }
            return !page.isZoomed
        }
        pan.delegate = panGate
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        updateTitle()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 영상 재생 화면에서 돌아올 때도 숨김 상태를 그대로
        navigationController?.setNavigationBarHidden(chromeHidden, animated: animated)
        navigationController?.setToolbarHidden(chromeHidden, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 닫다가 취소했을 때 남은 변형을 지움
        if let pageView = pannedView {
            pageView.transform = .identity
            pageView.alpha = 1
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 이 화면을 떠날 때만 원래대로 (영상 재생 화면이 위에 뜰 때는 그대로 둠)
        if isMovingFromParent {
            navigationController?.setNavigationBarHidden(false, animated: animated)
            navigationController?.setToolbarHidden(true, animated: animated)
        }
    }

    private var currentIndex: Int? {
        assets.firstIndex { $0.localIdentifier == currentID }
    }

    private var currentAsset: PHAsset? {
        currentIndex.map { assets[$0] }
    }

    private func makePage(_ index: Int) -> AssetPageViewController {
        let page = AssetPageViewController(asset: assets[index])
        page.onSingleTap = { [weak self] in self?.toggleChrome() }
        return page
    }

    private func updateTitle() {
        if let date = currentAsset?.creationDate {
            title = titleFormatter.string(from: date)
        } else {
            title = nil
        }
        let favorite = currentAsset?.isFavorite ?? false
        favoriteItem.image = UIImage(systemName: favorite ? "heart.fill" : "heart")
    }

    private func toggleChrome() {
        chromeHidden.toggle()
        navigationController?.setNavigationBarHidden(chromeHidden, animated: true)
        navigationController?.setToolbarHidden(chromeHidden, animated: true)
        UIView.animate(withDuration: 0.2) {
            self.view.backgroundColor = self.chromeHidden ? .black : .systemBackground
        }
    }

    // MARK: - 쓸기 (아래: 닫기, 위: 정보)

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began {
            pannedView = viewControllers?.first?.view
        }
        guard let pageView = pannedView else { return }
        let move = gesture.translation(in: view)
        switch gesture.state {
        case .changed:
            if let page = viewControllers?.first as? AssetPageViewController, page.isZoomed {
                restore(pageView)   // 쓸다가 확대가 시작되면 그만둠
                return
            }
            if move.y > 0 {
                // 사진이 손가락을 따라 내려가며 조금 작아짐
                let progress = min(1, move.y / 320)
                let scale = 1 - progress * 0.3
                pageView.transform = CGAffineTransform(translationX: move.x * 0.6, y: move.y).scaledBy(x: scale, y: scale)
                pageView.alpha = 1 - progress * 0.4
            } else {
                pageView.transform = CGAffineTransform(translationX: 0, y: move.y * 0.3)
                pageView.alpha = 1
            }
        case .ended:
            let speed = gesture.velocity(in: view).y
            if move.y > 110 || (move.y > 30 && speed > 900) {
                navigationController?.popViewController(animated: true)
                return
            }
            let wantsInfo = move.y < -70 || (move.y < -20 && speed < -900)
            restore(pageView)
            if wantsInfo { showInfo() }
        case .cancelled, .failed:
            restore(pageView)
        default:
            break
        }
    }

    private func restore(_ pageView: UIView) {
        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [], animations: {
            pageView.transform = .identity
            pageView.alpha = 1
        }, completion: nil)
    }

    // MARK: - 넘기기

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? AssetPageViewController,
              let index = assets.firstIndex(where: { $0.localIdentifier == page.asset.localIdentifier }),
              index > 0 else { return nil }
        return makePage(index - 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? AssetPageViewController,
              let index = assets.firstIndex(where: { $0.localIdentifier == page.asset.localIdentifier }),
              index + 1 < assets.count else { return nil }
        return makePage(index + 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let page = viewControllers?.first as? AssetPageViewController else { return }
        currentID = page.asset.localIdentifier
        updateTitle()
    }

    /// 사진이 목록에서 빠졌을 때 (지움·옮김). 그사이 다른 사진으로 넘겼으면 보던 사진은 그대로
    private func remove(id: String) {
        guard let index = assets.firstIndex(where: { $0.localIdentifier == id }) else { return }
        let wasCurrent = id == currentID
        assets.remove(at: index)
        guard wasCurrent else { return }
        if assets.isEmpty {
            navigationController?.popViewController(animated: true)
            return
        }
        let next = min(index, assets.count - 1)
        currentID = assets[next].localIdentifier
        setViewControllers([makePage(next)], direction: .forward, animated: false)
        updateTitle()
    }

    // MARK: - 아래 막대

    @objc private func shareCurrent() {
        guard let asset = currentAsset else { return }
        Sharer.share([asset], from: self, barButtonItem: shareItem)
    }

    @objc private func toggleFavorite() {
        guard let index = currentIndex else { return }
        let asset = assets[index]
        let id = asset.localIdentifier
        Library.shared.setFavorite(asset, !asset.isFavorite) { [weak self] ok in
            guard ok, let self else { return }
            // PHAsset 은 바뀌지 않는 값이라 새로 받아 옴
            if let fresh = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
               let at = self.assets.firstIndex(where: { $0.localIdentifier == id }) {
                self.assets[at] = fresh
            }
            self.updateTitle()
        }
    }

    private func makeMoreMenu() -> UIMenu {
        UIMenu(children: [
            UIAction(title: "앨범으로 이동", image: UIImage(systemName: "folder")) { [weak self] _ in self?.sendCurrent(copy: false) },
            UIAction(title: "앨범으로 복사", image: UIImage(systemName: "plus.rectangle.on.folder")) { [weak self] _ in self?.sendCurrent(copy: true) },
        ])
    }

    private func sendCurrent(copy: Bool) {
        guard let asset = currentAsset else { return }
        let id = asset.localIdentifier
        Mover.present(from: self, assets: [asset], sourceAlbumID: sourceAlbumID, copy: copy) { [weak self] ok in
            // 내 앨범에서 다른 앨범으로 이동하면 이 앨범에서는 빠짐
            if ok, !copy, self?.sourceAlbumID != nil { self?.remove(id: id) }
        }
    }

    @objc private func deleteCurrent() {
        guard let asset = currentAsset else { return }
        let id = asset.localIdentifier
        Library.shared.delete([asset]) { [weak self] ok in
            if ok { self?.remove(id: id) }
        }
    }

    @objc private func showInfo() {
        guard let asset = currentAsset, presentedViewController == nil else { return }
        let nav = UINavigationController(rootViewController: InfoViewController(asset: asset))
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }
}

/// 사진 정보 (위로 쓸거나 ⓘ)
final class InfoViewController: UITableViewController {
    private var rows: [(title: String, value: String)] = []

    init(asset: PHAsset) {
        super.init(style: .insetGrouped)
        rows = InfoViewController.makeRows(asset)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "정보"
        tableView.allowsSelection = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    private static func makeRows(_ asset: PHAsset) -> [(title: String, value: String)] {
        var rows: [(title: String, value: String)] = []
        if let date = asset.creationDate {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ko_KR")
            formatter.dateFormat = "yyyy년 M월 d일 EEEE a h:mm"
            rows.append(("날짜", formatter.string(from: date)))
        }
        let isVideo = asset.mediaType == .video
        let resources = PHAssetResource.assetResources(for: asset)
        let primaryType: PHAssetResourceType = isVideo ? .video : .photo
        let primary = resources.first { $0.type == primaryType } ?? resources.first
        if let name = primary?.originalFilename, !name.isEmpty {
            rows.append(("파일", name))
        }
        rows.append(("크기", "\(asset.pixelWidth) × \(asset.pixelHeight)"))
        if isVideo {
            let total = Int(asset.duration.rounded())
            rows.append(("길이", String(format: "%d:%02d", total / 60, total % 60)))
        }

        var kind = "분류 중"
        if asset.mediaSubtypes.contains(.photoScreenshot) {
            kind = "스크린샷"
        } else if let entry = Library.shared.classifier.entry(for: asset.localIdentifier) {
            switch entry.cat {
            case .camera:
                kind = "카메라"
            case .recording:
                kind = "화면 녹화"
            case .saved:
                if let app = entry.app {
                    kind = app + "에서 저장"
                } else {
                    kind = "저장한 사진"
                }
            }
        }
        rows.append(("앨범", kind))
        if asset.isFavorite {
            rows.append(("즐겨찾기", "예"))
        }
        if let location = asset.location {
            rows.append(("위치", String(format: "%.5f, %.5f", location.coordinate.latitude, location.coordinate.longitude)))
        }
        return rows
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var content = UIListContentConfiguration.valueCell()
        content.text = rows[indexPath.row].title
        content.secondaryText = rows[indexPath.row].value
        cell.contentConfiguration = content
        return cell
    }
}
