# Notes Redux

Written by Claude Code.

A native iOS note-taking app (Swift + SwiftUI, Apple frameworks only) inspired by
Apple Notes. Its main feature is **Add Entry**: type some text, pick a note and a
section, and the text is inserted at the end of that section without opening or
scrolling the note.

Product context: [`Resources/Project_Notes.txt`](Resources/Project_Notes.txt).

> **Status: first working version. All four planned stages are complete.**
> The core engine passes its unit tests (`swift test`). The app builds in CI
> and passes the simulator smoke test. See *Known limitations*.

## Build and run (Xcode 27)

Requirements: a Mac with **Xcode 27** (Xcode 26 also works) and an iOS 18 or
later simulator or device. No accounts, servers or third-party packages are
needed.

1. Clone the repository:
   ```sh
   git clone https://github.com/nwong7/ECS191_HW_Part2.git
   ```
   Keep the whole folder together. The app package finds the core library
   through the relative path `..`.
2. In Xcode, choose **File → Open…** and select the **`NotesRedux.swiftpm`**
   folder inside the clone. You can also double-click it in Finder. Don't open
   the top-level `Package.swift`: that's only the core library.
3. Wait for Xcode to finish resolving the local package (the `notes-redux`
   dependency).
4. Choose the **NotesRedux** scheme and an iPhone simulator, then press
   **Run** (⌘R).
5. *(Optional, real device only)* Select the app target, open **Signing &
   Capabilities** and choose your team.

The first launch adds three example notes from the project brief: Recipes,
Birthdays and Word List.

## Using the app

### Notes
- **Create:** tap the compose button at the bottom right of the notes list.
- **Edit:** type the title in the large field at the top of the note and the
  body below it. Every change is saved immediately.
- **Search:** pull down on the list to show the search field. Search matches
  titles and body text.
- **Delete:** swipe left on a note, long-press it, or use **•••** inside the
  note. You're always asked to confirm.

### Formatting (bar above the keyboard)
- **Headings:** put the cursor in a line, or select several lines. Open the
  style menu at the left of the bar and choose **Heading** or **Subheading**.
  Press Return at the end of a heading to go back to body text.
- **Bold / italic / underline / strikethrough:** tap these to format the
  selection or the text you type next.
- **Paste:** tap the clipboard icon and choose **Paste with Formatting** or
  **Paste without Formatting**.

### Add Entry (main feature)
1. Tap **Add Entry** in the notes list's bottom bar. Inside a note, tap the
   text-with-plus icon instead; that note is then chosen for you.
2. Type the entry. It can be more than one line.
3. Choose a **Note**, then a **Section**. Sections are headings, with
   subheadings indented, plus *End of Note*. The footer shows where the entry
   will go.
4. Tap **Add**. The entry goes at the end of that section's own text, before
   its subheadings.
5. On the confirmation screen:
   - **View in Note** opens the note, scrolls to the new lines and highlights
     them.
   - **Undo** removes exactly those lines.
   - **Done** closes the sheet.

**Cancel** changes nothing. **Add** stays disabled until there is text and a
valid destination. If the note or section is deleted while the sheet is open,
the destination is flagged in red.

*Example:* add `Josh B - 5/28/2004` to **Birthdays › Friends**. It lands
directly after the last friend and before the blank line that comes before
*School*.

### Outline (section navigation)
- Inside a note, tap the outline button (indented-list icon) in the toolbar.
  You can also tap or drag the **yellow bar on the right edge** of the screen.
- Tap a heading to jump to it.
- The section you're currently reading is highlighted. The outline updates as
  you edit.
- To close it, tap ✕, tap outside it on iPhone, or swipe it toward the edge.

### Icons, colours and grid view
- **Change an icon:** long-press a note, or use **•••** inside it, and choose
  **Change Icon…**. Pick one of 12 emoji, or the title's first letter. Then
  pick one of 9 colours.
- **Switch layout:** the button at the top right of the notes list switches
  between the list and an icon grid. Your choice is remembered.

## Design summary

- **Notes are lists of blocks.** Each paragraph is a `Block` with a UUID, a style
  (`body`, `heading`, `subheading`) and formatted text runs.
- **A section is identified by its heading block's UUID**, never by matching
  heading text. Renamed or duplicate headings can't misdirect an insertion.
- **Sections are derived, not stored.** The outline and the Add Entry picker are
  recomputed from the blocks, so they can't go out of sync with the note.
- **Insertion rule:** a new entry goes right after the last non-blank line of the
  section's *own* content: before its first subheading, and before any blank
  separator lines. Multi-line entries become several blocks, which keeps line
  breaks. Whitespace around the whole entry is trimmed; everything inside is kept.
- **Safety:** insertion is a pure function on a note value. Empty input, deleted
  notes and deleted sections raise clear errors, and nothing is written unless the
  whole operation succeeds. Undo removes exactly the blocks that were inserted.
- **Storage:** one JSON file per note in Application Support, written atomically.
  Unreadable files are moved to an `Unreadable/` folder instead of being deleted.
- **Editor:** a `UITextView` wrapper. Each paragraph's block id and style are
  stored as text attributes, and edits are reconciled back into blocks so ids
  stay stable.

## Repository layout

| Path | Contents |
|---|---|
| `NotesRedux.swiftpm` | SwiftUI iOS app package. **Open this folder in Xcode** |
| `NotesRedux.swiftpm/Editor` | `RichTextEditor` (`UITextView` wrapper), `RichTextCodec` (blocks ↔ attributed text), `ClipboardReader` |
| `NotesRedux.swiftpm/Views` | Notes list and grid, note editor and format bar, Add Entry sheet, outline panel, Change Icon sheet |
| `Package.swift` | SwiftPM package exposing the `NotesReduxCore` library |
| `Sources/NotesReduxCore/Model` | `Note`, `Block` (paragraph with stable id), `TextRun` (inline formatting) |
| `Sources/NotesReduxCore/Sections` | `SectionIndex`: derives headings/subheadings from blocks |
| `Sources/NotesReduxCore/Editing` | `Entry`, `EntryInserter` (Add Entry engine), `AddEntryDestinations`, `BlockReconciler` (editor → blocks), `ParagraphSplitter`, `PasteNormalizer` |
| `Sources/NotesReduxCore/Storage` | `NoteStore` protocol, `JSONFileNoteStore`, `InMemoryNoteStore` |
| `Sources/NotesReduxCore/Library` | `NotesLibrary` (observable source of truth), `SampleNotes` |
| `Tests/NotesReduxCoreTests` | Swift Testing suites (62 tests) for all of the above |
| `.github/` | Manual-only CI workflow and the simulator smoke-test script |

## Testing the core library

The data model, Add Entry engine, storage and paste cleanup are plain Swift with
no UI, so they can be tested on any platform with Swift 6.2 or later:

```sh
swift test
```

Run this from the repository root. On a Mac you can also open the top-level
`Package.swift` in Xcode and press ⌘U.

**On Windows**, Swift 6.4 also needs the **Windows 11 SDK (10.0.22621 or
later)**. With the older 10.0.19041 SDK, any file that imports Foundation fails
with `header 'stdnoreturn.h' not found`. To install the newer SDK, open Visual
Studio Installer and choose Modify → Individual components → *Windows 11 SDK*.
A warning about being "unable to create symbolic link at .build\debug" is
harmless. The iOS app itself can only be built on a Mac.

## Continuous integration (GitHub Actions, macOS)

`.github/workflows/ios-build.yml` runs only when started by hand
(Actions → *iOS build check* → *Run workflow*). It has read-only repository
permissions, no secrets and no code signing. On a hosted macOS runner it:

1. Selects the newest non-beta Xcode installed on the runner.
2. Runs `swift test` for the core library on macOS.
3. Builds the core library for the iOS Simulator.
4. Type-checks every app source file against the iOS SDK.
5. Builds the whole app package (`-scheme NotesRedux`) for the iOS Simulator.
6. **Smoke test** (`.github/scripts/smoke-test.sh`): installs the app on an iOS
   Simulator and launches it eight times, taking a screenshot each time:
   1. The notes list.
   2. The Birthdays note.
   3. The same note with its outline open.
   4. An Add Entry of "Josh B - 5/28/2004" into *Friends*.
   5. A plain relaunch, to show the entry was saved.
   6. The Add Entry sheet, pre-filled but not submitted.
   7. The grid view.
   8. The Change Icon sheet.

   The step fails if the app crashes, and the screenshots are attached to the
   run under *Artifacts* (kept 7 days). The app is driven through DEBUG-only
   launch arguments (`NotesRedux.swiftpm/SmokeTestHooks.swift`), with no taps
   or typing, so the screenshots have to be checked by eye. Paste isn't
   covered, because iOS asks for permission before an app reads the clipboard.

Hosted macOS minutes are free for public repositories but billed at a higher
rate than Linux minutes for private ones. Check GitHub's billing page for
current rates.

## Known limitations

- **Limited UI testing.** The app builds in CI, but the smoke test only
  launches it into fixed states. Interactive behaviour hasn't been tested
  automatically: typing, formatting, pasting, submitting the Add Entry sheet,
  and the outline gestures. All the data-integrity logic is in the tested core.
- The outline highlights the section at the top of the screen, not every
  heading that is visible.
- There's no custom app icon, so the default one is shown.
- Formatting changes made with the format bar (style, bold, etc.) can't be
  undone with the system Undo; typing can.
- Fonts follow Dynamic Type when a note is opened, not live while it is open.
- The system Edit-menu Paste pastes plain text. Use the format bar's paste
  menu to keep formatting. That menu makes iOS ask "Allow Paste?" when the
  text came from another app, unless this is allowed in Settings.
- Formatting applied by *Paste with Formatting* can't be undone with system
  Undo (the pasted text itself can). Headings in pasted HTML come in as bold
  body text.
- If saving fails (for example, the disk is full), the last keystroke is
  discarded so the screen matches what's on disk, and an alert is shown.
- Not implemented from the project notes: photo-based icons, named note
  clusters, swipe-to-switch layouts, and pin/lock/duplicate.
