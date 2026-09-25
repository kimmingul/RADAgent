unit RADAgent.HandlerCode;

{ Source code of event handlers bound by the rad.form_* tools. The IDE drops handlers with an
  empty body when it saves, which also unbinds the event, so every new handler gets one comment
  line. Delphi: the designer's IDesigner.CreateMethod writes the stub; KeepDelphiHandler adds the
  comment. C++Builder: CreateMethod registers the name but writes no code, so EnsureCppHandler
  writes what the C++ IDE would, the declaration in the form class's __published section (.h) and
  the body (.cpp). All edits go through the editor buffers so the designer sees them at once.
  Main thread only. }

interface

uses
  System.TypInfo, ToolsAPI;

{ True when the form's unit is C++ (the module has a .cpp file). }
function IsCppForm(const Editor: IOTAFormEditor): Boolean;
{ Adds the declaration and body of Handler (of event type EventType) to the form's class when
  they are missing. ClassName is the form class ("TForm1"). }
function EnsureCppHandler(const Editor: IOTAFormEditor; const ClassName, Handler: string;
  EventType: PTypeInfo; out Problem: string): Boolean;
{ "TObject *Sender" for TNotifyEvent: the C++ parameter list of a Delphi method type. }
function CppParams(EventType: PTypeInfo): string;
{ After CreateMethod: puts a comment into Handler's body when it is empty (begin end;). }
procedure KeepDelphiHandler(const Editor: IOTAFormEditor; const ClassName, Handler: string);

implementation

uses
  System.SysUtils, System.Classes, System.Rtti, System.RegularExpressions;

function SourceEditor(const Editor: IOTAFormEditor; const Ext: string): IOTASourceEditor;
var
  Module: IOTAModule;
  Index: Integer;
begin
  Result := nil;
  Module := Editor.Module;
  if Module = nil then
    Exit;
  for Index := 0 to Module.ModuleFileCount - 1 do
    if SameText(ExtractFileExt(Module.ModuleFileEditors[Index].FileName), Ext) and
      Supports(Module.ModuleFileEditors[Index], IOTASourceEditor, Result) then
      Exit;
  Result := nil;
end;

function IsCppForm(const Editor: IOTAFormEditor): Boolean;
begin
  Result := SourceEditor(Editor, '.cpp') <> nil;
end;

function ReadAll(const Source: IOTASourceEditor): string;
var
  Reader: IOTAEditReader;
  Bytes: TBytes;
  Chunk: array[0..16383] of AnsiChar;
  Read, Position: Integer;
begin
  Reader := Source.CreateReader;
  Position := 0;
  repeat
    Read := Reader.GetText(Position, @Chunk[0], SizeOf(Chunk));
    if Read > 0 then
    begin
      SetLength(Bytes, Length(Bytes) + Read);
      Move(Chunk[0], Bytes[Length(Bytes) - Read], Read);
      Inc(Position, Read);
    end;
  until Read < SizeOf(Chunk);
  Result := TEncoding.UTF8.GetString(Bytes);
end;

{ Inserts Text before character index At (0-based) of Content, the buffer's current text. }
procedure InsertText(const Source: IOTASourceEditor; const Content: string; At: Integer;
  const Text: string);
var
  Writer: IOTAEditWriter;
begin
  Writer := Source.CreateWriter;
  Writer.CopyTo(Length(TEncoding.UTF8.GetBytes(Copy(Content, 1, At))));
  Writer.Insert(PAnsiChar(UTF8String(Text)));
  Writer := nil;
end;

function CppTypeName(const Name: string): string;
const
  Pairs: array[0..15, 0..1] of string = (('Integer', 'int'), ('LongInt', 'int'),
    ('Cardinal', 'unsigned'), ('LongWord', 'unsigned'), ('Boolean', 'bool'), ('string', 'UnicodeString'),
    ('Char', 'System::WideChar'), ('WideChar', 'System::WideChar'), ('Word', 'System::Word'),
    ('Byte', 'System::Byte'), ('Single', 'float'), ('Double', 'double'), ('Extended', 'long double'),
    ('Int64', '__int64'), ('Pointer', 'void *'), ('NativeInt', 'NativeInt'));
var
  Index: Integer;
begin
  for Index := 0 to High(Pairs) do
    if SameText(Name, Pairs[Index, 0]) then
      Exit(Pairs[Index, 1]);
  Result := Name;
end;

function CppParams(EventType: PTypeInfo): string;
var
  Context: TRttiContext;
  Method: TRttiMethodType;
  Param: TRttiParameter;
  Item, TypeName: string;
begin
  Result := '';
  Context := TRttiContext.Create;
  try
    if not (Context.GetType(EventType) is TRttiMethodType) then
      Exit;
    Method := TRttiMethodType(Context.GetType(EventType));
    for Param in Method.GetParameters do
    begin
      if Param.ParamType = nil then
        TypeName := 'void *'
      else
        TypeName := CppTypeName(Param.ParamType.Name);
      if (Param.ParamType <> nil) and (Param.ParamType.TypeKind in [tkClass, tkInterface]) then
        Item := TypeName + ' *' + Param.Name
      else if ([pfVar, pfOut] * Param.Flags) <> [] then
        Item := TypeName + ' &' + Param.Name
      else if (pfConst in Param.Flags) and (Param.ParamType <> nil) and
        (Param.ParamType.TypeKind in [tkRecord, tkMRecord, tkUString, tkArray]) then
        Item := 'const ' + TypeName + ' &' + Param.Name
      else
        Item := TypeName + ' ' + Param.Name;
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + Item;
    end;
  finally
    Context.Free;
  end;
end;

{ Character index (0-based) where the declaration goes: the start of the first line after
  "__published:" in ClassName that opens another section (private:, public:, protected:) or closes
  the class; -1 when there is none. }
function DeclarationAt(const Header, ClassName: string): Integer;
var
  Lines: TArray<string>;
  Index, Offset, Stage: Integer;
  Line: string;
begin
  Result := -1;
  Lines := Header.Split([#10]);
  Offset := 0;
  Stage := 0;
  for Index := 0 to High(Lines) do
  begin
    Line := Trim(Lines[Index]);
    case Stage of
      0: if TRegEx.IsMatch(Line, '^class\s+(PACKAGE\s+)?' + ClassName + '\b') then
           Stage := 1;
      1: if Line.StartsWith('__published') then
           Stage := 2;
      2: if TRegEx.IsMatch(Line, '^(private|public|protected)\s*:') or Line.StartsWith('}') then
           Exit(Offset);
    end;
    Inc(Offset, Length(Lines[Index]) + 1);
  end;
end;

function EnsureCppHandler(const Editor: IOTAFormEditor; const ClassName, Handler: string;
  EventType: PTypeInfo; out Problem: string): Boolean;
const
  Rule = '//---------------------------------------------------------------------------';
var
  Header, Body: IOTASourceEditor;
  Text, Params, Prefix: string;
  At: Integer;
begin
  Result := False;
  Problem := '';
  Header := SourceEditor(Editor, '.h');
  Body := SourceEditor(Editor, '.cpp');
  if (Header = nil) or (Body = nil) then
  begin
    Problem := 'The form unit has no .h/.cpp pair.';
    Exit;
  end;
  Params := CppParams(EventType);
  Text := ReadAll(Header);
  if not TRegEx.IsMatch(Text, '__fastcall\s+' + Handler + '\s*\(') then
  begin
    At := DeclarationAt(Text, ClassName);
    if At < 0 then
    begin
      Problem := 'Could not find the __published section of ' + ClassName + ' in the header.';
      Exit;
    end;
    InsertText(Header, Text, At, #9'void __fastcall ' + Handler + '(' + Params + ');'#13#10);
  end;
  Text := ReadAll(Body);
  if not TRegEx.IsMatch(Text, ClassName + '\s*::\s*' + Handler + '\s*\(') then
  begin
    Prefix := '';
    if (Text <> '') and not Text.EndsWith(#10) then
      Prefix := #13#10;
    { The comment keeps the IDE from deleting the handler as empty when it saves. }
    InsertText(Body, Text, Length(Text), Prefix + 'void __fastcall ' + ClassName + '::' + Handler +
      '(' + Params + ')'#13#10'{'#13#10#9'// ' + Handler + #13#10'}'#13#10 + Rule + #13#10);
  end;
  Result := True;
end;

procedure KeepDelphiHandler(const Editor: IOTAFormEditor; const ClassName, Handler: string);
var
  Source: IOTASourceEditor;
  Text: string;
  Match: TMatch;
begin
  Source := SourceEditor(Editor, '.pas');
  if Source = nil then
    Exit;
  Text := ReadAll(Source);
  Match := TRegEx.Match(Text, '(?i)procedure\s+' + ClassName + '\.' + Handler +
    '\b[^;]*;\s*begin(\s*)end\s*;');
  if Match.Success then
    { Just after "begin". }
    InsertText(Source, Text, Match.Groups[1].Index - 1, #13#10'  // ' + Handler);
end;

end.
