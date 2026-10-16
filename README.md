# NotchFlow

**Turn your MacBook's notch into a clipboard, a shelf, a media player and a menu bar drawer.**

NotchFlow is a free, open-source macOS app that lives in the notch. Hover over the notch (or
click it, or press a shortcut) and it smoothly expands into a dark panel with everything you
reach for all day. On Macs and external displays without a notch, it draws a small virtual
notch at the top of the screen instead.

It's a single native app, written in Swift with AppKit and SwiftUI. It needs no account, has no
analytics, and your data never leaves your Mac.

## Features

### Notch
- Opens when the cursor comes near the notch, when you drag a file toward it, when you click
  it, or from a keyboard shortcut. Closes when you move away, click elsewhere or press Esc.
- Fits the exact shape of your notch and animates smoothly between closed and open.
- Small live indicators beside the closed notch: an orange mic while an app is recording,
  album artwork and an equalizer while music plays, and the battery level when you plug in.

### Clipboard
- Keeps a history of the text, links, images and files you copy (up to 200 items, plus anything
  you pin).
- **Search includes text inside images**: copied screenshots are read on-device with Apple's
  Vision framework.
- Click a card to copy it again, pin favorites, or drag items out into other apps.
- Never saves passwords: content that password managers mark as private is skipped.

### Shelf
- Drag files, links or text onto the notch to park them for later, then drag them out wherever
  you need them.
- YouTube links show their title and thumbnail. If you've installed
  [yt-dlp](https://github.com/yt-dlp/yt-dlp) yourself, you can download videos from the shelf.
  Only download videos you have the right to save.

### Status
- **Now Playing**: artwork, title, progress and play/pause/skip for Music and Spotify, plus
  every other player, browsers included, when you turn on universal media support.
- **Battery**: level, charging state and time remaining.
- **Microphone**: whether any app is recording, and which one (useful with dictation apps like
  Wispr Flow).

### Menu bar drawer
- A row along the bottom of the open notch with quick-launch buttons for Claude, Wispr Flow,
  Spotlight and Siri (whichever you have installed).
- Shows **all your menu bar icons, including ones hidden behind the notch** (marked with an
  orange dot), and clicking one opens its menu.

## Requirements

- macOS 14 Sonoma or later
- Any Mac. It's designed around the MacBook notch but works on every screen.

## Install

1. Download `NotchFlow-x.y.z.zip` from the [latest release](../../releases/latest) and unzip it.
2. Move **NotchFlow.app** to your **Applications** folder.
3. Open it. NotchFlow isn't signed with a paid Apple Developer certificate yet, so macOS blocks
   the first launch:
   - Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next
     to the NotchFlow message. Confirm with your password.
   - You only need to do this once.

NotchFlow has no Dock icon. Look for its icon in the menu bar to open Settings or quit.

## Permissions

NotchFlow works without any special permissions. Some features ask for one the first time you
use them:

| Permission | Used for | Needed? |
|---|---|---|
| Automation (Music, Spotify) | Showing what's playing and play/pause/skip | Only for Now Playing in those apps |
| Accessibility | Listing and clicking menu bar icons, opening Spotlight from the drawer | Only for the menu bar drawer |
| Screen Recording | Showing the real menu bar icon pictures instead of app icons | Optional; nothing is recorded or saved |

You can see and change them in **NotchFlow Settings** and in **System Settings → Privacy &
Security**.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌃⌥Space | Open or close the notch |
| ⌃⌥V | Open the clipboard and search it. Press Return to copy the top match |
| ⌘1, ⌘2, ⌘3 | Switch tabs (while the notch is focused) |
| Esc | Close the notch |

## Privacy

- Clipboard history and the shelf are stored only on your Mac, in
  `~/Library/Application Support/NotchFlow/`. Deleting that folder removes them.
- Text recognition runs on-device. Nothing is uploaded.
- The only network requests are fetching YouTube titles and thumbnails, and Spotify album art.
- You can pause clipboard history or clear it any time in Settings.

## Build from source

You need Xcode 16 or later.

```bash
git clone https://github.com/hashirsulthan0-cmd/open-source-app.git
cd open-source-app
open NotchFlow.xcodeproj
```

Press **⌘R** in Xcode to build and run. To build a release zip like the ones on the Releases
page:

```bash
scripts/build-release.sh
```

**Tip for development builds:** debug builds are re-signed on every build, so macOS may
silently stop honoring the Accessibility permission. If the menu bar drawer stops seeing icons
after a rebuild, remove NotchFlow from **System Settings → Privacy & Security →
Accessibility** with the **−** button and add it again.

### Project layout

| Folder | What's inside |
|---|---|
| `NotchFlow/App` | App startup and the menu bar icon |
| `NotchFlow/Notch` | The notch window, its geometry, and open/close behavior |
| `NotchFlow/Clipboard` | Clipboard history and OCR |
| `NotchFlow/Shelf` | The shelf, YouTube previews and yt-dlp downloads |
| `NotchFlow/NowPlaying` | Music and Spotify support, and universal media support |
| `NotchFlow/System` | Battery, microphone and global keyboard shortcuts |
| `NotchFlow/MenuBar` | Menu bar icon scanning, clicking and quick launch |
| `NotchFlow/Settings` | Preferences and the Settings window |
| `NotchFlow/Views` | SwiftUI views for everything inside the notch |
| `ThirdParty` | mediaremote-adapter, built from source by an Xcode build phase |

## Contributing

Issues and pull requests are welcome. For bigger changes, please open an issue first so we can
talk about the approach.

## Known limitations

- **Universal media support** relies on [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter),
  which works around an Apple restriction added in macOS 15.4. A future macOS update could
  break it until the adapter is updated. Music and Spotify support doesn't depend on it.
- **Menu bar drawer** depends on how macOS exposes menu bar icons, which changed in macOS 26.
  Some apps' icons may not respond to clicks from the drawer.
- Releases are not yet notarized by Apple, so the first launch needs the one-time
  **Open Anyway** step above.

## License

Released under the [MIT License](LICENSE).

## Credits

Universal Now Playing support uses [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
by Jonas van den Berg and contributors, included in `ThirdParty/` under the BSD 3-Clause License
(see `ThirdParty/mediaremote-adapter/LICENSE`).

NotchFlow is an independent project. It is not affiliated with Apple or with any other notch or
menu bar app.
