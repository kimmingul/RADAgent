//---------------------------------------------------------------------------
#include <vcl.h>
#pragma hdrstop

#include "MainForm.h"
//---------------------------------------------------------------------------
#pragma package(smart_init)
#pragma resource "*.dfm"
TForm1 *Form1;
//---------------------------------------------------------------------------
__fastcall TForm1::TForm1(TComponent* Owner)
	: TForm(Owner)
{
}
//---------------------------------------------------------------------------
int __fastcall TForm1::Total(int Count)
{
	int Result = 0;
	for (int Index = 1; Index <= Count; Index++)
		Result += Index;
	return Result;
}
//---------------------------------------------------------------------------
void __fastcall TForm1::Button1Click(TObject *Sender)
{
	int Answer = Total(10);
	Label1->Caption = "Total=" + IntToStr(Answer);
}
//---------------------------------------------------------------------------
