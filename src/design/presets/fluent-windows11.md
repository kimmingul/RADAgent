---
version: alpha
name: "Windows 11 (Fluent 2)"
description: "Desktop design system preset based on Windows 11 Fluent Design and Fluent 2 guidelines, targeting desktop pointer density."
colors:
  primary: "#005FB8"
  primary-dark: "#60CDFF"
  accent-base: "#0078D4"
  on-primary: "#FFFFFF"
  on-primary-dark: "#000000"
  surface: "#FFFFFF"
  surface-dark: "#2C2C2C"
  surface-base: "#F3F3F3"
  surface-base-dark: "#202020"
  surface-secondary: "#EEEEEE"
  surface-secondary-dark: "#1C1C1C"
  on-surface: "#1A1A1A"
  on-surface-dark: "#FFFFFF"
  on-surface-secondary: "#616161"
  on-surface-secondary-dark: "#CCCCCC"
  on-surface-disabled: "#A1A1A1"
  on-surface-disabled-dark: "#5D5D5D"
  outline: "#EBEBEB"
  outline-dark: "#1C1C1C"
  outline-control: "#E0E0E0"
  outline-control-dark: "#333333"
  divider: "#E5E5E5"
  divider-dark: "#2E2E2E"
  success: "#0F7B0F"
  success-dark: "#6CCB5F"
  caution: "#9D5D00"
  caution-dark: "#FCE100"
  critical: "#C42B1C"
  critical-dark: "#FF99A4"
typography:
  caption:
    fontFamily: "Segoe UI Variable"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: "16px"
  body:
    fontFamily: "Segoe UI Variable"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: "20px"
  body-strong:
    fontFamily: "Segoe UI Variable"
    fontSize: "14px"
    fontWeight: 600
    lineHeight: "20px"
  body-large:
    fontFamily: "Segoe UI Variable"
    fontSize: "18px"
    fontWeight: 400
    lineHeight: "24px"
  body-large-strong:
    fontFamily: "Segoe UI Variable"
    fontSize: "18px"
    fontWeight: 600
    lineHeight: "24px"
  subtitle:
    fontFamily: "Segoe UI Variable"
    fontSize: "20px"
    fontWeight: 600
    lineHeight: "28px"
  title:
    fontFamily: "Segoe UI Variable"
    fontSize: "28px"
    fontWeight: 600
    lineHeight: "36px"
  title-large:
    fontFamily: "Segoe UI Variable"
    fontSize: "40px"
    fontWeight: 600
    lineHeight: "52px"
  display:
    fontFamily: "Segoe UI Variable"
    fontSize: "68px"
    fontWeight: 600
    lineHeight: "92px"
rounded:
  none: "0px"
  subtle: "2px"
  control: "4px"
  overlay: "8px"
  panel: "12px"
  full: "9999px"
spacing:
  none: "0px"
  xxs: "2px"
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "20px"
  xxl: "24px"
  gutter: "12px"
  margin-surface: "16px"
  titlebar: "32px"
  titlebar-extended: "48px"
components:
  button:
    height: "32px"
    minWidth: "64px"
    padding: "5px 11px 6px 11px"
    rounded: "{rounded.control}"
  textBox:
    height: "32px"
    minWidth: "64px"
    padding: "5px 6px 6px 10px"
    rounded: "{rounded.control}"
  comboBox:
    height: "32px"
    minWidth: "64px"
    padding: "5px 0px 7px 12px"
    rounded: "{rounded.control}"
  listItem:
    height: "40px"
    minWidth: "88px"
    padding: "0px 12px 0px 16px"
    rounded: "{rounded.control}"
  dialog:
    height: "184px"
    minWidth: "320px"
    padding: "24px"
    rounded: "{rounded.overlay}"
---

## Overview

Windows 11 Fluent 2 provides a calm, approachable visual language designed for focused desktop productivity. Layouts employ subtle tonal layering, soft rounded corners, and a single purposeful accent color to guide user attention. This preset standardizes desktop pointer density, favoring compact control heights and precise gutters over enlarged touch targets. All dimension tokens are specified in pixels (`px`), converted 1:1 from platform effective pixels (`epx`) at 96 DPI (1x scaling).

## Colors

Windows 11 defines adaptive neutral palettes for light and dark modes, paired with a system accent color. The default Windows accent is `#0078D4`, adapted in controls to `#005FB8` (`SystemAccentColorDark1`) in light mode for white text contrast, and `#60CDFF` (`SystemAccentColorLight2`) in dark mode for dark text contrast.

- **Surface Base:** Low-importance background canvas (`#F3F3F3` light, `#202020` dark) housing window chrome and navigation.
- **Surface (Card):** Promoted content container (`#FFFFFF` light, `#2C2C2C` dark) segmenting primary user tasks.
- **On-Surface Text:** Primary text (`#1A1A1A` light derived from 89.4% black, `#FFFFFF` dark), secondary text (`#616161` light, `#CCCCCC` dark), and disabled text (`#A1A1A1` light, `#5D5D5D` dark).
- **Outlines & Dividers:** Control and card outlines (`#EBEBEB` light, `#1C1C1C` dark) and layout dividers (`#E5E5E5` light, `#2E2E2E` dark).
- **Feedback:** Semantic indicators for success (`#0F7B0F` light, `#6CCB5F` dark), caution (`#9D5D00` light, `#FCE100` dark), and critical alerts (`#C42B1C` light, `#FF99A4` dark).

## Typography

Segoe UI Variable is the primary Windows 11 typeface, utilizing variable optical sizing (`opsz`) and weight (`wght`) axes. Windows 11 intentionally omits bold (700) and italic styles from its UI type ramp, selecting semibold (600) for titles and emphasis to maximize readability and dyslexia accessibility.

- **Caption (12px / 16px line height, regular 400):** Metadata, timestamps, and compact command buttons.
- **Body (14px / 20px line height, regular 400):** Default interactive control labels and long-form prose.
- **Body Strong (14px / 20px line height, semibold 600):** Emphasized body text, list section headers, and confined title labels.
- **Body Large (18px / 24px line height, regular 400 / semibold 600):** Prominent introductory text.
- **Subtitle (20px / 28px line height, semibold 600):** Section titles and group headers.
- **Title (28px / 36px line height, semibold 600):** Primary page headers.
- **Title Large & Display (40px / 52px and 68px / 92px, semibold 600):** Marketing banners and large hero headers.
- **Korean Localization:** Use **Malgun Gothic** (Regular 400) as the recommended system UI font for Korean text.

## Layout

Layouts align to a 4px global base grid, structured around a multi-tier spacing ramp.

- **Control Spacing:** Maintain 8px between adjacent command buttons and between buttons and flyout anchors.
- **Label Gaps:** Place 8px between a control and its header, and 12px between a control and its descriptive label.
- **Card & Content Gaps:** Space independent content cards 12px apart. Keep 16px padding between a surface boundary and inner edge text.
- **Expander Layout:** Maintain 16px between child controls and the expander toggle button; indent nested controls 48px.
- **Title Bar Metrics:** Standard desktop title bars measure 32px in height with a 16x16px window icon centered with 8px vertical margins. Extended title bars hosting search fields, profile images, or tabs measure 48px in height.
- **Page Margins:** Universal window outer margins are not published as a fixed token `[unverified]`; adapt outer margins to page hierarchy (e.g. 12px header offset).

## Elevation & Depth

Windows 11 establishes depth through a two-layer structural model reinforced with contour strokes and soft ambient drop shadows:

- **Base Layer:** The structural foundation (elevation 1, 1px stroke) supporting window commands, sidebars, and title bars.
- **Content Layer & Cards:** The operational workspace (card elevation 8, 1px stroke) floating above the base canvas.
- **Interactive Controls:** Buttons, inputs, and selectors sit at elevation 2 (rest and hover) with a 1px contour stroke, shifting to elevation 1 when pressed.
- **Transient Surfaces:** Tooltips sit at elevation 16 (1px stroke), flyout popovers at elevation 32 (1px stroke), and modal dialogs at elevation 128 (1px stroke).
- **Platform Distinctive:** Windows utilizes a 1px boundary stroke (`ControlElevationBorderBrush`, `SurfaceStrokeColorFlyout`) instead of sharp directional key shadows to define edges, supplemented by soft ambient blur.

## Shapes

Geometry in Windows 11 employs progressive corner radii to denote containment levels:

- **4px (`ControlCornerRadius`):** Standard in-page controls including Button, TextBox, ComboBox, ListViewItem, ToolTip, and progress bars.
- **8px (`OverlayCornerRadius`):** Transient flyouts, context menus, ContentDialog windows, and top-level application windows.
- **0px (Sharp):** Contact edges where controls join without gaps (e.g. SplitButton segments), dock-attached popups, and maximized or snapped windows.
- **Strokes:** Standard control borders use 1px thin strokes; keyboard focus indicators use a 2px outer stroke.

## Components

Desktop pointer density standardizes dimensions and inner paddings for foundational controls:

- **Button:** 32px height (derived from 20px line height + 11px vertical padding + 2px border), 64px baseline minWidth (derived), padding `5px 11px 6px 11px` (`ButtonPadding`), 4px corner radius, 1px border.
- **TextBox:** 32px minHeight (`TextControlThemeMinHeight`), 64px minWidth (`TextControlThemeMinWidth`), padding `5px 6px 6px 10px` (`TextControlThemePadding`), 4px corner radius.
- **ComboBox:** 32px minHeight (`ComboBoxMinHeight`), 64px minWidth (`ComboBoxThemeMinWidth`), padding `5px 0px 7px 12px` (`ComboBoxPadding` desktop), popup item padding `5px 11px 7px 11px` (desktop pointer density), 4px corner radius.
- **ListItem:** 40px minHeight (`ListViewItemMinHeight`), 88px minWidth (`ListViewItemMinWidth`), padding `0px 12px 0px 16px` (`16,0,12,0`), 4px corner radius.
- **Dialog (`ContentDialog`):** MinWidth 320px, maxWidth 548px, minHeight 184px, maxHeight 756px, 24px uniform padding (`ContentDialogPadding`), 8px button gap, 12px title bottom margin, 8px overlay corner radius.
- **ToolTip:** MaxWidth 320px, padding `6px 9px 8px 9px` (`ToolTipBorderPadding`), 4px corner radius.
- **Flyout:** Padding `15px 16px 17px 16px` (`FlyoutContentPadding`), 8px overlay corner radius.
- **Icons:** Use the Segoe Fluent Icons font (ships with Windows 11; it replaced Segoe MDL2 Assets, which Windows 10 has). Draw glyphs at 16, 20, 24, 32, 40, 48 or 64px, the sizes Microsoft recommends for crisp rendering, in the same color as the text beside them so light and dark themes recolor them. Glyphs are private-use code points: look them up (RAD Agent: `rad.design_icons`), never guess. The font may not be shipped to other platforms.

## Do's and Don'ts

- **Do** use 4px corner radius for standard in-page controls and 8px for modal dialogs and flyouts.
- **Don't** mix sharp corners and rounded corners on independent adjacent controls.
- **Do** maintain an 8px gutter between adjacent command buttons and 12px between controls and labels.
- **Do** select Semibold (600) rather than Bold (700) when creating visual hierarchy and emphasis.
- **Don't** use italic typefaces in standard desktop UI to preserve legibility and dyslexia accessibility.
- **Do** apply 1px contour strokes alongside ambient shadows to express Windows elevation.
- **Don't** apply touch target paddings (such as 11px vertical item padding) when designing for desktop pointer interactions.

## Sources

- **Geometry in Windows 11** — https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/geometry — Retrieved: 2026-09-27 — Values: 4px in-page control corner radius, 8px overlay and window corner radius, 0px snapped/touching edge rule, global resource keys `ControlCornerRadius` and `OverlayCornerRadius`. Terms: Microsoft Documentation Terms / CC-BY 4.0.
- **Content layout and spacing** — https://learn.microsoft.com/en-us/windows/apps/design/basics/content-basics — Retrieved: 2026-09-27 — Values: Spacing and gutters in epx (8epx button gap, 8epx flyout gap, 8epx header gap, 12epx label gap, 12epx card gap, 16epx surface edge text margin, 12epx text hierarchy spacing, 16epx expander control margin, 48epx expander indent). Terms: Microsoft Documentation Terms / CC-BY 4.0.
- **Typography in Windows** — https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/typography — Retrieved: 2026-09-27 — Values: Segoe UI Variable type ramp (Caption 12/16 epx, Body 14/20 epx, Body Strong 14/20 epx semibold, Body Large 18/24 epx, Subtitle 20/28 epx semibold, Title 28/36 epx semibold, Title Large 40/52 epx semibold, Display 68/92 epx semibold), weight values (Regular 400, Semibold 600), bold/italic exclusion, Malgun Gothic Korean UI font recommendation. Terms: Microsoft Documentation Terms / CC-BY 4.0.
- **Layering and elevation in Windows** — https://learn.microsoft.com/en-us/windows/apps/design/signature-experiences/layering — Retrieved: 2026-09-27 — Values: Two-layer application model (Base layer, Content layer), elevation scale and stroke widths (Layer: 1, Control: 2 rest/hover and 1 pressed, Card: 8, Tooltip: 16, Flyout: 32, Dialog: 128, Window: 128). Terms: Microsoft Documentation Terms / CC-BY 4.0.
- **Windows app title bar** — https://learn.microsoft.com/en-us/windows/apps/design/basics/titlebar-design — Retrieved: 2026-09-27 — Values: Standard title bar height 32px, extended interactive height 48px, window icon dimensions 16x16px with 16px lateral margin and 8px vertical margin. Terms: Microsoft Documentation Terms / CC-BY 4.0.
- **WinUI 3 Theme Resources (`microsoft/microsoft-ui-xaml`)** — https://github.com/microsoft/microsoft-ui-xaml/ — Retrieved: 2026-09-27 — Values: Theme colors (`SolidBackgroundFillColorBase`, `CardStrokeColorDefaultSolid`, `SystemFillColorSuccess`, `SystemFillColorCaution`, `SystemFillColorCritical`, `SystemAccentColorDark1`, `SystemAccentColorLight2`, system accent `#0078D4`), control metrics (`ButtonPadding`, `TextControlThemeMinHeight`, `TextControlThemeMinWidth`, `TextControlThemePadding`, `ComboBoxMinHeight`, `ComboBoxThemeMinWidth`, `ComboBoxPadding`, `ComboBoxItemThemePadding`, `ListViewItemMinHeight`, `ListViewItemMinWidth`, `ListViewItemCornerRadius`, `ContentDialogMinWidth`, `ContentDialogMinHeight`, `ContentDialogMaxWidth`, `ContentDialogMaxHeight`, `ContentDialogPadding`, `ToolTipBorderPadding`, `FlyoutContentPadding`). License: MIT License.
- **Fluent 2 Design System** — https://fluent2.microsoft.design/ (Layout, Shapes, Elevation) — Retrieved: 2026-09-27 — Values: 4px base spacing ramp, shape corner tokens (none 0, small 2, medium 4, large 8, x-large 12), stroke tokens (thin 1px, thick 2px), shadow ramp blur equations, platform note on Windows contour strokes. Terms: Microsoft Terms of Use.

- **Segoe Fluent Icons font** — https://learn.microsoft.com/en-us/windows/apps/design/iconography/segoe-fluent-icons-font — Retrieved: 2026-09-27 — Values: icon font name, replacement of Segoe MDL2 Assets, recommended glyph sizes (16, 20, 24, 32, 40, 48, 64), code point list, redistribution note. Terms: Microsoft Documentation Terms.

### Usage notes

- **Segoe UI Variable & Segoe UI:** Proprietary to Microsoft Corporation and preinstalled with Windows 11. May be used freely by apps running on Windows. Third-party developers cannot legally bundle or redistribute Segoe UI font files within applications running on macOS or Linux without purchasing a separate commercial license from Monotype/Microsoft.
- **Selawik Alternative:** Microsoft publishes Selawik (`https://github.com/Microsoft/Selawik`) as an open-source, metrically compatible fallback font for non-Windows platforms; check the repository's license file before bundling it `[unverified]`.
- **Malgun Gothic:** Proprietary Korean UI typeface developed by Sandoll Communications for Microsoft. Included on Windows systems; bundling on macOS requires commercial licensing.
- **Trademarks:** "Windows", "Fluent", and "Segoe" are registered trademarks of Microsoft Corporation.
- **Unverified Values:** Universal window-level outer margin token is not published by Microsoft Learn `[unverified]` and is determined by window chrome / navigation shell layout.
