---
version: alpha
name: Material 3
description: Official Material Design 3 system preset tailored for desktop applications with pointer precision.
colors:
  primary: "#6750a4"
  primary-dark: "#d0bcff"
  on-primary: "#ffffff"
  on-primary-dark: "#381e72"
  primary-container: "#eaddff"
  primary-container-dark: "#4f378b"
  on-primary-container: "#21005d"
  on-primary-container-dark: "#eaddff"
  secondary: "#625b71"
  secondary-dark: "#ccc2dc"
  on-secondary: "#ffffff"
  on-secondary-dark: "#332d41"
  secondary-container: "#e8def8"
  secondary-container-dark: "#4a4458"
  on-secondary-container: "#1d192b"
  on-secondary-container-dark: "#e8def8"
  tertiary: "#7d5260"
  tertiary-dark: "#efb8c8"
  on-tertiary: "#ffffff"
  on-tertiary-dark: "#492532"
  tertiary-container: "#ffd8e4"
  tertiary-container-dark: "#633b48"
  on-tertiary-container: "#31111d"
  on-tertiary-container-dark: "#ffd8e4"
  error: "#b3261e"
  error-dark: "#f2b8b5"
  on-error: "#ffffff"
  on-error-dark: "#601410"
  error-container: "#f9dedc"
  error-container-dark: "#8c1d18"
  on-error-container: "#410e0b"
  on-error-container-dark: "#f9dedc"
  surface: "#fef7ff"
  surface-dark: "#141218"
  on-surface: "#1d1b20"
  on-surface-dark: "#e6e0e9"
  surface-variant: "#e7e0ec"
  surface-variant-dark: "#49454f"
  on-surface-variant: "#49454f"
  on-surface-variant-dark: "#cac4d0"
  surface-container-lowest: "#ffffff"
  surface-container-lowest-dark: "#0f0d13"
  surface-container-low: "#f7f2fa"
  surface-container-low-dark: "#1d1b20"
  surface-container: "#f3edf7"
  surface-container-dark: "#211f26"
  surface-container-high: "#ece6f0"
  surface-container-high-dark: "#2b2930"
  surface-container-highest: "#e6e0e9"
  surface-container-highest-dark: "#36343b"
  outline: "#79747e"
  outline-dark: "#938f99"
  outline-variant: "#cac4d0"
  outline-variant-dark: "#49454f"
  inverse-surface: "#322f35"
  inverse-surface-dark: "#e6e0e9"
  inverse-on-surface: "#f5eff7"
  inverse-on-surface-dark: "#322f35"
  inverse-primary: "#d0bcff"
  inverse-primary-dark: "#6750a4"
  scrim: "#000000"
  scrim-dark: "#000000"
  shadow: "#000000"
  shadow-dark: "#000000"
typography:
  display-large: { fontFamily: Roboto, fontSize: "57px", fontWeight: 400, lineHeight: "64px", letterSpacing: "-0.25px" }
  display-medium: { fontFamily: Roboto, fontSize: "45px", fontWeight: 400, lineHeight: "52px" }
  display-small: { fontFamily: Roboto, fontSize: "36px", fontWeight: 400, lineHeight: "44px" }
  headline-large: { fontFamily: Roboto, fontSize: "32px", fontWeight: 400, lineHeight: "40px" }
  headline-medium: { fontFamily: Roboto, fontSize: "28px", fontWeight: 400, lineHeight: "36px" }
  headline-small: { fontFamily: Roboto, fontSize: "24px", fontWeight: 400, lineHeight: "32px" }
  title-large: { fontFamily: Roboto, fontSize: "22px", fontWeight: 400, lineHeight: "28px" }
  title-medium: { fontFamily: Roboto, fontSize: "16px", fontWeight: 500, lineHeight: "24px", letterSpacing: "0.15px" }
  title-small: { fontFamily: Roboto, fontSize: "14px", fontWeight: 500, lineHeight: "20px", letterSpacing: "0.1px" }
  body-large: { fontFamily: Roboto, fontSize: "16px", fontWeight: 400, lineHeight: "24px", letterSpacing: "0.5px" }
  body-medium: { fontFamily: Roboto, fontSize: "14px", fontWeight: 400, lineHeight: "20px", letterSpacing: "0.25px" }
  body-small: { fontFamily: Roboto, fontSize: "12px", fontWeight: 400, lineHeight: "16px", letterSpacing: "0.4px" }
  label-large: { fontFamily: Roboto, fontSize: "14px", fontWeight: 500, lineHeight: "20px", letterSpacing: "0.1px" }
  label-medium: { fontFamily: Roboto, fontSize: "12px", fontWeight: 500, lineHeight: "16px", letterSpacing: "0.5px" }
  label-small: { fontFamily: Roboto, fontSize: "11px", fontWeight: 500, lineHeight: "16px", letterSpacing: "0.5px" }
rounded:
  none: "0px"
  extra-small: "4px"
  small: "8px"
  medium: "12px"
  large: "16px"
  extra-large: "28px"
  full: "9999px"
spacing:
  none: "0px"
  xs: "4px"
  sm: "8px"
  md: "16px"
  lg: "24px"
  xl: "32px"
  xxl: "48px"
components:
  button: { height: "40px", padding: "0px 24px", minWidth: "48px", rounded: "{rounded.full}" }
  button-icon: { height: "40px", padding: "0px 16px", minWidth: "48px", rounded: "{rounded.full}" }
  text-field: { height: "56px", padding: "8px 16px", minWidth: "200px", rounded: "{rounded.extra-small}" }
  dialog: { padding: "24px", minWidth: "280px", rounded: "{rounded.extra-large}" }
  menu: { padding: "8px 0px", minWidth: "112px", rounded: "{rounded.extra-small}" }
  list-item-one-line: { height: "56px", padding: "0px 16px", rounded: "{rounded.none}" }
  list-item-two-line: { height: "72px", padding: "0px 16px", rounded: "{rounded.none}" }
  list-item-three-line: { height: "88px", padding: "0px 16px", rounded: "{rounded.none}" }
---

## Overview
This preset encapsulates the official Google Material Design 3 (M3) specifications for desktop interfaces on Windows and macOS. The desktop profile assumes high-precision mouse and keyboard input, prioritizing information density over touch-first targets. The foundational design unit in Material Design is the density-independent pixel (dp); at standard 1x desktop scaling (96 DPI on Windows), 1dp maps directly to 1px (derived conversion).

## Colors
Material 3 organizes colors through tonal palettes and functional roles rather than fixed color names. Primary drives key visual emphasis, secondary supports tonal depth, and tertiary introduces balanced contrast. Surface levels manage physical depth: legacy elevation overlays are replaced by distinct surface container roles (Lowest, Low, Default, High, Highest), each establishing visual contrast against standard surface backgrounds without opacity blending. Outline and outline-variant define subtle and prominent boundaries. Each role provides explicit light and dark pairings adhering to WCAG AA contrast standards.

## Typography
Typography uses the Roboto typeface. The type scale comprises 15 distinct roles organized into five functional categories: Display (large-scale promotional numerals and hero headers), Headline (prominent page headings), Title (window headers and card titles), Body (content blocks, inputs, and descriptions), and Label (buttons, tabs, captions, and badges). All sizes derive from rem units at a 16px base and map directly to pixels at 1x scale factor.

| Role | Font Family | Size | Line Height | Weight | Tracking |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Display Large | Roboto | 57px | 64px | 400 | -0.25px |
| Display Medium | Roboto | 45px | 52px | 400 | 0px |
| Display Small | Roboto | 36px | 44px | 400 | 0px |
| Headline Large | Roboto | 32px | 40px | 400 | 0px |
| Headline Medium | Roboto | 28px | 36px | 400 | 0px |
| Headline Small | Roboto | 24px | 32px | 400 | 0px |
| Title Large | Roboto | 22px | 28px | 400 | 0px |
| Title Medium | Roboto | 16px | 24px | 500 | +0.15px |
| Title Small | Roboto | 14px | 20px | 500 | +0.1px |
| Body Large | Roboto | 16px | 24px | 400 | +0.5px |
| Body Medium | Roboto | 14px | 20px | 400 | +0.25px |
| Body Small | Roboto | 12px | 16px | 400 | +0.4px |
| Label Large | Roboto | 14px | 20px | 500 | +0.1px |
| Label Medium | Roboto | 12px | 16px | 500 | +0.5px |
| Label Small | Roboto | 11px | 16px | 500 | +0.5px |

## Layout
Material 3 defines five responsive window size classes: Compact (<600dp), Medium (600–839dp), Expanded (840–1199dp), Large (1200–1599dp), and Extra-large (≥1600dp). Desktop applications target Large and Extra-large windows.
- Margins: Use 24px window margins for desktop viewports (Large and Extra-large). Medium layouts also use 24px margins, while Compact mobile viewports reduce to 16px.
- Spatial Grid: All structural layout components, containers, and spacing tokens align to an 8px grid. Typographic vertical baselines and compact icon alignment utilize a 4px half-grid step.
- Desktop Multi-pane: Desktop layouts employ permanent or dismissible navigation drawers (280px to 360px wide) or compact navigation rails (80px wide) paired with list-detail split views.

## Elevation & Depth
Elevation is expressed through tonal color shifts and soft drop shadows across six discrete levels (the token value is the shadow elevation in dp):
- Level 0 (0dp): Co-planar surfaces, flat cards, and unraised containers.
- Level 1 (1dp): Hover state for buttons, switch thumbs, and resting elevated cards.
- Level 2 (3dp): Popovers, menus, and compact floating surfaces.
- Level 3 (6dp): Modal dialog containers and resting floating action buttons (FAB).
- Level 4 (8dp): Active drawers and complex multi-layer panels.
- Level 5 (12dp): High-priority modal alerts and full-screen temporary sheets.

## Shapes
Material 3 applies rounded corner radii symmetrically across seven standardized scale tiers:
- None (0px): Full-width dividers, edge-to-edge containers, and standard list items.
- Extra-small (4px): Text fields, text inputs, menus, and snackbars.
- Small (8px): Chips and small contextual badges.
- Medium (12px): Standard cards and segmented button groups.
- Large (16px): Extended floating action buttons and large cards.
- Extra-large (28px): Modal dialog containers and time/date pickers.
- Full (9999px / pill): Standard buttons, icon buttons, and filter chips.

## Components
- Common Button: Height 40px, full corner radius (9999px), horizontal padding 24px (16px when preceded by an icon). Resting elevation is Level 0, elevating to Level 1 on hover.
- Text Field: Standard container height 56px, corner radius 4px (Extra-small), horizontal content padding 16px, vertical label/input padding 8px top and 8px bottom. Active indicator height 1px (resting) to 3px (focus).
- Dialog: Container corner radius 28px (Extra-large), minimum width 280px, maximum width 560px, interior padding 24px, container color surface-container-high, elevation Level 3 (6px).
- Menu: Container corner radius 4px (Extra-small), minimum width 112px, maximum width 280px, vertical padding 8px top/bottom, container color surface-container, elevation Level 2 (3px).
- List Item: Minimum container heights 56px (one-line), 72px (two-line), and 88px (three-line). Horizontal padding 16px leading and trailing. Corner radius 0px.
- Density Guidance: For data-heavy desktop forms and tables, pointer input allows reducing list item vertical heights from 56px to 48px or 40px and field heights from 56px to 48px by adjusting vertical padding in multiples of 4px/8px.
- Icons: RAD Agent's glyph catalog (`rad.design_icons`) is Segoe Fluent Icons, a Windows font. This preset's own icon set is not installed on Windows; ship icons as images (SVG or multi-resolution PNG) in an image list, or use Segoe Fluent Icons on Windows and say so in DESIGN.md. [policy: RAD Agent guidance, not a value from the preset's source]

## Do's and Don'ts
- Do use surface container tiers (Lowest through Highest) to distinguish nested panels and cards instead of relying solely on heavy shadows.
- Do align layout margins and container gaps to multiples of 8px.
- Do use Label Large (14px, 500 weight) for interactive button text and Title Medium (16px, 500 weight) for form section headers.
- Don't mix mismatched corner radii within the same component hierarchy; keep containers, buttons, and inputs strictly within their designated shape roles.
- Don't apply elevation Level 4 or Level 5 to persistent inline controls; reserve upper elevations for modal popups, sheets, and active dragging states.
- Don't hardcode touch-first 48px square hit targets when designing high-density desktop data grids; use compact pointer targets while preserving keyboard accessibility.

## Sources
- Material Design 3 Web Tokens: `https://github.com/material-components/material-web` (tokens/versions/v0_192 and tokens/). Values: System color mappings (light and dark palettes), 15-tier typography scale (size, line height, weight, tracking), shape corner scale (0–28px, full), elevation levels 0–5 (0–12dp), button height/padding (40px, 24px/16px), text field dimensions (56px), list item heights (56/72/88px), dialog shape/elevation (28px, level 3), and menu tokens (level 2, 4px). Retrieved: Sun Sep 27 2026. License: Apache-2.0.
- Material Design 3 Official Documentation (Breakpoints & Layout): `https://m3.material.io/foundations/layout/breakpoints`. Values: Five window size classes (Compact <600dp, Medium 600–839dp, Expanded 840–1199dp, Large 1200–1599dp, Extra-large ≥1600dp) and window margin rules (16dp compact, 24dp desktop). Retrieved: Sun Sep 27 2026. Terms: Google Terms of Service (documentation CC BY 4.0).
- Material Design 3 Official Documentation (Spacing & Density): `https://m3.material.io/styles/spacing/tokens` and `https://m3.material.io/foundations/layout/grids-spacing/density`. Values: 8dp spatial baseline grid, 4dp half-grid baseline, information density principles for desktop forms. Retrieved: Sun Sep 27 2026. Terms: Google Terms of Service (documentation CC BY 4.0).
- Google Fonts Roboto Repository: `https://github.com/googlefonts/roboto-2`. Values: Font family name (Roboto) and standard weights (400, 500, 700). Retrieved: Sun Sep 27 2026. License: Apache-2.0.

### Usage Notes
- Font Bundling: The Roboto font family is released under the Apache License 2.0. Desktop applications targeting Windows or macOS may freely bundle the font binaries with commercial or proprietary distributions without royalty obligations, provided the Apache-2.0 copyright and license notices are retained.
- Trademark Notice: "Material Design" is a trademark of Google LLC.
- Derived Values: Dimensions defined in dp (density-independent pixels) in the official M3 guidelines equal pixels (px) at 1x baseline scale factor (96 DPI on Windows). Density token values for desktop are derived from the 4dp/8dp spacing system as Material 3 does not publish an explicit negative density token scale.
