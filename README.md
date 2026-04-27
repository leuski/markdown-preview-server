# MarkdownPreviewer

A small macOS menu bar app that serves a live, browser-based preview of Markdown
files from your editor. Point it at a `.md` file and it renders the document
through your chosen processor, wraps it in a styleable HTML template, and
auto-reloads the page whenever the file changes on disk.

It is designed to pair with **BBEdit**'s "Preview in Browser" hook, but the
preview URL is a plain HTTP endpoint, so any editor that can open a URL on save
works.

## How it works

The app runs an HTTP server bound to `127.0.0.1` (default port `8089`). It
exposes a few routes:

- `GET /preview/<absolute file path>` — renders a Markdown file as HTML.
- `GET /preview/<absolute file path>` for non-Markdown extensions — serves
  static assets (images, CSS, fonts, etc.) sitting next to the document.
- `GET /template/<template-id>/<file>` — serves assets bundled with the
  selected HTML template.
- `GET /events/<absolute file path>` — Server-Sent Events stream the page
  subscribes to for live reload. The injected client refreshes on each event.

When you visit `http://127.0.0.1:8089/preview/Users/you/notes/example.md`, the
server reads the file, hands it to the active renderer, substitutes
placeholders into the template, injects a small live-reload script, and
returns the result. A file watcher pushes a reload event whenever the document
or any of its sibling assets change.

## Markdown processors

The app discovers and presents a BBEdit-style picker of supported processors:

| Processor | Install |
|---|---|
| Default (swift-markdown) | bundled |
| MultiMarkdown | `brew install multimarkdown` |
| Discount | `brew install discount` |
| Pandoc | `brew install pandoc` |
| cmark-gfm | `brew install cmark-gfm` |
| Classic (Markdown.pl) | place `Markdown.pl` on `PATH` |

Unavailable processors stay visible in the menu so you can see what would be
selectable after installing the underlying tool. Your preference persists even
when the tool is missing, so reinstalling it brings the selection back without
further input.

## Templates

Output is wrapped in an HTML template. A built-in template is always available;
custom templates live in:

```
~/Library/Application Support/MarkdownPreviewer/Templates/
```

Each subdirectory there is a template. Drop in `template.html` plus any CSS,
JS, fonts, or images alongside it. The template store watches the directory
and picks up additions and edits without restarting the app.

Templates may use these placeholders, which are substituted on every render:

| Placeholder | Replaced with |
|---|---|
| `#DOCUMENT_CONTENT#` | The rendered HTML body |
| `#TITLE#` | Document base name |
| `#BASE#` | URL prefix for resolving relative links |
| `#FILE#` | Document filename |
| `#BASENAME#` | Filename without extension |
| `#FILE_EXTENSION#` | Filename extension |
| `#DATE#` | Today's date |
| `#TIME#` | Current time |

Asset references inside the template (e.g. `<link href="style.css">`) are
rewritten to point at `/template/<id>/...` so they load through the same
server.

## BBEdit integration

The app bundles two helper scripts that open the preview URL for the document
currently being edited in BBEdit:

- `Preview Markdown… in Safari.sh`
- `Preview Markdown… in Google Chrome.sh`

Use the **Install BBEdit Scripts** in the Settings (or copy the scripts
manually) into:

```
~/Library/Application Support/BBEdit/Scripts/
```

The installer rewrites the hardcoded server URL in each script to match the
running server's host and port. Run the script from BBEdit (Scripts menu, or
bind a key) and the previewer focuses an existing tab pointed at the local
server, or opens a new one if there isn't one.

Any other editor that can shell out to a URL on save can drive the preview the
same way — the server doesn't care who opens the page.

## Settings

Available from the menu bar item:

- **Port** — TCP port the server binds to (default `8089`). Restarting on
  change happens automatically if the server is running.
- **Markdown processor** — picker described above.
- **Template** — picker built from the templates directory.
- **Launch at login** — registered via `SMAppService`.

## Building

Open `MarkdownPreviewer.xcodeproj` in Xcode and run. The project targets macOS
and uses Swift's structured concurrency throughout (`@Observable`, actors,
typed `async`/`await`).

Tests use the **Swift Testing** framework:

```
swift test
```

or run the test target from Xcode.

## Project layout

```
Sources/
├── App/             AppModel, login-item registration
├── Menu/            Menu bar UI and Settings window
├── Render/          Renderer protocol + built-in and external-process renderers
├── Server/          HTTP server (FlyingFox), routes, SSE
├── Templates/       Built-in template, user-template store, placeholders
├── Watch/           File system watcher for live reload
├── Scripts/         BBEdit script installer
└── Utilities/       Small extensions

Resources/
├── Bundled/         App icon and assets
└── Scripts/         Bundled BBEdit helper scripts

Tests/               Swift Testing test suite
```

## License

[MIT](LICENSE) © Anton Leuski
