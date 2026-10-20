# External Widget Bundles

Docky loads community widgets as native macOS bundles. This contract is backward-compatible: the original view method remains required, while settings and locale-aware rendering are optional.

## Install location

```text
~/Library/Application Support/Docky/Widgets/
```

Use the `.dockywidget` extension and restart Docky after installing, replacing, or removing a bundle. Discovery runs once during application startup.

## Bundle layout

```text
MyWidget.dockywidget/
  Contents/
    Info.plist
    MacOS/
      MyWidget
    Resources/
      settings.json
      en.lproj/
        DockyWidget.strings
      ru.lproj/
        DockyWidget.strings
```

Only `Info.plist` and the compiled executable are required. `settings.json` and localization resources are optional.

`Info.plist` must set `NSPrincipalClass` to the fully qualified principal class name, for example `MyWidget.MyWidget`.

## Plugin contract

The principal class must inherit from `NSObject` and conform to a copied declaration of `DockyWidgetPlugin`. The explicit Objective-C protocol name is required; without `@objc(DockyWidgetPlugin)`, Docky cannot match the plugin's protocol at runtime.

```swift
import AppKit

@objc(DockyWidgetPlugin) public protocol DockyWidgetPlugin: AnyObject {
    @objc init()

    var identifier: String { get }
    var displayName: String { get }
    var systemImageName: String { get }

    var defaultSpanValue: Int { get }
    var supportedSpanValues: [Int] { get }
    var expansionWidthTiles: Int { get }
    var expansionHeightTiles: Int { get }
    var isExpandable: Bool { get }
    var includesInPalette: Bool { get }
    var includesInSmartStack: Bool { get }

    @objc optional var author: String { get }
    @objc optional var version: String { get }

    func makeView(
        cornerRadius: CGFloat,
        renderedSpanValue: Int,
        isWithinStack: Bool,
        isExpanded: Bool,
        isExpandedPreviewOpen: Bool
    ) -> NSView

    @objc optional func makeView(
        cornerRadius: CGFloat,
        renderedSpanValue: Int,
        isWithinStack: Bool,
        isExpanded: Bool,
        isExpandedPreviewOpen: Bool,
        configuration: [String: Any]
    ) -> NSView

    @objc optional func makeView(
        cornerRadius: CGFloat,
        renderedSpanValue: Int,
        isWithinStack: Bool,
        isExpanded: Bool,
        isExpandedPreviewOpen: Bool,
        configuration: [String: Any],
        localeIdentifier: String
    ) -> NSView
}
```

`makeView` may return an `NSHostingView` or any other `NSView`.

Docky dispatches view creation in this order:

1. Configured view with `localeIdentifier`.
2. Configured view without `localeIdentifier`.
3. Required legacy view.

The locale identifier is the effective Docky interface language, such as `en`, `ru`, or a regional identifier. It is not inserted into `configuration`, so it cannot collide with a settings field ID.

## Identity and metadata

- `identifier` is persisted as `external:<identifier>`. Keep it stable across releases.
- `displayName` is the literal fallback display name.
- `systemImageName` is an SF Symbol used by Docky's editor and settings UI.
- Span values are integers from 1 through 4.
- `author` defaults to Docky's localized “Unknown” label.
- `version` defaults to `1.0`.

Changing an identifier breaks existing persisted placements. Author, version, identifiers, field IDs, and option values are never localized by Docky.

## Declarative settings

Docky owns the settings UI and persistence. A plugin opts in by shipping `Contents/Resources/settings.json`.

```json
{
  "fields": [
    {
      "id": "headline",
      "type": "text",
      "label": "Headline",
      "labelKey": "settings.headline",
      "default": "Hello"
    },
    {
      "id": "scale",
      "type": "number",
      "label": "Scale",
      "labelKey": "settings.scale",
      "default": 1.5
    },
    {
      "id": "showIcon",
      "type": "toggle",
      "label": "Show Icon",
      "labelKey": "settings.showIcon",
      "default": true
    },
    {
      "id": "style",
      "type": "select",
      "label": "Style",
      "labelKey": "settings.style",
      "default": "compact",
      "options": [
        {
          "value": "compact",
          "label": "Compact",
          "labelKey": "settings.style.compact"
        },
        {
          "value": "expanded",
          "label": "Expanded",
          "labelKey": "settings.style.expanded"
        }
      ]
    }
  ]
}
```

Supported field types:

| Type | Stored Cocoa value |
|---|---|
| `text` | `String` |
| `number` | `NSNumber` / `Double` |
| `toggle` | `NSNumber` / `Bool` |
| `select` | `String` option `value` |

Malformed fields are skipped. Missing labels fall back to the field `id`; missing option labels fall back to the option `value`. Unknown field types are skipped. Docky passes the persisted values to configured view methods as Cocoa primitives in `configuration`.

Do not change field IDs or option values after release. They are persistence and behavior tokens, not display text.

## Plugin-owned localization

Put widget translations in:

```text
Contents/Resources/<language>.lproj/DockyWidget.strings
```

Reserved and manifest keys share this table:

```text
"widget.displayName" = "My localized widget name";
"settings.headline" = "Headline";
"settings.style.compact" = "Compact";
```

`widget.displayName` localizes the plugin display name. `labelKey` localizes a field or option label.

Docky resolves every key independently:

1. Effective regional or base interface language.
2. English.
3. Literal `displayName`, `label`, field `id`, or option `value`.

This per-key fallback allows a partial Russian table to use English for only its missing keys. Plugin keys are always read from the plugin bundle, never Docky's main bundle. Language changes take effect after restart because plugin discovery and metadata registration run once.

## Minimal legacy plugin

```swift
import AppKit
import SwiftUI

@objc(MyWidget)
public final class MyWidget: NSObject, DockyWidgetPlugin {
    public override init() { super.init() }

    public var identifier: String { "com.example.MyWidget" }
    public var displayName: String { "My Widget" }
    public var systemImageName: String { "sparkles" }
    public var defaultSpanValue: Int { 3 }
    public var supportedSpanValues: [Int] { [1, 2, 3] }
    public var expansionWidthTiles: Int { 3 }
    public var expansionHeightTiles: Int { 3 }
    public var isExpandable: Bool { true }
    public var includesInPalette: Bool { true }
    public var includesInSmartStack: Bool { false }

    public func makeView(
        cornerRadius: CGFloat,
        renderedSpanValue: Int,
        isWithinStack: Bool,
        isExpanded: Bool,
        isExpandedPreviewOpen: Bool
    ) -> NSView {
        NSHostingView(rootView: Text("Hello from my widget"))
    }
}
```

This legacy implementation remains valid. Add `settings.json` and one or both configured overloads only when needed.

## Build and runtime constraints

- Bundle type: loadable bundle, not framework.
- Wrapper extension: `dockywidget`.
- Deployment target: macOS 14.0 or later.
- Swift compiler: compatible with the compiler used to build Docky.
- Signing: the bundle must satisfy macOS code-signing policy. Docky disables library validation under hardened runtime so other teams' valid bundles can load, but this does not bypass Gatekeeper or invalid signatures.

## Loader failures

Docky skips a failed bundle rather than blocking application launch. Console logs under subsystem `gt.quintero.Docky`, category `ExternalWidgetLoader`, distinguish:

- Bundle cannot be opened.
- Compiled executable is missing.
- `Bundle.load()` fails.
- `NSPrincipalClass` is missing.
- Principal class does not conform to `DockyWidgetPlugin`.

If a loaded widget file disappears, Docky preserves its identifier and displays a localized file-missing decoration until the layout is updated.
