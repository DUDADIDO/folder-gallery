# Gallery (folder-gallery)

An iOS photo gallery written in Swift/UIKit. The owner's goal: it must look and behave like the stock iOS Photos app everywhere, with one addition — photos are sorted into folders automatically (camera / screenshots / saved-from-app / screen recordings / per-app), plus an "unsorted" tab, a Face ID-gated sorter, and a hidden-albums tab. The owner writes Korean; answer in Korean. Code comments are short Korean sentences.

## State of the code (read before changing anything)

Everything up to and including the data-layer restructure has been written **without ever running the app**: there was no Mac, so each change was only compile-checked on GitHub Actions and then judged from screen recordings of a phone. Treat every screen as unverified. The most recent and riskiest changes are listed under "Verify first".

- `project.yml` — XcodeGen project. Deployment target iOS 17, Swift 5 language mode. Bundle id is in this file.
- `.github/workflows/build.yml` — unsigned build on `macos-15` with the newest installed Xcode; uploads `Gallery-ipa`. Runs on every push to `main`.
- `Sources/AssetList.swift` — list type used by every screen. Backed by a `PHFetchResult` (library, user albums, videos, favourites), an array (classified groups from the background pass), or saved identifiers resolved in chunks of 500 (classified groups at launch). `version` changes only when membership or order changes.
- `Sources/Library.swift` — snapshot of folders and lists. Quick snapshot at launch (album structure, covers, fetch-backed lists, saved group ids), then a full background pass that classifies and is the source of truth. `photoLibraryDidChange` patches fetch-backed lists and subtracts deleted/moved ids immediately, then schedules a full rebuild.
- `Sources/Classifier.swift` — camera / saved / recording classification with an on-disk cache. Uses a private `importProperties` probe guarded by a marker file; do not loosen that guard.
- `Sources/GridViewController.swift` — photo grid, `PhotoGridLayout` (1/3/5/7 columns, pinch zoom with a timed cross-fade when the column count switches), selection mode, album cover header, day sections for the root grids.
- `Sources/ViewerViewController.swift` — photo viewer (paging, zoom, info panel, Live Photo, inline video, thumbnail strip, its own bottom `UIToolbar`).
- `Sources/PhotoTransition.swift` — custom grid ↔ viewer transition (only the photo flies; drag down to close follows the finger).
- `Sources/FoldersViewController.swift` — album list (auto row + user album cards, real Photos folders, drag reorder, hidden tab lock). Album cards open with the system zoom transition; folders push sideways.
- `Sources/PhotoInfo.swift`, `Sources/Sorter.swift`, `Sources/Helpers.swift`, `Sources/Groups.swift`, `Sources/AppDelegate.swift`.

## Build and run on a Mac

```sh
brew install xcodegen        # once
xcodegen generate
xcodebuild -project Gallery.xcodeproj -scheme Gallery -destination 'platform=iOS Simulator,name=<a simulator>' -derivedDataPath build build
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/Gallery.app
xcrun simctl privacy booted grant photos <bundle id from project.yml>
xcrun simctl launch booted <bundle id>
xcrun simctl io booted screenshot shot.png      # or: recordVideo out.mp4
xcrun simctl addmedia booted <image/video files>  # sample photos
```

Check the scheme and project names against what `xcodegen generate` actually produces. There is no UI-test target yet; add one if gestures (pinch, drag to close, long-press selection) need to be driven and recorded.

## Rules set by the owner

- **Verify in the Simulator with sample photos only.** Do not capture or record the owner's real phone screen, and do not pull anything from a real photo library. If a problem can only be seen on the real phone, ask first.
- Do not sign in to any Apple account or change signing settings; the owner does account steps themselves. The Mac may be borrowed — leave nothing signed in and do not change its system settings.
- Photos and locations never leave the device. Deletions always go through the iOS confirmation. In-app diagnostics show counts and statistics only (no file names, album names, or photo content).
- This repository is public: never commit personal data, credentials, device identifiers, or real photos. Sample images for the Simulator must be generated or clearly free to use.
- Commit and push only when the owner asks. A push to `main` starts a CI build.
- Say plainly what was verified by running and what was only compiled.

## Verify first (written blind, never run)

1. Launch: album tab appears at once; auto row and unsorted come from saved ids on the second launch; no crash when photos were deleted in the stock app in between.
2. Library tab and albums open instantly; day headers in the root grids are correct before and after the background sections arrive; no jump.
3. Open/close a photo from an album (oldest-first and newest-first) and from deep in the library: the photo returns to the right cell. Paging, thumbnail strip, swipe at both ends.
4. Delete and move-to-album from the viewer and from grid selection; favourite; date adjust; album sort toggle; sorter.
5. Viewer chrome: the viewer's own bottom toolbar position and look, thumbnail strip position, tap to hide chrome, video controls, info panel; drag down to close — chrome fades with the finger and returns when the finger moves back; cancel restores everything; tab bar returns after closing.
6. Pinch in an album and in the library: one solid arrangement scaling with the fingers, a short cross-fade when the column count switches, settles on release, anchor photo stays under the fingers.
7. Album card zoom open/close (no jolt at the end), folders pushing sideways, back swipes.

Known differences from stock that are not done: no cover-less compact title at 1 column, no library year/month views, no search, Live Photo loop/bounce, captions.
