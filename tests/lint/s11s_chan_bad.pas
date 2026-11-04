// EXPECT: error SAFE-S11s
// ARGS: --typed --rtl @rtl@ -Fu@root@ -Fi@root@ -Fu@root@/safe -Fu@root@/ext -Fi@root@/safe -Fi@root@/ext
{ S11s: a channel carries a shared object with a field of a mutable class. }
unit s11s_chan_bad;

{$mode objfpc}{$H+}

interface

uses
  BP;

type
  TBox = class
  public
    Value: Integer;
  end;

  TBoxOwner = specialize TOwned<TBox>;

  THolder = class
  private
    FBox: TBoxOwner;
  public
    constructor Create;
  end;

  TSharedHolder = specialize TShared<THolder>;
  THolderChan = specialize TChan<TSharedHolder>;

procedure Bump(const B: TBox);
procedure Pass(const Ch: THolderChan; const H: TSharedHolder);

implementation

constructor THolder.Create;
begin
  inherited Create;
  FBox := TBoxOwner.Own(TBox.Create);
end;

procedure Bump(const B: TBox);
begin
  B.Value := B.Value + 1;
end;

procedure Pass(const Ch: THolderChan; const H: TSharedHolder);
begin
  Ch.Send(H);
end;

end.
