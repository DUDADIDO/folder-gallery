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
        let libraryNav = UINavigationController(rootViewController: library)
        libraryNav.navigationBar.prefersLargeTitles = true
        libraryNav.tabBarItem = UITabBarItem(title: "보관함", image: UIImage(systemName: "photo.on.rectangle"), tag: 0)

        let albumsNav = UINavigationController(rootViewController: FoldersViewController(mode: .top))
        albumsNav.navigationBar.prefersLargeTitles = true
        albumsNav.tabBarItem = UITabBarItem(title: "앨범", image: UIImage(systemName: "rectangle.stack"), tag: 1)

        let hidden = FoldersViewController(mode: .hidden)
        let hiddenNav = UINavigationController(rootViewController: hidden)
        hiddenNav.navigationBar.prefersLargeTitles = true
        hiddenNav.tabBarItem = UITabBarItem(title: "숨긴 앨범", image: UIImage(systemName: "eye.slash"), tag: 2)
        self.hiddenRoot = hidden
        self.hiddenNav = hiddenNav

        let tabs = UITabBarController()
        tabs.viewControllers = [libraryNav, albumsNav, hiddenNav]
        tabs.selectedIndex = 1   // 켜면 앨범 탭부터
        tabs.delegate = self
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        self.window = window
        Library.shared.start()
    }

    /// 숨긴 앨범 탭을 벗어나면 다시 잠금
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        if viewController !== hiddenNav {
            hiddenRoot?.lock()
        }
    }
}
