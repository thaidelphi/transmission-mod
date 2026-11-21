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
  Classes, SysUtils, Types, Math, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ComCtrls, Spin, Clipbrd, LCLType, LCLIntf, fpjson, DateUtils, uTypes, uBencode, uRpcClient, uWebServer;

type
  { TDetailsPanel: พาเนลแสดงและแก้ไขคุณสมบัติทอร์เรนต์ 6 แท็บ ใช้ร่วมกันได้ทั้งในหน้าต่างหลักด้านล่างและ Modal Dialog }
  TDetailsPanel = class(TPanel)
  private
    FRpc: TTransmissionRpcClient;
    FOwnedTorrent: TTorrentItem;
    FCurrentId: Integer;
    FOnDataChanged: TNotifyEvent;
    FOnModalStart: TNotifyEvent;
    FOnModalEnd: TNotifyEvent;

    FPageControl: TPageControl;

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

    // Information dynamic labels
    LblInfoSizeVal: TLabel;
    LblInfoHashVal: TLabel;
    LblInfoTypeVal: TLabel;
    LblInfoLocVal: TLabel;
    LblInfoCreatorVal: TLabel;
    LblInfoAddedVal: TLabel;
    LblInfoDoneVal: TLabel;
    LblInfoCommentVal: TLabel;

    TsPeersTab: TTabSheet;
    TsTrackersTab: TTabSheet;
    TsFilesTab: TTabSheet;
    LvPeers: TListView;
    LvTrackers: TListView;
    LvFiles: TListView;
    BtnBlockTrkPackets: TButton;
    ChkAutoPauseTrk: TCheckBox;
    FSyncingTrkChk: Boolean;
    FGlobalTrackerPaused: Boolean;
    FOnRequestGlobalTrackerUnpause: TNotifyEvent;

    ChkHonorSession: TCheckBox;
    ChkDownLimit: TCheckBox;
    SpnDownLimit: TSpinEdit;
    ChkUpLimit: TCheckBox;
    SpnUpLimit: TSpinEdit;
    CmbRatioMode: TComboBox;
    EdtRatioLimit: TEdit;
    SpnPeerLimit: TSpinEdit;

    // Speed Graph Tab
    TsSpeedGraphTab: TTabSheet;
    RbGraphTorrent: TRadioButton;
    RbGraphGlobal: TRadioButton;
    LblGraphStats: TLabel;
    PbSpeedGraph: TPaintBox;
    FGlobalDownHist: array of Int64;
    FGlobalUpHist: array of Int64;
    FTorrentDownHist: array of Int64;
    FTorrentUpHist: array of Int64;

    procedure BuildTabs;
    procedure NotifyModalStart;
    procedure NotifyModalEnd;
    procedure NotifyDataChanged;
    procedure SyncOptionsAndInfo;
    procedure UpdateDynamicViews;
    procedure UpdateGraphStatsLabel;
    procedure PbSpeedGraphPaint(Sender: TObject);
    procedure GraphSourceChange(Sender: TObject);
    procedure BtnGraphClearClick(Sender: TObject);

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
    procedure BtnBlockTrkPacketsClick(Sender: TObject);
    procedure ChkAutoPauseTrkClick(Sender: TObject);
    procedure SetGlobalTrackerPaused(AValue: Boolean);
  public
    constructor CreatePanel(AOwner: TComponent; ARpc: TTransmissionRpcClient);
    destructor Destroy; override;

    procedure LoadTorrent(ATorrentId: Integer);
    procedure RefreshDetails;
    procedure RecordGlobalSpeed(DownRate, UpRate: Int64);
    function IsTrackerPaused: Boolean;
    procedure SetUnifiedPausedState(APaused: Boolean);

    property CurrentTorrentId: Integer read FCurrentId;
    property GlobalTrackerPaused: Boolean read FGlobalTrackerPaused write SetGlobalTrackerPaused;
    property PageControl: TPageControl read FPageControl;
    property OnDataChanged: TNotifyEvent read FOnDataChanged write FOnDataChanged;
    property OnModalStart: TNotifyEvent read FOnModalStart write FOnModalStart;
    property OnModalEnd: TNotifyEvent read FOnModalEnd write FOnModalEnd;
    property OnRequestGlobalTrackerUnpause: TNotifyEvent read FOnRequestGlobalTrackerUnpause write FOnRequestGlobalTrackerUnpause;
  end;

function ShowOpenTorrentDialog(Owner: TComponent; Rpc: TTransmissionRpcClient;
  InitialFile: string; const DefaultDir: string; DefaultStart: Boolean;
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
  WebSrv: TTransmissionWebServer; var Config: TSessionConfig;
  var DesktopPrefs: TDesktopPrefs; OnApplyCallback: TNotifyEvent = nil): Boolean;

function ShowSessionDialog(Owner: TComponent; Rpc: TTransmissionRpcClient): Boolean;

function ShowRelocateDialog(Owner: TComponent; const CurrentDir: string;
  out NewDir: string; out MoveData: Boolean): Boolean;

procedure ShowStatsDialog(Owner: TComponent; Rpc: TTransmissionRpcClient);

function ShowHistoryDialog(Owner: TComponent; Rpc: TTransmissionRpcClient;
  History: TDownloadHistoryManager; const DataDir, IniPath: string): Boolean;

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
    EdtDir: TComboBox;
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
  Dir := Trim(EdtDir.Text);
  if SelectDirectory('Select Destination Folder', '', Dir) then
  begin
    SaveDestinationDirToHistory(Dir);
    LoadDestinationDirHistory(EdtDir.Items, Dir);
    EdtDir.Text := Dir;
    EdtDirChange(nil);
  end;
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
  InitialFile: string; const DefaultDir: string; DefaultStart: Boolean;
  out SelectedFile, DestDir: string; out StartNow, TrashTorrent: Boolean;
  out Priority: Integer; out UnwantedFiles: TIntegerDynArray): Boolean;
var
  F: TOpenTorrentForm;
  Lbl: TLabel;
  BtnFile, BtnDir, BtnSelAll, BtnSelNone, BtnOK, BtnCancel: TButton;
  I, UnwantedCount: Integer;
  SessArgs: TJSONObject;
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

    F.EdtDir := TComboBox.Create(F);
    F.EdtDir.Parent := F;
    F.EdtDir.Left := 16; F.EdtDir.Top := 88; F.EdtDir.Width := 420;
    F.EdtDir.Anchors := [akLeft, akTop, akRight];
    F.EdtDir.Style := csDropDown;
    F.EdtDir.AutoComplete := True;
    F.EdtDir.DropDownCount := 12;
    F.EdtDir.Text := LoadDestinationDirHistory(F.EdtDir.Items, DefaultDir);
    F.EdtDir.OnChange := @F.EdtDirChange;
    F.EdtDir.OnSelect := @F.EdtDirChange;

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
      if DestDir <> '' then
      begin
        SaveDestinationDirToHistory(DestDir);
        if Rpc <> nil then
        begin
          SessArgs := TJSONObject.Create;
          SessArgs.Add('download-dir', StringReplace(DestDir, '\', '/', [rfReplaceAll]));
          Rpc.UpdateSession(SessArgs);
        end;
      end;
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
    EdtDir: TComboBox;
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
  Dir := Trim(EdtDir.Text);
  if SelectDirectory('Select Destination Folder', '', Dir) then
  begin
    SaveDestinationDirToHistory(Dir);
    LoadDestinationDirHistory(EdtDir.Items, Dir);
    EdtDir.Text := Dir;
    EdtDirChange(nil);
  end;
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
  SessArgs: TJSONObject;
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

    F.EdtDir := TComboBox.Create(F);
    F.EdtDir.Parent := F;
    F.EdtDir.Left := 16; F.EdtDir.Top := 92; F.EdtDir.Width := 360;
    F.EdtDir.Style := csDropDown;
    F.EdtDir.AutoComplete := True;
    F.EdtDir.DropDownCount := 12;
    F.EdtDir.Text := LoadDestinationDirHistory(F.EdtDir.Items, DefaultDir);
    F.EdtDir.OnChange := @F.EdtDirChange;
    F.EdtDir.OnSelect := @F.EdtDirChange;

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
      if DestDir <> '' then
      begin
        SaveDestinationDirToHistory(DestDir);
        if Rpc <> nil then
        begin
          SessArgs := TJSONObject.Create;
          SessArgs.Add('download-dir', StringReplace(DestDir, '\', '/', [rfReplaceAll]));
          Rpc.UpdateSession(SessArgs);
        end;
      end;
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
  I, J, LastTier: Integer;
  SL: TStringList;
  UrlStr: string;
  IsDup: Boolean;
begin
  Result := '';
  if Torrent = nil then Exit;
  SL := TStringList.Create;
  try
    LastTier := -1;
    for I := 0 to High(Torrent.Trackers) do
    begin
      UrlStr := Trim(Torrent.Trackers[I].Announce);
      if UrlStr = '' then Continue;
      IsDup := False;
      for J := 0 to I - 1 do
        if SameText(UrlStr, Trim(Torrent.Trackers[J].Announce)) then
        begin
          IsDup := True;
          Break;
        end;
      if IsDup then Continue;

      if (LastTier >= 0) and (Torrent.Trackers[I].Tier <> LastTier) then
        SL.Add('');
      SL.Add(UrlStr);
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

{ 5. Torrent Properties / Details Panel & Dialog (with Live Auto-Refresh) }

type
  TDetailsForm = class(TForm)
  public
    DetailsPanel: TDetailsPanel;
    RefreshTimer: TTimer;
    procedure RefreshTimerTick(Sender: TObject);
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
  LKey.Font.Color := RGBToColor(100, 116, 139);
  LKey.Caption := KeyText;

  Result := TLabel.Create(ParentCtrl);
  Result.Parent := ParentCtrl;
  Result.Left := 155;
  Result.Top := Y;
  Result.Width := 440;
  Result.Font.Color := RGBToColor(15, 23, 42);
  Result.Caption := ValText;
end;

constructor TDetailsPanel.CreatePanel(AOwner: TComponent; ARpc: TTransmissionRpcClient);
begin
  inherited Create(AOwner);
  FRpc := ARpc;
  FOwnedTorrent := TTorrentItem.Create;
  FCurrentId := 0;
  BevelOuter := bvNone;
  DoubleBuffered := True;
  BuildTabs;
end;

destructor TDetailsPanel.Destroy;
begin
  FOwnedTorrent.Free;
  inherited Destroy;
end;

procedure TDetailsPanel.NotifyModalStart;
begin
  if Assigned(FOnModalStart) then FOnModalStart(Self);
end;

procedure TDetailsPanel.NotifyModalEnd;
begin
  if Assigned(FOnModalEnd) then FOnModalEnd(Self);
end;

procedure TDetailsPanel.NotifyDataChanged;
begin
  if Assigned(FOnDataChanged) then FOnDataChanged(Self);
end;

procedure TDetailsPanel.BuildTabs;
var
  TsAct, TsInfo, TsOpts: TTabSheet;
  SbAct, SbInfo, SbOpts: TScrollBox;
  PnlTrkBtns, PnlFileBtns: TPanel;
  BtnAddTrk, BtnEditTrk, BtnRemTrk, BtnToggleTrk: TButton;
  BtnSelAll, BtnSelNone, BtnPriHigh, BtnPriNorm, BtnPriLow, BtnRename, BtnSaveFiles: TButton;
  BtnApplyOpt: TButton;
  Lbl: TLabel;
begin
  FPageControl := TPageControl.Create(Self);
  FPageControl.Parent := Self;
  FPageControl.Align := alClient;

  // Tab 1: Activity (ห่อด้วย TScrollBox เพื่อรองรับพาเนลด้านล่างทุกความสูง)
  TsAct := FPageControl.AddTabSheet;
  TsAct.Caption := 'Activity';
  SbAct := TScrollBox.Create(TsAct);
  SbAct.Parent := TsAct;
  SbAct.Align := alClient;
  SbAct.BorderStyle := bsNone;
  SbAct.Color := clWhite;
  LblHaveVal := CreateKeyValLabel(SbAct, 14, 'Have:', '');
  LblDownVal := CreateKeyValLabel(SbAct, 40, 'Downloaded:', '');
  LblUpVal := CreateKeyValLabel(SbAct, 66, 'Uploaded:', '');
  LblStateVal := CreateKeyValLabel(SbAct, 92, 'State:', '');
  LblDownSpdVal := CreateKeyValLabel(SbAct, 118, 'Download Speed:', '');
  LblUpSpdVal := CreateKeyValLabel(SbAct, 144, 'Upload Speed:', '');
  LblRunTimeVal := CreateKeyValLabel(SbAct, 170, 'Running Time:', '');
  LblRemTimeVal := CreateKeyValLabel(SbAct, 196, 'Remaining Time:', '');
  LblLastActVal := CreateKeyValLabel(SbAct, 222, 'Last Activity:', '');
  LblErrVal := CreateKeyValLabel(SbAct, 248, 'Error:', '');

  // Tab 2: Information
  TsInfo := FPageControl.AddTabSheet;
  TsInfo.Caption := 'Information';
  SbInfo := TScrollBox.Create(TsInfo);
  SbInfo.Parent := TsInfo;
  SbInfo.Align := alClient;
  SbInfo.BorderStyle := bsNone;
  SbInfo.Color := clWhite;
  LblInfoSizeVal := CreateKeyValLabel(SbInfo, 14, 'Total Size:', '');
  LblInfoHashVal := CreateKeyValLabel(SbInfo, 40, 'Hash:', '');
  LblInfoTypeVal := CreateKeyValLabel(SbInfo, 66, 'Type:', '');
  LblInfoLocVal := CreateKeyValLabel(SbInfo, 92, 'Location:', '');
  LblInfoCreatorVal := CreateKeyValLabel(SbInfo, 118, 'Creator:', '');
  LblInfoAddedVal := CreateKeyValLabel(SbInfo, 144, 'Added Date:', '');
  LblInfoDoneVal := CreateKeyValLabel(SbInfo, 170, 'Completed Date:', '');
  LblInfoCommentVal := CreateKeyValLabel(SbInfo, 196, 'Comment:', '');

  // Tab 3: Peers
  TsPeersTab := FPageControl.AddTabSheet;
  TsPeersTab.Caption := 'Peers';
  LvPeers := TListView.Create(TsPeersTab);
  LvPeers.Parent := TsPeersTab;
  LvPeers.Align := alClient;
  LvPeers.ViewStyle := vsReport;
  LvPeers.ReadOnly := True;
  LvPeers.RowSelect := True;
  LvPeers.GridLines := True;
  with LvPeers.Columns.Add do begin Caption := 'Address'; Width := 155; end;
  with LvPeers.Columns.Add do begin Caption := 'Client'; Width := 155; end;
  with LvPeers.Columns.Add do begin Caption := '%'; Width := 65; end;
  with LvPeers.Columns.Add do begin Caption := 'Down'; Width := 90; end;
  with LvPeers.Columns.Add do begin Caption := 'Up'; Width := 90; end;
  with LvPeers.Columns.Add do begin Caption := 'Flags'; Width := 65; end;

  // Tab 4: Trackers (ใช้ alBottom สำหรับแถวปุ่ม เพื่อไม่ให้หลุดขอบเมื่อย่อความสูงพาเนล)
  TsTrackersTab := FPageControl.AddTabSheet;
  TsTrackersTab.Caption := 'Trackers';
  PnlTrkBtns := TPanel.Create(TsTrackersTab);
  PnlTrkBtns.Parent := TsTrackersTab;
  PnlTrkBtns.Align := alBottom;
  PnlTrkBtns.Height := 36;
  PnlTrkBtns.BevelOuter := bvNone;

  LvTrackers := TListView.Create(TsTrackersTab);
  LvTrackers.Parent := TsTrackersTab;
  LvTrackers.Align := alClient;
  LvTrackers.ViewStyle := vsReport;
  LvTrackers.ReadOnly := True;
  LvTrackers.RowSelect := True;
  LvTrackers.GridLines := True;
  with LvTrackers.Columns.Add do begin Caption := 'Tier'; Width := 45; end;
  with LvTrackers.Columns.Add do begin Caption := 'Tracker Announce URL'; Width := 320; end;
  with LvTrackers.Columns.Add do begin Caption := 'Status'; Width := 160; end;
  with LvTrackers.Columns.Add do begin Caption := 'Seeders'; Width := 65; end;
  with LvTrackers.Columns.Add do begin Caption := 'Leechers'; Width := 65; end;

  BtnAddTrk := TButton.Create(PnlTrkBtns);
  BtnAddTrk.Parent := PnlTrkBtns;
  BtnAddTrk.Left := 8; BtnAddTrk.Top := 5; BtnAddTrk.Width := 98; BtnAddTrk.Height := 26;
  BtnAddTrk.Caption := 'Add Tracker...';
  BtnAddTrk.OnClick := @BtnAddTrackerClick;

  BtnEditTrk := TButton.Create(PnlTrkBtns);
  BtnEditTrk.Parent := PnlTrkBtns;
  BtnEditTrk.Left := 110; BtnEditTrk.Top := 5; BtnEditTrk.Width := 104; BtnEditTrk.Height := 26;
  BtnEditTrk.Caption := 'Edit Trackers...';
  BtnEditTrk.OnClick := @BtnEditTrackersClick;

  BtnRemTrk := TButton.Create(PnlTrkBtns);
  BtnRemTrk.Parent := PnlTrkBtns;
  BtnRemTrk.Left := 218; BtnRemTrk.Top := 5; BtnRemTrk.Width := 110; BtnRemTrk.Height := 26;
  BtnRemTrk.Caption := 'Remove Tracker';
  BtnRemTrk.OnClick := @BtnRemoveTrackerClick;

  BtnToggleTrk := TButton.Create(PnlTrkBtns);
  BtnToggleTrk.Parent := PnlTrkBtns;
  BtnToggleTrk.Left := 332; BtnToggleTrk.Top := 5; BtnToggleTrk.Width := 172; BtnToggleTrk.Height := 26;
  BtnToggleTrk.Caption := 'สลับ https:// <-> ht..tps://';
  BtnToggleTrk.OnClick := @BtnToggleTrackerHttpsClick;

  BtnBlockTrkPackets := TButton.Create(PnlTrkBtns);
  BtnBlockTrkPackets.Parent := PnlTrkBtns;
  BtnBlockTrkPackets.Left := 510; BtnBlockTrkPackets.Top := 5; BtnBlockTrkPackets.Width := 196; BtnBlockTrkPackets.Height := 26;
  BtnBlockTrkPackets.Caption := 'Tracker Packet: ON (คลิกปิด)';
  BtnBlockTrkPackets.OnClick := @BtnBlockTrkPacketsClick;

  ChkAutoPauseTrk := TCheckBox.Create(PnlTrkBtns);
  ChkAutoPauseTrk.Parent := PnlTrkBtns;
  ChkAutoPauseTrk.Left := 714; ChkAutoPauseTrk.Top := 8;
  ChkAutoPauseTrk.Caption := 'ดึง Peer รอบแรกแล้วหยุดส่ง';
  ChkAutoPauseTrk.Hint := 'เมื่อได้รับรายชื่อ Peer จาก Tracker รอบแรกแล้ว ให้หยุดส่ง Packet อัตโนมัติ';
  ChkAutoPauseTrk.ShowHint := True;
  ChkAutoPauseTrk.OnClick := @ChkAutoPauseTrkClick;

  // Tab 5: Files
  TsFilesTab := FPageControl.AddTabSheet;
  TsFilesTab.Caption := 'Files';
  PnlFileBtns := TPanel.Create(TsFilesTab);
  PnlFileBtns.Parent := TsFilesTab;
  PnlFileBtns.Align := alBottom;
  PnlFileBtns.Height := 36;
  PnlFileBtns.BevelOuter := bvNone;

  LvFiles := TListView.Create(TsFilesTab);
  LvFiles.Parent := TsFilesTab;
  LvFiles.Align := alClient;
  LvFiles.ViewStyle := vsReport;
  LvFiles.Checkboxes := True;
  LvFiles.MultiSelect := True;
  LvFiles.RowSelect := True;
  LvFiles.GridLines := True;
  with LvFiles.Columns.Add do begin Caption := 'File Name'; Width := 305; end;
  with LvFiles.Columns.Add do begin Caption := 'Size'; Width := 85; end;
  with LvFiles.Columns.Add do begin Caption := 'Done'; Width := 85; end;
  with LvFiles.Columns.Add do begin Caption := '%'; Width := 60; end;
  with LvFiles.Columns.Add do begin Caption := 'Priority'; Width := 65; end;

  BtnSelAll := TButton.Create(PnlFileBtns);
  BtnSelAll.Parent := PnlFileBtns;
  BtnSelAll.Left := 8; BtnSelAll.Top := 5; BtnSelAll.Width := 68; BtnSelAll.Height := 26;
  BtnSelAll.Caption := 'All';
  BtnSelAll.OnClick := @BtnSelectAllFilesClick;

  BtnSelNone := TButton.Create(PnlFileBtns);
  BtnSelNone.Parent := PnlFileBtns;
  BtnSelNone.Left := 80; BtnSelNone.Top := 5; BtnSelNone.Width := 68; BtnSelNone.Height := 26;
  BtnSelNone.Caption := 'None';
  BtnSelNone.OnClick := @BtnSelectNoneFilesClick;

  BtnPriHigh := TButton.Create(PnlFileBtns);
  BtnPriHigh.Parent := PnlFileBtns;
  BtnPriHigh.Left := 156; BtnPriHigh.Top := 5; BtnPriHigh.Width := 72; BtnPriHigh.Height := 26;
  BtnPriHigh.Caption := 'Pri: High';
  BtnPriHigh.Tag := TR_PRI_HIGH;
  BtnPriHigh.OnClick := @BtnSetFilePriorityClick;

  BtnPriNorm := TButton.Create(PnlFileBtns);
  BtnPriNorm.Parent := PnlFileBtns;
  BtnPriNorm.Left := 232; BtnPriNorm.Top := 5; BtnPriNorm.Width := 76; BtnPriNorm.Height := 26;
  BtnPriNorm.Caption := 'Pri: Norm';
  BtnPriNorm.Tag := TR_PRI_NORMAL;
  BtnPriNorm.OnClick := @BtnSetFilePriorityClick;

  BtnPriLow := TButton.Create(PnlFileBtns);
  BtnPriLow.Parent := PnlFileBtns;
  BtnPriLow.Left := 312; BtnPriLow.Top := 5; BtnPriLow.Width := 72; BtnPriLow.Height := 26;
  BtnPriLow.Caption := 'Pri: Low';
  BtnPriLow.Tag := TR_PRI_LOW;
  BtnPriLow.OnClick := @BtnSetFilePriorityClick;

  BtnRename := TButton.Create(PnlFileBtns);
  BtnRename.Parent := PnlFileBtns;
  BtnRename.Left := 390; BtnRename.Top := 5; BtnRename.Width := 85; BtnRename.Height := 26;
  BtnRename.Caption := 'Rename...';
  BtnRename.OnClick := @BtnRenameFileClick;

  BtnSaveFiles := TButton.Create(PnlFileBtns);
  BtnSaveFiles.Parent := PnlFileBtns;
  BtnSaveFiles.Left := 485; BtnSaveFiles.Top := 5; BtnSaveFiles.Width := 145; BtnSaveFiles.Height := 26;
  BtnSaveFiles.Caption := 'Apply Wanted Files';
  BtnSaveFiles.OnClick := @BtnApplyFilesClick;

  // Tab 6: Options
  TsOpts := FPageControl.AddTabSheet;
  TsOpts.Caption := 'Options';
  SbOpts := TScrollBox.Create(TsOpts);
  SbOpts.Parent := TsOpts;
  SbOpts.Align := alClient;
  SbOpts.BorderStyle := bsNone;

  ChkHonorSession := TCheckBox.Create(SbOpts);
  ChkHonorSession.Parent := SbOpts;
  ChkHonorSession.Left := 20; ChkHonorSession.Top := 16;
  ChkHonorSession.Caption := 'Honor global session bandwidth limits';

  ChkDownLimit := TCheckBox.Create(SbOpts);
  ChkDownLimit.Parent := SbOpts;
  ChkDownLimit.Left := 20; ChkDownLimit.Top := 48;
  ChkDownLimit.Caption := 'Limit download speed (KB/s):';

  SpnDownLimit := TSpinEdit.Create(SbOpts);
  SpnDownLimit.Parent := SbOpts;
  SpnDownLimit.Left := 230; SpnDownLimit.Top := 44; SpnDownLimit.Width := 100;
  SpnDownLimit.MaxValue := 1000000;

  ChkUpLimit := TCheckBox.Create(SbOpts);
  ChkUpLimit.Parent := SbOpts;
  ChkUpLimit.Left := 20; ChkUpLimit.Top := 82;
  ChkUpLimit.Caption := 'Limit upload speed (KB/s):';

  SpnUpLimit := TSpinEdit.Create(SbOpts);
  SpnUpLimit.Parent := SbOpts;
  SpnUpLimit.Left := 230; SpnUpLimit.Top := 78; SpnUpLimit.Width := 100;
  SpnUpLimit.MaxValue := 1000000;

  Lbl := TLabel.Create(SbOpts);
  Lbl.Parent := SbOpts;
  Lbl.Left := 20; Lbl.Top := 120;
  Lbl.Caption := 'Seed ratio limit:';

  CmbRatioMode := TComboBox.Create(SbOpts);
  CmbRatioMode.Parent := SbOpts;
  CmbRatioMode.Left := 140; CmbRatioMode.Top := 116; CmbRatioMode.Width := 180;
  CmbRatioMode.Style := csDropDownList;
  CmbRatioMode.Items.Add('Use global settings');
  CmbRatioMode.Items.Add('Stop seeding at ratio:');
  CmbRatioMode.Items.Add('Seed regardless of ratio');

  EdtRatioLimit := TEdit.Create(SbOpts);
  EdtRatioLimit.Parent := SbOpts;
  EdtRatioLimit.Left := 330; EdtRatioLimit.Top := 116; EdtRatioLimit.Width := 80;

  Lbl := TLabel.Create(SbOpts);
  Lbl.Parent := SbOpts;
  Lbl.Left := 20; Lbl.Top := 156;
  Lbl.Caption := 'Maximum peers:';

  SpnPeerLimit := TSpinEdit.Create(SbOpts);
  SpnPeerLimit.Parent := SbOpts;
  SpnPeerLimit.Left := 140; SpnPeerLimit.Top := 152; SpnPeerLimit.Width := 100;
  SpnPeerLimit.MaxValue := 2000;

  BtnApplyOpt := TButton.Create(SbOpts);
  BtnApplyOpt.Parent := SbOpts;
  BtnApplyOpt.Left := 20; BtnApplyOpt.Top := 196; BtnApplyOpt.Width := 130; BtnApplyOpt.Height := 28;
  BtnApplyOpt.Caption := 'Apply Options';
  BtnApplyOpt.OnClick := @BtnApplyOptionsClick;

  // Tab 7: Speed Graph (กราฟความเร็วเรียลไทม์ Down/Up)
  TsSpeedGraphTab := FPageControl.AddTabSheet;
  TsSpeedGraphTab.Caption := 'Speed Graph';

  PnlTrkBtns := TPanel.Create(TsSpeedGraphTab); // แถบควบคุมด้านบนของกราฟ
  PnlTrkBtns.Parent := TsSpeedGraphTab;
  PnlTrkBtns.Align := alTop;
  PnlTrkBtns.Height := 30;
  PnlTrkBtns.BevelOuter := bvNone;

  RbGraphTorrent := TRadioButton.Create(PnlTrkBtns);
  RbGraphTorrent.Parent := PnlTrkBtns;
  RbGraphTorrent.Left := 8; RbGraphTorrent.Top := 6;
  RbGraphTorrent.Caption := 'Selected Torrent';
  RbGraphTorrent.Checked := True;
  RbGraphTorrent.OnChange := @GraphSourceChange;

  RbGraphGlobal := TRadioButton.Create(PnlTrkBtns);
  RbGraphGlobal.Parent := PnlTrkBtns;
  RbGraphGlobal.Left := 132; RbGraphGlobal.Top := 6;
  RbGraphGlobal.Caption := 'All Torrents (Global)';
  RbGraphGlobal.OnChange := @GraphSourceChange;

  BtnToggleTrk := TButton.Create(PnlTrkBtns);
  BtnToggleTrk.Parent := PnlTrkBtns;
  BtnToggleTrk.Left := 280; BtnToggleTrk.Top := 3; BtnToggleTrk.Width := 56; BtnToggleTrk.Height := 24;
  BtnToggleTrk.Caption := 'Reset';
  BtnToggleTrk.OnClick := @BtnGraphClearClick;

  LblGraphStats := TLabel.Create(PnlTrkBtns);
  LblGraphStats.Parent := PnlTrkBtns;
  LblGraphStats.Left := 346; LblGraphStats.Top := 7;
  LblGraphStats.Caption := 'Down: 0 B/s | Up: 0 B/s';

  PnlFileBtns := TPanel.Create(TsSpeedGraphTab); // พาเนลพื้นหลังกราฟแบบ DoubleBuffered ป้องกันการกระพริบ
  PnlFileBtns.Parent := TsSpeedGraphTab;
  PnlFileBtns.Align := alClient;
  PnlFileBtns.BevelOuter := bvNone;
  PnlFileBtns.DoubleBuffered := True;
  PnlFileBtns.Color := RGBToColor(20, 24, 32);

  PbSpeedGraph := TPaintBox.Create(PnlFileBtns);
  PbSpeedGraph.Parent := PnlFileBtns;
  PbSpeedGraph.Align := alClient;
  PbSpeedGraph.OnPaint := @PbSpeedGraphPaint;
end;

procedure TDetailsPanel.SyncOptionsAndInfo;
begin
  LblInfoSizeVal.Caption := Format('%s (%d pieces @ %s)',
    [FormatSize(FOwnedTorrent.TotalSize), FOwnedTorrent.PieceCount, FormatSize(FOwnedTorrent.PieceSize)]);
  LblInfoHashVal.Caption := FOwnedTorrent.HashString;
  if FOwnedTorrent.IsPrivate then
    LblInfoTypeVal.Caption := 'Private torrent (DHT and PEX disabled)'
  else
    LblInfoTypeVal.Caption := 'Public torrent';
  LblInfoLocVal.Caption := FOwnedTorrent.DownloadDir;
  LblInfoCreatorVal.Caption := FOwnedTorrent.Creator;
  LblInfoAddedVal.Caption := UnixToDateTimeStr(FOwnedTorrent.AddedDate);
  LblInfoDoneVal.Caption := UnixToDateTimeStr(FOwnedTorrent.DoneDate);
  LblInfoCommentVal.Caption := FOwnedTorrent.Comment;

  ChkHonorSession.Checked := FOwnedTorrent.HonorsSessionLimits;
  ChkDownLimit.Checked := FOwnedTorrent.DownloadLimited;
  SpnDownLimit.Value := FOwnedTorrent.DownloadLimit;
  ChkUpLimit.Checked := FOwnedTorrent.UploadLimited;
  SpnUpLimit.Value := FOwnedTorrent.UploadLimit;
  if (FOwnedTorrent.SeedRatioMode >= 0) and (FOwnedTorrent.SeedRatioMode <= 2) then
    CmbRatioMode.ItemIndex := FOwnedTorrent.SeedRatioMode
  else
    CmbRatioMode.ItemIndex := 0;
  EdtRatioLimit.Text := Format('%.2f', [FOwnedTorrent.SeedRatioLimit]);
  SpnPeerLimit.Value := FOwnedTorrent.PeerLimit;
end;

const
  MAX_GRAPH_SAMPLES = 120;

procedure PushSpeedSample(var ArrDown, ArrUp: specialize TArray<Int64>; DownVal, UpVal: Int64);
var
  Len, I: Integer;
begin
  if DownVal < 0 then DownVal := 0;
  if UpVal < 0 then UpVal := 0;
  Len := Length(ArrDown);
  if Len < MAX_GRAPH_SAMPLES then
  begin
    SetLength(ArrDown, Len + 1);
    SetLength(ArrUp, Len + 1);
    ArrDown[Len] := DownVal;
    ArrUp[Len] := UpVal;
  end
  else
  begin
    for I := 0 to Len - 2 do
    begin
      ArrDown[I] := ArrDown[I + 1];
      ArrUp[I] := ArrUp[I + 1];
    end;
    ArrDown[Len - 1] := DownVal;
    ArrUp[Len - 1] := UpVal;
  end;
end;

function SnapGraphScaleMax(PeakVal: Int64): Int64;
const
  STEPS: array[0..11] of Int64 = (
    10 * 1024,          // 10 KB/s
    50 * 1024,          // 50 KB/s
    100 * 1024,         // 100 KB/s
    250 * 1024,         // 250 KB/s
    500 * 1024,         // 500 KB/s
    1024 * 1024,        // 1 MB/s
    2 * 1024 * 1024,    // 2 MB/s
    5 * 1024 * 1024,    // 5 MB/s
    10 * 1024 * 1024,   // 10 MB/s
    25 * 1024 * 1024,   // 25 MB/s
    50 * 1024 * 1024,   // 50 MB/s
    100 * 1024 * 1024   // 100 MB/s
  );
var
  I: Integer;
begin
  for I := Low(STEPS) to High(STEPS) do
    if PeakVal <= STEPS[I] then
      Exit(STEPS[I]);
  Result := ((PeakVal div (50 * 1024 * 1024)) + 1) * (50 * 1024 * 1024);
end;

procedure TDetailsPanel.RecordGlobalSpeed(DownRate, UpRate: Int64);
begin
  PushSpeedSample(FGlobalDownHist, FGlobalUpHist, DownRate, UpRate);
  if (RbGraphGlobal <> nil) and RbGraphGlobal.Checked then
  begin
    UpdateGraphStatsLabel;
    if (PbSpeedGraph <> nil) and (FPageControl <> nil) and (FPageControl.ActivePage = TsSpeedGraphTab) then
      PbSpeedGraph.Invalidate;
  end;
end;

procedure TDetailsPanel.GraphSourceChange(Sender: TObject);
begin
  UpdateGraphStatsLabel;
  if PbSpeedGraph <> nil then
    PbSpeedGraph.Invalidate;
end;

procedure TDetailsPanel.BtnGraphClearClick(Sender: TObject);
begin
  if (RbGraphGlobal <> nil) and RbGraphGlobal.Checked then
  begin
    SetLength(FGlobalDownHist, 0);
    SetLength(FGlobalUpHist, 0);
  end
  else
  begin
    SetLength(FTorrentDownHist, 0);
    SetLength(FTorrentUpHist, 0);
  end;
  UpdateGraphStatsLabel;
  if PbSpeedGraph <> nil then
    PbSpeedGraph.Invalidate;
end;

procedure TDetailsPanel.UpdateGraphStatsLabel;
var
  I, Cnt: Integer;
  SumD, SumU, PeakD, PeakU, CurD, CurU: Int64;
  UseGlobal: Boolean;
begin
  if LblGraphStats = nil then Exit;
  UseGlobal := (RbGraphGlobal <> nil) and RbGraphGlobal.Checked;
  if UseGlobal then
    Cnt := Length(FGlobalDownHist)
  else
    Cnt := Length(FTorrentDownHist);

  if Cnt = 0 then
  begin
    LblGraphStats.Caption := 'Down: 0 B/s | Up: 0 B/s';
    Exit;
  end;

  SumD := 0; SumU := 0; PeakD := 0; PeakU := 0; CurD := 0; CurU := 0;
  for I := 0 to Cnt - 1 do
  begin
    if UseGlobal then
    begin
      CurD := FGlobalDownHist[I];
      CurU := FGlobalUpHist[I];
    end
    else
    begin
      CurD := FTorrentDownHist[I];
      CurU := FTorrentUpHist[I];
    end;
    Inc(SumD, CurD);
    Inc(SumU, CurU);
    if CurD > PeakD then PeakD := CurD;
    if CurU > PeakU then PeakU := CurU;
  end;
  LblGraphStats.Caption := Format('Down: %s (Peak %s, Avg %s) | Up: %s (Peak %s)',
    [FormatSpeed(CurD), FormatSpeed(PeakD), FormatSpeed(SumD div Cnt),
     FormatSpeed(CurU), FormatSpeed(PeakU)]);
end;

procedure TDetailsPanel.PbSpeedGraphPaint(Sender: TObject);
const
  PAD_L = 12;
  PAD_R = 76;
  PAD_T = 12;
  PAD_B = 14;
var
  C: TCanvas;
  W, H, GW, GH, I, Cnt, StartIdx: Integer;
  MaxRate, PeakVal, ValD, ValU: Int64;
  UseGlobal: Boolean;
  PtsDown, PtsUp, PolyDown: array of TPoint;
  YVal: Int64;
  YPos, XPos: Integer;
  LabelTxt: string;
begin
  if PbSpeedGraph = nil then Exit;
  C := PbSpeedGraph.Canvas;
  W := PbSpeedGraph.Width;
  H := PbSpeedGraph.Height;

  C.Brush.Color := RGBToColor(20, 24, 32);
  C.FillRect(0, 0, W, H);

  GW := W - PAD_L - PAD_R;
  GH := H - PAD_T - PAD_B;
  if (GW < 40) or (GH < 30) then Exit;

  UseGlobal := (RbGraphGlobal <> nil) and RbGraphGlobal.Checked;
  if UseGlobal then
    Cnt := Length(FGlobalDownHist)
  else
    Cnt := Length(FTorrentDownHist);

  PeakVal := 0;
  for I := 0 to Cnt - 1 do
  begin
    if UseGlobal then
    begin
      ValD := FGlobalDownHist[I];
      ValU := FGlobalUpHist[I];
    end
    else
    begin
      ValD := FTorrentDownHist[I];
      ValU := FTorrentUpHist[I];
    end;
    if ValD > PeakVal then PeakVal := ValD;
    if ValU > PeakVal then PeakVal := ValU;
  end;
  MaxRate := SnapGraphScaleMax(PeakVal);

  // Grid lines & right Y-axis labels
  C.Font.Size := 8;
  C.Font.Color := RGBToColor(156, 166, 184);
  for I := 0 to 4 do
  begin
    YPos := PAD_T + Round((GH * (4 - I)) / 4);
    C.Pen.Color := RGBToColor(44, 52, 66);
    C.Pen.Style := psSolid;
    C.Pen.Width := 1;
    C.MoveTo(PAD_L, YPos);
    C.LineTo(PAD_L + GW, YPos);

    YVal := (MaxRate * I) div 4;
    LabelTxt := FormatSpeed(YVal);
    C.Brush.Style := bsClear;
    C.TextOut(PAD_L + GW + 6, YPos - 7, LabelTxt);
  end;

  // Vertical time gridlines
  for I := 1 to 5 do
  begin
    XPos := PAD_L + Round((GW * I) / 6);
    C.Pen.Color := RGBToColor(34, 40, 52);
    C.MoveTo(XPos, PAD_T);
    C.LineTo(XPos, PAD_T + GH);
  end;

  // Frame border
  C.Pen.Color := RGBToColor(58, 68, 86);
  C.Brush.Style := bsClear;
  C.Rectangle(PAD_L, PAD_T, PAD_L + GW + 1, PAD_T + GH + 1);

  if Cnt >= 2 then
  begin
    SetLength(PtsDown, Cnt);
    SetLength(PtsUp, Cnt);
    StartIdx := MAX_GRAPH_SAMPLES - Cnt;
    for I := 0 to Cnt - 1 do
    begin
      XPos := PAD_L + Round(((StartIdx + I) * GW) / (MAX_GRAPH_SAMPLES - 1));
      if UseGlobal then
      begin
        ValD := FGlobalDownHist[I];
        ValU := FGlobalUpHist[I];
      end
      else
      begin
        ValD := FTorrentDownHist[I];
        ValU := FTorrentUpHist[I];
      end;
      PtsDown[I].X := XPos;
      PtsDown[I].Y := PAD_T + GH - Round((EnsureRange(ValD, 0, MaxRate) * GH) / MaxRate);
      PtsUp[I].X := XPos;
      PtsUp[I].Y := PAD_T + GH - Round((EnsureRange(ValU, 0, MaxRate) * GH) / MaxRate);
    end;

    // Shaded download area
    SetLength(PolyDown, Cnt + 2);
    for I := 0 to Cnt - 1 do
      PolyDown[I] := PtsDown[I];
    PolyDown[Cnt] := Point(PtsDown[Cnt - 1].X, PAD_T + GH);
    PolyDown[Cnt + 1] := Point(PtsDown[0].X, PAD_T + GH);
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(24, 62, 46);
    C.Pen.Style := psClear;
    C.Polygon(PolyDown);

    // Download line (Green)
    C.Brush.Style := bsClear;
    C.Pen.Style := psSolid;
    C.Pen.Width := 2;
    C.Pen.Color := RGBToColor(46, 204, 113);
    C.Polyline(PtsDown);

    // Upload line (Sky Blue)
    C.Pen.Color := RGBToColor(72, 168, 255);
    C.Polyline(PtsUp);
  end;

  // Legend overlay at top-left (ใช้ TextWidth จริงรองรับทุกสเกล DPI)
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(46, 204, 113);
  C.FillRect(PAD_L + 10, PAD_T + 7, PAD_L + 20, PAD_T + 15);
  C.Brush.Style := bsClear;
  C.Font.Color := RGBToColor(215, 224, 236);
  C.TextOut(PAD_L + 25, PAD_T + 3, 'Download');

  XPos := PAD_L + 25 + C.TextWidth('Download') + 18;
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(72, 168, 255);
  C.FillRect(XPos, PAD_T + 7, XPos + 10, PAD_T + 15);
  C.Brush.Style := bsClear;
  C.TextOut(XPos + 15, PAD_T + 3, 'Upload');
end;

procedure TDetailsPanel.LoadTorrent(ATorrentId: Integer);
begin
  if ATorrentId <= 0 then
  begin
    FCurrentId := 0;
    FOwnedTorrent.Id := 0;
    SetLength(FTorrentDownHist, 0);
    SetLength(FTorrentUpHist, 0);
    UpdateGraphStatsLabel;
    if PbSpeedGraph <> nil then PbSpeedGraph.Invalidate;
    Exit;
  end;

  if FCurrentId = ATorrentId then Exit;

  FCurrentId := ATorrentId;
  FOwnedTorrent.Id := ATorrentId;
  SetLength(FOwnedTorrent.Files, 0);
  SetLength(FOwnedTorrent.Peers, 0);
  SetLength(FOwnedTorrent.Trackers, 0);
  SetLength(FTorrentDownHist, 0);
  SetLength(FTorrentUpHist, 0);
  LvFiles.Items.Clear;

  if (FRpc <> nil) and FRpc.FetchTorrentDetails(FOwnedTorrent) then
  begin
    SyncOptionsAndInfo;
    UpdateDynamicViews;
  end;
end;

procedure TDetailsPanel.RefreshDetails;
begin
  if (FCurrentId > 0) and (FRpc <> nil) and FRpc.FetchTorrentDetails(FOwnedTorrent) then
    UpdateDynamicViews;
end;

function TDetailsPanel.IsTrackerPaused: Boolean;
begin
  Result := FOwnedTorrent.TrackerPaused or FGlobalTrackerPaused;
end;

procedure TDetailsPanel.SetUnifiedPausedState(APaused: Boolean);
begin
  FOwnedTorrent.TrackerPaused := APaused;
  FGlobalTrackerPaused := APaused;
  UpdateDynamicViews;
end;

procedure TDetailsPanel.SetGlobalTrackerPaused(AValue: Boolean);
begin
  if FGlobalTrackerPaused = AValue then Exit;
  FGlobalTrackerPaused := AValue;
  UpdateDynamicViews;
end;

procedure TDetailsPanel.UpdateDynamicViews;
var
  I: Integer;
  LI: TListItem;
  PctFile: Double;
  EffTrkPaused: Boolean;
begin
  if FCurrentId <= 0 then Exit;
  EffTrkPaused := FOwnedTorrent.TrackerPaused or FGlobalTrackerPaused;

  LblHaveVal.Caption := Format('%s of %s (%s) - %s Unverified',
    [FormatSize(FOwnedTorrent.HaveTotal), FormatSize(FOwnedTorrent.SizeWhenDone),
     FormatPercent(FOwnedTorrent.PercentDone), FormatSize(FOwnedTorrent.HaveUnchecked)]);
  LblDownVal.Caption := FormatSize(FOwnedTorrent.DownloadedEver);
  LblUpVal.Caption := Format('%s (Ratio: %s)',
    [FormatSize(FOwnedTorrent.UploadedEver), FormatRatio(FOwnedTorrent.UploadRatio)]);
  LblStateVal.Caption := FOwnedTorrent.FullStatusString;
  LblDownSpdVal.Caption := FormatSpeed(FOwnedTorrent.RateDownload);
  LblUpSpdVal.Caption := FormatSpeed(FOwnedTorrent.RateUpload);
  PushSpeedSample(FTorrentDownHist, FTorrentUpHist, FOwnedTorrent.RateDownload, FOwnedTorrent.RateUpload);
  if (RbGraphTorrent <> nil) and RbGraphTorrent.Checked then
  begin
    UpdateGraphStatsLabel;
    if (PbSpeedGraph <> nil) and (FPageControl <> nil) and (FPageControl.ActivePage = TsSpeedGraphTab) then
      PbSpeedGraph.Invalidate;
  end;
  LblRunTimeVal.Caption := Format('Downloading: %s, Seeding: %s',
    [FormatDuration(FOwnedTorrent.SecondsDownloading), FormatDuration(FOwnedTorrent.SecondsSeeding)]);
  LblRemTimeVal.Caption := FormatETA(FOwnedTorrent.ETA);
  LblLastActVal.Caption := UnixToDateTimeStr(FOwnedTorrent.ActivityDate);
  if FOwnedTorrent.ErrorString <> '' then
    LblErrVal.Caption := FOwnedTorrent.ErrorString
  else
    LblErrVal.Caption := 'None';

  if BtnBlockTrkPackets <> nil then
  begin
    if EffTrkPaused then
      BtnBlockTrkPackets.Caption := 'Tracker Packet: OFF (คลิกเปิด)'
    else
      BtnBlockTrkPackets.Caption := 'Tracker Packet: ON (คลิกปิด)';
  end;
  if ChkAutoPauseTrk <> nil then
  begin
    FSyncingTrkChk := True;
    try
      ChkAutoPauseTrk.Checked := FOwnedTorrent.TrackerAutoPause;
    finally
      FSyncingTrkChk := False;
    end;
  end;

  // Update Peers ListView
  TsPeersTab.Caption := Format('Peers (%d)', [Length(FOwnedTorrent.Peers)]);
  LvPeers.Items.BeginUpdate;
  try
    LvPeers.Items.Clear;
    for I := 0 to High(FOwnedTorrent.Peers) do
    begin
      LI := LvPeers.Items.Add;
      LI.Caption := Format('%s:%d', [FOwnedTorrent.Peers[I].Address, FOwnedTorrent.Peers[I].Port]);
      LI.SubItems.Add(FOwnedTorrent.Peers[I].ClientName);
      LI.SubItems.Add(FormatPercent(FOwnedTorrent.Peers[I].Progress));
      LI.SubItems.Add(FormatSpeed(FOwnedTorrent.Peers[I].RateToClient));
      LI.SubItems.Add(FormatSpeed(FOwnedTorrent.Peers[I].RateToPeer));
      LI.SubItems.Add(FOwnedTorrent.Peers[I].FlagStr);
    end;
  finally
    LvPeers.Items.EndUpdate;
  end;

  // Update Trackers ListView
  TsTrackersTab.Caption := Format('Trackers (%d)', [Length(FOwnedTorrent.Trackers)]);
  LvTrackers.Items.BeginUpdate;
  try
    while LvTrackers.Items.Count < Length(FOwnedTorrent.Trackers) do
      LvTrackers.Items.Add;
    while LvTrackers.Items.Count > Length(FOwnedTorrent.Trackers) do
      LvTrackers.Items.Delete(LvTrackers.Items.Count - 1);

    for I := 0 to High(FOwnedTorrent.Trackers) do
    begin
      LI := LvTrackers.Items[I];
      LI.Caption := IntToStr(FOwnedTorrent.Trackers[I].Tier + 1);
      LI.SubItems.Clear;
      LI.SubItems.Add(FOwnedTorrent.Trackers[I].Announce);
      if EffTrkPaused then
        LI.SubItems.Add('OFF (หยุดส่ง Packet)')
      else
        LI.SubItems.Add(FOwnedTorrent.Trackers[I].LastAnnounceResult);
      if FOwnedTorrent.Trackers[I].SeederCount >= 0 then
        LI.SubItems.Add(IntToStr(FOwnedTorrent.Trackers[I].SeederCount))
      else
        LI.SubItems.Add('-');
      if FOwnedTorrent.Trackers[I].LeecherCount >= 0 then
        LI.SubItems.Add(IntToStr(FOwnedTorrent.Trackers[I].LeecherCount))
      else
        LI.SubItems.Add('-');
    end;
  finally
    LvTrackers.Items.EndUpdate;
  end;

  // Update Files progress without overwriting user's unsaved checkbox changes if count matches
  TsFilesTab.Caption := Format('Files (%d)', [Length(FOwnedTorrent.Files)]);
  if LvFiles.Items.Count <> Length(FOwnedTorrent.Files) then
  begin
    LvFiles.Items.BeginUpdate;
    try
      LvFiles.Items.Clear;
      for I := 0 to High(FOwnedTorrent.Files) do
      begin
        LI := LvFiles.Items.Add;
        LI.Checked := FOwnedTorrent.Files[I].Wanted;
        LI.Caption := FOwnedTorrent.Files[I].Name;
        LI.SubItems.Add(FormatSize(FOwnedTorrent.Files[I].Length));
        LI.SubItems.Add(FormatSize(FOwnedTorrent.Files[I].BytesCompleted));
        if FOwnedTorrent.Files[I].Length > 0 then
          PctFile := FOwnedTorrent.Files[I].BytesCompleted / FOwnedTorrent.Files[I].Length
        else
          PctFile := 1.0;
        LI.SubItems.Add(FormatPercent(PctFile));
        LI.SubItems.Add(PriorityToStr(FOwnedTorrent.Files[I].Priority));
      end;
    finally
      LvFiles.Items.EndUpdate;
    end;
  end
  else
  begin
    for I := 0 to High(FOwnedTorrent.Files) do
    begin
      LI := LvFiles.Items[I];
      if LI.SubItems.Count >= 4 then
      begin
        LI.SubItems[1] := FormatSize(FOwnedTorrent.Files[I].BytesCompleted);
        if FOwnedTorrent.Files[I].Length > 0 then
          PctFile := FOwnedTorrent.Files[I].BytesCompleted / FOwnedTorrent.Files[I].Length
        else
          PctFile := 1.0;
        LI.SubItems[2] := FormatPercent(PctFile);
      end;
    end;
  end;
end;

procedure TDetailsForm.RefreshTimerTick(Sender: TObject);
begin
  if DetailsPanel <> nil then
    DetailsPanel.RefreshDetails;
end;

procedure TDetailsPanel.BtnApplyOptionsClick(Sender: TObject);
var
  Args: TJSONObject;
begin
  if FCurrentId <= 0 then Exit;
  Args := TJSONObject.Create;
  Args.Add('honorsSessionLimits', ChkHonorSession.Checked);
  Args.Add('downloadLimited', ChkDownLimit.Checked);
  Args.Add('downloadLimit', SpnDownLimit.Value);
  Args.Add('uploadLimited', ChkUpLimit.Checked);
  Args.Add('uploadLimit', SpnUpLimit.Value);
  Args.Add('seedRatioMode', CmbRatioMode.ItemIndex);
  Args.Add('seedRatioLimit', StrToFloatDef(EdtRatioLimit.Text, 2.0));
  Args.Add('peer-limit', SpnPeerLimit.Value);

  NotifyModalStart;
  try
    if FRpc.SetTorrentOptions(FCurrentId, Args) then
    begin
      RefreshDetails;
      NotifyDataChanged;
      MessageDlg('Torrent options updated.', mtInformation, [mbOK], 0);
    end
    else
      MessageDlg('Failed to update options: ' + FRpc.LastError, mtError, [mbOK], 0);
  finally
    NotifyModalEnd;
  end;
end;

procedure TDetailsPanel.BtnApplyFilesClick(Sender: TObject);
var
  Args: TJSONObject;
  WantedArr, UnwantedArr: TJSONArray;
  I: Integer;
begin
  if FCurrentId <= 0 then Exit;
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

  NotifyModalStart;
  try
    if FRpc.SetTorrentOptions(FCurrentId, Args) then
    begin
      RefreshDetails;
      NotifyDataChanged;
      MessageDlg('File selection saved.', mtInformation, [mbOK], 0);
    end
    else
      MessageDlg('Failed to update file selection: ' + FRpc.LastError, mtError, [mbOK], 0);
  finally
    NotifyModalEnd;
  end;
end;

procedure TDetailsPanel.BtnSelectAllFilesClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to LvFiles.Items.Count - 1 do
    LvFiles.Items[I].Checked := True;
end;

procedure TDetailsPanel.BtnSelectNoneFilesClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to LvFiles.Items.Count - 1 do
    LvFiles.Items[I].Checked := False;
end;

procedure TDetailsPanel.BtnSetFilePriorityClick(Sender: TObject);
var
  TagPri: Integer;
  KeyName: string;
  Args: TJSONObject;
  IdxArr: TJSONArray;
  I: Integer;
begin
  if FCurrentId <= 0 then Exit;
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
    NotifyModalStart;
    try
      MessageDlg('Select one or more files in the list first.', mtInformation, [mbOK], 0);
    finally
      NotifyModalEnd;
    end;
    Exit;
  end;

  Args := TJSONObject.Create;
  Args.Add(KeyName, IdxArr);
  if FRpc.SetTorrentOptions(FCurrentId, Args) then
    NotifyDataChanged;
end;

procedure TDetailsPanel.BtnRenameFileClick(Sender: TObject);
var
  OldPath, BaseName, NewName: string;
begin
  if FCurrentId <= 0 then Exit;
  if LvFiles.Selected = nil then
  begin
    NotifyModalStart;
    try
      MessageDlg('Please select a file to rename.', mtInformation, [mbOK], 0);
    finally
      NotifyModalEnd;
    end;
    Exit;
  end;
  OldPath := LvFiles.Selected.Caption;
  BaseName := ExtractFileName(StringReplace(OldPath, '/', '\', [rfReplaceAll]));
  NewName := BaseName;
  NotifyModalStart;
  try
    if InputQuery('Rename File', 'Enter new file name:', NewName) and (Trim(NewName) <> '') and (NewName <> BaseName) then
    begin
      if FRpc.RenameTorrentPath(FCurrentId, OldPath, Trim(NewName)) then
      begin
        FRpc.FetchTorrentDetails(FOwnedTorrent);
        LvFiles.Items.Clear;
        UpdateDynamicViews;
        NotifyDataChanged;
      end
      else
        MessageDlg('Failed to rename file: ' + FRpc.LastError, mtError, [mbOK], 0);
    end;
  finally
    NotifyModalEnd;
  end;
end;

procedure TDetailsPanel.BtnEditTrackersClick(Sender: TObject);
begin
  if FCurrentId <= 0 then Exit;
  NotifyModalStart;
  try
    if ShowEditTrackersDialog(Self, FRpc, FOwnedTorrent) then
    begin
      RefreshDetails;
      NotifyDataChanged;
    end;
  finally
    NotifyModalEnd;
  end;
end;

procedure TDetailsPanel.BtnAddTrackerClick(Sender: TObject);
var
  NewUrl: string;
  Args: TJSONObject;
  Arr: TJSONArray;
begin
  if FCurrentId <= 0 then Exit;
  NewUrl := '';
  NotifyModalStart;
  try
    if InputQuery('Add Tracker', 'Enter tracker announce URL:', NewUrl) and (Trim(NewUrl) <> '') then
    begin
      Args := TJSONObject.Create;
      Arr := TJSONArray.Create;
      Arr.Add(Trim(NewUrl));
      Args.Add('trackerAdd', Arr);
      if FRpc.SetTorrentOptions(FCurrentId, Args) then
      begin
        RefreshDetails;
        NotifyDataChanged;
      end
      else
        MessageDlg('Failed to add tracker: ' + FRpc.LastError, mtError, [mbOK], 0);
    end;
  finally
    NotifyModalEnd;
  end;
end;

procedure TDetailsPanel.BtnRemoveTrackerClick(Sender: TObject);
var
  Idx: Integer;
  Args: TJSONObject;
  Arr: TJSONArray;
begin
  if FCurrentId <= 0 then Exit;
  if (LvTrackers.Selected = nil) or (LvTrackers.Selected.Index > High(FOwnedTorrent.Trackers)) then
  begin
    NotifyModalStart;
    try
      MessageDlg('Select a tracker to remove first.', mtInformation, [mbOK], 0);
    finally
      NotifyModalEnd;
    end;
    Exit;
  end;
  Idx := LvTrackers.Selected.Index;
  Args := TJSONObject.Create;
  Arr := TJSONArray.Create;
  Arr.Add(FOwnedTorrent.Trackers[Idx].Id);
  Args.Add('trackerRemove', Arr);
  if FRpc.SetTorrentOptions(FCurrentId, Args) then
  begin
    RefreshDetails;
    NotifyDataChanged;
  end
  else
  begin
    NotifyModalStart;
    try
      MessageDlg('Failed to remove tracker: ' + FRpc.LastError, mtError, [mbOK], 0);
    finally
      NotifyModalEnd;
    end;
  end;
end;

procedure TDetailsPanel.BtnToggleTrackerHttpsClick(Sender: TObject);
var
  OldText, NewText: string;
  Args: TJSONObject;
begin
  if (FCurrentId <= 0) or (Length(FOwnedTorrent.Trackers) = 0) then Exit;
  OldText := FormatTrackersAsText(FOwnedTorrent);
  NewText := TransformTrackerUrls(OldText, 0);
  if NewText = OldText then Exit;
  Args := TJSONObject.Create;
  Args.Add('trackerList', NewText);
  if FRpc.SetTorrentOptions(FCurrentId, Args) then
  begin
    RefreshDetails;
    NotifyDataChanged;
  end
  else
  begin
    NotifyModalStart;
    try
      MessageDlg('Failed to update trackers: ' + FRpc.LastError + LineEnding + LineEnding +
        'daemon ที่เชื่อมต่ออยู่อาจเป็นเวอร์ชันเก่าที่ไม่รองรับ ht..tps:// ' +
        '(เช่นมีไฟล์ transmission-daemon.exe เก่าวางข้างโปรแกรม หรือมี daemon อื่นเปิดค้างที่พอร์ต 9091) ' +
        'ให้ปิดโปรแกรม ลบ/ปิด daemon ตัวเก่า แล้วเปิดใหม่', mtError, [mbOK], 0);
    finally
      NotifyModalEnd;
    end;
  end;
end;

procedure TDetailsPanel.BtnBlockTrkPacketsClick(Sender: TObject);
var
  EffPaused, NextPaused: Boolean;
  SessArgs: TJSONObject;
begin
  if FCurrentId <= 0 then Exit;
  EffPaused := FOwnedTorrent.TrackerPaused or FGlobalTrackerPaused;
  NextPaused := not EffPaused;

  // หากอยู่ในหน้าต่างหลัก ให้ TMainForm ซิงค์ทั้งปุ่มในแท็บ Trackers และปุ่มบน StatusBar พร้อมกันทันที
  if Assigned(FOnRequestGlobalTrackerUnpause) then
  begin
    FOnRequestGlobalTrackerUnpause(Self);
    Exit;
  end;

  // กรณีเปิดในหน้าต่าง Properties แยก (ShowDetailsDialog) ให้ซิงค์ทั้งระดับทอร์เรนต์และเซสชันพร้อมกัน
  SetUnifiedPausedState(NextPaused);
  SessArgs := TJSONObject.Create;
  SessArgs.Add('tracker_paused', NextPaused);
  FRpc.UpdateSession(SessArgs);
  if FRpc.SetTorrentsTrackerPaused([FCurrentId], NextPaused) then
  begin
    SetUnifiedPausedState(NextPaused);
    NotifyDataChanged;
  end
  else
  begin
    SetUnifiedPausedState(EffPaused);
    NotifyModalStart;
    try
      MessageDlg('Failed to toggle tracker packet state: ' + FRpc.LastError, mtError, [mbOK], 0);
    finally
      NotifyModalEnd;
    end;
  end;
end;

procedure TDetailsPanel.ChkAutoPauseTrkClick(Sender: TObject);
begin
  if FSyncingTrkChk or (FCurrentId <= 0) then Exit;
  if FRpc.SetTorrentsTrackerAutoPause([FCurrentId], ChkAutoPauseTrk.Checked) then
  begin
    RefreshDetails;
    NotifyDataChanged;
  end
  else
  begin
    FSyncingTrkChk := True;
    try
      ChkAutoPauseTrk.Checked := FOwnedTorrent.TrackerAutoPause;
    finally
      FSyncingTrkChk := False;
    end;
    NotifyModalStart;
    try
      MessageDlg('Failed to update auto-pause setting: ' + FRpc.LastError, mtError, [mbOK], 0);
    finally
      NotifyModalEnd;
    end;
  end;
end;

procedure ShowDetailsDialog(Owner: TComponent; Rpc: TTransmissionRpcClient;
  Torrent: TTorrentItem);
var
  F: TDetailsForm;
  BtnClose: TButton;
  PnlBottom: TPanel;
begin
  if Torrent = nil then Exit;

  F := TDetailsForm.CreateNew(Owner);
  try
    F.Caption := Torrent.Name + ' Properties';
    F.Position := poMainFormCenter;
    F.BorderStyle := bsSizeable;
    F.ClientWidth := 920;
    F.ClientHeight := 455;
    F.Constraints.MinWidth := 780;
    F.Constraints.MinHeight := 400;

    PnlBottom := TPanel.Create(F);
    PnlBottom.Parent := F;
    PnlBottom.Align := alBottom;
    PnlBottom.Height := 42;
    PnlBottom.BevelOuter := bvNone;

    BtnClose := TButton.Create(PnlBottom);
    BtnClose.Parent := PnlBottom;
    BtnClose.Left := 816; BtnClose.Top := 8; BtnClose.Width := 88;
    BtnClose.Anchors := [akRight, akTop];
    BtnClose.Caption := 'Close';
    BtnClose.Cancel := True;
    BtnClose.ModalResult := mrClose;

    F.DetailsPanel := TDetailsPanel.CreatePanel(F, Rpc);
    F.DetailsPanel.Parent := F;
    F.DetailsPanel.Align := alClient;
    F.DetailsPanel.LoadTorrent(Torrent.Id);

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
  { หน้าต่าง Options / Preferences สไตล์ BitComet (แถบหมวดหมู่ซ้าย + หัวข้อแถบน้ำเงิน + GroupBox ขวา + OK / Cancel / Apply) }
  TPrefsForm = class(TForm)
  public
    RpcRef: TTransmissionRpcClient;
    WebSrvRef: TTransmissionWebServer;
    ConfigPtr: ^TSessionConfig;
    DesktopPtr: ^TDesktopPrefs;
    OnApplyCb: TNotifyEvent;
    AppliedOnce: Boolean;

    LstCategories: TListBox;
    PnlBanner: TPanel;
    LblBanner: TLabel;
    Pages: array[0..7] of TScrollBox;

    // 0: Connection
    ChkUpLimit: TCheckBox;
    SpnUpLimit: TSpinEdit;
    ChkDownLimit: TCheckBox;
    SpnDownLimit: TSpinEdit;
    ChkAltEnabled: TCheckBox;
    SpnAltUp: TSpinEdit;
    SpnAltDown: TSpinEdit;
    SpnPeerPort: TSpinEdit;
    LblPortStatus: TLabel;
    ChkRandomPort: TCheckBox;
    ChkPortForwarding: TCheckBox;
    ChkUtp: TCheckBox;

    // 1: Directories
    EdtDownloadDir: TEdit;
    ChkIncompleteDir: TCheckBox;
    EdtIncompleteDir: TEdit;
    ChkRenamePartial: TCheckBox;
    ChkWatchDir: TCheckBox;
    EdtWatchDir: TEdit;
    ChkWatchDelete: TCheckBox;
    EdtDataDir: TEdit;

    // 2: Tasks (เหมือนภาพตัวอย่าง BitComet)
    ChkStartAdded: TCheckBox;
    ChkTrashTorrent: TCheckBox;
    ChkRenamePartialTask: TCheckBox;
    ChkPreventSleep: TCheckBox;
    ChkFinishSound: TCheckBox;
    ChkFinishNotify: TCheckBox;
    ChkQueueDown: TCheckBox;
    SpnQueueDown: TSpinEdit;
    ChkQueueSeed: TCheckBox;
    SpnQueueSeed: TSpinEdit;
    SpnCacheSizeMiB: TSpinEdit;

    // 3: BitTorrent
    CmbEncryption: TComboBox;
    ChkPex: TCheckBox;
    ChkDht: TCheckBox;
    ChkLpd: TCheckBox;
    SpnPeerGlobal: TSpinEdit;
    SpnPeerPerTorrent: TSpinEdit;
    ChkBlockTrackers: TCheckBox;
    ChkAutoPauseTrackers: TCheckBox;

    // 4: Seeding Rules
    ChkRatioLimit: TCheckBox;
    EdtRatioLimit: TEdit;
    ChkIdleLimit: TCheckBox;
    SpnIdleLimit: TSpinEdit;

    // 5: IP Filter / Blocklist
    ChkBlocklist: TCheckBox;
    EdtBlocklistUrl: TEdit;
    LblBlocklistRules: TLabel;

    // 6: Remote / Web UI
    ChkWebEnabled: TCheckBox;
    SpnWebPort: TSpinEdit;
    ChkWebAuth: TCheckBox;
    EdtWebUser: TEdit;
    EdtWebPass: TEdit;

    // 7: Appearance & Startup
    ChkAutoStart: TCheckBox;
    ChkStartMinimized: TCheckBox;
    RbCloseExit: TRadioButton;
    RbCloseTray: TRadioButton;
    ChkAssocTorrent: TCheckBox;
    ChkAssocMagnet: TCheckBox;

    procedure LstCategoriesClick(Sender: TObject);
    procedure LstCategoriesDrawItem(Control: TWinControl; Index: Integer;
      ARect: TRect; State: TOwnerDrawState);
    procedure SwitchCategory(Idx: Integer);
    procedure BtnBrowseSaveDirClick(Sender: TObject);
    procedure BtnBrowseIncDirClick(Sender: TObject);
    procedure BtnBrowseWatchDirClick(Sender: TObject);
    procedure BtnBrowseDataDirClick(Sender: TObject);
    procedure BtnTestPortClick(Sender: TObject);
    procedure BtnUpdateBlocklistClick(Sender: TObject);
    procedure BtnOpenWebClientClick(Sender: TObject);
    procedure ChkAutoStartChange(Sender: TObject);
    procedure SyncPartialCheck(Sender: TObject);
    procedure ApplySettings;
    procedure BtnApplyClick(Sender: TObject);
  end;

procedure TPrefsForm.SwitchCategory(Idx: Integer);
var
  I: Integer;
begin
  if (Idx < 0) or (Idx > High(Pages)) then Exit;
  for I := 0 to High(Pages) do
    if Pages[I] <> nil then
      Pages[I].Visible := (I = Idx);
  if (LstCategories <> nil) and (Idx < LstCategories.Items.Count) then
    LblBanner.Caption := '  ' + StringReplace(LstCategories.Items[Idx], '&', '&&', [rfReplaceAll]);
end;

procedure TPrefsForm.LstCategoriesClick(Sender: TObject);
begin
  if LstCategories.ItemIndex >= 0 then
    SwitchCategory(LstCategories.ItemIndex);
end;

procedure TPrefsForm.LstCategoriesDrawItem(Control: TWinControl; Index: Integer;
  ARect: TRect; State: TOwnerDrawState);
var
  C: TCanvas;
  TextStr: string;
  IsSel: Boolean;
  PillR: TRect;
begin
  C := LstCategories.Canvas;
  IsSel := odSelected in State;
  C.Brush.Style := bsSolid;
  C.Brush.Color := RGBToColor(248, 250, 252);
  C.FillRect(ARect);

  if IsSel then
  begin
    PillR := Rect(ARect.Left + 6, ARect.Top + 2, ARect.Right - 6, ARect.Bottom - 2);
    C.Brush.Color := RGBToColor(37, 99, 235);
    C.Pen.Style := psClear;
    C.RoundRect(PillR.Left, PillR.Top, PillR.Right, PillR.Bottom, 8, 8);
    C.Pen.Style := psSolid;
    C.Font.Color := clWhite;
    C.Font.Style := [fsBold];
  end
  else
  begin
    C.Font.Color := RGBToColor(51, 65, 85);
    C.Font.Style := [];
  end;
  C.Brush.Style := bsClear;
  TextStr := LstCategories.Items[Index];
  C.TextOut(ARect.Left + 16, ARect.Top + ((ARect.Bottom - ARect.Top - C.TextHeight('Hg')) div 2), TextStr);
end;

procedure TPrefsForm.BtnBrowseSaveDirClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := EdtDownloadDir.Text;
  if SelectDirectory('Select Default Save Folder', '', Dir) then
    EdtDownloadDir.Text := Dir;
end;

procedure TPrefsForm.BtnBrowseIncDirClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := EdtIncompleteDir.Text;
  if SelectDirectory('Select Incomplete Folder', '', Dir) then
    EdtIncompleteDir.Text := Dir;
end;

procedure TPrefsForm.BtnBrowseWatchDirClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := EdtWatchDir.Text;
  if SelectDirectory('Select Watch Folder for .torrent files', '', Dir) then
    EdtWatchDir.Text := Dir;
end;

procedure TPrefsForm.BtnBrowseDataDirClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := EdtDataDir.Text;
  if SelectDirectory('Select Persistent Data & History Folder (ควรเลือกนอกไดรฟ์ C:)', '', Dir) then
    EdtDataDir.Text := Dir;
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

procedure TPrefsForm.ChkAutoStartChange(Sender: TObject);
begin
  if ChkStartMinimized <> nil then
    ChkStartMinimized.Enabled := ChkAutoStart.Checked;
end;

procedure TPrefsForm.SyncPartialCheck(Sender: TObject);
begin
  if Sender = ChkRenamePartial then
  begin
    if ChkRenamePartialTask <> nil then
      ChkRenamePartialTask.Checked := ChkRenamePartial.Checked;
  end
  else if Sender = ChkRenamePartialTask then
  begin
    if ChkRenamePartial <> nil then
      ChkRenamePartial.Checked := ChkRenamePartialTask.Checked;
  end;
end;

procedure TPrefsForm.ApplySettings;
var
  Args: TJSONObject;
begin
  DesktopPtr^.MinimizeToTray := RbCloseTray.Checked;
  DesktopPtr^.PreventSleepWhenActive := ChkPreventSleep.Checked;
  DesktopPtr^.PlaySoundOnFinish := ChkFinishSound.Checked;
  DesktopPtr^.ShowNotifyOnFinish := ChkFinishNotify.Checked;
  DesktopPtr^.WatchDirEnabled := ChkWatchDir.Checked;
  DesktopPtr^.WatchDir := Trim(EdtWatchDir.Text);
  DesktopPtr^.WatchDirDeleteOriginal := ChkWatchDelete.Checked;
  if Trim(EdtDataDir.Text) <> '' then
    DesktopPtr^.DataDir := Trim(EdtDataDir.Text);
  SetWindowsAutoStart(ChkAutoStart.Checked, ChkStartMinimized.Checked);
  SetTorrentFileAssociation(ChkAssocTorrent.Checked);
  SetMagnetProtocolAssociation(ChkAssocMagnet.Checked);

  Args := TJSONObject.Create;
  Args.Add('speed-limit-up-enabled', ChkUpLimit.Checked);
  Args.Add('speed-limit-up', SpnUpLimit.Value);
  Args.Add('speed-limit-down-enabled', ChkDownLimit.Checked);
  Args.Add('speed-limit-down', SpnDownLimit.Value);
  Args.Add('alt-speed-enabled', ChkAltEnabled.Checked);
  Args.Add('alt-speed-up', SpnAltUp.Value);
  Args.Add('alt-speed-down', SpnAltDown.Value);
  if Trim(EdtDownloadDir.Text) <> '' then
    SaveDestinationDirToHistory(Trim(EdtDownloadDir.Text));
  Args.Add('download-dir', StringReplace(EdtDownloadDir.Text, '\', '/', [rfReplaceAll]));
  Args.Add('start-added-torrents', ChkStartAdded.Checked);
  Args.Add('trash-original-torrent-files', ChkTrashTorrent.Checked);
  Args.Add('rename-partial-files', ChkRenamePartialTask.Checked);
  Args.Add('incomplete-dir-enabled', ChkIncompleteDir.Checked);
  Args.Add('incomplete-dir', StringReplace(EdtIncompleteDir.Text, '\', '/', [rfReplaceAll]));
  Args.Add('download-queue-enabled', ChkQueueDown.Checked);
  Args.Add('download-queue-size', SpnQueueDown.Value);
  Args.Add('seed-queue-enabled', ChkQueueSeed.Checked);
  Args.Add('seed-queue-size', SpnQueueSeed.Value);
  Args.Add('cache_size_mib', SpnCacheSizeMiB.Value);
  Args.Add('seedRatioLimited', ChkRatioLimit.Checked);
  Args.Add('seedRatioLimit', StrToFloatDef(EdtRatioLimit.Text, 2.0));
  Args.Add('idle-seeding-limit-enabled', ChkIdleLimit.Checked);
  Args.Add('idle-seeding-limit', SpnIdleLimit.Value);
  case CmbEncryption.ItemIndex of
    0: Args.Add('encryption', 'tolerated');
    2: Args.Add('encryption', 'required');
  else
    Args.Add('encryption', 'preferred');
  end;
  Args.Add('pex-enabled', ChkPex.Checked);
  Args.Add('dht-enabled', ChkDht.Checked);
  Args.Add('lpd-enabled', ChkLpd.Checked);
  Args.Add('blocklist-enabled', ChkBlocklist.Checked);
  Args.Add('blocklist-url', EdtBlocklistUrl.Text);
  Args.Add('peer-port', SpnPeerPort.Value);
  Args.Add('peer-port-random-on-start', ChkRandomPort.Checked);
  Args.Add('port-forwarding-enabled', ChkPortForwarding.Checked);
  Args.Add('utp-enabled', ChkUtp.Checked);
  Args.Add('peer-limit-per-torrent', SpnPeerPerTorrent.Value);
  Args.Add('peer-limit-global', SpnPeerGlobal.Value);
  Args.Add('tracker_paused', ChkBlockTrackers.Checked);
  Args.Add('tracker_auto_pause', ChkAutoPauseTrackers.Checked);

  RpcRef.UpdateSession(Args);
  RpcRef.FetchSession(ConfigPtr^);

  if WebSrvRef <> nil then
  begin
    WebSrvRef.Enabled := ChkWebEnabled.Checked;
    WebSrvRef.Port := SpnWebPort.Value;
    WebSrvRef.AuthEnabled := ChkWebAuth.Checked;
    WebSrvRef.Username := Trim(EdtWebUser.Text);
    WebSrvRef.Password := EdtWebPass.Text;
    WebSrvRef.RestartServer;
  end;

  AppliedOnce := True;
  if Assigned(OnApplyCb) then
    OnApplyCb(Self);
end;

procedure TPrefsForm.BtnApplyClick(Sender: TObject);
begin
  ApplySettings;
end;

function ShowPrefsDialog(Owner: TComponent; Rpc: TTransmissionRpcClient;
  WebSrv: TTransmissionWebServer; var Config: TSessionConfig;
  var DesktopPrefs: TDesktopPrefs; OnApplyCallback: TNotifyEvent = nil): Boolean;
var
  F: TPrefsForm;
  PnlNav, PnlRight, PnlPageHost: TPanel;
  DivLine: TBevel;
  Gb1, Gb2, Gb3, Gb4: TGroupBox;
  Lbl: TLabel;
  BtnBrowse, BtnBrowseInc, BtnBrowseWatch, BtnBrowseData, BtnTestPort, BtnUpdBlk, BtnOpenWeb, BtnOK, BtnCancel, BtnApply: TButton;
  AutoStartOn, AutoStartMin: Boolean;
  I: Integer;

  function MakeGroup(ParentPage: TWinControl; ATop, AHeight: Integer; const ACaption: string): TGroupBox;
  begin
    Result := TGroupBox.Create(ParentPage);
    Result.Parent := ParentPage;
    Result.Left := 8;
    Result.Top := ATop;
    Result.Width := 564;
    Result.Height := AHeight;
    Result.Caption := ACaption;
  end;

  function MakeCheck(ParentGrp: TWinControl; ALeft, ATop: Integer; const ACaption: string; AChecked: Boolean): TCheckBox;
  begin
    Result := TCheckBox.Create(ParentGrp);
    Result.Parent := ParentGrp;
    Result.Left := ALeft;
    Result.Top := ATop;
    Result.Caption := ACaption;
    Result.Checked := AChecked;
  end;

  function MakeLabel(ParentCtrl: TWinControl; ALeft, ATop: Integer; const ACaption: string): TLabel;
  begin
    Result := TLabel.Create(ParentCtrl);
    Result.Parent := ParentCtrl;
    Result.Left := ALeft;
    Result.Top := ATop;
    Result.Caption := ACaption;
  end;

  function MakeSpin(ParentCtrl: TWinControl; ALeft, ATop, AWidth, AMin, AMax, AVal: Integer): TSpinEdit;
  begin
    Result := TSpinEdit.Create(ParentCtrl);
    Result.Parent := ParentCtrl;
    Result.Left := ALeft;
    Result.Top := ATop;
    Result.Width := AWidth;
    Result.MinValue := AMin;
    Result.MaxValue := AMax;
    Result.Value := EnsureRange(AVal, AMin, AMax);
  end;

begin
  Result := False;
  Rpc.FetchSession(Config);

  F := TPrefsForm.CreateNew(Owner);
  try
    F.RpcRef := Rpc;
    F.WebSrvRef := WebSrv;
    F.ConfigPtr := @Config;
    F.DesktopPtr := @DesktopPrefs;
    F.OnApplyCb := OnApplyCallback;
    F.AppliedOnce := False;
    F.Caption := 'Transmission Preferences';
    F.Position := poMainFormCenter;
    F.BorderStyle := bsDialog;
    F.ClientWidth := 820;
    F.ClientHeight := 580;
    F.Font.Name := 'Segoe UI';
    F.Font.Size := 9;
    F.Color := clWhite;

    // 1. แถบรายการหมวดหมู่ด้านซ้าย (สไตล์ Modern Slate)
    PnlNav := TPanel.Create(F);
    PnlNav.Parent := F;
    PnlNav.Left := 10; PnlNav.Top := 10; PnlNav.Width := 188; PnlNav.Height := 512;
    PnlNav.BevelOuter := bvNone;
    PnlNav.Color := RGBToColor(226, 232, 240);
    PnlNav.BorderWidth := 1;

    F.LstCategories := TListBox.Create(PnlNav);
    F.LstCategories.Parent := PnlNav;
    F.LstCategories.Align := alClient;
    F.LstCategories.BorderStyle := bsNone;
    F.LstCategories.Color := RGBToColor(248, 250, 252);
    F.LstCategories.Style := lbOwnerDrawFixed;
    F.LstCategories.ItemHeight := 34;
    F.LstCategories.OnDrawItem := @F.LstCategoriesDrawItem;
    F.LstCategories.OnClick := @F.LstCategoriesClick;
    F.LstCategories.Items.Add('Connection');
    F.LstCategories.Items.Add('Directories');
    F.LstCategories.Items.Add('Tasks');
    F.LstCategories.Items.Add('BitTorrent');
    F.LstCategories.Items.Add('Seeding Rules');
    F.LstCategories.Items.Add('IP Filter / Blocklist');
    F.LstCategories.Items.Add('Remote / Web UI');
    F.LstCategories.Items.Add('Appearance & Startup');

    // 2. พื้นที่เนื้อหาด้านขวา + แถบหัวข้อด้านบน
    PnlRight := TPanel.Create(F);
    PnlRight.Parent := F;
    PnlRight.Left := 208; PnlRight.Top := 10; PnlRight.Width := 602; PnlRight.Height := 512;
    PnlRight.BevelOuter := bvNone;
    PnlRight.Color := clWhite;

    F.PnlBanner := TPanel.Create(PnlRight);
    F.PnlBanner.Parent := PnlRight;
    F.PnlBanner.Align := alTop;
    F.PnlBanner.Height := 36;
    F.PnlBanner.BevelOuter := bvNone;
    F.PnlBanner.Color := RGBToColor(30, 64, 175);

    F.LblBanner := TLabel.Create(F.PnlBanner);
    F.LblBanner.Parent := F.PnlBanner;
    F.LblBanner.Left := 8; F.LblBanner.Top := 6;
    F.LblBanner.Font.Color := clWhite;
    F.LblBanner.Font.Size := 12;
    F.LblBanner.Font.Style := [fsBold];
    F.LblBanner.Caption := '  Connection';

    PnlPageHost := TPanel.Create(PnlRight);
    PnlPageHost.Parent := PnlRight;
    PnlPageHost.Align := alClient;
    PnlPageHost.BevelOuter := bvNone;
    PnlPageHost.Color := clWhite;

    for I := 0 to High(F.Pages) do
    begin
      F.Pages[I] := TScrollBox.Create(PnlPageHost);
      F.Pages[I].Parent := PnlPageHost;
      F.Pages[I].Align := alClient;
      F.Pages[I].BorderStyle := bsNone;
      F.Pages[I].Color := clWhite;
      F.Pages[I].VertScrollBar.Tracking := True;
      F.Pages[I].HorzScrollBar.Visible := False;
      F.Pages[I].Visible := False;
    end;

    // --- Page 0: Connection ---
    Gb1 := MakeGroup(F.Pages[0], 10, 206, 'Bandwidth && Turtle Mode');
    F.ChkUpLimit := MakeCheck(Gb1, 14, 14, 'Global max upload speed (KB/s):', Config.SpeedLimitUpEnabled);
    F.SpnUpLimit := MakeSpin(Gb1, 310, 10, 100, 0, 1000000, Config.SpeedLimitUp);
    F.ChkDownLimit := MakeCheck(Gb1, 14, 48, 'Global max download speed (KB/s):', Config.SpeedLimitDownEnabled);
    F.SpnDownLimit := MakeSpin(Gb1, 310, 44, 100, 0, 1000000, Config.SpeedLimitDown);
    F.ChkAltEnabled := MakeCheck(Gb1, 14, 84, 'Enable Alternative Speed Limits (Turtle Mode) now', Config.AltSpeedEnabled);
    MakeLabel(Gb1, 34, 118, 'Alt upload limit (KB/s):');
    F.SpnAltUp := MakeSpin(Gb1, 310, 114, 100, 0, 1000000, Config.AltSpeedUp);
    MakeLabel(Gb1, 34, 152, 'Alt download limit (KB/s):');
    F.SpnAltDown := MakeSpin(Gb1, 310, 148, 100, 0, 1000000, Config.AltSpeedDown);

    Gb2 := MakeGroup(F.Pages[0], 226, 178, 'Listen Port && Router Mapping');
    MakeLabel(Gb2, 14, 18, 'BitTorrent listening port:');
    F.SpnPeerPort := MakeSpin(Gb2, 196, 14, 92, 1, 65535, Config.PeerPort);
    BtnTestPort := TButton.Create(Gb2);
    BtnTestPort.Parent := Gb2;
    BtnTestPort.Left := 298; BtnTestPort.Top := 12; BtnTestPort.Width := 96; BtnTestPort.Height := 27;
    BtnTestPort.Caption := 'Test Port';
    BtnTestPort.OnClick := @F.BtnTestPortClick;
    F.LblPortStatus := MakeLabel(Gb2, 404, 18, '');
    F.LblPortStatus.Font.Style := [fsBold];
    F.ChkRandomPort := MakeCheck(Gb2, 14, 54, 'Pick a random listening port on startup', Config.PeerPortRandomOnStart);
    F.ChkPortForwarding := MakeCheck(Gb2, 14, 84, 'Enable UPnP / NAT-PMP port forwarding', Config.PortForwardingEnabled);
    F.ChkUtp := MakeCheck(Gb2, 14, 114, 'Enable µTP (Micro Transport Protocol)', Config.UtpEnabled);

    // --- Page 1: Directories ---
    Gb1 := MakeGroup(F.Pages[1], 10, 96, 'Default Download Directory');
    MakeLabel(Gb1, 14, 10, 'Save downloaded files to:');
    F.EdtDownloadDir := TEdit.Create(Gb1);
    F.EdtDownloadDir.Parent := Gb1;
    F.EdtDownloadDir.Left := 14; F.EdtDownloadDir.Top := 34; F.EdtDownloadDir.Width := 436;
    F.EdtDownloadDir.Text := Config.DownloadDir;
    BtnBrowse := TButton.Create(Gb1);
    BtnBrowse.Parent := Gb1;
    BtnBrowse.Left := 460; BtnBrowse.Top := 32; BtnBrowse.Width := 88; BtnBrowse.Height := 27;
    BtnBrowse.Caption := 'Browse...';
    BtnBrowse.OnClick := @F.BtnBrowseSaveDirClick;

    Gb2 := MakeGroup(F.Pages[1], 116, 132, 'Temporary / Incomplete Files');
    F.ChkIncompleteDir := MakeCheck(Gb2, 14, 10, 'Store incomplete downloads in temporary folder:', Config.IncompleteDirEnabled);
    F.EdtIncompleteDir := TEdit.Create(Gb2);
    F.EdtIncompleteDir.Parent := Gb2;
    F.EdtIncompleteDir.Left := 14; F.EdtIncompleteDir.Top := 38; F.EdtIncompleteDir.Width := 436;
    F.EdtIncompleteDir.Text := Config.IncompleteDir;
    BtnBrowseInc := TButton.Create(Gb2);
    BtnBrowseInc.Parent := Gb2;
    BtnBrowseInc.Left := 460; BtnBrowseInc.Top := 36; BtnBrowseInc.Width := 88; BtnBrowseInc.Height := 27;
    BtnBrowseInc.Caption := 'Browse...';
    BtnBrowseInc.OnClick := @F.BtnBrowseIncDirClick;
    F.ChkRenamePartial := MakeCheck(Gb2, 14, 72, 'Append ".part" file extension to unfinished files', Config.RenamePartialFiles);
    F.ChkRenamePartial.OnChange := @F.SyncPartialCheck;

    Gb3 := MakeGroup(F.Pages[1], 258, 132, 'Watch Folder (โฟลเดอร์เฝ้าดูไฟล์ .torrent อัตโนมัติ)');
    F.ChkWatchDir := MakeCheck(Gb3, 14, 10, 'Automatically add .torrent files from Watch Folder:', DesktopPrefs.WatchDirEnabled);
    F.EdtWatchDir := TEdit.Create(Gb3);
    F.EdtWatchDir.Parent := Gb3;
    F.EdtWatchDir.Left := 14; F.EdtWatchDir.Top := 38; F.EdtWatchDir.Width := 436;
    F.EdtWatchDir.Text := DesktopPrefs.WatchDir;
    BtnBrowseWatch := TButton.Create(Gb3);
    BtnBrowseWatch.Parent := Gb3;
    BtnBrowseWatch.Left := 460; BtnBrowseWatch.Top := 36; BtnBrowseWatch.Width := 88; BtnBrowseWatch.Height := 27;
    BtnBrowseWatch.Caption := 'Browse...';
    BtnBrowseWatch.OnClick := @F.BtnBrowseWatchDirClick;
    F.ChkWatchDelete := MakeCheck(Gb3, 14, 72, 'Delete .torrent file after adding (otherwise rename to .added)', DesktopPrefs.WatchDirDeleteOriginal);

    Gb4 := MakeGroup(F.Pages[1], 400, 144, 'Persistent Data && History Folder (เก็บประวัติข้ามการล้าง Windows)');
    MakeLabel(Gb4, 14, 10, 'Config, Torrents, Resume && History directory (ควรวางไว้นอกไดรฟ์ C:):');
    F.EdtDataDir := TEdit.Create(Gb4);
    F.EdtDataDir.Parent := Gb4;
    F.EdtDataDir.Left := 14; F.EdtDataDir.Top := 36; F.EdtDataDir.Width := 436;
    if Trim(DesktopPrefs.DataDir) <> '' then
      F.EdtDataDir.Text := DesktopPrefs.DataDir
    else
      F.EdtDataDir.Text := GetDefaultPortableDataDir;
    BtnBrowseData := TButton.Create(Gb4);
    BtnBrowseData.Parent := Gb4;
    BtnBrowseData.Left := 460; BtnBrowseData.Top := 34; BtnBrowseData.Width := 88; BtnBrowseData.Height := 27;
    BtnBrowseData.Caption := 'Browse...';
    BtnBrowseData.OnClick := @F.BtnBrowseDataDirClick;
    Lbl := MakeLabel(Gb4, 14, 70, 'ค่าเริ่มต้นเป็นแบบ Portable (.\data ข้างตัวโปรแกรม) — หากเปลี่ยนโฟลเดอร์ใหม่จะมีผลหลังเปิดโปรแกรมใหม่');
    Lbl.Width := 534;
    Lbl.Height := 42;
    Lbl.AutoSize := False;
    Lbl.WordWrap := True;
    Lbl.Font.Color := clGrayText;

    // --- Page 2: Tasks (คล้ายหน้า Tasks ของ BitComet) ---
    Gb1 := MakeGroup(F.Pages[2], 10, 152, 'Download');
    F.ChkStartAdded := MakeCheck(Gb1, 14, 12, 'Auto-start added tasks immediately', Config.StartAddedTorrents);
    F.ChkRenamePartialTask := MakeCheck(Gb1, 14, 40, 'Add ".part" file extension to unfinished files', Config.RenamePartialFiles);
    F.ChkRenamePartialTask.OnChange := @F.SyncPartialCheck;
    F.ChkTrashTorrent := MakeCheck(Gb1, 14, 68, 'Move original .torrent file to Recycle Bin after adding', Config.TrashOriginalTorrentFiles);
    F.ChkPreventSleep := MakeCheck(Gb1, 14, 96, 'Avoid system entering suspend/sleeping mode when any task is running', DesktopPrefs.PreventSleepWhenActive);

    Gb2 := MakeGroup(F.Pages[2], 172, 96, 'When Download Finished');
    F.ChkFinishSound := MakeCheck(Gb2, 14, 12, 'Play sound when task finished', DesktopPrefs.PlaySoundOnFinish);
    F.ChkFinishNotify := MakeCheck(Gb2, 14, 40, 'Display notification when task finished', DesktopPrefs.ShowNotifyOnFinish);

    Gb3 := MakeGroup(F.Pages[2], 278, 108, 'Task Queue');
    F.ChkQueueDown := MakeCheck(Gb3, 14, 16, 'Maximum number of concurrent downloading BitTorrent tasks:', Config.DownloadQueueEnabled);
    F.SpnQueueDown := MakeSpin(Gb3, 444, 12, 92, 1, 200, Config.DownloadQueueSize);
    F.ChkQueueSeed := MakeCheck(Gb3, 14, 50, 'Maximum number of concurrent seeding BitTorrent tasks:', Config.SeedQueueEnabled);
    F.SpnQueueSeed := MakeSpin(Gb3, 444, 46, 92, 1, 200, Config.SeedQueueSize);

    Gb4 := MakeGroup(F.Pages[2], 396, 76, 'Disk RAM Cache (แคชอ่าน/เขียนดิสก์ใน RAM)');
    MakeLabel(Gb4, 14, 18, 'RAM Disk Cache Size (MiB, 0 = OS Cache only):');
    F.SpnCacheSizeMiB := MakeSpin(Gb4, 360, 14, 96, 0, 4096, Config.CacheSizeMiB);
    MakeLabel(Gb4, 464, 18, 'MiB');

    // --- Page 3: BitTorrent ---
    Gb1 := MakeGroup(F.Pages[3], 10, 174, 'Protocol && Peer Discovery');
    MakeLabel(Gb1, 14, 18, 'Protocol encryption mode:');
    F.CmbEncryption := TComboBox.Create(Gb1);
    F.CmbEncryption.Parent := Gb1;
    F.CmbEncryption.Left := 196; F.CmbEncryption.Top := 14; F.CmbEncryption.Width := 220;
    F.CmbEncryption.Style := csDropDownList;
    F.CmbEncryption.Items.Add('Allow encryption (Tolerated)');
    F.CmbEncryption.Items.Add('Prefer encryption (Default)');
    F.CmbEncryption.Items.Add('Require encryption (Strict)');
    if Config.Encryption = 'required' then
      F.CmbEncryption.ItemIndex := 2
    else if Config.Encryption = 'tolerated' then
      F.CmbEncryption.ItemIndex := 0
    else
      F.CmbEncryption.ItemIndex := 1;
    F.ChkPex := MakeCheck(Gb1, 14, 52, 'Enable Peer Exchange (PEX) for public torrents', Config.PexEnabled);
    F.ChkDht := MakeCheck(Gb1, 14, 82, 'Enable Distributed Hash Table (DHT) Network', Config.DhtEnabled);
    F.ChkLpd := MakeCheck(Gb1, 14, 112, 'Enable Local Peer Discovery (LPD)', Config.LpdEnabled);

    Gb2 := MakeGroup(F.Pages[3], 194, 182, 'Peer Limits && Tracker Packet Control');
    MakeLabel(Gb2, 14, 18, 'Max peers per torrent:');
    F.SpnPeerPerTorrent := MakeSpin(Gb2, 224, 14, 96, 1, 2000, Config.PeerLimitPerTorrent);
    MakeLabel(Gb2, 14, 52, 'Global max peer connections:');
    F.SpnPeerGlobal := MakeSpin(Gb2, 224, 48, 96, 1, 5000, Config.PeerLimitGlobal);
    F.ChkBlockTrackers := MakeCheck(Gb2, 14, 90, 'Block ALL outgoing tracker packets globally (No Tracker Mode)', Config.TrackerPaused);
    F.ChkAutoPauseTrackers := MakeCheck(Gb2, 14, 120, 'Get peers once, then auto-pause tracker packets (ดึง Peer รอบแรกแล้วหยุดส่ง)', Config.TrackerAutoPause);

    // --- Page 4: Seeding Rules ---
    Gb1 := MakeGroup(F.Pages[4], 10, 126, 'Auto-Stop Seeding Conditions');
    F.ChkRatioLimit := MakeCheck(Gb1, 14, 18, 'Stop seeding when share ratio reaches:', Config.SeedRatioLimited);
    F.EdtRatioLimit := TEdit.Create(Gb1);
    F.EdtRatioLimit.Parent := Gb1;
    F.EdtRatioLimit.Left := 306; F.EdtRatioLimit.Top := 14; F.EdtRatioLimit.Width := 96;
    F.EdtRatioLimit.Text := Format('%.2f', [Config.SeedRatioLimit]);
    F.ChkIdleLimit := MakeCheck(Gb1, 14, 58, 'Stop seeding if idle for (minutes):', Config.IdleSeedingLimited);
    F.SpnIdleLimit := MakeSpin(Gb1, 306, 54, 96, 1, 99999, Config.IdleSeedingLimit);

    // --- Page 5: IP Filter / Blocklist ---
    Gb1 := MakeGroup(F.Pages[5], 10, 152, 'Peer IP Blocklist');
    F.ChkBlocklist := MakeCheck(Gb1, 14, 14, 'Enable IP blocklist from URL:', Config.BlocklistEnabled);
    F.EdtBlocklistUrl := TEdit.Create(Gb1);
    F.EdtBlocklistUrl.Parent := Gb1;
    F.EdtBlocklistUrl.Left := 14; F.EdtBlocklistUrl.Top := 44; F.EdtBlocklistUrl.Width := 534;
    F.EdtBlocklistUrl.Text := Config.BlocklistUrl;
    F.LblBlocklistRules := MakeLabel(Gb1, 14, 88, Format('Current blocklist: %d IP rules loaded', [Config.BlocklistSize]));
    BtnUpdBlk := TButton.Create(Gb1);
    BtnUpdBlk.Parent := Gb1;
    BtnUpdBlk.Left := 418; BtnUpdBlk.Top := 82; BtnUpdBlk.Width := 130; BtnUpdBlk.Height := 28;
    BtnUpdBlk.Caption := 'Update Blocklist';
    BtnUpdBlk.OnClick := @F.BtnUpdateBlocklistClick;

    // --- Page 6: Remote / Web UI ---
    Gb1 := MakeGroup(F.Pages[6], 10, 114, 'Built-in Web Server');
    F.ChkWebEnabled := MakeCheck(Gb1, 14, 14, 'Allow remote web access (Built-in Web UI Server)',
      (WebSrv = nil) or WebSrv.Enabled);
    MakeLabel(Gb1, 34, 52, 'HTTP Listening Port:');
    if WebSrv <> nil then
      F.SpnWebPort := MakeSpin(Gb1, 186, 48, 96, 1, 65535, WebSrv.Port)
    else
      F.SpnWebPort := MakeSpin(Gb1, 186, 48, 96, 1, 65535, 9092);
    BtnOpenWeb := TButton.Create(Gb1);
    BtnOpenWeb.Parent := Gb1;
    BtnOpenWeb.Left := 296; BtnOpenWeb.Top := 46; BtnOpenWeb.Width := 148; BtnOpenWeb.Height := 27;
    BtnOpenWeb.Caption := 'Open Web Client';
    BtnOpenWeb.OnClick := @F.BtnOpenWebClientClick;

    Gb2 := MakeGroup(F.Pages[6], 134, 152, 'HTTP Authentication');
    F.ChkWebAuth := MakeCheck(Gb2, 14, 14, 'Require username and password',
      (WebSrv <> nil) and WebSrv.AuthEnabled);
    MakeLabel(Gb2, 34, 52, 'Username:');
    F.EdtWebUser := TEdit.Create(Gb2);
    F.EdtWebUser.Parent := Gb2;
    F.EdtWebUser.Left := 146; F.EdtWebUser.Top := 48; F.EdtWebUser.Width := 220;
    if WebSrv <> nil then F.EdtWebUser.Text := WebSrv.Username else F.EdtWebUser.Text := 'admin';
    MakeLabel(Gb2, 34, 88, 'Password:');
    F.EdtWebPass := TEdit.Create(Gb2);
    F.EdtWebPass.Parent := Gb2;
    F.EdtWebPass.Left := 146; F.EdtWebPass.Top := 84; F.EdtWebPass.Width := 220;
    F.EdtWebPass.PasswordChar := '*';
    if WebSrv <> nil then F.EdtWebPass.Text := WebSrv.Password;

    // --- Page 7: Appearance & Startup ---
    AutoStartOn := GetWindowsAutoStart(AutoStartMin);
    Gb1 := MakeGroup(F.Pages[7], 10, 102, 'Windows Startup');
    F.ChkAutoStart := MakeCheck(Gb1, 14, 14, 'Start automatically when signing in to Windows (เปิดอัตโนมัติ)', AutoStartOn);
    F.ChkAutoStart.OnChange := @F.ChkAutoStartChange;
    F.ChkStartMinimized := MakeCheck(Gb1, 34, 44, 'Start minimized to system tray (เริ่มแบบย่อไปมุมขวาล่าง)', AutoStartMin);
    F.ChkStartMinimized.Enabled := AutoStartOn;

    Gb2 := MakeGroup(F.Pages[7], 122, 162, 'Window Close Button Behavior (เมื่อกดปุ่มปิด X)');
    F.RbCloseExit := TRadioButton.Create(Gb2);
    F.RbCloseExit.Parent := Gb2;
    F.RbCloseExit.Left := 14; F.RbCloseExit.Top := 14;
    F.RbCloseExit.Caption := 'Exit program immediately (ปิดโปรแกรมทันที)';
    F.RbCloseExit.Checked := not DesktopPrefs.MinimizeToTray;

    F.RbCloseTray := TRadioButton.Create(Gb2);
    F.RbCloseTray.Parent := Gb2;
    F.RbCloseTray.Left := 14; F.RbCloseTray.Top := 42;
    F.RbCloseTray.Caption := 'Minimize to system tray (ย่อไปไว้มุมขวาล่าง)';
    F.RbCloseTray.Checked := DesktopPrefs.MinimizeToTray;

    Lbl := MakeLabel(Gb2, 14, 74,
      'คำแนะนำ: เมื่อเลือก "Minimize to system tray" การกดปุ่มปิด (X) จะซ่อนหน้าต่างลงไปที่มุมขวาล่าง ' +
      'โดยโปรแกรมยังคงทำงานต่อเบื้องหลัง ดับเบิลคลิกไอคอนเพื่อเปิดกลับ หรือคลิกขวาแล้วเลือก Quit เพื่อปิดถาวร');
    Lbl.Width := 534;
    Lbl.Height := 54;
    Lbl.AutoSize := False;
    Lbl.WordWrap := True;
    Lbl.Font.Color := clGrayText;

    Gb3 := MakeGroup(F.Pages[7], 294, 152, 'Windows File && Magnet Integration (ผูกไฟล์และลิงก์)');
    F.ChkAssocTorrent := MakeCheck(Gb3, 14, 14,
      'Associate .torrent files with Transmission (ดับเบิลคลิกเปิดไฟล์ .torrent)',
      GetTorrentFileAssociation);
    F.ChkAssocMagnet := MakeCheck(Gb3, 14, 44,
      'Associate magnet: links with Transmission (คลิกลิงก์ magnet: จากเบราว์เซอร์)',
      GetMagnetProtocolAssociation);
    Lbl := MakeLabel(Gb3, 14, 76,
      'บันทึกลง HKEY_CURRENT_USER (ไม่ต้องใช้สิทธิ์ Administrator) และเปิดเข้าหน้าต่างเดิมอัตโนมัติเมื่อเปิดซ้ำ');
    Lbl.Width := 534;
    Lbl.Height := 42;
    Lbl.AutoSize := False;
    Lbl.WordWrap := True;
    Lbl.Font.Color := clGrayText;

    // เปิดหน้า Connection (0) เป็นค่าเริ่มต้น
    F.LstCategories.ItemIndex := 0;
    F.SwitchCategory(0);

    // 3. เส้นแบ่งด้านล่างและปุ่ม OK / Cancel / Apply (สไตล์ BitComet)
    DivLine := TBevel.Create(F);
    DivLine.Parent := F;
    DivLine.Left := 10; DivLine.Top := 530; DivLine.Width := 800; DivLine.Height := 2;
    DivLine.Shape := bsTopLine;

    BtnOK := TButton.Create(F);
    BtnOK.Parent := F;
    BtnOK.Left := 538; BtnOK.Top := 540; BtnOK.Width := 86; BtnOK.Height := 30;
    BtnOK.Caption := 'OK';
    BtnOK.Default := True;
    BtnOK.ModalResult := mrOk;

    BtnCancel := TButton.Create(F);
    BtnCancel.Parent := F;
    BtnCancel.Left := 632; BtnCancel.Top := 540; BtnCancel.Width := 86; BtnCancel.Height := 30;
    BtnCancel.Caption := 'Cancel';
    BtnCancel.Cancel := True;
    BtnCancel.ModalResult := mrCancel;

    BtnApply := TButton.Create(F);
    BtnApply.Parent := F;
    BtnApply.Left := 726; BtnApply.Top := 540; BtnApply.Width := 86; BtnApply.Height := 30;
    BtnApply.Caption := 'Apply';
    BtnApply.OnClick := @F.BtnApplyClick;

    if F.ShowModal = mrOk then
    begin
      F.ApplySettings;
      Result := True;
    end
    else
      Result := F.AppliedOnce;
  finally
    F.Free;
  end;
end;

{ 8. Set Location / Relocate Dialog }

type
  TRelocateForm = class(TForm)
  public
    EdtDir: TComboBox;
    RbMove: TRadioButton;
    RbFind: TRadioButton;
    procedure BtnBrowseClick(Sender: TObject);
  end;

procedure TRelocateForm.BtnBrowseClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := Trim(EdtDir.Text);
  if SelectDirectory('Select New Torrent Location', '', Dir) then
  begin
    SaveDestinationDirToHistory(Dir);
    LoadDestinationDirHistory(EdtDir.Items, Dir);
    EdtDir.Text := Dir;
  end;
end;

function ShowRelocateDialog(Owner: TComponent; const CurrentDir: string;
  out NewDir: string; out MoveData: Boolean): Boolean;
var
  F: TRelocateForm;
  Lbl: TLabel;
  BtnBrowse, BtnOK, BtnCancel: TButton;
  InitDir: string;
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

    F.EdtDir := TComboBox.Create(F);
    F.EdtDir.Parent := F;
    F.EdtDir.Left := 16; F.EdtDir.Top := 36; F.EdtDir.Width := 340;
    F.EdtDir.Style := csDropDown;
    F.EdtDir.AutoComplete := True;
    F.EdtDir.DropDownCount := 12;
    InitDir := LoadDestinationDirHistory(F.EdtDir.Items, CurrentDir);
    if Trim(CurrentDir) <> '' then
      F.EdtDir.Text := CurrentDir
    else
      F.EdtDir.Text := InitDir;

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
      if NewDir <> '' then
        SaveDestinationDirToHistory(NewDir);
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
    F.ClientWidth := 430;
    F.ClientHeight := 360;
    F.Font.Name := 'Segoe UI';
    F.Font.Size := 9;
    F.Color := clWhite;

    GbCur := TGroupBox.Create(F);
    GbCur.Parent := F;
    GbCur.Left := 14; GbCur.Top := 12; GbCur.Width := 402; GbCur.Height := 142;
    GbCur.Caption := 'Current Session';

    F.LblCurUp := CreateKeyValLabel(GbCur, 10, 'Uploaded:', '0 B');
    F.LblCurDown := CreateKeyValLabel(GbCur, 34, 'Downloaded:', '0 B');
    F.LblCurRatio := CreateKeyValLabel(GbCur, 58, 'Ratio:', '0.00');
    F.LblCurDur := CreateKeyValLabel(GbCur, 82, 'Duration:', '0s');

    F.GbTot := TGroupBox.Create(F);
    F.GbTot.Parent := F;
    F.GbTot.Left := 14; F.GbTot.Top := 162; F.GbTot.Width := 402; F.GbTot.Height := 142;
    F.GbTot.Caption := 'Total';

    F.LblTotUp := CreateKeyValLabel(F.GbTot, 10, 'Uploaded:', '0 B');
    F.LblTotDown := CreateKeyValLabel(F.GbTot, 34, 'Downloaded:', '0 B');
    F.LblTotRatio := CreateKeyValLabel(F.GbTot, 58, 'Ratio:', '0.00');
    F.LblTotDur := CreateKeyValLabel(F.GbTot, 82, 'Total Duration:', '0s');

    BtnClose := TButton.Create(F);
    BtnClose.Parent := F;
    BtnClose.Left := 332; BtnClose.Top := 316; BtnClose.Width := 84; BtnClose.Height := 28;
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

{ ============================================================================ }
{ 10. Download History & Portable Backup Dialog                                }
{ ============================================================================ }
type
  THistoryForm = class(TForm)
  public
    FRpc: TTransmissionRpcClient;
    FHistory: TDownloadHistoryManager;
    FDataDir: string;
    FIniPath: string;
    FRestoredFromBackup: Boolean;

    PnlTop: TPanel;
    LblSearch: TLabel;
    EdtSearch: TEdit;
    LblSummary: TLabel;
    LvHistory: TListView;
    PnlBottom: TPanel;
    BtnReDownload: TButton;
    BtnCopyMagnet: TButton;
    BtnOpenFolder: TButton;
    BtnDelete: TButton;
    BtnClear: TButton;
    BtnExport: TButton;
    BtnImport: TButton;
    BtnClose: TButton;

    function GetSelectedHistoryItem: THistoryItem;
    function GetHistoryFilePath: string;
    procedure RefreshList;
    procedure UpdateButtons;
    procedure EdtSearchChange(Sender: TObject);
    procedure LvHistorySelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure LvHistoryDblClick(Sender: TObject);
    procedure BtnReDownloadClick(Sender: TObject);
    procedure BtnCopyMagnetClick(Sender: TObject);
    procedure BtnOpenFolderClick(Sender: TObject);
    procedure BtnDeleteClick(Sender: TObject);
    procedure BtnClearClick(Sender: TObject);
    procedure BtnExportClick(Sender: TObject);
    procedure BtnImportClick(Sender: TObject);
  end;

function THistoryForm.GetHistoryFilePath: string;
begin
  Result := IncludeTrailingPathDelimiter(FDataDir) + 'download_history.json';
end;

function THistoryForm.GetSelectedHistoryItem: THistoryItem;
begin
  Result := nil;
  if (LvHistory <> nil) and (LvHistory.Selected <> nil) and (LvHistory.Selected.Data <> nil) then
    Result := THistoryItem(LvHistory.Selected.Data);
end;

procedure THistoryForm.RefreshList;
var
  I, CompCount: Integer;
  H: THistoryItem;
  FilterStr: string;
  Li: TListItem;
begin
  if (FHistory = nil) or (LvHistory = nil) then Exit;
  FilterStr := LowerCase(Trim(EdtSearch.Text));
  CompCount := 0;

  LvHistory.Items.BeginUpdate;
  try
    LvHistory.Items.Clear;
    for I := 0 to FHistory.Count - 1 do
    begin
      H := FHistory.GetItem(I);
      if H = nil then Continue;
      if H.Completed then Inc(CompCount);

      if (FilterStr <> '') and
         (Pos(FilterStr, LowerCase(H.Name)) = 0) and
         (Pos(FilterStr, LowerCase(H.DownloadDir)) = 0) and
         (Pos(FilterStr, LowerCase(H.HashString)) = 0) then
        Continue;

      Li := LvHistory.Items.Add;
      Li.Caption := H.Name;
      Li.Data := H;
      Li.SubItems.Add(FormatSize(H.TotalSize));
      Li.SubItems.Add(FormatSize(H.DownloadedEver));
      Li.SubItems.Add(FormatSize(H.UploadedEver));
      Li.SubItems.Add(FormatRatio(H.UploadRatio));
      if H.Completed then
        Li.SubItems.Add('Completed')
      else
        Li.SubItems.Add('In Progress');
      Li.SubItems.Add(UnixToDateTimeStr(H.AddedDate));
      if H.DoneDate > 0 then
        Li.SubItems.Add(UnixToDateTimeStr(H.DoneDate))
      else
        Li.SubItems.Add('-');
      Li.SubItems.Add(H.DownloadDir);
    end;
  finally
    LvHistory.Items.EndUpdate;
  end;

  LblSummary.Caption := Format('Entries: %d (%d completed) | Data Folder: %s',
    [FHistory.Count, CompCount, FDataDir]);
  UpdateButtons;
end;

procedure THistoryForm.UpdateButtons;
var
  H: THistoryItem;
begin
  H := GetSelectedHistoryItem;
  BtnReDownload.Enabled := (H <> nil) and (H.MagnetLink <> '') and (FRpc <> nil);
  BtnCopyMagnet.Enabled := (H <> nil) and (H.MagnetLink <> '');
  BtnOpenFolder.Enabled := (H <> nil) and (H.DownloadDir <> '');
  BtnDelete.Enabled := (H <> nil);
  BtnClear.Enabled := (FHistory <> nil) and (FHistory.Count > 0);
end;

procedure THistoryForm.EdtSearchChange(Sender: TObject);
begin
  RefreshList;
end;

procedure THistoryForm.LvHistorySelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  UpdateButtons;
end;

procedure THistoryForm.LvHistoryDblClick(Sender: TObject);
begin
  if BtnReDownload.Enabled then
    BtnReDownloadClick(Sender);
end;

procedure THistoryForm.BtnReDownloadClick(Sender: TObject);
var
  H: THistoryItem;
  DestDir, AddedName: string;
begin
  H := GetSelectedHistoryItem;
  if (H = nil) or (FRpc = nil) then Exit;
  if H.MagnetLink = '' then
  begin
    MessageDlg('Re-download', 'No magnet link is saved for this entry.', mtInformation, [mbOK], 0);
    Exit;
  end;
  DestDir := H.DownloadDir;
  if FRpc.AddTorrentUrl(H.MagnetLink, DestDir, True, TR_PRI_NORMAL, AddedName) then
    MessageDlg('Re-download', 'Added "' + H.Name + '" back to Transmission queue.', mtInformation, [mbOK], 0)
  else
    MessageDlg('Re-download Error', 'Failed to re-add torrent: ' + FRpc.LastError, mtError, [mbOK], 0);
end;

procedure THistoryForm.BtnCopyMagnetClick(Sender: TObject);
var
  H: THistoryItem;
begin
  H := GetSelectedHistoryItem;
  if (H = nil) or (H.MagnetLink = '') then Exit;
  Clipboard.AsText := H.MagnetLink;
end;

procedure THistoryForm.BtnOpenFolderClick(Sender: TObject);
var
  H: THistoryItem;
begin
  H := GetSelectedHistoryItem;
  if H = nil then Exit;
  if (H.DownloadDir <> '') and DirectoryExists(H.DownloadDir) then
    OpenDocument(H.DownloadDir)
  else
    MessageDlg('Open Folder', 'Folder not found: ' + H.DownloadDir, mtWarning, [mbOK], 0);
end;

procedure THistoryForm.BtnDeleteClick(Sender: TObject);
var
  H: THistoryItem;
begin
  H := GetSelectedHistoryItem;
  if (H = nil) or (FHistory = nil) then Exit;
  FHistory.RemoveByHash(H.HashString);
  FHistory.SaveToFile(GetHistoryFilePath);
  RefreshList;
end;

procedure THistoryForm.BtnClearClick(Sender: TObject);
begin
  if (FHistory = nil) or (FHistory.Count = 0) then Exit;
  if MessageDlg('Clear History', 'Remove all saved download history entries?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    FHistory.Clear;
    FHistory.SaveToFile(GetHistoryFilePath);
    RefreshList;
  end;
end;

procedure THistoryForm.BtnExportClick(Sender: TObject);
var
  Dlg: TSaveDialog;
begin
  Dlg := TSaveDialog.Create(Self);
  try
    Dlg.Title := 'Export Portable Backup';
    Dlg.Filter := 'Transmission Backup (*.trbak)|*.trbak|All files (*.*)|*.*';
    Dlg.DefaultExt := 'trbak';
    Dlg.FileName := 'transmission_backup_' + FormatDateTime('yyyymmdd', Now) + '.trbak';
    if Dlg.Execute then
    begin
      if ExportPortableBackup(Dlg.FileName, FDataDir, FIniPath, FHistory) then
        MessageDlg('Export Backup',
          'Backup exported successfully to:' + LineEnding + Dlg.FileName + LineEnding + LineEnding +
          'Copy this file (or the entire Data Folder) to restore history and torrents after reinstalling Windows.',
          mtInformation, [mbOK], 0)
      else
        MessageDlg('Export Error', 'Failed to export backup file.', mtError, [mbOK], 0);
    end;
  finally
    Dlg.Free;
  end;
end;

procedure THistoryForm.BtnImportClick(Sender: TObject);
var
  Dlg: TOpenDialog;
  RestoredCount: Integer;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title := 'Import Portable Backup';
    Dlg.Filter := 'Transmission Backup (*.trbak)|*.trbak|All files (*.*)|*.*';
    if Dlg.Execute then
    begin
      if ImportPortableBackup(Dlg.FileName, FDataDir, FHistory, RestoredCount) then
      begin
        FRestoredFromBackup := True;
        RefreshList;
        MessageDlg('Import Backup',
          Format('Restored %d history entries and %d session/resume files.',
            [FHistory.Count, RestoredCount]),
          mtInformation, [mbOK], 0);
      end
      else
        MessageDlg('Import Error', 'Failed to import backup file (invalid or unreadable .trbak).', mtError, [mbOK], 0);
    end;
  finally
    Dlg.Free;
  end;
end;

function ShowHistoryDialog(Owner: TComponent; Rpc: TTransmissionRpcClient;
  History: TDownloadHistoryManager; const DataDir, IniPath: string): Boolean;
var
  F: THistoryForm;
  Col: TListColumn;
begin
  Result := False;
  F := THistoryForm.CreateNew(Owner);
  try
    F.FRpc := Rpc;
    F.FHistory := History;
    F.FDataDir := DataDir;
    F.FIniPath := IniPath;
    F.FRestoredFromBackup := False;
    F.Caption := 'Download History & Portable Backup';
    F.Width := 940;
    F.Height := 520;
    F.Constraints.MinWidth := 740;
    F.Constraints.MinHeight := 360;
    F.Position := poScreenCenter;

    F.PnlTop := TPanel.Create(F);
    F.PnlTop.Parent := F;
    F.PnlTop.Align := alTop;
    F.PnlTop.Height := 54;
    F.PnlTop.BevelOuter := bvNone;

    F.LblSearch := TLabel.Create(F.PnlTop);
    F.LblSearch.Parent := F.PnlTop;
    F.LblSearch.Left := 12; F.LblSearch.Top := 10;
    F.LblSearch.Caption := 'Filter:';

    F.EdtSearch := TEdit.Create(F.PnlTop);
    F.EdtSearch.Parent := F.PnlTop;
    F.EdtSearch.Left := 54; F.EdtSearch.Top := 6; F.EdtSearch.Width := 260;
    F.EdtSearch.TextHint := 'Search torrent name, hash, or folder...';
    F.EdtSearch.OnChange := @F.EdtSearchChange;

    F.LblSummary := TLabel.Create(F.PnlTop);
    F.LblSummary.Parent := F.PnlTop;
    F.LblSummary.Left := 12; F.LblSummary.Top := 33;
    F.LblSummary.Caption := '';

    F.LvHistory := TListView.Create(F);
    F.LvHistory.Parent := F;
    F.LvHistory.Align := alClient;
    F.LvHistory.ViewStyle := vsReport;
    F.LvHistory.RowSelect := True;
    F.LvHistory.ReadOnly := True;
    F.LvHistory.GridLines := True;
    F.LvHistory.HideSelection := False;
    F.LvHistory.OnSelectItem := @F.LvHistorySelectItem;
    F.LvHistory.OnDblClick := @F.LvHistoryDblClick;

    Col := F.LvHistory.Columns.Add; Col.Caption := 'Name'; Col.Width := 230;
    Col := F.LvHistory.Columns.Add; Col.Caption := 'Size'; Col.Width := 80;
    Col := F.LvHistory.Columns.Add; Col.Caption := 'Downloaded'; Col.Width := 85;
    Col := F.LvHistory.Columns.Add; Col.Caption := 'Uploaded'; Col.Width := 85;
    Col := F.LvHistory.Columns.Add; Col.Caption := 'Ratio'; Col.Width := 55;
    Col := F.LvHistory.Columns.Add; Col.Caption := 'Status'; Col.Width := 80;
    Col := F.LvHistory.Columns.Add; Col.Caption := 'Added'; Col.Width := 115;
    Col := F.LvHistory.Columns.Add; Col.Caption := 'Completed'; Col.Width := 115;
    Col := F.LvHistory.Columns.Add; Col.Caption := 'Save Folder'; Col.Width := 190;

    F.PnlBottom := TPanel.Create(F);
    F.PnlBottom.Parent := F;
    F.PnlBottom.Align := alBottom;
    F.PnlBottom.Height := 44;
    F.PnlBottom.BevelOuter := bvNone;

    F.BtnReDownload := TButton.Create(F.PnlBottom);
    F.BtnReDownload.Parent := F.PnlBottom;
    F.BtnReDownload.Left := 12; F.BtnReDownload.Top := 9; F.BtnReDownload.Width := 94;
    F.BtnReDownload.Caption := 'Re-download';
    F.BtnReDownload.OnClick := @F.BtnReDownloadClick;

    F.BtnCopyMagnet := TButton.Create(F.PnlBottom);
    F.BtnCopyMagnet.Parent := F.PnlBottom;
    F.BtnCopyMagnet.Left := 112; F.BtnCopyMagnet.Top := 9; F.BtnCopyMagnet.Width := 92;
    F.BtnCopyMagnet.Caption := 'Copy Magnet';
    F.BtnCopyMagnet.OnClick := @F.BtnCopyMagnetClick;

    F.BtnOpenFolder := TButton.Create(F.PnlBottom);
    F.BtnOpenFolder.Parent := F.PnlBottom;
    F.BtnOpenFolder.Left := 210; F.BtnOpenFolder.Top := 9; F.BtnOpenFolder.Width := 88;
    F.BtnOpenFolder.Caption := 'Open Folder';
    F.BtnOpenFolder.OnClick := @F.BtnOpenFolderClick;

    F.BtnDelete := TButton.Create(F.PnlBottom);
    F.BtnDelete.Parent := F.PnlBottom;
    F.BtnDelete.Left := 304; F.BtnDelete.Top := 9; F.BtnDelete.Width := 82;
    F.BtnDelete.Caption := 'Delete Entry';
    F.BtnDelete.OnClick := @F.BtnDeleteClick;

    F.BtnClear := TButton.Create(F.PnlBottom);
    F.BtnClear.Parent := F.PnlBottom;
    F.BtnClear.Left := 392; F.BtnClear.Top := 9; F.BtnClear.Width := 70;
    F.BtnClear.Caption := 'Clear All';
    F.BtnClear.OnClick := @F.BtnClearClick;

    F.BtnExport := TButton.Create(F.PnlBottom);
    F.BtnExport.Parent := F.PnlBottom;
    F.BtnExport.Left := 482; F.BtnExport.Top := 9; F.BtnExport.Width := 112;
    F.BtnExport.Caption := 'Export Backup...';
    F.BtnExport.OnClick := @F.BtnExportClick;

    F.BtnImport := TButton.Create(F.PnlBottom);
    F.BtnImport.Parent := F.PnlBottom;
    F.BtnImport.Left := 600; F.BtnImport.Top := 9; F.BtnImport.Width := 112;
    F.BtnImport.Caption := 'Import Backup...';
    F.BtnImport.OnClick := @F.BtnImportClick;

    F.BtnClose := TButton.Create(F.PnlBottom);
    F.BtnClose.Parent := F.PnlBottom;
    F.BtnClose.Left := 848; F.BtnClose.Top := 9; F.BtnClose.Width := 80;
    F.BtnClose.Anchors := [akTop, akRight];
    F.BtnClose.Caption := 'Close';
    F.BtnClose.Default := True;
    F.BtnClose.Cancel := True;
    F.BtnClose.ModalResult := mrClose;

    F.RefreshList;
    F.ShowModal;
    Result := F.FRestoredFromBackup;
  finally
    F.Free;
  end;
end;

end.
