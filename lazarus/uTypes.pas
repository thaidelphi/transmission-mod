unit uTypes;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math;

const
  TR_STATUS_STOPPED       = 0; // Torrent is stopped
  TR_STATUS_CHECK_WAIT    = 1; // Queued to check files
  TR_STATUS_CHECK         = 2; // Checking files
  TR_STATUS_DOWNLOAD_WAIT = 3; // Queued to download
  TR_STATUS_DOWNLOAD      = 4; // Downloading
  TR_STATUS_SEED_WAIT     = 5; // Queued to seed
  TR_STATUS_SEED          = 6; // Seeding

  TR_PRI_LOW    = -1;
  TR_PRI_NORMAL =  0;
  TR_PRI_HIGH   =  1;

  TR_RATIOLIMIT_GLOBAL    = 0;
  TR_RATIOLIMIT_SINGLE    = 1;
  TR_RATIOLIMIT_UNLIMITED = 2;

type
  TTorrentFileItem = record
    Index: Integer;
    Name: string;
    Length: Int64;
    BytesCompleted: Int64;
    Wanted: Boolean;
    Priority: Integer;
  end;

  TTorrentPeerItem = record
    Address: string;
    Port: Integer;
    ClientName: string;
    FlagStr: string;
    Progress: Double;
    RateToClient: Int64; // Download from peer
    RateToPeer: Int64;   // Upload to peer
    IsEncrypted: Boolean;
    IsUTP: Boolean;
  end;

  TTorrentTrackerItem = record
    Id: Integer;
    Tier: Integer;
    Announce: string;
    Host: string;
    LastAnnounceResult: string;
    LastAnnounceTime: Int64;
    LastAnnounceSucceeded: Boolean;
    SeederCount: Integer;
    LeecherCount: Integer;
    DownloadCount: Integer;
  end;

  { TTorrentItem }
  TTorrentItem = class
  public
    Id: Integer;
    Name: string;
    HashString: string;
    Status: Integer;
    PercentDone: Double;
    MetadataPercentComplete: Double;
    TotalSize: Int64;
    SizeWhenDone: Int64;
    LeftUntilDone: Int64;
    HaveValid: Int64;
    HaveUnchecked: Int64;
    RateDownload: Int64;
    RateUpload: Int64;
    UploadRatio: Double;
    UploadedEver: Int64;
    DownloadedEver: Int64;
    ETA: Int64;
    PeersConnected: Integer;
    PeersSendingToUs: Integer;
    PeersGettingFromUs: Integer;
    Error: Integer;
    ErrorString: string;
    AddedDate: Int64;
    DoneDate: Int64;
    ActivityDate: Int64;
    SecondsDownloading: Int64;
    SecondsSeeding: Int64;
    DownloadDir: string;
    IsPrivate: Boolean;
    IsFinished: Boolean;
    Creator: string;
    Comment: string;
    PieceCount: Integer;
    PieceSize: Int64;
    QueuePosition: Integer;
    BandwidthPriority: Integer;
    HonorsSessionLimits: Boolean;
    DownloadLimited: Boolean;
    DownloadLimit: Int64; // KB/s
    UploadLimited: Boolean;
    UploadLimit: Int64;   // KB/s
    SeedRatioMode: Integer;
    SeedRatioLimit: Double;
    SeedIdleMode: Integer;
    SeedIdleLimit: Integer;
    PeerLimit: Integer;
    PrimaryTrackerHost: string;
    MagnetLink: string;
    Selected: Boolean;

    Files: array of TTorrentFileItem;
    Peers: array of TTorrentPeerItem;
    Trackers: array of TTorrentTrackerItem;

    function IsPaused: Boolean;
    function IsDownloading: Boolean;
    function IsSeeding: Boolean;
    function IsVerifying: Boolean;
    function IsQueued: Boolean;
    function IsActive: Boolean;
    function HasError: Boolean;
    function HaveTotal: Int64;
    function EffectiveSeedRatioLimit(const GlobalRatioLimited: Boolean; const GlobalRatioLimit: Double): Double;
    function ShortStatusString: string;
    function FullStatusString: string;
    function ProgressSummaryString(const GlobalRatioLimited: Boolean; const GlobalRatioLimit: Double): string;
  end;

  TSessionConfig = record
    Version: string;
    RpcVersion: Integer;
    DownloadDir: string;
    IncompleteDir: string;
    IncompleteDirEnabled: Boolean;
    RenamePartialFiles: Boolean;
    StartAddedTorrents: Boolean;
    TrashOriginalTorrentFiles: Boolean;
    SpeedLimitDown: Int64; // KB/s
    SpeedLimitDownEnabled: Boolean;
    SpeedLimitUp: Int64;   // KB/s
    SpeedLimitUpEnabled: Boolean;
    AltSpeedDown: Int64;   // KB/s
    AltSpeedUp: Int64;     // KB/s
    AltSpeedEnabled: Boolean;
    AltSpeedTimeEnabled: Boolean;
    AltSpeedTimeBegin: Integer;
    AltSpeedTimeEnd: Integer;
    SeedRatioLimited: Boolean;
    SeedRatioLimit: Double;
    IdleSeedingLimited: Boolean;
    IdleSeedingLimit: Integer;
    Encryption: string; // 'required', 'preferred', 'tolerated'
    PexEnabled: Boolean;
    DhtEnabled: Boolean;
    LpdEnabled: Boolean;
    UtpEnabled: Boolean;
    BlocklistEnabled: Boolean;
    BlocklistUrl: string;
    BlocklistSize: Integer;
    PeerPort: Integer;
    PeerPortRandomOnStart: Boolean;
    PortForwardingEnabled: Boolean;
    PeerLimitGlobal: Integer;
    PeerLimitPerTorrent: Integer;
    DownloadQueueEnabled: Boolean;
    DownloadQueueSize: Integer;
    SeedQueueEnabled: Boolean;
    SeedQueueSize: Integer;
  end;

  TSessionStatsData = record
    ActiveTorrentCount: Integer;
    PausedTorrentCount: Integer;
    TorrentCount: Integer;
    DownloadSpeed: Int64;
    UploadSpeed: Int64;
    CurrentUploadedBytes: Int64;
    CurrentDownloadedBytes: Int64;
    CurrentFilesAdded: Integer;
    CurrentSessionCount: Integer;
    CurrentSecondsActive: Int64;
    TotalUploadedBytes: Int64;
    TotalDownloadedBytes: Int64;
    TotalFilesAdded: Integer;
    TotalSessionCount: Integer;
    TotalSecondsActive: Int64;
  end;

function FormatSize(Bytes: Int64): string;
function FormatSpeed(BytesPerSec: Int64): string;
function FormatRatio(Ratio: Double): string;
function FormatETA(Seconds: Int64): string;
function FormatDuration(Seconds: Int64): string;
function FormatPercent(Frac: Double): string;
function ExtractTrackerHost(const AnnounceUrl: string): string;

implementation

function FormatSize(Bytes: Int64): string;
const
  Units: array[0..4] of string = ('B', 'KB', 'MB', 'GB', 'TB');
var
  Val: Double;
  Idx: Integer;
begin
  if Bytes <= 0 then
    Exit('0 B');
  Val := Bytes;
  Idx := 0;
  while (Val >= 1024.0) and (Idx < High(Units)) do
  begin
    Val := Val / 1024.0;
    Inc(Idx);
  end;
  if Idx = 0 then
    Result := Format('%d %s', [Bytes, Units[Idx]])
  else if Val < 10.0 then
    Result := Format('%.2f %s', [Val, Units[Idx]])
  else if Val < 100.0 then
    Result := Format('%.1f %s', [Val, Units[Idx]])
  else
    Result := Format('%.0f %s', [Val, Units[Idx]]);
end;

function FormatSpeed(BytesPerSec: Int64): string;
begin
  if BytesPerSec <= 0 then
    Result := '0 B/s'
  else
    Result := FormatSize(BytesPerSec) + '/s';
end;

function FormatRatio(Ratio: Double): string;
begin
  if Ratio < 0 then
    Result := 'None'
  else if IsInfinite(Ratio) or IsNan(Ratio) then
    Result := 'Inf'
  else if Ratio < 10.0 then
    Result := Format('%.2f', [Ratio])
  else if Ratio < 100.0 then
    Result := Format('%.1f', [Ratio])
  else
    Result := Format('%.0f', [Ratio]);
end;

function FormatETA(Seconds: Int64): string;
begin
  if Seconds = -1 then
    Result := 'Done'
  else if Seconds < 0 then
    Result := 'Unknown time remaining'
  else
    Result := FormatDuration(Seconds) + ' remaining';
end;

function FormatDuration(Seconds: Int64): string;
var
  D, H, M, S: Int64;
begin
  if Seconds <= 0 then
    Exit('0s');
  D := Seconds div 86400;
  Seconds := Seconds mod 86400;
  H := Seconds div 3600;
  Seconds := Seconds mod 3600;
  M := Seconds div 60;
  S := Seconds mod 60;

  if D > 0 then
    Result := Format('%dd %dh', [D, H])
  else if H > 0 then
    Result := Format('%dh %dm', [H, M])
  else if M > 0 then
    Result := Format('%dm %ds', [M, S])
  else
    Result := Format('%ds', [S]);
end;

function FormatPercent(Frac: Double): string;
var
  Pct: Double;
begin
  Pct := EnsureRange(Frac * 100.0, 0.0, 100.0);
  if Pct >= 99.995 then
    Result := '100%'
  else if Pct < 10.0 then
    Result := Format('%.2f%%', [Pct])
  else
    Result := Format('%.1f%%', [Pct]);
end;

function ExtractTrackerHost(const AnnounceUrl: string): string;
var
  S: string;
  P: Integer;
begin
  S := Trim(AnnounceUrl);
  P := Pos('://', S);
  if P > 0 then
    Delete(S, 1, P + 2);
  P := Pos('/', S);
  if P > 0 then
    S := Copy(S, 1, P - 1);
  P := Pos(':', S);
  if P > 0 then
    S := Copy(S, 1, P - 1);
  Result := LowerCase(S);
end;

{ TTorrentItem }

function TTorrentItem.IsPaused: Boolean;
begin
  Result := Status = TR_STATUS_STOPPED;
end;

function TTorrentItem.IsDownloading: Boolean;
begin
  Result := (Status = TR_STATUS_DOWNLOAD) or (Status = TR_STATUS_DOWNLOAD_WAIT);
end;

function TTorrentItem.IsSeeding: Boolean;
begin
  Result := (Status = TR_STATUS_SEED) or (Status = TR_STATUS_SEED_WAIT);
end;

function TTorrentItem.IsVerifying: Boolean;
begin
  Result := (Status = TR_STATUS_CHECK) or (Status = TR_STATUS_CHECK_WAIT);
end;

function TTorrentItem.IsQueued: Boolean;
begin
  Result := (Status = TR_STATUS_CHECK_WAIT) or
            (Status = TR_STATUS_DOWNLOAD_WAIT) or
            (Status = TR_STATUS_SEED_WAIT);
end;

function TTorrentItem.IsActive: Boolean;
begin
  Result := (RateDownload > 0) or (RateUpload > 0) or (PeersSendingToUs > 0) or (PeersGettingFromUs > 0);
end;

function TTorrentItem.HasError: Boolean;
begin
  Result := (Error <> 0) and (Trim(ErrorString) <> '');
end;

function TTorrentItem.HaveTotal: Int64;
begin
  Result := HaveValid + HaveUnchecked;
  if (Result = 0) and (SizeWhenDone > 0) then
    Result := Round(SizeWhenDone * PercentDone);
end;

function TTorrentItem.EffectiveSeedRatioLimit(const GlobalRatioLimited: Boolean;
  const GlobalRatioLimit: Double): Double;
begin
  if SeedRatioMode = TR_RATIOLIMIT_SINGLE then
    Result := SeedRatioLimit
  else if (SeedRatioMode = TR_RATIOLIMIT_GLOBAL) and GlobalRatioLimited then
    Result := GlobalRatioLimit
  else
    Result := -1.0;
end;

function TTorrentItem.ShortStatusString: string;
begin
  if HasError then
    Exit('Error');

  case Status of
    TR_STATUS_STOPPED:
      if IsFinished then
        Result := 'Finished'
      else
        Result := 'Paused';
    TR_STATUS_CHECK_WAIT:
      Result := 'Queued for verification';
    TR_STATUS_CHECK:
      Result := Format('Verifying (%s)', [FormatPercent(PercentDone)]);
    TR_STATUS_DOWNLOAD_WAIT:
      Result := 'Queued for download';
    TR_STATUS_SEED_WAIT:
      Result := 'Queued for seeding';
    TR_STATUS_DOWNLOAD:
      begin
        Result := '';
        if RateDownload > 0 then
          Result := 'Down: ' + FormatSpeed(RateDownload);
        if RateUpload > 0 then
        begin
          if Result <> '' then Result := Result + '  ';
          Result := Result + 'Up: ' + FormatSpeed(RateUpload);
        end;
        if Result = '' then
          Result := 'Idle';
      end;
    TR_STATUS_SEED:
      begin
        if RateUpload > 0 then
          Result := Format('Ratio: %s, Up: %s', [FormatRatio(UploadRatio), FormatSpeed(RateUpload)])
        else
          Result := Format('Ratio: %s', [FormatRatio(UploadRatio)]);
      end;
  else
    Result := '';
  end;
end;

function TTorrentItem.FullStatusString: string;
begin
  if HasError then
    Exit('Error: ' + ErrorString);

  case Status of
    TR_STATUS_STOPPED:
      if IsFinished then
        Result := 'Finished'
      else
        Result := 'Paused';
    TR_STATUS_CHECK_WAIT:
      Result := 'Queued for verification';
    TR_STATUS_CHECK:
      Result := Format('Verifying local data (%s tested)', [FormatPercent(PercentDone)]);
    TR_STATUS_DOWNLOAD_WAIT:
      Result := 'Waiting to download';
    TR_STATUS_SEED_WAIT:
      Result := 'Waiting to seed';
    TR_STATUS_DOWNLOAD:
      begin
        if MetadataPercentComplete < 1.0 then
          Result := Format('Downloading metadata from %d peers (%s)',
            [PeersConnected, FormatPercent(MetadataPercentComplete)])
        else
          Result := Format('Downloading from %d of %d peers - Down: %s  Up: %s',
            [PeersSendingToUs, PeersConnected, FormatSpeed(RateDownload), FormatSpeed(RateUpload)]);
      end;
    TR_STATUS_SEED:
      Result := Format('Seeding to %d of %d peers - Up: %s',
        [PeersGettingFromUs, PeersConnected, FormatSpeed(RateUpload)]);
  else
    Result := 'Unknown';
  end;
end;

function TTorrentItem.ProgressSummaryString(const GlobalRatioLimited: Boolean;
  const GlobalRatioLimit: Double): string;
var
  Goal: Double;
begin
  Goal := EffectiveSeedRatioLimit(GlobalRatioLimited, GlobalRatioLimit);
  if MetadataPercentComplete < 1.0 then
  begin
    Result := Format('Magnetized transfer - retrieving metadata (%s)',
      [FormatPercent(MetadataPercentComplete)]);
  end
  else if LeftUntilDone > 0 then
  begin
    Result := Format('%s of %s (%s)',
      [FormatSize(HaveTotal), FormatSize(SizeWhenDone), FormatPercent(PercentDone)]);
    if IsDownloading and (ETA >= 0) then
      Result := Result + ' - ' + FormatETA(ETA);
  end
  else
  begin
    if Goal > 0 then
      Result := Format('%s, uploaded %s (Ratio: %s, Goal: %s)',
        [FormatSize(TotalSize), FormatSize(UploadedEver), FormatRatio(UploadRatio), FormatRatio(Goal)])
    else
      Result := Format('%s, uploaded %s (Ratio: %s)',
        [FormatSize(TotalSize), FormatSize(UploadedEver), FormatRatio(UploadRatio)]);
  end;
end;

end.
