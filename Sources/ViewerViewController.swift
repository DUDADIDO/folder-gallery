import AVFoundation
import CoreLocation
import Photos
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// 그림 자리 계산
enum Geo {
    /// size 를 rect 안에 다 보이게 (남는 곳은 비움)
    static func fit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0, rect.width > 0, rect.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let width = size.width * scale, height = size.height * scale
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }

    /// size 로 rect 를 꽉 채우게 (넘치는 곳은 잘림)
    static func fill(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0, rect.width > 0, rect.height > 0 else { return rect }
        let scale = max(rect.width / size.width, rect.height / size.height)
        let width = size.width * scale, height = size.height * scale
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }

    static func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t,
               y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t,
               height: a.height + (b.height - a.height) * t)
    }
}

/// 영상 그림판 (AVPlayerLayer 를 그대로 씀)
final class PlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// 사진 한 장 (확대 가능). Live Photo 는 길게 눌러 재생, 영상은 이 안에서 바로 재생.
/// 정보를 열면 사진이 위쪽을 꽉 채우고 그 아래에 정보 카드가 이어져 한 장처럼 위아래로 스크롤됨.
/// (이 화면의 맨 바깥 view 는 움직이지 않음. 움직이는 건 안쪽의 우리 view 들뿐)
final class AssetPageViewController: UIViewController, UIScrollViewDelegate {
    private(set) var asset: PHAsset
    var onSingleTap: (() -> Void)?
    /// 확대가 시작될 때 (순정: 확대하면 막대가 숨고 바탕이 검게)
    var onZoomIn: (() -> Void)?
    /// 정보 카드 안의 버튼·줄을 눌렀을 때
    var onInfoAction: ((InfoAction) -> Void)?
    /// 정보를 연 채 맨 위에서 아래로 당겼을 때 (정보 닫기)
    var onInfoPullDown: (() -> Void)?
    /// 영상 상태가 바뀜 (불러옴 · 재생 · 멈춤 · 끝)
    var onPlaybackChange: (() -> Void)?
    /// 영상 소리 끔 (보기 화면을 닫아도 앱이 켜져 있는 동안 기억)
    static var videoMuted = false

    private let pageScroll = UIScrollView()   // 정보 모드에서 사진 + 정보를 한 장으로 세로 스크롤
    private let mediaClip = UIView()          // 사진이 보이는 영역 (정보 모드에서 위쪽으로 줄어듦)
    private let zoomScroll = UIScrollView()   // 두 손가락 확대
    private let mediaView = UIView()          // 확대되는 것. 사진·Live·영상이 다 이 안에
    private let imageView = UIImageView()
    private var livePhotoView: PHLivePhotoView?
    private var playerView: PlayerView?
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var infoPanel: InfoPanelView?
    private var panelHeight: CGFloat?
    private(set) var infoProgress: CGFloat = 0

    private var requestID: PHImageRequestID = PHInvalidImageRequestID
    private var liveRequestID: PHImageRequestID = PHInvalidImageRequestID
    private var videoRequestID: PHImageRequestID = PHInvalidImageRequestID
    private var loadedSize: CGSize = .zero
    private var layoutSize: CGSize = .zero
    private var isActive = false      // 지금 보고 있는 사진인지 (viewDidAppear ~ viewWillDisappear)
    private var hintPlayed = false
    private var liveEnabled: Bool
    private(set) var player: AVPlayer?
    private var videoFailed = false
    private var endObserver: NSObjectProtocol?

    /// 확대해서 보는 중인지 (이때는 아래로 쓸어 닫기·정보 열기를 안 함)
    var isZoomed: Bool { zoomScroll.zoomScale > 1.01 }
    var isVideo: Bool { asset.mediaType == .video }
    var isLivePhoto: Bool { asset.mediaType == .image && asset.mediaSubtypes.contains(.photoLive) }
    var isPlaying: Bool { (player?.rate ?? 0) != 0 }

    init(asset: PHAsset, liveEnabled: Bool) {
        self.asset = asset
        self.liveEnabled = liveEnabled
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        let manager = PHImageManager.default()
        for id in [requestID, liveRequestID, videoRequestID] where id != PHInvalidImageRequestID {
            manager.cancelImageRequest(id)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        player?.pause()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        pageScroll.frame = view.bounds
        pageScroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        pageScroll.contentInsetAdjustmentBehavior = .never
        pageScroll.showsVerticalScrollIndicator = false
        pageScroll.showsHorizontalScrollIndicator = false
        pageScroll.alwaysBounceVertical = true
        pageScroll.isScrollEnabled = false
        pageScroll.scrollsToTop = false
        pageScroll.delegate = self
        if #available(iOS 26.0, *) {
            pageScroll.topEdgeEffect.isHidden = true
            zoomScroll.topEdgeEffect.isHidden = true
        }
        view.addSubview(pageScroll)

        mediaClip.clipsToBounds = true
        pageScroll.addSubview(mediaClip)

        zoomScroll.delegate = self
        zoomScroll.minimumZoomScale = 1
        zoomScroll.maximumZoomScale = isVideo ? 1 : 5
        zoomScroll.showsVerticalScrollIndicator = false
        zoomScroll.showsHorizontalScrollIndicator = false
        zoomScroll.contentInsetAdjustmentBehavior = .never
        zoomScroll.scrollsToTop = false
        mediaClip.addSubview(zoomScroll)

        zoomScroll.addSubview(mediaView)
        imageView.contentMode = .scaleAspectFit
        imageView.frame = mediaView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mediaView.addSubview(imageView)

        spinner.hidesWhenStopped = true
        spinner.color = .gray   // 밝은 바탕·어두운 바탕 모두에서 보이게
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        zoomScroll.addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        singleTap.require(toFail: doubleTap)
        zoomScroll.addGestureRecognizer(singleTap)

        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive),
                                               name: UIApplication.willResignActiveNotification, object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        if size != layoutSize {
            layoutSize = size
            if zoomScroll.zoomScale != 1 { zoomScroll.zoomScale = 1 }
            panelHeight = nil
        }
        applyLayout()
        loadImageIfNeeded()
        loadLiveIfNeeded()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadVideoIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isActive = true
        if isVideo {
            if player != nil {
                play()
            } else {
                loadVideoIfNeeded()
            }
        }
        playHintIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isActive = false
        if isPlaying { pausePlayback() }
        livePhotoView?.stopPlayback()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isZoomed { zoomScroll.setZoomScale(1, animated: false) }
    }

    @objc private func appWillResignActive() {
        if isPlaying { pausePlayback() }
    }

    // MARK: - 배치

    private var mediaSize: CGSize {
        if asset.pixelWidth > 0 && asset.pixelHeight > 0 {
            return CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
        }
        return view.bounds.size
    }

    /// 정보를 다 열었을 때 사진이 차지하는 위쪽 (화면 맨 위부터 46%)
    private var infoMediaRect: CGRect {
        CGRect(x: 0, y: 0, width: view.bounds.width, height: (view.bounds.height * 0.46).rounded())
    }

    /// 정보 진행도(0: 사진만 ~ 1: 사진은 위쪽을 꽉, 아래에 정보)에 맞춰 자리를 잡음
    private func applyLayout() {
        let bounds = CGRect(origin: .zero, size: view.bounds.size)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let progress = infoProgress
        let top = infoMediaRect
        let clip = Geo.lerp(bounds, top, progress)
        // 변형(아래로 끌어 닫기)이 걸려 있어도 안전하게 크기와 중심으로 놓음
        mediaClip.bounds = CGRect(origin: .zero, size: clip.size)
        mediaClip.center = CGPoint(x: clip.midX, y: clip.midY)
        let clipBounds = mediaClip.bounds
        if zoomScroll.frame != clipBounds {
            if zoomScroll.zoomScale != 1 { zoomScroll.zoomScale = 1 }
            zoomScroll.frame = clipBounds
        }
        if !isZoomed {
            if progress <= 0 {
                mediaView.frame = clipBounds
            } else {
                // 화면에 맞춘 크기(aspect fit)에서 위쪽을 꽉 채운 크기(aspect fill)로
                let fit = Geo.fit(mediaSize, in: bounds)
                let fill = Geo.fill(mediaSize, in: top)
                mediaView.frame = Geo.lerp(fit, fill, progress).offsetBy(dx: -clip.minX, dy: -clip.minY)
            }
            zoomScroll.contentSize = clipBounds.size
        }

        var contentHeight = bounds.height
        if let panel = infoPanel {
            let height = panelHeight ?? measurePanel(width: bounds.width)
            let finalY = top.maxY + InfoPanelView.cardSpacing
            let y = bounds.height + (finalY - bounds.height) * progress
            panel.frame = CGRect(x: 0, y: y, width: bounds.width, height: height)
            panel.alpha = min(1, progress * 1.4)
            contentHeight = max(bounds.height, finalY + height + view.safeAreaInsets.bottom + 20)
        }
        let contentSize = CGSize(width: bounds.width, height: contentHeight)
        if pageScroll.contentSize != contentSize {
            pageScroll.contentSize = contentSize
        }
    }

    private func measurePanel(width: CGFloat) -> CGFloat {
        guard let panel = infoPanel else { return 0 }
        let size = panel.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                                 withHorizontalFittingPriority: .required,
                                                 verticalFittingPriority: .fittingSizeLevel)
        panelHeight = size.height
        return size.height
    }

    /// 사진이 실제로 보이는 자리 (확대 전환이 맞출 곳)
    func mediaFrame(in target: UIView) -> CGRect {
        let fit = Geo.fit(mediaSize, in: mediaView.bounds)
        let rect = mediaView.convert(fit, to: target)
        let clip = mediaClip.convert(mediaClip.bounds, to: target)
        let visible = rect.intersection(clip)
        return (visible.isNull || visible.isEmpty) ? rect : visible
    }

    // MARK: - 정보

    /// 0: 사진만, 1: 사진이 위를 꽉 채우고 아래에 정보 (애니메이션 블록 안에서 불러도 됨)
    func setInfoProgress(_ value: CGFloat) {
        let progress = min(1, max(0, value))
        if progress > 0 {
            ensureInfoPanel()
            if isZoomed { zoomScroll.setZoomScale(1, animated: false) }
        }
        infoProgress = progress
        pageScroll.isScrollEnabled = progress >= 1
        zoomScroll.pinchGestureRecognizer?.isEnabled = progress <= 0
        if progress < 1, pageScroll.contentOffset != .zero {
            pageScroll.contentOffset = .zero
        }
        applyLayout()
    }

    private func ensureInfoPanel() {
        guard infoPanel == nil, isViewLoaded else { return }
        let panel = InfoPanelView(asset: asset)
        panel.alpha = 0
        panel.frame = CGRect(x: 0, y: view.bounds.height, width: view.bounds.width, height: 0)
        panel.onContentChange = { [weak self] in
            guard let self else { return }
            self.panelHeight = nil
            self.view.setNeedsLayout()
        }
        panel.onAction = { [weak self] action in
            self?.onInfoAction?(action)
        }
        pageScroll.addSubview(panel)
        infoPanel = panel
    }

    /// 같은 사진의 새 값으로 바꿈 (날짜 조정 등. 그림은 그대로)
    func replaceAsset(_ fresh: PHAsset) {
        guard fresh.localIdentifier == asset.localIdentifier else { return }
        asset = fresh
        infoPanel?.update(asset: fresh)
    }

    /// 넘기고 남은 화면을 원래대로
    func resetTransientState() {
        mediaClip.transform = .identity
        if infoProgress != 0 { setInfoProgress(0) }
    }

    /// 우리 전환으로 닫을 수 없을 때 아래로 끌어 닫는 동안 (우리 view 만 움직임)
    func setDismissDrag(_ transform: CGAffineTransform) {
        mediaClip.transform = transform
    }

    /// 사진 전환 동안 이 화면의 사진을 숨김 (날아가는 사진과 겹쳐 두 장으로 보이지 않게)
    func setMediaHidden(_ hidden: Bool) {
        guard isViewLoaded else { return }
        mediaClip.isHidden = hidden
    }

    /// 지금 보이는 그림 (닫힐 때 날아가는 사진으로 씀)
    var displayedImage: UIImage? {
        isViewLoaded ? imageView.image : nil
    }

    /// 아직 그림이 안 왔으면 썸네일을 대신 보여 줌 (열기 전환이 끝났을 때 사진이 비어 보이지 않게. 큰 그림이 오면 바뀜)
    func showPlaceholderIfEmpty(_ image: UIImage) {
        guard isViewLoaded, imageView.image == nil else { return }
        imageView.image = image
    }

    /// 사진 전환 전에 확대·끌기 변형을 바로 풀어 둠 (날아가는 사진이 화면에 맞춘 자리에서 시작하게)
    func resetForTransition() {
        guard isViewLoaded else { return }
        mediaClip.transform = .identity
        if isZoomed { zoomScroll.setZoomScale(1, animated: false) }
    }

    // MARK: - 불러오기

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

    /// Live Photo 는 시스템의 PHLivePhotoView 로 (길게 누르면 재생)
    private func loadLiveIfNeeded() {
        guard isLivePhoto, liveEnabled, livePhotoView == nil, view.bounds.width > 0 else { return }
        let live = PHLivePhotoView(frame: mediaView.bounds)
        live.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        live.contentMode = .scaleAspectFit
        live.backgroundColor = .clear
        mediaView.addSubview(live)
        livePhotoView = live

        let scale = traitCollection.displayScale
        let target = CGSize(width: view.bounds.width * scale, height: view.bounds.height * scale)
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        liveRequestID = PHImageManager.default().requestLivePhoto(for: asset, targetSize: target, contentMode: .aspectFit,
                                                                  options: options) { [weak self] livePhoto, _ in
            DispatchQueue.main.async {
                guard let self, let livePhoto else { return }
                self.liveRequestID = PHInvalidImageRequestID
                self.livePhotoView?.livePhoto = livePhoto
                self.playHintIfNeeded()
            }
        }
    }

    /// 순정처럼 사진이 나타날 때 짧게 한 번 움직임
    private func playHintIfNeeded() {
        guard isActive, liveEnabled, !hintPlayed, let live = livePhotoView, live.livePhoto != nil else { return }
        hintPlayed = true
        live.startPlayback(with: .hint)
    }

    /// Live 켬/끔 (사진 자체는 안 바꿈. 이 앱에서만 기억)
    func setLiveEnabled(_ on: Bool) {
        liveEnabled = on
        if on {
            livePhotoView?.isHidden = false
            loadLiveIfNeeded()
            if isActive, let live = livePhotoView, live.livePhoto != nil {
                live.startPlayback(with: .hint)
            }
        } else {
            livePhotoView?.stopPlayback()
            livePhotoView?.isHidden = true
        }
    }

    // MARK: - 영상 (화면 안에서 바로 재생)

    private func loadVideoIfNeeded() {
        guard isVideo, isViewLoaded, player == nil, videoRequestID == PHInvalidImageRequestID, !videoFailed else { return }
        spinner.startAnimating()
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        videoRequestID = PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.videoRequestID = PHInvalidImageRequestID
                self.spinner.stopAnimating()
                guard let item else {
                    self.videoFailed = true
                    self.onPlaybackChange?()
                    return
                }
                self.attachPlayer(item)
            }
        }
    }

    private func attachPlayer(_ item: AVPlayerItem) {
        guard player == nil else { return }
        let player = AVPlayer(playerItem: item)
        player.isMuted = AssetPageViewController.videoMuted
        player.actionAtItemEnd = .pause
        let playerView = PlayerView(frame: mediaView.bounds)
        playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        playerView.isUserInteractionEnabled = false
        playerView.backgroundColor = .clear
        playerView.playerLayer.videoGravity = .resizeAspect
        playerView.playerLayer.player = player
        mediaView.addSubview(playerView)
        self.playerView = playerView
        self.player = player
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item,
                                                             queue: .main) { [weak self] _ in
            self?.onPlaybackChange?()
        }
        if isActive { play() }
        onPlaybackChange?()
    }

    private func configureAudioSession() {
        // 소리를 켜면 무음 스위치와 상관없이 들리게, 끄면 다른 앱 소리를 끊지 않게
        if AssetPageViewController.videoMuted {
            try? AVAudioSession.sharedInstance().setCategory(.ambient)
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        }
    }

    func play() {
        guard let player else {
            // 불러오다 실패했으면 다시
            videoFailed = false
            loadVideoIfNeeded()
            return
        }
        configureAudioSession()
        if let item = player.currentItem {
            let total = item.duration.seconds
            if total.isFinite, total > 0, player.currentTime().seconds >= total - 0.05 {
                player.seek(to: .zero)
            }
        }
        player.play()
        onPlaybackChange?()
    }

    func pausePlayback() {
        player?.pause()
        onPlaybackChange?()
    }

    func togglePlay() {
        if isPlaying {
            pausePlayback()
        } else {
            play()
        }
    }

    func applyMute() {
        player?.isMuted = AssetPageViewController.videoMuted
        if isPlaying { configureAudioSession() }
    }

    /// 0...1 자리로 이동
    func seek(fraction: Double) {
        guard let player, let item = player.currentItem else { return }
        let total = item.duration.seconds
        guard total.isFinite, total > 0 else { return }
        let time = CMTime(seconds: total * min(1, max(0, fraction)), preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - 확대 · 누르기

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        scrollView === zoomScroll ? mediaView : nil
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        guard scrollView === zoomScroll else { return }
        onZoomIn?()
    }

    /// 정보를 연 채 맨 위에서 아래로 당기면 정보를 닫음
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard scrollView === pageScroll, infoProgress >= 1 else { return }
        let y = scrollView.contentOffset.y
        if y < -50 || (y < 0 && velocity.y < -0.5) {
            targetContentOffset.pointee = .zero
            DispatchQueue.main.async { [weak self] in
                self?.onInfoPullDown?()
            }
        }
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        guard !isVideo, infoProgress <= 0 else { return }
        if isZoomed {
            zoomScroll.setZoomScale(1, animated: true)
        } else {
            let point = gesture.location(in: mediaView)
            // 순정: 화면을 꽉 채우는 배율로 (이미 거의 꽉 차면 2배)
            let bounds = zoomScroll.bounds
            let fit = Geo.fit(mediaSize, in: bounds)
            let fillScale = fit.width > 0 && fit.height > 0 ? max(bounds.width / fit.width, bounds.height / fit.height) : 2
            let targetScale = min(zoomScroll.maximumZoomScale, fillScale < 1.3 ? 2 : fillScale)
            onZoomIn?()
            let width = zoomScroll.bounds.width / targetScale
            let height = zoomScroll.bounds.height / targetScale
            // 사진 밖(검은 여백)이 안 보이게 사진 안으로 붙임
            func clamp(_ value: CGFloat, _ size: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
                high - low <= size ? (low + high - size) / 2 : min(max(value, low), high - size)
            }
            let x = clamp(point.x - width / 2, width, fit.minX, fit.maxX)
            let y = clamp(point.y - height / 2, height, fit.minY, fit.maxY)
            zoomScroll.zoom(to: CGRect(x: x, y: y, width: width, height: height), animated: true)
        }
    }

    @objc private func singleTapped() {
        onSingleTap?()
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

// MARK: - 썸네일 줄

/// 순정처럼: 좁은 세로 조각들이 줄지어 있고, 지금 사진만 원래 비율에 가깝게 넓어지고 양옆이 더 벌어짐.
/// focus(소수)를 따라 넓어지는 칸이 부드럽게 옮겨 감. 스크롤 위치 = lead + focus × step (곧은 관계)
final class StripLayout: UICollectionViewLayout {
    var count = 0
    var aspect: (Int) -> CGFloat = { _ in 1 }
    var focus: CGFloat = 0

    let itemHeight: CGFloat = 34
    let baseWidth: CGFloat = 21
    let gap: CGFloat = 2
    let focusGap: CGFloat = 7
    var step: CGFloat { baseWidth + gap }
    var maxWide: CGFloat { itemHeight * 1.7 }
    /// 맨 앞 칸 앞의 여유 (넓어진 칸이 앞으로 밀려도 0 아래로 안 가게)
    var lead: CGFloat { (maxWide + focusGap * 2) * 2 }

    /// focus 가 가리키는 점의 가로 자리 (이 점이 줄의 한가운데에 옴)
    func anchor(for focus: CGFloat) -> CGFloat {
        lead + focus * step
    }

    private func wide(_ index: Int) -> CGFloat {
        guard index >= 0, index < count else { return baseWidth }
        return min(max(baseWidth, aspect(index) * itemHeight), maxWide)
    }

    override var collectionViewContentSize: CGSize {
        CGSize(width: anchor(for: CGFloat(max(0, count - 1))) + lead, height: collectionView?.bounds.height ?? itemHeight)
    }

    func frame(for index: Int) -> CGRect {
        let f = min(max(0, focus), CGFloat(max(0, count - 1)))
        let k = Int(floor(f))
        let s = f - CGFloat(k)
        let widthK = baseWidth + (wide(k) - baseWidth) * (1 - s)
        let widthNext = baseWidth + (wide(k + 1) - baseWidth) * s
        // k 와 k+1 의 가운데 사이 거리 (넓어진 쪽의 여백 포함)
        let distance = widthK / 2 + gap + focusGap + widthNext / 2
        let centerK = anchor(for: f) - s * distance
        let xK = centerK - widthK / 2
        let xNext = centerK + distance - widthNext / 2
        let height = collectionView?.bounds.height ?? itemHeight
        let y = ((height - itemHeight) / 2).rounded()
        let x: CGFloat
        let width: CGFloat
        if index == k {
            x = xK
            width = widthK
        } else if index < k {
            x = xK - focusGap * (1 - s) - CGFloat(k - index) * step
            width = baseWidth
        } else if index == k + 1 {
            x = xNext
            width = widthNext
        } else {
            x = xNext + widthNext + focusGap * s + gap + CGFloat(index - k - 2) * step
            width = baseWidth
        }
        return CGRect(x: x, y: y, width: width, height: itemHeight)
    }

    private func attributes(for index: Int) -> UICollectionViewLayoutAttributes {
        let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: index, section: 0))
        attributes.frame = frame(for: index)
        return attributes
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard count > 0 else { return [] }
        // 넓어진 칸 때문에 바둑판 자리에서 벗어나는 만큼 넉넉히
        let slack = (maxWide + focusGap * 2) * 2 + step
        let first = max(0, Int(floor((rect.minX - lead - slack) / step)))
        let last = min(count - 1, Int(ceil((rect.maxX - lead + slack) / step)))
        guard first <= last else { return [] }
        return (first...last).map { attributes(for: $0) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.item >= 0, indexPath.item < count else { return nil }
        return attributes(for: indexPath.item)
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.size != collectionView?.bounds.size
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
            imageView.layer.cornerRadius = 4
            imageView.layer.cornerCurve = .continuous
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

    /// 줄에 보여 주는 목록. 새로 넣으면 다시 그림
    var list: AssetList {
        get { storage }
        set {
            storage = newValue
            layout.count = newValue.count
            collectionView.reloadData()
            applyFocus(focus)
        }
    }
    private var storage: AssetList = .empty

    /// 같은 사진·같은 차례의 새 목록 (즐겨찾기 등 내용만 바뀜). 다시 그리지 않음
    func replaceList(_ fresh: AssetList) {
        storage = fresh
    }
    /// 사용자가 줄을 밀거나 눌러서 고른 사진
    var onPick: ((Int) -> Void)?
    /// 사용자가 줄을 끌거나 줄이 미끄러지는 중인지 (이때는 밖에서 위치를 안 바꿈)
    private(set) var isUserDriving = false

    private let layout: StripLayout
    private let collectionView: UICollectionView
    private var focus: CGFloat = 0
    private var lastPicked = -1

    override init(frame: CGRect) {
        let stripLayout = StripLayout()
        layout = stripLayout
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: stripLayout)
        super.init(frame: frame)
        stripLayout.aspect = { [weak self] index in
            guard let self, index >= 0, index < self.storage.count else { return 1 }
            let asset = self.storage[index]
            guard asset.pixelWidth > 0, asset.pixelHeight > 0 else { return 1 }
            return CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
        }
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.alwaysBounceHorizontal = true
        collectionView.decelerationRate = .fast
        collectionView.scrollsToTop = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(ThumbCell.self, forCellWithReuseIdentifier: "thumb")
        addSubview(collectionView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard collectionView.frame != bounds else { return }
        collectionView.frame = bounds
        // 맨 처음·맨 끝 사진도 가운데에 올 수 있게
        let half = bounds.width / 2
        collectionView.contentInset = UIEdgeInsets(top: 0, left: half, bottom: 0, right: half)
        layout.invalidateLayout()
        applyFocus(focus)
    }

    private func applyFocus(_ value: CGFloat) {
        guard !storage.isEmpty else { return }
        focus = min(max(0, value), CGFloat(storage.count - 1))
        layout.focus = focus
        layout.invalidateLayout()
        guard bounds.width > 0 else { return }
        collectionView.contentOffset = CGPoint(x: layout.anchor(for: focus) - bounds.width / 2, y: 0)
    }

    /// 넘기는 동안은 소수(예: 3.4)로 불러서 넓어지는 칸이 따라오게
    func setFocus(_ value: CGFloat, animated: Bool) {
        guard !isUserDriving, !storage.isEmpty else { return }
        lastPicked = Int(value.rounded())
        if abs(value - focus) < 0.0001 && collectionView.contentOffset.x == layout.anchor(for: focus) - bounds.width / 2 {
            return
        }
        if animated && window != nil {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: {
                self.applyFocus(value)
                self.collectionView.layoutIfNeeded()
            }, completion: nil)
        } else {
            applyFocus(value)
        }
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        storage.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "thumb", for: indexPath) as! ThumbCell
        let asset = storage[indexPath.item]
        let id = asset.localIdentifier
        cell.assetID = id
        cell.requestID = Thumbs.manager.requestImage(for: asset, targetSize: CGSize(width: 120, height: 120), contentMode: .aspectFill,
                                                     options: Thumbs.options) { [weak cell] image, _ in
            guard let cell, cell.assetID == id, let image else { return }
            cell.imageView.image = image
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        isUserDriving = false
        let index = indexPath.item
        setFocus(CGFloat(index), animated: true)
        onPick?(index)
    }

    private func focusValue(forOffset x: CGFloat) -> CGFloat {
        let raw = (x + bounds.width / 2 - layout.lead) / layout.step
        return min(max(0, raw), CGFloat(max(0, storage.count - 1)))
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isUserDriving = true
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard isUserDriving, !storage.isEmpty, bounds.width > 0 else { return }
        let value = focusValue(forOffset: scrollView.contentOffset.x)
        focus = value
        layout.focus = value
        layout.invalidateLayout()
        let index = Int(value.rounded())
        if index != lastPicked {
            lastPicked = index
            onPick?(index)
        }
    }

    /// 손을 떼면 칸 위에 정확히 멈추게
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard !storage.isEmpty, bounds.width > 0 else { return }
        let index = focusValue(forOffset: targetContentOffset.pointee.x).rounded()
        targetContentOffset.pointee.x = layout.anchor(for: index) - bounds.width / 2
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { finishUserDrive() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finishUserDrive()
    }

    private func finishUserDrive() {
        guard isUserDriving else { return }
        isUserDriving = false
        setFocus(focus.rounded(), animated: true)
    }
}

// MARK: - 영상 조절 막대

/// 영상일 때 썸네일 줄 아래(아래 막대 바로 위)에 나오는 재생/멈춤 · 시간 · 소리 막대
final class VideoControlsView: UIView {
    private let playButton = UIButton(type: .system)
    private let muteButton = UIButton(type: .system)
    private let slider = UISlider()
    private let elapsedLabel = UILabel()
    private let remainingLabel = UILabel()

    var onPlayPause: (() -> Void)?
    var onMute: (() -> Void)?
    var onScrubBegin: (() -> Void)?
    var onScrub: ((Float) -> Void)?
    var onScrubEnd: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        background.layer.cornerRadius = 24
        background.layer.cornerCurve = .continuous
        background.clipsToBounds = true
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        let symbol = UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        playButton.setPreferredSymbolConfiguration(symbol, forImageIn: .normal)
        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playButton.tintColor = .label
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        muteButton.setPreferredSymbolConfiguration(symbol, forImageIn: .normal)
        muteButton.setImage(UIImage(systemName: "speaker.wave.2.fill"), for: .normal)
        muteButton.tintColor = .label
        muteButton.addTarget(self, action: #selector(muteTapped), for: .touchUpInside)

        for label in [elapsedLabel, remainingLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            label.textColor = .secondaryLabel
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        elapsedLabel.text = "0:00"
        remainingLabel.text = "-0:00"

        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.isContinuous = true
        slider.addTarget(self, action: #selector(sliderBegan), for: .touchDown)
        slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        // 순정 iOS 27: 시간 글자 없이 [재생] [막대] [소리]
        elapsedLabel.isHidden = true
        remainingLabel.isHidden = true
        slider.setThumbImage(UIImage(), for: .normal)
        slider.setThumbImage(UIImage(), for: .highlighted)
        slider.setMinimumTrackImage(VideoControlsView.track(.secondaryLabel), for: .normal)
        slider.setMaximumTrackImage(VideoControlsView.track(.label.withAlphaComponent(0.12)), for: .normal)
        let row = UIStackView(arrangedSubviews: [playButton, elapsedLabel, slider, remainingLabel, muteButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        background.contentView.addSubview(row)
        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: background.contentView.topAnchor),
            row.bottomAnchor.constraint(equalTo: background.contentView.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: background.contentView.leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: background.contentView.trailingAnchor, constant: -8),
            playButton.widthAnchor.constraint(equalToConstant: 36),
            muteButton.widthAnchor.constraint(equalToConstant: 36),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 두꺼운 둥근 막대 그림 (늘려 씀)
    static func track(_ color: UIColor) -> UIImage {
        let height: CGFloat = 8
        let image = UIGraphicsImageRenderer(size: CGSize(width: height + 2, height: height)).image { _ in
            color.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: height + 2, height: height), cornerRadius: height / 2).fill()
        }
        return image.resizableImage(withCapInsets: UIEdgeInsets(top: 0, left: height / 2, bottom: 0, right: height / 2))
    }

    private static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    func update(elapsed: Double, total: Double, playing: Bool, muted: Bool, ready: Bool, scrubbing: Bool) {
        playButton.setImage(UIImage(systemName: playing ? "pause.fill" : "play.fill"), for: .normal)
        muteButton.setImage(UIImage(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill"), for: .normal)
        slider.isEnabled = ready
        elapsedLabel.text = VideoControlsView.clock(elapsed)
        remainingLabel.text = "-" + VideoControlsView.clock(max(0, total - elapsed))
        if !scrubbing {
            slider.value = total > 0 ? Float(min(1, max(0, elapsed / total))) : 0
        }
    }

    @objc private func playTapped() { onPlayPause?() }
    @objc private func muteTapped() { onMute?() }
    @objc private func sliderBegan() { onScrubBegin?() }
    @objc private func sliderChanged() { onScrub?(slider.value) }
    @objc private func sliderEnded() { onScrubEnd?() }
}

// MARK: - 보기 화면

/// 좌우로 넘겨 보는 화면. 순정 사진 앱처럼 위에 장소(또는 날짜)·시간, 아래에 썸네일 줄과 막대.
/// 아래로 끌면 사진이 손가락을 따라가다 격자의 썸네일로 닫히고(PhotoTransitionAnimator), 위로 끌면 사진이 위쪽을 꽉 채우며 아래에 정보가 이어짐
final class ViewerViewController: UIPageViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    /// 보여 주는 목록 (격자와 같은 앨범·같은 차례). 보관함이 바뀌면 Library 에서 다시 읽음
    private var list: AssetList
    private let folderID: String
    private let newestFirst: Bool
    /// 지금 사진과 그 목록 안의 차례
    private var currentID: String
    private var currentIndex: Int
    /// 지웠거나 앨범에서 뺐는데 아직 목록에 남아 있는 사진 (보관함 알림이 오기 전). 넘길 때 건너뜀
    private var removedIDs = Set<String>()
    /// 즐겨찾기·날짜 조정 뒤 새로 받은 사진 (새 목록이 올 때까지 이것을 씀)
    private var freshAssets: [String: PHAsset] = [:]
    /// 화면 전환 중에 보관함이 바뀌었으면 끝난 뒤에 반영
    private var libraryChangePending = false
    private let sourceAlbumID: String?
    private var chromeHidden = false
    private let panGate = VerticalPanGate()
    private weak var pannedPage: AssetPageViewController?   // 끌기 시작할 때 잡은 사진 화면
    private var panDismissing = false

    /// 바탕 (우리 view 는 투명. 확대 전환 때 사진만 커지고 바탕은 서서히 나타나게)
    private let backdrop = UIView()
    private let scrubber = ScrubberView()
    private var scrubberBottom: NSLayoutConstraint?
    private let liveBadge = UIButton(type: .system)
    private let videoControls = VideoControlsView()
    private var infoShown = false
    private var infoProgress: CGFloat = 0
    private var pagingObservation: NSKeyValueObservation?

    private weak var videoPage: AssetPageViewController?
    private var timeObserver: Any?
    private weak var observedPlayer: AVPlayer?
    private var scrubbingVideo = false
    private var resumeAfterScrub = false

    /// 화면이 아직 안 만들어졌을 때 확대 전환이 쓸 크기 (여는 쪽에서 채움)
    var fallbackBounds: CGRect = .zero
    /// 아래로 끌어 닫는 중인 우리 전환
    private var dismissDriver: PhotoTransitionAnimator?

    private lazy var shareItem = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: self, action: #selector(shareCurrent))
    private lazy var favoriteItem = UIBarButtonItem(image: UIImage(systemName: "heart"), style: .plain, target: self, action: #selector(toggleFavorite))
    private lazy var infoItem = UIBarButtonItem(image: UIImage(systemName: "info.circle"), style: .plain, target: self, action: #selector(toggleInfo))
    private lazy var albumItem = UIBarButtonItem(image: UIImage(systemName: "rectangle.stack.badge.plus"), style: .plain, target: self, action: #selector(addToAlbum))
    private lazy var deleteItem = UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain, target: self, action: #selector(deleteCurrent))

    private let titleTopLabel = UILabel()
    private let titleBottomLabel = UILabel()
    /// 위 막대 가운데의 제목 알약 (줄·배지와 같이 옅어짐)
    private let titlePill = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    /// 이 화면 자신의 아래 막대. 내비게이션의 아래 막대는 투명도를 바꿔도 보이는 게 안 바뀌어서
    /// (끌어 닫는 동안 손가락을 따라 옅어지게 하려고) 이 화면에서는 쓰지 않음
    private let bottomBar = UIToolbar()

    /// list 는 격자가 보여 주는 목록, folderID·newestFirst 는 보관함이 바뀌었을 때 같은 목록을 다시 읽는 데 씀
    init(list: AssetList, index: Int, folderID: String, newestFirst: Bool, sourceAlbumID: String?) {
        self.list = list
        self.folderID = folderID
        self.newestFirst = newestFirst
        let start = list.isEmpty ? 0 : min(max(0, index), list.count - 1)
        self.currentIndex = start
        self.currentID = list.isEmpty ? "" : list[start].localIdentifier
        self.sourceAlbumID = sourceAlbumID
        super.init(transitionStyle: .scroll, navigationOrientation: .horizontal, options: [.interPageSpacing: 16])
        // 아래 탭 막대는 iOS 18 부터 setTabBarHidden 으로 직접 숨기고 보임 (viewWillAppear·viewWillDisappear).
        // 그 전 버전에서만 예전 방식
        if #unavailable(iOS 18.0) {
            hidesBottomBarWhenPushed = true
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let timeObserver, let observedPlayer {
            observedPlayer.removeTimeObserver(timeObserver)
        }
    }

    /// 정보를 볼 때와, 탭해서 막대를 숨겨 검은 바탕일 때 (순정처럼 시간·배터리도 숨김)
    override var prefersStatusBarHidden: Bool { infoShown || chromeHidden }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        backdrop.backgroundColor = .systemBackground
        backdrop.frame = view.bounds
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(backdrop, at: 0)

        navigationItem.largeTitleDisplayMode = .never
        dataSource = self
        delegate = self

        // 아래 막대 (순정처럼): 공유 | 하트·정보·앨범에 추가 | 휴지통. 자리는 viewDidLayoutSubviews 에서
        let space = { UIBarButtonItem.flexibleSpace() }
        bottomBar.items = [shareItem, space(), favoriteItem, infoItem, albumItem, space(), deleteItem]
        // 오른쪽 위 ⋯
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: makeMoreMenu())
        setUpTitle()

        if !list.isEmpty {
            setViewControllers([makePage(currentIndex)], direction: .forward, animated: false)
        }

        scrubber.list = list
        scrubber.onPick = { [weak self] index in self?.jump(to: index) }
        scrubber.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrubber)

        videoControls.isHidden = true
        videoControls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoControls)
        setUpVideoControls()

        liveBadge.isHidden = true
        liveBadge.showsMenuAsPrimaryAction = true
        liveBadge.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(liveBadge)

        view.addSubview(bottomBar)
        // 첫 배치 전에도 대강 맞게 (정확한 높이는 layoutBottomBar 가 맞춤)
        additionalSafeAreaInsets.bottom = 44

        // 썸네일 줄은 아래 막대 바로 위. 안전 영역(아래 막대 포함)에 붙여서 처음부터 제자리에
        let guide = view.safeAreaLayoutGuide
        let stripBottom = scrubber.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -8)
        scrubberBottom = stripBottom
        NSLayoutConstraint.activate([
            stripBottom,
            scrubber.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrubber.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrubber.heightAnchor.constraint(equalToConstant: 40),
            // 순정 iOS 27: 영상 막대는 썸네일 줄 바로 위, 양옆 28
            videoControls.bottomAnchor.constraint(equalTo: scrubber.topAnchor, constant: -10),
            videoControls.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 28),
            videoControls.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -28),
            videoControls.heightAnchor.constraint(equalToConstant: 48),
            liveBadge.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            liveBadge.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        panGate.canBegin = { [weak self, weak pan] in
            guard let self, let pan, let page = self.currentPage else { return false }
            let velocity = pan.velocity(in: self.view)
            if velocity.y > 0 {
                // 아래로: 닫기 (모든 iOS 에서 우리 전환이 손가락을 따라감). 분명히 아래로 끌 때만
                return self.allowsInteractiveDismiss(location: pan.location(in: self.view), velocity: velocity)
            }
            // 위로: 정보 열기. 정보가 열려 있으면 사진 페이지 안의 스크롤이 맡음.
            // 아래 막대 위에서 시작한 끌기는 막대의 것 (예전 내비게이션 막대는 이 화면 밖이었음)
            let bar = self.bottomBar
            if !bar.isHidden, bar.alpha > 0.01, bar.frame.contains(pan.location(in: self.view)) { return false }
            return !page.isZoomed && !self.infoShown
        }
        pan.delegate = panGate
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        observePaging()
        pageDidChange(animated: false)
        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: Library.didChange, object: nil)
    }

    /// 좌우로 넘기는 동안 썸네일 줄의 넓어진 칸이 손가락을 따라오게
    private func observePaging() {
        guard pagingObservation == nil, let scroll = pagingScrollView else { return }
        pagingObservation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            self?.pagingScrolled()
        }
    }

    private func pagingScrolled() {
        guard isViewLoaded, !scrubber.isUserDriving, let focus = visibleFocus() else { return }
        scrubber.setFocus(focus, animated: false)
    }

    /// 화면 가운데에 가장 가까운 사진 화면의 자리로 지금 위치(소수)를 셈
    private func visibleFocus() -> CGFloat? {
        let width = view.bounds.width
        guard width > 0 else { return nil }
        var best: (distance: CGFloat, focus: CGFloat)?
        for child in children {
            guard let page = child as? AssetPageViewController, page.isViewLoaded, page.view.window != nil,
                  let index = index(of: page) else { continue }
            let frame = page.view.convert(page.view.bounds, to: view)
            let distance = (frame.midX - view.bounds.midX) / (width + 16)
            if best == nil || abs(distance) < abs(best?.distance ?? 0) {
                best = (distance, CGFloat(index) - distance)
            }
        }
        return best?.focus
    }

    /// 장소(또는 날짜)·시간 두 줄을 둥근 알약 안에
    private func setUpTitle() {
        titleTopLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleTopLabel.textAlignment = .center
        titleTopLabel.lineBreakMode = .byTruncatingTail
        titleBottomLabel.font = .systemFont(ofSize: 12)
        titleBottomLabel.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [titleTopLabel, titleBottomLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        let pill = titlePill
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

    private func setUpVideoControls() {
        videoControls.onPlayPause = { [weak self] in
            self?.videoPage?.togglePlay()
        }
        videoControls.onMute = { [weak self] in
            AssetPageViewController.videoMuted.toggle()
            self?.videoPage?.applyMute()
            self?.refreshVideoControls()
        }
        videoControls.onScrubBegin = { [weak self] in
            guard let self, let page = self.videoPage else { return }
            self.scrubbingVideo = true
            self.resumeAfterScrub = page.isPlaying
            if page.isPlaying { page.pausePlayback() }
        }
        videoControls.onScrub = { [weak self] value in
            self?.videoPage?.seek(fraction: Double(value))
        }
        videoControls.onScrubEnd = { [weak self] in
            guard let self else { return }
            self.scrubbingVideo = false
            if self.resumeAfterScrub { self.videoPage?.play() }
            self.resumeAfterScrub = false
            self.refreshVideoControls()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 보는 동안은 '밀어서 뒤로'(가장자리·어디서나)를 끔. 옆으로 빨리 넘기는 것이 뒤로 가기로 잡히지 않게
        navigationController?.setBackSwipe(blocked: .all, by: self)
        // 다른 화면에서 돌아올 때도 숨김 상태를 그대로
        navigationController?.setNavigationBarHidden(chromeHidden || infoShown, animated: animated)
        // 아래 막대는 이 화면 자신의 것(bottomBar). 내비게이션의 아래 막대는 숨긴 채로만 둠
        if let navigation = navigationController, !navigation.isToolbarHidden {
            navigation.setToolbarHidden(true, animated: false)
        }
        // 보는 동안은 아래 탭 막대를 숨김 (선택 모드와 같은 방법. 닫다가 취소했을 때도 여기서 다시 숨김)
        if #available(iOS 18.0, *) {
            tabBarController?.setTabBarHidden(true, animated: animated)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 닫다가 취소했을 때도 다시 끔 (그사이 뒤 화면이 풀었을 수 있음)
        navigationController?.setBackSwipe(blocked: .all, by: self)
        // 막대가 어긋난 채로 남지 않게 (닫다가 취소한 뒤 등). 맞으면 건드리지 않음
        if let navigation = navigationController, navigation.topViewController === self, !navigation.isToolbarHidden {
            navigation.setToolbarHidden(true, animated: false)
        }
        if #available(iOS 18.0, *), let tabs = tabBarController, !tabs.isTabBarHidden {
            tabs.setTabBarHidden(true, animated: false)
        }
        observePaging()
        // 닫다가 취소했을 때 남은 변형을 지움
        if !infoShown { currentPage?.setDismissDrag(.identity) }
        backdrop.alpha = 1
        applyChromeAlpha()
        if !list.isEmpty { scrubber.setFocus(CGFloat(currentIndex), animated: false) }
        // 전환 중에 보관함이 바뀌었으면 이제 반영
        if libraryChangePending {
            libraryChangePending = false
            libraryChanged()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 떠날 때(닫힘·다른 화면을 엶) 다시 켬. 닫기를 취소하면 viewDidAppear 에서 다시 끔
        navigationController?.setBackSwipe(blocked: nil, by: self)
        // 떠날 때는 언제나 아래 탭 막대를 다시 보임 (닫힘·이 위에 앨범을 엶·코드로 탭을 바꿈 — showInLibrary).
        // 이 위에 다른 화면을 열었다 돌아오거나 닫기를 취소하면 viewWillAppear 가 다시 숨김
        if #available(iOS 18.0, *), let tabs = tabBarController {
            if let coordinator = transitionCoordinator, coordinator.isInteractive, closesWithPhotoTransition(coordinator) {
                // 끌어 닫기: 애니메이션으로 보이면 손가락 전환에 묶여 멈춘 채 남음(투명). 바로 보이게 하고 투명도는 전환이 손가락을 따라 바꿈
                tabs.setTabBarHidden(false, animated: false)
                tabs.tabBar.alpha = 0
            } else {
                tabs.setTabBarHidden(false, animated: animated)
            }
        }
        guard isMovingFromParent else { return }
        navigationController?.setNavigationBarHidden(false, animated: animated)
        // 격자로 닫는 우리 사진 전환이면 바탕·줄·배지·아래 막대는 전환이 지움 (끌어 닫을 때는 손가락을 따라)
        if let coordinator = transitionCoordinator, !closesWithPhotoTransition(coordinator) {
            // 닫힐 때: 바탕이 사라지며 뒤의 화면이 보임
            coordinator.animate(alongsideTransition: { _ in
                self.backdrop.alpha = 0
                self.setChromeViewsAlpha(fade: 0)
            }, completion: { context in
                if context.isCancelled {
                    self.backdrop.alpha = 1
                    self.applyChromeAlpha()
                }
            })
        }
    }

    /// 이 닫힘을 우리 사진 전환(PhotoTransitionAnimator)이 맡는지 (격자로 돌아가는 움직이는 pop)
    private func closesWithPhotoTransition(_ coordinator: UIViewControllerTransitionCoordinator) -> Bool {
        guard coordinator.isAnimated, navigationController?.delegate is PhotoNavigationDelegate,
              let to = coordinator.viewController(forKey: .to) else { return false }
        return PhotoTransition.handles(.pop, from: self, to: to)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        // 아래 막대가 나타나고 사라질 때 썸네일 줄이 바로 따라가게
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutBottomBar()
    }

    /// 아래 막대를 내비게이션의 아래 막대가 있던 자리(홈 막대 바로 위)에 놓고,
    /// 그 막대처럼 보이는 동안은 안전 영역 아래를 막대 높이만큼 올림 (썸네일 줄·영상 막대·사진 자리가 예전 그대로).
    /// 막대 자리는 우리가 더한 만큼을 뺀 안전 영역으로 셈 (막대 자리 ↔ 더한 안전 영역이 서로 물고 돌지 않게)
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        // 돌린 뒤 아래 막대가 가로 크기(작은 아이콘·낮은 자리)로 남지 않게 다시 잼
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            guard let self else { return }
            self.bottomBar.setNeedsLayout()
            self.bottomBar.layoutIfNeeded()
            self.layoutBottomBar()
            self.view.setNeedsLayout()
        }
    }

    private func layoutBottomBar() {
        let bounds = view.bounds
        guard bounds.width > 0 else { return }
        let fitted = bottomBar.sizeThatFits(CGSize(width: bounds.width, height: 100)).height
        let height = fitted > 1 ? fitted : 44
        // 창의 안전 영역(홈 막대)을 씀: 탭 막대가 숨는 중이거나 우리가 더한 만큼이 아직 반영되기 전에도 흔들리지 않게
        let systemBottom = view.window?.safeAreaInsets.bottom ?? max(0, view.safeAreaInsets.bottom - additionalSafeAreaInsets.bottom)
        let frame = CGRect(x: 0, y: bounds.height - systemBottom - height, width: bounds.width, height: height)
        if bottomBar.frame != frame { bottomBar.frame = frame }
        let inset = chromeHidden ? 0 : height
        if additionalSafeAreaInsets.bottom != inset {
            additionalSafeAreaInsets.bottom = inset
        }
    }

    /// 목록의 index 번째 사진 (즐겨찾기·날짜 조정으로 새로 받은 것이 있으면 그것)
    private func asset(at index: Int) -> PHAsset {
        let asset = list[index]
        return freshAssets[asset.localIdentifier] ?? asset
    }

    private var currentAsset: PHAsset? {
        guard currentIndex >= 0, currentIndex < list.count else { return nil }
        return asset(at: currentIndex)
    }

    /// 사진 화면의 목록 안 차례 (지금 차례 둘레부터 찾음)
    private func index(of page: AssetPageViewController) -> Int? {
        list.index(ofID: page.asset.localIdentifier, near: currentIndex)
    }

    private var currentPage: AssetPageViewController? {
        viewControllers?.first as? AssetPageViewController
    }

    /// 지금 보고 있는 사진 (확대 전환이 돌아갈 칸을 찾는 데 씀)
    var visibleAssetID: String { currentID }
    /// 그 사진의 목록 안 차례 (격자에서 그 칸을 빨리 찾게)
    var visibleAssetIndex: Int? { list.isEmpty ? nil : currentIndex }

    /// '끌어내려 닫기'를 시작해도 되는지. location·velocity 는 끌기의 위치(이 화면 좌표)와 속도.
    /// 분명히 아래로 끌 때만 — 옆으로 넘기기(빠르게 연달아 넘기는 것 포함)는 절대 닫기가 아님
    func allowsInteractiveDismiss(location: CGPoint, velocity: CGPoint) -> Bool {
        if infoShown || infoProgress > 0 { return false }
        if let page = currentPage, page.isZoomed { return false }
        guard isViewLoaded else { return ZoomGesture.isDownward(velocity) }
        // 옆으로 넘기는 중(손가락을 떼고 미끄러지는 중 포함)이면 아님
        if let scroll = pagingScrollView, scroll.isDragging || scroll.isDecelerating { return false }
        // 속도를 알 수 없을 때(0)는 방향을 못 가리므로, 넘기는 중이 아니면 허용. 그 밖에는 분명히 아래로 끌 때만
        if velocity != .zero, !ZoomGesture.isDownward(velocity) { return false }
        // 썸네일 줄·영상 막대 위에서 시작한 끌기는 그 막대의 것
        for bar in [scrubber, videoControls, bottomBar] as [UIView] where !bar.isHidden && bar.alpha > 0.01 {
            if bar.frame.insetBy(dx: 0, dy: -8).contains(location) { return false }
        }
        return true
    }

    /// 확대 전환이 썸네일과 맞출 자리: 사진이 화면에 맞춰 보이는 곳 (흰 바탕 전체가 아니라)
    func zoomAlignmentRect() -> CGRect {
        let bounds = (isViewLoaded && view.bounds.width > 0) ? view.bounds : fallbackBounds
        if isViewLoaded, let page = currentPage, page.isViewLoaded, page.view.bounds.width > 0 {
            // 아직 자리가 안 잡혔으면(크기 0) 아래의 계산으로
            let rect = page.mediaFrame(in: view)
            if rect.width > 1, rect.height > 1 { return rect }
        }
        guard let asset = currentAsset, asset.pixelWidth > 0, asset.pixelHeight > 0 else { return bounds }
        return Geo.fit(CGSize(width: asset.pixelWidth, height: asset.pixelHeight), in: bounds)
    }

    // MARK: - 격자 ↔ 보기 화면 사진 전환 (PhotoTransitionAnimator 가 부름)

    /// 지금 사진의 원래 크기 (날아가는 사진의 비율)
    var transitionMediaSize: CGSize {
        guard let asset = currentAsset, asset.pixelWidth > 0, asset.pixelHeight > 0 else { return .zero }
        return CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
    }

    /// 지금 사진 화면에 떠 있는 그림 (썸네일보다 선명함. 아직 없으면 nil)
    var transitionImage: UIImage? {
        currentPage?.displayedImage
    }

    /// 전환 직전: 확대·끌기 변형을 풀어서 사진이 화면에 맞춘 자리에 있게
    func prepareForPhotoTransition() {
        currentPage?.resetForTransition()
    }

    /// 사진이 날아가는 동안 이 화면의 사진을 숨김. 다시 보일 때 아직 그림이 없으면 placeholder(날아온 썸네일)를 대신
    func setTransitionMediaHidden(_ hidden: Bool, placeholder: UIImage? = nil) {
        if !hidden, let placeholder { currentPage?.showPlaceholderIfEmpty(placeholder) }
        currentPage?.setMediaHidden(hidden)
    }

    /// 0: 바탕·썸네일 줄·배지·아래 막대가 다 투명 (뒤의 격자가 보임) ~ 1: 평소대로.
    /// 시스템 위 막대(뒤로·⋯)는 viewWillAppear·viewWillDisappear 의 시스템 호출이 맡음
    /// backdrop 은 흰 바탕, chrome 은 줄·배지·아래 막대·제목 (끌어 닫을 때는 둘이 따로 — 막대가 훨씬 빨리 옅어짐)
    func setTransitionAppearance(backdrop backdropProgress: CGFloat, chrome chromeProgress: CGFloat) {
        guard isViewLoaded else { return }
        backdrop.alpha = backdropProgress
        setChromeViewsAlpha(fade: chromeProgress)
    }

    private func makePage(_ index: Int) -> AssetPageViewController {
        let asset = self.asset(at: index)
        let page = AssetPageViewController(asset: asset, liveEnabled: !Prefs.liveOffAssets.contains(asset.localIdentifier))
        page.onSingleTap = { [weak self] in self?.tapped() }
        page.onZoomIn = { [weak self] in
            guard let self, !self.infoShown else { return }
            self.setChromeHidden(true, animated: true)
        }
        page.onInfoPullDown = { [weak self] in self?.setInfo(false, animated: true) }
        page.onInfoAction = { [weak self, weak page] action in
            guard let self, let page else { return }
            self.handleInfoAction(action, page: page)
        }
        return page
    }

    /// 지금 사진이 바뀌었을 때 위·아래 표시를 맞춤
    private func pageDidChange(animated: Bool) {
        updateTitle()
        updateLiveBadge()
        attachVideoControls()
        if !list.isEmpty { scrubber.setFocus(CGFloat(currentIndex), animated: animated) }
        applyChromeAlpha()
    }

    /// 순정처럼: 위치가 있으면 장소 이름 / 날짜·시간, 없으면 날짜 / 시간
    private func updateTitle() {
        let favorite = currentAsset?.isFavorite ?? false
        favoriteItem.image = UIImage(systemName: favorite ? "heart.fill" : "heart")
        guard let asset = currentAsset, let date = asset.creationDate else {
            titleTopLabel.text = " "
            titleBottomLabel.text = " "
            return
        }
        if let location = asset.location {
            if let place = PlaceNames.shared.cachedName(location) {
                titleTopLabel.text = place
                titleBottomLabel.text = DateText.dayAndTime(date)
                return
            }
            if !PlaceNames.shared.isKnown(location) {
                // 이름은 뒤에서 알아보고, 그동안은 날짜·시간
                let id = asset.localIdentifier
                PlaceNames.shared.lookup(location) { [weak self] name in
                    guard let self, name != nil, self.currentID == id else { return }
                    self.updateTitle()
                }
            }
        }
        titleTopLabel.text = DateText.day(date)
        titleBottomLabel.text = DateText.time(date)
    }

    // MARK: - Live 배지 (왼쪽 위 "LIVE ⌄")

    private func updateLiveBadge() {
        guard let asset = currentAsset, asset.mediaType == .image, asset.mediaSubtypes.contains(.photoLive) else {
            liveBadge.isHidden = true
            return
        }
        liveBadge.isHidden = false
        let on = !Prefs.liveOffAssets.contains(asset.localIdentifier)
        var config = UIButton.Configuration.gray()
        config.image = UIImage(systemName: on ? "livephoto" : "livephoto.slash")
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        config.imagePadding = 4
        config.title = "LIVE"
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
            return outgoing
        }
        config.indicator = .popup
        config.cornerStyle = .capsule
        config.buttonSize = .mini
        config.baseForegroundColor = .secondaryLabel
        liveBadge.configuration = config
        liveBadge.menu = UIMenu(children: [
            UIAction(title: "Live", image: UIImage(systemName: "livephoto"), state: on ? .on : .off) { [weak self] _ in
                self?.setLive(true)
            },
            UIAction(title: "Live 끔", image: UIImage(systemName: "livephoto.slash"), state: on ? .off : .on) { [weak self] _ in
                self?.setLive(false)
            },
        ])
    }

    private func setLive(_ on: Bool) {
        guard let asset = currentAsset else { return }
        var off = Prefs.liveOffAssets
        if on {
            off.remove(asset.localIdentifier)
        } else {
            off.insert(asset.localIdentifier)
        }
        Prefs.liveOffAssets = off
        currentPage?.setLiveEnabled(on)
        updateLiveBadge()
    }

    // MARK: - 영상 막대

    private func attachVideoControls() {
        let page = currentPage
        let isVideo = page?.isVideo == true
        if videoPage !== page {
            detachTimeObserver()
            scrubbingVideo = false
        }
        videoPage = isVideo ? page : nil
        videoControls.isHidden = !isVideo
        // 썸네일 줄은 늘 아래 막대 바로 위 (영상 막대가 그 위에)
        scrubberBottom?.constant = -8
        page?.onPlaybackChange = { [weak self, weak page] in
            guard let self, let page, page === self.videoPage else { return }
            self.attachTimeObserverIfNeeded()
            self.refreshVideoControls()
        }
        attachTimeObserverIfNeeded()
        refreshVideoControls()
    }

    private func attachTimeObserverIfNeeded() {
        guard let player = videoPage?.player, observedPlayer !== player else { return }
        detachTimeObserver()
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] _ in
            self?.refreshVideoControls()
        }
        observedPlayer = player
    }

    private func detachTimeObserver() {
        if let timeObserver, let observedPlayer {
            observedPlayer.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        observedPlayer = nil
    }

    private func refreshVideoControls() {
        guard let page = videoPage else { return }
        let player = page.player
        var total = page.asset.duration
        if let seconds = player?.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 {
            total = seconds
        }
        var elapsed = player?.currentTime().seconds ?? 0
        if !elapsed.isFinite { elapsed = 0 }
        videoControls.update(elapsed: elapsed, total: total, playing: page.isPlaying,
                             muted: AssetPageViewController.videoMuted, ready: player != nil, scrubbing: scrubbingVideo)
    }

    // MARK: - 위아래 표시 숨기기

    /// 줄·배지·영상 막대·아래 막대·제목 알약의 투명도. fade 는 지금 상태의 값에 곱하는 정도 (1 이 평소, 0 이 다 사라짐)
    private func setChromeViewsAlpha(fade: CGFloat) {
        let alpha = chromeAlpha * fade
        scrubber.alpha = alpha
        liveBadge.alpha = alpha
        videoControls.alpha = alpha
        // 아래 막대와 제목은 정보를 열어도 그대로 (예전 내비게이션 막대처럼)
        let bars = (chromeHidden ? 0 : 1) * fade
        titlePill.alpha = bars
        bottomBar.alpha = bars
        syncBottomBarHidden(bars)
    }

    /// 유리 막대가 투명도를 안 따를 때를 대비해 거의 투명하면 숨김. 움직이는 중이면 끝난 뒤에 (사라지는 게 보이게)
    private func syncBottomBarHidden(_ alpha: CGFloat) {
        if alpha > 0.02 {
            bottomBar.isHidden = false
            return
        }
        let duration = UIView.inheritedAnimationDuration
        guard duration > 0 else {
            bottomBar.isHidden = true
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { [weak self] in
            guard let self, self.bottomBar.alpha <= 0.02 else { return }
            self.bottomBar.isHidden = true
        }
    }

    /// 지금 상태에서 줄·배지가 보일 정도 (숨김 0, 정보를 열수록 옅어짐)
    private var chromeAlpha: CGFloat {
        (chromeHidden ? 0 : 1) * (1 - infoProgress)
    }

    private func applyChromeAlpha() {
        setChromeViewsAlpha(fade: 1)
    }

    /// 썸네일 줄에서 고른 사진으로 바로 바꿈
    private func jump(to index: Int) {
        guard index >= 0, index < list.count, list[index].localIdentifier != currentID else { return }
        if infoShown { setInfo(false, animated: false) }
        currentID = list[index].localIdentifier
        currentIndex = index
        setViewControllers([makePage(index)], direction: .forward, animated: false)
        pageDidChange(animated: false)
    }

    private func tapped() {
        if infoShown {
            setInfo(false, animated: true)
        } else {
            toggleChrome()
        }
    }

    private func setChromeHidden(_ hidden: Bool, animated: Bool) {
        guard chromeHidden != hidden else { return }
        chromeHidden = hidden
        navigationController?.setNavigationBarHidden(hidden, animated: animated)
        let changes = {
            self.setNeedsStatusBarAppearanceUpdate()
            self.backdrop.backgroundColor = self.chromeHidden ? .black : .systemBackground
            self.applyChromeAlpha()
            // 아래 막대만큼 올려 둔 안전 영역도 같이 (썸네일 줄이 따라 내려가고 올라옴)
            self.layoutBottomBar()
            self.view.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: 0.2, animations: changes)
        } else {
            changes()
        }
    }

    private func toggleChrome() {
        setChromeHidden(!chromeHidden, animated: true)
    }

    // MARK: - 정보 (순정처럼: 사진이 위쪽을 꽉 채우고, 바로 아래에 정보가 한 장으로 이어짐)

    private var infoDistance: CGFloat {
        max(200, view.bounds.height * 0.4)
    }

    /// 좌우 넘기기를 맡는 안쪽 스크롤뷰. 세로로 끄는 동안과 정보가 떠 있는 동안은 잠금
    private var pagingScrollView: UIScrollView? {
        view.subviews.compactMap { $0 as? UIScrollView }.first
    }

    /// 0: 사진만 ~ 1: 정보. 사진 화면 안쪽과 위아래 표시만 바꿈 (페이지 화면 자체는 안 움직임)
    private func applyInfo(_ progress: CGFloat, to page: AssetPageViewController?) {
        infoProgress = progress
        page?.setInfoProgress(progress)
        applyChromeAlpha()
        if let navigation = navigationController, !navigation.isNavigationBarHidden {
            navigation.navigationBar.alpha = 1 - progress
        }
    }

    private func setInfo(_ shown: Bool, animated: Bool) {
        let page = currentPage
        if shown && chromeHidden { setChromeHidden(false, animated: false) }
        infoShown = shown
        pagingScrollView?.isScrollEnabled = !shown
        infoItem.image = UIImage(systemName: shown ? "info.circle.fill" : "info.circle")
        if !shown, !chromeHidden, let navigation = navigationController, navigation.isNavigationBarHidden {
            // 위 막대를 투명하게 다시 꺼내 놓고 서서히 보이게
            navigation.navigationBar.alpha = 0
            navigation.setNavigationBarHidden(false, animated: false)
        }
        let target: CGFloat = shown ? 1 : 0
        let finish: (Bool) -> Void = { _ in
            guard self.infoShown == shown else { return }
            if shown { self.navigationController?.setNavigationBarHidden(true, animated: false) }
            self.navigationController?.navigationBar.alpha = 1
        }
        guard animated else {
            applyInfo(target, to: page)
            setNeedsStatusBarAppearanceUpdate()
            finish(true)
            return
        }
        // 순정을 녹화해 잰 값: 처음엔 천천히 출발해 0.4초쯤에 튀지 않고 멈춤
        UIView.animate(springDuration: 0.4, bounce: 0, initialSpringVelocity: 0, delay: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState], animations: {
            self.applyInfo(target, to: page)
            self.setNeedsStatusBarAppearanceUpdate()
        }, completion: finish)
    }

    @objc private func toggleInfo() {
        setInfo(!infoShown, animated: true)
    }

    // MARK: - 세로로 끌기 (위: 정보 열기. 아래: 닫기 — 사진이 손가락을 따라가다 썸네일로)

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        let move = gesture.translation(in: view)
        switch gesture.state {
        case .began:
            pannedPage = currentPage
            panDismissing = gesture.velocity(in: view).y > 0
            // 끄는 동안 옆 사진으로 넘어가지 않게
            pagingScrollView?.isScrollEnabled = false
            if panDismissing {
                // 격자 위에서 닫는 우리 전환을 시작 (뒤에 격자가 보이고 사진만 손가락을 따라감)
                dismissDriver = (navigationController?.delegate as? PhotoNavigationDelegate)?
                    .beginInteractiveClose(of: self, touch: gesture.location(in: nil))
            } else if chromeHidden {
                setChromeHidden(false, animated: true)
            }
        case .changed:
            if panDismissing, let driver = dismissDriver {
                driver.update(translation: move)
                return
            }
            guard let page = pannedPage, !page.isZoomed else { return }
            if panDismissing {
                let progress = min(1, max(0, move.y) / 320)
                let scale = 1 - progress * 0.3
                page.setDismissDrag(CGAffineTransform(translationX: move.x * 0.6, y: max(0, move.y)).scaledBy(x: scale, y: scale))
                backdrop.alpha = 1 - progress
                setChromeViewsAlpha(fade: 1 - progress)
            } else {
                applyInfo(min(1, max(0, -move.y / infoDistance)), to: page)
            }
        case .ended:
            let speed = gesture.velocity(in: view).y
            let page = pannedPage
            pannedPage = nil
            if panDismissing, let driver = dismissDriver {
                dismissDriver = nil
                // 충분히 내렸거나 빠르게 내리며 놓으면 썸네일로 닫힘. 위로 튕기며 놓으면 제자리로
                let close = speed > -200 && (move.y > 110 || (move.y > 30 && speed > 900) || speed > 1500)
                if !close { pagingScrollView?.isScrollEnabled = !infoShown }
                driver.end(finish: close)
            } else if panDismissing {
                if move.y > 110 || (move.y > 30 && speed > 900) {
                    navigationController?.popViewController(animated: true)
                } else {
                    // 조금만 내렸다 놓음: 제자리로
                    pagingScrollView?.isScrollEnabled = true
                    UIView.animate(withDuration: 0.25) {
                        page?.setDismissDrag(.identity)
                        self.backdrop.alpha = 1
                        self.applyChromeAlpha()
                    }
                }
            } else {
                let open = (-move.y > 60 && speed < 400) || speed < -600
                setInfo(open, animated: true)
            }
        case .cancelled, .failed:
            let page = pannedPage
            pannedPage = nil
            if panDismissing, let driver = dismissDriver {
                dismissDriver = nil
                pagingScrollView?.isScrollEnabled = !infoShown
                driver.end(finish: false)
            } else if panDismissing {
                page?.setDismissDrag(.identity)
                backdrop.alpha = 1
                applyChromeAlpha()
                pagingScrollView?.isScrollEnabled = true
            } else {
                setInfo(false, animated: true)
            }
        default:
            break
        }
    }

    // MARK: - 넘기기

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? AssetPageViewController, let index = index(of: page) else { return nil }
        // 지웠는데 아직 목록에 남은 사진은 건너뜀
        var before = index - 1
        while before >= 0, removedIDs.contains(list[before].localIdentifier) { before -= 1 }
        return before >= 0 ? makePage(before) : nil
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? AssetPageViewController, let index = index(of: page) else { return nil }
        var after = index + 1
        while after < list.count, removedIDs.contains(list[after].localIdentifier) { after += 1 }
        return after < list.count ? makePage(after) : nil
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        // 넘어간 뒤 남아 있던 화면을 원래대로
        for old in previousViewControllers where old !== viewControllers?.first {
            (old as? AssetPageViewController)?.resetTransientState()
        }
        guard completed, let page = currentPage else { return }
        if let index = index(of: page) { currentIndex = index }
        currentID = page.asset.localIdentifier
        pageDidChange(animated: true)
    }

    /// 사진이 목록에서 빠졌을 때 (지움·옮김). 보관함 알림을 기다리지 않고 바로 옆 사진으로 넘어감
    /// (썸네일 줄은 새 목록이 올 때까지 잠깐 그대로). 그사이 다른 사진으로 넘겼으면 보던 사진은 그대로
    private func remove(id: String) {
        // 새 목록이 이미 와서 그 사진이 없으면 할 일 없음
        guard list.index(ofID: id, near: currentIndex) != nil else { return }
        removedIDs.insert(id)
        guard id == currentID else { return }
        if infoShown { setInfo(false, animated: false) }
        guard let next = neighbour(of: currentIndex) else {
            closeEmpty()
            return
        }
        show(next)
    }

    /// index 다음(없으면 앞)의 아직 남아 있는 사진
    private func neighbour(of index: Int) -> Int? {
        var after = index + 1
        while after < list.count, removedIDs.contains(list[after].localIdentifier) { after += 1 }
        if after < list.count { return after }
        var before = min(index, list.count) - 1
        while before >= 0, removedIDs.contains(list[before].localIdentifier) { before -= 1 }
        return before >= 0 ? before : nil
    }

    /// index 번째 사진으로 바로 바꿈
    private func show(_ index: Int) {
        currentIndex = index
        currentID = list[index].localIdentifier
        setViewControllers([makePage(index)], direction: .forward, animated: false)
        pageDidChange(animated: false)
    }

    /// 보여 줄 사진이 없음: 닫음 (이 위에 다른 화면이 열려 있으면 이 화면만 빼냄)
    private func closeEmpty() {
        guard let navigation = navigationController else { return }
        if navigation.topViewController === self {
            navigation.popViewController(animated: true)
        } else {
            navigation.viewControllers.removeAll { $0 === self }
        }
    }

    /// 보관함이 바뀜: 같은 앨범·같은 차례의 목록을 다시 읽고 보던 사진을 찾음.
    /// 없어졌으면 같은 자리의 옆 사진으로, 목록이 비었으면 닫음
    @objc private func libraryChanged() {
        guard isViewLoaded else { return }
        if transitionCoordinator != nil {
            libraryChangePending = true
            return
        }
        let new = Library.shared.list(for: folderID, newestFirst: newestFirst)
        if new.version == list.version {
            // 들어 있는 사진·순서는 같음: 새 값(즐겨찾기 등)만 받아 둠
            list = new
            freshAssets = [:]
            scrubber.replaceList(new)
            updateTitle()
            return
        }
        let oldIndex = currentIndex
        list = new
        freshAssets = [:]
        // 지운 사진이 새 목록에도 아직 있으면 계속 건너뜀
        removedIDs = removedIDs.filter { new.index(ofID: $0) != nil }
        scrubber.list = new
        if let found = new.index(ofID: currentID, near: oldIndex), !removedIDs.contains(currentID) {
            currentIndex = found
            scrubber.setFocus(CGFloat(found), animated: false)
            return
        }
        // 보던 사진이 없어짐
        if infoShown { setInfo(false, animated: false) }
        guard !new.isEmpty else {
            closeEmpty()
            return
        }
        let start = min(oldIndex, new.count - 1)
        if !removedIDs.contains(new[start].localIdentifier) {
            show(start)
        } else if let next = neighbour(of: start) {
            show(next)
        } else {
            closeEmpty()
        }
    }

    // MARK: - 정보 카드의 버튼

    private func handleInfoAction(_ action: InfoAction, page: AssetPageViewController) {
        switch action {
        case .adjustDate:
            adjustDate(of: page)
        case .openPlace:
            openInMaps(page.asset)
        case .openSource(let folderID):
            openAlbum(folderID)
        case .showInLibrary:
            showInLibrary(page.asset.localIdentifier)
        case .addLocation:
            addLocation(to: page)
        }
    }

    /// 위치가 없는 사진에 장소 넣기 (장소를 찾아 고르면 사진 보관함에 바로 반영. iOS 가 확인 창을 띄움)
    private func addLocation(to page: AssetPageViewController) {
        let asset = page.asset
        let sheet = LocationSearchViewController()
        sheet.onPick = { [weak self, weak page] location in
            Library.shared.setLocation(asset, location) { ok in
                guard let self else { return }
                guard ok else {
                    self.toast("위치를 넣지 못했어요")
                    return
                }
                let id = asset.localIdentifier
                guard let fresh = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return }
                self.freshAssets[id] = fresh
                page?.replaceAsset(fresh)
            }
        }
        let nav = UINavigationController(rootViewController: sheet)
        if let presentation = nav.sheetPresentationController {
            presentation.detents = [.large()]
            presentation.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    /// 날짜·시간 조정 (사진 보관함에 바로 반영. iOS 가 확인 창을 띄움)
    private func adjustDate(of page: AssetPageViewController) {
        let asset = page.asset
        let sheet = DateAdjustViewController(date: asset.creationDate ?? Date())
        sheet.onSave = { [weak self, weak page] date in
            Library.shared.setCreationDate(asset, date) { ok in
                guard let self else { return }
                guard ok else {
                    self.toast("날짜를 바꾸지 못했어요")
                    return
                }
                // PHAsset 은 바뀌지 않는 값이라 새로 받아 옴
                let id = asset.localIdentifier
                guard let fresh = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return }
                self.freshAssets[id] = fresh
                page?.replaceAsset(fresh)
                if id == self.currentID { self.updateTitle() }
            }
        }
        let nav = UINavigationController(rootViewController: sheet)
        if let presentation = nav.sheetPresentationController {
            presentation.detents = [.large()]
            presentation.prefersGrabberVisible = true
        }
        present(nav, animated: true)
    }

    /// 찍은 자리를 지도 앱에서 (장소 이름이 있으면 그 이름으로 핀)
    private func openInMaps(_ asset: PHAsset) {
        guard let location = asset.location else { return }
        let coordinate = location.coordinate
        var components = URLComponents(string: "https://maps.apple.com/")
        var items = [URLQueryItem(name: "ll", value: String(format: "%.6f,%.6f", coordinate.latitude, coordinate.longitude))]
        if let name = PlaceNames.shared.cachedName(location) {
            items.append(URLQueryItem(name: "q", value: name))
        }
        components?.queryItems = items
        guard let url = components?.url else { return }
        UIApplication.shared.open(url)
    }

    /// 저장한 앱의 자동 분류 앨범을 이 위에 엶
    private func openAlbum(_ folderID: String) {
        guard let folder = Library.shared.snapshot.folders.first(where: { $0.id == folderID }),
              !Prefs.hiddenAlbums.contains(folderID) else { return }
        navigationController?.pushViewController(GridViewController(folder: folder), animated: true)
    }

    /// '모든 사진에서 보기': 보관함 탭으로 가서 그 사진이 보이게 스크롤하고 이 화면은 닫음
    private func showInLibrary(_ id: String) {
        guard let tabs = tabBarController,
              let libraryNav = tabs.viewControllers?.compactMap({ $0 as? UINavigationController }).first(where: {
                  ($0.viewControllers.first as? GridViewController)?.folderID == "all"
              }),
              let library = libraryNav.viewControllers.first as? GridViewController else { return }
        if infoShown { setInfo(false, animated: false) }
        guard let ownNav = navigationController else { return }
        if ownNav === libraryNav {
            // 보관함 탭에서 연 사진: 격자를 그 사진 자리로 옮겨 둔 뒤 닫아서 그 칸으로 줄어들며 돌아감
            library.reveal(assetID: id)
            ownNav.popToViewController(library, animated: ownNav.viewControllers.count == 2)
            return
        }
        // 다른 탭에서 연 사진: 이 화면만 닫고 보관함 탭으로
        if ownNav.topViewController === self {
            ownNav.popViewController(animated: false)
        }
        libraryNav.popToRootViewController(animated: false)
        if let index = tabs.viewControllers?.firstIndex(where: { $0 === libraryNav }) {
            tabs.selectedIndex = index
        }
        // 코드로 탭을 바꾸면 tabBarController(_:didSelect:) 가 안 불려서 직접 알림 (숨긴 앨범 탭 다시 잠금 등)
        tabs.delegate?.tabBarController?(tabs, didSelect: libraryNav)
        library.reveal(assetID: id)
    }

    // MARK: - 막대 버튼

    @objc private func shareCurrent() {
        guard let asset = currentAsset else { return }
        Sharer.share([asset], from: self, barButtonItem: shareItem)
    }

    @objc private func toggleFavorite() {
        guard let asset = currentAsset else { return }
        let id = asset.localIdentifier
        Library.shared.setFavorite(asset, !asset.isFavorite) { [weak self] ok in
            guard ok, let self else { return }
            // PHAsset 은 바뀌지 않는 값이라 새로 받아 옴 (새 목록이 올 때까지 이것을 씀)
            if let fresh = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject {
                self.freshAssets[id] = fresh
            }
            self.updateTitle()
        }
    }

    /// 순정 iOS 27 의 ··· 메뉴와 같은 짜임:
    /// 위 줄(복사 · 복제 · 가리기) / 슬라이드쇼 시작 / 추가 대상 › / 정보 조정 ›
    private func makeMoreMenu() -> UIMenu {
        let top = UIMenu(options: .displayInline, preferredElementSize: .medium, children: [
            UIAction(title: "복사", image: UIImage(systemName: "doc.on.doc.fill")) { [weak self] _ in self?.copyCurrent() },
            UIAction(title: "복제", image: UIImage(systemName: "plus.square.fill.on.square.fill")) { [weak self] _ in self?.duplicateCurrent() },
            UIAction(title: "가리기", image: UIImage(systemName: "eye.slash.fill")) { [weak self] _ in self?.hideCurrent() },
        ])
        let slideshow = UIMenu(options: .displayInline, children: [
            UIAction(title: "슬라이드쇼 시작", image: UIImage(systemName: "play.rectangle")) { [weak self] _ in self?.startSlideshow() },
        ])
        let addTo = UIMenu(title: "추가 대상", image: UIImage(systemName: "photo.on.rectangle.angled"), children: [
            UIAction(title: "앨범에 추가", image: UIImage(systemName: "rectangle.stack.badge.plus")) { [weak self] _ in self?.sendCurrent(copy: true) },
            UIAction(title: "앨범으로 이동", image: UIImage(systemName: "folder")) { [weak self] _ in self?.sendCurrent(copy: false) },
        ])
        let adjust = UIMenu(title: "정보 조정", image: UIImage(systemName: "info.circle"), children: [
            UIAction(title: "날짜 및 시간 조정", image: UIImage(systemName: "calendar.badge.clock")) { [weak self] _ in
                guard let self, let page = self.currentPage else { return }
                self.adjustDate(of: page)
            },
            UIAction(title: "위치 조정", image: UIImage(systemName: "mappin.circle")) { [weak self] _ in
                guard let self, let page = self.currentPage else { return }
                self.addLocation(to: page)
            },
        ])
        return UIMenu(children: [top, slideshow, UIMenu(options: .displayInline, children: [addTo, adjust])])
    }

    /// 복사: 지금 사진(영상)을 붙여 넣을 수 있게 클립보드로
    private func copyCurrent() {
        guard let asset = currentAsset else { return }
        if asset.mediaType == .video {
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.version = .current
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { video, _, _ in
                guard let url = (video as? AVURLAsset)?.url, let data = try? Data(contentsOf: url) else { return }
                let type = UTType(filenameExtension: url.pathExtension) ?? .movie
                DispatchQueue.main.async { UIPasteboard.general.setData(data, forPasteboardType: type.identifier) }
            }
            return
        }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .current
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, _ in
            guard let data else { return }
            UIPasteboard.general.setData(data, forPasteboardType: uti ?? UTType.jpeg.identifier)
        }
    }

    /// 복제: 같은 사진을 새 항목으로 (보관함 알림이 목록에 넣음)
    private func duplicateCurrent() {
        guard let asset = currentAsset else { return }
        Library.shared.duplicate(asset) { [weak self] ok in
            if !ok { self?.toast("복제하지 못했어요") }
        }
    }

    /// 가리기: 가려진 항목으로 (보관함에서 빠지니 옆 사진으로 넘어감)
    private func hideCurrent() {
        guard let asset = currentAsset else { return }
        let id = asset.localIdentifier
        Library.shared.setHidden([asset], true) { [weak self] ok in
            if ok { self?.remove(id: id) }
        }
    }

    /// 슬라이드쇼: 지금 사진부터 차례로
    private func startSlideshow() {
        guard !list.isEmpty else { return }
        let show = SlideshowViewController(count: list.count, start: currentIndex) { [weak self] index in
            self?.asset(at: index)
        }
        show.modalPresentationStyle = .fullScreen
        show.modalTransitionStyle = .crossDissolve
        present(show, animated: true)
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

// MARK: - 슬라이드쇼 (검은 바탕에 사진이 3초마다 천천히 바뀜. 누르면 끝)

final class SlideshowViewController: UIViewController {
    private let count: Int
    private var index: Int
    private let assetAt: (Int) -> PHAsset?
    private let imageView = UIImageView()
    private var timer: Timer?
    private var requestID: PHImageRequestID = PHInvalidImageRequestID

    init(count: Int, start: Int, assetAt: @escaping (Int) -> PHAsset?) {
        self.count = count
        self.index = start
        self.assetAt = assetAt
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        imageView.contentMode = .scaleAspectFit
        imageView.frame = view.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(imageView)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))
        show(index, animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.advance() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        timer?.invalidate()
        timer = nil
    }

    private func advance() {
        guard count > 1 else { return }
        index = (index + 1) % count
        show(index, animated: true)
    }

    private func show(_ index: Int, animated: Bool) {
        guard let asset = assetAt(index) else { return }
        PHImageManager.default().cancelImageRequest(requestID)
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        let scale = view.window?.screen.scale ?? 3
        let size = CGSize(width: view.bounds.width * scale, height: view.bounds.height * scale)
        requestID = PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit,
                                                          options: options) { [weak self] image, _ in
            guard let self, let image else { return }
            if animated {
                UIView.transition(with: self.imageView, duration: 0.8, options: .transitionCrossDissolve) {
                    self.imageView.image = image
                }
            } else {
                self.imageView.image = image
            }
        }
    }

    @objc private func close() {
        let presenter = presentingViewController
        dismiss(animated: true) {
            // 검은 화면의 흰 상태 막대가 남지 않게 뒤 화면 기준으로 다시 맞춤
            var screen = presenter
            while let current = screen {
                current.setNeedsStatusBarAppearanceUpdate()
                screen = (current as? UITabBarController)?.selectedViewController
                    ?? (current as? UINavigationController)?.topViewController
                if screen === current { break }
            }
        }
    }
}
