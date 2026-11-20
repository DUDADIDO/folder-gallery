import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate, UITabBarControllerDelegate {
    var window: UIWindow?
    private weak var hiddenRoot: FoldersViewController?
    private weak var hiddenNav: UINavigationController?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)

        let library = GridViewController(folder: Folder(id: "all", title: "보관함", symbol: "photo.on.rectangle", section: .auto),
                                         isRoot: true)
        let libraryNav = TopStyledNavigationController(rootViewController: library)
        libraryNav.navigationBar.prefersLargeTitles = true
        libraryNav.tabBarItem = UITabBarItem(title: "보관함", image: UIImage(systemName: "photo.on.rectangle"), tag: 0)

        let albumsNav = TopStyledNavigationController(rootViewController: FoldersViewController(mode: .top))
        albumsNav.navigationBar.prefersLargeTitles = true
        albumsNav.tabBarItem = UITabBarItem(title: "앨범", image: UIImage(systemName: "rectangle.stack"), tag: 1)

        let unsorted = GridViewController(folder: Folder(id: "unsorted", title: "미분류", symbol: "tray", section: .auto),
                                          isRoot: true)
        let unsortedNav = TopStyledNavigationController(rootViewController: unsorted)
        unsortedNav.navigationBar.prefersLargeTitles = true
        unsortedNav.tabBarItem = UITabBarItem(title: "미분류", image: UIImage(systemName: "tray"), tag: 3)

        let hidden = FoldersViewController(mode: .hidden)
        let hiddenNav = TopStyledNavigationController(rootViewController: hidden)
        hiddenNav.navigationBar.prefersLargeTitles = true
        hiddenNav.tabBarItem = UITabBarItem(title: "숨긴 앨범", image: UIImage(systemName: "eye.slash"), tag: 2)
        self.hiddenRoot = hidden
        self.hiddenNav = hiddenNav

        // 격자 ↔ 사진 보기 화면만 우리 전환 (사진만 날아가고 둘레는 서서히). 나머지 전환은 지금 그대로
        for nav in [libraryNav, albumsNav, unsortedNav, hiddenNav] {
            nav.delegate = PhotoNavigationDelegate.shared
        }

        let tabs = UITabBarController()
        if #available(iOS 26.0, *) {
            // 순정 iOS 27 처럼 탭 막대 오른쪽에 따로 떨어진 둥근 검색 버튼 (search 역할 탭)
            func tab(_ nav: UINavigationController, _ id: String) -> UITab {
                UITab(title: nav.tabBarItem.title ?? "", image: nav.tabBarItem.image, identifier: id) { _ in nav }
            }
            let search = UISearchTab { [weak self] _ in
                let controller = SearchViewController()
                controller.onOpenFolder = { id in self?.openFolder(id) }
                let nav = TopStyledNavigationController(rootViewController: controller)
                nav.navigationBar.prefersLargeTitles = true
                return nav
            }
            search.automaticallyActivatesSearch = true
            tabs.tabs = [tab(libraryNav, "library"), tab(albumsNav, "albums"), tab(unsortedNav, "unsorted"),
                         tab(hiddenNav, "hidden"), search]
            // iOS 27: 검색 탭을 따로 떨어진 둥근 버튼으로 (순정과 같은 자리)
            if #available(iOS 27.0, *) {
                tabs.prominentTabIdentifier = search.identifier
            }
        } else {
            tabs.viewControllers = [libraryNav, albumsNav, unsortedNav, hiddenNav]
        }
        tabs.selectedIndex = 1   // 켜면 앨범 탭부터
        tabs.delegate = self
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        self.window = window
        Library.shared.start()
    }

    /// 순정처럼 지금 탭을 다시 누르면: 안쪽 화면이면 맨 처음 화면으로, 처음 화면이면 최신 사진(끝)으로 스크롤
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if viewController === tabBarController.selectedViewController,
           let nav = viewController as? UINavigationController, nav.viewControllers.count == 1,
           let grid = nav.topViewController as? GridViewController {
            grid.scrollToLatest(animated: true)
        }
        return true
    }

    /// 검색에서 앨범을 고름: 앨범 탭에서 그 앨범을 엶
    private func openFolder(_ id: String) {
        guard let folder = Library.shared.snapshot.folders.first(where: { $0.id == id }),
              let tabs = window?.rootViewController as? UITabBarController,
              let albums = tabs.viewControllers?.compactMap({ $0 as? UINavigationController })
                .first(where: { $0.viewControllers.first is FoldersViewController && $0 !== hiddenNav }) else { return }
        if let index = tabs.viewControllers?.firstIndex(where: { $0 === albums }) { tabs.selectedIndex = index }
        albums.popToRootViewController(animated: false)
        albums.pushViewController(GridViewController(folder: folder), animated: true)
    }

    /// 숨긴 앨범 탭을 벗어나면 다시 잠금
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        if viewController !== hiddenNav {
            hiddenRoot?.lock()
        }
    }
}

/// 상태 막대 모양(흰/검은 글자)을 맨 위 화면이 정하게 (보관함 위 어두운 제목에서 흰 글자)
final class TopStyledNavigationController: UINavigationController {
    override var childForStatusBarStyle: UIViewController? { topViewController }
}
