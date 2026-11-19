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

/// 좌우로 넘겨 보는 화면. 사진 앱처럼 아래로 쓸면 닫히고, 위로 끌면 사진이 작아지며 아래에 정보가 나옴
final class ViewerViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    private var assets: [PHAsset]
    private var currentID: String
    private let sourceAlbumID: String?
    private var chromeHidden = false
    private let panGate = VerticalPanGate()
    private weak var pannedView: UIView?   // 쓸기 시작할 때 잡은 사진 화면

    // 정보 칸 (화면 아래 45%)
    private let infoController = InfoViewController()
    private var infoShown = false
    private var panStartedWithInfo = false

    private lazy var shareItem = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(shareCurrent))
    private lazy var favoriteItem = UIBarButtonItem(image: UIImage(systemName: "heart"), style: .plain, target: self, action: #selector(toggleFavorite))
    private lazy var infoItem = UIBarButtonItem(image: UIImage(systemName: "info.circle"), style: .plain, target: self, action: #selector(toggleInfo))
    private lazy var moreItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: makeMoreMenu())
    private lazy var deleteItem = UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain, target: self, action: #selector(deleteCurrent))

    private let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일"
        return formatter
    }()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm"
        return formatter
    }()
    private let titleDateLabel = UILabel()
    private let titleTimeLabel = UILabel()

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
        // 순정 사진 앱처럼: 공유 | 하트·정보·더보기 | 휴지통
        toolbarItems = [shareItem, space(), favoriteItem, infoItem, moreItem, space(), deleteItem]
        titleDateLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleDateLabel.textAlignment = .center
        titleTimeLabel.font = .systemFont(ofSize: 12)
        titleTimeLabel.textColor = .secondaryLabel
        titleTimeLabel.textAlignment = .center
        let titleStack = UIStackView(arrangedSubviews: [titleDateLabel, titleTimeLabel])
        titleStack.axis = .vertical
        titleStack.alignment = .center
        navigationItem.titleView = titleStack
        if let index = currentIndex {
            setViewControllers([makePage(index)], direction: .forward, animated: false)
        }

        addChild(infoController)
        infoController.view.layer.cornerRadius = 18
        infoController.view.layer.cornerCurve = .continuous
        infoController.view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        infoController.view.clipsToBounds = true
        infoController.view.isHidden = true
        view.addSubview(infoController.view)
        infoController.didMove(toParent: self)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        panGate.canBegin = { [weak self, weak pan] in
            guard let self, let page = self.viewControllers?.first as? AssetPageViewController else { return false }
            if page.isZoomed { return false }
            // iOS 18 부터는 아래로 끌어 닫기를 시스템(확대 전환)이 함. 여기서는 위로 끌기와 정보 칸 내리기만
            if #available(iOS 18.0, *), !self.infoShown, let pan, pan.velocity(in: self.view).y > 0 {
                return false
            }
            return true
        }
        pan.delegate = panGate
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        updateTitle()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 변형(transform)이 걸려 있어도 안전하게 크기와 중심으로 놓음
        let height = panelHeight
        infoController.view.bounds = CGRect(x: 0, y: 0, width: view.bounds.width, height: height)
        infoController.view.center = CGPoint(x: view.bounds.midX, y: view.bounds.height - height / 2)
        if !infoShown && pannedView == nil {
            infoController.view.transform = CGAffineTransform(translationX: 0, y: height)
        }
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
        if !infoShown, let pageView = viewControllers?.first?.view {
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

    /// 지금 보고 있는 사진 (확대 전환이 돌아갈 칸을 찾는 데 씀)
    var visibleAssetID: String { currentID }

    /// 시스템의 '끌어내려 닫기'를 해도 되는지
    var allowsInteractiveDismiss: Bool {
        if infoShown { return false }
        if let page = viewControllers?.first as? AssetPageViewController, page.isZoomed { return false }
        return true
    }

    private var currentAsset: PHAsset? {
        currentIndex.map { assets[$0] }
    }

    private func makePage(_ index: Int) -> AssetPageViewController {
        let page = AssetPageViewController(asset: assets[index])
        page.onSingleTap = { [weak self] in self?.tapped() }
        return page
    }

    private func updateTitle() {
        if let date = currentAsset?.creationDate {
            titleDateLabel.text = titleFormatter.string(from: date)
            titleTimeLabel.text = timeFormatter.string(from: date)
        } else {
            titleDateLabel.text = nil
            titleTimeLabel.text = nil
        }
        navigationItem.titleView?.sizeToFit()
        let favorite = currentAsset?.isFavorite ?? false
        favoriteItem.image = UIImage(systemName: favorite ? "heart.fill" : "heart")
    }

    private func tapped() {
        if infoShown {
            setInfo(false, animated: true)
        } else {
            toggleChrome()
        }
    }

    private func toggleChrome() {
        chromeHidden.toggle()
        navigationController?.setNavigationBarHidden(chromeHidden, animated: true)
        navigationController?.setToolbarHidden(chromeHidden, animated: true)
        UIView.animate(withDuration: 0.2) {
            self.view.backgroundColor = self.chromeHidden ? .black : .systemBackground
        }
    }

    // MARK: - 정보 칸

    private var panelHeight: CGFloat {
        max(220, view.bounds.height * 0.45)
    }

    /// 좌우 넘기기를 맡는 안쪽 스크롤뷰. 세로로 끄는 동안과 정보가 떠 있는 동안은 잠금
    private var pagingScrollView: UIScrollView? {
        view.subviews.compactMap { $0 as? UIScrollView }.first
    }

    /// progress 0: 사진만, 1: 사진이 위로 작아지고 정보가 다 올라옴
    private func applyInfo(_ progress: CGFloat, to pageView: UIView) {
        let height = panelHeight
        let total = max(1, view.bounds.height)
        let topScale = max(0.4, (total - height) / total)
        let scale = 1 - (1 - topScale) * progress
        pageView.transform = CGAffineTransform(translationX: 0, y: -height / 2 * progress).scaledBy(x: scale, y: scale)
        pageView.alpha = 1
        infoController.view.transform = CGAffineTransform(translationX: 0, y: height * (1 - progress))
    }

    private func prepareInfo() {
        if let asset = currentAsset {
            infoController.show(asset)
        }
        infoController.view.isHidden = false
        view.bringSubviewToFront(infoController.view)
    }

    private func setInfo(_ shown: Bool, animated: Bool) {
        guard let pageView = viewControllers?.first?.view else { return }
        if shown { prepareInfo() }
        infoShown = shown
        pagingScrollView?.isScrollEnabled = !shown
        infoItem.image = UIImage(systemName: shown ? "info.circle.fill" : "info.circle")
        let finish = {
            if !self.infoShown {
                self.infoController.view.isHidden = true
                pageView.transform = .identity
            }
        }
        guard animated else {
            applyInfo(shown ? 1 : 0, to: pageView)
            finish()
            return
        }
        UIView.animate(withDuration: 0.32, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [.allowUserInteraction], animations: {
            self.applyInfo(shown ? 1 : 0, to: pageView)
        }, completion: { _ in
            finish()
        })
    }

    @objc private func toggleInfo() {
        setInfo(!infoShown, animated: true)
    }

    // MARK: - 세로로 끌기 (아래: 닫기, 위: 정보)

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began {
            pannedView = viewControllers?.first?.view
            panStartedWithInfo = infoShown
            // 끄는 동안 옆 사진으로 넘어가지 않게
            pagingScrollView?.isScrollEnabled = false
            if !infoShown, let pageView = pannedView {
                prepareInfo()
                applyInfo(0, to: pageView)
            }
        }
        guard let pageView = pannedView else { return }
        let move = gesture.translation(in: view)
        let height = panelHeight

        switch gesture.state {
        case .changed:
            if let page = viewControllers?.first as? AssetPageViewController, page.isZoomed {
                return   // 끌다가 확대가 시작되면 그대로 둠
            }
            if panStartedWithInfo {
                // 정보가 떠 있을 때: 아래로 끌면 내려감
                applyInfo(min(1, max(0, 1 - move.y / height)), to: pageView)
            } else if move.y <= 0 {
                // 위로 끌기: 손가락을 따라 사진이 작아지고 정보가 올라옴
                applyInfo(min(1, -move.y / height), to: pageView)
            } else {
                // 아래로 끌기: 닫기
                infoController.view.transform = CGAffineTransform(translationX: 0, y: height)
                let progress = min(1, move.y / 320)
                let scale = 1 - progress * 0.3
                pageView.transform = CGAffineTransform(translationX: move.x * 0.6, y: move.y).scaledBy(x: scale, y: scale)
                pageView.alpha = 1 - progress * 0.4
            }
        case .ended:
            let speed = gesture.velocity(in: view).y
            pannedView = nil
            if panStartedWithInfo {
                setInfo(!(move.y > 60 || speed > 700), animated: true)
            } else if move.y <= 0 {
                setInfo(-move.y > 70 || speed < -700, animated: true)
            } else if move.y > 110 || (move.y > 30 && speed > 900) {
                pagingScrollView?.isScrollEnabled = true
                infoController.view.isHidden = true
                navigationController?.popViewController(animated: true)
            } else {
                // 조금만 내렸다 놓음: 제자리로
                infoShown = false
                pagingScrollView?.isScrollEnabled = true
                infoController.view.isHidden = true
                restore(pageView)
            }
        case .cancelled, .failed:
            pannedView = nil
            setInfo(panStartedWithInfo, animated: true)
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
        // 넘어간 뒤 남아 있던 화면의 변형을 지움
        for old in previousViewControllers {
            old.view.transform = .identity
            old.view.alpha = 1
        }
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
        if infoShown { setInfo(false, animated: false) }
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
                if self.infoShown, id == self.currentID { self.infoController.show(fresh) }
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
}

/// 사진 정보 칸 (사진을 위로 끌거나 ⓘ)
final class InfoViewController: UITableViewController {
    private var rows: [(title: String, value: String)] = []

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.allowsSelection = false
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    func show(_ asset: PHAsset) {
        rows = InfoViewController.makeRows(asset)
        if isViewLoaded {
            tableView.reloadData()
            tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: false)
        }
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
