---
name: radstudio-cpp
description: C++Builder conventions for RAD Studio projects - VCL/FMX classes in C++, __fastcall and __published, form unit files, project layout, compilers, strings and object lifetime. Read before writing or reviewing C++Builder code, adding forms or handlers, or calling VCL/FMX/RTL APIs from C++.
---

# C++Builder in RAD Studio

The project's own style wins. Look at 2-3 existing units first and follow them. A project `AGENTS.md`
or `.omp` rules override this skill. The VCL and FMX are written in Delphi; C++Builder uses them
through generated headers (`.hpp`), which explains most of the rules below.

## Form units

A form is three files with the same base name: `MainForm.h`, `MainForm.cpp`, `MainForm.dfm` (or `.fmx`).

```cpp
// MainForm.h
#ifndef MainFormH
#define MainFormH
#include <System.Classes.hpp>
#include <Vcl.Controls.hpp>
#include <Vcl.StdCtrls.hpp>
#include <Vcl.Forms.hpp>

class TMainForm : public TForm
{
__published:  // IDE-managed components and handlers
    TButton *SaveButton;
    void __fastcall SaveButtonClick(TObject *Sender);
private:
    int FCount;
public:
    __fastcall TMainForm(TComponent* Owner);
};
extern PACKAGE TMainForm *MainForm;
#endif
```

```cpp
// MainForm.cpp
#include <vcl.h>
#pragma hdrstop
#include "MainForm.h"
#pragma package(smart_init)
#pragma resource "*.dfm"
TMainForm *MainForm;

__fastcall TMainForm::TMainForm(TComponent* Owner) : TForm(Owner)
{
}

void __fastcall TMainForm::SaveButtonClick(TObject *Sender)
{
    // ...
}
```

- `__published` holds exactly the components and handlers of the .dfm. Methods of VCL classes,
  constructors and event handlers are `__fastcall`.
- In this IDE host the C++ designer does not write handler code. `rad.form_apply` and
  `rad.form_set_event` add the declaration and a body; fill the body, do not declare handlers by hand.
- Rename components with `rad.form_rename_component`, never by editing the header.
- New forms, frames, data modules and units come from `rad.new_module`, which adds them to the project.

## Naming

Follow the VCL: classes `T` + PascalCase, fields `F` + PascalCase, events `On...`, exception classes
`E...`. Components get meaningful names (`SaveButton` or `btnSave`, whichever the project uses).
Handlers are component name + event without `On`: `SaveButtonClick`, `FormCreate`.

## Project layout

| File | Meaning | Edit? |
| --- | --- | --- |
| `.cbproj` | MSBuild project: platforms, configurations, include paths, defines | Never by hand (IDE or `rad.set_build_config`) |
| `Project.cpp` | Main: `WinMain`, `USEFORM(...)`, `Application->CreateForm(...)` | Code outside the IDE-managed lines only |
| `ProjectPCH1.h` | Precompiled header | Rarely |
| `.groupproj` | Project group | Never by hand |
| `.h` / `.cpp` / `.dfm` | Form unit | `.dfm` only through `rad.form_*` |
| `.res` | Version info and icon | No |
| `.local`, `.dsk`, `__history\`, `__recovery\`, `__astcache\` | IDE state | No; not in git |
| `Win32\Debug\`, `Win64x\Release\` ... with `.obj`, `.tds`, `.il?`, `.pch` | Output | No; not in git |

## Compilers and platforms

| Platform | Compiler | Notes |
| --- | --- | --- |
| Win32 | `bcc32c` (Clang) | Classic `bcc32` only for old code |
| Win64 | `bcc64` (Clang) | |
| Win64x (Windows 64-bit Modern) | `bcc64x` (Clang/LLVM, RAD Studio 12.1+) | C++17/20/23, MinGW-style ABI |

Write standard C++ that all three accept unless the project targets one. Use `<memory>`,
`<vector>`, range-for, `auto`, `nullptr`.

## VCL and FMX objects from C++

- VCL/FMX classes live on the heap only: `new TStringList()`. Never on the stack.
- An object with an `Owner` is deleted by its owner. Others: `std::unique_ptr<TStringList> List(new TStringList());`
  or `delete` in a `__finally`/destructor.
- Properties use `->`: `SaveButton->Caption = "Save";`. They are `__property`, not fields; you cannot
  take their address or pass them by non-const reference.
- Sets: `Font->Style = TFontStyles() << fsBold << fsItalic;`, test with `Style.Contains(fsBold)`.
- Class references: `__classid(TMainForm)`; creating a form: `Application->CreateForm(__classid(TAbout), &About);`.
- Casting `Sender`: `if (auto *B = dynamic_cast<TButton*>(Sender)) ...`.
- Method pointers are `__closure`; assign handlers with `Button->OnClick = &SaveButtonClick;`.
- Catch Delphi exceptions by reference: `catch (const Exception &E) { ShowMessage(E.Message); }`.
- Touch VCL objects only on the main thread; from workers use `TThread::Queue(nullptr, ...)`.

## Strings

- `String` is `UnicodeString` (UTF-16, 1-based `[]`, reference counted). String literals for VCL
  APIs: `L"text"` or `_D("text")`; plain `"text"` also converts.
- Convert: `std::wstring(S.c_str())`, `UTF8String(S)` for UTF-8 bytes, `String(std::wstring)`.
- `Format(L"%d items", ARRAYOFCONST((Count)))`, `IntToStr(n)`, `S.ToInt()`, `S.Trim()`.
- `TStringList`, `TArray<T>`/`DynamicArray<T>` bridge to Delphi APIs.

## FMX differences

Labels and buttons use `Text`, not `Caption`; positions are `Position->X`/`Position->Y` (float);
`Align = TAlignLayout::Client`; colors are `TAlphaColor` (`TAlphaColorRec::Red`); group with `TLayout`.

## Finding facts instead of guessing

- Live properties and values of a component: `rad.form_properties`. Installed classes: `rad.list_components`.
- C++ declarations of VCL/FMX/RTL: headers under the RAD Studio `include\windows\vcl`,
  `include\windows\fmx` and `include\windows\rtl` folders; the Delphi sources with comments and
  defaults are under `source\vcl`, `source\fmx`, `source\rtl` (folder given in the project guide).
- The IDE shows C++ errors only in the Messages view; `rad.compile` returns them. Fix every error.
