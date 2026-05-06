<p align="center">
  <img src="MacOSUtilities/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="112" alt="MacOSUtilities app icon">
</p>

<h1 align="center">MacOSUtilities</h1>

<p align="center">
  <strong>Small native utilities for macOS, built to appear only when they are useful.</strong>
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111?style=flat-square">
  <img alt="Native Swift" src="https://img.shields.io/badge/Native-Swift-111111?style=flat-square">
  <img alt="Local First" src="https://img.shields.io/badge/Clipboard-Local%20First-111111?style=flat-square">
</p>

---

## Utility Suite

MacOSUtilities is a home for focused desktop tools: compact, shortcut-driven,
and quiet enough to stay out of the way.

| Utility | Status | Purpose |
| --- | --- | --- |
| `01` **Clipboard** | Available | Recall, preview, save, and restore clipboard items from a floating history panel. |
| `02` More utilities | Planned | Future tools can be added as separate modules. |

---

## Clipboard

Clipboard is the first utility in the suite. It runs in the background with no
Dock icon, watches your clipboard during the session, and opens a glass-style
panel from the top corner when you press:

<p align="center">
  <kbd>Command</kbd> + <kbd>Shift</kbd> + <kbd>V</kbd>
</p>

Choose a previous clip, restore it to the system clipboard, then paste normally
with <kbd>Command</kbd> + <kbd>V</kbd>.

|  |  |
| --- | --- |
| **History**<br>Text, rich text, URLs, files, images, and mixed pasteboard data when macOS exposes it. | **Preview**<br>Compact rows stay clean, while hover previews reveal larger content when needed. |
| **Save**<br>Move useful clips into Saved and give them short titles for quick scanning. | **Gestures**<br>Drag to reorder, slide left to delete, slide right to save. |

| Recent | Saved |
| --- | --- |
| Short-term clipboard memory for the current session. | Long-term clips you choose to keep. |
| Automatically tracks new copies. | Save from Recent with a slide-right gesture. |
| Prunes older entries based on your history length setting. | Add optional titles so saved clips are easy to scan. |
| Disappears when the app quits. | Persists locally on your Mac. |
| Best for quickly recovering something you copied moments ago. | Best for snippets, links, images, and file references you reuse. |

---

## Panel Controls

| Control | Action |
| --- | --- |
| <kbd>Command</kbd> + <kbd>Shift</kbd> + <kbd>V</kbd> | Open clipboard panel. |
| Click item | Restore item, then paste with <kbd>Command</kbd> + <kbd>V</kbd>. |
| <kbd>Escape</kbd> | Close panel. |
| Arrow keys | Move through items. |
| <kbd>Return</kbd> | Restore selected item. |
| Slide left | Delete item. |
| Slide right | Save item. |
| Drag | Reorder items. |
| Hover | Preview content. |
| Gear button | Adjust settings, history length, login item, and clear-all. |

---

## Privacy

Clipboard data stays on your Mac.

Recent history is kept in memory and disappears when the app quits. Saved clips
are stored in your user Application Support folder. MacOSUtilities does not send
clipboard contents to a server.

The app captures readable pasteboard representations exposed by macOS. Some apps
use lazy or promised clipboard data that third-party clipboard managers cannot
fully capture until the source app exposes it.
