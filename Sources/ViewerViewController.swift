import AVKit
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
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, let item else { return }
                let player = AVPlayerViewController()
                player.player = AVPlayer(playerItem: item)
                self.present(player, animated: true) {
                    player.player?.play()
                }
            }
        }
    }
}

/// 좌우로 넘겨 보는 화면
final class ViewerViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    private var assets: [PHAsset]
    private var currentID: String
    private let sourceAlbumID: String?
    private var chromeHidden = false

    private lazy var shareItem = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(shareCurrent))
    private lazy var moveItem = UIBarButtonItem(image: UIImage(systemName: "folder"), style: .plain, target: self, action: #selector(moveCurrent))
    private lazy var infoItem = UIBarButtonItem(image: UIImage(systemName: "info.circle"), style: .plain, target: self, action: #selector(showInfo))
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
        toolbarItems = [shareItem, space(), moveItem, space(), infoItem, space(), deleteItem]
        if let index = currentIndex {
            setViewControllers([makePage(index)], direction: .forward, animated: false)
        }
        updateTitle()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 영상 재생 화면에서 돌아올 때도 숨김 상태를 그대로
        navigationController?.setNavigationBarHidden(chromeHidden, animated: animated)
        navigationController?.setToolbarHidden(chromeHidden, animated: animated)
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
    }

    private func toggleChrome() {
        chromeHidden.toggle()
        navigationController?.setNavigationBarHidden(chromeHidden, animated: true)
        navigationController?.setToolbarHidden(chromeHidden, animated: true)
        UIView.animate(withDuration: 0.2) {
            self.view.backgroundColor = self.chromeHidden ? .black : .systemBackground
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
        guard completed, let page = viewControllers?.first as? AssetPageViewController else { return }
        currentID = page.asset.localIdentifier
        updateTitle()
    }

    /// 지금 보던 사진이 목록에서 빠졌을 때 (지움·옮김)
    private func removeCurrent() {
        guard let index = currentIndex else { return }
        assets.remove(at: index)
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

    @objc private func moveCurrent() {
        guard let asset = currentAsset else { return }
        Mover.present(from: self, assets: [asset], sourceAlbumID: sourceAlbumID) { [weak self] ok in
            // 내 폴더에서 다른 폴더로 옮기면 이 폴더에서는 빠짐
            if ok, self?.sourceAlbumID != nil { self?.removeCurrent() }
        }
    }

    @objc private func deleteCurrent() {
        guard let asset = currentAsset else { return }
        Library.shared.delete([asset]) { [weak self] ok in
            if ok { self?.removeCurrent() }
        }
    }

    @objc private func showInfo() {
        guard let asset = currentAsset else { return }
        let resources = PHAssetResource.assetResources(for: asset)
        let isVideo = asset.mediaType == .video
        let primaryType: PHAssetResourceType = isVideo ? .video : .photo
        let primary = resources.first { $0.type == primaryType } ?? resources.first
        let name = primary?.originalFilename ?? "-"

        var kind = "분류 중"
        if asset.mediaSubtypes.contains(.photoScreenshot) {
            kind = "스크린샷"
        } else if let entry = Library.shared.classifier.entry(for: asset.localIdentifier) {
            switch entry.cat {
            case .camera: kind = "카메라"
            case .recording: kind = "화면 녹화"
            case .saved: kind = entry.app.map { "저장한 사진 (\($0))" } ?? "저장한 사진"
            }
        }
        var lines = [
            "파일: \(name)",
            "크기: \(asset.pixelWidth) × \(asset.pixelHeight)",
            "분류: \(kind)",
        ]
        if let date = asset.creationDate {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ko_KR")
            formatter.dateStyle = .long
            formatter.timeStyle = .medium
            lines.insert("날짜: \(formatter.string(from: date))", at: 0)
        }
        if isVideo {
            lines.append("길이: \(Int(asset.duration.rounded()))초")
        }
        let alert = UIAlertController(title: "정보", message: lines.joined(separator: "\n"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "닫기", style: .cancel))
        present(alert, animated: true)
    }
}
