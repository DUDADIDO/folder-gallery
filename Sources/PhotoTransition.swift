import UIKit

/// 격자 ↔ 사진 보기 화면 사이의 우리 전환 (순정 사진 앱처럼).
/// 움직이는 건 사진 하나뿐: 격자의 정사각형 썸네일 자리에서 화면에 맞춘 자리로 커지며 잘린 정사각형이 사진 전체로 펴짐.
/// 뒤의 격자는 제자리에 그대로 있고, 보기 화면의 흰 바탕·썸네일 줄·배지만 제자리에서 서서히 나타나고 사라짐.
/// 위·아래 막대와 탭 막대는 건드리지 않음 (두 화면이 평소의 시스템 호출로 숨기고 보임)
/// (시스템 확대 전환은 보기 화면 전체를 둥근 카드처럼 키우고 줄여서 이 화면에는 쓰지 않음)
enum PhotoTransition {
    static let duration: TimeInterval = 0.3

    /// 우리 전환을 쓰는 경우: 격자에서 보기 화면을 열 때와 보기 화면에서 격자로 닫을 때만
    static func handles(_ operation: UINavigationController.Operation, from: UIViewController, to: UIViewController) -> Bool {
        switch operation {
        case .push:
            return from is GridViewController && to is ViewerViewController
        case .pop:
            return from is ViewerViewController && to is GridViewController
        default:
            return false
        }
    }
}

/// 네 탭의 내비게이션이 함께 쓰는 delegate. 격자 ↔ 보기 화면만 우리 전환을 돌려주고,
/// 나머지(앨범 카드 ↔ 앨범 화면의 확대 전환, 폴더가 옆에서 밀려 들어오는 것 등)는 nil 을 돌려줘서 지금 동작 그대로 둠
final class PhotoNavigationDelegate: NSObject, UINavigationControllerDelegate {
    /// 내비게이션의 delegate 는 약하게 잡히므로 여기서 붙잡아 둠
    static let shared = PhotoNavigationDelegate()

    /// 끌어서 닫기를 시작하며 pop 을 부르는 사이에만 들고 있는 전환
    private var pendingInteractive: PhotoTransitionAnimator?

    func navigationController(_ navigationController: UINavigationController,
                              animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController,
                              to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard PhotoTransition.handles(operation, from: fromVC, to: toVC) else {
            pendingInteractive = nil
            return nil
        }
        if operation == .pop, let pending = pendingInteractive {
            pendingInteractive = nil
            return pending
        }
        return PhotoTransitionAnimator(operation: operation, interactive: false)
    }

    func navigationController(_ navigationController: UINavigationController,
                              interactionControllerFor animationController: UIViewControllerAnimatedTransitioning)
        -> UIViewControllerInteractiveTransitioning? {
        guard let animator = animationController as? PhotoTransitionAnimator, animator.isInteractive else { return nil }
        return animator
    }

    /// 보기 화면을 아래로 끌기 시작함: 손가락을 따라가는 닫기를 시작하고 그 전환을 돌려줌.
    /// 우리 전환으로 닫을 수 없으면(바로 아래 화면이 격자가 아님 등) nil. touch 는 창 좌표
    func beginInteractiveClose(of viewer: ViewerViewController, touch: CGPoint) -> PhotoTransitionAnimator? {
        guard let nav = viewer.navigationController, nav.delegate === self, nav.topViewController === viewer,
              nav.transitionCoordinator == nil,
              let index = nav.viewControllers.firstIndex(of: viewer), index > 0,
              nav.viewControllers[index - 1] is GridViewController else { return nil }
        let animator = PhotoTransitionAnimator(operation: .pop, interactive: true)
        animator.touchInWindow = touch
        pendingInteractive = animator
        nav.popViewController(animated: true)
        // pop 이 전환을 묻지 않았으면 다음 차례에 버림 (다른 pop 이 이걸 잘못 집어 가지 않게)
        DispatchQueue.main.async { [weak self, weak animator] in
            guard let self, let animator, self.pendingInteractive === animator else { return }
            self.pendingInteractive = nil
        }
        return animator
    }
}

/// 사진만 날아가는 전환. 열기·닫기(버튼), 그리고 끌어서 닫기(손가락을 따라감)를 맡음
final class PhotoTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning, UIViewControllerInteractiveTransitioning {
    let operation: UINavigationController.Operation
    let isInteractive: Bool
    /// 끌기를 시작한 자리 (창 좌표)
    var touchInWindow: CGPoint = .zero

    private var context: UIViewControllerContextTransitioning?
    private weak var grid: GridViewController?
    private weak var viewer: ViewerViewController?

    /// 날아가는 사진: 바깥 판이 자리(썸네일 ↔ 화면에 맞춘 자리)를, 안의 그림이 잘림(정사각형 채움 ↔ 전체)을 맡음
    private var flight: UIView?
    private var flightImage: UIImageView?
    private weak var sourceView: UIView?
    private var mediaSize: CGSize = .zero
    private var fittedRect: CGRect = .zero
    private var thumbRect: CGRect?

    // 끌어서 닫기
    private var started = false
    private var ending = false
    private var translation: CGPoint = .zero
    private var touchInContainer: CGPoint = .zero
    private var pendingEnd: Bool?

    init(operation: UINavigationController.Operation, interactive: Bool) {
        self.operation = operation
        self.isInteractive = interactive
        super.init()
    }

    private var opening: Bool { operation == .push }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        PhotoTransition.duration
    }

    // MARK: - 버튼으로 열고 닫기

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        context = transitionContext
        guard setUp(transitionContext) else {
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            return
        }
        let opening = self.opening
        UIView.performWithoutAnimation {
            apply(progress: opening ? 0 : 1)
            placeFlight(opening ? (thumbRect ?? fittedRect) : fittedRect, cropped: opening && thumbRect != nil)
        }
        // 순정처럼 짧게 (움직임이 보이는 건 0.2초 남짓), 튀지 않게 감쇠 1
        UIView.animate(withDuration: PhotoTransition.duration, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0,
                       options: [], animations: {
            self.apply(progress: opening ? 1 : 0)
            if opening {
                self.placeFlight(self.fittedRect, cropped: false)
            } else if let thumb = self.thumbRect {
                self.placeFlight(thumb, cropped: true)
            } else {
                self.flight?.alpha = 0
            }
        }, completion: { _ in
            self.finish(completed: !transitionContext.transitionWasCancelled)
        })
    }

    // MARK: - 끌어서 닫기 (손가락을 따라감)

    func startInteractiveTransition(_ transitionContext: UIViewControllerContextTransitioning) {
        context = transitionContext
        guard setUp(transitionContext) else {
            transitionContext.cancelInteractiveTransition()
            transitionContext.completeTransition(false)
            return
        }
        touchInContainer = transitionContext.containerView.convert(touchInWindow, from: nil)
        started = true
        UIView.performWithoutAnimation {
            apply(progress: 1)
            placeFlight(fittedRect, cropped: false)
        }
        update(translation: translation)
        if let finish = pendingEnd {
            pendingEnd = nil
            end(finish: finish)
        }
    }

    /// 끈 거리(보기 화면 좌표의 이동량). 사진은 손가락을 따라 움직이며 줄고, 바탕은 거리만큼 천천히,
    /// 줄·배지·아래 막대·제목은 훨씬 빨리 (순정처럼 20pt 까지는 그대로, 80pt 에서 다 사라짐). 손가락을 되돌리면 다시 보임
    func update(translation move: CGPoint) {
        translation = move
        guard started, !ending, let context else { return }
        let height = max(1, context.containerView.bounds.height)
        let down = max(0, move.y)
        let progress = min(1, down / (height * 0.45))
        let scale = 1 - 0.5 * min(1, down / height)
        // 위로는 조금만 (고무줄처럼)
        let dy = move.y >= 0 ? move.y : move.y * 0.3
        let finger = CGPoint(x: touchInContainer.x + move.x, y: touchInContainer.y + dy)
        let rect = fittedRect
        // 처음 잡은 사진 위의 점이 손가락 아래에 그대로 남게 줄임
        let moved = CGRect(x: finger.x + (rect.minX - touchInContainer.x) * scale,
                           y: finger.y + (rect.minY - touchInContainer.y) * scale,
                           width: rect.width * scale, height: rect.height * scale)
        placeFlight(moved, cropped: false)
        let chrome = 1 - min(1, max(0, (down - 20) / 60))
        apply(backdrop: 1 - progress, chrome: chrome)
        context.updateInteractiveTransition(progress)
    }

    /// 손을 뗌: finish 면 썸네일로 줄어들며 닫히고, 아니면 제자리로 돌아감
    func end(finish: Bool) {
        guard started, let context else {
            pendingEnd = finish
            return
        }
        guard !ending else { return }
        ending = true
        if finish {
            context.finishInteractiveTransition()
            UIView.animate(withDuration: 0.34, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0,
                           options: [], animations: {
                self.apply(progress: 0)
                if let thumb = self.thumbRect {
                    self.placeFlight(thumb, cropped: true)
                } else {
                    self.flight?.alpha = 0
                }
            }, completion: { _ in
                self.finish(completed: true)
            })
        } else {
            context.cancelInteractiveTransition()
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                           options: [], animations: {
                self.apply(progress: 1)
                self.placeFlight(self.fittedRect, cropped: false)
            }, completion: { _ in
                self.finish(completed: false)
            })
        }
    }

    // MARK: - 준비 · 진행 · 정리

    /// 화면을 놓고 날아갈 사진을 만듦. 격자·보기 화면이 아니면 false
    private func setUp(_ context: UIViewControllerContextTransitioning) -> Bool {
        guard let fromVC = context.viewController(forKey: .from), let toVC = context.viewController(forKey: .to),
              let grid = (opening ? fromVC : toVC) as? GridViewController,
              let viewer = (opening ? toVC : fromVC) as? ViewerViewController else { return false }
        self.grid = grid
        self.viewer = viewer
        let container = context.containerView

        // 화면은 크기를 바꾸지 않고 제자리에 겹쳐 놓기만 함 (보기 화면이 위)
        if opening {
            viewer.view.frame = context.finalFrame(for: viewer)
            if viewer.view.superview !== container { container.addSubview(viewer.view) }
        } else {
            grid.view.frame = context.finalFrame(for: grid)
            if grid.view.superview !== container { container.insertSubview(grid.view, belowSubview: viewer.view) }
        }
        grid.view.layoutIfNeeded()
        viewer.view.layoutIfNeeded()
        viewer.prepareForPhotoTransition()

        let id = viewer.visibleAssetID
        fittedRect = container.convert(viewer.zoomAlignmentRect(), from: viewer.view)
        mediaSize = viewer.transitionMediaSize
        if mediaSize.width <= 0 || mediaSize.height <= 0 { mediaSize = fittedRect.size }

        // 닫을 때는 지금 보고 있는 사진의 칸으로 (화면 밖이면 격자가 먼저 그 칸이 보이게 스크롤)
        let source = grid.transitionSource(forAssetID: id, near: viewer.visibleAssetIndex, reveal: !opening)
        if let source {
            let rect = source.view.convert(source.view.bounds, to: container)
            if rect.width > 1, rect.height > 1, rect.intersects(container.bounds) {
                thumbRect = rect
                sourceView = source.view
            }
        }
        let image = opening ? (source?.image ?? viewer.transitionImage) : (viewer.transitionImage ?? source?.image)

        // 열 때 썸네일이 없으면 날아갈 사진 없이 보기 화면 전체가 서서히 (닫을 때는 사진이 그 자리에서 사라짐)
        if let image, fittedRect.width > 1, fittedRect.height > 1, !(opening && thumbRect == nil) {
            let flight = UIView()
            flight.clipsToBounds = true
            flight.isUserInteractionEnabled = false
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleToFill   // 비율은 자리 계산이 지킴
            flight.addSubview(imageView)
            container.addSubview(flight)
            self.flight = flight
            flightImage = imageView
            sourceView?.isHidden = true
            viewer.setTransitionMediaHidden(true)
        }
        return true
    }

    /// progress 1: 보기 화면이 다 보임, 0: 격자만. 보기 화면 자신의 view 만 바꿈 (막대는 건드리지 않음)
    private func apply(progress: CGFloat) {
        apply(backdrop: progress, chrome: progress)
    }

    /// 바탕과 줄·막대를 따로 (끌어 닫을 때). 버튼으로 열고 닫을 때는 apply(progress:) 로 같이
    private func apply(backdrop: CGFloat, chrome: CGFloat) {
        guard let viewer else { return }
        viewer.setTransitionAppearance(backdrop: backdrop, chrome: chrome)
        if flight == nil { viewer.view.alpha = backdrop }
    }

    /// 날아가는 사진을 rect 에. cropped 면 정사각형 썸네일처럼 가운데를 꽉 채워 자르고, 아니면 사진 전체
    private func placeFlight(_ rect: CGRect, cropped: Bool) {
        guard let flight, let flightImage else { return }
        flight.frame = rect
        let bounds = CGRect(origin: .zero, size: rect.size)
        flightImage.frame = cropped ? Geo.fill(mediaSize, in: bounds) : Geo.fit(mediaSize, in: bounds)
    }

    private func finish(completed: Bool) {
        let flownImage = flightImage?.image
        flight?.removeFromSuperview()
        flight = nil
        flightImage = nil
        sourceView?.isHidden = false
        let viewerShown = opening == completed
        if let viewer {
            viewer.setTransitionMediaHidden(false, placeholder: viewerShown ? flownImage : nil)
            viewer.view.alpha = 1
            let shown: CGFloat = viewerShown ? 1 : 0
            viewer.setTransitionAppearance(backdrop: shown, chrome: shown)
        }
        if !completed && !opening {
            // 닫기를 취소함: 밑에 깔았던 격자를 치움
            grid?.view.removeFromSuperview()
        }
        let context = self.context
        self.context = nil
        context?.completeTransition(completed)
    }
}
