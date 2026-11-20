import Photos
import UIKit

/// 미분류 사진을 한 장씩 넘기며 정리하는 화면 (Slidebox 방식).
/// 아래 앨범 이름을 누르면 그 앨범에 들어가고 다음 사진으로. 왼쪽으로 쓸면 건너뛰기, 위로 쓸면 휴지통에 담기.
/// 휴지통에 담은 사진은 한꺼번에 지움(iOS 확인 창 한 번).
final class SorterViewController: UIViewController {
    private enum Step {
        case filed(index: Int, albumID: String)
        case trashed(index: Int)
        case skipped(index: Int)
    }

    private let queue: [PHAsset]
    private var index = 0
    private var history: [Step] = []
    private var trash: [PHAsset] = []

    private let imageView = UIImageView()
    private let videoBadge = UILabel()
    private let doneLabel = UILabel()
    private let chipScroll = UIScrollView()
    private let chipStack = UIStackView()
    private let undoButton = UIButton(type: .system)
    private let skipButton = UIButton(type: .system)
    private let trashButton = UIButton(type: .system)
    private var albums: [Folder] = []
    private var requestID: PHImageRequestID = PHInvalidImageRequestID
    private var loadToken = 0

    init(assets: [PHAsset]) {
        self.queue = assets
        super.init(nibName: nil, bundle: nil)
        hidesBottomBarWhenPushed = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.largeTitleDisplayMode = .never

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)

        videoBadge.text = "  동영상  "
        videoBadge.font = .systemFont(ofSize: 13, weight: .semibold)
        videoBadge.textColor = .white
        videoBadge.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        videoBadge.layer.cornerRadius = 11
        videoBadge.layer.masksToBounds = true
        videoBadge.isHidden = true
        videoBadge.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(videoBadge)

        doneLabel.numberOfLines = 0
        doneLabel.textAlignment = .center
        doneLabel.textColor = .secondaryLabel
        doneLabel.font = .systemFont(ofSize: 17)
        doneLabel.isHidden = true
        doneLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(doneLabel)

        chipScroll.showsHorizontalScrollIndicator = false
        chipScroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chipScroll)
        chipStack.axis = .horizontal
        chipStack.spacing = 8
        chipStack.translatesAutoresizingMaskIntoConstraints = false
        chipScroll.addSubview(chipStack)

        configure(undoButton, title: "되돌리기", symbol: "arrow.uturn.backward", action: #selector(undo))
        configure(skipButton, title: "건너뛰기", symbol: "arrow.right", action: #selector(skip))
        configure(trashButton, title: "휴지통", symbol: "trash", action: #selector(trashCurrent))
        trashButton.tintColor = .systemRed
        let buttons = UIStackView(arrangedSubviews: [undoButton, skipButton, trashButton])
        buttons.axis = .horizontal
        buttons.distribution = .fillEqually
        buttons.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buttons)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            imageView.bottomAnchor.constraint(equalTo: chipScroll.topAnchor, constant: -12),

            videoBadge.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 10),
            videoBadge.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 10),
            videoBadge.heightAnchor.constraint(equalToConstant: 22),

            doneLabel.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            doneLabel.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            doneLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),

            chipScroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chipScroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chipScroll.heightAnchor.constraint(equalToConstant: 44),
            chipScroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -8),

            chipStack.topAnchor.constraint(equalTo: chipScroll.contentLayoutGuide.topAnchor),
            chipStack.bottomAnchor.constraint(equalTo: chipScroll.contentLayoutGuide.bottomAnchor),
            chipStack.leadingAnchor.constraint(equalTo: chipScroll.contentLayoutGuide.leadingAnchor, constant: 16),
            chipStack.trailingAnchor.constraint(equalTo: chipScroll.contentLayoutGuide.trailingAnchor, constant: -16),
            chipStack.heightAnchor.constraint(equalTo: chipScroll.frameLayoutGuide.heightAnchor),

            buttons.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            buttons.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            buttons.heightAnchor.constraint(equalToConstant: 56),
            buttons.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -4),
        ])

        addSwipe(.left, #selector(skip))
        addSwipe(.right, #selector(undo))
        addSwipe(.up, #selector(trashCurrent))

        NotificationCenter.default.addObserver(self, selector: #selector(libraryChanged), name: Library.didChange, object: nil)
        // Face ID 로 연 화면이라 앱이 뒤로 가면 닫음
        NotificationCenter.default.addObserver(self, selector: #selector(closeForLock),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        rebuildChips()
        showCurrent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 오른쪽으로 쓸기는 '되돌리기'라서, 밀어서 뒤로 가기는 끔 (나갈 때는 왼쪽 위 뒤로 버튼)
        navigationController?.setBackSwipe(blocked: .all, by: self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setBackSwipe(blocked: nil, by: self)
    }

    private func configure(_ button: UIButton, title: String, symbol: String, action: Selector) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: symbol)
        config.imagePlacement = .top
        config.imagePadding = 4
        var text = AttributedString(title)
        text.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        config.attributedTitle = text
        button.configuration = config
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func addSwipe(_ direction: UISwipeGestureRecognizer.Direction, _ action: Selector) {
        let swipe = UISwipeGestureRecognizer(target: self, action: action)
        swipe.direction = direction
        imageView.addGestureRecognizer(swipe)
    }

    @objc private func closeForLock() {
        navigationController?.popToRootViewController(animated: false)
    }

    // MARK: - 앨범 칩

    @objc private func libraryChanged() {
        rebuildChips()
    }

    private func rebuildChips() {
        let fresh = Library.shared.snapshot.folders.filter { $0.isUser }
        guard fresh != albums || chipStack.arrangedSubviews.isEmpty else { return }
        albums = fresh
        for view in chipStack.arrangedSubviews {
            chipStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        chipStack.addArrangedSubview(makeChip(title: "새로운 앨범", symbol: "plus", tag: -1, tinted: true))
        for (offset, album) in albums.enumerated() {
            chipStack.addArrangedSubview(makeChip(title: album.title, symbol: nil, tag: offset, tinted: false))
        }
    }

    private func makeChip(title: String, symbol: String?, tag: Int, tinted: Bool) -> UIButton {
        var config = tinted ? UIButton.Configuration.tinted() : UIButton.Configuration.gray()
        config.title = title
        if let symbol {
            config.image = UIImage(systemName: symbol)
            config.imagePadding = 4
        }
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        let button = UIButton(configuration: config)
        button.tag = tag
        button.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
        return button
    }

    @objc private func chipTapped(_ sender: UIButton) {
        guard index < queue.count else { return }
        let asset = queue[index]
        if sender.tag < 0 {
            promptText(title: "새로운 앨범", placeholder: "앨범 이름", confirm: "저장") { [weak self] name in
                Library.shared.createAlbum(title: name, adding: [asset]) { ok in
                    guard let self, ok else { return }
                    // 새 앨범은 ID 를 아직 몰라 되돌리기는 건너뛴 것으로 기록
                    self.history.append(.skipped(index: self.index))
                    self.advance()
                }
            }
            return
        }
        guard sender.tag < albums.count, let albumID = albums[sender.tag].albumID,
              let album = Library.shared.album(id: albumID) else { return }
        Library.shared.copy([asset], to: album)
        history.append(.filed(index: index, albumID: albumID))
        advance()
    }

    // MARK: - 넘기기

    private func advance() {
        index += 1
        slide(forward: true)
        showCurrent()
    }

    /// 사진이 옆으로 밀려 나가고 들어오는 효과
    private func slide(forward: Bool) {
        let transition = CATransition()
        transition.type = .push
        transition.subtype = forward ? .fromRight : .fromLeft
        transition.duration = 0.25
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        imageView.layer.add(transition, forKey: "slide")
    }

    @objc private func skip() {
        guard index < queue.count else { return }
        history.append(.skipped(index: index))
        advance()
    }

    @objc private func trashCurrent() {
        guard index < queue.count else { return }
        trash.append(queue[index])
        history.append(.trashed(index: index))
        advance()
    }

    @objc private func undo() {
        guard let last = history.popLast() else { return }
        switch last {
        case .filed(let at, let albumID):
            if at < queue.count, let album = Library.shared.album(id: albumID) {
                Library.shared.remove([queue[at]], from: album)
            }
            index = at
        case .trashed(let at):
            if at < queue.count {
                let id = queue[at].localIdentifier
                trash.removeAll { $0.localIdentifier == id }
            }
            index = at
        case .skipped(let at):
            index = at
        }
        slide(forward: false)
        showCurrent()
    }

    @objc private func emptyTrash() {
        guard !trash.isEmpty else { return }
        let list = trash
        Library.shared.delete(list) { [weak self] ok in
            guard let self, ok else { return }
            let ids = Set(list.map { $0.localIdentifier })
            self.trash.removeAll { ids.contains($0.localIdentifier) }
            // 지운 사진은 되돌릴 수 없으니 기록에서도 뺌
            self.history.removeAll { step in
                if case .trashed = step { return true }
                return false
            }
            self.updateChrome()
        }
    }

    private func updateChrome() {
        let total = queue.count
        navigationItem.title = index < total ? "\(index + 1) / \(total)" : "정리 끝"
        undoButton.isEnabled = !history.isEmpty
        skipButton.isEnabled = index < total
        trashButton.isEnabled = index < total
        if trash.isEmpty {
            navigationItem.rightBarButtonItem = nil
        } else {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "휴지통 비우기 (\(trash.count))", style: .plain,
                                                                target: self, action: #selector(emptyTrash))
        }
    }

    private func showCurrent() {
        updateChrome()
        loadToken += 1
        let token = loadToken
        if requestID != PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(requestID)
            requestID = PHInvalidImageRequestID
        }
        guard index < queue.count else {
            imageView.image = nil
            videoBadge.isHidden = true
            chipScroll.isHidden = true
            doneLabel.isHidden = false
            doneLabel.text = trash.isEmpty
                ? "미분류 사진을 다 봤어요."
                : "미분류 사진을 다 봤어요.\n휴지통에 담은 \(trash.count)장은 오른쪽 위에서 지울 수 있어요."
            return
        }
        chipScroll.isHidden = false
        doneLabel.isHidden = true
        let asset = queue[index]
        videoBadge.isHidden = asset.mediaType != .video
        imageView.image = nil
        let scale = traitCollection.displayScale
        let size = CGSize(width: max(200, view.bounds.width) * scale, height: max(200, view.bounds.height) * scale)
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        requestID = PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit,
                                                          options: options) { [weak self] image, _ in
            guard let self, self.loadToken == token, let image else { return }
            if self.imageView.image == nil {
                UIView.transition(with: self.imageView, duration: 0.15, options: .transitionCrossDissolve, animations: {
                    self.imageView.image = image
                }, completion: nil)
            } else {
                self.imageView.image = image
            }
        }
    }
}
