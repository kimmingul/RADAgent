---
name: radstudio-ui-design
description: Turn the project's DESIGN.md (style, spacing scale, type ramp, radii, colors) into VCL and FMX form properties. Read before creating or changing forms, frames or dialogs in a project that has DESIGN.md.
---

# RAD Studio UI design

DESIGN.md (project folder) is the design system. Its front matter has the tokens; `radstudio:` names
the RAD Studio style that draws the controls and the platform preset that supplies spacing, type,
radii and guidance. The style decides how a control looks inside (its colors, states, internal
padding, often its corners). DESIGN.md decides what the style does not: how controls are arranged,
the gaps between them, the margins around content, which text is a title and which is body, and
the colors of surfaces you add yourself.

## Order of work

1. Read DESIGN.md: `radstudio.framework`, `style`, `preset`, then `spacing`, `typography`,
   `rounded`, `colors`, `components`, and the Layout and Do's and Don'ts sections.
2. Plan the form as regions (header, navigation, content, command bar, status) before adding
   controls. Use containers and alignment, not absolute coordinates, for anything that resizes.
3. Build it with rad.form_apply, taking every number from the tokens.
4. rad.form_screenshot, then rad.design_lint on the unit. Fix findings; a finding you keep on
   purpose gets a one-line reason in your answer.
5. If a token you need is missing (for example a fallback font), add it to DESIGN.md in the same
   YAML shape and tell the user; do not invent values silently.

## Tokens to properties

| Token | VCL | FMX |
|---|---|---|
| `spacing.*` between siblings | `AlignWithMargins = True` + `Margins.*` (TMargins default to 3: always set them) | `Margins.*` |
| `spacing.*` inside a container | `Padding.*` on TPanel/TGridPanel/TFlowPanel | `Padding.*` on TLayout/TRectangle |
| window content margin | form or root panel `Padding` | root TLayout `Padding` |
| `typography.*.fontSize` (px) | `Font.Height = -px` (form at PixelsPerInch 96); `Font.Size` is whole points and cannot hold 10.5 pt | `TextSettings.Font.Size = px`, and remove `Size` from `StyledSettings` |
| `typography.*.fontFamily` | `Font.Name` | `TextSettings.Font.Family`, remove `Family` from `StyledSettings` |
| weight 600 (semibold) | a semibold family name, e.g. `Segoe UI Semibold` (TFont has no weight) | same: family name (`Font.StyleExt` is not a published property) |
| `rounded.*` | standard controls: the style decides; TShape stRoundRect derives its radius from its size, so custom rounded surfaces need code | `TRectangle.XRadius = YRadius = value` |
| `components.*.height` | `Height` of that control | `Height` of that control |
| `colors.style-*` | system colors the style maps: `clBtnFace` (background), `clWindow` (surface), `clWindowText` (text), `clHighlight` (accent), `clGrayText` (disabled) | leave styled controls alone; for your own TRectangle/TText use the `style-*` hex values |
| other `colors.*` | only on surfaces you draw yourself, with `seClient`/`seFont` removed from `StyleElements` on purpose and `ParentBackground = False` | `Fill.Color`, `Stroke.Color`, `TextSettings.FontColor` (remove `FontColor` from `StyledSettings`) |

Color values in rad.form_apply: the DESIGN.md hex as is (`#RRGGBB`, no alpha; RAD Agent converts
it for TColor and TAlphaColor), or a color name (`clBtnFace`, `claWhite`).

VCL: set the base font once on the form (`Font.Name`, `Font.Height`) and keep `ParentFont = True`
on children; only headings and captions that differ get their own font. FMX: set sizes and families
on the controls that differ; keep the rest styled.

## Layout rules

- One spacing scale: every margin, padding and gap is a `spacing` value (0 is fine). Related
  controls sit closer than unrelated groups.
- Commands: the command row is right-aligned. Windows puts the primary action first (OK, then
  Cancel); macOS puts it last (Cancel, then the default button). One primary button per dialog.
- Align edges: labels and fields in a column share a left edge; buttons in a row share a baseline
  and height (`components.button.height`).
- Resizing: VCL `Align`/`Anchors`, TGridPanel or TFlowPanel; FMX `Align`, TLayout, TGridPanelLayout,
  TFlowLayout. A form that can resize must be checked at its minimum size.
- Type hierarchy: at most three sizes on one form (title, body, caption from the ramp). Emphasis
  by weight or color from the tokens, not by new sizes.
- Dark mode: never hard-code a light color on a styled control. DESIGN.md lists the dark style
  (`darkStyle`) and `-dark` tokens for surfaces you draw yourself.

## Fonts

- Windows presets name Segoe UI Variable, which exists on Windows 11 only; `Segoe UI` is the safe
  family on Windows 10 and 11. Korean UI text: Malgun Gothic (Windows).
- Material 3 names Roboto; it must be installed or shipped with the app (Apache-2.0).
- The macOS preset names SF Pro, which may only be used on Apple platforms. On Windows put a
  fallback family into DESIGN.md typography (for example Segoe UI) before using it.
