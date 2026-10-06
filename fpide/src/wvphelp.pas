{
    This file is part of the Free Pascal Integrated Development Environment
    Copyright (c) 2000 by Berczi Gabor

    Help support for (.VPH) help files

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}
{$R-}
unit WVPHelp;


{$mode objfpc}{$H-}
{$modeswitch nestedprocvars}
{$modeswitch autoderef}
interface

uses Objects,
     WUtils,WHelp;

const
      VPHFileSignature = 'HS';

type
      TVPHFileHeader = packed record
        SectionCount: byte; { #1 }
        TotalTopics : word;
      end;

      TVPHTopicEntry = packed record
        TopicOfs   : word;
        Dunno      : byte;
      end;

      PVPHTopicTable = ^TVPHTopicTable;
      TVPHTopicTable = packed array[0..(MaxBytes div sizeof(TVPHTopicEntry))-1] of TVPHTopicEntry;

      PVPHSectionTable = ^TVPHSectionTable;
      TVPHSectionTable = packed array[0..4095] of longint;

      TVPHHelpFile = class;
      PVPHHelpFile = TVPHHelpFile;
      TVPHHelpFile = class(THelpFile)
        constructor Create(AFileName: string; AID: word);
        destructor Destroy; override;
      public
        function    LoadIndex: boolean; override;
        function    ReadTopic(T: PTopic): boolean; override;
      private
        F: PStream;
        Header: TVPHFileHeader;
        TopicTable: PVPHTopicTable;
        TopicTableSize: longint;
        SectionTable: PVPHSectionTable;
        SectionTableSize: longint;
        TopicBaseOfs: longint;
        function ReadHeader: boolean;
        function ReadTopicTable: boolean;
        function ReadBlock(Data: pointer; DataSize: longint): boolean;
      end;

      TVPHGetAttrColorProc = function(TextStyle, TextColor: byte; var Color: byte): boolean;

function DefVPHGetAttrColor(TextStyle, TextColor: byte; var Color: byte): boolean;

const VPHGetAttrColor : TVPHGetAttrColorProc = {$ifdef fpc}@{$endif}DefVPHGetAttrColor;

procedure RegisterHelpType;

implementation


function DefVPHGetAttrColor(TextStyle, TextColor: byte; var Color: byte): boolean;
begin
  DefVPHGetAttrColor:=false;
end;

constructor TVPHHelpFile.Create(AFileName: string; AID: word);
var OK: boolean;
begin
  inherited Create(AID);
  F := TFastBufStream.Create(AFileName, stOpenRead, HelpStreamBufSize);
  OK:=F<>nil;
  if OK then OK:=(F.Status=stOK);
  if OK then
  begin
    OK:=ReadHeader;
    if OK then
    begin
      SectionTableSize:=sizeof(SectionTable^[0])*Header.SectionCount;
      GetMem(SectionTable,SectionTableSize);
      F.Read(SectionTable^,SectionTableSize);
      OK:=(F.Status=stOK);
    end;
    if OK then
      OK:=ReadBlock(nil,2);
    if OK then
    begin
      TopicTableSize:=sizeof(TopicTable^[0])*Header.TotalTopics;
      GetMem(TopicTable,TopicTableSize);
      OK:=ReadTopicTable;
    end;
  end;
  if OK=false then
  begin
    Fail;
  end;
end;

function TVPHHelpFile.ReadHeader: boolean;
var OK: boolean;
begin
  F.Read(Header,sizeof(Header));
  OK:=(F.Status=stOK);
  ReadHeader:=OK;
end;

function TVPHHelpFile.LoadIndex: boolean;
var OK: boolean;
begin
  OK:=false;
  LoadIndex:=OK;
end;

function TVPHHelpFile.ReadBlock(Data: pointer; DataSize: longint): boolean;
var OK: boolean;
    C: char;
begin
  F.Read(C,sizeof(C));
  OK:=(F.Status=stOK) and (C='■');
  if OK then
  begin
    if Assigned(Data) then
      F.Read(Data^,DataSize)
    else
      F.Seek(F.GetPos+DataSize);
    OK:=(F.Status=stOK);
  end;
  ReadBlock:=OK;
end;

function TVPHHelpFile.ReadTopicTable: boolean;
var OK: boolean;
begin
  OK:=ReadBlock(TopicTable,TopicTableSize);
  TopicBaseOfs:=F.GetPos;
  ReadTopicTable:=OK;
end;

function TVPHHelpFile.ReadTopic(T: PTopic): boolean;
var OK: boolean;
begin
  OK:=false;
  ReadTopic:=OK;
end;

destructor TVPHHelpFile.Destroy;
begin
  if Assigned(TopicTable) and (TopicTableSize>0) then
      FreeMem(TopicTable{$ifndef FP},TopicTableSize{$endif});
  TopicTable:=nil;
  if Assigned(SectionTable) and (SectionTableSize>0) then
      FreeMem(SectionTable{$ifndef FP},SectionTableSize{$endif});
  SectionTable:=nil;
  if Assigned(F) then F.Free; F:=nil;
  inherited Destroy;
end;

function CreateProc(const FileName,Param: string;Index : longint): PHelpFile;
begin
  CreateProc := TVPHHelpFile.Create(FileName,Index);
end;

procedure RegisterHelpType;
begin
  RegisterHelpFileType({$ifdef FPC}@{$endif}CreateProc);
end;

END.
