// UNSAFE-UNIT: обвязка libc для test_ffi — образец FFI по SPEC §13
{ Слой обвязки: external-объявления (как файл с import "C" в Go) и безопасный
  фасад над ними. Наружу — только String, open array, TArray, TOwned. }
unit ffi_libc;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Safe;

type
  TCBox = specialize TOwned<TCResource>;
  TInts = specialize TArray<Integer>;

{ Длина UTF-8 строки в байтах — через C. Строка заимствуется на время вызова (F1). }
function CStrLen(const S: string): SizeInt;
{ Копия строки в памяти C: владелец освободит её через free (F3). }
function CStrDup(const S: string): TCBox;
{ Обратно в Pascal: копия (F3, как C.GoString). }
function CBoxToString(const B: TCBox): string;
{ Сортировка через qsort с обратным вызовом на Паскале (F4). }
procedure CSortInts(var A: TInts);

var
  CFreeCalls: LongInt = 0; // для теста: сколько раз C-память вернули через free

implementation

const
  libc = {$ifdef windows}'msvcrt'{$else}'c'{$endif};

type
  TCCompare = function(A, B: System.Pointer): LongInt; cdecl;

function c_strlen(S: System.PChar): SizeUInt; cdecl; external libc name 'strlen';
function c_strdup(S: System.PChar): System.Pointer; cdecl; external libc name {$ifdef windows}'_strdup'{$else}'strdup'{$endif};
procedure c_free(P: System.Pointer); cdecl; external libc name 'free';
procedure c_qsort(Base: System.Pointer; N, Size: SizeUInt; Cmp: TCCompare); cdecl; external libc name 'qsort';

procedure CountingFree(P: System.Pointer); cdecl;
begin
  InterlockedIncrement(CFreeCalls);
  c_free(P);
end;

function CStrLen(const S: string): SizeInt;
begin
  // UNSAFE: PChar(S) жив, пока жив S (const-параметр), C его не сохраняет (F1)
  Result := c_strlen(System.PChar(S));
end;

function CStrDup(const S: string): TCBox;
begin
  // UNSAFE: strdup возвращает malloc-память; сразу под владение с парной free (F3)
  Result := TCBox.Own(TCResource.Create(c_strdup(System.PChar(S)), @CountingFree));
end;

function CBoxToString(const B: TCBox): string;
begin
  // UNSAFE: Ptr — C-строка с нулём в конце; присваивание копирует (F3)
  Result := System.PChar(B.Get.Ptr);
end;

function CompareInts(A, B: System.Pointer): LongInt; cdecl;
begin
  // F4: исключение не должно пересекать C-кадры; здесь их нет (только чтение и сравнение)
  // UNSAFE: qsort передаёт указатели на элементы массива, который жив на время вызова
  if PInteger(A)^ < PInteger(B)^ then Result := -1
  else if PInteger(A)^ > PInteger(B)^ then Result := 1
  else Result := 0;
end;

procedure CSortInts(var A: TInts);
begin
  if Length(A) > 1 then
    // UNSAFE: @A[0] и Length(A) описывают один и тот же массив (F1, F2)
    c_qsort(@A[0], Length(A), SizeOf(Integer), @CompareInts);
end;

end.
