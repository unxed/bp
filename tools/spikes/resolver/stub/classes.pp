{ SPDX-License-Identifier: MIT }
{ A declaration stub for the spike resolver: only what the modules of this repository use. }
unit classes;
{$mode objfpc}{$H+}
interface
uses sysutils;
type
  TNotifyEvent = procedure(Sender: TObject) of object;
  TStrings = class(TObject)
  private
    FText: String;
  public
    function Add(const S: String): Integer; virtual;
    procedure Clear; virtual;
    function Count: Integer; virtual;
    property Text: String read FText write FText;
  end;
  TStringList = class(TStrings);
  TThread = class(TObject)
  private
    FFree, FTerm: Boolean;
  public
    constructor Create(CreateSuspended: Boolean);
    procedure Start;
    procedure WaitFor;
    procedure Execute; virtual;
    property FreeOnTerminate: Boolean read FFree write FFree;
    property Terminated: Boolean read FTerm;
  end;
implementation
function TStrings.Add(const S: String): Integer; begin end;
procedure TStrings.Clear; begin end;
function TStrings.Count: Integer; begin end;
constructor TThread.Create(CreateSuspended: Boolean); begin end;
procedure TThread.Start; begin end;
procedure TThread.WaitFor; begin end;
procedure TThread.Execute; begin end;
end.
