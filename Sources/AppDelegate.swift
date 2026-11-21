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

        // 숨긴 앨범은 탭에 두지 않음 (앨범 탭 ⋯ 메뉴에서 들어감)

        // 격자 ↔ 사진 보기 화면만 우리 전환 (사진만 날아가고 둘레는 서서히). 나머지 전환은 지금 그대로
        for nav in [libraryNav, albumsNav, unsortedNav] {
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
            if windowScene.traitCollection.userInterfaceIdiom == .pad {
                // 아이패드 (순정 iOS 27): 위 탭 막대 + 왼쪽 사이드바 단추. 검색은 탭이 아니라 각 화면 오른쪽 위 단추
                tabs.tabs = [tab(libraryNav, "library"), tab(albumsNav, "albums"), tab(unsortedNav, "unsorted")]
                tabs.mode = .tabSidebar
                self.sidebarTabs = tabs
                refreshSidebarAlbums()
                NotificationCenter.default.addObserver(forName: Library.didChange, object: nil, queue: .main) { [weak self] _ in
                    self?.refreshSidebarAlbums()
                }
            } else {
                tabs.tabs = [tab(libraryNav, "library"), tab(albumsNav, "albums"), tab(unsortedNav, "unsorted"), search]
                // iOS 27: 검색 탭을 따로 떨어진 둥근 버튼으로 (순정과 같은 자리)
                if #available(iOS 27.0, *) {
                    tabs.prominentTabIdentifier = search.identifier
                }
            }
        } else {
            tabs.viewControllers = [libraryNav, albumsNav, unsortedNav]
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
    // MARK: 아이패드 사이드바의 '앨범' 묶음 (순정처럼 앨범마다 한 줄, 누르면 앨범 탭에서 그 앨범)

    private weak var sidebarTabs: UITabBarController?
    private var sidebarIDs: [String] = []

    private func refreshSidebarAlbums() {
        guard #available(iOS 26.0, *), let tabs = sidebarTabs else { return }
        let folders = Library.shared.snapshot.folders.filter { !$0.isGroup && !Prefs.hiddenAlbums.contains($0.id) }
        let ids = folders.map(\.id)
        guard ids != sidebarIDs else { return }
        sidebarIDs = ids
        // 앨범 묶음은 비어 있으면 넣지 않음 (빈 묶음은 UIKit 이 받지 않음)
        var list = tabs.tabs.filter { $0.identifier != "albumGroup" }
        if !folders.isEmpty {
            let children = folders.map { folder -> UITab in
                // 그 앨범 격자를 오른쪽 넓은 자리에 (순정 사이드바의 앨범처럼)
                let tab = UITab(title: folder.title, image: UIImage(systemName: folder.isUser ? "rectangle.stack" : folder.symbol),
                                identifier: "folder:" + folder.id) { _ in GridViewController(folder: folder) }
                tab.preferredPlacement = .sidebarOnly
                return tab
            }
            // 묶음이 내비게이션을 맡아 고른 앨범 격자를 그 안에 띄움 (사진을 열면 그 안에서 우리 전환으로)
            let group = UITabGroup(title: "앨범", image: nil, identifier: "albumGroup", children: children, viewControllerProvider: nil)
            let nav = TopStyledNavigationController()
            nav.delegate = PhotoNavigationDelegate.shared
            group.managingNavigationController = nav
            group.preferredPlacement = .sidebarOnly
            list.append(group)
        }
        tabs.setTabs(list, animated: false)
    }

    private func openFolder(_ id: String) {
        guard let folder = Library.shared.snapshot.folders.first(where: { $0.id == id }),
              let tabs = window?.rootViewController as? UITabBarController,
              let albums = tabs.viewControllers?.compactMap({ $0 as? UINavigationController })
                .first(where: { $0.viewControllers.first is FoldersViewController }) else { return }
        if #available(iOS 18.0, *), let albumsTab = tabs.tabs.first(where: { $0.identifier == "albums" }) {
            tabs.selectedTab = albumsTab
        } else if let index = tabs.viewControllers?.firstIndex(where: { $0 === albums }) {
            tabs.selectedIndex = index
        }
        albums.popToRootViewController(animated: false)
        albums.pushViewController(GridViewController(folder: folder), animated: true)
    }
}

/// 상태 막대 모양(흰/검은 글자)을 맨 위 화면이 정하게 (보관함 위 어두운 제목에서 흰 글자)
final class TopStyledNavigationController: UINavigationController {
    override var childForStatusBarStyle: UIViewController? { topViewController }
}
