unit uBencode;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

type
  TBencodeMetaFile = record
    Path: string;
    Length: Int64;
  end;

  TTorrentMetaPreview = record
    Valid: Boolean;
    Name: string;
    Comment: string;
    CreatedBy: string;
    CreationDate: Int64;
    PieceLength: Int64;
    PieceCount: Integer;
    TotalSize: Int64;
    IsPrivate: Boolean;
    Trackers: array of string;
    Files: array of TBencodeMetaFile;
  end;

function ParseTorrentFileMeta(const FileName: string; out Meta: TTorrentMetaPreview): Boolean;

implementation

type
  TBencodeKind = (bkInt, bkStr, bkList, bkDict);

  TBencodeNode = class
  public
    Kind: TBencodeKind;
    IntVal: Int64;
    StrVal: RawByteString;
    ListItems: TFPList;
    DictKeys: TStringList;
    DictVals: TFPList;
    constructor Create(AKind: TBencodeKind);
    destructor Destroy; override;
    function FindKey(const Key: string): TBencodeNode;
  end;

constructor TBencodeNode.Create(AKind: TBencodeKind);
begin
  inherited Create;
  Kind := AKind;
  if AKind = bkList then
    ListItems := TFPList.Create
  else if AKind = bkDict then
  begin
    DictKeys := TStringList.Create;
    DictVals := TFPList.Create;
  end;
end;

destructor TBencodeNode.Destroy;
var
  I: Integer;
begin
  if ListItems <> nil then
  begin
    for I := 0 to ListItems.Count - 1 do
      TObject(ListItems[I]).Free;
    ListItems.Free;
  end;
  if DictVals <> nil then
  begin
    for I := 0 to DictVals.Count - 1 do
      TObject(DictVals[I]).Free;
    DictVals.Free;
  end;
  DictKeys.Free;
  inherited Destroy;
end;

function TBencodeNode.FindKey(const Key: string): TBencodeNode;
var
  I: Integer;
begin
  Result := nil;
  if (Kind <> bkDict) or (DictKeys = nil) then Exit;
  for I := 0 to DictKeys.Count - 1 do
    if DictKeys[I] = Key then
      Exit(TBencodeNode(DictVals[I]));
end;

function ParseBencodeValue(const Buf: RawByteString; var PosIdx: Integer; Len: Integer): TBencodeNode;
var
  C: Char;
  StartIdx: Integer;
  StrLen: Int64;
  KeyNode, ValNode: TBencodeNode;
begin
  Result := nil;
  if (PosIdx < 1) or (PosIdx > Len) then Exit;
  C := Buf[PosIdx];

  if C = 'i' then
  begin
    Inc(PosIdx);
    StartIdx := PosIdx;
    while (PosIdx <= Len) and (Buf[PosIdx] <> 'e') do
      Inc(PosIdx);
    if PosIdx > Len then Exit;
    Result := TBencodeNode.Create(bkInt);
    Result.IntVal := StrToInt64Def(Copy(Buf, StartIdx, PosIdx - StartIdx), 0);
    Inc(PosIdx); // skip 'e'
  end
  else if C = 'l' then
  begin
    Inc(PosIdx);
    Result := TBencodeNode.Create(bkList);
    while (PosIdx <= Len) and (Buf[PosIdx] <> 'e') do
    begin
      ValNode := ParseBencodeValue(Buf, PosIdx, Len);
      if ValNode = nil then
      begin
        FreeAndNil(Result);
        Exit;
      end;
      Result.ListItems.Add(ValNode);
    end;
    if PosIdx <= Len then
      Inc(PosIdx); // skip 'e'
  end
  else if C = 'd' then
  begin
    Inc(PosIdx);
    Result := TBencodeNode.Create(bkDict);
    while (PosIdx <= Len) and (Buf[PosIdx] <> 'e') do
    begin
      KeyNode := ParseBencodeValue(Buf, PosIdx, Len);
      if (KeyNode = nil) or (KeyNode.Kind <> bkStr) then
      begin
        KeyNode.Free;
        FreeAndNil(Result);
        Exit;
      end;
      ValNode := ParseBencodeValue(Buf, PosIdx, Len);
      if ValNode = nil then
      begin
        KeyNode.Free;
        FreeAndNil(Result);
        Exit;
      end;
      Result.DictKeys.Add(KeyNode.StrVal);
      Result.DictVals.Add(ValNode);
      KeyNode.Free;
    end;
    if PosIdx <= Len then
      Inc(PosIdx); // skip 'e'
  end
  else if C in ['0'..'9'] then
  begin
    StartIdx := PosIdx;
    while (PosIdx <= Len) and (Buf[PosIdx] in ['0'..'9']) do
      Inc(PosIdx);
    if (PosIdx > Len) or (Buf[PosIdx] <> ':') then Exit;
    StrLen := StrToInt64Def(Copy(Buf, StartIdx, PosIdx - StartIdx), -1);
    Inc(PosIdx); // skip ':'
    if (StrLen < 0) or (PosIdx + StrLen - 1 > Len) then Exit;
    Result := TBencodeNode.Create(bkStr);
    Result.StrVal := Copy(Buf, PosIdx, StrLen);
    Inc(PosIdx, StrLen);
  end;
end;

function GetNodeStr(Dict: TBencodeNode; const KeyUtf8, KeyFallback: string): string;
var
  N: TBencodeNode;
begin
  Result := '';
  if Dict = nil then Exit;
  if KeyUtf8 <> '' then
  begin
    N := Dict.FindKey(KeyUtf8);
    if (N <> nil) and (N.Kind = bkStr) then
      Exit(N.StrVal);
  end;
  N := Dict.FindKey(KeyFallback);
  if (N <> nil) and (N.Kind = bkStr) then
    Result := N.StrVal;
end;

function GetNodeInt(Dict: TBencodeNode; const Key: string; Def: Int64 = 0): Int64;
var
  N: TBencodeNode;
begin
  Result := Def;
  if Dict = nil then Exit;
  N := Dict.FindKey(Key);
  if (N <> nil) and (N.Kind = bkInt) then
    Result := N.IntVal;
end;

function ParseTorrentFileMeta(const FileName: string; out Meta: TTorrentMetaPreview): Boolean;
var
  FS: TFileStream;
  Raw: RawByteString;
  PosIdx, I, J, TrkCount: Integer;
  Root, Info, N, SubN, PathList, TierNode: TBencodeNode;
  PathStr: string;
begin
  Result := False;
  FillChar(Meta, SizeOf(Meta), 0);
  if not FileExists(FileName) then Exit;

  try
    FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      if FS.Size <= 0 then Exit;
      SetLength(Raw, FS.Size);
      FS.ReadBuffer(Raw[1], FS.Size);
    finally
      FS.Free;
    end;
  except
    Exit;
  end;

  PosIdx := 1;
  Root := ParseBencodeValue(Raw, PosIdx, Length(Raw));
  if Root = nil then Exit;
  try
    if Root.Kind <> bkDict then Exit;

    Meta.Comment := GetNodeStr(Root, 'comment.utf-8', 'comment');
    Meta.CreatedBy := GetNodeStr(Root, 'created by.utf-8', 'created by');
    Meta.CreationDate := GetNodeInt(Root, 'creation date', 0);

    // Trackers
    TrkCount := 0;
    N := Root.FindKey('announce-list');
    if (N <> nil) and (N.Kind = bkList) then
    begin
      for I := 0 to N.ListItems.Count - 1 do
      begin
        TierNode := TBencodeNode(N.ListItems[I]);
        if TierNode.Kind = bkList then
          for J := 0 to TierNode.ListItems.Count - 1 do
          begin
            SubN := TBencodeNode(TierNode.ListItems[J]);
            if (SubN.Kind = bkStr) and (Trim(SubN.StrVal) <> '') then
            begin
              SetLength(Meta.Trackers, TrkCount + 1);
              Meta.Trackers[TrkCount] := SubN.StrVal;
              Inc(TrkCount);
            end;
          end;
      end;
    end;

    if TrkCount = 0 then
    begin
      PathStr := GetNodeStr(Root, '', 'announce');
      if Trim(PathStr) <> '' then
      begin
        SetLength(Meta.Trackers, 1);
        Meta.Trackers[0] := PathStr;
      end;
    end;

    Info := Root.FindKey('info');
    if (Info = nil) or (Info.Kind <> bkDict) then Exit;

    Meta.Name := GetNodeStr(Info, 'name.utf-8', 'name');
    if Meta.Name = '' then
      Meta.Name := ChangeFileExt(ExtractFileName(FileName), '');

    Meta.PieceLength := GetNodeInt(Info, 'piece length', 0);
    Meta.IsPrivate := GetNodeInt(Info, 'private', 0) <> 0;

    N := Info.FindKey('pieces');
    if (N <> nil) and (N.Kind = bkStr) then
      Meta.PieceCount := Length(N.StrVal) div 20;

    // Files (multi-file or single-file)
    N := Info.FindKey('files');
    if (N <> nil) and (N.Kind = bkList) then
    begin
      SetLength(Meta.Files, N.ListItems.Count);
      Meta.TotalSize := 0;
      for I := 0 to N.ListItems.Count - 1 do
      begin
        SubN := TBencodeNode(N.ListItems[I]);
        if SubN.Kind = bkDict then
        begin
          Meta.Files[I].Length := GetNodeInt(SubN, 'length', 0);
          Inc(Meta.TotalSize, Meta.Files[I].Length);

          PathList := SubN.FindKey('path.utf-8');
          if PathList = nil then
            PathList := SubN.FindKey('path');

          PathStr := '';
          if (PathList <> nil) and (PathList.Kind = bkList) then
            for J := 0 to PathList.ListItems.Count - 1 do
              if TBencodeNode(PathList.ListItems[J]).Kind = bkStr then
              begin
                if PathStr <> '' then PathStr := PathStr + '/';
                PathStr := PathStr + TBencodeNode(PathList.ListItems[J]).StrVal;
              end;
          Meta.Files[I].Path := PathStr;
        end;
      end;
    end
    else
    begin
      Meta.TotalSize := GetNodeInt(Info, 'length', 0);
      SetLength(Meta.Files, 1);
      Meta.Files[0].Path := Meta.Name;
      Meta.Files[0].Length := Meta.TotalSize;
    end;

    Meta.Valid := True;
    Result := True;
  finally
    Root.Free;
  end;
end;

end.
