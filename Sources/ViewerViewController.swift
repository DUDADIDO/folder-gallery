import AVFoundation
import AVKit
import CoreLocation
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

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

/// 사진 상세 아래의 작은 썸네일 줄. 옆으로 밀거나 눌러서 다른 사진으로
final class ScrubberView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    private final class ThumbCell: UICollectionViewCell {
        let imageView = UIImageView()
        var assetID: String?
        var requestID: PHImageRequestID = PHInvalidImageRequestID

        override init(frame: CGRect) {
            super.init(frame: frame)
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.layer.cornerRadius = 3
            imageView.backgroundColor = .secondarySystemBackground
            imageView.frame = contentView.bounds
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentView.addSubview(imageView)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func prepareForReuse() {
            super.prepareForReuse()
            if requestID != PHInvalidImageRequestID {
                Thumbs.manager.cancelImageRequest(requestID)
                requestID = PHInvalidImageRequestID
            }
            imageView.image = nil
        }
    }

    var assets: [PHAsset] = [] {
        didSet { collectionView.reloadData() }
    }
    /// 사용자가 줄을 밀거나 눌러서 고른 사진
    var onPick: ((Int) -> Void)?

    private let itemSize = CGSize(width: 30, height: 40)
    private let spacing: CGFloat = 2
    private let collectionView: UICollectionView
    private var index = 0
    private var userDriven = false

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 30, height: 40)
        layout.minimumLineSpacing = 2
        layout.minimumInteritemSpacing = 0
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(ThumbCell.self, forCellWithReuseIdentifier: "thumb")
        addSubview(collectionView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var sideInset: CGFloat { max(0, (bounds.width - itemSize.width) / 2) }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard collectionView.frame != bounds else { return }
        collectionView.frame = bounds
        // 맨 처음·맨 끝 사진도 가운데에 올 수 있게
        collectionView.contentInset = UIEdgeInsets(top: 0, left: sideInset, bottom: 0, right: sideInset)
        select(index, animated: false)
    }

    /// 지금 사진을 가운데로
    func select(_ newIndex: Int, animated: Bool) {
        guard !assets.isEmpty else { return }
        index = min(max(0, newIndex), assets.count - 1)
        guard bounds.width > 0 else { return }
        let x = CGFloat(index) * (itemSize.width + spacing) - sideInset
        collectionView.setContentOffset(CGPoint(x: x, y: 0), animated: animated)
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        assets.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "thumb", for: indexPath) as! ThumbCell
        let asset = assets[indexPath.item]
        let id = asset.localIdentifier
        cell.assetID = id
        cell.requestID = Thumbs.manager.requestImage(for: asset, targetSize: CGSize(width: 90, height: 120), contentMode: .aspectFill,
                                                     options: Thumbs.options) { [weak cell] image, _ in
            guard let cell, cell.assetID == id, let image else { return }
            cell.imageView.image = image
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard indexPath.item != index else { return }
        select(indexPath.item, animated: true)
        onPick?(index)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        userDriven = true
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard userDriven, !assets.isEmpty else { return }
        let raw = (scrollView.contentOffset.x + sideInset) / (itemSize.width + spacing)
        let centered = min(max(0, Int(raw.rounded())), assets.count - 1)
        if centered != index {
            index = centered
            onPick?(centered)
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settle() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        settle()
    }

    private func settle() {
        guard userDriven else { return }
        userDriven = false
        select(index, animated: true)
    }
}

/// 좌우로 넘겨 보는 화면. 순정 사진 앱처럼 위에 날짜·시간, 아래에 썸네일 줄과 막대.
/// 아래로 끌면 닫히고(확대 전환), 위로 끌면 사진이 올라가며 아래에 정보가 나옴
final class ViewerViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    private var assets: [PHAsset]
    private var currentID: String
    private let sourceAlbumID: String?
    private var chromeHidden = false
    private let panGate = VerticalPanGate()
    private weak var pannedView: UIView?   // 끌기 시작할 때 잡은 사진 화면

    private let scrubber = ScrubberView()
    private let infoController = InfoViewController()
    private var infoShown = false
    private var panStartedWithInfo = false

    private lazy var shareItem = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(shareCurrent))
    private lazy var favoriteItem = UIBarButtonItem(image: UIImage(systemName: "heart"), style: .plain, target: self, action: #selector(toggleFavorite))
    private lazy var infoItem = UIBarButtonItem(image: UIImage(systemName: "info.circle"), style: .plain, target: self, action: #selector(toggleInfo))
    private lazy var albumItem = UIBarButtonItem(image: UIImage(systemName: "rectangle.stack.badge.plus"), style: .plain, target: self, action: #selector(addToAlbum))
    private lazy var deleteItem = UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain, target: self, action: #selector(deleteCurrent))

    private let dateFormatter: DateFormatter = {
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

        // 아래 막대 (순정처럼): 공유 | 하트·정보·앨범에 추가 | 휴지통
        let space = { UIBarButtonItem.flexibleSpace() }
        toolbarItems = [shareItem, space(), favoriteItem, infoItem, albumItem, space(), deleteItem]
        // 오른쪽 위 ⋯
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: makeMoreMenu())
        setUpTitle()

        if let index = currentIndex {
            setViewControllers([makePage(index)], direction: .forward, animated: false)
        }

        scrubber.assets = assets
        scrubber.onPick = { [weak self] index in self?.jump(to: index) }
        view.addSubview(scrubber)

        addChild(infoController)
        infoController.view.isHidden = true
        view.addSubview(infoController.view)
        infoController.didMove(toParent: self)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        panGate.canBegin = { [weak self, weak pan] in
            guard let self, let page = self.viewControllers?.first as? AssetPageViewController else { return false }
            if page.isZoomed { return false }
            // iOS 18 부터는 아래로 끌어 닫기를 시스템(확대 전환)이 함. 여기서는 위로 끌기와 정보 내리기만
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

    /// 날짜·시간 두 줄을 둥근 알약 안에
    private func setUpTitle() {
        titleDateLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleDateLabel.textAlignment = .center
        titleTimeLabel.font = .systemFont(ofSize: 12)
        titleTimeLabel.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [titleDateLabel, titleTimeLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        let pill = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        pill.layer.cornerRadius = 22
        pill.layer.cornerCurve = .continuous
        pill.clipsToBounds = true
        pill.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: pill.contentView.topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: pill.contentView.bottomAnchor, constant: -5),
            stack.leadingAnchor.constraint(equalTo: pill.contentView.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: pill.contentView.trailingAnchor, constant: -22),
            pill.heightAnchor.constraint(equalToConstant: 44),
        ])
        navigationItem.titleView = pill
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 썸네일 줄: 아래 막대 바로 위
        let stripHeight: CGFloat = 40
        scrubber.frame = CGRect(x: 0, y: view.bounds.height - view.safeAreaInsets.bottom - stripHeight - 10,
                                width: view.bounds.width, height: stripHeight)
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
        if let index = currentIndex { scrubber.select(index, animated: false) }
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

    private var currentAsset: PHAsset? {
        currentIndex.map { assets[$0] }
    }

    /// 지금 보고 있는 사진 (확대 전환이 돌아갈 칸을 찾는 데 씀)
    var visibleAssetID: String { currentID }

    /// 시스템의 '끌어내려 닫기'를 해도 되는지
    var allowsInteractiveDismiss: Bool {
        if infoShown { return false }
        if let page = viewControllers?.first as? AssetPageViewController, page.isZoomed { return false }
        return true
    }

    private func makePage(_ index: Int) -> AssetPageViewController {
        let page = AssetPageViewController(asset: assets[index])
        page.onSingleTap = { [weak self] in self?.tapped() }
        return page
    }

    private func updateTitle() {
        if let date = currentAsset?.creationDate {
            titleDateLabel.text = dateFormatter.string(from: date)
            titleTimeLabel.text = timeFormatter.string(from: date)
        } else {
            titleDateLabel.text = " "
            titleTimeLabel.text = " "
        }
        let favorite = currentAsset?.isFavorite ?? false
        favoriteItem.image = UIImage(systemName: favorite ? "heart.fill" : "heart")
    }

    /// 썸네일 줄에서 고른 사진으로 바로 바꿈
    private func jump(to index: Int) {
        guard index >= 0, index < assets.count, assets[index].localIdentifier != currentID else { return }
        if infoShown { setInfo(false, animated: false) }
        currentID = assets[index].localIdentifier
        setViewControllers([makePage(index)], direction: .forward, animated: false)
        updateTitle()
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
            self.scrubber.alpha = self.chromeHidden ? 0 : 1
        }
    }

    // MARK: - 정보 (순정처럼: 사진이 위로 올라가고 그 아래에 정보)

    private var panelHeight: CGFloat {
        max(260, view.bounds.height * 0.58)
    }

    /// 좌우 넘기기를 맡는 안쪽 스크롤뷰. 세로로 끄는 동안과 정보가 떠 있는 동안은 잠금
    private var pagingScrollView: UIScrollView? {
        view.subviews.compactMap { $0 as? UIScrollView }.first
    }

    /// 정보가 다 올라왔을 때 사진을 얼마나 위로 올릴지.
    /// 사진이 남는 자리보다 작으면 그 가운데에, 크면 사진 아래쪽이 정보 바로 위에 닿게
    private func photoShift() -> CGFloat {
        let total = view.bounds.height
        let panel = panelHeight
        var photoHeight = total
        if let asset = currentAsset, asset.pixelWidth > 0 {
            photoHeight = min(total, view.bounds.width * CGFloat(asset.pixelHeight) / CGFloat(asset.pixelWidth))
        }
        let centered = panel / 2
        let bottomAligned = (total + photoHeight) / 2 - (total - panel)
        return min(panel, max(centered, bottomAligned))
    }

    /// progress 0: 사진만, 1: 사진이 위로 올라가고 정보가 다 올라옴 (사진 크기는 그대로)
    private func applyInfo(_ progress: CGFloat, to pageView: UIView) {
        pageView.transform = CGAffineTransform(translationX: 0, y: -photoShift() * progress)
        pageView.alpha = 1
        infoController.view.transform = CGAffineTransform(translationX: 0, y: panelHeight * (1 - progress))
        scrubber.alpha = chromeHidden ? 0 : 1 - progress
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
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0.4,
                       options: [.allowUserInteraction], animations: {
            self.applyInfo(shown ? 1 : 0, to: pageView)
        }, completion: { _ in
            finish()
        })
    }

    @objc private func toggleInfo() {
        setInfo(!infoShown, animated: true)
    }

    // MARK: - 세로로 끌기 (위: 정보. 아래: 정보 내리기 / iOS 17 에서는 닫기)

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
                applyInfo(min(1, max(0, 1 - move.y / height)), to: pageView)
            } else if move.y <= 0 {
                applyInfo(min(1, -move.y / height), to: pageView)
            } else {
                // 아래로 끌기 (iOS 17: 직접 닫기)
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
                setInfo(-move.y > 60 || speed < -600, animated: true)
            } else if move.y > 110 || (move.y > 30 && speed > 900) {
                pagingScrollView?.isScrollEnabled = true
                infoController.view.isHidden = true
                navigationController?.popViewController(animated: true)
            } else {
                // 조금만 내렸다 놓음: 제자리로
                infoShown = false
                pagingScrollView?.isScrollEnabled = true
                infoController.view.isHidden = true
                UIView.animate(withDuration: 0.25) {
                    pageView.transform = .identity
                    pageView.alpha = 1
                }
            }
        case .cancelled, .failed:
            pannedView = nil
            setInfo(panStartedWithInfo, animated: true)
        default:
            break
        }
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
        if let index = currentIndex { scrubber.select(index, animated: true) }
    }

    /// 사진이 목록에서 빠졌을 때 (지움·옮김). 그사이 다른 사진으로 넘겼으면 보던 사진은 그대로
    private func remove(id: String) {
        guard let index = assets.firstIndex(where: { $0.localIdentifier == id }) else { return }
        let wasCurrent = id == currentID
        assets.remove(at: index)
        if wasCurrent {
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
        scrubber.assets = assets
        if let current = currentIndex { scrubber.select(current, animated: false) }
    }

    // MARK: - 막대 버튼

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
            UIAction(title: "앨범에 추가", image: UIImage(systemName: "rectangle.stack.badge.plus")) { [weak self] _ in self?.sendCurrent(copy: true) },
        ])
    }

    @objc private func addToAlbum() {
        sendCurrent(copy: true)
    }

    private func sendCurrent(copy: Bool) {
        guard let asset = currentAsset else { return }
        let id = asset.localIdentifier
        Mover.present(from: self, assets: [asset], sourceAlbumID: sourceAlbumID, copy: copy) { [weak self] ok in
            // 앨범에서 다른 앨범으로 이동하면 이 앨범에서는 빠짐
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

/// 사진 정보 (순정 사진 앱의 정보 화면 모양: 흰 바탕에 둥근 회색 카드)
final class InfoViewController: UIViewController {
    private struct Details {
        var camera: String?
        var lens: String?
        var format: String?
        var fileSize: Int?
        var iso: String?
        var focal: String?
        var bias: String?
        var aperture: String?
        var shutter: String?
    }

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var asset: PHAsset?
    private var details = Details()
    private var token = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        scrollView.alwaysBounceVertical = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -14),
        ])
        rebuild()
    }

    func show(_ asset: PHAsset) {
        self.asset = asset
        details = Details()
        token += 1
        if isViewLoaded {
            rebuild()
            scrollView.setContentOffset(.zero, animated: false)
        }
        loadDetails(asset, token: token)
    }

    /// 촬영 정보(카메라·렌즈·ISO…)와 파일 크기는 원본을 읽어야 알 수 있어서 따로 받아 옴
    private func loadDetails(_ asset: PHAsset, token: Int) {
        guard asset.mediaType == .image else { return }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { [weak self] data, uti, _, _ in
            guard let data else { return }
            var found = Details()
            found.fileSize = data.count
            if let uti, let type = UTType(uti) {
                found.format = (type.preferredFilenameExtension ?? "").uppercased()
                if found.format == "JPG" { found.format = "JPEG" }
            }
            if let source = CGImageSourceCreateWithData(data as CFData, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
                let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
                found.camera = (tiff?[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespaces)
                found.lens = (exif?[kCGImagePropertyExifLensModel] as? String)?.trimmingCharacters(in: .whitespaces)
                if let iso = (exif?[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first {
                    found.iso = "ISO \(iso.intValue)"
                }
                if let focal = exif?[kCGImagePropertyExifFocalLength] as? NSNumber {
                    found.focal = "\(Int(focal.doubleValue.rounded())) mm"
                }
                if let bias = exif?[kCGImagePropertyExifExposureBiasValue] as? NSNumber {
                    let value = bias.doubleValue
                    found.bias = (value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)) + " ev"
                }
                if let aperture = exif?[kCGImagePropertyExifFNumber] as? NSNumber {
                    found.aperture = "ƒ" + String(format: "%g", aperture.doubleValue)
                }
                if let time = exif?[kCGImagePropertyExifExposureTime] as? NSNumber, time.doubleValue > 0 {
                    let value = time.doubleValue
                    found.shutter = value < 1 ? "1/\(Int((1 / value).rounded())) s" : String(format: "%g s", value)
                }
            }
            DispatchQueue.main.async {
                guard let self, self.token == token else { return }
                self.details = found
                if self.isViewLoaded { self.rebuild() }
            }
        }
    }

    // MARK: - 카드 만들기

    private func label(_ text: String, size: CGFloat = 17, weight: UIFont.Weight = .regular, color: UIColor = .label) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    private func padded(_ content: UIView) -> UIView {
        let box = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: 13),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -13),
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
    private func card(_ rows: [UIView]) -> UIView {
        let column = UIStackView()
        column.axis = .vertical
        for (index, row) in rows.enumerated() {
            if index > 0 { column.addArrangedSubview(separator()) }
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
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.backgroundColor = .tertiarySystemFill
        label.layer.cornerRadius = 12
        label.layer.masksToBounds = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }

    private func rebuild() {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        guard let asset else { return }
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
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ko_KR")
            formatter.dateFormat = "yyyy년 M월 d일 EEEE a h:mm"
            header.addArrangedSubview(label(formatter.string(from: date)))
        }
        if !fileName.isEmpty {
            header.addArrangedSubview(label((fileName as NSString).deletingPathExtension, color: .secondaryLabel))
        }
        rows.append(padded(header))

        var cameraText = details.camera ?? ""
        if cameraText.isEmpty {
            if isScreenshot {
                cameraText = "스크린샷"
            } else if isVideo {
                cameraText = entry?.cat == .recording ? "화면 녹화" : "동영상"
            } else {
                cameraText = "카메라 정보 없음"
            }
        }
        var format = details.format ?? ""
        if format.isEmpty { format = (fileName as NSString).pathExtension.uppercased() }
        if format == "JPG" { format = "JPEG" }
        let cameraRow = UIStackView(arrangedSubviews: [label(cameraText)])
        cameraRow.axis = .horizontal
        cameraRow.alignment = .center
        cameraRow.spacing = 8
        if !format.isEmpty { cameraRow.addArrangedSubview(badge(format)) }
        rows.append(padded(cameraRow))

        let megapixels = Double(asset.pixelWidth * asset.pixelHeight) / 1_000_000
        var sizeParts = [megapixels >= 10 ? "\(Int(megapixels.rounded()))MP" : String(format: "%.1fMP", megapixels),
                         "\(asset.pixelWidth) × \(asset.pixelHeight)"]
        if let bytes = details.fileSize {
            sizeParts.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
        }
        if isVideo {
            let total = Int(asset.duration.rounded())
            sizeParts.append(String(format: "%d:%02d", total / 60, total % 60))
        }
        let lensColumn = UIStackView()
        lensColumn.axis = .vertical
        lensColumn.spacing = 3
        if !isVideo {
            lensColumn.addArrangedSubview(label(details.lens?.isEmpty == false ? details.lens! : "렌즈 정보 없음", color: .secondaryLabel))
        }
        lensColumn.addArrangedSubview(label(sizeParts.joined(separator: " • "), color: .secondaryLabel))
        rows.append(padded(lensColumn))

        if !isVideo {
            let values = [details.iso, details.focal, details.bias, details.aperture, details.shutter]
            let exifRow = UIStackView()
            exifRow.axis = .horizontal
            exifRow.distribution = .fillEqually
            for value in values {
                let item = label(value ?? "-", size: 14, color: .secondaryLabel)
                item.textAlignment = .center
                item.numberOfLines = 1
                item.adjustsFontSizeToFitWidth = true
                exifRow.addArrangedSubview(item)
            }
            rows.append(padded(exifRow))
        }
        stack.addArrangedSubview(card(rows))

        // 2) 위치
        if let location = asset.location {
            let text = String(format: "위치  %.5f, %.5f", location.coordinate.latitude, location.coordinate.longitude)
            stack.addArrangedSubview(card([padded(label(text))]))
        }

        // 3) 어디서 저장됐는지 (알 수 있을 때)
        if let app = entry?.app {
            stack.addArrangedSubview(card([padded(label(app + "에서 저장됨"))]))
        } else if entry?.cat == .camera {
            stack.addArrangedSubview(card([padded(label("카메라로 촬영"))]))
        }

        // 4) 들어 있는 앨범
        let snapshot = Library.shared.snapshot
        let id = asset.localIdentifier
        var albums: [String] = []
        for folder in snapshot.folders where folder.isUser {
            if snapshot.items[folder.id]?.contains(where: { $0.localIdentifier == id }) == true {
                albums.append(folder.title)
            }
        }
        let albumText = albums.isEmpty ? "앨범 없음 (미분류)" : "앨범  " + albums.joined(separator: ", ")
        stack.addArrangedSubview(card([padded(label(albumText, color: albums.isEmpty ? .secondaryLabel : .label))]))
    }
}
