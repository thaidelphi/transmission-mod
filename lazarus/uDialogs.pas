unit uDialogs;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ComCtrls, Spin, Clipbrd, fpjson, DateUtils, uTypes, uRpcClient;

function ShowOpenTorrentDialog(Owner: TComponent; Rpc: TTransmissionRpcClient;
  const InitialFile, DefaultDir: string; DefaultStart: Boolean;
  out SelectedFile, DestDir: string; out StartNow, TrashTorrent: Boolean;
  out Priority: Integer): Boolean;

function ShowAddUrlDialog(Owner: TComponent; Rpc: TTransmissionRpcClient;
  const DefaultDir: string; DefaultStart: Boolean;
  out UrlOrMagnet, DestDir: string; out StartNow: Boolean;
  out Priority: Integer): Boolean;

function ShowMakeTorrentDialog(Owner: TComponent; Rpc: TTransmissionRpcClient): Boolean;

procedure ShowDetailsDialog(Owner: TComponent; Rpc: TTransmissionRpcClient;
  Torrent: TTorrentItem);

function ShowPrefsDialog(Owner: TComponent; Rpc: TTransmissionRpcClient;
  var Config: TSessionConfig): Boolean;

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

{ 1. Open Torrent Dialog }

type
  TOpenTorrentForm = class(TForm)
  public
    RpcRef: TTransmissionRpcClient;
    EdtFile: TEdit;
    EdtDir: TEdit;
    LblFreeSpace: TLabel;
    CmbPriority: TComboBox;
    ChkStart: TCheckBox;
    ChkTrash: TCheckBox;
    procedure BtnBrowseFileClick(Sender: TObject);
    procedure BtnBrowseDirClick(Sender: TObject);
    procedure EdtDirChange(Sender: TObject);
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
      EdtFile.Text := Dlg.FileName;
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
  out Priority: Integer): Boolean;
var
  F: TOpenTorrentForm;
  Lbl: TLabel;
  BtnFile, BtnDir, BtnOK, BtnCancel: TButton;
begin
  Result := False;
  F := TOpenTorrentForm.CreateNew(Owner);
  try
    F.RpcRef := Rpc;
    F.Caption := 'Torrent Options';
    F.Position := poMainFormCenter;
    F.BorderStyle := bsDialog;
    F.ClientWidth := 480;
    F.ClientHeight := 255;

    Lbl := TLabel.Create(F);
    Lbl.Parent := F;
    Lbl.Left := 16;
    Lbl.Top := 16;
    Lbl.Caption := 'Torrent file:';

    F.EdtFile := TEdit.Create(F);
    F.EdtFile.Parent := F;
    F.EdtFile.Left := 16;
    F.EdtFile.Top := 36;
    F.EdtFile.Width := 360;
    F.EdtFile.Text := InitialFile;

    BtnFile := TButton.Create(F);
    BtnFile.Parent := F;
    BtnFile.Left := 384;
    BtnFile.Top := 34;
    BtnFile.Width := 80;
    BtnFile.Height := 26;
    BtnFile.Caption := 'Browse...';
    BtnFile.OnClick := @F.BtnBrowseFileClick;

    Lbl := TLabel.Create(F);
    Lbl.Parent := F;
    Lbl.Left := 16;
    Lbl.Top := 72;
    Lbl.Caption := 'Destination folder:';

    F.LblFreeSpace := TLabel.Create(F);
    F.LblFreeSpace.Parent := F;
    F.LblFreeSpace.Left := 140;
    F.LblFreeSpace.Top := 72;
    F.LblFreeSpace.Font.Color := clGrayText;

    F.EdtDir := TEdit.Create(F);
    F.EdtDir.Parent := F;
    F.EdtDir.Left := 16;
    F.EdtDir.Top := 92;
    F.EdtDir.Width := 360;
    F.EdtDir.Text := DefaultDir;
    F.EdtDir.OnChange := @F.EdtDirChange;

    BtnDir := TButton.Create(F);
    BtnDir.Parent := F;
    BtnDir.Left := 384;
    BtnDir.Top := 90;
    BtnDir.Width := 80;
    BtnDir.Height := 26;
    BtnDir.Caption := 'Browse...';
    BtnDir.OnClick := @F.BtnBrowseDirClick;

    Lbl := TLabel.Create(F);
    Lbl.Parent := F;
    Lbl.Left := 16;
    Lbl.Top := 134;
    Lbl.Caption := 'Priority:';

    F.CmbPriority := TComboBox.Create(F);
    F.CmbPriority.Parent := F;
    F.CmbPriority.Left := 76;
    F.CmbPriority.Top := 130;
    F.CmbPriority.Width := 130;
    F.CmbPriority.Style := csDropDownList;
    F.CmbPriority.Items.Add('High');
    F.CmbPriority.Items.Add('Normal');
    F.CmbPriority.Items.Add('Low');
    F.CmbPriority.ItemIndex := 1;

    F.ChkStart := TCheckBox.Create(F);
    F.ChkStart.Parent := F;
    F.ChkStart.Left := 16;
    F.ChkStart.Top := 166;
    F.ChkStart.Caption := 'Start when added';
    F.ChkStart.Checked := DefaultStart;

    F.ChkTrash := TCheckBox.Create(F);
    F.ChkTrash.Parent := F;
    F.ChkTrash.Left := 220;
    F.ChkTrash.Top := 166;
    F.ChkTrash.Caption := 'Move .torrent file to the trash';
    F.ChkTrash.Checked := False;

    BtnOK := TButton.Create(F);
    BtnOK.Parent := F;
    BtnOK.Left := 296;
    BtnOK.Top := 212;
    BtnOK.Width := 80;
    BtnOK.Caption := 'OK';
    BtnOK.Default := True;
    BtnOK.ModalResult := mrOk;

    BtnCancel := TButton.Create(F);
    BtnCancel.Parent := F;
    BtnCancel.Left := 384;
    BtnCancel.Top := 212;
    BtnCancel.Width := 80;
    BtnCancel.Caption := 'Cancel';
    BtnCancel.Cancel := True;
    BtnCancel.ModalResult := mrCancel;

    F.EdtDirChange(nil);

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
    EdtUrl: TEdit;
    EdtDir: TEdit;
    CmbPriority: TComboBox;
    ChkStart: TCheckBox;
    procedure BtnBrowseDirClick(Sender: TObject);
  end;

procedure TAddUrlForm.BtnBrowseDirClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := EdtDir.Text;
  if SelectDirectory('Select Destination Folder', '', Dir) then
    EdtDir.Text := Dir;
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
    F.Caption := 'Open URL or Magnet Link';
    F.Position := poMainFormCenter;
    F.BorderStyle := bsDialog;
    F.ClientWidth := 480;
    F.ClientHeight := 225;

    Lbl := TLabel.Create(F);
    Lbl.Parent := F;
    Lbl.Left := 16;
    Lbl.Top := 16;
    Lbl.Caption := 'Enter torrent URL or magnet: link:';

    F.EdtUrl := TEdit.Create(F);
    F.EdtUrl.Parent := F;
    F.EdtUrl.Left := 16;
    F.EdtUrl.Top := 36;
    F.EdtUrl.Width := 448;

    ClipStr := Trim(Clipboard.AsText);
    if (Pos('magnet:?', LowerCase(ClipStr)) = 1) or
       (Pos('http://', LowerCase(ClipStr)) = 1) or
       (Pos('https://', LowerCase(ClipStr)) = 1) then
      F.EdtUrl.Text := ClipStr;

    Lbl := TLabel.Create(F);
    Lbl.Parent := F;
    Lbl.Left := 16;
    Lbl.Top := 72;
    Lbl.Caption := 'Destination folder:';

    F.EdtDir := TEdit.Create(F);
    F.EdtDir.Parent := F;
    F.EdtDir.Left := 16;
    F.EdtDir.Top := 92;
    F.EdtDir.Width := 360;
    F.EdtDir.Text := DefaultDir;

    BtnDir := TButton.Create(F);
    BtnDir.Parent := F;
    BtnDir.Left := 384;
    BtnDir.Top := 90;
    BtnDir.Width := 80;
    BtnDir.Height := 26;
    BtnDir.Caption := 'Browse...';
    BtnDir.OnClick := @F.BtnBrowseDirClick;

    Lbl := TLabel.Create(F);
    Lbl.Parent := F;
    Lbl.Left := 16;
    Lbl.Top := 134;
    Lbl.Caption := 'Priority:';

    F.CmbPriority := TComboBox.Create(F);
    F.CmbPriority.Parent := F;
    F.CmbPriority.Left := 76;
    F.CmbPriority.Top := 130;
    F.CmbPriority.Width := 130;
    F.CmbPriority.Style := csDropDownList;
    F.CmbPriority.Items.Add('High');
    F.CmbPriority.Items.Add('Normal');
    F.CmbPriority.Items.Add('Low');
    F.CmbPriority.ItemIndex := 1;

    F.ChkStart := TCheckBox.Create(F);
    F.ChkStart.Parent := F;
    F.ChkStart.Left := 230;
    F.ChkStart.Top := 133;
    F.ChkStart.Caption := 'Start when added';
    F.ChkStart.Checked := DefaultStart;

    BtnOK := TButton.Create(F);
    BtnOK.Parent := F;
    BtnOK.Left := 296;
    BtnOK.Top := 180;
    BtnOK.Width := 80;
    BtnOK.Caption := 'OK';
    BtnOK.Default := True;
    BtnOK.ModalResult := mrOk;

    BtnCancel := TButton.Create(F);
    BtnCancel.Parent := F;
    BtnCancel.Left := 384;
    BtnCancel.Top := 180;
    BtnCancel.Width := 80;
    BtnCancel.Caption := 'Cancel';
    BtnCancel.Cancel := True;
    BtnCancel.ModalResult := mrCancel;

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
        RpcRef.AddTorrentFile(OutFile, ExtractFilePath(ExcludeTrailingPathDelimiter(EdtSource.Text)), True, TR_PRI_NORMAL, AddedName);
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
    F.RbFolder.Left := 16;
    F.RbFolder.Top := 16;
    F.RbFolder.Caption := 'Source Folder';
    F.RbFolder.Checked := True;

    F.RbFile := TRadioButton.Create(F);
    F.RbFile.Parent := F;
    F.RbFile.Left := 150;
    F.RbFile.Top := 16;
    F.RbFile.Caption := 'Source File';

    F.EdtSource := TEdit.Create(F);
    F.EdtSource.Parent := F;
    F.EdtSource.Left := 16;
    F.EdtSource.Top := 42;
    F.EdtSource.Width := 360;

    BtnBrowse := TButton.Create(F);
    BtnBrowse.Parent := F;
    BtnBrowse.Left := 384;
    BtnBrowse.Top := 40;
    BtnBrowse.Width := 80;
    BtnBrowse.Height := 26;
    BtnBrowse.Caption := 'Browse...';
    BtnBrowse.OnClick := @F.BtnBrowseSourceClick;

    Lbl := TLabel.Create(F);
    Lbl.Parent := F;
    Lbl.Left := 16;
    Lbl.Top := 78;
    Lbl.Caption := 'Trackers (one announce URL per line):';

    F.MemTrackers := TMemo.Create(F);
    F.MemTrackers.Parent := F;
    F.MemTrackers.Left := 16;
    F.MemTrackers.Top := 98;
    F.MemTrackers.Width := 448;
    F.MemTrackers.Height := 100;
    F.MemTrackers.ScrollBars := ssVertical;

    Lbl := TLabel.Create(F);
    Lbl.Parent := F;
    Lbl.Left := 16;
    Lbl.Top := 210;
    Lbl.Caption := 'Comment:';

    F.EdtComment := TEdit.Create(F);
    F.EdtComment.Parent := F;
    F.EdtComment.Left := 85;
    F.EdtComment.Top := 206;
    F.EdtComment.Width := 379;

    F.ChkPrivate := TCheckBox.Create(F);
    F.ChkPrivate.Parent := F;
    F.ChkPrivate.Left := 16;
    F.ChkPrivate.Top := 248;
    F.ChkPrivate.Caption := 'Private torrent (do not distribute via DHT/PEX)';

    F.ChkAddNow := TCheckBox.Create(F);
    F.ChkAddNow.Parent := F;
    F.ChkAddNow.Left := 16;
    F.ChkAddNow.Top := 274;
    F.ChkAddNow.Caption := 'Add torrent to Transmission after creation';
    F.ChkAddNow.Checked := True;

    BtnCreate := TButton.Create(F);
    BtnCreate.Parent := F;
    BtnCreate.Left := 280;
    BtnCreate.Top := 315;
    BtnCreate.Width := 96;
    BtnCreate.Caption := 'Create...';
    BtnCreate.OnClick := @F.BtnCreateClick;

    BtnClose := TButton.Create(F);
    BtnClose.Parent := F;
    BtnClose.Left := 384;
    BtnClose.Top := 315;
    BtnClose.Width := 80;
    BtnClose.Caption := 'Close';
    BtnClose.Cancel := True;
    BtnClose.ModalResult := mrCancel;

    Result := F.ShowModal = mrOk;
  finally
    F.Free;
  end;
end;

{ 4. Torrent Properties / Details Dialog }

type
  TDetailsForm = class(TForm)
  public
    RpcRef: TTransmissionRpcClient;
    TorRef: TTorrentItem;
    ChkHonorSession: TCheckBox;
    ChkDownLimit: TCheckBox;
    SpnDownLimit: TSpinEdit;
    ChkUpLimit: TCheckBox;
    SpnUpLimit: TSpinEdit;
    CmbRatioMode: TComboBox;
    EdtRatioLimit: TEdit;
    SpnPeerLimit: TSpinEdit;
    LvFiles: TListView;
    procedure BtnApplyOptionsClick(Sender: TObject);
    procedure BtnApplyFilesClick(Sender: TObject);
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
    MessageDlg('File selection saved.', mtInformation, [mbOK], 0)
  else
    MessageDlg('Failed to update file selection: ' + RpcRef.LastError, mtError, [mbOK], 0);
end;

procedure AddKeyValRow(ParentCtrl: TWinControl; Y: Integer; const KeyText, ValText: string);
var
  LKey, LVal: TLabel;
begin
  LKey := TLabel.Create(ParentCtrl);
  LKey.Parent := ParentCtrl;
  LKey.Left := 16;
  LKey.Top := Y;
  LKey.Font.Style := [fsBold];
  LKey.Caption := KeyText;

  LVal := TLabel.Create(ParentCtrl);
  LVal.Parent := ParentCtrl;
  LVal.Left := 155;
  LVal.Top := Y;
  LVal.Width := 420;
  LVal.Caption := ValText;
end;

procedure ShowDetailsDialog(Owner: TComponent; Rpc: TTransmissionRpcClient;
  Torrent: TTorrentItem);
var
  F: TDetailsForm;
  PC: TPageControl;
  TsAct, TsInfo, TsPeers, TsTrackers, TsFiles, TsOpts: TTabSheet;
  LvPeers, LvTrackers: TListView;
  LI: TListItem;
  I: Integer;
  BtnClose, BtnApplyOpt, BtnSaveFiles: TButton;
  Lbl: TLabel;
  PctFile: Double;
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
    F.ClientWidth := 620;
    F.ClientHeight := 440;

    PC := TPageControl.Create(F);
    PC.Parent := F;
    PC.Align := alClient;

    // Tab 1: Activity
    TsAct := PC.AddTabSheet;
    TsAct.Caption := 'Activity';
    AddKeyValRow(TsAct, 18, 'Have:', Format('%s of %s (%s) - %s Unverified',
      [FormatSize(Torrent.HaveTotal), FormatSize(Torrent.SizeWhenDone),
       FormatPercent(Torrent.PercentDone), FormatSize(Torrent.HaveUnchecked)]));
    AddKeyValRow(TsAct, 46, 'Downloaded:', FormatSize(Torrent.DownloadedEver));
    AddKeyValRow(TsAct, 74, 'Uploaded:', Format('%s (Ratio: %s)',
      [FormatSize(Torrent.UploadedEver), FormatRatio(Torrent.UploadRatio)]));
    AddKeyValRow(TsAct, 102, 'State:', Torrent.FullStatusString);
    AddKeyValRow(TsAct, 130, 'Download Speed:', FormatSpeed(Torrent.RateDownload));
    AddKeyValRow(TsAct, 158, 'Upload Speed:', FormatSpeed(Torrent.RateUpload));
    AddKeyValRow(TsAct, 186, 'Running Time:', Format('Downloading: %s, Seeding: %s',
      [FormatDuration(Torrent.SecondsDownloading), FormatDuration(Torrent.SecondsSeeding)]));
    AddKeyValRow(TsAct, 214, 'Remaining Time:', FormatETA(Torrent.ETA));
    AddKeyValRow(TsAct, 242, 'Last Activity:', UnixToDateTimeStr(Torrent.ActivityDate));
    if Torrent.ErrorString <> '' then
      AddKeyValRow(TsAct, 270, 'Error:', Torrent.ErrorString)
    else
      AddKeyValRow(TsAct, 270, 'Error:', 'None');

    // Tab 2: Information
    TsInfo := PC.AddTabSheet;
    TsInfo.Caption := 'Information';
    AddKeyValRow(TsInfo, 18, 'Total Size:', Format('%s (%d pieces @ %s)',
      [FormatSize(Torrent.TotalSize), Torrent.PieceCount, FormatSize(Torrent.PieceSize)]));
    AddKeyValRow(TsInfo, 46, 'Hash:', Torrent.HashString);
    if Torrent.IsPrivate then
      AddKeyValRow(TsInfo, 74, 'Type:', 'Private torrent (DHT and PEX disabled)')
    else
      AddKeyValRow(TsInfo, 74, 'Type:', 'Public torrent');
    AddKeyValRow(TsInfo, 102, 'Location:', Torrent.DownloadDir);
    AddKeyValRow(TsInfo, 130, 'Creator:', Torrent.Creator);
    AddKeyValRow(TsInfo, 158, 'Added Date:', UnixToDateTimeStr(Torrent.AddedDate));
    AddKeyValRow(TsInfo, 186, 'Completed Date:', UnixToDateTimeStr(Torrent.DoneDate));
    AddKeyValRow(TsInfo, 214, 'Comment:', Torrent.Comment);

    // Tab 3: Peers
    TsPeers := PC.AddTabSheet;
    TsPeers.Caption := Format('Peers (%d)', [Length(Torrent.Peers)]);
    LvPeers := TListView.Create(TsPeers);
    LvPeers.Parent := TsPeers;
    LvPeers.Align := alClient;
    LvPeers.ViewStyle := vsReport;
    LvPeers.ReadOnly := True;
    LvPeers.RowSelect := True;
    LvPeers.GridLines := True;
    with LvPeers.Columns.Add do begin Caption := 'Address'; Width := 150; end;
    with LvPeers.Columns.Add do begin Caption := 'Client'; Width := 150; end;
    with LvPeers.Columns.Add do begin Caption := '%'; Width := 65; end;
    with LvPeers.Columns.Add do begin Caption := 'Down'; Width := 85; end;
    with LvPeers.Columns.Add do begin Caption := 'Up'; Width := 85; end;
    with LvPeers.Columns.Add do begin Caption := 'Flags'; Width := 60; end;

    for I := 0 to High(Torrent.Peers) do
    begin
      LI := LvPeers.Items.Add;
      LI.Caption := Format('%s:%d', [Torrent.Peers[I].Address, Torrent.Peers[I].Port]);
      LI.SubItems.Add(Torrent.Peers[I].ClientName);
      LI.SubItems.Add(FormatPercent(Torrent.Peers[I].Progress));
      LI.SubItems.Add(FormatSpeed(Torrent.Peers[I].RateToClient));
      LI.SubItems.Add(FormatSpeed(Torrent.Peers[I].RateToPeer));
      LI.SubItems.Add(Torrent.Peers[I].FlagStr);
    end;

    // Tab 4: Trackers
    TsTrackers := PC.AddTabSheet;
    TsTrackers.Caption := Format('Trackers (%d)', [Length(Torrent.Trackers)]);
    LvTrackers := TListView.Create(TsTrackers);
    LvTrackers.Parent := TsTrackers;
    LvTrackers.Align := alClient;
    LvTrackers.ViewStyle := vsReport;
    LvTrackers.ReadOnly := True;
    LvTrackers.RowSelect := True;
    LvTrackers.GridLines := True;
    with LvTrackers.Columns.Add do begin Caption := 'Tier'; Width := 45; end;
    with LvTrackers.Columns.Add do begin Caption := 'Tracker Announce URL'; Width := 250; end;
    with LvTrackers.Columns.Add do begin Caption := 'Status'; Width := 130; end;
    with LvTrackers.Columns.Add do begin Caption := 'Seeders'; Width := 60; end;
    with LvTrackers.Columns.Add do begin Caption := 'Leechers'; Width := 65; end;

    for I := 0 to High(Torrent.Trackers) do
    begin
      LI := LvTrackers.Items.Add;
      LI.Caption := IntToStr(Torrent.Trackers[I].Tier + 1);
      LI.SubItems.Add(Torrent.Trackers[I].Announce);
      LI.SubItems.Add(Torrent.Trackers[I].LastAnnounceResult);
      if Torrent.Trackers[I].SeederCount >= 0 then
        LI.SubItems.Add(IntToStr(Torrent.Trackers[I].SeederCount))
      else
        LI.SubItems.Add('-');
      if Torrent.Trackers[I].LeecherCount >= 0 then
        LI.SubItems.Add(IntToStr(Torrent.Trackers[I].LeecherCount))
      else
        LI.SubItems.Add('-');
    end;

    // Tab 5: Files
    TsFiles := PC.AddTabSheet;
    TsFiles.Caption := Format('Files (%d)', [Length(Torrent.Files)]);
    F.LvFiles := TListView.Create(TsFiles);
    F.LvFiles.Parent := TsFiles;
    F.LvFiles.Left := 8;
    F.LvFiles.Top := 8;
    F.LvFiles.Width := 590;
    F.LvFiles.Height := 315;
    F.LvFiles.Anchors := [akLeft, akTop, akRight, akBottom];
    F.LvFiles.ViewStyle := vsReport;
    F.LvFiles.Checkboxes := True;
    F.LvFiles.RowSelect := True;
    F.LvFiles.GridLines := True;
    with F.LvFiles.Columns.Add do begin Caption := 'File Name'; Width := 330; end;
    with F.LvFiles.Columns.Add do begin Caption := 'Size'; Width := 95; end;
    with F.LvFiles.Columns.Add do begin Caption := 'Done'; Width := 95; end;
    with F.LvFiles.Columns.Add do begin Caption := '%'; Width := 60; end;

    for I := 0 to High(Torrent.Files) do
    begin
      LI := F.LvFiles.Items.Add;
      LI.Checked := Torrent.Files[I].Wanted;
      LI.Caption := Torrent.Files[I].Name;
      LI.SubItems.Add(FormatSize(Torrent.Files[I].Length));
      LI.SubItems.Add(FormatSize(Torrent.Files[I].BytesCompleted));
      if Torrent.Files[I].Length > 0 then
        PctFile := Torrent.Files[I].BytesCompleted / Torrent.Files[I].Length
      else
        PctFile := 1.0;
      LI.SubItems.Add(FormatPercent(PctFile));
    end;

    BtnSaveFiles := TButton.Create(TsFiles);
    BtnSaveFiles.Parent := TsFiles;
    BtnSaveFiles.Left := 450;
    BtnSaveFiles.Top := 330;
    BtnSaveFiles.Width := 145;
    BtnSaveFiles.Anchors := [akRight, akBottom];
    BtnSaveFiles.Caption := 'Apply File Selection';
    BtnSaveFiles.OnClick := @F.BtnApplyFilesClick;

    // Tab 6: Options
    TsOpts := PC.AddTabSheet;
    TsOpts.Caption := 'Options';

    F.ChkHonorSession := TCheckBox.Create(TsOpts);
    F.ChkHonorSession.Parent := TsOpts;
    F.ChkHonorSession.Left := 20;
    F.ChkHonorSession.Top := 20;
    F.ChkHonorSession.Caption := 'Honor global session bandwidth limits';
    F.ChkHonorSession.Checked := Torrent.HonorsSessionLimits;

    F.ChkDownLimit := TCheckBox.Create(TsOpts);
    F.ChkDownLimit.Parent := TsOpts;
    F.ChkDownLimit.Left := 20;
    F.ChkDownLimit.Top := 56;
    F.ChkDownLimit.Caption := 'Limit download speed (KB/s):';
    F.ChkDownLimit.Checked := Torrent.DownloadLimited;

    F.SpnDownLimit := TSpinEdit.Create(TsOpts);
    F.SpnDownLimit.Parent := TsOpts;
    F.SpnDownLimit.Left := 230;
    F.SpnDownLimit.Top := 52;
    F.SpnDownLimit.Width := 100;
    F.SpnDownLimit.MaxValue := 1000000;
    F.SpnDownLimit.Value := Torrent.DownloadLimit;

    F.ChkUpLimit := TCheckBox.Create(TsOpts);
    F.ChkUpLimit.Parent := TsOpts;
    F.ChkUpLimit.Left := 20;
    F.ChkUpLimit.Top := 92;
    F.ChkUpLimit.Caption := 'Limit upload speed (KB/s):';
    F.ChkUpLimit.Checked := Torrent.UploadLimited;

    F.SpnUpLimit := TSpinEdit.Create(TsOpts);
    F.SpnUpLimit.Parent := TsOpts;
    F.SpnUpLimit.Left := 230;
    F.SpnUpLimit.Top := 88;
    F.SpnUpLimit.Width := 100;
    F.SpnUpLimit.MaxValue := 1000000;
    F.SpnUpLimit.Value := Torrent.UploadLimit;

    Lbl := TLabel.Create(TsOpts);
    Lbl.Parent := TsOpts;
    Lbl.Left := 20;
    Lbl.Top := 134;
    Lbl.Caption := 'Seed ratio limit:';

    F.CmbRatioMode := TComboBox.Create(TsOpts);
    F.CmbRatioMode.Parent := TsOpts;
    F.CmbRatioMode.Left := 140;
    F.CmbRatioMode.Top := 130;
    F.CmbRatioMode.Width := 180;
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
    F.EdtRatioLimit.Left := 330;
    F.EdtRatioLimit.Top := 130;
    F.EdtRatioLimit.Width := 80;
    F.EdtRatioLimit.Text := Format('%.2f', [Torrent.SeedRatioLimit]);

    Lbl := TLabel.Create(TsOpts);
    Lbl.Parent := TsOpts;
    Lbl.Left := 20;
    Lbl.Top := 174;
    Lbl.Caption := 'Maximum peers:';

    F.SpnPeerLimit := TSpinEdit.Create(TsOpts);
    F.SpnPeerLimit.Parent := TsOpts;
    F.SpnPeerLimit.Left := 140;
    F.SpnPeerLimit.Top := 170;
    F.SpnPeerLimit.Width := 100;
    F.SpnPeerLimit.MaxValue := 2000;
    F.SpnPeerLimit.Value := Torrent.PeerLimit;

    BtnApplyOpt := TButton.Create(TsOpts);
    BtnApplyOpt.Parent := TsOpts;
    BtnApplyOpt.Left := 20;
    BtnApplyOpt.Top := 220;
    BtnApplyOpt.Width := 130;
    BtnApplyOpt.Caption := 'Apply Options';
    BtnApplyOpt.OnClick := @F.BtnApplyOptionsClick;

    // Bottom Close panel
    BtnClose := TButton.Create(F);
    BtnClose.Parent := F;
    BtnClose.Left := 520;
    BtnClose.Top := 404;
    BtnClose.Width := 85;
    BtnClose.Anchors := [akRight, akBottom];
    BtnClose.Caption := 'Close';
    BtnClose.Cancel := True;
    BtnClose.ModalResult := mrClose;
    PC.Height := 395;
    PC.Align := alTop;
    PC.Anchors := [akLeft, akTop, akRight, akBottom];

    F.ShowModal;
  finally
    F.Free;
  end;
end;

{ 5. Preferences Dialog }

type
  TPrefsForm = class(TForm)
  public
    RpcRef: TTransmissionRpcClient;
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

    RbLocalSession: TRadioButton;
    RbRemoteSession: TRadioButton;
    EdtRpcHost: TEdit;
    SpnRpcPort: TSpinEdit;
    EdtRpcUser: TEdit;
    EdtRpcPass: TEdit;

    procedure BtnBrowseSaveDirClick(Sender: TObject);
    procedure BtnTestPortClick(Sender: TObject);
    procedure BtnUpdateBlocklistClick(Sender: TObject);
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

function ShowPrefsDialog(Owner: TComponent; Rpc: TTransmissionRpcClient;
  var Config: TSessionConfig): Boolean;
var
  F: TPrefsForm;
  PC: TPageControl;
  TsSpeed, TsDown, TsSeed, TsPriv, TsNet, TsRemote: TTabSheet;
  Lbl: TLabel;
  BtnBrowse, BtnTestPort, BtnUpdBlk, BtnOK, BtnCancel: TButton;
  Args: TJSONObject;
begin
  Result := False;
  Rpc.FetchSession(Config);

  F := TPrefsForm.CreateNew(Owner);
  try
    F.RpcRef := Rpc;
    F.Caption := 'Transmission Preferences';
    F.Position := poMainFormCenter;
    F.BorderStyle := bsDialog;
    F.ClientWidth := 500;
    F.ClientHeight := 370;

    PC := TPageControl.Create(F);
    PC.Parent := F;
    PC.Left := 8;
    PC.Top := 8;
    PC.Width := 484;
    PC.Height := 312;

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
    Lbl.Left := 16; Lbl.Top := 18;
    Lbl.Caption := 'Save to Location:';

    F.EdtDownloadDir := TEdit.Create(TsDown);
    F.EdtDownloadDir.Parent := TsDown;
    F.EdtDownloadDir.Left := 16; F.EdtDownloadDir.Top := 38; F.EdtDownloadDir.Width := 355;
    F.EdtDownloadDir.Text := Config.DownloadDir;

    BtnBrowse := TButton.Create(TsDown);
    BtnBrowse.Parent := TsDown;
    BtnBrowse.Left := 380; BtnBrowse.Top := 36; BtnBrowse.Width := 80;
    BtnBrowse.Caption := 'Browse...';
    BtnBrowse.OnClick := @F.BtnBrowseSaveDirClick;

    F.ChkStartAdded := TCheckBox.Create(TsDown);
    F.ChkStartAdded.Parent := TsDown;
    F.ChkStartAdded.Left := 16; F.ChkStartAdded.Top := 78;
    F.ChkStartAdded.Caption := 'Start added torrents immediately';
    F.ChkStartAdded.Checked := Config.StartAddedTorrents;

    F.ChkRenamePartial := TCheckBox.Create(TsDown);
    F.ChkRenamePartial.Parent := TsDown;
    F.ChkRenamePartial.Left := 16; F.ChkRenamePartial.Top := 106;
    F.ChkRenamePartial.Caption := 'Append ".part" to incomplete files'' names';
    F.ChkRenamePartial.Checked := Config.RenamePartialFiles;

    F.ChkIncompleteDir := TCheckBox.Create(TsDown);
    F.ChkIncompleteDir.Parent := TsDown;
    F.ChkIncompleteDir.Left := 16; F.ChkIncompleteDir.Top := 138;
    F.ChkIncompleteDir.Caption := 'Keep incomplete torrents in:';
    F.ChkIncompleteDir.Checked := Config.IncompleteDirEnabled;

    F.EdtIncompleteDir := TEdit.Create(TsDown);
    F.EdtIncompleteDir.Parent := TsDown;
    F.EdtIncompleteDir.Left := 16; F.EdtIncompleteDir.Top := 162; F.EdtIncompleteDir.Width := 444;
    F.EdtIncompleteDir.Text := Config.IncompleteDir;

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
    F.SpnPeerPort.Left := 150; F.SpnPeerPort.Top := 18; F.SpnPeerPort.Width := 90;
    F.SpnPeerPort.MinValue := 1;
    F.SpnPeerPort.MaxValue := 65535;
    F.SpnPeerPort.Value := Config.PeerPort;

    BtnTestPort := TButton.Create(TsNet);
    BtnTestPort.Parent := TsNet;
    BtnTestPort.Left := 252; BtnTestPort.Top := 17; BtnTestPort.Width := 90;
    BtnTestPort.Caption := 'Test Port';
    BtnTestPort.OnClick := @F.BtnTestPortClick;

    F.LblPortStatus := TLabel.Create(TsNet);
    F.LblPortStatus.Parent := TsNet;
    F.LblPortStatus.Left := 354; F.LblPortStatus.Top := 22;
    F.LblPortStatus.Font.Style := [fsBold];
    F.LblPortStatus.Caption := '';

    F.ChkRandomPort := TCheckBox.Create(TsNet);
    F.ChkRandomPort.Parent := TsNet;
    F.ChkRandomPort.Left := 16; F.ChkRandomPort.Top := 58;
    F.ChkRandomPort.Caption := 'Pick a random port every time Transmission is started';
    F.ChkRandomPort.Checked := Config.PeerPortRandomOnStart;

    F.ChkPortForwarding := TCheckBox.Create(TsNet);
    F.ChkPortForwarding.Parent := TsNet;
    F.ChkPortForwarding.Left := 16; F.ChkPortForwarding.Top := 88;
    F.ChkPortForwarding.Caption := 'Use UPnP or NAT-PMP port forwarding from my router';
    F.ChkPortForwarding.Checked := Config.PortForwardingEnabled;

    F.ChkUtp := TCheckBox.Create(TsNet);
    F.ChkUtp.Parent := TsNet;
    F.ChkUtp.Left := 16; F.ChkUtp.Top := 118;
    F.ChkUtp.Caption := 'Enable µTP for peer communication';
    F.ChkUtp.Checked := Config.UtpEnabled;

    // 6. Session / Remote Tab
    TsRemote := PC.AddTabSheet;
    TsRemote.Caption := 'Session';

    F.RbLocalSession := TRadioButton.Create(TsRemote);
    F.RbLocalSession.Parent := TsRemote;
    F.RbLocalSession.Left := 16; F.RbLocalSession.Top := 20;
    F.RbLocalSession.Caption := 'Start Local Session (local transmission-daemon)';
    F.RbLocalSession.Checked := Rpc.IsLocalSession;

    F.RbRemoteSession := TRadioButton.Create(TsRemote);
    F.RbRemoteSession.Parent := TsRemote;
    F.RbRemoteSession.Left := 16; F.RbRemoteSession.Top := 48;
    F.RbRemoteSession.Caption := 'Connect to Remote Transmission Session (RPC)';
    F.RbRemoteSession.Checked := not Rpc.IsLocalSession;

    Lbl := TLabel.Create(TsRemote);
    Lbl.Parent := TsRemote;
    Lbl.Left := 32; Lbl.Top := 84;
    Lbl.Caption := 'Host:';

    F.EdtRpcHost := TEdit.Create(TsRemote);
    F.EdtRpcHost.Parent := TsRemote;
    F.EdtRpcHost.Left := 110; F.EdtRpcHost.Top := 80; F.EdtRpcHost.Width := 200;
    F.EdtRpcHost.Text := Rpc.Host;

    Lbl := TLabel.Create(TsRemote);
    Lbl.Parent := TsRemote;
    Lbl.Left := 325; Lbl.Top := 84;
    Lbl.Caption := 'Port:';

    F.SpnRpcPort := TSpinEdit.Create(TsRemote);
    F.SpnRpcPort.Parent := TsRemote;
    F.SpnRpcPort.Left := 365; F.SpnRpcPort.Top := 80; F.SpnRpcPort.Width := 80;
    F.SpnRpcPort.MinValue := 1;
    F.SpnRpcPort.MaxValue := 65535;
    F.SpnRpcPort.Value := Rpc.Port;

    Lbl := TLabel.Create(TsRemote);
    Lbl.Parent := TsRemote;
    Lbl.Left := 32; Lbl.Top := 120;
    Lbl.Caption := 'Username:';

    F.EdtRpcUser := TEdit.Create(TsRemote);
    F.EdtRpcUser.Parent := TsRemote;
    F.EdtRpcUser.Left := 110; F.EdtRpcUser.Top := 116; F.EdtRpcUser.Width := 200;
    F.EdtRpcUser.Text := Rpc.Username;

    Lbl := TLabel.Create(TsRemote);
    Lbl.Parent := TsRemote;
    Lbl.Left := 32; Lbl.Top := 154;
    Lbl.Caption := 'Password:';

    F.EdtRpcPass := TEdit.Create(TsRemote);
    F.EdtRpcPass.Parent := TsRemote;
    F.EdtRpcPass.Left := 110; F.EdtRpcPass.Top := 150; F.EdtRpcPass.Width := 200;
    F.EdtRpcPass.PasswordChar := '*';
    F.EdtRpcPass.Text := Rpc.Password;

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
      Rpc.Configure(F.EdtRpcHost.Text, F.SpnRpcPort.Value, F.EdtRpcUser.Text, F.EdtRpcPass.Text, F.RbLocalSession.Checked);
      Rpc.EnsureLocalDaemonRunning;

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

      Rpc.UpdateSession(Args);
      Rpc.FetchSession(Config);
      Result := True;
    end;
  finally
    F.Free;
  end;
end;

{ 6. Set Location / Relocate Dialog }

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

{ 7. Statistics Dialog }

procedure ShowStatsDialog(Owner: TComponent; Rpc: TTransmissionRpcClient);
var
  Stats: TSessionStatsData;
  F: TForm;
  GbCur, GbTot: TGroupBox;
  BtnClose: TButton;
  CurRatio, TotRatio: Double;
begin
  if not Rpc.FetchSessionStats(Stats) then
  begin
    MessageDlg('Unable to fetch statistics: ' + Rpc.LastError, mtError, [mbOK], 0);
    Exit;
  end;

  if Stats.CurrentDownloadedBytes > 0 then
    CurRatio := Stats.CurrentUploadedBytes / Stats.CurrentDownloadedBytes
  else
    CurRatio := 0.0;

  if Stats.TotalDownloadedBytes > 0 then
    TotRatio := Stats.TotalUploadedBytes / Stats.TotalDownloadedBytes
  else
    TotRatio := 0.0;

  F := TForm.CreateNew(Owner);
  try
    F.Caption := 'Statistics';
    F.Position := poMainFormCenter;
    F.BorderStyle := bsDialog;
    F.ClientWidth := 420;
    F.ClientHeight := 340;

    GbCur := TGroupBox.Create(F);
    GbCur.Parent := F;
    GbCur.Left := 14; GbCur.Top := 12; GbCur.Width := 392; GbCur.Height := 132;
    GbCur.Caption := 'Current Session';

    AddKeyValRow(GbCur, 10, 'Uploaded:', FormatSize(Stats.CurrentUploadedBytes));
    AddKeyValRow(GbCur, 34, 'Downloaded:', FormatSize(Stats.CurrentDownloadedBytes));
    AddKeyValRow(GbCur, 58, 'Ratio:', FormatRatio(CurRatio));
    AddKeyValRow(GbCur, 82, 'Duration:', FormatDuration(Stats.CurrentSecondsActive));

    GbTot := TGroupBox.Create(F);
    GbTot.Parent := F;
    GbTot.Left := 14; GbTot.Top := 154; GbTot.Width := 392; GbTot.Height := 136;
    GbTot.Caption := Format('Total (Started %d times)', [Stats.TotalSessionCount]);

    AddKeyValRow(GbTot, 10, 'Uploaded:', FormatSize(Stats.TotalUploadedBytes));
    AddKeyValRow(GbTot, 34, 'Downloaded:', FormatSize(Stats.TotalDownloadedBytes));
    AddKeyValRow(GbTot, 58, 'Ratio:', FormatRatio(TotRatio));
    AddKeyValRow(GbTot, 82, 'Total Duration:', FormatDuration(Stats.TotalSecondsActive));

    BtnClose := TButton.Create(F);
    BtnClose.Parent := F;
    BtnClose.Left := 326; BtnClose.Top := 298; BtnClose.Width := 80;
    BtnClose.Caption := 'Close';
    BtnClose.Default := True;
    BtnClose.Cancel := True;
    BtnClose.ModalResult := mrClose;

    F.ShowModal;
  finally
    F.Free;
  end;
end;

end.
