---
version: alpha
name: macOS (Apple HIG)
description: Official Apple Human Interface Guidelines preset tailored for macOS desktop applications.
colors:
  primary: "#0088FF"
  primary-dark: "#0091FF"
  system-blue: "#0088FF"
  system-blue-dark: "#0091FF"
  system-red: "#FF383C"
  system-red-dark: "#FF4245"
  system-orange: "#FF8D28"
  system-orange-dark: "#FF9230"
  system-yellow: "#FFCC00"
  system-yellow-dark: "#FFD600"
  system-green: "#34C759"
  system-green-dark: "#30D158"
  system-mint: "#00C8B3"
  system-mint-dark: "#00DAC3"
  system-teal: "#00C3D0"
  system-teal-dark: "#00D2E0"
  system-cyan: "#00C0E8"
  system-cyan-dark: "#3CD3FE"
  system-indigo: "#6155F5"
  system-indigo-dark: "#6D7CFF"
  system-purple: "#CB30E0"
  system-purple-dark: "#DB34F2"
  system-pink: "#FF2D55"
  system-pink-dark: "#FF375F"
  system-brown: "#AC7F5E"
  system-brown-dark: "#B78A66"
  system-gray: "#8E8E93"
  system-gray-dark: "#8E8E93"
  system-gray2: "#AEAEB2"
  system-gray2-dark: "#636366"
  system-gray3: "#C7C7CC"
  system-gray3-dark: "#48484A"
  system-gray4: "#D1D1D6"
  system-gray4-dark: "#3A3A3C"
  system-gray5: "#E5E5EA"
  system-gray5-dark: "#2C2C2E"
  system-gray6: "#F2F2F7"
  system-gray6-dark: "#1C1C1E"
  surface: "#F2F2F7"
  surface-dark: "#1C1C1E"
  on-surface: "#000000"
  on-surface-dark: "#FFFFFF"
  outline: "#D1D1D6"
  outline-dark: "#3A3A3C"
typography:
  large-title: { fontFamily: "SF Pro", fontSize: "26px", fontWeight: 400, lineHeight: "32px", letterSpacing: "0.22px" }
  title-1: { fontFamily: "SF Pro", fontSize: "22px", fontWeight: 400, lineHeight: "26px", letterSpacing: "-0.26px" }
  title-2: { fontFamily: "SF Pro", fontSize: "17px", fontWeight: 400, lineHeight: "22px", letterSpacing: "-0.43px" }
  title-3: { fontFamily: "SF Pro", fontSize: "15px", fontWeight: 400, lineHeight: "20px", letterSpacing: "-0.23px" }
  headline: { fontFamily: "SF Pro", fontSize: "13px", fontWeight: 700, lineHeight: "16px", letterSpacing: "-0.08px" }
  body: { fontFamily: "SF Pro", fontSize: "13px", fontWeight: 400, lineHeight: "16px", letterSpacing: "-0.08px" }
  callout: { fontFamily: "SF Pro", fontSize: "12px", fontWeight: 400, lineHeight: "15px", letterSpacing: "0px" }
  subheadline: { fontFamily: "SF Pro", fontSize: "11px", fontWeight: 400, lineHeight: "14px", letterSpacing: "0.06px" }
  footnote: { fontFamily: "SF Pro", fontSize: "10px", fontWeight: 400, lineHeight: "13px", letterSpacing: "0.12px" }
  caption-1: { fontFamily: "SF Pro", fontSize: "10px", fontWeight: 400, lineHeight: "13px", letterSpacing: "0.12px" }
  caption-2: { fontFamily: "SF Pro", fontSize: "10px", fontWeight: 500, lineHeight: "13px", letterSpacing: "0.12px" }
rounded:
  none: "0px"
  full: "9999px"
spacing:
  none: "0px"
  xs: "4px"
  sm: "8px"
  md: "16px"
  lg: "20px"
  xl: "24px"
  xxl: "32px"
components:
  image-button: { padding: "10px", rounded: "{rounded.none}" }
  help-button: { rounded: "{rounded.full}" }
  stack-view: { gap: "{spacing.sm}" }
---

## Overview
This preset codifies the official macOS Human Interface Guidelines (HIG) and AppKit specifications for desktop applications. Desktop macOS interfaces rely on pointer precision, direct manipulation, and subtle visual depth. macOS measures layout and type in points (pt); at 1x scale one point is one pixel, so this preset writes pt values as px (derived 1:1 conversion).

## Colors
macOS utilizes two color architectures: a unified system palette with explicit light and dark sRGB definitions, and semantic AppKit system colors that adapt dynamically to appearance, vibrancy, and desktop tinting. The primary accent defaults to system blue (`#0088FF` light, `#0091FF` dark). Semantic roles without published static hex values (such as `labelColor`, `separatorColor`, and `windowBackgroundColor`) adapt dynamically at runtime; for static fallback environments, `surface` derives from `systemGray6` (`#F2F2F7` / `#1C1C1E`), `outline` from `systemGray4` (`#D1D1D6` / `#3A3A3C`), and `on-surface` uses high-contrast text (`#000000` / `#FFFFFF`).

| Token Role | Light Hex | Dark Hex | Source / Note |
| :--- | :--- | :--- | :--- |
| primary (systemBlue) | #0088FF | #0091FF | Apple HIG Specifications (sRGB) |
| systemRed | #FF383C | #FF4245 | Apple HIG Specifications (sRGB) |
| systemOrange | #FF8D28 | #FF9230 | Apple HIG Specifications (sRGB) |
| systemYellow | #FFCC00 | #FFD600 | Apple HIG Specifications (sRGB) |
| systemGreen | #34C759 | #30D158 | Apple HIG Specifications (sRGB) |
| systemMint | #00C8B3 | #00DAC3 | Apple HIG Specifications (sRGB) |
| systemTeal | #00C3D0 | #00D2E0 | Apple HIG Specifications (sRGB) |
| systemCyan | #00C0E8 | #3CD3FE | Apple HIG Specifications (sRGB) |
| systemIndigo | #6155F5 | #6D7CFF | Apple HIG Specifications (sRGB) |
| systemPurple | #CB30E0 | #DB34F2 | Apple HIG Specifications (sRGB) |
| systemPink | #FF2D55 | #FF375F | Apple HIG Specifications (sRGB) |
| systemBrown | #AC7F5E | #B78A66 | Apple HIG Specifications (sRGB) |
| systemGray | #8E8E93 | #8E8E93 | Apple HIG Specifications (sRGB) |
| systemGray2 | #AEAEB2 | #636366 | Apple HIG Specifications (sRGB) |
| systemGray3 | #C7C7CC | #48484A | Apple HIG Specifications (sRGB) |
| systemGray4 | #D1D1D6 | #3A3A3C | Apple HIG Specifications (sRGB) |
| systemGray5 | #E5E5EA | #2C2C2E | Apple HIG Specifications (sRGB) |
| systemGray6 | #F2F2F7 | #1C1C1E | Apple HIG Specifications (sRGB) |
| surface (derived) | #F2F2F7 | #1C1C1E | Derived from systemGray6 fallback |
| on-surface (derived) | #000000 | #FFFFFF | High-contrast label fallback |
| outline (derived) | #D1D1D6 | #3A3A3C | Derived from systemGray4 fallback |

## Typography
The system typeface for macOS is SF Pro. macOS does not support iOS Dynamic Type; instead, apps use built-in text styles or standard AppKit control font metrics (`NSFont.systemFontSize` = 13pt, `smallSystemFontSize` = 11pt, `labelFontSize` = 10pt). All point values translate 1:1 to px at 1x resolution.

| Text Style | Weight | Emphasized | Size | Line Height | Tracking |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Large Title | Regular (400) | Bold (700) | 26px | 32px | +0.22px |
| Title 1 | Regular (400) | Bold (700) | 22px | 26px | -0.26px |
| Title 2 | Regular (400) | Bold (700) | 17px | 22px | -0.43px |
| Title 3 | Regular (400) | Semibold (600) | 15px | 20px | -0.23px |
| Headline | Bold (700) | Heavy (800) | 13px | 16px | -0.08px |
| Body | Regular (400) | Semibold (600) | 13px | 16px | -0.08px |
| Callout | Regular (400) | Semibold (600) | 12px | 15px | 0.00px |
| Subheadline | Regular (400) | Semibold (600) | 11px | 14px | +0.06px |
| Footnote | Regular (400) | Semibold (600) | 10px | 13px | +0.12px |
| Caption 1 | Regular (400) | Medium (500) | 10px | 13px | +0.12px |
| Caption 2 | Medium (500) | Semibold (600) | 10px | 13px | +0.12px |

Fallback Policy: Apple's San Francisco (SF Pro) font license strictly restricts its use to software running on Apple operating systems and prohibits bundling on non-Apple platforms. When generating or rendering forms targeting Windows, the agent must fall back to Segoe UI Variable or Segoe UI (Windows system fonts) or Inter (open-source neutral grotesque), matching SF Pro typographic metrics as closely as possible.

## Layout
macOS layout follows the system's standard spacing; Apple publishes few fixed numbers.
- Spacing: Standard sibling spacing between related controls is 8px (default `NSStackView.spacing` = 8.0pt).
- The other spacing tokens (4, 16, 20, 24, 32px) and the 20px window content margin are [unverified]: Apple does not publish them as constants; they are a RAD Agent convention on the same 4/8px rhythm. Prefer 8px between controls and a consistent margin around window content.
- Window Anatomy: A window consists of a top frame (title bar, toolbar, window controls) and a body content area. Window titles may sit inline with toolbar items.
- Bottom Margin Rule: Avoid positioning critical actions or primary controls along the bottom edge of a window; users frequently position windows such that bottom edges clip below screen viewports.

## Elevation & Depth
Depth in macOS is primarily expressed through translucent materials and vibrancy rather than prominent elevation drop shadows.
- Vibrancy: Background materials blend underlying desktop or window content via two modes: behind-window blending and within-window blending.
- Window States: Inactive windows automatically disable vibrancy and dim controls to gray, visually receding behind the active key window.
- Surface Hierarchy: Separate content regions using split views, visual effect materials, or subtle 1px dividers rather than elevated card shadows.
- Cast Shadows: Drop shadows are reserved for floating window frames, popovers, and contextual menus rendered by the window manager; avoid applying heavy artificial drop shadows to in-window buttons or cards.

## Shapes
Apple does not publish public numeric corner radius tokens for standard macOS controls or window frames.
- Standard Controls: Push buttons, text fields, search bars, and pop-up buttons rely on system bezel styles (`NSButton.BezelStyle.push`) where geometry and corner radii are rendered dynamically by AppKit.
- Help Buttons: Strictly circular (`rounded.full` / `9999px`) containing a centered question mark glyph.
- Custom Surfaces: For bespoke cards and unbordered containers, maintain smooth continuous curvature matching system styling, or omit arbitrary corner radii (`rounded.none` / `0px`) to prevent visual clashes with native system bezels.

## Components
- Push Button: The standard button type in macOS. Features fixed system height governed by `NSControl.ControlSize` (regular, small, mini). Use flexible-height buttons (`NSButton.BezelStyle.flexiblePush`) only when hosting multi-line text or custom icons. Append trailing ellipses when invoking secondary dialogs.
- Image Button: Interactive borderless or bezel-less image/icon button. Requires 10px interior padding between the image bounding box and clickable bounds to ensure accurate mouse targeting.
- Help Button: Circular button placed in the lower corner opposite dialog dismissal buttons (or lower-left/right in setting panes). Limit to one help button per window.
- Control Sizing: Controls support regular (default, 13px font), small (11px font for inspectors and dense toolbars), and mini (9px font for compact utility panels).
- Table View: Supports alternating row background colors for wide datasets. Column headers support interactive click-to-sort and click-to-reverse sorting.
- Stack View: Sibling views align horizontally or vertically with default minimum spacing of 8px (`NSStackView.spacing`).
- Icons: RAD Agent's glyph catalog (`rad.design_icons`) is Segoe Fluent Icons, a Windows font. This preset's own icon set is not installed on Windows; ship icons as images (SVG or multi-resolution PNG) in an image list, or use Segoe Fluent Icons on Windows and say so in DESIGN.md. [policy: RAD Agent guidance, not a value from the preset's source]

## Do's and Don'ts
- Do use Body (13px Regular) as the baseline for content labels and Headline (13px Bold) for standard field headers.
- Do maintain 8px spacing between adjacent controls and 20px margins around window content areas.
- Do place help buttons in the bottom corner opposite standard dismissal buttons (OK/Cancel).
- Don't hardcode arbitrary corner radius values on standard buttons or text inputs; let system bezels render native curves.
- Don't place critical buttons or indicators at the bottom edge of a window.
- Don't apply heavy drop shadows to inline UI cards or buttons; express hierarchy through materials, grouping, and subtle dividers.
- Don't bundle SF Pro font files with non-Apple platform applications; configure Segoe UI Variable or Inter as fallbacks.

## Sources
- Apple Human Interface Guidelines - Typography: `https://developer.apple.com/design/human-interface-guidelines/typography` (JSON: `/tutorials/data/design/human-interface-guidelines/typography.json`). Values: macOS built-in text styles table (Large Title through Caption 2: size, leading, weight, emphasized weight), macOS tracking values table (sizes 6–96pt), and dynamic font variants. Retrieval date: Sun Sep 27 2026. License/Terms: Apple Website Terms of Use.
- Apple Human Interface Guidelines - Color: `https://developer.apple.com/design/human-interface-guidelines/color` (JSON: `/tutorials/data/design/human-interface-guidelines/color.json`). Values: Unified system color hex values light and dark (systemBlue #0088FF/#0091FF, Red, Orange, Yellow, Green, Mint, Teal, Cyan, Indigo, Purple, Pink, Brown), system gray palette, and AppKit semantic color role descriptions. Retrieval date: Sun Sep 27 2026. License/Terms: Apple Website Terms of Use.
- Apple Human Interface Guidelines - Buttons: `https://developer.apple.com/design/human-interface-guidelines/buttons` (JSON: `/tutorials/data/design/human-interface-guidelines/buttons.json`). Values: Push button behavior, flexible-height push button rules, help button placement table, and image button padding (10px). Retrieval date: Sun Sep 27 2026. License/Terms: Apple Website Terms of Use.
- Apple Human Interface Guidelines - Layout: `https://developer.apple.com/design/human-interface-guidelines/layout` (JSON: `/tutorials/data/design/human-interface-guidelines/layout.json`). Values: Window layout principles, bottom-margin positioning caveats, and safe areas. Retrieval date: Sun Sep 27 2026. License/Terms: Apple Website Terms of Use.
- Apple Human Interface Guidelines - Materials: `https://developer.apple.com/design/human-interface-guidelines/materials` (JSON: `/tutorials/data/design/human-interface-guidelines/materials.json`). Values: Vibrancy guidance, behind-window and within-window blending modes. Retrieval date: Sun Sep 27 2026. License/Terms: Apple Website Terms of Use.
- Apple Developer Documentation - AppKit NSFont: `https://developer.apple.com/documentation/appkit/nsfont` (JSON: `/tutorials/data/documentation/appkit/nsfont/systemfontsize.json`, `smallsystemfontsize.json`, `labelfontsize.json`). Values: systemFontSize (13pt), smallSystemFontSize (11pt), labelFontSize (10pt). Retrieval date: Sun Sep 27 2026. License/Terms: Apple Website Terms of Use.
- Apple Developer Documentation - AppKit NSStackView & NSControl: `https://developer.apple.com/documentation/appkit/nsstackview/spacing` and `https://developer.apple.com/documentation/appkit/nscontrol/controlsize-swift.enum`. Values: NSStackView.spacing default (8.0pt), NSControl.ControlSize cases (regular, small, mini, large). Retrieval date: Sun Sep 27 2026. License/Terms: Apple Website Terms of Use.
- Apple Developer Fonts Terms: `https://developer.apple.com/fonts/`. Values: Software License Agreement for the Apple San Francisco Font, Section 2 restrictions prohibiting embedding, distribution, or use on non-Apple operating systems. Retrieval date: Sun Sep 27 2026. License/Terms: Proprietary Apple Developer License.

### Usage Notes
- Font Bundling: The Apple San Francisco (SF Pro) font is proprietary and strictly licensed by Apple Inc. for mockups and apps running solely on Apple platforms (iOS, macOS, tvOS, watchOS, visionOS). It cannot be bundled, embedded, or distributed with software running on Windows or other non-Apple operating systems. On Windows, applications must fall back to system fonts (Segoe UI / Segoe UI Variable) or open-source typefaces (Inter).
- Trademarks: "macOS", "Apple", "AppKit", "Cocoa", and "SF Pro" are trademarks of Apple Inc.
- Derived Values: macOS points (pt) are converted to pixels (px) at 1:1 for standard 1x displays (96 DPI coordinate space). Semantic color hex values (surface, on-surface, outline) are derived fallbacks from Apple's official system gray palette because AppKit defines native semantic colors as dynamic vibrant materials rather than static hex values.
- Unpublished Values: Exact numeric corner radii for standard push buttons and window frames, as well as fixed component heights for standard push buttons, are intentionally not published by Apple as public constants and are omitted from explicit token definitions.
