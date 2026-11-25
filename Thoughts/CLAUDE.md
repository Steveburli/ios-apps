# Thoughts

A native SwiftUI notes app (iOS 18+, iPhone, portrait, light and dark) in the style of block-based workspace apps: pages that nest inside pages, a block editor with a "/" menu and Markdown shortcuts, and databases shown as a table, board or list. It was built from scratch on 2026-11-25 at the user's request for a Notion-style iPhone app. The name, look, icon and wording are its own. Don't copy another product's name, logo, artwork or text into it.

## Layout

- `Thoughts.xcodeproj` is an Xcode 16 synchronized-folder project (objectVersion 77). Files added under `Thoughts/` join the app target automatically, so never edit `project.pbxproj` just to add a file.
- `Packages/ThoughtsKit` holds Foundation-only logic plus XCTest:
  - `Block`: `BlockKind` (text, three headings, bulleted, numbered, to-do, toggle, quote, callout, divider, code, page link) and `Block`. A page's body is a flat array of blocks, and nesting is `Block.indent`: a block's children are the blocks right after it with a deeper indent. A closed toggle hides them.
  - `BlockEditing`: the editor's rules as pure functions on `[Block]`. Return splits at the cursor and lists carry on; Return on an empty list item steps out. Backspace at the start turns a styled block into text, then outdents, then joins the block above. It also handles indent and outdent (at most one level deeper than the block above), move up and down (with children), delete, duplicate, numbering, and which blocks show. Cursor offsets are UTF-16, the way UITextView counts.
  - `Shortcuts` (`MarkdownShortcut`): `# `, `## `, `### `, `- `/`* `, `1. `, `[] `/`[x] `, `> ` (toggle), `" ` (quote), `---`, and three backticks.
  - `SlashCommands`: the "/" menu's items, `filter` (title starts first, then keywords, then title contains) and `activeQuery` (the "/word" being typed at the end of a block).
  - `Page` and `Workspace`: pages keyed by ID with `parentID` and `order`. Workspace handles create (`createSubpage` adds a link block to a document parent), move (the link follows the page, and loops are refused), reorder, favorites, recents, the Trash (only the trashed page is marked; its subpages count as in the Trash through `isInTrash`), restore, delete forever (links to deleted pages are removed), and duplicate (copies subpages and points links inside the copy at the copies).
  - `Properties`: database columns (`PropertyDefinition` of text, number, select, multi-select, date, checkbox or URL), `PropertyValue`, `DatabaseSchema` (layout, board group-by, sort, a select or checkbox filter). A database is a page with `kind == .database`; its rows are its child pages, and each row's values are keyed by property ID string. `Workspace` adds `rows(of:)` (filtered and sorted, empty values last), `boardColumns`, `moveRow`, and adding, retyping (values convert: text becomes options) and deleting properties and options.
  - `Search`: every word must match title, writing or text values, ignoring case and accents. Title matches come first.
  - `Markdown` (`MarkdownExport`) for sharing, and `Templates` (meeting notes, to-do, journal, weekly plan, Projects board, Reading list) plus `Workspace.sample`, which a new install opens with.
- `Thoughts/App`: `AppModel` owns the workspace and saves `workspace.json` in Application Support 0.6 s after a change and whenever the app leaves the foreground. It also holds each tab's navigation path (pages are pushed by `UUID`), the open tree rows (`expanded.v1`) and the appearance setting. `ThoughtsApp` has the three tabs: Home, Search, Settings.
- `Thoughts/Home`: recents ("Jump back in"), Favorites, the page tree (Private) and templates. Touch and hold a page for Favorite, Duplicate, Move to…, Share as Markdown and Move to Trash (`PageMenuItems`, also the page's "…" menu).
- `Thoughts/Page`: `PageScreen` (cover, icon, title, row properties, then blocks or the database). `BlockTextView` wraps a `UITextView` because SwiftUI can't see Backspace on an empty line or stop Return. Its `cursorRequest` takes the keyboard with the cursor at an offset. `EditorState` tracks the focused block, the pending cursor and the "/" menu. `BlockActions` turns each key or toolbar tap into a `BlockEditing` call. `BlockViews` holds the block rows, the "/" menu and the bar above the keyboard (insert, turn into, tick, indent, outdent, move, duplicate, delete, hide keyboard). Tapping below the last block starts a new line.
- `Thoughts/Database`: `DatabaseBody` (layout, sort and filter menus, properties, New), the table (scrolls sideways; tap a cell to edit it in a sheet), the board (drag cards between columns or use Move to; "Add a group" adds an option) and the list. `PropertyViews` has the value controls used on row pages and in cells, and the properties editor.
- `Thoughts/Search`, `Thoughts/Settings` (appearance, Trash, export everything as Markdown, add the example pages again) and `Thoughts/Support` (theme, screenshots).

## Commands

```bash
cd Packages/ThoughtsKit && swift test
xcodebuild -project Thoughts.xcodeproj -scheme Thoughts -destination 'generic/platform=iOS Simulator' build
```

## Rules

- Editing rules live in the Kit (`BlockEditing`, `Workspace`), with a test for each. The views only call them.
- Every saved type decodes field by field with defaults, so older `workspace.json` files keep loading. Never rename a stored field.
- Swift 5 language mode is deliberate.
- Commit, push, or change signing and the bundle ID only when the user asks.

## How this repo is worked on

- Code is edited without a Swift compiler; the GitHub cloud Mac checks it. `.github/workflows/build.yml` runs `swift test` for ThoughtsKit and an unsigned Simulator build on every push to `main` (or Run workflow on a branch). The `report-Thoughts` artifact has `errors.txt`, `screens/` (screens opened with `-screenshots home|page|slash|table|board|row|search|settings`, see `Support/Screenshots.swift`, plus a dark-mode home), `app-log.txt` and any crash reports. Look at the screenshots after UI changes.
- TestFlight: push a tag `testflight-Thoughts-<n>`, or Run workflow on `testflight.yml`. Before the first upload, the App ID `com.steveburlison.thoughts` and an app record named Thoughts must exist in App Store Connect (the workflow creates the provisioning profile itself).

## Status (2026-11-25)

Version 1 is written: nested pages, the block editor, the "/" menu and Markdown shortcuts, toggles, to-dos with a progress line, callouts, code, page links, covers and icons, favorites, recents, search, the Trash, templates, Markdown export, and databases with table, board and list views, sorting, filtering and seven property types. It has not run on a phone yet.

Not in version 1: sync and sharing (everything stays on the phone), undo, inline text styling (bold, links), images and files, block drag handles, more than one view per database, and relations or formulas.

## Next tasks, in order

1. Keep the GitHub build green after every change.
2. Create the App ID and app record, then ship a TestFlight build (ask the user first). On the phone, check typing across blocks: Return and Backspace at line edges, "/" then Return, every Markdown shortcut, and the toolbar while the keyboard is up.
3. Likely next features: undo, bold/italic/links in text, iCloud sync (`CKSyncEngine`, as in Do This Now's trips), images, and a Lock Screen widget for a quick note.
