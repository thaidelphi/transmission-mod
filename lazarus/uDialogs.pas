{******************************************************************************
 * ยูนิต: uDialogs.pas
 * คำอธิบาย:
 *   รวบรวมหน้าต่างโต้ตอบ (Dialogs) ทั้งหมดของโปรแกรม โดยถอดแบบโครงสร้างและหน้าที่
 *   มาจากชุดไฟล์ .ui ของ `transmission-qt` ได้แก่:
 *
 *   1. ShowOpenTorrentDialog (เหมือน OptionsDialog.ui):
 *      - อ่านโครงสร้างไฟล์ .torrent ด้วย uBencode ทันทีที่เลือกไฟล์
 *      - แสดงตารางรายชื่อไฟล์ย่อยข้างในพร้อม Checkbox ให้เลือก/ข้ามไฟล์ก่อนกดเริ่มโหลด
 *      - แสดงพื้นที่ว่างในโฟลเดอร์ปลายทางสด ๆ ผ่านคำสั่ง RPC `free-space`
 *   2. ShowAddUrlDialog:
 *      - รับลิงก์ `magnet:?` หรือ URL ของไฟล์ `.torrent` (ดึงจาก Clipboard อัตโนมัติ)
 *   3. ShowMakeTorrentDialog (เหมือน MakeDialog.ui):
 *      - สร้างไฟล์ `.torrent` ใหม่จากไฟล์หรือโฟลเดอร์ผ่าน `transmission-create.exe`
 *   4. ShowEditTrackersDialog (เหมือน TrackersDialog.ui):
 *      - แก้ไขรายการ Tracker Announce URLs แบบแบ่งบรรทัดและแบ่ง Tier ด้วยบรรทัดว่าง
 *   5. ShowDetailsDialog (เหมือน DetailsDialog.ui):
 *      - หน้าต่าง Properties 6 แท็บ (Activity, Information, Peers, Trackers, Files, Options)
 *      - มี TTimer อัปเดตข้อมูลความเร็ว เปอร์เซ็นต์ และรายชื่อ Peers แบบ Real-time ทุก 2 วินาที
 *   6. ShowSessionDialog (เหมือน SessionDialog.ui):
 *      - สลับการเชื่อมต่อระหว่าง Local Session และ Remote Session (RPC)
 *   7. ShowPrefsDialog (เหมือน PrefsDialog.ui):
 *      - หน้าต่างตั้งค่าโปรแกรม 6 แท็บ (Speed, Downloading, Seeding, Privacy, Network, Remote/Web)
 *   8. ShowRelocateDialog (เหมือน RelocateDialog.ui):
 *      - ย้ายโฟลเดอร์เก็บข้อมูลของทอร์เรนต์ (`torrent-set-location`)
 *   9. ShowStatsDialog (เหมือน StatsDialog.ui):
 *      - แสดงสถิติการใช้งานเซสชันปัจจุบันและยอดสะสมทั้งหมด พร้อมอัปเดตสดทุก 2 วินาที
 ******************************************************************************}
unit uDialogs;

{$mode objfpc}{$H+}
{$WARN 5024 OFF}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ComCtrls, Spin, Clipbrd, LCLIntf, fpjson, DateUtils, uTypes, uBencode, uRpcClient, uWebServer;

function ShowOpenTorrentDialog(Owner: TComponent; Rpc: TTransmissionRpcClient;
  const InitialFile, DefaultDir: string; DefaultStart: Boolean;
  out SelectedFile, DestDir: string; out StartNow, TrashTorrent: Boolean;
  out Priority: Integer; out UnwantedFiles: TIntegerDynArray): Boolean;

function ShowAddUrlDialog(Owner: TComponent; Rpc: TTransmissionRpcClient;
  const DefaultDir: string; DefaultStart: Boolean;
  out UrlOrMagnet, DestDir: string; out StartNow: Boolean;
  out Priority: Integer): Boolean;

function ShowMakeTorrentDialog(Owner: TComponent; Rpc: TTransmissionRpcClient): Boolean;

procedure ShowDetailsDialog(Owner: TComponent; Rpc: TTransmissionRpcClient;
  Torrent: TTorrentItem);

function ShowPrefsDialog(Owner: TComponent; Rpc: TTransmissionRpcClient;
  WebSrv: TTransmissionWebServer; var Config: TSessionConfig): Boolean;

function ShowSessionDialog(Owner: TComponent; Rpc: TTransmissionRpcClient): Boolean;

function ShowRelocateDialog(Owner: TComponent; const CurrentDir: string;
  out NewDir: string; out MoveData: Boolean): Boolean;

procedure ShowStatsDialog(Owner: TComponent; Rpc: TTransmissionRpcClient);

implementation

function UnixToDateTimeStr(Ts: Int64): string;
begin
  if Ts <= 0 then
    Result := 'Never'
  else
    Result := FormatDateTime('yyyy-mm-dd hh:nn:ss', UnixToDateTime(Ts, False));
end;

function PriorityToStr(Pri: Integer): string;
begin
  if Pri > 0 then
    Result := 'High'
  else if Pri < 0 then
    Result := 'Low'
  else
    Result := 'Normal';
end;

{ 1. Open Torrent Options Dialog (with Bencode File Tree Preview) }

type
  TOpenTorrentForm = class(TForm)
  public
    RpcRef: TTransmissionRpcClient;
    MetaPreview: TTorrentMetaPreview;
    EdtFile: TEdit;
    EdtDir: TEdit;
    LblTorrentSummary: TLabel;
    LblFreeSpace: TLabel;
    LvPreviewFiles: TListView;
    CmbPriority: TComboBox;
    ChkStart: TCheckBox;
    ChkTrash: TCheckBox;
    procedure LoadTorrentMetadata(const FileName: string);
    procedure BtnBrowseFileClick(Sender: TObject);
    procedure BtnBrowseDirClick(Sender: TObject);
    procedure BtnSelectAllFilesClick(Sender: TObject);
    procedure BtnSelectNoneFilesClick(Sender: TObject);
    procedure EdtDirChange(Sender: TObject);
  end;

procedure TOpenTorrentForm.LoadTorrentMetadata(const FileName: string);
var
  I: Integer;
  LI: TListItem;
begin
  LvPreviewFiles.Items.BeginUpdate;
  try
    LvPreviewFiles.Items.Clear;
    if ParseTorrentFileMeta(FileName, MetaPreview) and MetaPreview.Valid then
    begin
      LblTorrentSummary.Caption := Format('%s  (%s, %d files, %d pieces @ %s)',
        [MetaPreview.Name, FormatSize(MetaPreview.TotalSize),
         Length(MetaPreview.Files), MetaPreview.PieceCount, FormatSize(MetaPreview.PieceLength)]);
      for I := 0 to High(MetaPreview.Files) do
      begin
        LI := LvPreviewFiles.Items.Add;
        LI.Checked := True;
        LI.Caption := MetaPreview.Files[I].Path;
        LI.SubItems.Add(FormatSize(MetaPreview.Files[I].Length));
      end;
    end
    else
      LblTorrentSummary.Caption := ExtractFileName(FileName);
  finally
    LvPreviewFiles.Items.EndUpdate;
  end;
end;

procedure TOpenTorrentForm.BtnBrowseFileClick(Sender: TObject);
var
  Dlg: TOpenDialog;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title := 'Open Torrent File';
    Dlg.Filter := 'Torrent Files (*.torrent)|*.torrent|All Files (*.*)|*.*';
    Dlg.FileName := EdtFile.Text;
    if Dlg.Execute then
    begin
      EdtFile.Text := Dlg.FileName;
      LoadTorrentMetadata(Dlg.FileName);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TOpenTorrentForm.BtnBrowseDirClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := EdtDir.Text;
  if SelectDirectory('Select Destination Folder', '', Dir) then
    EdtDir.Text := Dir;
end;

procedure TOpenTorrentForm.BtnSelectAllFilesClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to LvPreviewFiles.Items.Count - 1 do
    LvPreviewFiles.Items[I].Checked := True;
end;

procedure TOpenTorrentForm.BtnSelectNoneFilesClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to LvPreviewFiles.Items.Count - 1 do
    LvPreviewFiles.Items[I].Checked := False;
end;

procedure TOpenTorrentForm.EdtDirChange(Sender: TObject);
var
  FreeB: Int64;
begin
  if (RpcRef <> nil) and (Trim(EdtDir.Text) <> '') and RpcRef.QueryFreeSpace(EdtDir.Text, FreeB) and (FreeB >= 0) then
    LblFreeSpace.Caption := Format('Free space: %s', [FormatSize(FreeB)])
  else
    LblFreeSpace.Caption := '';
end;

function ShowOpenTorrentDialog(Owner: TComponent; Rpc: TTransmissionRpcClient;
  const InitialFile, DefaultDir: string; DefaultStart: Boolean;
  out SelectedFile, DestDir: string; out StartNow, TrashTorrent: Boolean;
  out Priority: Integer; out UnwantedFiles: TIntegerDynArray): Boolean;
var
  F: TOpenTorrentForm;
  Lbl: TLabel;
  BtnFile, BtnDir, BtnSelAll, BtnSelNone, BtnOK, BtnCancel: TButton;
  I, UnwantedCount: Integer;
begin
  Result := False;
  UnwantedFiles := nil;
  F := TOpenTorrentForm.CreateNew(Owner);
  try
    F.RpcRef := Rpc;
    F.Caption := 'Torrent Options';
    F.Position := poMainFormCenter;
    F.BorderStyle := bsSizeable;
    F.ClientWidth := 540;
    F.ClientHeight := 430;
    F.Constraints.MinWidth := 460;
    F.Constraints.MinHeight := 360;

    Lbl := TLabel.Create(F);
    Lbl.Parent := F;
    Lbl.Left := 16; Lbl.Top := 14;
    Lbl.Caption := 'Source torrent:';

    F.LblTorrentSummary := TLabel.Create(F);
    F.LblTorrentSummary.Parent := F;
    F.LblTorrentSummary.Left := 115;
    F.LblTorrentSummary.Top := 14;
    F.LblTorrentSummary.Font.Style := [fsBold];
    F.LblTorrentSummary.Caption := '';

    F.EdtFile := TEdit.Create(F);
    F.EdtFile.Parent := F;
    F.EdtFile.Left := 16; F.EdtFile.Top := 34; F.EdtFile.Width := 420;
    F.EdtFile.Anchors := [akLeft, akTop, akRight];
    F.EdtFile.Text := InitialFile;

    BtnFile := TButton.Create(F);
    BtnFile.Parent := F;
    BtnFile.Left := 444; BtnFile.Top := 32; BtnFile.Width := 80; BtnFile.Height := 26;
    BtnFile.Anchors := [akTop, akRight];
    BtnFile.Caption := 'Browse...';
    BtnFile.OnClick := @F.BtnBrowseFileClick;

    Lbl := TLabel.Create(F);
    Lbl.Parent := F;
    Lbl.Left := 16; Lbl.Top := 68;
    Lbl.Caption := 'Destination folder:';

    F.LblFreeSpace := TLabel.Create(F);
    F.LblFreeSpace.Parent := F;
    F.LblFreeSpace.Left := 140; F.LblFreeSpace.Top := 68;
    F.LblFreeSpace.Font.Color := clGrayText;

    F.EdtDir := TEdit.Create(F);
    F.EdtDir.Parent := F;
    F.EdtDir.Left := 16; F.EdtDir.Top := 88; F.EdtDir.Width := 420;
    F.EdtDir.Anchors := [akLeft, akTop, akRight];
    F.EdtDir.Text := DefaultDir;
    F.EdtDir.OnChange := @F.EdtDirChange;

    BtnDir := TButton.Create(F);
    BtnDir.Parent := F;
    BtnDir.Left := 444; BtnDir.Top := 86; BtnDir.Width := 80; BtnDir.Height := 26;
    BtnDir.Anchors := [akTop, akRight];
    BtnDir.Caption := 'Browse...';
    BtnDir.OnClick := @F.BtnBrowseDirClick;

    Lbl := TLabel.Create(F);
    Lbl.Parent := F;
    Lbl.Left := 16; Lbl.Top := 122;
    Lbl.Caption := 'Files to download:';

    BtnSelAll := TButton.Create(F);
    BtnSelAll.Parent := F;
    BtnSelAll.Left := 360; BtnSelAll.Top := 117; BtnSelAll.Width := 78; BtnSelAll.Height := 23;
    BtnSelAll.Anchors := [akTop, akRight];
    BtnSelAll.Caption := 'Select All';
    BtnSelAll.OnClick := @F.BtnSelectAllFilesClick;

    BtnSelNone := TButton.Create(F);
    BtnSelNone.Parent := F;
    BtnSelNone.Left := 444; BtnSelNone.Top := 117; BtnSelNone.Width := 80; BtnSelNone.Height := 23;
    BtnSelNone.Anchors := [akTop, akRight];
    BtnSelNone.Caption := 'Select None';
    BtnSelNone.OnClick := @F.BtnSelectNoneFilesClick;

    F.LvPreviewFiles := TListView.Create(F);
    F.LvPreviewFiles.Parent := F;
    F.LvPreviewFiles.Left := 16; F.LvPreviewFiles.Top := 144;
    F.LvPreviewFiles.Width := 508; F.LvPreviewFiles.Height := 180;
    F.LvPreviewFiles.Anchors := [akLeft, akTop, akRight, akBottom];
    F.LvPreviewFiles.ViewStyle := vsReport;
    F.LvPreviewFiles.Checkboxes := True;
    F.LvPreviewFiles.RowSelect := True;
    F.LvPreviewFiles.GridLines := True;
    with F.LvPreviewFiles.Columns.Add do begin Caption := 'File Path'; Width := 385; end;
    with F.LvPreviewFiles.Columns.Add do begin Caption := 'Size'; Width := 100; end;

    Lbl := TLabel.Create(F);
    Lbl.Parent := F;
    Lbl.Left := 16; Lbl.Top := 338;
    Lbl.Anchors := [akLeft, akBottom];
    Lbl.Caption := 'Priority:';

    F.CmbPriority := TComboBox.Create(F);
    F.CmbPriority.Parent := F;
    F.CmbPriority.Left := 76; F.CmbPriority.Top := 334; F.CmbPriority.Width := 120;
    F.CmbPriority.Anchors := [akLeft, akBottom];
    F.CmbPriority.Style := csDropDownList;
    F.CmbPriority.Items.Add('High');
    F.CmbPriority.Items.Add('Normal');
    F.CmbPriority.Items.Add('Low');
    F.CmbPriority.ItemIndex := 1;

    F.ChkStart := TCheckBox.Create(F);
    F.ChkStart.Parent := F;
    F.ChkStart.Left := 16; F.ChkStart.Top := 366;
    F.ChkStart.Anchors := [akLeft, akBottom];
    F.ChkStart.Caption := 'Start when added';
    F.ChkStart.Checked := DefaultStart;

    F.ChkTrash := TCheckBox.Create(F);
    F.ChkTrash.Parent := F;
    F.ChkTrash.Left := 215; F.ChkTrash.Top := 366;
    F.ChkTrash.Anchors := [akLeft, akBottom];
    F.ChkTrash.Caption := 'Move .torrent file to the trash';
    F.ChkTrash.Checked := False;

    BtnOK := TButton.Create(F);
    BtnOK.Parent := F;
    BtnOK.Left := 356; BtnOK.Top := 392; BtnOK.Width := 80;
    BtnOK.Anchors := [akRight, akBottom];
    BtnOK.Caption := 'Open';
    BtnOK.Default := True;
    BtnOK.ModalResult := mrOk;

    BtnCancel := TButton.Create(F);
    BtnCancel.Parent := F;
    BtnCancel.Left := 444; BtnCancel.Top := 392; BtnCancel.Width := 80;
    BtnCancel.Anchors := [akRight, akBottom];
    BtnCancel.Caption := 'Cancel';
    BtnCancel.Cancel := True;
    BtnCancel.ModalResult := mrCancel;

    F.EdtDirChange(nil);
    if InitialFile <> '' then
      F.LoadTorrentMetadata(InitialFile);

    if F.ShowModal = mrOk then
    begin
      SelectedFile := Trim(F.EdtFile.Text);
      DestDir := Trim(F.EdtDir.Text);
      StartNow := F.ChkStart.Checked;
      TrashTorrent := F.ChkTrash.Checked;
      case F.CmbPriority.ItemIndex of
        0: Priority := TR_PRI_HIGH;
        2: Priority := TR_PRI_LOW;
      else
        Priority := TR_PRI_NORMAL;
      end;

      UnwantedCount := 0;
      SetLength(UnwantedFiles, F.LvPreviewFiles.Items.Count);
      for I := 0 to F.LvPreviewFiles.Items.Count - 1 do
        if not F.LvPreviewFiles.Items[I].Checked then
        begin
          UnwantedFiles[UnwantedCount] := I;
          Inc(UnwantedCount);
        end;
      SetLength(UnwantedFiles, UnwantedCount);

      Result := SelectedFile <> '';
    end;
  finally
    F.Free;
  end;
end;

{ 2. Open URL / Magnet Dialog }

type
  TAddUrlForm = class(TForm)
  public
    RpcRef: TTransmissionRpcClient;
    EdtUrl: TEdit;
    EdtDir: TEdit;
    LblFreeSpace: TLabel;
    CmbPriority: TComboBox;
    ChkStart: TCheckBox;
    procedure BtnBrowseDirClick(Sender: TObject);
    procedure EdtDirChange(Sender: TObject);
  end;

procedure TAddUrlForm.BtnBrowseDirClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := EdtDir.Text;
  if SelectDirectory('Select Destination Folder', '', Dir) then
    EdtDir.Text := Dir;
end;

procedure TAddUrlForm.EdtDirChange(Sender: TObject);
var
  FreeB: Int64;
begin
  if (RpcRef <> nil) and (Trim(EdtDir.Text) <> '') and RpcRef.QueryFreeSpace(EdtDir.Text, FreeB) and (FreeB >= 0) then
    LblFreeSpace.Caption := Format('Free space: %s', [FormatSize(FreeB)])
  else
    LblFreeSpace.Caption := '';
end;

function ShowAddUrlDialog(Owner: TComponent; Rpc: TTransmissionRpcClient;
  const DefaultDir: string; DefaultStart: Boolean;
  out UrlOrMagnet, DestDir: string; out StartNow: Boolean;
  out Priority: Integer): Boolean;
var
  F: TAddUrlForm;
  Lbl: TLabel;
  BtnDir, BtnOK, BtnCancel: TButton;
  ClipStr: string;
begin
  Result := False;
  F := TAddUrlForm.CreateNew(Owner);
  try
    F.RpcRef := Rpc;
    F.Caption := 'Open URL or Magnet Link';
    F.Position := poMainFormCenter;
    F.BorderStyle := bsDialog;
    F.ClientWidth := 480;
    F.ClientHeight := 225;

    Lbl := TLabel.Create(F);
    Lbl.Parent := F;
    Lbl.Left := 16; Lbl.Top := 16;
    Lbl.Caption := 'Enter torrent URL or magnet: link:';

    F.EdtUrl := TEdit.Create(F);
    F.EdtUrl.Parent := F;
    F.EdtUrl.Left := 16; F.EdtUrl.Top := 36; F.EdtUrl.Width := 448;

    ClipStr := Trim(Clipboard.AsText);
    if (Pos('magnet:?', LowerCase(ClipStr)) = 1) or
       (Pos('http://', LowerCase(ClipStr)) = 1) or
       (Pos('https://', LowerCase(ClipStr)) = 1) then
      F.EdtUrl.Text := ClipStr;

    Lbl := TLabel.Create(F);
    Lbl.Parent := F;
    Lbl.Left := 16; Lbl.Top := 72;
    Lbl.Caption := 'Destination folder:';

    F.LblFreeSpace := TLabel.Create(F);
    F.LblFreeSpace.Parent := F;
    F.LblFreeSpace.Left := 140; F.LblFreeSpace.Top := 72;
    F.LblFreeSpace.Font.Color := clGrayText;

    F.EdtDir := TEdit.Create(F);
    F.EdtDir.Parent := F;
    F.EdtDir.Left := 16; F.EdtDir.Top := 92; F.EdtDir.Width := 360;
    F.EdtDir.Text := DefaultDir;
    F.EdtDir.OnChange := @F.EdtDirChange;

    BtnDir := TButton.Create(F);
    BtnDir.Parent := F;
    BtnDir.Left := 384; BtnDir.Top := 90; BtnDir.Width := 80; BtnDir.Height := 26;
    BtnDir.Caption := 'Browse...';
    BtnDir.OnClick := @F.BtnBrowseDirClick;

    Lbl := TLabel.Create(F);
    Lbl.Parent := F;
    Lbl.Left := 16; Lbl.Top := 134;
    Lbl.Caption := 'Priority:';

    F.CmbPriority := TComboBox.Create(F);
    F.CmbPriority.Parent := F;
    F.CmbPriority.Left := 76; F.CmbPriority.Top := 130; F.CmbPriority.Width := 130;
    F.CmbPriority.Style := csDropDownList;
    F.CmbPriority.Items.Add('High');
    F.CmbPriority.Items.Add('Normal');
    F.CmbPriority.Items.Add('Low');
    F.CmbPriority.ItemIndex := 1;

    F.ChkStart := TCheckBox.Create(F);
    F.ChkStart.Parent := F;
    F.ChkStart.Left := 230; F.ChkStart.Top := 133;
    F.ChkStart.Caption := 'Start when added';
    F.ChkStart.Checked := DefaultStart;

    BtnOK := TButton.Create(F);
    BtnOK.Parent := F;
    BtnOK.Left := 296; BtnOK.Top := 180; BtnOK.Width := 80;
    BtnOK.Caption := 'Open';
    BtnOK.Default := True;
    BtnOK.ModalResult := mrOk;

    BtnCancel := TButton.Create(F);
    BtnCancel.Parent := F;
    BtnCancel.Left := 384; BtnCancel.Top := 180; BtnCancel.Width := 80;
    BtnCancel.Caption := 'Cancel';
    BtnCancel.Cancel := True;
    BtnCancel.ModalResult := mrCancel;

    F.EdtDirChange(nil);

    if F.ShowModal = mrOk then
    begin
      UrlOrMagnet := Trim(F.EdtUrl.Text);
      DestDir := Trim(F.EdtDir.Text);
      StartNow := F.ChkStart.Checked;
      case F.CmbPriority.ItemIndex of
        0: Priority := TR_PRI_HIGH;
        2: Priority := TR_PRI_LOW;
      else
        Priority := TR_PRI_NORMAL;
      end;
      Result := UrlOrMagnet <> '';
    end;
  finally
    F.Free;
  end;
end;

{ 3. Make New Torrent Dialog }

type
  TMakeTorrentForm = class(TForm)
  public
    RpcRef: TTransmissionRpcClient;
    RbFolder: TRadioButton;
    RbFile: TRadioButton;
    EdtSource: TEdit;
    MemTrackers: TMemo;
    EdtComment: TEdit;
    ChkPrivate: TCheckBox;
    ChkAddNow: TCheckBox;
    procedure BtnBrowseSourceClick(Sender: TObject);
    procedure BtnCreateClick(Sender: TObject);
  end;

procedure TMakeTorrentForm.BtnBrowseSourceClick(Sender: TObject);
var
  Dir: string;
  Dlg: TOpenDialog;
begin
  if RbFolder.Checked then
  begin
    Dir := EdtSource.Text;
    if SelectDirectory('Select Source Folder', '', Dir) then
      EdtSource.Text := Dir;
  end
  else
  begin
    Dlg := TOpenDialog.Create(Self);
    try
      Dlg.Title := 'Select Source File';
      if Dlg.Execute then
        EdtSource.Text := Dlg.FileName;
    finally
      Dlg.Free;
    end;
  end;
end;

procedure TMakeTorrentForm.BtnCreateClick(Sender: TObject);
var
  SaveDlg: TSaveDialog;
  OutFile, LogOut, AddedName: string;
begin
  if Trim(EdtSource.Text) = '' then
  begin
    MessageDlg('Please select a source file or folder first.', mtWarning, [mbOK], 0);
    Exit;
  end;

  SaveDlg := TSaveDialog.Create(Self);
  try
    SaveDlg.Title := 'Save New .torrent File';
    SaveDlg.Filter := 'Torrent Files (*.torrent)|*.torrent';
    SaveDlg.DefaultExt := 'torrent';
    SaveDlg.FileName := ExtractFileName(ExcludeTrailingPathDelimiter(EdtSource.Text)) + '.torrent';
    if not SaveDlg.Execute then Exit;
    OutFile := SaveDlg.FileName;
  finally
    SaveDlg.Free;
  end;

  Screen.Cursor := crHourGlass;
  try
    if RpcRef.CreateTorrentFile(EdtSource.Text, OutFile, MemTrackers.Lines, EdtComment.Text, ChkPrivate.Checked, LogOut) then
    begin
      if ChkAddNow.Checked then
        RpcRef.AddTorrentFile(OutFile, ExtractFilePath(ExcludeTrailingPathDelimiter(EdtSource.Text)),
          True, TR_PRI_NORMAL, [], AddedName);
      MessageDlg('New torrent created successfully:' + LineEnding + OutFile, mtInformation, [mbOK], 0);
      ModalResult := mrOk;
    end
    else
      MessageDlg('Failed to create torrent:' + LineEnding + LogOut, mtError, [mbOK], 0);
  finally
    Screen.Cursor := crDefault;
  end;
end;

function ShowMakeTorrentDialog(Owner: TComponent; Rpc: TTransmissionRpcClient): Boolean;
var
  F: TMakeTorrentForm;
  Lbl: TLabel;
  BtnBrowse, BtnCreate, BtnClose: TButton;
begin
  F := TMakeTorrentForm.CreateNew(Owner);
  try
    F.RpcRef := Rpc;
    F.Caption := 'New Torrent';
    F.Position := poMainFormCenter;
    F.BorderStyle := bsDialog;
    F.ClientWidth := 480;
    F.ClientHeight := 360;

    F.RbFolder := TRadioButton.Create(F);
    F.RbFolder.Parent := F;
    F.RbFolder.Left := 16; F.RbFolder.Top := 16;
    F.RbFolder.Caption := 'Source Folder';
    F.RbFolder.Checked := True;

    F.RbFile := TRadioButton.Create(F);
    F.RbFile.Parent := F;
    F.RbFile.Left := 150; F.RbFile.Top := 16;
    F.RbFile.Caption := 'Source File';

    F.EdtSource := TEdit.Create(F);
    F.EdtSource.Parent := F;
    F.EdtSource.Left := 16; F.EdtSource.Top := 42; F.EdtSource.Width := 360;

    BtnBrowse := TButton.Create(F);
    BtnBrowse.Parent := F;
    BtnBrowse.Left := 384; BtnBrowse.Top := 40; BtnBrowse.Width := 80; BtnBrowse.Height := 26;
    BtnBrowse.Caption := 'Browse...';
    BtnBrowse.OnClick := @F.BtnBrowseSourceClick;

    Lbl := TLabel.Create(F);
    Lbl.Parent := F;
    Lbl.Left := 16; Lbl.Top := 78;
    Lbl.Caption := 'Trackers (one announce URL per line):';

    F.MemTrackers := TMemo.Create(F);
    F.MemTrackers.Parent := F;
    F.MemTrackers.Left := 16; F.MemTrackers.Top := 98; F.MemTrackers.Width := 448; F.MemTrackers.Height := 100;
    F.MemTrackers.ScrollBars := ssVertical;

    Lbl := TLabel.Create(F);
    Lbl.Parent := F;
    Lbl.Left := 16; Lbl.Top := 210;
    Lbl.Caption := 'Comment:';

    F.EdtComment := TEdit.Create(F);
    F.EdtComment.Parent := F;
    F.EdtComment.Left := 85; F.EdtComment.Top := 206; F.EdtComment.Width := 379;

    F.ChkPrivate := TCheckBox.Create(F);
    F.ChkPrivate.Parent := F;
    F.ChkPrivate.Left := 16; F.ChkPrivate.Top := 248;
    F.ChkPrivate.Caption := 'Private torrent (do not distribute via DHT/PEX)';

    F.ChkAddNow := TCheckBox.Create(F);
    F.ChkAddNow.Parent := F;
    F.ChkAddNow.Left := 16; F.ChkAddNow.Top := 274;
    F.ChkAddNow.Caption := 'Add torrent to Transmission after creation';
    F.ChkAddNow.Checked := True;

    BtnCreate := TButton.Create(F);
    BtnCreate.Parent := F;
    BtnCreate.Left := 280; BtnCreate.Top := 315; BtnCreate.Width := 96;
    BtnCreate.Caption := 'Create...';
    BtnCreate.OnClick := @F.BtnCreateClick;

    BtnClose := TButton.Create(F);
    BtnClose.Parent := F;
    BtnClose.Left := 384; BtnClose.Top := 315; BtnClose.Width := 80;
    BtnClose.Caption := 'Close';
    BtnClose.Cancel := True;
    BtnClose.ModalResult := mrCancel;

    Result := F.ShowModal = mrOk;
  finally
    F.Free;
  end;
end;

{ 4. Edit Trackers Dialog (matching TrackersDialog.ui) }

type
  TEditTrackersForm = class(TForm)
  public
    Mem: TMemo;
    procedure BtnConvertClick(Sender: TObject);
  end;

{ จัดรูปแบบรายการ Tracker ของทอร์เรนต์เป็นข้อความแบ่งบรรทัดและแบ่ง Tier ด้วยบรรทัดว่าง }
function FormatTrackersAsText(Torrent: TTorrentItem): string;
var
  I, LastTier: Integer;
  SL: TStringList;
begin
  Result := '';
  if Torrent = nil then Exit;
  SL := TStringList.Create;
  try
    LastTier := -1;
    for I := 0 to High(Torrent.Trackers) do
    begin
      if (LastTier >= 0) and (Torrent.Trackers[I].Tier <> LastTier) then
        SL.Add('');
      SL.Add(Torrent.Trackers[I].Announce);
      LastTier := Torrent.Trackers[I].Tier;
    end;
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

{ แปลงโปรโตคอล Tracker URL ระหว่าง https:// (http://) กับ ht..tps:// (ht..tp://)
  Mode: 0 = สลับอัตโนมัติ, 1 = แปลงเป็น ht..tps://, 2 = แปลงกลับเป็น https:// }
function TransformTrackerUrls(const SourceText: string; Mode: Integer): string;
var
  LowerTxt: string;
  ToDots: Boolean;
begin
  Result := SourceText;
  if Result = '' then Exit;

  if Mode = 1 then
    ToDots := True
  else if Mode = 2 then
    ToDots := False
  else
  begin
    LowerTxt := LowerCase(SourceText);
    ToDots := (Pos('https://', LowerTxt) > 0) or (Pos('http://', LowerTxt) > 0);
  end;

  if ToDots then
  begin
    // แทนที่ https:// ก่อน http:// เพื่อไม่ให้ทับซ้อน
    Result := StringReplace(Result, 'https://', 'ht..tps://', [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, 'http://', 'ht..tp://', [rfReplaceAll, rfIgnoreCase]);
  end
  else
  begin
    Result := StringReplace(Result, 'ht..tps://', 'https://', [rfReplaceAll, rfIgnoreCase]);
    Result := StringReplace(Result, 'ht..tp://', 'http://', [rfReplaceAll, rfIgnoreCase]);
  end;
end;

procedure TEditTrackersForm.BtnConvertClick(Sender: TObject);
begin
  if Mem <> nil then
    Mem.Lines.Text := TransformTrackerUrls(Mem.Lines.Text, TComponent(Sender).Tag);
end;

function ShowEditTrackersDialog(Owner: TComponent; Rpc: TTransmissionRpcClient;
  Torrent: TTorrentItem): Boolean;
var
  F: TEditTrackersForm;
  Gb: TGroupBox;
  Lbl1, Lbl2, LblList: TLabel;
  BtnToggle, BtnToDots, BtnToStd: TButton;
  BtnOK, BtnCancel: TButton;
  Args: TJSONObject;
begin
  Result := False;
  F := TEditTrackersForm.CreateNew(Owner);
  try
    F.Caption := 'Edit Trackers - ' + Torrent.Name;
    F.Position := poOwnerFormCenter;
    F.BorderStyle := bsSizeable;
    F.ClientWidth := 560;
    F.ClientHeight := 410;
    F.Constraints.MinWidth := 540;
    F.Constraints.MinHeight := 340;

    Gb := TGroupBox.Create(F);
    Gb.Parent := F;
    Gb.Left := 12; Gb.Top := 10; Gb.Width := 536; Gb.Height := 350;
    Gb.Anchors := [akLeft, akTop, akRight, akBottom];
    Gb.Caption := 'Tracker Announce URLs';

    Lbl1 := TLabel.Create(Gb);
    Lbl1.Parent := Gb;
    Lbl1.Left := 12; Lbl1.Top := 10;
    Lbl1.Caption := 'To add a backup URL, add it on the next line after a primary URL.';

    Lbl2 := TLabel.Create(Gb);
    Lbl2.Parent := Gb;
    Lbl2.Left := 12; Lbl2.Top := 28;
    Lbl2.Caption := 'To add a new primary URL (new tier), add it after a blank line.';

    LblList := TLabel.Create(Gb);
    LblList.Parent := Gb;
    LblList.Left := 12; LblList.Top := 54;
    LblList.Font.Style := [fsBold];
    LblList.Caption := 'Tracker List:';

    BtnToggle := TButton.Create(Gb);
    BtnToggle.Parent := Gb;
    BtnToggle.Left := 102; BtnToggle.Top := 49; BtnToggle.Width := 180; BtnToggle.Height := 26;
    BtnToggle.Caption := 'สลับ https:// <-> ht..tps://';
    BtnToggle.Tag := 0;
    BtnToggle.OnClick := @F.BtnConvertClick;

    BtnToDots := TButton.Create(Gb);
    BtnToDots.Parent := Gb;
    BtnToDots.Left := 288; BtnToDots.Top := 49; BtnToDots.Width := 112; BtnToDots.Height := 26;
    BtnToDots.Caption := 'เป็น ht..tps://';
    BtnToDots.Tag := 1;
    BtnToDots.OnClick := @F.BtnConvertClick;

    BtnToStd := TButton.Create(Gb);
    BtnToStd.Parent := Gb;
    BtnToStd.Left := 406; BtnToStd.Top := 49; BtnToStd.Width := 118; BtnToStd.Height := 26;
    BtnToStd.Caption := 'กลับเป็น https://';
    BtnToStd.Tag := 2;
    BtnToStd.OnClick := @F.BtnConvertClick;

    F.Mem := TMemo.Create(Gb);
    F.Mem.Parent := Gb;
    F.Mem.Left := 12; F.Mem.Top := 82; F.Mem.Width := 512; F.Mem.Height := 232;
    F.Mem.Anchors := [akLeft, akTop, akRight, akBottom];
    F.Mem.ScrollBars := ssBoth;
    F.Mem.Text := FormatTrackersAsText(Torrent);

    BtnOK := TButton.Create(F);
    BtnOK.Parent := F;
    BtnOK.Left := 380; BtnOK.Top := 370; BtnOK.Width := 80;
    BtnOK.Anchors := [akRight, akBottom];
    BtnOK.Caption := 'OK';
    BtnOK.Default := True;
    BtnOK.ModalResult := mrOk;

    BtnCancel := TButton.Create(F);
    BtnCancel.Parent := F;
    BtnCancel.Left := 468; BtnCancel.Top := 370; BtnCancel.Width := 80;
    BtnCancel.Anchors := [akRight, akBottom];
    BtnCancel.Caption := 'Cancel';
    BtnCancel.Cancel := True;
    BtnCancel.ModalResult := mrCancel;

    if F.ShowModal = mrOk then
    begin
      Args := TJSONObject.Create;
      Args.Add('trackerList', F.Mem.Lines.Text);
      Result := Rpc.SetTorrentOptions(Torrent.Id, Args);
    end;
  finally
    F.Free;
  end;
end;

{ 5. Torrent Properties / Details Dialog (with Live Auto-Refresh) }

type
  TDetailsForm = class(TForm)
  public
    RpcRef: TTransmissionRpcClient;
    TorRef: TTorrentItem;
    RefreshTimer: TTimer;

    // Activity dynamic labels
    LblHaveVal: TLabel;
    LblDownVal: TLabel;
    LblUpVal: TLabel;
    LblStateVal: TLabel;
    LblDownSpdVal: TLabel;
    LblUpSpdVal: TLabel;
    LblRunTimeVal: TLabel;
    LblRemTimeVal: TLabel;
    LblLastActVal: TLabel;
    LblErrVal: TLabel;

    TsPeersTab: TTabSheet;
    TsTrackersTab: TTabSheet;
    TsFilesTab: TTabSheet;
    LvPeers: TListView;
    LvTrackers: TListView;
    LvFiles: TListView;

    ChkHonorSession: TCheckBox;
    ChkDownLimit: TCheckBox;
    SpnDownLimit: TSpinEdit;
    ChkUpLimit: TCheckBox;
    SpnUpLimit: TSpinEdit;
    CmbRatioMode: TComboBox;
    EdtRatioLimit: TEdit;
    SpnPeerLimit: TSpinEdit;

    procedure UpdateDynamicViews;
    procedure RefreshTimerTick(Sender: TObject);
    procedure BtnApplyOptionsClick(Sender: TObject);
    procedure BtnApplyFilesClick(Sender: TObject);
    procedure BtnSelectAllFilesClick(Sender: TObject);
    procedure BtnSelectNoneFilesClick(Sender: TObject);
    procedure BtnSetFilePriorityClick(Sender: TObject);
    procedure BtnRenameFileClick(Sender: TObject);
    procedure BtnEditTrackersClick(Sender: TObject);
    procedure BtnAddTrackerClick(Sender: TObject);
    procedure BtnRemoveTrackerClick(Sender: TObject);
    procedure BtnToggleTrackerHttpsClick(Sender: TObject);
  end;

function CreateKeyValLabel(ParentCtrl: TWinControl; Y: Integer; const KeyText, ValText: string): TLabel;
var
  LKey: TLabel;
begin
  LKey := TLabel.Create(ParentCtrl);
  LKey.Parent := ParentCtrl;
  LKey.Left := 16;
  LKey.Top := Y;
  LKey.Font.Style := [fsBold];
  LKey.Caption := KeyText;

  Result := TLabel.Create(ParentCtrl);
  Result.Parent := ParentCtrl;
  Result.Left := 155;
  Result.Top := Y;
  Result.Width := 440;
  Result.Caption := ValText;
end;

procedure TDetailsForm.UpdateDynamicViews;
var
  I: Integer;
  LI: TListItem;
  PctFile: Double;
begin
  if TorRef = nil then Exit;

  LblHaveVal.Caption := Format('%s of %s (%s) - %s Unverified',
    [FormatSize(TorRef.HaveTotal), FormatSize(TorRef.SizeWhenDone),
     FormatPercent(TorRef.PercentDone), FormatSize(TorRef.HaveUnchecked)]);
  LblDownVal.Caption := FormatSize(TorRef.DownloadedEver);
  LblUpVal.Caption := Format('%s (Ratio: %s)',
    [FormatSize(TorRef.UploadedEver), FormatRatio(TorRef.UploadRatio)]);
  LblStateVal.Caption := TorRef.FullStatusString;
  LblDownSpdVal.Caption := FormatSpeed(TorRef.RateDownload);
  LblUpSpdVal.Caption := FormatSpeed(TorRef.RateUpload);
  LblRunTimeVal.Caption := Format('Downloading: %s, Seeding: %s',
    [FormatDuration(TorRef.SecondsDownloading), FormatDuration(TorRef.SecondsSeeding)]);
  LblRemTimeVal.Caption := FormatETA(TorRef.ETA);
  LblLastActVal.Caption := UnixToDateTimeStr(TorRef.ActivityDate);
  if TorRef.ErrorString <> '' then
    LblErrVal.Caption := TorRef.ErrorString
  else
    LblErrVal.Caption := 'None';

  // Update Peers ListView
  TsPeersTab.Caption := Format('Peers (%d)', [Length(TorRef.Peers)]);
  LvPeers.Items.BeginUpdate;
  try
    LvPeers.Items.Clear;
    for I := 0 to High(TorRef.Peers) do
    begin
      LI := LvPeers.Items.Add;
      LI.Caption := Format('%s:%d', [TorRef.Peers[I].Address, TorRef.Peers[I].Port]);
      LI.SubItems.Add(TorRef.Peers[I].ClientName);
      LI.SubItems.Add(FormatPercent(TorRef.Peers[I].Progress));
      LI.SubItems.Add(FormatSpeed(TorRef.Peers[I].RateToClient));
      LI.SubItems.Add(FormatSpeed(TorRef.Peers[I].RateToPeer));
      LI.SubItems.Add(TorRef.Peers[I].FlagStr);
    end;
  finally
    LvPeers.Items.EndUpdate;
  end;

  // Update Trackers ListView
  TsTrackersTab.Caption := Format('Trackers (%d)', [Length(TorRef.Trackers)]);
  LvTrackers.Items.BeginUpdate;
  try
    while LvTrackers.Items.Count < Length(TorRef.Trackers) do
      LvTrackers.Items.Add;
    while LvTrackers.Items.Count > Length(TorRef.Trackers) do
      LvTrackers.Items.Delete(LvTrackers.Items.Count - 1);

    for I := 0 to High(TorRef.Trackers) do
    begin
      LI := LvTrackers.Items[I];
      LI.Caption := IntToStr(TorRef.Trackers[I].Tier + 1);
      LI.SubItems.Clear;
      LI.SubItems.Add(TorRef.Trackers[I].Announce);
      LI.SubItems.Add(TorRef.Trackers[I].LastAnnounceResult);
      if TorRef.Trackers[I].SeederCount >= 0 then
        LI.SubItems.Add(IntToStr(TorRef.Trackers[I].SeederCount))
      else
        LI.SubItems.Add('-');
      if TorRef.Trackers[I].LeecherCount >= 0 then
        LI.SubItems.Add(IntToStr(TorRef.Trackers[I].LeecherCount))
      else
        LI.SubItems.Add('-');
    end;
  finally
    LvTrackers.Items.EndUpdate;
  end;

  // Update Files progress without overwriting user's unsaved checkbox changes if count matches
  TsFilesTab.Caption := Format('Files (%d)', [Length(TorRef.Files)]);
  if LvFiles.Items.Count <> Length(TorRef.Files) then
  begin
    LvFiles.Items.BeginUpdate;
    try
      LvFiles.Items.Clear;
      for I := 0 to High(TorRef.Files) do
      begin
        LI := LvFiles.Items.Add;
        LI.Checked := TorRef.Files[I].Wanted;
        LI.Caption := TorRef.Files[I].Name;
        LI.SubItems.Add(FormatSize(TorRef.Files[I].Length));
        LI.SubItems.Add(FormatSize(TorRef.Files[I].BytesCompleted));
        if TorRef.Files[I].Length > 0 then
          PctFile := TorRef.Files[I].BytesCompleted / TorRef.Files[I].Length
        else
          PctFile := 1.0;
        LI.SubItems.Add(FormatPercent(PctFile));
        LI.SubItems.Add(PriorityToStr(TorRef.Files[I].Priority));
      end;
    finally
      LvFiles.Items.EndUpdate;
    end;
  end
  else
  begin
    for I := 0 to High(TorRef.Files) do
    begin
      LI := LvFiles.Items[I];
      if LI.SubItems.Count >= 4 then
      begin
        LI.SubItems[1] := FormatSize(TorRef.Files[I].BytesCompleted);
        if TorRef.Files[I].Length > 0 then
          PctFile := TorRef.Files[I].BytesCompleted / TorRef.Files[I].Length
        else
          PctFile := 1.0;
        LI.SubItems[2] := FormatPercent(PctFile);
      end;
    end;
  end;
end;

procedure TDetailsForm.RefreshTimerTick(Sender: TObject);
begin
  if (RpcRef <> nil) and (TorRef <> nil) and RpcRef.FetchTorrentDetails(TorRef) then
    UpdateDynamicViews;
end;

procedure TDetailsForm.BtnApplyOptionsClick(Sender: TObject);
var
  Args: TJSONObject;
begin
  Args := TJSONObject.Create;
  Args.Add('honorsSessionLimits', ChkHonorSession.Checked);
  Args.Add('downloadLimited', ChkDownLimit.Checked);
  Args.Add('downloadLimit', SpnDownLimit.Value);
  Args.Add('uploadLimited', ChkUpLimit.Checked);
  Args.Add('uploadLimit', SpnUpLimit.Value);
  Args.Add('seedRatioMode', CmbRatioMode.ItemIndex);
  Args.Add('seedRatioLimit', StrToFloatDef(EdtRatioLimit.Text, 2.0));
  Args.Add('peer-limit', SpnPeerLimit.Value);

  if RpcRef.SetTorrentOptions(TorRef.Id, Args) then
    MessageDlg('Torrent options updated.', mtInformation, [mbOK], 0)
  else
    MessageDlg('Failed to update options: ' + RpcRef.LastError, mtError, [mbOK], 0);
end;

procedure TDetailsForm.BtnApplyFilesClick(Sender: TObject);
var
  Args: TJSONObject;
  WantedArr, UnwantedArr: TJSONArray;
  I: Integer;
begin
  WantedArr := TJSONArray.Create;
  UnwantedArr := TJSONArray.Create;
  for I := 0 to LvFiles.Items.Count - 1 do
  begin
    if LvFiles.Items[I].Checked then
      WantedArr.Add(I)
    else
      UnwantedArr.Add(I);
  end;

  Args := TJSONObject.Create;
  if WantedArr.Count > 0 then
    Args.Add('files-wanted', WantedArr)
  else
    WantedArr.Free;

  if UnwantedArr.Count > 0 then
    Args.Add('files-unwanted', UnwantedArr)
  else
    UnwantedArr.Free;

  if RpcRef.SetTorrentOptions(TorRef.Id, Args) then
  begin
    RpcRef.FetchTorrentDetails(TorRef);
    UpdateDynamicViews;
    MessageDlg('File selection saved.', mtInformation, [mbOK], 0);
  end
  else
    MessageDlg('Failed to update file selection: ' + RpcRef.LastError, mtError, [mbOK], 0);
end;

procedure TDetailsForm.BtnSelectAllFilesClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to LvFiles.Items.Count - 1 do
    LvFiles.Items[I].Checked := True;
end;

procedure TDetailsForm.BtnSelectNoneFilesClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to LvFiles.Items.Count - 1 do
    LvFiles.Items[I].Checked := False;
end;

procedure TDetailsForm.BtnSetFilePriorityClick(Sender: TObject);
var
  TagPri: Integer;
  KeyName: string;
  Args: TJSONObject;
  IdxArr: TJSONArray;
  I: Integer;
begin
  TagPri := TComponent(Sender).Tag;
  if TagPri > 0 then
    KeyName := 'priority-high'
  else if TagPri < 0 then
    KeyName := 'priority-low'
  else
    KeyName := 'priority-normal';

  IdxArr := TJSONArray.Create;
  for I := 0 to LvFiles.Items.Count - 1 do
    if LvFiles.Items[I].Selected then
    begin
      IdxArr.Add(I);
      if LvFiles.Items[I].SubItems.Count >= 4 then
        LvFiles.Items[I].SubItems[3] := PriorityToStr(TagPri);
    end;

  if IdxArr.Count = 0 then
  begin
    IdxArr.Free;
    MessageDlg('Select one or more files in the list first.', mtInformation, [mbOK], 0);
    Exit;
  end;

  Args := TJSONObject.Create;
  Args.Add(KeyName, IdxArr);
  RpcRef.SetTorrentOptions(TorRef.Id, Args);
end;

procedure TDetailsForm.BtnRenameFileClick(Sender: TObject);
var
  OldPath, BaseName, NewName: string;
begin
  if LvFiles.Selected = nil then
  begin
    MessageDlg('Please select a file to rename.', mtInformation, [mbOK], 0);
    Exit;
  end;
  OldPath := LvFiles.Selected.Caption;
  BaseName := ExtractFileName(StringReplace(OldPath, '/', '\', [rfReplaceAll]));
  NewName := BaseName;
  if InputQuery('Rename File', 'Enter new file name:', NewName) and (Trim(NewName) <> '') and (NewName <> BaseName) then
  begin
    if RpcRef.RenameTorrentPath(TorRef.Id, OldPath, Trim(NewName)) then
    begin
      RpcRef.FetchTorrentDetails(TorRef);
      LvFiles.Items.Clear;
      UpdateDynamicViews;
    end
    else
      MessageDlg('Failed to rename file: ' + RpcRef.LastError, mtError, [mbOK], 0);
  end;
end;

procedure TDetailsForm.BtnEditTrackersClick(Sender: TObject);
begin
  if ShowEditTrackersDialog(Self, RpcRef, TorRef) then
  begin
    RpcRef.FetchTorrentDetails(TorRef);
    UpdateDynamicViews;
  end;
end;

procedure TDetailsForm.BtnAddTrackerClick(Sender: TObject);
var
  NewUrl: string;
  Args: TJSONObject;
  Arr: TJSONArray;
begin
  NewUrl := '';
  if InputQuery('Add Tracker', 'Enter tracker announce URL:', NewUrl) and (Trim(NewUrl) <> '') then
  begin
    Args := TJSONObject.Create;
    Arr := TJSONArray.Create;
    Arr.Add(Trim(NewUrl));
    Args.Add('trackerAdd', Arr);
    if RpcRef.SetTorrentOptions(TorRef.Id, Args) then
    begin
      RpcRef.FetchTorrentDetails(TorRef);
      UpdateDynamicViews;
    end
    else
      MessageDlg('Failed to add tracker: ' + RpcRef.LastError, mtError, [mbOK], 0);
  end;
end;

procedure TDetailsForm.BtnRemoveTrackerClick(Sender: TObject);
var
  Idx: Integer;
  Args: TJSONObject;
  Arr: TJSONArray;
begin
  if (LvTrackers.Selected = nil) or (LvTrackers.Selected.Index > High(TorRef.Trackers)) then
  begin
    MessageDlg('Select a tracker to remove first.', mtInformation, [mbOK], 0);
    Exit;
  end;
  Idx := LvTrackers.Selected.Index;
  Args := TJSONObject.Create;
  Arr := TJSONArray.Create;
  Arr.Add(TorRef.Trackers[Idx].Id);
  Args.Add('trackerRemove', Arr);
  if RpcRef.SetTorrentOptions(TorRef.Id, Args) then
  begin
    RpcRef.FetchTorrentDetails(TorRef);
    UpdateDynamicViews;
  end
  else
    MessageDlg('Failed to remove tracker: ' + RpcRef.LastError, mtError, [mbOK], 0);
end;

procedure TDetailsForm.BtnToggleTrackerHttpsClick(Sender: TObject);
var
  OldText, NewText: string;
  Args: TJSONObject;
begin
  if Length(TorRef.Trackers) = 0 then Exit;
  OldText := FormatTrackersAsText(TorRef);
  NewText := TransformTrackerUrls(OldText, 0);
  if NewText = OldText then Exit;
  Args := TJSONObject.Create;
  Args.Add('trackerList', NewText);
  if RpcRef.SetTorrentOptions(TorRef.Id, Args) then
  begin
    RpcRef.FetchTorrentDetails(TorRef);
    UpdateDynamicViews;
  end
  else
    MessageDlg('Failed to update trackers: ' + RpcRef.LastError, mtError, [mbOK], 0);
end;

procedure ShowDetailsDialog(Owner: TComponent; Rpc: TTransmissionRpcClient;
  Torrent: TTorrentItem);
var
  F: TDetailsForm;
  PC: TPageControl;
  TsAct, TsInfo, TsOpts: TTabSheet;
  BtnClose, BtnApplyOpt, BtnSaveFiles, BtnSelAll, BtnSelNone: TButton;
  BtnPriHigh, BtnPriNorm, BtnPriLow, BtnRename: TButton;
  BtnEditTrk, BtnAddTrk, BtnRemTrk, BtnToggleTrk: TButton;
  Lbl: TLabel;
begin
  if Torrent = nil then Exit;
  Rpc.FetchTorrentDetails(Torrent);

  F := TDetailsForm.CreateNew(Owner);
  try
    F.RpcRef := Rpc;
    F.TorRef := Torrent;
    F.Caption := Torrent.Name + ' Properties';
    F.Position := poMainFormCenter;
    F.BorderStyle := bsSizeable;
    F.ClientWidth := 650;
    F.ClientHeight := 455;
    F.Constraints.MinWidth := 580;
    F.Constraints.MinHeight := 400;

    PC := TPageControl.Create(F);
    PC.Parent := F;
    PC.Left := 0; PC.Top := 0; PC.Width := 650; PC.Height := 410;
    PC.Anchors := [akLeft, akTop, akRight, akBottom];

    // Tab 1: Activity
    TsAct := PC.AddTabSheet;
    TsAct.Caption := 'Activity';
    F.LblHaveVal := CreateKeyValLabel(TsAct, 18, 'Have:', '');
    F.LblDownVal := CreateKeyValLabel(TsAct, 46, 'Downloaded:', '');
    F.LblUpVal := CreateKeyValLabel(TsAct, 74, 'Uploaded:', '');
    F.LblStateVal := CreateKeyValLabel(TsAct, 102, 'State:', '');
    F.LblDownSpdVal := CreateKeyValLabel(TsAct, 130, 'Download Speed:', '');
    F.LblUpSpdVal := CreateKeyValLabel(TsAct, 158, 'Upload Speed:', '');
    F.LblRunTimeVal := CreateKeyValLabel(TsAct, 186, 'Running Time:', '');
    F.LblRemTimeVal := CreateKeyValLabel(TsAct, 214, 'Remaining Time:', '');
    F.LblLastActVal := CreateKeyValLabel(TsAct, 242, 'Last Activity:', '');
    F.LblErrVal := CreateKeyValLabel(TsAct, 270, 'Error:', '');

    // Tab 2: Information
    TsInfo := PC.AddTabSheet;
    TsInfo.Caption := 'Information';
    CreateKeyValLabel(TsInfo, 18, 'Total Size:', Format('%s (%d pieces @ %s)',
      [FormatSize(Torrent.TotalSize), Torrent.PieceCount, FormatSize(Torrent.PieceSize)]));
    CreateKeyValLabel(TsInfo, 46, 'Hash:', Torrent.HashString);
    if Torrent.IsPrivate then
      CreateKeyValLabel(TsInfo, 74, 'Type:', 'Private torrent (DHT and PEX disabled)')
    else
      CreateKeyValLabel(TsInfo, 74, 'Type:', 'Public torrent');
    CreateKeyValLabel(TsInfo, 102, 'Location:', Torrent.DownloadDir);
    CreateKeyValLabel(TsInfo, 130, 'Creator:', Torrent.Creator);
    CreateKeyValLabel(TsInfo, 158, 'Added Date:', UnixToDateTimeStr(Torrent.AddedDate));
    CreateKeyValLabel(TsInfo, 186, 'Completed Date:', UnixToDateTimeStr(Torrent.DoneDate));
    CreateKeyValLabel(TsInfo, 214, 'Comment:', Torrent.Comment);

    // Tab 3: Peers
    F.TsPeersTab := PC.AddTabSheet;
    F.TsPeersTab.Caption := 'Peers';
    F.LvPeers := TListView.Create(F.TsPeersTab);
    F.LvPeers.Parent := F.TsPeersTab;
    F.LvPeers.Align := alClient;
    F.LvPeers.ViewStyle := vsReport;
    F.LvPeers.ReadOnly := True;
    F.LvPeers.RowSelect := True;
    F.LvPeers.GridLines := True;
    with F.LvPeers.Columns.Add do begin Caption := 'Address'; Width := 155; end;
    with F.LvPeers.Columns.Add do begin Caption := 'Client'; Width := 155; end;
    with F.LvPeers.Columns.Add do begin Caption := '%'; Width := 65; end;
    with F.LvPeers.Columns.Add do begin Caption := 'Down'; Width := 90; end;
    with F.LvPeers.Columns.Add do begin Caption := 'Up'; Width := 90; end;
    with F.LvPeers.Columns.Add do begin Caption := 'Flags'; Width := 65; end;

    // Tab 4: Trackers
    F.TsTrackersTab := PC.AddTabSheet;
    F.TsTrackersTab.Caption := 'Trackers';
    F.LvTrackers := TListView.Create(F.TsTrackersTab);
    F.LvTrackers.Parent := F.TsTrackersTab;
    F.LvTrackers.Left := 8; F.LvTrackers.Top := 8; F.LvTrackers.Width := 624; F.LvTrackers.Height := 332;
    F.LvTrackers.Anchors := [akLeft, akTop, akRight, akBottom];
    F.LvTrackers.ViewStyle := vsReport;
    F.LvTrackers.ReadOnly := True;
    F.LvTrackers.RowSelect := True;
    F.LvTrackers.GridLines := True;
    with F.LvTrackers.Columns.Add do begin Caption := 'Tier'; Width := 45; end;
    with F.LvTrackers.Columns.Add do begin Caption := 'Tracker Announce URL'; Width := 280; end;
    with F.LvTrackers.Columns.Add do begin Caption := 'Status'; Width := 150; end;
    with F.LvTrackers.Columns.Add do begin Caption := 'Seeders'; Width := 65; end;
    with F.LvTrackers.Columns.Add do begin Caption := 'Leechers'; Width := 65; end;

    BtnAddTrk := TButton.Create(F.TsTrackersTab);
    BtnAddTrk.Parent := F.TsTrackersTab;
    BtnAddTrk.Left := 8; BtnAddTrk.Top := 346; BtnAddTrk.Width := 110;
    BtnAddTrk.Anchors := [akLeft, akBottom];
    BtnAddTrk.Caption := 'Add Tracker...';
    BtnAddTrk.OnClick := @F.BtnAddTrackerClick;

    BtnEditTrk := TButton.Create(F.TsTrackersTab);
    BtnEditTrk.Parent := F.TsTrackersTab;
    BtnEditTrk.Left := 124; BtnEditTrk.Top := 346; BtnEditTrk.Width := 115;
    BtnEditTrk.Anchors := [akLeft, akBottom];
    BtnEditTrk.Caption := 'Edit Trackers...';
    BtnEditTrk.OnClick := @F.BtnEditTrackersClick;

    BtnRemTrk := TButton.Create(F.TsTrackersTab);
    BtnRemTrk.Parent := F.TsTrackersTab;
    BtnRemTrk.Left := 245; BtnRemTrk.Top := 346; BtnRemTrk.Width := 120;
    BtnRemTrk.Anchors := [akLeft, akBottom];
    BtnRemTrk.Caption := 'Remove Tracker';
    BtnRemTrk.OnClick := @F.BtnRemoveTrackerClick;

    BtnToggleTrk := TButton.Create(F.TsTrackersTab);
    BtnToggleTrk.Parent := F.TsTrackersTab;
    BtnToggleTrk.Left := 371; BtnToggleTrk.Top := 346; BtnToggleTrk.Width := 190;
    BtnToggleTrk.Anchors := [akLeft, akBottom];
    BtnToggleTrk.Caption := 'สลับ https:// <-> ht..tps://';
    BtnToggleTrk.OnClick := @F.BtnToggleTrackerHttpsClick;

    // Tab 5: Files
    F.TsFilesTab := PC.AddTabSheet;
    F.TsFilesTab.Caption := 'Files';
    F.LvFiles := TListView.Create(F.TsFilesTab);
    F.LvFiles.Parent := F.TsFilesTab;
    F.LvFiles.Left := 8; F.LvFiles.Top := 8; F.LvFiles.Width := 624; F.LvFiles.Height := 332;
    F.LvFiles.Anchors := [akLeft, akTop, akRight, akBottom];
    F.LvFiles.ViewStyle := vsReport;
    F.LvFiles.Checkboxes := True;
    F.LvFiles.MultiSelect := True;
    F.LvFiles.RowSelect := True;
    F.LvFiles.GridLines := True;
    with F.LvFiles.Columns.Add do begin Caption := 'File Name'; Width := 305; end;
    with F.LvFiles.Columns.Add do begin Caption := 'Size'; Width := 85; end;
    with F.LvFiles.Columns.Add do begin Caption := 'Done'; Width := 85; end;
    with F.LvFiles.Columns.Add do begin Caption := '%'; Width := 60; end;
    with F.LvFiles.Columns.Add do begin Caption := 'Priority'; Width := 65; end;

    BtnSelAll := TButton.Create(F.TsFilesTab);
    BtnSelAll.Parent := F.TsFilesTab;
    BtnSelAll.Left := 8; BtnSelAll.Top := 346; BtnSelAll.Width := 68;
    BtnSelAll.Anchors := [akLeft, akBottom];
    BtnSelAll.Caption := 'All';
    BtnSelAll.OnClick := @F.BtnSelectAllFilesClick;

    BtnSelNone := TButton.Create(F.TsFilesTab);
    BtnSelNone.Parent := F.TsFilesTab;
    BtnSelNone.Left := 80; BtnSelNone.Top := 346; BtnSelNone.Width := 68;
    BtnSelNone.Anchors := [akLeft, akBottom];
    BtnSelNone.Caption := 'None';
    BtnSelNone.OnClick := @F.BtnSelectNoneFilesClick;

    BtnPriHigh := TButton.Create(F.TsFilesTab);
    BtnPriHigh.Parent := F.TsFilesTab;
    BtnPriHigh.Left := 156; BtnPriHigh.Top := 346; BtnPriHigh.Width := 72;
    BtnPriHigh.Anchors := [akLeft, akBottom];
    BtnPriHigh.Caption := 'Pri: High';
    BtnPriHigh.Tag := TR_PRI_HIGH;
    BtnPriHigh.OnClick := @F.BtnSetFilePriorityClick;

    BtnPriNorm := TButton.Create(F.TsFilesTab);
    BtnPriNorm.Parent := F.TsFilesTab;
    BtnPriNorm.Left := 232; BtnPriNorm.Top := 346; BtnPriNorm.Width := 76;
    BtnPriNorm.Anchors := [akLeft, akBottom];
    BtnPriNorm.Caption := 'Pri: Norm';
    BtnPriNorm.Tag := TR_PRI_NORMAL;
    BtnPriNorm.OnClick := @F.BtnSetFilePriorityClick;

    BtnPriLow := TButton.Create(F.TsFilesTab);
    BtnPriLow.Parent := F.TsFilesTab;
    BtnPriLow.Left := 312; BtnPriLow.Top := 346; BtnPriLow.Width := 72;
    BtnPriLow.Anchors := [akLeft, akBottom];
    BtnPriLow.Caption := 'Pri: Low';
    BtnPriLow.Tag := TR_PRI_LOW;
    BtnPriLow.OnClick := @F.BtnSetFilePriorityClick;

    BtnRename := TButton.Create(F.TsFilesTab);
    BtnRename.Parent := F.TsFilesTab;
    BtnRename.Left := 390; BtnRename.Top := 346; BtnRename.Width := 85;
    BtnRename.Anchors := [akLeft, akBottom];
    BtnRename.Caption := 'Rename...';
    BtnRename.OnClick := @F.BtnRenameFileClick;

    BtnSaveFiles := TButton.Create(F.TsFilesTab);
    BtnSaveFiles.Parent := F.TsFilesTab;
    BtnSaveFiles.Left := 485; BtnSaveFiles.Top := 346; BtnSaveFiles.Width := 145;
    BtnSaveFiles.Anchors := [akRight, akBottom];
    BtnSaveFiles.Caption := 'Apply Wanted Files';
    BtnSaveFiles.OnClick := @F.BtnApplyFilesClick;

    // Tab 6: Options
    TsOpts := PC.AddTabSheet;
    TsOpts.Caption := 'Options';

    F.ChkHonorSession := TCheckBox.Create(TsOpts);
    F.ChkHonorSession.Parent := TsOpts;
    F.ChkHonorSession.Left := 20; F.ChkHonorSession.Top := 20;
    F.ChkHonorSession.Caption := 'Honor global session bandwidth limits';
    F.ChkHonorSession.Checked := Torrent.HonorsSessionLimits;

    F.ChkDownLimit := TCheckBox.Create(TsOpts);
    F.ChkDownLimit.Parent := TsOpts;
    F.ChkDownLimit.Left := 20; F.ChkDownLimit.Top := 56;
    F.ChkDownLimit.Caption := 'Limit download speed (KB/s):';
    F.ChkDownLimit.Checked := Torrent.DownloadLimited;

    F.SpnDownLimit := TSpinEdit.Create(TsOpts);
    F.SpnDownLimit.Parent := TsOpts;
    F.SpnDownLimit.Left := 230; F.SpnDownLimit.Top := 52; F.SpnDownLimit.Width := 100;
    F.SpnDownLimit.MaxValue := 1000000;
    F.SpnDownLimit.Value := Torrent.DownloadLimit;

    F.ChkUpLimit := TCheckBox.Create(TsOpts);
    F.ChkUpLimit.Parent := TsOpts;
    F.ChkUpLimit.Left := 20; F.ChkUpLimit.Top := 92;
    F.ChkUpLimit.Caption := 'Limit upload speed (KB/s):';
    F.ChkUpLimit.Checked := Torrent.UploadLimited;

    F.SpnUpLimit := TSpinEdit.Create(TsOpts);
    F.SpnUpLimit.Parent := TsOpts;
    F.SpnUpLimit.Left := 230; F.SpnUpLimit.Top := 88; F.SpnUpLimit.Width := 100;
    F.SpnUpLimit.MaxValue := 1000000;
    F.SpnUpLimit.Value := Torrent.UploadLimit;

    Lbl := TLabel.Create(TsOpts);
    Lbl.Parent := TsOpts;
    Lbl.Left := 20; Lbl.Top := 134;
    Lbl.Caption := 'Seed ratio limit:';

    F.CmbRatioMode := TComboBox.Create(TsOpts);
    F.CmbRatioMode.Parent := TsOpts;
    F.CmbRatioMode.Left := 140; F.CmbRatioMode.Top := 130; F.CmbRatioMode.Width := 180;
    F.CmbRatioMode.Style := csDropDownList;
    F.CmbRatioMode.Items.Add('Use global settings');
    F.CmbRatioMode.Items.Add('Stop seeding at ratio:');
    F.CmbRatioMode.Items.Add('Seed regardless of ratio');
    if (Torrent.SeedRatioMode >= 0) and (Torrent.SeedRatioMode <= 2) then
      F.CmbRatioMode.ItemIndex := Torrent.SeedRatioMode
    else
      F.CmbRatioMode.ItemIndex := 0;

    F.EdtRatioLimit := TEdit.Create(TsOpts);
    F.EdtRatioLimit.Parent := TsOpts;
    F.EdtRatioLimit.Left := 330; F.EdtRatioLimit.Top := 130; F.EdtRatioLimit.Width := 80;
    F.EdtRatioLimit.Text := Format('%.2f', [Torrent.SeedRatioLimit]);

    Lbl := TLabel.Create(TsOpts);
    Lbl.Parent := TsOpts;
    Lbl.Left := 20; Lbl.Top := 174;
    Lbl.Caption := 'Maximum peers:';

    F.SpnPeerLimit := TSpinEdit.Create(TsOpts);
    F.SpnPeerLimit.Parent := TsOpts;
    F.SpnPeerLimit.Left := 140; F.SpnPeerLimit.Top := 170; F.SpnPeerLimit.Width := 100;
    F.SpnPeerLimit.MaxValue := 2000;
    F.SpnPeerLimit.Value := Torrent.PeerLimit;

    BtnApplyOpt := TButton.Create(TsOpts);
    BtnApplyOpt.Parent := TsOpts;
    BtnApplyOpt.Left := 20; BtnApplyOpt.Top := 220; BtnApplyOpt.Width := 130;
    BtnApplyOpt.Caption := 'Apply Options';
    BtnApplyOpt.OnClick := @F.BtnApplyOptionsClick;

    BtnClose := TButton.Create(F);
    BtnClose.Parent := F;
    BtnClose.Left := 550; BtnClose.Top := 418; BtnClose.Width := 88;
    BtnClose.Anchors := [akRight, akBottom];
    BtnClose.Caption := 'Close';
    BtnClose.Cancel := True;
    BtnClose.ModalResult := mrClose;

    F.UpdateDynamicViews;

    F.RefreshTimer := TTimer.Create(F);
    F.RefreshTimer.Interval := 2000;
    F.RefreshTimer.OnTimer := @F.RefreshTimerTick;
    F.RefreshTimer.Enabled := True;

    F.ShowModal;
  finally
    F.Free;
  end;
end;

{ 6. Change Session Dialog (matching SessionDialog.ui) }

type
  TSessionDlgForm = class(TForm)
  public
    RbLocal: TRadioButton;
    RbRemote: TRadioButton;
    EdtHost: TEdit;
    SpnPort: TSpinEdit;
    ChkAuth: TCheckBox;
    EdtUser: TEdit;
    EdtPass: TEdit;
    EdtRpcPath: TEdit;
    procedure UpdateControls(Sender: TObject);
  end;

procedure TSessionDlgForm.UpdateControls(Sender: TObject);
var
  Rem: Boolean;
begin
  Rem := RbRemote.Checked;
  EdtHost.Enabled := Rem;
  SpnPort.Enabled := True;
  ChkAuth.Enabled := Rem;
  EdtUser.Enabled := Rem and ChkAuth.Checked;
  EdtPass.Enabled := Rem and ChkAuth.Checked;
  EdtRpcPath.Enabled := Rem;
end;

function ShowSessionDialog(Owner: TComponent; Rpc: TTransmissionRpcClient): Boolean;
var
  F: TSessionDlgForm;
  Gb: TGroupBox;
  Lbl: TLabel;
  BtnOK, BtnCancel: TButton;
begin
  Result := False;
  F := TSessionDlgForm.CreateNew(Owner);
  try
    F.Caption := 'Change Session';
    F.Position := poMainFormCenter;
    F.BorderStyle := bsDialog;
    F.ClientWidth := 360;
    F.ClientHeight := 320;

    Gb := TGroupBox.Create(F);
    Gb.Parent := F;
    Gb.Left := 12; Gb.Top := 10; Gb.Width := 336; Gb.Height := 258;
    Gb.Caption := 'Source';

    F.RbLocal := TRadioButton.Create(Gb);
    F.RbLocal.Parent := Gb;
    F.RbLocal.Left := 14; F.RbLocal.Top := 12;
    F.RbLocal.Caption := 'Start Local Session';
    F.RbLocal.Checked := Rpc.IsLocalSession;
    F.RbLocal.OnChange := @F.UpdateControls;

    F.RbRemote := TRadioButton.Create(Gb);
    F.RbRemote.Parent := Gb;
    F.RbRemote.Left := 14; F.RbRemote.Top := 38;
    F.RbRemote.Caption := 'Connect to Remote Session';
    F.RbRemote.Checked := not Rpc.IsLocalSession;
    F.RbRemote.OnChange := @F.UpdateControls;

    Lbl := TLabel.Create(Gb);
    Lbl.Parent := Gb;
    Lbl.Left := 14; Lbl.Top := 72;
    Lbl.Caption := 'Host:';

    F.EdtHost := TEdit.Create(Gb);
    F.EdtHost.Parent := Gb;
    F.EdtHost.Left := 125; F.EdtHost.Top := 68; F.EdtHost.Width := 195;
    F.EdtHost.Text := Rpc.Host;

    Lbl := TLabel.Create(Gb);
    Lbl.Parent := Gb;
    Lbl.Left := 14; Lbl.Top := 104;
    Lbl.Caption := 'Port:';

    F.SpnPort := TSpinEdit.Create(Gb);
    F.SpnPort.Parent := Gb;
    F.SpnPort.Left := 125; F.SpnPort.Top := 100; F.SpnPort.Width := 100;
    F.SpnPort.MinValue := 1;
    F.SpnPort.MaxValue := 65535;
    F.SpnPort.Value := Rpc.Port;

    F.ChkAuth := TCheckBox.Create(Gb);
    F.ChkAuth.Parent := Gb;
    F.ChkAuth.Left := 14; F.ChkAuth.Top := 134;
    F.ChkAuth.Caption := 'Authentication required';
    F.ChkAuth.Checked := Rpc.Username <> '';
    F.ChkAuth.OnChange := @F.UpdateControls;

    Lbl := TLabel.Create(Gb);
    Lbl.Parent := Gb;
    Lbl.Left := 14; Lbl.Top := 164;
    Lbl.Caption := 'Username:';

    F.EdtUser := TEdit.Create(Gb);
    F.EdtUser.Parent := Gb;
    F.EdtUser.Left := 125; F.EdtUser.Top := 160; F.EdtUser.Width := 195;
    F.EdtUser.Text := Rpc.Username;

    Lbl := TLabel.Create(Gb);
    Lbl.Parent := Gb;
    Lbl.Left := 14; Lbl.Top := 194;
    Lbl.Caption := 'Password:';

    F.EdtPass := TEdit.Create(Gb);
    F.EdtPass.Parent := Gb;
    F.EdtPass.Left := 125; F.EdtPass.Top := 190; F.EdtPass.Width := 195;
    F.EdtPass.PasswordChar := '*';
    F.EdtPass.Text := Rpc.Password;

    Lbl := TLabel.Create(Gb);
    Lbl.Parent := Gb;
    Lbl.Left := 14; Lbl.Top := 224;
    Lbl.Caption := 'Remote path:';

    F.EdtRpcPath := TEdit.Create(Gb);
    F.EdtRpcPath.Parent := Gb;
    F.EdtRpcPath.Left := 125; F.EdtRpcPath.Top := 220; F.EdtRpcPath.Width := 195;
    F.EdtRpcPath.Text := Rpc.UrlPath;

    BtnOK := TButton.Create(F);
    BtnOK.Parent := F;
    BtnOK.Left := 180; BtnOK.Top := 280; BtnOK.Width := 80;
    BtnOK.Caption := 'OK';
    BtnOK.Default := True;
    BtnOK.ModalResult := mrOk;

    BtnCancel := TButton.Create(F);
    BtnCancel.Parent := F;
    BtnCancel.Left := 268; BtnCancel.Top := 280; BtnCancel.Width := 80;
    BtnCancel.Caption := 'Cancel';
    BtnCancel.Cancel := True;
    BtnCancel.ModalResult := mrCancel;

    F.UpdateControls(nil);

    if F.ShowModal = mrOk then
    begin
      if F.RbLocal.Checked then
        Rpc.Configure('127.0.0.1', F.SpnPort.Value, '', '', True, '/transmission/rpc')
      else if F.ChkAuth.Checked then
        Rpc.Configure(F.EdtHost.Text, F.SpnPort.Value, F.EdtUser.Text, F.EdtPass.Text, False, F.EdtRpcPath.Text)
      else
        Rpc.Configure(F.EdtHost.Text, F.SpnPort.Value, '', '', False, F.EdtRpcPath.Text);
      Rpc.EnsureLocalDaemonRunning;
      Result := True;
    end;
  finally
    F.Free;
  end;
end;

{ 7. Preferences Dialog }

type
  TPrefsForm = class(TForm)
  public
    RpcRef: TTransmissionRpcClient;
    WebSrvRef: TTransmissionWebServer;
    ChkUpLimit: TCheckBox;
    SpnUpLimit: TSpinEdit;
    ChkDownLimit: TCheckBox;
    SpnDownLimit: TSpinEdit;
    SpnAltUp: TSpinEdit;
    SpnAltDown: TSpinEdit;
    ChkAltEnabled: TCheckBox;

    EdtDownloadDir: TEdit;
    ChkStartAdded: TCheckBox;
    ChkRenamePartial: TCheckBox;
    ChkIncompleteDir: TCheckBox;
    EdtIncompleteDir: TEdit;
    ChkQueueDown: TCheckBox;
    SpnQueueDown: TSpinEdit;

    ChkRatioLimit: TCheckBox;
    EdtRatioLimit: TEdit;
    ChkIdleLimit: TCheckBox;
    SpnIdleLimit: TSpinEdit;

    CmbEncryption: TComboBox;
    ChkPex: TCheckBox;
    ChkDht: TCheckBox;
    ChkLpd: TCheckBox;
    ChkBlocklist: TCheckBox;
    EdtBlocklistUrl: TEdit;
    LblBlocklistRules: TLabel;

    SpnPeerPort: TSpinEdit;
    LblPortStatus: TLabel;
    ChkRandomPort: TCheckBox;
    ChkPortForwarding: TCheckBox;
    ChkUtp: TCheckBox;
    SpnPeerGlobal: TSpinEdit;
    SpnPeerPerTorrent: TSpinEdit;

    ChkWebEnabled: TCheckBox;
    SpnWebPort: TSpinEdit;
    ChkWebAuth: TCheckBox;
    EdtWebUser: TEdit;
    EdtWebPass: TEdit;

    procedure BtnBrowseSaveDirClick(Sender: TObject);
    procedure BtnTestPortClick(Sender: TObject);
    procedure BtnUpdateBlocklistClick(Sender: TObject);
    procedure BtnOpenWebClientClick(Sender: TObject);
  end;

procedure TPrefsForm.BtnBrowseSaveDirClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := EdtDownloadDir.Text;
  if SelectDirectory('Select Default Save Folder', '', Dir) then
    EdtDownloadDir.Text := Dir;
end;

procedure TPrefsForm.BtnTestPortClick(Sender: TObject);
var
  OpenOk: Boolean;
begin
  LblPortStatus.Caption := 'Testing...';
  Application.ProcessMessages;
  if RpcRef.TestPeerPort(OpenOk) then
  begin
    if OpenOk then
      LblPortStatus.Caption := 'Port is OPEN'
    else
      LblPortStatus.Caption := 'Port is CLOSED';
  end
  else
    LblPortStatus.Caption := 'Port test failed';
end;

procedure TPrefsForm.BtnUpdateBlocklistClick(Sender: TObject);
var
  Cnt: Integer;
begin
  LblBlocklistRules.Caption := 'Updating blocklist...';
  Application.ProcessMessages;
  if RpcRef.UpdateBlocklist(Cnt) then
    LblBlocklistRules.Caption := Format('Blocklist has %d rules', [Cnt])
  else
    LblBlocklistRules.Caption := 'Update failed: ' + RpcRef.LastError;
end;

procedure TPrefsForm.BtnOpenWebClientClick(Sender: TObject);
begin
  OpenURL(Format('http://127.0.0.1:%d/', [SpnWebPort.Value]));
end;

function ShowPrefsDialog(Owner: TComponent; Rpc: TTransmissionRpcClient;
  WebSrv: TTransmissionWebServer; var Config: TSessionConfig): Boolean;
var
  F: TPrefsForm;
  PC: TPageControl;
  TsSpeed, TsDown, TsSeed, TsPriv, TsNet, TsRemote: TTabSheet;
  Lbl: TLabel;
  BtnBrowse, BtnTestPort, BtnUpdBlk, BtnOpenWeb, BtnOK, BtnCancel: TButton;
  Args: TJSONObject;
begin
  Result := False;
  Rpc.FetchSession(Config);

  F := TPrefsForm.CreateNew(Owner);
  try
    F.RpcRef := Rpc;
    F.WebSrvRef := WebSrv;
    F.Caption := 'Transmission Preferences';
    F.Position := poMainFormCenter;
    F.BorderStyle := bsDialog;
    F.ClientWidth := 500;
    F.ClientHeight := 370;

    PC := TPageControl.Create(F);
    PC.Parent := F;
    PC.Left := 8; PC.Top := 8; PC.Width := 484; PC.Height := 312;

    // 1. Speed Tab
    TsSpeed := PC.AddTabSheet;
    TsSpeed.Caption := 'Speed';

    Lbl := TLabel.Create(TsSpeed);
    Lbl.Parent := TsSpeed;
    Lbl.Left := 16; Lbl.Top := 16;
    Lbl.Font.Style := [fsBold];
    Lbl.Caption := 'Speed Limits';

    F.ChkUpLimit := TCheckBox.Create(TsSpeed);
    F.ChkUpLimit.Parent := TsSpeed;
    F.ChkUpLimit.Left := 24; F.ChkUpLimit.Top := 44;
    F.ChkUpLimit.Caption := 'Upload (KB/s):';
    F.ChkUpLimit.Checked := Config.SpeedLimitUpEnabled;

    F.SpnUpLimit := TSpinEdit.Create(TsSpeed);
    F.SpnUpLimit.Parent := TsSpeed;
    F.SpnUpLimit.Left := 180; F.SpnUpLimit.Top := 40; F.SpnUpLimit.Width := 100;
    F.SpnUpLimit.MaxValue := 1000000;
    F.SpnUpLimit.Value := Config.SpeedLimitUp;

    F.ChkDownLimit := TCheckBox.Create(TsSpeed);
    F.ChkDownLimit.Parent := TsSpeed;
    F.ChkDownLimit.Left := 24; F.ChkDownLimit.Top := 78;
    F.ChkDownLimit.Caption := 'Download (KB/s):';
    F.ChkDownLimit.Checked := Config.SpeedLimitDownEnabled;

    F.SpnDownLimit := TSpinEdit.Create(TsSpeed);
    F.SpnDownLimit.Parent := TsSpeed;
    F.SpnDownLimit.Left := 180; F.SpnDownLimit.Top := 74; F.SpnDownLimit.Width := 100;
    F.SpnDownLimit.MaxValue := 1000000;
    F.SpnDownLimit.Value := Config.SpeedLimitDown;

    Lbl := TLabel.Create(TsSpeed);
    Lbl.Parent := TsSpeed;
    Lbl.Left := 16; Lbl.Top := 124;
    Lbl.Font.Style := [fsBold];
    Lbl.Caption := 'Alternative Speed Limits (Turtle Mode)';

    F.ChkAltEnabled := TCheckBox.Create(TsSpeed);
    F.ChkAltEnabled.Parent := TsSpeed;
    F.ChkAltEnabled.Left := 24; F.ChkAltEnabled.Top := 150;
    F.ChkAltEnabled.Caption := 'Enable Alternative Speed Limits now';
    F.ChkAltEnabled.Checked := Config.AltSpeedEnabled;

    Lbl := TLabel.Create(TsSpeed);
    Lbl.Parent := TsSpeed;
    Lbl.Left := 24; Lbl.Top := 184;
    Lbl.Caption := 'Alt Upload (KB/s):';

    F.SpnAltUp := TSpinEdit.Create(TsSpeed);
    F.SpnAltUp.Parent := TsSpeed;
    F.SpnAltUp.Left := 180; F.SpnAltUp.Top := 180; F.SpnAltUp.Width := 100;
    F.SpnAltUp.MaxValue := 1000000;
    F.SpnAltUp.Value := Config.AltSpeedUp;

    Lbl := TLabel.Create(TsSpeed);
    Lbl.Parent := TsSpeed;
    Lbl.Left := 24; Lbl.Top := 218;
    Lbl.Caption := 'Alt Download (KB/s):';

    F.SpnAltDown := TSpinEdit.Create(TsSpeed);
    F.SpnAltDown.Parent := TsSpeed;
    F.SpnAltDown.Left := 180; F.SpnAltDown.Top := 214; F.SpnAltDown.Width := 100;
    F.SpnAltDown.MaxValue := 1000000;
    F.SpnAltDown.Value := Config.AltSpeedDown;

    // 2. Downloading Tab
    TsDown := PC.AddTabSheet;
    TsDown.Caption := 'Downloading';

    Lbl := TLabel.Create(TsDown);
    Lbl.Parent := TsDown;
    Lbl.Left := 16; Lbl.Top := 16;
    Lbl.Caption := 'Save to Location:';

    F.EdtDownloadDir := TEdit.Create(TsDown);
    F.EdtDownloadDir.Parent := TsDown;
    F.EdtDownloadDir.Left := 16; F.EdtDownloadDir.Top := 36; F.EdtDownloadDir.Width := 355;
    F.EdtDownloadDir.Text := Config.DownloadDir;

    BtnBrowse := TButton.Create(TsDown);
    BtnBrowse.Parent := TsDown;
    BtnBrowse.Left := 380; BtnBrowse.Top := 34; BtnBrowse.Width := 80;
    BtnBrowse.Caption := 'Browse...';
    BtnBrowse.OnClick := @F.BtnBrowseSaveDirClick;

    F.ChkStartAdded := TCheckBox.Create(TsDown);
    F.ChkStartAdded.Parent := TsDown;
    F.ChkStartAdded.Left := 16; F.ChkStartAdded.Top := 72;
    F.ChkStartAdded.Caption := 'Start added torrents immediately';
    F.ChkStartAdded.Checked := Config.StartAddedTorrents;

    F.ChkRenamePartial := TCheckBox.Create(TsDown);
    F.ChkRenamePartial.Parent := TsDown;
    F.ChkRenamePartial.Left := 16; F.ChkRenamePartial.Top := 100;
    F.ChkRenamePartial.Caption := 'Append ".part" to incomplete files'' names';
    F.ChkRenamePartial.Checked := Config.RenamePartialFiles;

    F.ChkIncompleteDir := TCheckBox.Create(TsDown);
    F.ChkIncompleteDir.Parent := TsDown;
    F.ChkIncompleteDir.Left := 16; F.ChkIncompleteDir.Top := 130;
    F.ChkIncompleteDir.Caption := 'Keep incomplete torrents in:';
    F.ChkIncompleteDir.Checked := Config.IncompleteDirEnabled;

    F.EdtIncompleteDir := TEdit.Create(TsDown);
    F.EdtIncompleteDir.Parent := TsDown;
    F.EdtIncompleteDir.Left := 16; F.EdtIncompleteDir.Top := 154; F.EdtIncompleteDir.Width := 444;
    F.EdtIncompleteDir.Text := Config.IncompleteDir;

    F.ChkQueueDown := TCheckBox.Create(TsDown);
    F.ChkQueueDown.Parent := TsDown;
    F.ChkQueueDown.Left := 16; F.ChkQueueDown.Top := 196;
    F.ChkQueueDown.Caption := 'Maximum active downloads:';
    F.ChkQueueDown.Checked := Config.DownloadQueueEnabled;

    F.SpnQueueDown := TSpinEdit.Create(TsDown);
    F.SpnQueueDown.Parent := TsDown;
    F.SpnQueueDown.Left := 220; F.SpnQueueDown.Top := 192; F.SpnQueueDown.Width := 80;
    F.SpnQueueDown.MinValue := 1;
    F.SpnQueueDown.MaxValue := 100;
    F.SpnQueueDown.Value := Config.DownloadQueueSize;

    // 3. Seeding Tab
    TsSeed := PC.AddTabSheet;
    TsSeed.Caption := 'Seeding';

    F.ChkRatioLimit := TCheckBox.Create(TsSeed);
    F.ChkRatioLimit.Parent := TsSeed;
    F.ChkRatioLimit.Left := 20; F.ChkRatioLimit.Top := 28;
    F.ChkRatioLimit.Caption := 'Stop seeding at ratio:';
    F.ChkRatioLimit.Checked := Config.SeedRatioLimited;

    F.EdtRatioLimit := TEdit.Create(TsSeed);
    F.EdtRatioLimit.Parent := TsSeed;
    F.EdtRatioLimit.Left := 210; F.EdtRatioLimit.Top := 24; F.EdtRatioLimit.Width := 80;
    F.EdtRatioLimit.Text := Format('%.2f', [Config.SeedRatioLimit]);

    F.ChkIdleLimit := TCheckBox.Create(TsSeed);
    F.ChkIdleLimit.Parent := TsSeed;
    F.ChkIdleLimit.Left := 20; F.ChkIdleLimit.Top := 68;
    F.ChkIdleLimit.Caption := 'Stop seeding if idle for (minutes):';
    F.ChkIdleLimit.Checked := Config.IdleSeedingLimited;

    F.SpnIdleLimit := TSpinEdit.Create(TsSeed);
    F.SpnIdleLimit.Parent := TsSeed;
    F.SpnIdleLimit.Left := 250; F.SpnIdleLimit.Top := 64; F.SpnIdleLimit.Width := 80;
    F.SpnIdleLimit.MaxValue := 99999;
    F.SpnIdleLimit.Value := Config.IdleSeedingLimit;

    // 4. Privacy Tab
    TsPriv := PC.AddTabSheet;
    TsPriv.Caption := 'Privacy';

    Lbl := TLabel.Create(TsPriv);
    Lbl.Parent := TsPriv;
    Lbl.Left := 16; Lbl.Top := 20;
    Lbl.Caption := 'Encryption mode:';

    F.CmbEncryption := TComboBox.Create(TsPriv);
    F.CmbEncryption.Parent := TsPriv;
    F.CmbEncryption.Left := 140; F.CmbEncryption.Top := 16; F.CmbEncryption.Width := 180;
    F.CmbEncryption.Style := csDropDownList;
    F.CmbEncryption.Items.Add('Allow encryption');
    F.CmbEncryption.Items.Add('Prefer encryption');
    F.CmbEncryption.Items.Add('Require encryption');
    if Config.Encryption = 'required' then
      F.CmbEncryption.ItemIndex := 2
    else if Config.Encryption = 'tolerated' then
      F.CmbEncryption.ItemIndex := 0
    else
      F.CmbEncryption.ItemIndex := 1;

    F.ChkPex := TCheckBox.Create(TsPriv);
    F.ChkPex.Parent := TsPriv;
    F.ChkPex.Left := 16; F.ChkPex.Top := 56;
    F.ChkPex.Caption := 'Use Peer Exchange (PEX) for public torrents';
    F.ChkPex.Checked := Config.PexEnabled;

    F.ChkDht := TCheckBox.Create(TsPriv);
    F.ChkDht.Parent := TsPriv;
    F.ChkDht.Left := 16; F.ChkDht.Top := 82;
    F.ChkDht.Caption := 'Use Distributed Hash Table (DHT) for public torrents';
    F.ChkDht.Checked := Config.DhtEnabled;

    F.ChkLpd := TCheckBox.Create(TsPriv);
    F.ChkLpd.Parent := TsPriv;
    F.ChkLpd.Left := 16; F.ChkLpd.Top := 108;
    F.ChkLpd.Caption := 'Use Local Peer Discovery (LPD) for public torrents';
    F.ChkLpd.Checked := Config.LpdEnabled;

    F.ChkBlocklist := TCheckBox.Create(TsPriv);
    F.ChkBlocklist.Parent := TsPriv;
    F.ChkBlocklist.Left := 16; F.ChkBlocklist.Top := 146;
    F.ChkBlocklist.Caption := 'Enable blocklist URL:';
    F.ChkBlocklist.Checked := Config.BlocklistEnabled;

    F.EdtBlocklistUrl := TEdit.Create(TsPriv);
    F.EdtBlocklistUrl.Parent := TsPriv;
    F.EdtBlocklistUrl.Left := 16; F.EdtBlocklistUrl.Top := 170; F.EdtBlocklistUrl.Width := 440;
    F.EdtBlocklistUrl.Text := Config.BlocklistUrl;

    F.LblBlocklistRules := TLabel.Create(TsPriv);
    F.LblBlocklistRules.Parent := TsPriv;
    F.LblBlocklistRules.Left := 16; F.LblBlocklistRules.Top := 204;
    F.LblBlocklistRules.Caption := Format('Blocklist has %d rules', [Config.BlocklistSize]);

    BtnUpdBlk := TButton.Create(TsPriv);
    BtnUpdBlk.Parent := TsPriv;
    BtnUpdBlk.Left := 346; BtnUpdBlk.Top := 200; BtnUpdBlk.Width := 110;
    BtnUpdBlk.Caption := 'Update Blocklist';
    BtnUpdBlk.OnClick := @F.BtnUpdateBlocklistClick;

    // 5. Network Tab
    TsNet := PC.AddTabSheet;
    TsNet.Caption := 'Network';

    Lbl := TLabel.Create(TsNet);
    Lbl.Parent := TsNet;
    Lbl.Left := 16; Lbl.Top := 22;
    Lbl.Caption := 'Peer listening port:';

    F.SpnPeerPort := TSpinEdit.Create(TsNet);
    F.SpnPeerPort.Parent := TsNet;
    F.SpnPeerPort.Left := 165; F.SpnPeerPort.Top := 18; F.SpnPeerPort.Width := 90;
    F.SpnPeerPort.MinValue := 1;
    F.SpnPeerPort.MaxValue := 65535;
    F.SpnPeerPort.Value := Config.PeerPort;

    BtnTestPort := TButton.Create(TsNet);
    BtnTestPort.Parent := TsNet;
    BtnTestPort.Left := 268; BtnTestPort.Top := 17; BtnTestPort.Width := 90;
    BtnTestPort.Caption := 'Test Port';
    BtnTestPort.OnClick := @F.BtnTestPortClick;

    F.LblPortStatus := TLabel.Create(TsNet);
    F.LblPortStatus.Parent := TsNet;
    F.LblPortStatus.Left := 370; F.LblPortStatus.Top := 22;
    F.LblPortStatus.Font.Style := [fsBold];
    F.LblPortStatus.Caption := '';

    F.ChkRandomPort := TCheckBox.Create(TsNet);
    F.ChkRandomPort.Parent := TsNet;
    F.ChkRandomPort.Left := 16; F.ChkRandomPort.Top := 54;
    F.ChkRandomPort.Caption := 'Pick a random port every time Transmission is started';
    F.ChkRandomPort.Checked := Config.PeerPortRandomOnStart;

    F.ChkPortForwarding := TCheckBox.Create(TsNet);
    F.ChkPortForwarding.Parent := TsNet;
    F.ChkPortForwarding.Left := 16; F.ChkPortForwarding.Top := 82;
    F.ChkPortForwarding.Caption := 'Use UPnP or NAT-PMP port forwarding from my router';
    F.ChkPortForwarding.Checked := Config.PortForwardingEnabled;

    F.ChkUtp := TCheckBox.Create(TsNet);
    F.ChkUtp.Parent := TsNet;
    F.ChkUtp.Left := 16; F.ChkUtp.Top := 110;
    F.ChkUtp.Caption := 'Enable µTP for peer communication';
    F.ChkUtp.Checked := Config.UtpEnabled;

    Lbl := TLabel.Create(TsNet);
    Lbl.Parent := TsNet;
    Lbl.Left := 16; Lbl.Top := 152;
    Lbl.Caption := 'Max peers per torrent:';

    F.SpnPeerPerTorrent := TSpinEdit.Create(TsNet);
    F.SpnPeerPerTorrent.Parent := TsNet;
    F.SpnPeerPerTorrent.Left := 165; F.SpnPeerPerTorrent.Top := 148; F.SpnPeerPerTorrent.Width := 90;
    F.SpnPeerPerTorrent.MinValue := 1;
    F.SpnPeerPerTorrent.MaxValue := 2000;
    F.SpnPeerPerTorrent.Value := Config.PeerLimitPerTorrent;

    Lbl := TLabel.Create(TsNet);
    Lbl.Parent := TsNet;
    Lbl.Left := 16; Lbl.Top := 188;
    Lbl.Caption := 'Max peers overall:';

    F.SpnPeerGlobal := TSpinEdit.Create(TsNet);
    F.SpnPeerGlobal.Parent := TsNet;
    F.SpnPeerGlobal.Left := 165; F.SpnPeerGlobal.Top := 184; F.SpnPeerGlobal.Width := 90;
    F.SpnPeerGlobal.MinValue := 1;
    F.SpnPeerGlobal.MaxValue := 5000;
    F.SpnPeerGlobal.Value := Config.PeerLimitGlobal;

    // 6. Remote / Web UI Tab (matching PrefsDialog.ui Remote tab)
    TsRemote := PC.AddTabSheet;
    TsRemote.Caption := 'Remote / Web';

    F.ChkWebEnabled := TCheckBox.Create(TsRemote);
    F.ChkWebEnabled.Parent := TsRemote;
    F.ChkWebEnabled.Left := 16; F.ChkWebEnabled.Top := 20;
    F.ChkWebEnabled.Caption := 'Allow remote web access (Built-in Web UI Server)';
    if WebSrv <> nil then
      F.ChkWebEnabled.Checked := WebSrv.Enabled
    else
      F.ChkWebEnabled.Checked := True;

    Lbl := TLabel.Create(TsRemote);
    Lbl.Parent := TsRemote;
    Lbl.Left := 36; Lbl.Top := 56;
    Lbl.Caption := 'HTTP Port:';

    F.SpnWebPort := TSpinEdit.Create(TsRemote);
    F.SpnWebPort.Parent := TsRemote;
    F.SpnWebPort.Left := 140; F.SpnWebPort.Top := 52; F.SpnWebPort.Width := 95;
    F.SpnWebPort.MinValue := 1;
    F.SpnWebPort.MaxValue := 65535;
    if WebSrv <> nil then
      F.SpnWebPort.Value := WebSrv.Port
    else
      F.SpnWebPort.Value := 9092;

    BtnOpenWeb := TButton.Create(TsRemote);
    BtnOpenWeb.Parent := TsRemote;
    BtnOpenWeb.Left := 252; BtnOpenWeb.Top := 50; BtnOpenWeb.Width := 145;
    BtnOpenWeb.Caption := 'Open Web Client';
    BtnOpenWeb.OnClick := @F.BtnOpenWebClientClick;

    F.ChkWebAuth := TCheckBox.Create(TsRemote);
    F.ChkWebAuth.Parent := TsRemote;
    F.ChkWebAuth.Left := 16; F.ChkWebAuth.Top := 96;
    F.ChkWebAuth.Caption := 'Use HTTP authentication';
    if WebSrv <> nil then
      F.ChkWebAuth.Checked := WebSrv.AuthEnabled
    else
      F.ChkWebAuth.Checked := False;

    Lbl := TLabel.Create(TsRemote);
    Lbl.Parent := TsRemote;
    Lbl.Left := 36; Lbl.Top := 132;
    Lbl.Caption := 'Username:';

    F.EdtWebUser := TEdit.Create(TsRemote);
    F.EdtWebUser.Parent := TsRemote;
    F.EdtWebUser.Left := 140; F.EdtWebUser.Top := 128; F.EdtWebUser.Width := 190;
    if WebSrv <> nil then
      F.EdtWebUser.Text := WebSrv.Username
    else
      F.EdtWebUser.Text := 'admin';

    Lbl := TLabel.Create(TsRemote);
    Lbl.Parent := TsRemote;
    Lbl.Left := 36; Lbl.Top := 168;
    Lbl.Caption := 'Password:';

    F.EdtWebPass := TEdit.Create(TsRemote);
    F.EdtWebPass.Parent := TsRemote;
    F.EdtWebPass.Left := 140; F.EdtWebPass.Top := 164; F.EdtWebPass.Width := 190;
    F.EdtWebPass.PasswordChar := '*';
    if WebSrv <> nil then
      F.EdtWebPass.Text := WebSrv.Password;

    BtnOK := TButton.Create(F);
    BtnOK.Parent := F;
    BtnOK.Left := 324; BtnOK.Top := 330; BtnOK.Width := 80;
    BtnOK.Caption := 'OK';
    BtnOK.Default := True;
    BtnOK.ModalResult := mrOk;

    BtnCancel := TButton.Create(F);
    BtnCancel.Parent := F;
    BtnCancel.Left := 412; BtnCancel.Top := 330; BtnCancel.Width := 80;
    BtnCancel.Caption := 'Cancel';
    BtnCancel.Cancel := True;
    BtnCancel.ModalResult := mrCancel;

    if F.ShowModal = mrOk then
    begin
      Args := TJSONObject.Create;
      Args.Add('speed-limit-up-enabled', F.ChkUpLimit.Checked);
      Args.Add('speed-limit-up', F.SpnUpLimit.Value);
      Args.Add('speed-limit-down-enabled', F.ChkDownLimit.Checked);
      Args.Add('speed-limit-down', F.SpnDownLimit.Value);
      Args.Add('alt-speed-enabled', F.ChkAltEnabled.Checked);
      Args.Add('alt-speed-up', F.SpnAltUp.Value);
      Args.Add('alt-speed-down', F.SpnAltDown.Value);
      Args.Add('download-dir', StringReplace(F.EdtDownloadDir.Text, '\', '/', [rfReplaceAll]));
      Args.Add('start-added-torrents', F.ChkStartAdded.Checked);
      Args.Add('rename-partial-files', F.ChkRenamePartial.Checked);
      Args.Add('incomplete-dir-enabled', F.ChkIncompleteDir.Checked);
      Args.Add('incomplete-dir', StringReplace(F.EdtIncompleteDir.Text, '\', '/', [rfReplaceAll]));
      Args.Add('download-queue-enabled', F.ChkQueueDown.Checked);
      Args.Add('download-queue-size', F.SpnQueueDown.Value);
      Args.Add('seedRatioLimited', F.ChkRatioLimit.Checked);
      Args.Add('seedRatioLimit', StrToFloatDef(F.EdtRatioLimit.Text, 2.0));
      Args.Add('idle-seeding-limit-enabled', F.ChkIdleLimit.Checked);
      Args.Add('idle-seeding-limit', F.SpnIdleLimit.Value);
      case F.CmbEncryption.ItemIndex of
        0: Args.Add('encryption', 'tolerated');
        2: Args.Add('encryption', 'required');
      else
        Args.Add('encryption', 'preferred');
      end;
      Args.Add('pex-enabled', F.ChkPex.Checked);
      Args.Add('dht-enabled', F.ChkDht.Checked);
      Args.Add('lpd-enabled', F.ChkLpd.Checked);
      Args.Add('blocklist-enabled', F.ChkBlocklist.Checked);
      Args.Add('blocklist-url', F.EdtBlocklistUrl.Text);
      Args.Add('peer-port', F.SpnPeerPort.Value);
      Args.Add('peer-port-random-on-start', F.ChkRandomPort.Checked);
      Args.Add('port-forwarding-enabled', F.ChkPortForwarding.Checked);
      Args.Add('utp-enabled', F.ChkUtp.Checked);
      Args.Add('peer-limit-per-torrent', F.SpnPeerPerTorrent.Value);
      Args.Add('peer-limit-global', F.SpnPeerGlobal.Value);

      Rpc.UpdateSession(Args);
      Rpc.FetchSession(Config);

      if WebSrv <> nil then
      begin
        WebSrv.Enabled := F.ChkWebEnabled.Checked;
        WebSrv.Port := F.SpnWebPort.Value;
        WebSrv.AuthEnabled := F.ChkWebAuth.Checked;
        WebSrv.Username := Trim(F.EdtWebUser.Text);
        WebSrv.Password := F.EdtWebPass.Text;
        WebSrv.RestartServer;
      end;

      Result := True;
    end;
  finally
    F.Free;
  end;
end;

{ 8. Set Location / Relocate Dialog }

type
  TRelocateForm = class(TForm)
  public
    EdtDir: TEdit;
    RbMove: TRadioButton;
    RbFind: TRadioButton;
    procedure BtnBrowseClick(Sender: TObject);
  end;

procedure TRelocateForm.BtnBrowseClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := EdtDir.Text;
  if SelectDirectory('Select New Torrent Location', '', Dir) then
    EdtDir.Text := Dir;
end;

function ShowRelocateDialog(Owner: TComponent; const CurrentDir: string;
  out NewDir: string; out MoveData: Boolean): Boolean;
var
  F: TRelocateForm;
  Lbl: TLabel;
  BtnBrowse, BtnOK, BtnCancel: TButton;
begin
  Result := False;
  F := TRelocateForm.CreateNew(Owner);
  try
    F.Caption := 'Set Torrent Location';
    F.Position := poMainFormCenter;
    F.BorderStyle := bsDialog;
    F.ClientWidth := 460;
    F.ClientHeight := 180;

    Lbl := TLabel.Create(F);
    Lbl.Parent := F;
    Lbl.Left := 16; Lbl.Top := 16;
    Lbl.Caption := 'New location:';

    F.EdtDir := TEdit.Create(F);
    F.EdtDir.Parent := F;
    F.EdtDir.Left := 16; F.EdtDir.Top := 36; F.EdtDir.Width := 340;
    F.EdtDir.Text := CurrentDir;

    BtnBrowse := TButton.Create(F);
    BtnBrowse.Parent := F;
    BtnBrowse.Left := 364; BtnBrowse.Top := 34; BtnBrowse.Width := 80;
    BtnBrowse.Caption := 'Browse...';
    BtnBrowse.OnClick := @F.BtnBrowseClick;

    F.RbMove := TRadioButton.Create(F);
    F.RbMove.Parent := F;
    F.RbMove.Left := 16; F.RbMove.Top := 76;
    F.RbMove.Caption := 'Move data from current folder to new folder';
    F.RbMove.Checked := True;

    F.RbFind := TRadioButton.Create(F);
    F.RbFind.Parent := F;
    F.RbFind.Left := 16; F.RbFind.Top := 102;
    F.RbFind.Caption := 'Local data is already in the new folder';

    BtnOK := TButton.Create(F);
    BtnOK.Parent := F;
    BtnOK.Left := 276; BtnOK.Top := 138; BtnOK.Width := 80;
    BtnOK.Caption := 'Apply';
    BtnOK.Default := True;
    BtnOK.ModalResult := mrOk;

    BtnCancel := TButton.Create(F);
    BtnCancel.Parent := F;
    BtnCancel.Left := 364; BtnCancel.Top := 138; BtnCancel.Width := 80;
    BtnCancel.Caption := 'Cancel';
    BtnCancel.Cancel := True;
    BtnCancel.ModalResult := mrCancel;

    if F.ShowModal = mrOk then
    begin
      NewDir := Trim(F.EdtDir.Text);
      MoveData := F.RbMove.Checked;
      Result := NewDir <> '';
    end;
  finally
    F.Free;
  end;
end;

{ 9. Statistics Dialog (with Live Auto-Refresh) }

type
  TStatsForm = class(TForm)
  public
    RpcRef: TTransmissionRpcClient;
    RefreshTimer: TTimer;
    GbTot: TGroupBox;
    LblCurUp, LblCurDown, LblCurRatio, LblCurDur: TLabel;
    LblTotUp, LblTotDown, LblTotRatio, LblTotDur: TLabel;
    procedure RefreshStats;
    procedure RefreshTimerTick(Sender: TObject);
  end;

procedure TStatsForm.RefreshStats;
var
  Stats: TSessionStatsData;
  CurRatio, TotRatio: Double;
begin
  if (RpcRef = nil) or not RpcRef.FetchSessionStats(Stats) then Exit;

  if Stats.CurrentDownloadedBytes > 0 then
    CurRatio := Stats.CurrentUploadedBytes / Stats.CurrentDownloadedBytes
  else
    CurRatio := 0.0;

  if Stats.TotalDownloadedBytes > 0 then
    TotRatio := Stats.TotalUploadedBytes / Stats.TotalDownloadedBytes
  else
    TotRatio := 0.0;

  LblCurUp.Caption := FormatSize(Stats.CurrentUploadedBytes);
  LblCurDown.Caption := FormatSize(Stats.CurrentDownloadedBytes);
  LblCurRatio.Caption := FormatRatio(CurRatio);
  LblCurDur.Caption := FormatDuration(Stats.CurrentSecondsActive);

  GbTot.Caption := Format('Total (Started %d times)', [Stats.TotalSessionCount]);
  LblTotUp.Caption := FormatSize(Stats.TotalUploadedBytes);
  LblTotDown.Caption := FormatSize(Stats.TotalDownloadedBytes);
  LblTotRatio.Caption := FormatRatio(TotRatio);
  LblTotDur.Caption := FormatDuration(Stats.TotalSecondsActive);
end;

procedure TStatsForm.RefreshTimerTick(Sender: TObject);
begin
  RefreshStats;
end;

procedure ShowStatsDialog(Owner: TComponent; Rpc: TTransmissionRpcClient);
var
  F: TStatsForm;
  GbCur: TGroupBox;
  BtnClose: TButton;
begin
  F := TStatsForm.CreateNew(Owner);
  try
    F.RpcRef := Rpc;
    F.Caption := 'Statistics';
    F.Position := poMainFormCenter;
    F.BorderStyle := bsDialog;
    F.ClientWidth := 420;
    F.ClientHeight := 340;

    GbCur := TGroupBox.Create(F);
    GbCur.Parent := F;
    GbCur.Left := 14; GbCur.Top := 12; GbCur.Width := 392; GbCur.Height := 132;
    GbCur.Caption := 'Current Session';

    F.LblCurUp := CreateKeyValLabel(GbCur, 10, 'Uploaded:', '0 B');
    F.LblCurDown := CreateKeyValLabel(GbCur, 34, 'Downloaded:', '0 B');
    F.LblCurRatio := CreateKeyValLabel(GbCur, 58, 'Ratio:', '0.00');
    F.LblCurDur := CreateKeyValLabel(GbCur, 82, 'Duration:', '0s');

    F.GbTot := TGroupBox.Create(F);
    F.GbTot.Parent := F;
    F.GbTot.Left := 14; F.GbTot.Top := 154; F.GbTot.Width := 392; F.GbTot.Height := 136;
    F.GbTot.Caption := 'Total';

    F.LblTotUp := CreateKeyValLabel(F.GbTot, 10, 'Uploaded:', '0 B');
    F.LblTotDown := CreateKeyValLabel(F.GbTot, 34, 'Downloaded:', '0 B');
    F.LblTotRatio := CreateKeyValLabel(F.GbTot, 58, 'Ratio:', '0.00');
    F.LblTotDur := CreateKeyValLabel(F.GbTot, 82, 'Total Duration:', '0s');

    BtnClose := TButton.Create(F);
    BtnClose.Parent := F;
    BtnClose.Left := 326; BtnClose.Top := 298; BtnClose.Width := 80;
    BtnClose.Caption := 'Close';
    BtnClose.Default := True;
    BtnClose.Cancel := True;
    BtnClose.ModalResult := mrClose;

    F.RefreshStats;

    F.RefreshTimer := TTimer.Create(F);
    F.RefreshTimer.Interval := 2000;
    F.RefreshTimer.OnTimer := @F.RefreshTimerTick;
    F.RefreshTimer.Enabled := True;

    F.ShowModal;
  finally
    F.Free;
  end;
end;

end.
