// EXPECT: clean
// ARGS: --typed --rtl @rtl@ -Fu@root@/tools/spikes/region -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S17: copying a record that holds no region value is not a store of a region value: an element of a dynamic array or
  of a TGrowArray goes into another dynamic array whole. }
unit s17_copy_ok;

{$mode objfpc}{$H+}

interface

uses
  Region, Safe;

type
  THeader = record
    Name, Value: String;
  end;
  THeaders = specialize TGrowArray<THeader>;
  THeaderList = array of THeader;
  TPlain = class
    Items: THeaderList;
    One: THeader;
  end;
  TBag = record
    Items: THeaderList;
    One: THeader;
  end;

  TRequest = class(TRegionObject)
    Headers: THeaders;
    Items: THeaderList;
  end;

function Collect: THeaderList;

implementation

function Collect: THeaderList;
var
  Scratch: TRegion;
  Req: TRequest;
  I: Integer;
  H: THeader;
  Queue: THeaderList;
  Plain: TPlain;
  Bag: TBag;
begin
  Scratch := TRegion.Create;
  Req := TRequest.Create;
  Req.Headers := THeaders.Create;
  Req.Headers.Push(H);
  // UNSAFE: the object of another style is only read here
  Plain := TPlain.Create;
  Plain.One := Req.Headers[0];
  Bag.One := Req.Headers[0];
  SetLength(Queue, Req.Headers.Len);
  for I := 0 to Req.Headers.Len - 1 do
  begin
    Queue[I] := Req.Headers[I];
    H := Req.Headers[I];
    Queue[I] := H;
  end;
  SetLength(Req.Items, 1);
  Queue[0] := Req.Items[0];
  Result := nil;
  SetLength(Result, 1);
  Result[0] := Req.Items[0];
  Result[0] := Req.Headers[0];
  SetLength(Plain.Items, 1);
  Plain.Items[0] := Req.Headers[0];
  Plain.Items[0] := Req.Items[0];
  SetLength(Bag.Items, 1);
  Bag.Items[0] := Req.Items[0];
  Bag.Items := Copy(Req.Items);
  Plain.Items := Copy(Req.Items);
  Scratch.Release;
end;

end.
