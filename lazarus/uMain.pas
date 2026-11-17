unit uMain;

{$mode objfpc}{$H+}
{$HINTS OFF}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics, Dialogs, Menus, ExtCtrls,
  StdCtrls, Buttons, ComCtrls, LCLType, LCLIntf, Clipbrd, IniFiles, fpjson, Math,
  uTypes, uRpcClient, uWebServer, uDialogs;

type
  TSortMode = (
    smQueue, smActivity, smAge, smETA, smName, smProgress, smRatio, smSize, smState
  );

  TStatsDisplayMode = (
    sdmTotalRatio, sdmSessionRatio, sdmTotalTransfer, sdmSessionTransfer
  );

  { TMainForm }
  TMainForm = class(TForm)
  published
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FRpc: TTransmissionRpcClient;
    FWebServer: TTransmissionWebServer;
    FSessionConfig: TSessionConfig;
    FSessionStats: TSessionStatsData;
    FAllTorrents: TList;      // Owns TTorrentItem instances
    FFilteredTorrents: TList; // Pointers into FAllTorrents
    FKnownFinishedIds: TList; // Tracks completed IDs for tray notifications
    FFirstLoadDone: Boolean;

    FCompactView: Boolean;
    FSortMode: TSortMode;
    FReverseSort: Boolean;
    FStatsMode: TStatsDisplayMode;
    FSelectedIds: TList;
    FUpdatingFilterCombo: Boolean;

    // Top Menu
    FMainMenu: TMainMenu;
    MnuFile, MnuEdit, MnuTorrent, MnuQueue, MnuView, MnuHelp: TMenuItem;
    MiCompactView, MiToolbar, MiFilterbar, MiStatusbar, MiReverseSort: TMenuItem;
    MiSortItems: array[TSortMode] of TMenuItem;

    // Context, Status & Tray Popup Menus
    FTorrentPopup: TPopupMenu;
    FStatsPopup: TPopupMenu;
    FOptionsPopup: TPopupMenu;
    FTrayPopup: TPopupMenu;
    FTrayIcon: TTrayIcon;

    // Toolbar
    FPnlToolbar: TPanel;
    FBtnOpenFile: TSpeedButton;
    FBtnOpenUrl: TSpeedButton;
    FBtnStart: TSpeedButton;
    FBtnPause: TSpeedButton;
    FBtnRemove: TSpeedButton;
    FBtnProperties: TSpeedButton;
    FBtnWebUi: TSpeedButton;

    // Filter Bar
    FPnlFilterBar: TPanel;
    FCmbShowState: TComboBox;
    FCmbTracker: TComboBox;
    FEdtSearch: TEdit;

    // Main List
    FLstTorrents: TListBox;

    // Bottom Status Bar
    FPnlStatusBar: TPanel;
    FBtnOptionsMenu: TSpeedButton;
    FBtnAltSpeed: TSpeedButton;
    FLblStatusInfo: TLabel;
    FLblDownSpeed: TLabel;
    FLblUpSpeed: TLabel;
    FLblRatioInfo: TLabel;
    FBtnStatsMode: TSpeedButton;

    // Refresh Timer
    FTimerRefresh: TTimer;

    function GetConfigIniPath: string;
    procedure LoadAppSettings;
    procedure SaveAppSettings;

    procedure BuildMenus;
    procedure BuildToolbar;
    procedure BuildFilterBar;
    procedure BuildTorrentList;
    procedure BuildStatusBar;
    procedure BuildTrayIcon;
    procedure RenderToolbarIcons;
    procedure RenderStatusBarIcons;
    procedure DrawFileIcon(C: TCanvas; R: TRect; IsPaused, HasErr: Boolean);

    procedure ClearAllTorrents;
    procedure SaveSelectedIds;
    procedure RestoreSelectedIds;
    function GetSelectedTorrentIds: TIntegerDynArray;
    function GetFirstSelectedTorrent: TTorrentItem;
    function MatchesFilter(T: TTorrentItem): Boolean;
    procedure UpdateStateFilterCounts;
    procedure RebuildTrackerFilterList;
    procedure ApplyFilterAndSort;
    procedure UpdateActionStates;
    procedure UpdateStatusBarText;
    procedure CheckCompletedNotifications;
    procedure RefreshFromRpc;

    // Event Handlers
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
    procedure TimerRefreshTimer(Sender: TObject);

    procedure LstTorrentsDrawItem(Control: TWinControl; Index: Integer; ARect: TRect; State: TOwnerDrawState);
    procedure LstTorrentsDblClick(Sender: TObject);
    procedure LstTorrentsSelectionChange(Sender: TObject; User: Boolean);
    procedure LstTorrentsResize(Sender: TObject);
    procedure LstTorrentsKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);

    procedure FilterControlChange(Sender: TObject);

    // Actions
    procedure ActOpenFile(Sender: TObject);
    procedure ActOpenUrl(Sender: TObject);
    procedure ActNewTorrent(Sender: TObject);
    procedure ActStartSelected(Sender: TObject);
    procedure ActStartNowSelected(Sender: TObject);
    procedure ActPauseSelected(Sender: TObject);
    procedure ActStartAll(Sender: TObject);
    procedure ActPauseAll(Sender: TObject);
    procedure ActRemoveSelected(Sender: TObject);
    procedure ActDeleteSelected(Sender: TObject);
    procedure ActProperties(Sender: TObject);
    procedure ActOpenFolder(Sender: TObject);
    procedure ActVerifySelected(Sender: TObject);
    procedure ActAnnounceSelected(Sender: TObject);
    procedure ActSetLocation(Sender: TObject);
    procedure ActCopyMagnet(Sender: TObject);
    procedure ActQueueMove(Sender: TObject);
    procedure ActSelectAll(Sender: TObject);
    procedure ActDeselectAll(Sender: TObject);
    procedure ActChangeSession(Sender: TObject);
    procedure ActPreferences(Sender: TObject);
    procedure ActToggleCompactView(Sender: TObject);
    procedure ActToggleToolbar(Sender: TObject);
    procedure ActToggleFilterbar(Sender: TObject);
    procedure ActToggleStatusbar(Sender: TObject);
    procedure ActSortModeClick(Sender: TObject);
    procedure ActToggleReverseSort(Sender: TObject);
    procedure ActToggleAltSpeed(Sender: TObject);
    procedure ActOpenWebUi(Sender: TObject);
    procedure ActShowStatistics(Sender: TObject);
    procedure ActShowAbout(Sender: TObject);
    procedure ActStatsModeClick(Sender: TObject);
    procedure ActOptionsPopupClick(Sender: TObject);
    procedure ActStatsPopupClick(Sender: TObject);
    procedure ActToggleMainWindow(Sender: TObject);
    procedure ActQuit(Sender: TObject);
  public
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

var
  ActiveSortMode: TSortMode = smQueue;
  ActiveReverseSort: Boolean = False;

function CompareTorrents(Item1, Item2: Pointer): Integer;
var
  A, B: TTorrentItem;
  ValA, ValB: Double;
begin
  A := TTorrentItem(Item1);
  B := TTorrentItem(Item2);
  Result := 0;

  case ActiveSortMode of
    smQueue:
      Result := CompareValue(A.QueuePosition, B.QueuePosition);
    smActivity:
      begin
        Result := CompareValue(B.RateDownload + B.RateUpload, A.RateDownload + A.RateUpload);
        if Result = 0 then
          Result := CompareValue(B.ActivityDate, A.ActivityDate);
      end;
    smAge:
      Result := CompareValue(B.AddedDate, A.AddedDate);
    smETA:
      begin
        if (A.ETA < 0) and (B.ETA >= 0) then Result := 1
        else if (B.ETA < 0) and (A.ETA >= 0) then Result := -1
        else Result := CompareValue(A.ETA, B.ETA);
      end;
    smName:
      Result := CompareText(A.Name, B.Name);
    smProgress:
      Result := CompareValue(A.PercentDone, B.PercentDone);
    smRatio:
      begin
        ValA := A.UploadRatio;
        ValB := B.UploadRatio;
        Result := CompareValue(ValB, ValA);
      end;
    smSize:
      Result := CompareValue(B.TotalSize, A.TotalSize);
    smState:
      Result := CompareValue(B.Status, A.Status);
  end;

  if Result = 0 then
    Result := CompareText(A.Name, B.Name);

  if ActiveReverseSort then
    Result := -Result;
end;

{ TMainForm }

function TMainForm.GetConfigIniPath: string;
begin
  Result := ChangeFileExt(ParamStr(0), '.ini');
end;

procedure TMainForm.LoadAppSettings;
var
  Ini: TIniFile;
  HostStr, UserStr, PassStr, PathStr: string;
  PortNum: Integer;
  LocalSess: Boolean;
begin
  if not FileExists(GetConfigIniPath) then Exit;
  Ini := TIniFile.Create(GetConfigIniPath);
  try
    Width := Ini.ReadInteger('Window', 'Width', Width);
    Height := Ini.ReadInteger('Window', 'Height', Height);
    FCompactView := Ini.ReadBool('View', 'CompactView', True);
    FSortMode := TSortMode(EnsureRange(Ini.ReadInteger('View', 'SortMode', 0), 0, Ord(High(TSortMode))));
    FReverseSort := Ini.ReadBool('View', 'ReverseSort', False);
    FStatsMode := TStatsDisplayMode(EnsureRange(Ini.ReadInteger('View', 'StatsMode', 0), 0, 3));

    FPnlToolbar.Visible := Ini.ReadBool('View', 'ShowToolbar', True);
    FPnlFilterBar.Visible := Ini.ReadBool('View', 'ShowFilterbar', True);
    FPnlStatusBar.Visible := Ini.ReadBool('View', 'ShowStatusbar', True);

    MiCompactView.Checked := FCompactView;
    MiToolbar.Checked := FPnlToolbar.Visible;
    MiFilterbar.Checked := FPnlFilterBar.Visible;
    MiStatusbar.Checked := FPnlStatusBar.Visible;
    MiReverseSort.Checked := FReverseSort;
    MiSortItems[FSortMode].Checked := True;

    if FCompactView then
      FLstTorrents.ItemHeight := 28
    else
      FLstTorrents.ItemHeight := 68;

    LocalSess := Ini.ReadBool('Session', 'LocalSession', True);
    HostStr := Ini.ReadString('Session', 'Host', '127.0.0.1');
    PortNum := Ini.ReadInteger('Session', 'Port', 9091);
    UserStr := Ini.ReadString('Session', 'Username', '');
    PassStr := Ini.ReadString('Session', 'Password', '');
    PathStr := Ini.ReadString('Session', 'UrlPath', '/transmission/rpc');
    FRpc.Configure(HostStr, PortNum, UserStr, PassStr, LocalSess, PathStr);

    if FWebServer <> nil then
    begin
      FWebServer.Enabled := Ini.ReadBool('WebUI', 'Enabled', True);
      FWebServer.Port := Ini.ReadInteger('WebUI', 'Port', 9092);
      FWebServer.AuthEnabled := Ini.ReadBool('WebUI', 'AuthEnabled', False);
      FWebServer.Username := Ini.ReadString('WebUI', 'Username', 'admin');
    end;
  finally
    Ini.Free;
  end;
end;

procedure TMainForm.SaveAppSettings;
var
  Ini: TIniFile;
begin
  try
    Ini := TIniFile.Create(GetConfigIniPath);
    try
      if WindowState = wsNormal then
      begin
        Ini.WriteInteger('Window', 'Width', Width);
        Ini.WriteInteger('Window', 'Height', Height);
      end;
      Ini.WriteBool('View', 'CompactView', FCompactView);
      Ini.WriteInteger('View', 'SortMode', Ord(FSortMode));
      Ini.WriteBool('View', 'ReverseSort', FReverseSort);
      Ini.WriteInteger('View', 'StatsMode', Ord(FStatsMode));
      Ini.WriteBool('View', 'ShowToolbar', FPnlToolbar.Visible);
      Ini.WriteBool('View', 'ShowFilterbar', FPnlFilterBar.Visible);
      Ini.WriteBool('View', 'ShowStatusbar', FPnlStatusBar.Visible);

      Ini.WriteBool('Session', 'LocalSession', FRpc.IsLocalSession);
      Ini.WriteString('Session', 'Host', FRpc.Host);
      Ini.WriteInteger('Session', 'Port', FRpc.Port);
      Ini.WriteString('Session', 'Username', FRpc.Username);
      Ini.WriteString('Session', 'UrlPath', FRpc.UrlPath);

      if FWebServer <> nil then
      begin
        Ini.WriteBool('WebUI', 'Enabled', FWebServer.Enabled);
        Ini.WriteInteger('WebUI', 'Port', FWebServer.Port);
        Ini.WriteBool('WebUI', 'AuthEnabled', FWebServer.AuthEnabled);
        Ini.WriteString('WebUI', 'Username', FWebServer.Username);
      end;
    finally
      Ini.Free;
    end;
  except
  end;
end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  Caption := 'Transmission';
  Width := 1020;
  Height := 640;
  Constraints.MinWidth := 520;
  Constraints.MinHeight := 340;
  Position := poScreenCenter;
  AllowDropFiles := True;
  OnDropFiles := @FormDropFiles;
  Color := clWindow;
  DoubleBuffered := True;

  FAllTorrents := TList.Create;
  FFilteredTorrents := TList.Create;
  FSelectedIds := TList.Create;
  FKnownFinishedIds := TList.Create;
  FFirstLoadDone := False;
  FUpdatingFilterCombo := False;

  FCompactView := True;
  FSortMode := smQueue;
  FReverseSort := False;
  FStatsMode := sdmTotalRatio;

  FRpc := TTransmissionRpcClient.Create;
  FWebServer := TTransmissionWebServer.Create(FRpc);

  BuildMenus;
  BuildToolbar;
  BuildFilterBar;
  BuildStatusBar;
  BuildTorrentList;
  BuildTrayIcon;

  LoadAppSettings;

  // Start or connect to local transmission-daemon automatically
  FRpc.EnsureLocalDaemonRunning;
  FRpc.FetchSession(FSessionConfig);
  FWebServer.StartServer;
  RenderStatusBarIcons;
  RefreshFromRpc;

  FTimerRefresh := TTimer.Create(Self);
  FTimerRefresh.Interval := 1500;
  FTimerRefresh.OnTimer := @TimerRefreshTimer;
  FTimerRefresh.Enabled := True;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  if FTimerRefresh <> nil then
    FTimerRefresh.Enabled := False;
  SaveAppSettings;
  ClearAllTorrents;
  FKnownFinishedIds.Free;
  FFilteredTorrents.Free;
  FAllTorrents.Free;
  FSelectedIds.Free;
  FWebServer.Free;
  FRpc.Free;
end;

procedure TMainForm.ClearAllTorrents;
var
  I: Integer;
begin
  FFilteredTorrents.Clear;
  for I := 0 to FAllTorrents.Count - 1 do
    TObject(FAllTorrents[I]).Free;
  FAllTorrents.Clear;
end;

procedure TMainForm.BuildMenus;
  function AddItem(ParentItem: TMenuItem; const ACaption: string;
    AShortcut: TShortCut; AOnClick: TNotifyEvent; ATag: PtrInt = 0): TMenuItem;
  begin
    Result := TMenuItem.Create(Self);
    Result.Caption := ACaption;
    Result.ShortCut := AShortcut;
    Result.OnClick := AOnClick;
    Result.Tag := ATag;
    ParentItem.Add(Result);
  end;

  procedure AddSep(ParentItem: TMenuItem);
  var
    S: TMenuItem;
  begin
    S := TMenuItem.Create(Self);
    S.Caption := '-';
    ParentItem.Add(S);
  end;

const
  SortCaptions: array[TSortMode] of string = (
    'Sort by &Queue',
    'Sort by &Activity',
    'Sort by A&ge',
    'Sort by Time &Left',
    'Sort by &Name',
    'Sort by &Progress',
    'Sort by Rati&o',
    'Sort by Si&ze',
    'Sort by Stat&e'
  );
var
  SM: TSortMode;
  PItem: TMenuItem;
begin
  FMainMenu := TMainMenu.Create(Self);
  Menu := FMainMenu;

  // File Menu
  MnuFile := TMenuItem.Create(Self);
  MnuFile.Caption := '&File';
  FMainMenu.Items.Add(MnuFile);
  AddItem(MnuFile, '&Open...', ShortCut(Ord('O'), [ssCtrl]), @ActOpenFile);
  AddItem(MnuFile, 'Open &URL...', ShortCut(Ord('U'), [ssCtrl]), @ActOpenUrl);
  AddItem(MnuFile, '&New...', ShortCut(Ord('N'), [ssCtrl]), @ActNewTorrent);
  AddSep(MnuFile);
  AddItem(MnuFile, '&Start All', 0, @ActStartAll);
  AddItem(MnuFile, '&Pause All', 0, @ActPauseAll);
  AddSep(MnuFile);
  AddItem(MnuFile, '&Quit', ShortCut(Ord('Q'), [ssCtrl]), @ActQuit);

  // Edit Menu
  MnuEdit := TMenuItem.Create(Self);
  MnuEdit.Caption := '&Edit';
  FMainMenu.Items.Add(MnuEdit);
  AddItem(MnuEdit, '&Select All', ShortCut(Ord('A'), [ssCtrl]), @ActSelectAll);
  AddItem(MnuEdit, '&Deselect All', ShortCut(Ord('A'), [ssCtrl, ssShift]), @ActDeselectAll);
  AddSep(MnuEdit);
  AddItem(MnuEdit, 'Change &Session...', 0, @ActChangeSession);
  AddSep(MnuEdit);
  AddItem(MnuEdit, '&Preferences...', 0, @ActPreferences);

  // Torrent Menu
  MnuTorrent := TMenuItem.Create(Self);
  MnuTorrent.Caption := '&Torrent';
  FMainMenu.Items.Add(MnuTorrent);
  AddItem(MnuTorrent, '&Properties', ShortCut(VK_RETURN, [ssAlt]), @ActProperties);
  AddItem(MnuTorrent, 'Open Fold&er', ShortCut(Ord('E'), [ssCtrl]), @ActOpenFolder);
  AddSep(MnuTorrent);
  AddItem(MnuTorrent, '&Start', ShortCut(Ord('S'), [ssCtrl]), @ActStartSelected);
  AddItem(MnuTorrent, 'Start &Now', ShortCut(Ord('S'), [ssCtrl, ssShift]), @ActStartNowSelected);

  MnuQueue := TMenuItem.Create(Self);
  MnuQueue.Caption := '&Queue';
  MnuTorrent.Add(MnuQueue);
  AddItem(MnuQueue, 'Move to &Top', 0, @ActQueueMove, 1);
  AddItem(MnuQueue, 'Move &Up', 0, @ActQueueMove, 2);
  AddItem(MnuQueue, 'Move &Down', 0, @ActQueueMove, 3);
  AddItem(MnuQueue, 'Move to &Bottom', 0, @ActQueueMove, 4);

  AddItem(MnuTorrent, 'Ask Tracker for &More Peers', 0, @ActAnnounceSelected);
  AddItem(MnuTorrent, '&Pause', ShortCut(Ord('P'), [ssCtrl]), @ActPauseSelected);
  AddSep(MnuTorrent);
  AddItem(MnuTorrent, 'Set &Location...', 0, @ActSetLocation);
  AddItem(MnuTorrent, '&Verify Local Data', ShortCut(Ord('V'), [ssCtrl]), @ActVerifySelected);
  AddItem(MnuTorrent, 'Copy &Magnet Link to Clipboard', 0, @ActCopyMagnet);
  AddSep(MnuTorrent);
  AddItem(MnuTorrent, '&Remove', ShortCut(VK_DELETE, []), @ActRemoveSelected);
  AddItem(MnuTorrent, '&Delete Files and Remove', ShortCut(VK_DELETE, [ssShift]), @ActDeleteSelected);

  // View Menu
  MnuView := TMenuItem.Create(Self);
  MnuView.Caption := '&View';
  FMainMenu.Items.Add(MnuView);
  MiCompactView := AddItem(MnuView, '&Compact View', ShortCut(Ord('C'), [ssAlt]), @ActToggleCompactView);
  MiCompactView.Checked := FCompactView;
  AddItem(MnuView, 'Open &Web Interface', ShortCut(Ord('W'), [ssCtrl]), @ActOpenWebUi);
  AddSep(MnuView);
  MiToolbar := AddItem(MnuView, '&Toolbar', 0, @ActToggleToolbar);
  MiToolbar.Checked := True;
  MiFilterbar := AddItem(MnuView, '&Filterbar', 0, @ActToggleFilterbar);
  MiFilterbar.Checked := True;
  MiStatusbar := AddItem(MnuView, '&Statusbar', 0, @ActToggleStatusbar);
  MiStatusbar.Checked := True;
  AddSep(MnuView);
  for SM := Low(TSortMode) to High(TSortMode) do
  begin
    MiSortItems[SM] := AddItem(MnuView, SortCaptions[SM], 0, @ActSortModeClick, Ord(SM));
    MiSortItems[SM].RadioItem := True;
    MiSortItems[SM].GroupIndex := 10;
    MiSortItems[SM].Checked := (SM = FSortMode);
  end;
  AddSep(MnuView);
  MiReverseSort := AddItem(MnuView, 'Re&verse Sort Order', 0, @ActToggleReverseSort);

  // Help Menu
  MnuHelp := TMenuItem.Create(Self);
  MnuHelp.Caption := '&Help';
  FMainMenu.Items.Add(MnuHelp);
  AddItem(MnuHelp, '&Statistics', 0, @ActShowStatistics);
  AddSep(MnuHelp);
  AddItem(MnuHelp, '&About Transmission', ShortCut(VK_F1, []), @ActShowAbout);

  // Context Menu on Torrent List
  FTorrentPopup := TPopupMenu.Create(Self);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Properties...'; PItem.OnClick := @ActProperties; FTorrentPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Open Folder'; PItem.OnClick := @ActOpenFolder; FTorrentPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := '-'; FTorrentPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Start'; PItem.OnClick := @ActStartSelected; FTorrentPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Start Now'; PItem.OnClick := @ActStartNowSelected; FTorrentPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Pause'; PItem.OnClick := @ActPauseSelected; FTorrentPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := '-'; FTorrentPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Set Location...'; PItem.OnClick := @ActSetLocation; FTorrentPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Verify Local Data'; PItem.OnClick := @ActVerifySelected; FTorrentPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Ask Tracker for More Peers'; PItem.OnClick := @ActAnnounceSelected; FTorrentPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Copy Magnet Link to Clipboard'; PItem.OnClick := @ActCopyMagnet; FTorrentPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := '-'; FTorrentPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Remove'; PItem.OnClick := @ActRemoveSelected; FTorrentPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Delete Files and Remove'; PItem.OnClick := @ActDeleteSelected; FTorrentPopup.Items.Add(PItem);

  // Ratio / Stats Popup Menu
  FStatsPopup := TPopupMenu.Create(Self);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Total Ratio'; PItem.Tag := 0; PItem.OnClick := @ActStatsModeClick; FStatsPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Session Ratio'; PItem.Tag := 1; PItem.OnClick := @ActStatsModeClick; FStatsPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Total Transfer'; PItem.Tag := 2; PItem.OnClick := @ActStatsModeClick; FStatsPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Session Transfer'; PItem.Tag := 3; PItem.OnClick := @ActStatsModeClick; FStatsPopup.Items.Add(PItem);

  // Hamburger Options Popup Menu
  FOptionsPopup := TPopupMenu.Create(Self);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Open Web Interface (Browser)...'; PItem.OnClick := @ActOpenWebUi; FOptionsPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Change Session...'; PItem.OnClick := @ActChangeSession; FOptionsPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Preferences...'; PItem.OnClick := @ActPreferences; FOptionsPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Statistics...'; PItem.OnClick := @ActShowStatistics; FOptionsPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := '-'; FOptionsPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Compact View'; PItem.OnClick := @ActToggleCompactView; FOptionsPopup.Items.Add(PItem);
end;

procedure TMainForm.BuildTrayIcon;
var
  PItem: TMenuItem;
begin
  FTrayPopup := TPopupMenu.Create(Self);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Show / Hide Transmission'; PItem.OnClick := @ActToggleMainWindow; FTrayPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Open Web Interface...'; PItem.OnClick := @ActOpenWebUi; FTrayPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := '-'; FTrayPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Open Torrent...'; PItem.OnClick := @ActOpenFile; FTrayPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Open URL...'; PItem.OnClick := @ActOpenUrl; FTrayPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := '-'; FTrayPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Start All'; PItem.OnClick := @ActStartAll; FTrayPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Pause All'; PItem.OnClick := @ActPauseAll; FTrayPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Alternative Speed Limits'; PItem.OnClick := @ActToggleAltSpeed; FTrayPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := '-'; FTrayPopup.Items.Add(PItem);
  PItem := TMenuItem.Create(Self); PItem.Caption := 'Quit'; PItem.OnClick := @ActQuit; FTrayPopup.Items.Add(PItem);

  FTrayIcon := TTrayIcon.Create(Self);
  FTrayIcon.Hint := 'Transmission';
  FTrayIcon.PopUpMenu := FTrayPopup;
  FTrayIcon.OnDblClick := @ActToggleMainWindow;
  if not Application.Icon.Empty then
    FTrayIcon.Icon.Assign(Application.Icon);
  FTrayIcon.Visible := True;
end;

procedure TMainForm.BuildToolbar;
  function CreateToolBtn(ALeft: Integer; const AHint: string; AOnClick: TNotifyEvent): TSpeedButton;
  begin
    Result := TSpeedButton.Create(FPnlToolbar);
    Result.Parent := FPnlToolbar;
    Result.Left := ALeft;
    Result.Top := 4;
    Result.Width := 34;
    Result.Height := 32;
    Result.Flat := True;
    Result.Hint := AHint;
    Result.ShowHint := True;
    Result.OnClick := AOnClick;
  end;
var
  Sep: TBevel;
begin
  FPnlToolbar := TPanel.Create(Self);
  FPnlToolbar.Parent := Self;
  FPnlToolbar.Align := alTop;
  FPnlToolbar.Height := 40;
  FPnlToolbar.BevelOuter := bvNone;
  FPnlToolbar.Color := RGBToColor(246, 246, 246);
  FPnlToolbar.DoubleBuffered := True;

  FBtnOpenFile := CreateToolBtn(6, 'Open a torrent (Ctrl+O)', @ActOpenFile);
  FBtnOpenUrl := CreateToolBtn(42, 'Open URL or Magnet link (Ctrl+U)', @ActOpenUrl);
  FBtnStart := CreateToolBtn(78, 'Start selected torrents (Ctrl+S)', @ActStartSelected);
  FBtnPause := CreateToolBtn(114, 'Pause selected torrents (Ctrl+P)', @ActPauseSelected);
  FBtnRemove := CreateToolBtn(150, 'Remove selected torrents (Del)', @ActRemoveSelected);

  Sep := TBevel.Create(FPnlToolbar);
  Sep.Parent := FPnlToolbar;
  Sep.Shape := bsLeftLine;
  Sep.Left := 190;
  Sep.Top := 7;
  Sep.Width := 2;
  Sep.Height := 26;

  FBtnProperties := CreateToolBtn(198, 'Show torrent properties (Alt+Enter)', @ActProperties);
  FBtnWebUi := CreateToolBtn(236, 'Open Web Interface in Browser (Ctrl+W)', @ActOpenWebUi);

  RenderToolbarIcons;
end;

procedure TMainForm.RenderToolbarIcons;
  procedure AssignBtnIcon(Btn: TSpeedButton; Kind: Integer);
  var
    Bmp: TBitmap;
    C: TCanvas;
    PenCol: TColor;
  begin
    Bmp := TBitmap.Create;
    try
      Bmp.SetSize(24, 24);
      Bmp.Transparent := True;
      Bmp.TransparentColor := clFuchsia;
      C := Bmp.Canvas;
      C.Brush.Color := clFuchsia;
      C.FillRect(0, 0, 24, 24);

      PenCol := RGBToColor(68, 68, 68);
      C.Pen.Color := PenCol;
      C.Pen.Width := 2;
      C.Brush.Style := bsClear;

      case Kind of
        1: // Open File (Page outline + up arrow)
          begin
            C.Polygon([Point(5, 3), Point(14, 3), Point(19, 8), Point(19, 21), Point(5, 21)]);
            C.MoveTo(14, 3); C.LineTo(14, 8); C.LineTo(19, 8);
            C.MoveTo(12, 18); C.LineTo(12, 10);
            C.MoveTo(9, 13); C.LineTo(12, 10); C.LineTo(15, 13);
          end;
        2: // Open URL (Globe)
          begin
            C.Ellipse(3, 3, 21, 21);
            C.Ellipse(8, 3, 16, 21);
            C.MoveTo(3, 12); C.LineTo(21, 12);
            C.MoveTo(5, 7); C.LineTo(19, 7);
            C.MoveTo(5, 17); C.LineTo(19, 17);
          end;
        3: // Start (Play triangle)
          begin
            C.Polygon([Point(7, 4), Point(19, 12), Point(7, 20)]);
          end;
        4: // Pause (Two vertical bars)
          begin
            C.MoveTo(8, 5); C.LineTo(8, 19);
            C.MoveTo(16, 5); C.LineTo(16, 19);
          end;
        5: // Remove (Horizontal minus line)
          begin
            C.MoveTo(4, 12); C.LineTo(20, 12);
          end;
        6: // Properties (Circle with 'i')
          begin
            C.Ellipse(3, 3, 21, 21);
            C.MoveTo(12, 10); C.LineTo(12, 17);
            C.Pixels[12, 7] := PenCol;
            C.Pixels[11, 7] := PenCol;
            C.Pixels[12, 6] := PenCol;
          end;
        7: // Web UI (Browser window with top bar)
          begin
            C.Rectangle(3, 4, 21, 20);
            C.MoveTo(3, 9); C.LineTo(21, 9);
            C.Pixels[6, 6] := PenCol;
            C.Pixels[9, 6] := PenCol;
            C.MoveTo(8, 14); C.LineTo(16, 14);
          end;
      end;
      Btn.Glyph.Assign(Bmp);
    finally
      Bmp.Free;
    end;
  end;
begin
  AssignBtnIcon(FBtnOpenFile, 1);
  AssignBtnIcon(FBtnOpenUrl, 2);
  AssignBtnIcon(FBtnStart, 3);
  AssignBtnIcon(FBtnPause, 4);
  AssignBtnIcon(FBtnRemove, 5);
  AssignBtnIcon(FBtnProperties, 6);
  AssignBtnIcon(FBtnWebUi, 7);
end;

procedure TMainForm.RenderStatusBarIcons;
var
  Bmp: TBitmap;
  C: TCanvas;
  TurtleCol: TColor;
begin
  // 1. Hamburger menu icon (16x16)
  Bmp := TBitmap.Create;
  try
    Bmp.SetSize(16, 16);
    Bmp.Transparent := True;
    Bmp.TransparentColor := clFuchsia;
    C := Bmp.Canvas;
    C.Brush.Color := clFuchsia;
    C.FillRect(0, 0, 16, 16);
    C.Pen.Color := RGBToColor(70, 70, 70);
    C.Pen.Width := 2;
    C.MoveTo(3, 4); C.LineTo(13, 4);
    C.MoveTo(3, 8); C.LineTo(13, 8);
    C.MoveTo(3, 12); C.LineTo(13, 12);
    FBtnOptionsMenu.Caption := '';
    FBtnOptionsMenu.Glyph.Assign(Bmp);
  finally
    Bmp.Free;
  end;

  // 2. Turtle / Alt-Speed icon (16x16)
  Bmp := TBitmap.Create;
  try
    Bmp.SetSize(16, 16);
    Bmp.Transparent := True;
    Bmp.TransparentColor := clFuchsia;
    C := Bmp.Canvas;
    C.Brush.Color := clFuchsia;
    C.FillRect(0, 0, 16, 16);
    if FSessionConfig.AltSpeedEnabled then
      TurtleCol := RGBToColor(35, 135, 225)
    else
      TurtleCol := RGBToColor(90, 90, 90);
    C.Brush.Style := bsSolid;
    C.Brush.Color := TurtleCol;
    C.Pen.Color := TurtleCol;
    C.Pen.Width := 1;
    // Shell dome
    C.Chord(2, 5, 12, 14, 12, 10, 2, 10);
    // Head
    C.Ellipse(11, 7, 15, 10);
    // Legs
    C.Rectangle(3, 10, 5, 13);
    C.Rectangle(9, 10, 11, 13);
    FBtnAltSpeed.Caption := '';
    FBtnAltSpeed.Glyph.Assign(Bmp);
  finally
    Bmp.Free;
  end;

  // 3. Ratio circle icon (16x16)
  Bmp := TBitmap.Create;
  try
    Bmp.SetSize(16, 16);
    Bmp.Transparent := True;
    Bmp.TransparentColor := clFuchsia;
    C := Bmp.Canvas;
    C.Brush.Color := clFuchsia;
    C.FillRect(0, 0, 16, 16);
    C.Pen.Color := RGBToColor(95, 95, 95);
    C.Pen.Width := 1;
    C.Brush.Style := bsClear;
    C.Ellipse(2, 2, 14, 14);
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(120, 120, 120);
    C.Pie(2, 2, 14, 14, 8, 2, 8, 14);
    FBtnStatsMode.Caption := '';
    FBtnStatsMode.Glyph.Assign(Bmp);
  finally
    Bmp.Free;
  end;
end;

procedure TMainForm.BuildFilterBar;
var
  LblShow: TLabel;
  TopLine, BotLine: TBevel;
begin
  FPnlFilterBar := TPanel.Create(Self);
  FPnlFilterBar.Parent := Self;
  FPnlFilterBar.Align := alTop;
  FPnlFilterBar.Height := 34;
  FPnlFilterBar.BevelOuter := bvNone;
  FPnlFilterBar.Color := RGBToColor(246, 246, 246);
  FPnlFilterBar.DoubleBuffered := True;

  TopLine := TBevel.Create(FPnlFilterBar);
  TopLine.Parent := FPnlFilterBar;
  TopLine.Align := alTop;
  TopLine.Height := 2;
  TopLine.Shape := bsTopLine;

  BotLine := TBevel.Create(FPnlFilterBar);
  BotLine.Parent := FPnlFilterBar;
  BotLine.Align := alBottom;
  BotLine.Height := 2;
  BotLine.Shape := bsBottomLine;

  LblShow := TLabel.Create(FPnlFilterBar);
  LblShow.Parent := FPnlFilterBar;
  LblShow.Left := 8;
  LblShow.Top := 9;
  LblShow.Caption := 'Show:';

  FCmbShowState := TComboBox.Create(FPnlFilterBar);
  FCmbShowState.Parent := FPnlFilterBar;
  FCmbShowState.Left := 48;
  FCmbShowState.Top := 5;
  FCmbShowState.Width := 155;
  FCmbShowState.Style := csDropDownList;
  FCmbShowState.Items.Add('All');
  FCmbShowState.Items.Add('Active');
  FCmbShowState.Items.Add('Downloading');
  FCmbShowState.Items.Add('Seeding');
  FCmbShowState.Items.Add('Paused');
  FCmbShowState.Items.Add('Finished');
  FCmbShowState.Items.Add('Verifying');
  FCmbShowState.Items.Add('Error');
  FCmbShowState.ItemIndex := 0;
  FCmbShowState.OnChange := @FilterControlChange;

  FCmbTracker := TComboBox.Create(FPnlFilterBar);
  FCmbTracker.Parent := FPnlFilterBar;
  FCmbTracker.Left := 210;
  FCmbTracker.Top := 5;
  FCmbTracker.Width := 160;
  FCmbTracker.Style := csDropDownList;
  FCmbTracker.Items.Add('All');
  FCmbTracker.ItemIndex := 0;
  FCmbTracker.OnChange := @FilterControlChange;

  FEdtSearch := TEdit.Create(FPnlFilterBar);
  FEdtSearch.Parent := FPnlFilterBar;
  FEdtSearch.Left := FPnlFilterBar.Width - 235;
  FEdtSearch.Top := 5;
  FEdtSearch.Width := 227;
  FEdtSearch.Anchors := [akTop, akRight];
  FEdtSearch.TextHint := 'Search...';
  FEdtSearch.OnChange := @FilterControlChange;
end;

procedure TMainForm.BuildStatusBar;
var
  TopLine: TBevel;
begin
  FPnlStatusBar := TPanel.Create(Self);
  FPnlStatusBar.Parent := Self;
  FPnlStatusBar.Align := alBottom;
  FPnlStatusBar.Height := 28;
  FPnlStatusBar.BevelOuter := bvNone;
  FPnlStatusBar.Color := RGBToColor(246, 246, 246);
  FPnlStatusBar.DoubleBuffered := True;

  TopLine := TBevel.Create(FPnlStatusBar);
  TopLine.Parent := FPnlStatusBar;
  TopLine.Align := alTop;
  TopLine.Height := 2;
  TopLine.Shape := bsTopLine;

  FBtnOptionsMenu := TSpeedButton.Create(FPnlStatusBar);
  FBtnOptionsMenu.Parent := FPnlStatusBar;
  FBtnOptionsMenu.Left := 4;
  FBtnOptionsMenu.Top := 3;
  FBtnOptionsMenu.Width := 24;
  FBtnOptionsMenu.Height := 22;
  FBtnOptionsMenu.Flat := True;
  FBtnOptionsMenu.Hint := 'Transmission Options';
  FBtnOptionsMenu.ShowHint := True;
  FBtnOptionsMenu.OnClick := @ActOptionsPopupClick;

  FBtnAltSpeed := TSpeedButton.Create(FPnlStatusBar);
  FBtnAltSpeed.Parent := FPnlStatusBar;
  FBtnAltSpeed.Left := 30;
  FBtnAltSpeed.Top := 3;
  FBtnAltSpeed.Width := 28;
  FBtnAltSpeed.Height := 22;
  FBtnAltSpeed.Flat := True;
  FBtnAltSpeed.GroupIndex := 2;
  FBtnAltSpeed.AllowAllUp := True;
  FBtnAltSpeed.Hint := 'Alternative Speed Limits (Turtle Mode)';
  FBtnAltSpeed.ShowHint := True;
  FBtnAltSpeed.OnClick := @ActToggleAltSpeed;

  FLblStatusInfo := TLabel.Create(FPnlStatusBar);
  FLblStatusInfo.Parent := FPnlStatusBar;
  FLblStatusInfo.Left := 66;
  FLblStatusInfo.Top := 6;
  FLblStatusInfo.Caption := '';

  FBtnStatsMode := TSpeedButton.Create(FPnlStatusBar);
  FBtnStatsMode.Parent := FPnlStatusBar;
  FBtnStatsMode.Left := FPnlStatusBar.Width - 28;
  FBtnStatsMode.Top := 3;
  FBtnStatsMode.Width := 24;
  FBtnStatsMode.Height := 22;
  FBtnStatsMode.Flat := True;
  FBtnStatsMode.Anchors := [akTop, akRight];
  FBtnStatsMode.Hint := 'Select Statistics Display Mode';
  FBtnStatsMode.ShowHint := True;
  FBtnStatsMode.OnClick := @ActStatsPopupClick;

  FLblRatioInfo := TLabel.Create(FPnlStatusBar);
  FLblRatioInfo.Parent := FPnlStatusBar;
  FLblRatioInfo.Left := FPnlStatusBar.Width - 155;
  FLblRatioInfo.Top := 6;
  FLblRatioInfo.Width := 122;
  FLblRatioInfo.Alignment := taRightJustify;
  FLblRatioInfo.Anchors := [akTop, akRight];
  FLblRatioInfo.Caption := 'Ratio: 0.00';

  FLblUpSpeed := TLabel.Create(FPnlStatusBar);
  FLblUpSpeed.Parent := FPnlStatusBar;
  FLblUpSpeed.Left := FPnlStatusBar.Width - 260;
  FLblUpSpeed.Top := 6;
  FLblUpSpeed.Width := 95;
  FLblUpSpeed.Alignment := taRightJustify;
  FLblUpSpeed.Anchors := [akTop, akRight];
  FLblUpSpeed.Caption := '';

  FLblDownSpeed := TLabel.Create(FPnlStatusBar);
  FLblDownSpeed.Parent := FPnlStatusBar;
  FLblDownSpeed.Left := FPnlStatusBar.Width - 365;
  FLblDownSpeed.Top := 6;
  FLblDownSpeed.Width := 95;
  FLblDownSpeed.Alignment := taRightJustify;
  FLblDownSpeed.Anchors := [akTop, akRight];
  FLblDownSpeed.Caption := '';
end;

procedure TMainForm.BuildTorrentList;
begin
  FLstTorrents := TListBox.Create(Self);
  FLstTorrents.Parent := Self;
  FLstTorrents.Align := alClient;
  FLstTorrents.BorderStyle := bsNone;
  FLstTorrents.Style := lbOwnerDrawFixed;
  FLstTorrents.ItemHeight := 28;
  FLstTorrents.MultiSelect := True;
  FLstTorrents.ExtendedSelect := True;
  FLstTorrents.Color := clWindow;
  FLstTorrents.DoubleBuffered := True;
  FLstTorrents.PopupMenu := FTorrentPopup;
  FLstTorrents.OnDrawItem := @LstTorrentsDrawItem;
  FLstTorrents.OnDblClick := @LstTorrentsDblClick;
  FLstTorrents.OnSelectionChange := @LstTorrentsSelectionChange;
  FLstTorrents.OnResize := @LstTorrentsResize;
  FLstTorrents.OnKeyDown := @LstTorrentsKeyDown;
end;

procedure TMainForm.DrawFileIcon(C: TCanvas; R: TRect; IsPaused, HasErr: Boolean);
var
  BorderCol, FillCol, AccCol: TColor;
begin
  if HasErr then
  begin
    BorderCol := RGBToColor(200, 45, 45);
    FillCol := RGBToColor(255, 235, 235);
    AccCol := RGBToColor(210, 50, 50);
  end
  else if IsPaused then
  begin
    BorderCol := RGBToColor(160, 160, 160);
    FillCol := RGBToColor(242, 242, 242);
    AccCol := RGBToColor(150, 150, 150);
  end
  else
  begin
    BorderCol := RGBToColor(90, 130, 180);
    FillCol := RGBToColor(240, 247, 255);
    AccCol := RGBToColor(55, 115, 195);
  end;

  C.Brush.Style := bsSolid;
  C.Brush.Color := FillCol;
  C.Pen.Color := BorderCol;
  C.Pen.Width := 1;
  C.Polygon([
    Point(R.Left + 2, R.Top + 1),
    Point(R.Right - 5, R.Top + 1),
    Point(R.Right - 1, R.Top + 5),
    Point(R.Right - 1, R.Bottom - 1),
    Point(R.Left + 2, R.Bottom - 1)
  ]);

  C.Brush.Color := AccCol;
  C.Pen.Color := AccCol;
  C.Polygon([
    Point(R.Left + 6, R.Top + 5),
    Point(R.Right - 4, (R.Top + R.Bottom) div 2),
    Point(R.Left + 6, R.Bottom - 5)
  ]);
end;

procedure TMainForm.LstTorrentsDrawItem(Control: TWinControl; Index: Integer;
  ARect: TRect; State: TOwnerDrawState);
var
  C: TCanvas;
  T: TTorrentItem;
  IsSelected: Boolean;
  BgCol, NameCol, SubCol, BarFillCol, BarBackCol, BarBorderCol: TColor;
  IconR, BarR: TRect;
  StatusStr, PctStr, Line2, Line3: string;
  StatusW, FillW, TextW, TextH: Integer;
  PctFrac: Double;
begin
  if (Index < 0) or (Index >= FFilteredTorrents.Count) then Exit;
  T := TTorrentItem(FFilteredTorrents[Index]);
  C := FLstTorrents.Canvas;
  IsSelected := odSelected in State;

  if IsSelected then
    BgCol := RGBToColor(204, 228, 247)
  else if Odd(Index) then
    BgCol := RGBToColor(249, 249, 249)
  else
    BgCol := clWindow;

  C.Brush.Style := bsSolid;
  C.Brush.Color := BgCol;
  C.FillRect(ARect);

  if T.HasError then
    NameCol := RGBToColor(200, 30, 30)
  else if T.IsPaused then
    NameCol := RGBToColor(120, 120, 120)
  else
    NameCol := RGBToColor(25, 25, 25);

  SubCol := RGBToColor(95, 95, 95);

  if T.HasError then
  begin
    BarFillCol := RGBToColor(215, 70, 70);
    BarBackCol := RGBToColor(245, 220, 220);
    BarBorderCol := RGBToColor(185, 60, 60);
  end
  else if T.IsPaused then
  begin
    BarFillCol := RGBToColor(165, 165, 165);
    BarBackCol := RGBToColor(232, 232, 232);
    BarBorderCol := RGBToColor(150, 150, 150);
  end
  else if T.IsSeeding or (T.PercentDone >= 0.9999) then
  begin
    BarFillCol := RGBToColor(38, 162, 69);
    BarBackCol := RGBToColor(214, 238, 219);
    BarBorderCol := RGBToColor(32, 138, 58);
  end
  else
  begin
    BarFillCol := RGBToColor(52, 132, 228);
    BarBackCol := RGBToColor(216, 232, 250);
    BarBorderCol := RGBToColor(42, 112, 198);
  end;

  PctFrac := EnsureRange(T.PercentDone, 0.0, 1.0);

  if FCompactView then
  begin
    IconR := Rect(ARect.Left + 8, ARect.Top + 6, ARect.Left + 24, ARect.Top + 22);
    DrawFileIcon(C, IconR, T.IsPaused, T.HasError);

    BarR := Rect(ARect.Right - 92, ARect.Top + 6, ARect.Right - 8, ARect.Bottom - 6);

    C.Brush.Color := BarBackCol;
    C.Pen.Color := BarBorderCol;
    C.Rectangle(BarR);

    FillW := Round((BarR.Right - BarR.Left - 2) * PctFrac);
    if FillW > 0 then
    begin
      C.Brush.Color := BarFillCol;
      C.Pen.Style := psClear;
      C.FillRect(Rect(BarR.Left + 1, BarR.Top + 1, BarR.Left + 1 + FillW, BarR.Bottom - 1));
      C.Pen.Style := psSolid;
    end;

    PctStr := Format('%d%%', [Round(PctFrac * 100)]);
    C.Font.Name := 'Segoe UI';
    C.Font.Size := 8;
    C.Font.Style := [];
    TextW := C.TextWidth(PctStr);
    TextH := C.TextHeight(PctStr);
    C.Brush.Style := bsClear;
    if FillW > (BarR.Right - BarR.Left) div 2 then
      C.Font.Color := clWhite
    else
      C.Font.Color := RGBToColor(40, 40, 40);
    C.TextOut(
      BarR.Left + ((BarR.Right - BarR.Left) - TextW) div 2,
      BarR.Top + ((BarR.Bottom - BarR.Top) - TextH) div 2,
      PctStr
    );

    StatusStr := T.ShortStatusString;
    C.Font.Size := 8;
    C.Font.Color := SubCol;
    StatusW := C.TextWidth(StatusStr);
    C.TextOut(BarR.Left - StatusW - 10, ARect.Top + ((ARect.Bottom - ARect.Top) - C.TextHeight(StatusStr)) div 2, StatusStr);

    C.Font.Size := 9;
    C.Font.Style := [];
    C.Font.Color := NameCol;
    C.TextRect(
      Rect(IconR.Right + 8, ARect.Top + 2, BarR.Left - StatusW - 18, ARect.Bottom - 2),
      IconR.Right + 8,
      ARect.Top + ((ARect.Bottom - ARect.Top) - C.TextHeight(T.Name)) div 2,
      T.Name
    );
  end
  else
  begin
    IconR := Rect(ARect.Left + 10, ARect.Top + 18, ARect.Left + 34, ARect.Top + 42);
    DrawFileIcon(C, IconR, T.IsPaused, T.HasError);

    C.Brush.Style := bsClear;

    C.Font.Name := 'Segoe UI';
    C.Font.Size := 9;
    C.Font.Style := [fsBold];
    C.Font.Color := NameCol;
    C.TextOut(IconR.Right + 10, ARect.Top + 4, T.Name);

    Line2 := T.FullStatusString;
    C.Font.Size := 8;
    C.Font.Style := [];
    C.Font.Color := SubCol;
    C.TextOut(IconR.Right + 10, ARect.Top + 21, Line2);

    BarR := Rect(IconR.Right + 10, ARect.Top + 37, ARect.Right - 12, ARect.Top + 49);
    C.Brush.Style := bsSolid;
    C.Brush.Color := BarBackCol;
    C.Pen.Color := BarBorderCol;
    C.Rectangle(BarR);

    FillW := Round((BarR.Right - BarR.Left - 2) * PctFrac);
    if FillW > 0 then
    begin
      C.Brush.Color := BarFillCol;
      C.Pen.Style := psClear;
      C.FillRect(Rect(BarR.Left + 1, BarR.Top + 1, BarR.Left + 1 + FillW, BarR.Bottom - 1));
      C.Pen.Style := psSolid;
    end;

    Line3 := T.ProgressSummaryString(FSessionConfig.SeedRatioLimited, FSessionConfig.SeedRatioLimit);
    C.Brush.Style := bsClear;
    C.Font.Size := 8;
    C.Font.Color := SubCol;
    C.TextOut(IconR.Right + 10, ARect.Top + 51, Line3);

    C.Pen.Color := RGBToColor(236, 236, 236);
    C.MoveTo(ARect.Left, ARect.Bottom - 1);
    C.LineTo(ARect.Right, ARect.Bottom - 1);
  end;
end;

procedure TMainForm.LstTorrentsResize(Sender: TObject);
begin
  FLstTorrents.Invalidate;
end;

procedure TMainForm.LstTorrentsKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (Shift = []) then
  begin
    ActProperties(Self);
    Key := 0;
  end;
end;

procedure TMainForm.SaveSelectedIds;
var
  I: Integer;
begin
  FSelectedIds.Clear;
  for I := 0 to FLstTorrents.Items.Count - 1 do
    if FLstTorrents.Selected[I] and (I < FFilteredTorrents.Count) then
      FSelectedIds.Add( {%H-}Pointer(PtrUInt(TTorrentItem(FFilteredTorrents[I]).Id)) );
end;

procedure TMainForm.RestoreSelectedIds;
var
  I: Integer;
  T: TTorrentItem;
begin
  for I := 0 to FFilteredTorrents.Count - 1 do
  begin
    T := TTorrentItem(FFilteredTorrents[I]);
    if I < FLstTorrents.Items.Count then
      FLstTorrents.Selected[I] := (FSelectedIds.IndexOf( {%H-}Pointer(PtrUInt(T.Id)) ) >= 0);
  end;
end;

function TMainForm.GetSelectedTorrentIds: TIntegerDynArray;
var
  I, CountSel: Integer;
begin
  Result := nil;
  CountSel := 0;
  SetLength(Result, FLstTorrents.Items.Count);
  for I := 0 to FLstTorrents.Items.Count - 1 do
    if FLstTorrents.Selected[I] and (I < FFilteredTorrents.Count) then
    begin
      Result[CountSel] := TTorrentItem(FFilteredTorrents[I]).Id;
      Inc(CountSel);
    end;
  SetLength(Result, CountSel);
end;

function TMainForm.GetFirstSelectedTorrent: TTorrentItem;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to FLstTorrents.Items.Count - 1 do
    if FLstTorrents.Selected[I] and (I < FFilteredTorrents.Count) then
      Exit(TTorrentItem(FFilteredTorrents[I]));
end;

function TMainForm.MatchesFilter(T: TTorrentItem): Boolean;
var
  StateIdx: Integer;
  TrkFilter, SearchStr: string;
  J: Integer;
  TrkMatch: Boolean;
begin
  Result := False;
  if T = nil then Exit;

  StateIdx := FCmbShowState.ItemIndex;
  case StateIdx of
    1: if not T.IsActive then Exit;
    2: if not T.IsDownloading then Exit;
    3: if not T.IsSeeding then Exit;
    4: if not T.IsPaused then Exit;
    5: if not T.IsFinished then Exit;
    6: if not T.IsVerifying then Exit;
    7: if not T.HasError then Exit;
  end;

  if FCmbTracker.ItemIndex > 0 then
  begin
    TrkFilter := LowerCase(Trim(FCmbTracker.Text));
    TrkMatch := SameText(T.PrimaryTrackerHost, TrkFilter);
    if not TrkMatch then
    begin
      for J := 0 to High(T.Trackers) do
        if SameText(T.Trackers[J].Host, TrkFilter) then
        begin
          TrkMatch := True;
          Break;
        end;
    end;
    if not TrkMatch then Exit;
  end;

  SearchStr := LowerCase(Trim(FEdtSearch.Text));
  if (SearchStr <> '') and
     (Pos(SearchStr, LowerCase(T.Name)) = 0) and
     (Pos(SearchStr, LowerCase(T.PrimaryTrackerHost)) = 0) then
    Exit;

  Result := True;
end;

procedure TMainForm.UpdateStateFilterCounts;
var
  CntActive, CntDown, CntSeed, CntPaused, CntFin, CntVer, CntErr: Integer;
  I, SavedIdx: Integer;
  T: TTorrentItem;
  function FmtCount(const Title: string; C: Integer): string;
  begin
    if C > 0 then
      Result := Format('%s (%d)', [Title, C])
    else
      Result := Title;
  end;
begin
  if FUpdatingFilterCombo then Exit;
  CntActive := 0; CntDown := 0; CntSeed := 0; CntPaused := 0;
  CntFin := 0; CntVer := 0; CntErr := 0;

  for I := 0 to FAllTorrents.Count - 1 do
  begin
    T := TTorrentItem(FAllTorrents[I]);
    if T.IsActive then Inc(CntActive);
    if T.IsDownloading then Inc(CntDown);
    if T.IsSeeding then Inc(CntSeed);
    if T.IsPaused then Inc(CntPaused);
    if T.IsFinished then Inc(CntFin);
    if T.IsVerifying then Inc(CntVer);
    if T.HasError then Inc(CntErr);
  end;

  FUpdatingFilterCombo := True;
  try
    SavedIdx := FCmbShowState.ItemIndex;
    if SavedIdx < 0 then SavedIdx := 0;
    FCmbShowState.Items[0] := FmtCount('All', FAllTorrents.Count);
    FCmbShowState.Items[1] := FmtCount('Active', CntActive);
    FCmbShowState.Items[2] := FmtCount('Downloading', CntDown);
    FCmbShowState.Items[3] := FmtCount('Seeding', CntSeed);
    FCmbShowState.Items[4] := FmtCount('Paused', CntPaused);
    FCmbShowState.Items[5] := FmtCount('Finished', CntFin);
    FCmbShowState.Items[6] := FmtCount('Verifying', CntVer);
    FCmbShowState.Items[7] := FmtCount('Error', CntErr);
    FCmbShowState.ItemIndex := SavedIdx;
  finally
    FUpdatingFilterCombo := False;
  end;
end;

procedure TMainForm.RebuildTrackerFilterList;
var
  Hosts: TStringList;
  I: Integer;
  T: TTorrentItem;
  CurText: string;
  Idx: Integer;
begin
  Hosts := TStringList.Create;
  try
    Hosts.Sorted := True;
    Hosts.Duplicates := dupIgnore;
    for I := 0 to FAllTorrents.Count - 1 do
    begin
      T := TTorrentItem(FAllTorrents[I]);
      if T.PrimaryTrackerHost <> '' then
        Hosts.Add(T.PrimaryTrackerHost);
    end;

    if FCmbTracker.Items.Count <> Hosts.Count + 1 then
    begin
      CurText := FCmbTracker.Text;
      FCmbTracker.Items.BeginUpdate;
      try
        FCmbTracker.Items.Clear;
        FCmbTracker.Items.Add('All');
        for I := 0 to Hosts.Count - 1 do
          FCmbTracker.Items.Add(Hosts[I]);
        Idx := FCmbTracker.Items.IndexOf(CurText);
        if Idx >= 0 then
          FCmbTracker.ItemIndex := Idx
        else
          FCmbTracker.ItemIndex := 0;
      finally
        FCmbTracker.Items.EndUpdate;
      end;
    end;
  finally
    Hosts.Free;
  end;
end;

procedure TMainForm.ApplyFilterAndSort;
var
  I: Integer;
  T: TTorrentItem;
begin
  SaveSelectedIds;

  FFilteredTorrents.Clear;
  for I := 0 to FAllTorrents.Count - 1 do
  begin
    T := TTorrentItem(FAllTorrents[I]);
    if MatchesFilter(T) then
      FFilteredTorrents.Add(T);
  end;

  ActiveSortMode := FSortMode;
  ActiveReverseSort := FReverseSort;
  FFilteredTorrents.Sort(@CompareTorrents);

  FLstTorrents.Items.BeginUpdate;
  try
    while FLstTorrents.Items.Count < FFilteredTorrents.Count do
      FLstTorrents.Items.Add('');
    while FLstTorrents.Items.Count > FFilteredTorrents.Count do
      FLstTorrents.Items.Delete(FLstTorrents.Items.Count - 1);
    RestoreSelectedIds;
  finally
    FLstTorrents.Items.EndUpdate;
  end;

  FLstTorrents.Invalidate;
  UpdateActionStates;
end;

procedure TMainForm.UpdateActionStates;
var
  HasSel: Boolean;
begin
  HasSel := Length(GetSelectedTorrentIds) > 0;
  FBtnStart.Enabled := HasSel;
  FBtnPause.Enabled := HasSel;
  FBtnRemove.Enabled := HasSel;
  FBtnProperties.Enabled := HasSel;
end;

procedure TMainForm.UpdateStatusBarText;
var
  RatioVal: Double;
begin
  FBtnAltSpeed.Down := FSessionConfig.AltSpeedEnabled;

  if not FRpc.Connected then
  begin
    FLblStatusInfo.Caption := 'Disconnected (' + FRpc.LastError + ')';
    FLblDownSpeed.Caption := '';
    FLblUpSpeed.Caption := '';
    Exit;
  end;

  if FFilteredTorrents.Count <> FAllTorrents.Count then
    FLblStatusInfo.Caption := Format('%d of %d torrents', [FFilteredTorrents.Count, FAllTorrents.Count])
  else if FAllTorrents.Count = 1 then
    FLblStatusInfo.Caption := '1 torrent'
  else if FAllTorrents.Count > 1 then
    FLblStatusInfo.Caption := Format('%d torrents', [FAllTorrents.Count])
  else
    FLblStatusInfo.Caption := '';

  if not FRpc.IsLocalSession then
  begin
    if FLblStatusInfo.Caption <> '' then
      FLblStatusInfo.Caption := FLblStatusInfo.Caption + '  [' + FRpc.Host + ']'
    else
      FLblStatusInfo.Caption := '[' + FRpc.Host + ']';
  end;

  if FSessionStats.DownloadSpeed > 0 then
    FLblDownSpeed.Caption := 'Down: ' + FormatSpeed(FSessionStats.DownloadSpeed)
  else
    FLblDownSpeed.Caption := '';

  if FSessionStats.UploadSpeed > 0 then
    FLblUpSpeed.Caption := 'Up: ' + FormatSpeed(FSessionStats.UploadSpeed)
  else
    FLblUpSpeed.Caption := '';

  case FStatsMode of
    sdmTotalRatio:
      begin
        if FSessionStats.TotalDownloadedBytes > 0 then
          RatioVal := FSessionStats.TotalUploadedBytes / FSessionStats.TotalDownloadedBytes
        else
          RatioVal := 0.0;
        FLblRatioInfo.Caption := 'Ratio: ' + FormatRatio(RatioVal);
      end;
    sdmSessionRatio:
      begin
        if FSessionStats.CurrentDownloadedBytes > 0 then
          RatioVal := FSessionStats.CurrentUploadedBytes / FSessionStats.CurrentDownloadedBytes
        else
          RatioVal := 0.0;
        FLblRatioInfo.Caption := 'Session Ratio: ' + FormatRatio(RatioVal);
      end;
    sdmTotalTransfer:
      FLblRatioInfo.Caption := Format('D: %s  U: %s',
        [FormatSize(FSessionStats.TotalDownloadedBytes), FormatSize(FSessionStats.TotalUploadedBytes)]);
    sdmSessionTransfer:
      FLblRatioInfo.Caption := Format('D: %s  U: %s',
        [FormatSize(FSessionStats.CurrentDownloadedBytes), FormatSize(FSessionStats.CurrentUploadedBytes)]);
  end;
end;

procedure TMainForm.CheckCompletedNotifications;
var
  I: Integer;
  T: TTorrentItem;
  PtrId: Pointer;
begin
  for I := 0 to FAllTorrents.Count - 1 do
  begin
    T := TTorrentItem(FAllTorrents[I]);
    PtrId := {%H-}Pointer(PtrUInt(T.Id));
    if (T.PercentDone >= 0.9999) and (T.LeftUntilDone = 0) then
    begin
      if FKnownFinishedIds.IndexOf(PtrId) < 0 then
      begin
        FKnownFinishedIds.Add(PtrId);
        if FFirstLoadDone and (FTrayIcon <> nil) then
        begin
          FTrayIcon.BalloonTitle := 'Torrent Complete';
          FTrayIcon.BalloonHint := T.Name + ' has finished downloading.';
          FTrayIcon.ShowBalloonHint;
        end;
      end;
    end;
  end;
  FFirstLoadDone := True;
end;

procedure TMainForm.RefreshFromRpc;
var
  NewList: TList;
  I: Integer;
begin
  SaveSelectedIds;
  NewList := TList.Create;
  try
    if FRpc.FetchTorrents(NewList) then
    begin
      ClearAllTorrents;
      for I := 0 to NewList.Count - 1 do
        FAllTorrents.Add(NewList[I]);
      NewList.Clear;
      FRpc.FetchSessionStats(FSessionStats);
      CheckCompletedNotifications;
      UpdateStateFilterCounts;
      RebuildTrackerFilterList;
      ApplyFilterAndSort;
    end;
    UpdateStatusBarText;
  finally
    for I := 0 to NewList.Count - 1 do
      TObject(NewList[I]).Free;
    NewList.Free;
  end;
end;

procedure TMainForm.TimerRefreshTimer(Sender: TObject);
begin
  RefreshFromRpc;
end;

procedure TMainForm.FilterControlChange(Sender: TObject);
begin
  if FUpdatingFilterCombo then Exit;
  ApplyFilterAndSort;
  UpdateStatusBarText;
end;

procedure TMainForm.LstTorrentsSelectionChange(Sender: TObject; User: Boolean);
begin
  if User then
  begin
    SaveSelectedIds;
    UpdateActionStates;
  end;
end;

procedure TMainForm.LstTorrentsDblClick(Sender: TObject);
begin
  ActProperties(Sender);
end;

procedure TMainForm.FormDropFiles(Sender: TObject; const FileNames: array of string);
var
  I, Pri: Integer;
  SelFile, DestDir, AddedName: string;
  StartNow, TrashFile: Boolean;
  Unwanted: TIntegerDynArray;
begin
  for I := Low(FileNames) to High(FileNames) do
  begin
    if SameText(ExtractFileExt(FileNames[I]), '.torrent') then
    begin
      if ShowOpenTorrentDialog(Self, FRpc, FileNames[I], FSessionConfig.DownloadDir,
           FSessionConfig.StartAddedTorrents, SelFile, DestDir, StartNow, TrashFile, Pri, Unwanted) then
      begin
        if FRpc.AddTorrentFile(SelFile, DestDir, StartNow, Pri, Unwanted, AddedName) then
        begin
          if TrashFile then
            DeleteFile(SelFile);
          RefreshFromRpc;
        end
        else
          MessageDlg('Failed to add torrent: ' + FRpc.LastError, mtError, [mbOK], 0);
      end;
    end;
  end;
end;

procedure TMainForm.ActOpenFile(Sender: TObject);
var
  Dlg: TOpenDialog;
  SelFile, DestDir, AddedName: string;
  StartNow, TrashFile: Boolean;
  Pri: Integer;
  Unwanted: TIntegerDynArray;
begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title := 'Open Torrent File';
    Dlg.Filter := 'Torrent Files (*.torrent)|*.torrent|All Files (*.*)|*.*';
    if not Dlg.Execute then Exit;
    SelFile := Dlg.FileName;
  finally
    Dlg.Free;
  end;

  if ShowOpenTorrentDialog(Self, FRpc, SelFile, FSessionConfig.DownloadDir,
       FSessionConfig.StartAddedTorrents, SelFile, DestDir, StartNow, TrashFile, Pri, Unwanted) then
  begin
    if FRpc.AddTorrentFile(SelFile, DestDir, StartNow, Pri, Unwanted, AddedName) then
    begin
      if TrashFile then
        DeleteFile(SelFile);
      RefreshFromRpc;
    end
    else
      MessageDlg('Failed to add torrent: ' + FRpc.LastError, mtError, [mbOK], 0);
  end;
end;

procedure TMainForm.ActOpenUrl(Sender: TObject);
var
  UrlStr, DestDir, AddedName: string;
  StartNow: Boolean;
  Pri: Integer;
begin
  if ShowAddUrlDialog(Self, FRpc, FSessionConfig.DownloadDir,
       FSessionConfig.StartAddedTorrents, UrlStr, DestDir, StartNow, Pri) then
  begin
    if FRpc.AddTorrentUrl(UrlStr, DestDir, StartNow, Pri, AddedName) then
      RefreshFromRpc
    else
      MessageDlg('Failed to add URL/Magnet: ' + FRpc.LastError, mtError, [mbOK], 0);
  end;
end;

procedure TMainForm.ActNewTorrent(Sender: TObject);
begin
  if ShowMakeTorrentDialog(Self, FRpc) then
    RefreshFromRpc;
end;

procedure TMainForm.ActStartSelected(Sender: TObject);
var
  Ids: TIntegerDynArray;
begin
  Ids := GetSelectedTorrentIds;
  if Length(Ids) = 0 then Exit;
  FRpc.StartTorrents(Ids, False);
  RefreshFromRpc;
end;

procedure TMainForm.ActStartNowSelected(Sender: TObject);
var
  Ids: TIntegerDynArray;
begin
  Ids := GetSelectedTorrentIds;
  if Length(Ids) = 0 then Exit;
  FRpc.StartTorrents(Ids, True);
  RefreshFromRpc;
end;

procedure TMainForm.ActPauseSelected(Sender: TObject);
var
  Ids: TIntegerDynArray;
begin
  Ids := GetSelectedTorrentIds;
  if Length(Ids) = 0 then Exit;
  FRpc.StopTorrents(Ids);
  RefreshFromRpc;
end;

procedure TMainForm.ActStartAll(Sender: TObject);
begin
  FRpc.StartTorrents([], False);
  RefreshFromRpc;
end;

procedure TMainForm.ActPauseAll(Sender: TObject);
begin
  FRpc.StopTorrents([]);
  RefreshFromRpc;
end;

procedure TMainForm.ActRemoveSelected(Sender: TObject);
var
  Ids: TIntegerDynArray;
begin
  Ids := GetSelectedTorrentIds;
  if Length(Ids) = 0 then Exit;
  if MessageDlg('Remove Torrent',
       Format('Remove %d selected torrent(s) from the list?', [Length(Ids)]),
       mtConfirmation, [mbYes, mbNo], 0) = mrYes then
  begin
    FRpc.RemoveTorrents(Ids, False);
    RefreshFromRpc;
  end;
end;

procedure TMainForm.ActDeleteSelected(Sender: TObject);
var
  Ids: TIntegerDynArray;
begin
  Ids := GetSelectedTorrentIds;
  if Length(Ids) = 0 then Exit;
  if MessageDlg('Delete Files and Remove',
       Format('Remove %d selected torrent(s) AND permanently delete their downloaded files?', [Length(Ids)]),
       mtWarning, [mbYes, mbNo], 0) = mrYes then
  begin
    FRpc.RemoveTorrents(Ids, True);
    RefreshFromRpc;
  end;
end;

procedure TMainForm.ActProperties(Sender: TObject);
var
  T: TTorrentItem;
begin
  T := GetFirstSelectedTorrent;
  if T = nil then Exit;
  ShowDetailsDialog(Self, FRpc, T);
  RefreshFromRpc;
end;

procedure TMainForm.ActOpenFolder(Sender: TObject);
var
  T: TTorrentItem;
  FolderPath: string;
begin
  T := GetFirstSelectedTorrent;
  if T = nil then Exit;
  FolderPath := StringReplace(T.DownloadDir, '/', '\', [rfReplaceAll]);
  if DirectoryExists(FolderPath) then
    OpenDocument(FolderPath);
end;

procedure TMainForm.ActVerifySelected(Sender: TObject);
var
  Ids: TIntegerDynArray;
begin
  Ids := GetSelectedTorrentIds;
  if Length(Ids) = 0 then Exit;
  FRpc.VerifyTorrents(Ids);
  RefreshFromRpc;
end;

procedure TMainForm.ActAnnounceSelected(Sender: TObject);
var
  Ids: TIntegerDynArray;
begin
  Ids := GetSelectedTorrentIds;
  if Length(Ids) = 0 then Exit;
  FRpc.ReannounceTorrents(Ids);
  RefreshFromRpc;
end;

procedure TMainForm.ActSetLocation(Sender: TObject);
var
  Ids: TIntegerDynArray;
  T: TTorrentItem;
  NewDir: string;
  MoveData: Boolean;
begin
  Ids := GetSelectedTorrentIds;
  T := GetFirstSelectedTorrent;
  if (Length(Ids) = 0) or (T = nil) then Exit;
  if ShowRelocateDialog(Self, T.DownloadDir, NewDir, MoveData) then
  begin
    FRpc.SetTorrentLocation(Ids, NewDir, MoveData);
    RefreshFromRpc;
  end;
end;

procedure TMainForm.ActCopyMagnet(Sender: TObject);
var
  T: TTorrentItem;
begin
  T := GetFirstSelectedTorrent;
  if (T <> nil) and (T.MagnetLink <> '') then
    Clipboard.AsText := T.MagnetLink;
end;

procedure TMainForm.ActQueueMove(Sender: TObject);
var
  Ids: TIntegerDynArray;
  MethodStr: string;
begin
  Ids := GetSelectedTorrentIds;
  if Length(Ids) = 0 then Exit;
  case TComponent(Sender).Tag of
    1: MethodStr := 'queue-move-top';
    2: MethodStr := 'queue-move-up';
    3: MethodStr := 'queue-move-down';
    4: MethodStr := 'queue-move-bottom';
  else
    Exit;
  end;
  FRpc.QueueMove(Ids, MethodStr);
  RefreshFromRpc;
end;

procedure TMainForm.ActSelectAll(Sender: TObject);
begin
  FLstTorrents.SelectAll;
  SaveSelectedIds;
  UpdateActionStates;
end;

procedure TMainForm.ActDeselectAll(Sender: TObject);
begin
  FLstTorrents.ClearSelection;
  SaveSelectedIds;
  UpdateActionStates;
end;

procedure TMainForm.ActChangeSession(Sender: TObject);
begin
  if ShowSessionDialog(Self, FRpc) then
  begin
    FRpc.FetchSession(FSessionConfig);
    RenderStatusBarIcons;
    RefreshFromRpc;
    SaveAppSettings;
  end;
end;

procedure TMainForm.ActPreferences(Sender: TObject);
begin
  if ShowPrefsDialog(Self, FRpc, FWebServer, FSessionConfig) then
  begin
    RenderStatusBarIcons;
    RefreshFromRpc;
    SaveAppSettings;
  end;
end;

procedure TMainForm.ActToggleCompactView(Sender: TObject);
begin
  FCompactView := not FCompactView;
  MiCompactView.Checked := FCompactView;
  if FCompactView then
    FLstTorrents.ItemHeight := 28
  else
    FLstTorrents.ItemHeight := 68;
  FLstTorrents.Invalidate;
  SaveAppSettings;
end;

procedure TMainForm.ActToggleToolbar(Sender: TObject);
begin
  FPnlToolbar.Visible := not FPnlToolbar.Visible;
  MiToolbar.Checked := FPnlToolbar.Visible;
  SaveAppSettings;
end;

procedure TMainForm.ActToggleFilterbar(Sender: TObject);
begin
  FPnlFilterBar.Visible := not FPnlFilterBar.Visible;
  MiFilterbar.Checked := FPnlFilterBar.Visible;
  SaveAppSettings;
end;

procedure TMainForm.ActToggleStatusbar(Sender: TObject);
begin
  FPnlStatusBar.Visible := not FPnlStatusBar.Visible;
  MiStatusbar.Checked := FPnlStatusBar.Visible;
  SaveAppSettings;
end;

procedure TMainForm.ActSortModeClick(Sender: TObject);
var
  TagVal: PtrInt;
begin
  TagVal := TMenuItem(Sender).Tag;
  if (TagVal >= Ord(Low(TSortMode))) and (TagVal <= Ord(High(TSortMode))) then
  begin
    FSortMode := TSortMode(TagVal);
    MiSortItems[FSortMode].Checked := True;
    ApplyFilterAndSort;
    SaveAppSettings;
  end;
end;

procedure TMainForm.ActToggleReverseSort(Sender: TObject);
begin
  FReverseSort := not FReverseSort;
  MiReverseSort.Checked := FReverseSort;
  ApplyFilterAndSort;
  SaveAppSettings;
end;

procedure TMainForm.ActToggleAltSpeed(Sender: TObject);
var
  Args: TJSONObject;
begin
  FSessionConfig.AltSpeedEnabled := not FSessionConfig.AltSpeedEnabled;
  FBtnAltSpeed.Down := FSessionConfig.AltSpeedEnabled;
  RenderStatusBarIcons;
  Args := TJSONObject.Create;
  Args.Add('alt-speed-enabled', FSessionConfig.AltSpeedEnabled);
  FRpc.UpdateSession(Args);
end;

procedure TMainForm.ActOpenWebUi(Sender: TObject);
begin
  if FWebServer <> nil then
    OpenURL(FWebServer.GetWebUrl)
  else
    OpenURL('http://127.0.0.1:9091/');
end;

procedure TMainForm.ActShowStatistics(Sender: TObject);
begin
  ShowStatsDialog(Self, FRpc);
end;

procedure TMainForm.ActShowAbout(Sender: TObject);
begin
  MessageDlg('About Transmission',
    'Transmission 4.2.0-dev (Lazarus Pascal Edition)' + LineEnding +
    'A fast and easy BitTorrent client' + LineEnding + LineEnding +
    'Backend Engine: ' + FSessionConfig.Version + LineEnding +
    'Frontend: Lazarus / FreePascal LCL',
    mtInformation, [mbOK], 0);
end;

procedure TMainForm.ActStatsModeClick(Sender: TObject);
begin
  FStatsMode := TStatsDisplayMode(TMenuItem(Sender).Tag);
  UpdateStatusBarText;
  SaveAppSettings;
end;

procedure TMainForm.ActOptionsPopupClick(Sender: TObject);
var
  P: TPoint;
begin
  P := FBtnOptionsMenu.ClientToScreen(Point(0, FBtnOptionsMenu.Height));
  FOptionsPopup.PopUp(P.X, P.Y);
end;

procedure TMainForm.ActStatsPopupClick(Sender: TObject);
var
  P: TPoint;
begin
  P := FBtnStatsMode.ClientToScreen(Point(0, FBtnStatsMode.Height));
  FStatsPopup.PopUp(P.X, P.Y);
end;

procedure TMainForm.ActToggleMainWindow(Sender: TObject);
begin
  if Visible then
    Hide
  else
  begin
    Show;
    if WindowState = wsMinimized then
      WindowState := wsNormal;
    BringToFront;
  end;
end;

procedure TMainForm.ActQuit(Sender: TObject);
begin
  Close;
end;

end.
