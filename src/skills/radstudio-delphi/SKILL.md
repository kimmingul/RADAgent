---
name: radstudio-delphi
description: Delphi (Object Pascal) conventions for RAD Studio projects - naming, unit and project layout, object lifetime, VCL/FMX component usage and form-designer rules. Read before writing or reviewing Delphi code, adding units or forms, or choosing component names and patterns.
---

# Delphi in RAD Studio

The project's own style wins. Before naming anything, look at 2-3 existing units and follow what they
do (prefixes, casing, indentation, unit names). Use this guide where the project shows no preference.
A project `AGENTS.md` or `.omp` rules override this skill.

## Naming

| Kind | Convention | Example |
| --- | --- | --- |
| Class, record, other types | `T` + PascalCase | `TInvoiceList`, `TOrderLine` |
| Interface | `I` + PascalCase (GUID in the declaration) | `IInvoiceStore` |
| Exception class | `E` + PascalCase, derived from `Exception` | `EInvoiceError` |
| Pointer type | `P` + type name without `T` | `PInvoice` |
| Private field | `F` + PascalCase | `FTotal` |
| Parameter | PascalCase; `A` prefix only if the project uses it | `const AName: string` |
| Enumeration | `T` type, lower-case prefix on members | `TPayState = (psOpen, psPaid)` |
| Constant | PascalCase (or the project's style) | `MaxLines` |
| Unit | Dotted PascalCase namespace, one responsibility | `App.Invoice.Store.pas` |
| Form unit / class / global | unit `MainForm.pas`, class `TMainForm`, variable `MainForm` | |
| Data module | `TInvoiceData` in `InvoiceData.pas` | |
| Event handler | component name + event without `On` | `SaveButtonClick`, `FormCreate` |

Components on forms get meaningful names before any code refers to them. Two styles are common; use
the one already in the project:

- suffix: `SaveButton`, `NameEdit`, `CustomerGrid`, `MainMenu`
- prefix: `btnSave`, `edtName`, `grdCustomer`, `mnuMain`

Rename components with `rad.form_rename_component`, never by editing the field declaration: the IDE
renames the field, the .dfm object and the handlers together.

Formatting (Embarcadero style): keywords lower case, two-space indent, `begin` on its own line, one
statement per line, `end;` aligned with its `begin`, `else` on its own line when blocks are long.

## Project layout

| File | Meaning | Edit? |
| --- | --- | --- |
| `.dpr` | Program source; its `uses` list names every unit (`Unit in 'path'`) | Only code outside `uses`; the IDE owns the list |
| `.dproj` | MSBuild project: platforms, configurations, search paths, defines | Never by hand (use the IDE or `rad.set_build_config`) |
| `.dpk` + `.dproj` | Package (library of units, design-time or runtime) | `contains`/`requires` via the IDE |
| `.groupproj` | Project group | Never by hand |
| `.pas` | Unit | Yes |
| `.dfm` (VCL) / `.fmx` (FMX) | Form streaming file, paired with the unit of the same name | Only through `rad.form_*` |
| `.res` | Version info and icon | No |
| `.dsk`, `.local`, `.identcache`, `.stat` | Per-user IDE state | No; not in git |
| `__history\`, `__recovery\` | IDE backups | No; not in git |
| `Win32\Debug\`, `Win64\Release\` ... | Output: `.exe`, `.dcu`, `.bpl` | No; not in git |

New units, forms, frames and data modules come from `rad.new_module`, which adds them to the project.
A plain `.pas` created with the write tool is not part of the project until it is added.

Unit structure: `interface` (public types and routines, minimal `uses`) then `implementation` (its own
`uses` for everything only the implementation needs). Put a `uses` entry in `implementation` whenever
possible: it avoids circular unit references.

## Object lifetime

- Components with an `Owner` are freed by the owner (a form frees what it owns). Do not `Free` them.
- Everything else you create you free, with `try ... finally ... Free; end;` right after `Create`:
  ```pascal
  List := TStringList.Create;
  try
    List.LoadFromFile(Path, TEncoding.UTF8);
  finally
    List.Free;
  end;
  ```
- `FreeAndNil(FField)` for fields that may be checked later.
- Interfaces are reference counted: hold an `IFoo`, never also `Free` the object behind it.
- `Owner` decides who frees a control; `Parent` decides where it is drawn. A runtime control needs both.
- Strings and dynamic arrays are managed; no freeing. Strings are 1-based on every platform.

## VCL rules

- Touch VCL objects only on the main thread. From a worker, use `TThread.Queue` (or `Synchronize`).
- Avoid `Application.ProcessMessages` in loops; use a thread or `TTask` and queue results back.
- Lay out with `Align`, `Anchors`, `AlignWithMargins`/`Margins` and panels, not fixed pixel positions.
  Forms are DPI-aware: scale runtime sizes with `ScaleValue`.
- Commands go into a `TActionList` (`Caption`, `ShortCut`, `ImageIndex`, `OnExecute`, `OnUpdate`) and
  menu items/buttons point at the action; this keeps enabling logic in one place.
- Non-visual components shared by several forms (connections, queries, image lists) go on a
  `TDataModule`.
- Large lists: `TListView` with `OwnerData = True` and `OnData`, or a `TStringGrid`/`TDrawGrid`.
- Database access (FireDAC): parameters, never string concatenation
  (`Query.SQL.Text := 'select ... where Id = :Id'; Query.ParamByName('Id').AsInteger := Id;`).
- Setting properties in code that the designer already sets is noise; set them in the designer.

## FMX differences

FMX is not VCL with other names. Common traps:

| VCL | FMX |
| --- | --- |
| `Caption` on labels and buttons | `Text` |
| `Left`, `Top`, `Width`, `Height` | `Position.X`, `Position.Y`, `Width`, `Height` (Single) |
| `Align := alClient` | `Align := TAlignLayout.Client` |
| `TPanel` for grouping | `TLayout` (invisible) or `TRectangle` (painted) |
| `Color` | `Fill.Color`, or a style (`StyleLookup`, `TStyleBook`) |
| Window handles | none; use platform services |

Colors are `TAlphaColor` (`TAlphaColors.Red`), units are logical pixels.

## Form designer rules

- Fixed UI is designed, not written: forms, frames, dialogs, menus, toolbars and panels live in the
  .dfm/.fmx so the user can open and change them in the designer. Code creates controls only when
  their number or kind depends on data at run time, and puts them under a designed parent.
- FMX items (`TMenuItem` under `TMainMenu`/`TMenuBar`, `TListBoxItem`, `TTabItem`) are designed
  children of their container, like any other component.
- A custom control class (a `TControl`/`TComponent` descendant that paints itself or creates its
  own scroll bars and sub-controls in its constructor) is a component, not form UI. Its parts stay
  in code; do not rebase it on a frame. A frame's streamed children do not exist yet while the
  frame is loading, and a resize during loading then reaches nil fields.

- Every component in the .dfm has a matching `published` field in the form class, and every event in
  the .dfm names a published method with the event's exact signature. Keep them in sync by using the
  `rad.form_*` tools, which let the IDE do it.
- The IDE deletes empty event handlers when the unit is saved and unhooks the event. A new handler
  always gets at least a comment or a statement.
- Initialize in `FormCreate` (or override `Create` and call `inherited` first); release in `FormDestroy`.
- Inherited forms: change the ancestor in its own unit; the descendant's .dfm says `inherited`.

## Finding facts instead of guessing

- Live properties and values of a component on a form: `rad.form_properties`.
- Classes installed in the palette: `rad.list_components`.
- Declarations, properties and defaults of VCL, FMX and RTL classes: the RAD Studio sources in the
  folder given in the project guide (`source\vcl`, `source\fmx`, `source\rtl`). Grep for
  `TButton = class` or a property name there before assuming an API.
- After changes, `rad.compile` and fix every error it reports.
