{ SPDX-License-Identifier: MIT }
{ Safe Pascal, отравленные примитивы (интерфейс). Включается ПОСЛЕДНИМ в интерфейсе. }
type
  { ---------- Отравленные примитивы (SPEC §6) ----------
    Тип-заглушка с тем же именем закрывает процедуру из System/SysUtils:
    вызов превращается в недопустимое приведение типа (ошибка компиляции),
    а deprecated-сообщение объясняет, что писать вместо. }
  TSafeForbidden = record end;

  GetMem     = TSafeForbidden deprecated 'SAFE-S1: raw allocation. Use TOwned/TShared/TArena or TArray<T>; in unsafe code write System.GetMem with // UNSAFE: comment';
  AllocMem   = TSafeForbidden deprecated 'SAFE-S1: raw allocation. Use TOwned/TShared/TArena or TArray<T>; in unsafe code write System.AllocMem';
  ReallocMem = TSafeForbidden deprecated 'SAFE-S1: raw allocation. Use TArray<T> + SetLength; in unsafe code write System.ReallocMem';
  FreeMem    = TSafeForbidden deprecated 'SAFE-S1: raw deallocation. Owners free memory; in unsafe code write System.FreeMem';
  New        = TSafeForbidden deprecated 'SAFE-S1: raw allocation. Use a record value or TOwned; in unsafe code write System.New';
  Dispose    = TSafeForbidden deprecated 'SAFE-S1: raw deallocation. Owners free memory; in unsafe code write System.Dispose';
  Move       = TSafeForbidden deprecated 'SAFE-S2: raw memory copy. Use assignment or Copy(); in unsafe code write System.Move';
  FillChar   = TSafeForbidden deprecated 'SAFE-S2: raw memory fill. Use X := Default(TType); in unsafe code write System.FillChar';
  FreeAndNil = TSafeForbidden deprecated 'SAFE-S3: manual destruction. Use TOwned.Reset; in unsafe code write SysUtils.FreeAndNil';

  { Типы оставлены рабочими (миграция), но каждое использование — предупреждение. }
  Pointer   = System.Pointer   deprecated 'SAFE-S4: raw pointer. Use TOwned/TSlice/open array; in unsafe code write System.Pointer';
  PByte     = System.PByte     deprecated 'SAFE-S4: raw pointer. Use TSlice<Byte> or array of Byte; in unsafe code write System.PByte';
  PChar     = System.PChar     deprecated 'SAFE-S4: raw pointer. Use String; at OS boundary write System.PChar in unsafe code';
  PAnsiChar = System.PAnsiChar deprecated 'SAFE-S4: raw pointer. Use String; at OS boundary write System.PAnsiChar in unsafe code';
  PWideChar = System.PWideChar deprecated 'SAFE-S4: raw pointer. Use String; at OS boundary write System.PWideChar in unsafe code';

  { Free — метод TObject; его закрывает хелпер с тем же именем, но с обязательным
    параметром, которого в безопасном коде не создать. Поэтому Obj.Free — ОШИБКА
    компиляции без всяких опций, а объяснение правила — имя типа параметра, которое
    компилятор печатает в строке "Found declaration: Free(const SAFE_S3_...)".
    В unsafe-коде — Obj.Destroy с // UNSAFE:. Ограничение: другой хелпер для TObject,
    подключённый после Safe, перекроет этот (S7). }
  SAFE_S3_NoFree_UseTOwnedReset_or_UnsafeDestroy = record end;
  TSafeObjectHelper = class helper for TObject
  public
    procedure Free(const Forbidden: SAFE_S3_NoFree_UseTOwnedReset_or_UnsafeDestroy);
  end;
