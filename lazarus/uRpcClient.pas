(******************************************************************************
 * ยูนิต: uRpcClient.pas
 * คำอธิบาย:
 *   คลาสจัดการการสื่อสารกับแกนหลักของ Transmission ผ่านโปรโตคอล JSON-RPC (HTTP POST)
 *   และการจัดการโปรเซส `transmission-daemon.exe` อัตโนมัติในโหมด Local Session
 *
 * กลไกสำคัญของ Transmission JSON-RPC (ตามเอกสาร docs/rpc-spec.md):
 *   1. ทุกคำสั่งส่งเป็น HTTP POST ไปที่ `/transmission/rpc` ในรูปแบบ JSON:
 *      `{"method": "<ชื่อคำสั่ง>", "arguments": { ... }}`
 *   2. ระบบป้องกัน CSRF ด้วยโทเค็น `X-Transmission-Session-Id`:
 *      เมื่อส่งคำขอครั้งแรกโดยไม่มีโทเค็น หรือโทเค็นหมดอายุ เซิร์ฟเวอร์จะตอบกลับด้วยรหัส
 *      `HTTP 409 Conflict` พร้อมแนบ Header `X-Transmission-Session-Id: <รหัสใหม่>`
 *      เมธอด `SendRpcRequest` จะอ่านค่า Header นี้แล้วส่งคำขอซ้ำให้อัตโนมัติทันที
 ******************************************************************************)
unit uRpcClient;

{$mode objfpc}{$H+}
{$WARN 5024 OFF}

interface

uses
  Classes, SysUtils, fpjson, jsonparser, fphttpclient, base64, process, uTypes;

type
  { TTransmissionRpcClient: ตัวแทนเชื่อมต่อและสั่งงาน Transmission Engine }
  TTransmissionRpcClient = class
  private
    FHost: string;               // ชื่อโฮสต์หรือ IP ของ RPC Server (ค่าเริ่มต้น '127.0.0.1')
    FPort: Integer;              // พอร์ตของ RPC Server (ค่าเริ่มต้น 9091)
    FUrlPath: string;            // พาธของ RPC Endpoint (ค่าเริ่มต้น '/transmission/rpc')
    FUsername: string;           // ชื่อผู้ใช้กรณีเปิด HTTP Basic Authentication
    FPassword: string;           // รหัสผ่านกรณีเปิด HTTP Basic Authentication
    FSessionId: string;          // โทเค็น X-Transmission-Session-Id ปัจจุบัน
    FIsLocalSession: Boolean;    // True = รันและจัดการ transmission-daemon.exe ในเครื่องอัตโนมัติ
    FDataDir: string;            // โฟลเดอร์เก็บ config / torrents / resume ถาวร (-g)
    FDaemonProcess: TProcess;    // ออบเจกต์โปรเซสของ transmission-daemon.exe ที่เราเปิดขึ้นเอง
    FInEnsureDaemon: Boolean;    // ป้องกันการเรียก EnsureLocalDaemonRunning ซ้อนกัน
    FLastError: string;          // ข้อความข้อผิดพลาดล่าสุด
    FConnected: Boolean;         // สถานะว่าเชื่อมต่อกับ RPC Server สำเร็จหรือไม่

    function GetRpcUrl: string;
    function FindDaemonExecutable: string;
    procedure KillStaleLocalDaemons;
    function ExtractHeaderValue(Headers: TStrings; const HeaderName: string): string;
    function SendRpcRequest(const Method: string; Args: TJSONObject; out ResponseRoot: TJSONObject): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    { ตั้งค่าพารามิเตอร์การเชื่อมต่อ Local หรือ Remote Session }
    procedure Configure(const AHost: string; APort: Integer; const AUser, APass: string;
      ALocalSession: Boolean; const AUrlPath: string = '/transmission/rpc');

    { ตรวจสอบว่า Local Daemon รันอยู่หรือไม่ หากยังไม่ได้รันจะสั่งเปิดให้อัตโนมัติ }
    function EnsureLocalDaemonRunning: Boolean;

    { ปิดโปรเซส Local Daemon ที่โปรแกรมนี้เป็นคนเปิดขึ้นเมื่อปิดโปรแกรม }
    procedure StopLocalDaemonIfOwned;
    function RestartLocalDaemon: Boolean;

    { คำสั่งระดับเซสชัน (session-get, session-set, session-stats) }
    function FetchSession(out Config: TSessionConfig): Boolean;
    function UpdateSession(Args: TJSONObject): Boolean;
    function FetchSessionStats(out Stats: TSessionStatsData): Boolean;

    { คำสั่งดึงรายการและรายละเอียดของทอร์เรนต์ (torrent-get) }
    function FetchTorrents(List: TList): Boolean;
    function FetchTorrentDetails(Torrent: TTorrentItem): Boolean;

    { คำสั่งเพิ่มทอร์เรนต์ใหม่จากไฟล์ .torrent (Base64 metainfo) หรือ Magnet/URL (torrent-add) }
    function AddTorrentFile(const FileName, DownloadDir: string; StartImmediately: Boolean;
      Priority: Integer; const UnwantedFiles: array of Integer; out AddedName: string): Boolean;
    function AddTorrentUrl(const MagnetOrUrl, DownloadDir: string; StartImmediately: Boolean;
      Priority: Integer; out AddedName: string): Boolean;

    { คำสั่งควบคุมการทำงานของทอร์เรนต์ (Start, Stop, Verify, Reannounce, Remove, Relocate, Rename, Queue) }
    function StartTorrents(const Ids: array of Integer; Immediate: Boolean = False): Boolean;
    function StopTorrents(const Ids: array of Integer): Boolean;
    function VerifyTorrents(const Ids: array of Integer): Boolean;
    function ReannounceTorrents(const Ids: array of Integer): Boolean;
    function RemoveTorrents(const Ids: array of Integer; DeleteFiles: Boolean): Boolean;
    function SetTorrentLocation(const Ids: array of Integer; const NewDir: string; MoveData: Boolean): Boolean;
    function RenameTorrentPath(TorrentId: Integer; const OldPath, NewName: string): Boolean;
    function QueueMove(const Ids: array of Integer; const DirectionMethod: string): Boolean;
    function SetTorrentOptions(TorrentId: Integer; Args: TJSONObject): Boolean;
    function SetTorrentsTrackerPaused(const Ids: array of Integer; Paused: Boolean): Boolean;
    function SetTorrentsTrackerAutoPause(const Ids: array of Integer; AutoPause: Boolean): Boolean;

    { คำสั่งเครือข่าย พื้นที่ว่าง และการสร้างไฟล์ .torrent }
    function TestPeerPort(out IsOpen: Boolean): Boolean;
    function UpdateBlocklist(out RulesCount: Integer): Boolean;
    function QueryFreeSpace(const DirPath: string; out FreeBytes: Int64): Boolean;
    function ForwardRawRpc(const RequestJson: string; out ResponseJson: string): Boolean;
    function CreateTorrentFile(const SourcePath, OutputTorrentFile: string; Trackers: TStrings;
      const Comment: string; IsPrivate: Boolean; out LogOutput: string): Boolean;

    property Host: string read FHost write FHost;
    property Port: Integer read FPort write FPort;
    property UrlPath: string read FUrlPath write FUrlPath;
    property Username: string read FUsername write FUsername;
    property Password: string read FPassword write FPassword;
    property IsLocalSession: Boolean read FIsLocalSession write FIsLocalSession;
    property DataDir: string read FDataDir write FDataDir;
    property Connected: Boolean read FConnected;
    property LastError: string read FLastError;
  end;

implementation

{ ฟังก์ชันช่วยอ่านค่า String จาก TJSONObject อย่างปลอดภัย }
function JsonGetStr(Obj: TJSONObject; const Key: string; const Def: string = ''): string;
var
  D: TJSONData;
begin
  Result := Def;
  if Obj = nil then Exit;
  D := Obj.Find(Key);
  if (D <> nil) and (D.JSONType in [jtString, jtNumber, jtBoolean]) then
    Result := D.AsString;
end;

{ ฟังก์ชันช่วยอ่านค่า Int64 จาก TJSONObject อย่างปลอดภัย }
function JsonGetInt64(Obj: TJSONObject; const Key: string; const Def: Int64 = 0): Int64;
var
  D: TJSONData;
begin
  Result := Def;
  if Obj = nil then Exit;
  D := Obj.Find(Key);
  if D <> nil then
  begin
    if D.JSONType = jtNumber then
      Result := D.AsInt64
    else if D.JSONType = jtBoolean then
      Result := Ord(D.AsBoolean);
  end;
end;

function JsonGetInt(Obj: TJSONObject; const Key: string; const Def: Integer = 0): Integer;
begin
  Result := Integer(JsonGetInt64(Obj, Key, Def));
end;

{ ฟังก์ชันช่วยอ่านค่าทศนิยม Double จาก TJSONObject อย่างปลอดภัย }
function JsonGetFloat(Obj: TJSONObject; const Key: string; const Def: Double = 0.0): Double;
var
  D: TJSONData;
begin
  Result := Def;
  if Obj = nil then Exit;
  D := Obj.Find(Key);
  if (D <> nil) and (D.JSONType = jtNumber) then
    Result := D.AsFloat;
end;

{ ฟังก์ชันช่วยอ่านค่าตรรกะ Boolean จาก TJSONObject อย่างปลอดภัย }
function JsonGetBool(Obj: TJSONObject; const Key: string; const Def: Boolean = False): Boolean;
var
  D: TJSONData;
begin
  Result := Def;
  if Obj = nil then Exit;
  D := Obj.Find(Key);
  if D <> nil then
  begin
    if D.JSONType = jtBoolean then
      Result := D.AsBoolean
    else if D.JSONType = jtNumber then
      Result := D.AsInt64 <> 0;
  end;
end;

{ TTransmissionRpcClient }

constructor TTransmissionRpcClient.Create;
begin
  inherited Create;
  FHost := '127.0.0.1';
  FPort := 9091;
  FUrlPath := '/transmission/rpc';
  FUsername := '';
  FPassword := '';
  FSessionId := '';
  FIsLocalSession := True;
  FDataDir := GetDefaultPortableDataDir;
  FDaemonProcess := nil;
  FConnected := False;
end;

destructor TTransmissionRpcClient.Destroy;
begin
  StopLocalDaemonIfOwned;
  inherited Destroy;
end;

procedure TTransmissionRpcClient.Configure(const AHost: string; APort: Integer;
  const AUser, APass: string; ALocalSession: Boolean; const AUrlPath: string);
begin
  FHost := Trim(AHost);
  if FHost = '' then FHost := '127.0.0.1';
  FPort := APort;
  if FPort <= 0 then FPort := 9091;
  FUsername := AUser;
  FPassword := APass;
  FIsLocalSession := ALocalSession;
  FUrlPath := Trim(AUrlPath);
  if FUrlPath = '' then
    FUrlPath := '/transmission/rpc'
  else if FUrlPath[1] <> '/' then
    FUrlPath := '/' + FUrlPath;
  FSessionId := '';
end;

function TTransmissionRpcClient.GetRpcUrl: string;
begin
  Result := Format('http://%s:%d%s', [FHost, FPort, FUrlPath]);
end;

{ ค้นหาตำแหน่งไฟล์ transmission-daemon.exe จากโฟลเดอร์ปัจจุบัน, ไฟล์ฝังใน EXE, หรือโฟลเดอร์ build/daemon/ }
function TTransmissionRpcClient.FindDaemonExecutable: string;
var
  AppDir, Candidate, BinDir: string;
begin
  AppDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));

  // ใช้ daemon ที่ฝังใน EXE ก่อนเสมอ (เวอร์ชันตรงกับ GUI รองรับ ht..tps:// และ tracker_paused)
  BinDir := GetEmbeddedBinDir(FDataDir);
  Candidate := IncludeTrailingPathDelimiter(BinDir) + 'transmission-daemon.exe';
  if EnsureEmbeddedAsset('TR_DAEMON_Z', Candidate) then Exit(Candidate);

  Candidate := AppDir + 'transmission-daemon.exe';
  if FileExists(Candidate) then Exit(Candidate);

  Candidate := ExpandFileName(AppDir + '..\build\daemon\transmission-daemon.exe');
  if FileExists(Candidate) then Exit(Candidate);

  Candidate := ExpandFileName(AppDir + '..\..\build\daemon\transmission-daemon.exe');
  if FileExists(Candidate) then Exit(Candidate);

  Result := '';
end;

{ ตรวจสอบและสั่งรัน transmission-daemon.exe ในโหมดเบื้องหลัง (poNoConsole) หากรันในโหมด Local Session }
procedure CopyFileExact(const Src, Dst: string);
var
  S, D: TFileStream;
begin
  if not FileExists(Src) then Exit;
  ForceDirectories(ExtractFileDir(Dst));
  S := TFileStream.Create(Src, fmOpenRead or fmShareDenyNone);
  try
    D := TFileStream.Create(Dst, fmCreate);
    try
      if S.Size > 0 then
        D.CopyFrom(S, S.Size);
    finally
      D.Free;
    end;
  finally
    S.Free;
  end;
end;

procedure CopyDirContents(const SrcDir, DstDir: string);
var
  SR: TSearchRec;
  S, D: string;
begin
  if not DirectoryExists(SrcDir) then Exit;
  S := IncludeTrailingPathDelimiter(SrcDir);
  D := IncludeTrailingPathDelimiter(DstDir);
  ForceDirectories(D);
  if FindFirst(S + '*', faAnyFile, SR) = 0 then
  begin
    try
      repeat
        if (SR.Name = '.') or (SR.Name = '..') then Continue;
        if (SR.Attr and faDirectory) <> 0 then
          CopyDirContents(S + SR.Name, D + SR.Name)
        else
          CopyFileExact(S + SR.Name, D + SR.Name);
      until FindNext(SR) <> 0;
    finally
      FindClose(SR);
    end;
  end;
end;

procedure MigrateLegacyDaemonData(const TargetDir: string);
var
  LegacyDir, TgtSep, LegSep: string;
begin
  TgtSep := IncludeTrailingPathDelimiter(TargetDir);
  if FileExists(TgtSep + 'settings.json') or DirectoryExists(TgtSep + 'Resume') then
    Exit;

  LegacyDir := Trim(GetEnvironmentVariable('LOCALAPPDATA'));
  if LegacyDir = '' then Exit;
  LegacyDir := IncludeTrailingPathDelimiter(LegacyDir) + 'transmission-daemon';
  if not DirectoryExists(LegacyDir) then Exit;

  LegSep := IncludeTrailingPathDelimiter(LegacyDir);
  if SameText(ExcludeTrailingPathDelimiter(TargetDir), ExcludeTrailingPathDelimiter(LegacyDir)) then Exit;

  if FileExists(LegSep + 'settings.json') then
    CopyFileExact(LegSep + 'settings.json', TgtSep + 'settings.json');
  if FileExists(LegSep + 'stats.json') then
    CopyFileExact(LegSep + 'stats.json', TgtSep + 'stats.json');
  if DirectoryExists(LegSep + 'Torrents') then
    CopyDirContents(LegSep + 'Torrents', TgtSep + 'Torrents');
  if DirectoryExists(LegSep + 'Resume') then
    CopyDirContents(LegSep + 'Resume', TgtSep + 'Resume');
  if DirectoryExists(LegSep + 'blocklists') then
    CopyDirContents(LegSep + 'blocklists', TgtSep + 'blocklists');
end;

procedure TTransmissionRpcClient.KillStaleLocalDaemons;
var
  Killer: TProcess;
begin
  StopLocalDaemonIfOwned;
  Killer := TProcess.Create(nil);
  try
    Killer.Executable := 'taskkill.exe';
    Killer.Parameters.Add('/F');
    Killer.Parameters.Add('/IM');
    Killer.Parameters.Add('transmission-daemon.exe');
    Killer.Options := [poNoConsole, poWaitOnExit];
    try
      Killer.Execute;
    except
    end;
  finally
    Killer.Free;
  end;
end;

function TTransmissionRpcClient.EnsureLocalDaemonRunning: Boolean;
var
  DaemonExe, EffectiveDir: string;
  Cfg: TSessionConfig;
  Retries, CandPort: Integer;
  CloseResp: TJSONObject;
begin
  if not FIsLocalSession then
    Exit(True);
  if (FDaemonProcess <> nil) and FDaemonProcess.Running then
    Exit(True);
  if FInEnsureDaemon then
    Exit(False);

  FInEnsureDaemon := True;
  try
    // แตกไฟล์ transmission-daemon.exe ที่ฝังใน EXE ออกมาไว้ที่ data\bin\ เสมอ
    DaemonExe := FindDaemonExecutable;

    // หากยังไม่มีโปรเซสที่เราเป็นเจ้าของ (FDaemonProcess = nil) แต่มี Daemon เก่าเปิดค้างอยู่ก่อนหน้า
    // ให้สั่งปิด Daemon เก่าอย่างปลอดภัย (session-close + taskkill) แล้วแตกไฟล์และเปิด Daemon ตัวใหม่ที่เราเป็นเจ้าของแทนเสมอ
    if (FDaemonProcess = nil) and FetchSession(Cfg) then
    begin
      CloseResp := nil;
      if SendRpcRequest('session-close', nil, CloseResp) then
        CloseResp.Free;
      Sleep(200);
      KillStaleLocalDaemons;
      Sleep(300);
      FSessionId := '';
      FConnected := False;
      DaemonExe := FindDaemonExecutable;

      // หากพอร์ตเดิมยังถูกโปรแกรมอื่นที่ไม่ใช่ transmission-daemon ครองอยู่ (เช่น transmission-qt) ให้ย้ายไปพอร์ตว่างอัตโนมัติ
      if FetchSession(Cfg) then
      begin
        for CandPort := 9093 to 9099 do
        begin
          FPort := CandPort;
          FSessionId := '';
          if not FetchSession(Cfg) then
            Break;
        end;
      end;
    end;

    if (FDaemonProcess <> nil) and FDaemonProcess.Running then
      Exit(True);

    if DaemonExe = '' then
      DaemonExe := FindDaemonExecutable;
    if DaemonExe = '' then
    begin
      FLastError := 'Local transmission-daemon.exe not found in embedded assets or build/daemon/';
      Exit(False);
    end;

    EffectiveDir := Trim(FDataDir);
    if EffectiveDir = '' then
      EffectiveDir := GetDefaultPortableDataDir;
    if not ForceDirectories(EffectiveDir) then
    begin
      EffectiveDir := GetDefaultPortableDataDir;
      FDataDir := EffectiveDir;
      ForceDirectories(EffectiveDir);
    end;
    MigrateLegacyDaemonData(EffectiveDir);
    ConfigureDaemonSslEnvironment;

    FreeAndNil(FDaemonProcess);
    FDaemonProcess := TProcess.Create(nil);
    FDaemonProcess.Executable := DaemonExe;
    FDaemonProcess.CurrentDirectory := ExtractFilePath(DaemonExe);
    FDaemonProcess.Parameters.Add('-f'); // รันในโหมด Foreground ของโปรเซสย่อยแต่ซ่อนหน้าต่างด้วย poNoConsole
    FDaemonProcess.Parameters.Add('-g');
    FDaemonProcess.Parameters.Add(EffectiveDir);
    FDaemonProcess.Parameters.Add('-p');
    FDaemonProcess.Parameters.Add(IntToStr(FPort));
    FDaemonProcess.Parameters.Add('-a');
    FDaemonProcess.Parameters.Add('127.0.0.1,::1');
    FDaemonProcess.Options := [poNoConsole];
    try
      FDaemonProcess.Execute;
    except
      on E: Exception do
      begin
        FLastError := 'Failed to launch local daemon: ' + E.Message;
        FreeAndNil(FDaemonProcess);
        Exit(False);
      end;
    end;

    // รอสูงสุด 6 วินาทีเพื่อให้ HTTP RPC Server ของ Daemon เริ่มต้นเสร็จ (เผื่อ Windows Defender สแกนครั้งแรกบนเครื่องอื่น)
    for Retries := 1 to 24 do
    begin
      Sleep(250);
      if FetchSession(Cfg) then
        Exit(True);
    end;

    Result := FConnected;
  finally
    FInEnsureDaemon := False;
  end;
end;

procedure TTransmissionRpcClient.StopLocalDaemonIfOwned;
var
  Resp: TJSONObject;
  WaitIdx: Integer;
  WasEnsuring: Boolean;
begin
  if FDaemonProcess <> nil then
  begin
    try
      if FDaemonProcess.Running then
      begin
        WasEnsuring := FInEnsureDaemon;
        FInEnsureDaemon := True;
        try
          Resp := nil;
          if SendRpcRequest('session-close', nil, Resp) then
            Resp.Free;
        finally
          FInEnsureDaemon := WasEnsuring;
        end;
        for WaitIdx := 1 to 8 do
        begin
          if not FDaemonProcess.Running then
            Break;
          Sleep(100);
        end;
        if FDaemonProcess.Running then
          FDaemonProcess.Terminate(0);
      end;
    except
    end;
    FreeAndNil(FDaemonProcess);
  end;
end;

function TTransmissionRpcClient.RestartLocalDaemon: Boolean;
begin
  StopLocalDaemonIfOwned;
  Sleep(250);
  Result := EnsureLocalDaemonRunning;
end;

{ ดึงค่าจาก HTTP Response Header ตามชื่อคีย์ (ไม่สนใจตัวพิมพ์เล็ก/ใหญ่) }
function TTransmissionRpcClient.ExtractHeaderValue(Headers: TStrings;
  const HeaderName: string): string;
var
  I, P: Integer;
  Line, Key: string;
begin
  Result := '';
  for I := 0 to Headers.Count - 1 do
  begin
    Line := Headers[I];
    P := Pos(':', Line);
    if P > 0 then
    begin
      Key := Trim(Copy(Line, 1, P - 1));
      if SameText(Key, HeaderName) then
      begin
        Result := Trim(Copy(Line, P + 1, MaxInt));
        Exit;
      end;
    end;
  end;
end;

{ ส่งคำสั่ง JSON-RPC ไปยังเซิร์ฟเวอร์ พร้อมรองรับการขอโทเค็น X-Transmission-Session-Id อัตโนมัติเมื่อได้รหัส 409 }
function TTransmissionRpcClient.SendRpcRequest(const Method: string;
  Args: TJSONObject; out ResponseRoot: TJSONObject): Boolean;
var
  Http: TFPHTTPClient;
  ReqObj: TJSONObject;
  ReqBody: string;
  ReqStream: TStringStream;
  RespStream: TStringStream;
  Attempt: Integer;
  NewSid: string;
  Parsed: TJSONData;
  ResultStr: string;
begin
  Result := False;
  ResponseRoot := nil;

  ReqObj := TJSONObject.Create;
  try
    ReqObj.Add('method', Method);
    if Args <> nil then
      ReqObj.Add('arguments', Args);
    ReqBody := ReqObj.AsJSON;
  finally
    ReqObj.Free;
  end;

  Http := TFPHTTPClient.Create(nil);
  try
    if FIsLocalSession then
    begin
      Http.ConnectTimeout := 800;
      Http.IOTimeout := 3000;
    end
    else
    begin
      Http.ConnectTimeout := 2500;
      Http.IOTimeout := 5000;
    end;
    Http.AllowRedirect := False;
    if FUsername <> '' then
    begin
      Http.UserName := FUsername;
      Http.Password := FPassword;
    end;

    for Attempt := 1 to 3 do
    begin
      if FIsLocalSession and (not FInEnsureDaemon) and (FDaemonProcess <> nil) and (not FDaemonProcess.Running) then
        EnsureLocalDaemonRunning;

      Http.RequestHeaders.Clear;
      Http.RequestHeaders.Add('Content-Type: application/json');
      if FSessionId <> '' then
        Http.RequestHeaders.Add('X-Transmission-Session-Id: ' + FSessionId);

      ReqStream := TStringStream.Create(ReqBody);
      RespStream := TStringStream.Create('');
      try
        Http.RequestBody := ReqStream;
        try
          Http.Post(GetRpcUrl, RespStream);
        except
          on E: Exception do
          begin
            if Http.ResponseStatusCode <> 409 then
            begin
              FLastError := E.Message;
              FConnected := False;
              // หาก Local Daemon ถูกปิดหรือหลุดไป ให้สั่งเปิดใหม่โดยอัตโนมัติแล้วลองส่งซ้ำทันที
              if FIsLocalSession and (not FInEnsureDaemon) and (Attempt = 1) then
              begin
                if EnsureLocalDaemonRunning then
                  Continue;
              end;
              Exit(False);
            end;
          end;
        end;

        // กรณีได้รับ HTTP 409: อ่านค่า X-Transmission-Session-Id ใหม่แล้ววนลูปรอบที่ 2 ทันที
        if Http.ResponseStatusCode = 409 then
        begin
          NewSid := ExtractHeaderValue(Http.ResponseHeaders, 'X-Transmission-Session-Id');
          if NewSid <> '' then
          begin
            FSessionId := NewSid;
            Continue;
          end;
        end;

        if Http.ResponseStatusCode <> 200 then
        begin
          FLastError := Format('HTTP %d: %s', [Http.ResponseStatusCode, Http.ResponseStatusText]);
          FConnected := False;
          Exit(False);
        end;

        Parsed := GetJSON(RespStream.DataString);
        if (Parsed = nil) or (Parsed.JSONType <> jtObject) then
        begin
          Parsed.Free;
          FLastError := 'Invalid JSON response from RPC server';
          FConnected := False;
          Exit(False);
        end;

        ResponseRoot := TJSONObject(Parsed);
        ResultStr := JsonGetStr(ResponseRoot, 'result', '');
        FConnected := True;
        if ResultStr <> 'success' then
        begin
          FLastError := 'RPC Error: ' + ResultStr;
          FreeAndNil(ResponseRoot);
          Exit(False);
        end;

        FLastError := '';
        Result := True;
        Break;
      finally
        Http.RequestBody := nil;
        ReqStream.Free;
        RespStream.Free;
      end;
    end;
  finally
    Http.Free;
  end;
end;

{ ดึงค่าการตั้งค่าทั้งหมดของเซสชันด้วยคำสั่ง `session-get` }
function TTransmissionRpcClient.FetchSession(out Config: TSessionConfig): Boolean;
var
  Resp, Args, FixArgs: TJSONObject;
begin
  FillChar(Config, SizeOf(Config), 0);
  Config.Version := '4.2.0-dev';
  Config.RpcVersion := 17;
  Config.DownloadDir := GetCurrentUserDownloadsDir;
  Config.IncompleteDir := Config.DownloadDir;
  Config.RenamePartialFiles := True;
  Config.StartAddedTorrents := True;
  Config.SpeedLimitDown := 100;
  Config.SpeedLimitUp := 100;
  Config.AltSpeedDown := 50;
  Config.AltSpeedUp := 50;
  Config.SeedRatioLimit := 2.0;
  Config.IdleSeedingLimit := 30;
  Config.Encryption := 'preferred';
  Config.PexEnabled := True;
  Config.DhtEnabled := True;
  Config.UtpEnabled := True;
  Config.PeerPort := 51413;
  Config.PortForwardingEnabled := True;
  Config.PeerLimitGlobal := 200;
  Config.PeerLimitPerTorrent := 50;
  Config.DownloadQueueEnabled := True;
  Config.DownloadQueueSize := 5;
  Config.SeedQueueSize := 10;
  Config.CacheSizeMiB := 4;

  Result := SendRpcRequest('session-get', nil, Resp);
  if not Result then Exit;
  try
    Args := Resp.Find('arguments') as TJSONObject;
    if Args = nil then Exit(False);

    Config.Version := JsonGetStr(Args, 'version', '4.2.0-dev');
    Config.RpcVersion := JsonGetInt(Args, 'rpc-version', 17);
    Config.DownloadDir := JsonGetStr(Args, 'download-dir', '');
    Config.IncompleteDir := JsonGetStr(Args, 'incomplete-dir', '');
    Config.IncompleteDirEnabled := JsonGetBool(Args, 'incomplete-dir-enabled', False);

    // หากย้ายโปรแกรม/ข้อมูลไปเครื่องอื่นแล้วพาธ download-dir เดิม (เช่น C:\Users\Administrator\Downloads) เขียนไม่ได้ ให้เปลี่ยนเป็น Downloads ของเครื่องปัจจุบันทันที
    if FIsLocalSession and (not IsDirectoryWritable(Config.DownloadDir)) then
    begin
      Config.DownloadDir := GetCurrentUserDownloadsDir;
      if not FInEnsureDaemon then
      begin
        FixArgs := TJSONObject.Create;
        FixArgs.Add('download-dir', StringReplace(Config.DownloadDir, '\', '/', [rfReplaceAll]));
        if Config.IncompleteDirEnabled and (not IsDirectoryWritable(Config.IncompleteDir)) then
        begin
          Config.IncompleteDir := Config.DownloadDir;
          FixArgs.Add('incomplete-dir', StringReplace(Config.IncompleteDir, '\', '/', [rfReplaceAll]));
        end;
        UpdateSession(FixArgs);
      end;
    end;
    Config.RenamePartialFiles := JsonGetBool(Args, 'rename-partial-files', True);
    Config.StartAddedTorrents := JsonGetBool(Args, 'start-added-torrents', True);
    Config.TrashOriginalTorrentFiles := JsonGetBool(Args, 'trash-original-torrent-files', False);
    Config.SpeedLimitDown := JsonGetInt64(Args, 'speed-limit-down', 100);
    Config.SpeedLimitDownEnabled := JsonGetBool(Args, 'speed-limit-down-enabled', False);
    Config.SpeedLimitUp := JsonGetInt64(Args, 'speed-limit-up', 100);
    Config.SpeedLimitUpEnabled := JsonGetBool(Args, 'speed-limit-up-enabled', False);
    Config.AltSpeedDown := JsonGetInt64(Args, 'alt-speed-down', 50);
    Config.AltSpeedUp := JsonGetInt64(Args, 'alt-speed-up', 50);
    Config.AltSpeedEnabled := JsonGetBool(Args, 'alt-speed-enabled', False);
    Config.AltSpeedTimeEnabled := JsonGetBool(Args, 'alt-speed-time-enabled', False);
    Config.AltSpeedTimeBegin := JsonGetInt(Args, 'alt-speed-time-begin', 540);
    Config.AltSpeedTimeEnd := JsonGetInt(Args, 'alt-speed-time-end', 1020);
    Config.SeedRatioLimited := JsonGetBool(Args, 'seedRatioLimited', False);
    Config.SeedRatioLimit := JsonGetFloat(Args, 'seedRatioLimit', 2.0);
    Config.IdleSeedingLimited := JsonGetBool(Args, 'idle-seeding-limit-enabled', False);
    Config.IdleSeedingLimit := JsonGetInt(Args, 'idle-seeding-limit', 30);
    Config.Encryption := JsonGetStr(Args, 'encryption', 'preferred');
    Config.PexEnabled := JsonGetBool(Args, 'pex-enabled', True);
    Config.DhtEnabled := JsonGetBool(Args, 'dht-enabled', True);
    Config.LpdEnabled := JsonGetBool(Args, 'lpd-enabled', False);
    Config.UtpEnabled := JsonGetBool(Args, 'utp-enabled', True);
    Config.BlocklistEnabled := JsonGetBool(Args, 'blocklist-enabled', False);
    Config.BlocklistUrl := JsonGetStr(Args, 'blocklist-url', '');
    Config.BlocklistSize := JsonGetInt(Args, 'blocklist-size', 0);
    Config.PeerPort := JsonGetInt(Args, 'peer-port', 51413);
    Config.PeerPortRandomOnStart := JsonGetBool(Args, 'peer-port-random-on-start', False);
    Config.PortForwardingEnabled := JsonGetBool(Args, 'port-forwarding-enabled', True);
    Config.PeerLimitGlobal := JsonGetInt(Args, 'peer-limit-global', 200);
    Config.PeerLimitPerTorrent := JsonGetInt(Args, 'peer-limit-per-torrent', 50);
    Config.DownloadQueueEnabled := JsonGetBool(Args, 'download-queue-enabled', True);
    Config.DownloadQueueSize := JsonGetInt(Args, 'download-queue-size', 5);
    Config.SeedQueueEnabled := JsonGetBool(Args, 'seed-queue-enabled', False);
    Config.SeedQueueSize := JsonGetInt(Args, 'seed-queue-size', 10);
    Config.TrackerPaused := JsonGetBool(Args, 'tracker_paused', JsonGetBool(Args, 'tracker-paused', False));
    Config.TrackerAutoPause := JsonGetBool(Args, 'tracker_auto_pause', JsonGetBool(Args, 'tracker-auto-pause', False));
    Config.SupportsTrackerPause := (Args.Find('tracker_paused') <> nil) or (Args.Find('tracker-paused') <> nil);
    Config.CacheSizeMiB := JsonGetInt(Args, 'cache_size_mib', JsonGetInt(Args, 'cache-size-mb', 4));
  finally
    Resp.Free;
  end;
end;

{ บันทึกการตั้งค่าระดับเซสชันด้วยคำสั่ง `session-set` }
function TTransmissionRpcClient.UpdateSession(Args: TJSONObject): Boolean;
var
  Resp: TJSONObject;
begin
  Result := SendRpcRequest('session-set', Args, Resp);
  Resp.Free;
end;

{ ดึงข้อมูลสถิติการรับ-ส่งข้อมูลของเซสชันและยอดสะสมด้วยคำสั่ง `session-stats` }
function TTransmissionRpcClient.FetchSessionStats(out Stats: TSessionStatsData): Boolean;
var
  Resp, Args, Sub: TJSONObject;
begin
  FillChar(Stats, SizeOf(Stats), 0);
  Result := SendRpcRequest('session-stats', nil, Resp);
  if not Result then Exit;
  try
    Args := Resp.Find('arguments') as TJSONObject;
    if Args = nil then Exit(False);

    Stats.ActiveTorrentCount := JsonGetInt(Args, 'activeTorrentCount', 0);
    Stats.PausedTorrentCount := JsonGetInt(Args, 'pausedTorrentCount', 0);
    Stats.TorrentCount := JsonGetInt(Args, 'torrentCount', 0);
    Stats.DownloadSpeed := JsonGetInt64(Args, 'downloadSpeed', 0);
    Stats.UploadSpeed := JsonGetInt64(Args, 'uploadSpeed', 0);

    Sub := Args.Find('current-stats') as TJSONObject;
    if Sub <> nil then
    begin
      Stats.CurrentUploadedBytes := JsonGetInt64(Sub, 'uploadedBytes', 0);
      Stats.CurrentDownloadedBytes := JsonGetInt64(Sub, 'downloadedBytes', 0);
      Stats.CurrentFilesAdded := JsonGetInt(Sub, 'filesAdded', 0);
      Stats.CurrentSessionCount := JsonGetInt(Sub, 'sessionCount', 0);
      Stats.CurrentSecondsActive := JsonGetInt64(Sub, 'secondsActive', 0);
    end;

    Sub := Args.Find('cumulative-stats') as TJSONObject;
    if Sub <> nil then
    begin
      Stats.TotalUploadedBytes := JsonGetInt64(Sub, 'uploadedBytes', 0);
      Stats.TotalDownloadedBytes := JsonGetInt64(Sub, 'downloadedBytes', 0);
      Stats.TotalFilesAdded := JsonGetInt(Sub, 'filesAdded', 0);
      Stats.TotalSessionCount := JsonGetInt(Sub, 'sessionCount', 0);
      Stats.TotalSecondsActive := JsonGetInt64(Sub, 'secondsActive', 0);
    end;
  finally
    Resp.Free;
  end;
end;

{ ดึงรายการทอร์เรนต์ทั้งหมดสำหรับแสดงผลในหน้าต่างหลักด้วยคำสั่ง `torrent-get` }
function TTransmissionRpcClient.FetchTorrents(List: TList): Boolean;
const
  FieldNames: array[0..35] of string = (
    'id', 'name', 'hashString', 'status', 'percentDone',
    'metadataPercentComplete', 'totalSize', 'sizeWhenDone', 'leftUntilDone',
    'haveValid', 'haveUnchecked', 'rateDownload', 'rateUpload', 'uploadRatio',
    'uploadedEver', 'downloadedEver', 'eta', 'peersConnected',
    'peersSendingToUs', 'peersGettingFromUs', 'error', 'errorString',
    'addedDate', 'doneDate', 'activityDate', 'downloadDir', 'isPrivate',
    'isFinished', 'queuePosition', 'bandwidthPriority', 'seedRatioMode',
    'seedRatioLimit', 'magnetLink', 'tracker_paused', 'tracker_auto_pause', 'trackerStats'
  );
var
  Args, Resp, RespArgs, TorObj, TrkObj: TJSONObject;
  FieldsArr, TorArr, TrkArr: TJSONArray;
  I, J: Integer;
  Item: TTorrentItem;
begin
  Args := TJSONObject.Create;
  FieldsArr := TJSONArray.Create;
  for I := Low(FieldNames) to High(FieldNames) do
    FieldsArr.Add(FieldNames[I]);
  Args.Add('fields', FieldsArr);

  Result := SendRpcRequest('torrent-get', Args, Resp);
  if not Result then Exit;
  try
    RespArgs := Resp.Find('arguments') as TJSONObject;
    if RespArgs = nil then Exit(False);
    TorArr := RespArgs.Find('torrents') as TJSONArray;
    if TorArr = nil then Exit(False);

    for I := 0 to TorArr.Count - 1 do
    begin
      if TorArr.Items[I].JSONType <> jtObject then Continue;
      TorObj := TJSONObject(TorArr.Items[I]);

      Item := TTorrentItem.Create;
      Item.Id := JsonGetInt(TorObj, 'id', 0);
      Item.Name := JsonGetStr(TorObj, 'name', 'Unnamed Torrent');
      Item.HashString := JsonGetStr(TorObj, 'hashString', '');
      Item.Status := JsonGetInt(TorObj, 'status', TR_STATUS_STOPPED);
      Item.PercentDone := JsonGetFloat(TorObj, 'percentDone', 0.0);
      Item.MetadataPercentComplete := JsonGetFloat(TorObj, 'metadataPercentComplete', 1.0);
      Item.TotalSize := JsonGetInt64(TorObj, 'totalSize', 0);
      Item.SizeWhenDone := JsonGetInt64(TorObj, 'sizeWhenDone', Item.TotalSize);
      Item.LeftUntilDone := JsonGetInt64(TorObj, 'leftUntilDone', 0);
      Item.HaveValid := JsonGetInt64(TorObj, 'haveValid', 0);
      Item.HaveUnchecked := JsonGetInt64(TorObj, 'haveUnchecked', 0);
      Item.RateDownload := JsonGetInt64(TorObj, 'rateDownload', 0);
      Item.RateUpload := JsonGetInt64(TorObj, 'rateUpload', 0);
      Item.UploadRatio := JsonGetFloat(TorObj, 'uploadRatio', 0.0);
      Item.UploadedEver := JsonGetInt64(TorObj, 'uploadedEver', 0);
      Item.DownloadedEver := JsonGetInt64(TorObj, 'downloadedEver', 0);
      Item.ETA := JsonGetInt64(TorObj, 'eta', -1);
      Item.PeersConnected := JsonGetInt(TorObj, 'peersConnected', 0);
      Item.PeersSendingToUs := JsonGetInt(TorObj, 'peersSendingToUs', 0);
      Item.PeersGettingFromUs := JsonGetInt(TorObj, 'peersGettingFromUs', 0);
      Item.Error := JsonGetInt(TorObj, 'error', 0);
      Item.ErrorString := JsonGetStr(TorObj, 'errorString', '');
      Item.AddedDate := JsonGetInt64(TorObj, 'addedDate', 0);
      Item.DoneDate := JsonGetInt64(TorObj, 'doneDate', 0);
      Item.ActivityDate := JsonGetInt64(TorObj, 'activityDate', 0);
      Item.DownloadDir := JsonGetStr(TorObj, 'downloadDir', '');
      Item.IsPrivate := JsonGetBool(TorObj, 'isPrivate', False);
      Item.IsFinished := JsonGetBool(TorObj, 'isFinished', False);
      Item.QueuePosition := JsonGetInt(TorObj, 'queuePosition', 0);
      Item.BandwidthPriority := JsonGetInt(TorObj, 'bandwidthPriority', TR_PRI_NORMAL);
      Item.SeedRatioMode := JsonGetInt(TorObj, 'seedRatioMode', TR_RATIOLIMIT_GLOBAL);
      Item.SeedRatioLimit := JsonGetFloat(TorObj, 'seedRatioLimit', 2.0);
      Item.MagnetLink := JsonGetStr(TorObj, 'magnetLink', '');
      Item.TrackerPaused := JsonGetBool(TorObj, 'tracker_paused', JsonGetBool(TorObj, 'tracker-paused', False));
      Item.TrackerAutoPause := JsonGetBool(TorObj, 'tracker_auto_pause', JsonGetBool(TorObj, 'tracker-auto-pause', False));

      TrkArr := TorObj.Find('trackerStats') as TJSONArray;
      if (TrkArr <> nil) and (TrkArr.Count > 0) then
      begin
        SetLength(Item.Trackers, TrkArr.Count);
        for J := 0 to TrkArr.Count - 1 do
        begin
          TrkObj := TrkArr.Items[J] as TJSONObject;
          if TrkObj <> nil then
          begin
            Item.Trackers[J].Id := JsonGetInt(TrkObj, 'id', J);
            Item.Trackers[J].Tier := JsonGetInt(TrkObj, 'tier', 0);
            Item.Trackers[J].Announce := JsonGetStr(TrkObj, 'announce', '');
            Item.Trackers[J].Host := ExtractTrackerHost(Item.Trackers[J].Announce);
            Item.Trackers[J].LastAnnounceResult := JsonGetStr(TrkObj, 'lastAnnounceResult', '');
            Item.Trackers[J].LastAnnounceTime := JsonGetInt64(TrkObj, 'lastAnnounceTime', 0);
            Item.Trackers[J].LastAnnounceSucceeded := JsonGetBool(TrkObj, 'lastAnnounceSucceeded', False);
            Item.Trackers[J].SeederCount := JsonGetInt(TrkObj, 'seederCount', -1);
            Item.Trackers[J].LeecherCount := JsonGetInt(TrkObj, 'leecherCount', -1);
            Item.Trackers[J].DownloadCount := JsonGetInt(TrkObj, 'downloadCount', -1);
            if (Item.PrimaryTrackerHost = '') and (Item.Trackers[J].Host <> '') then
              Item.PrimaryTrackerHost := Item.Trackers[J].Host;
          end;
        end;
      end;

      List.Add(Item);
    end;
  finally
    Resp.Free;
  end;
end;

{ ดึงข้อมูลเชิงลึกของทอร์เรนต์เฉพาะตัว (Files, Peers, Trackers, Options) สำหรับหน้าต่าง Properties }
function TTransmissionRpcClient.FetchTorrentDetails(Torrent: TTorrentItem): Boolean;
const
  DetailFields: array[0..43] of string = (
    'id', 'name', 'hashString', 'status', 'percentDone', 'sizeWhenDone', 'totalSize',
    'haveValid', 'haveUnchecked', 'downloadedEver', 'uploadedEver',
    'rateDownload', 'rateUpload', 'uploadRatio', 'eta', 'activityDate',
    'addedDate', 'doneDate', 'downloadDir', 'isPrivate', 'errorString',
    'creator', 'comment', 'pieceCount', 'pieceSize',
    'secondsDownloading', 'secondsSeeding', 'honorsSessionLimits',
    'downloadLimited', 'downloadLimit', 'uploadLimited', 'uploadLimit',
    'seedRatioMode', 'seedRatioLimit', 'seedIdleMode', 'seedIdleLimit',
    'peer-limit', 'tracker_paused', 'tracker_auto_pause', 'files', 'fileStats', 'peers', 'trackerStats',
    'magnetLink'
  );
var
  Args, Resp, RespArgs, TorObj, SubObj, StatObj: TJSONObject;
  FieldsArr, IdsArr, TorArr, FilesArr, StatsArr, PeersArr, TrkArr: TJSONArray;
  I: Integer;
begin
  if Torrent = nil then Exit(False);

  Args := TJSONObject.Create;
  IdsArr := TJSONArray.Create;
  IdsArr.Add(Torrent.Id);
  Args.Add('ids', IdsArr);

  FieldsArr := TJSONArray.Create;
  for I := Low(DetailFields) to High(DetailFields) do
    FieldsArr.Add(DetailFields[I]);
  Args.Add('fields', FieldsArr);

  Result := SendRpcRequest('torrent-get', Args, Resp);
  if not Result then Exit;
  try
    RespArgs := Resp.Find('arguments') as TJSONObject;
    if RespArgs = nil then Exit(False);
    TorArr := RespArgs.Find('torrents') as TJSONArray;
    if (TorArr = nil) or (TorArr.Count = 0) then Exit(False);

    TorObj := TorArr.Items[0] as TJSONObject;
    if TorObj = nil then Exit(False);

    Torrent.Name := JsonGetStr(TorObj, 'name', Torrent.Name);
    Torrent.HashString := JsonGetStr(TorObj, 'hashString', Torrent.HashString);
    Torrent.Status := JsonGetInt(TorObj, 'status', Torrent.Status);
    Torrent.PercentDone := JsonGetFloat(TorObj, 'percentDone', Torrent.PercentDone);
    Torrent.TotalSize := JsonGetInt64(TorObj, 'totalSize', Torrent.TotalSize);
    Torrent.SizeWhenDone := JsonGetInt64(TorObj, 'sizeWhenDone', Torrent.SizeWhenDone);
    Torrent.HaveValid := JsonGetInt64(TorObj, 'haveValid', Torrent.HaveValid);
    Torrent.HaveUnchecked := JsonGetInt64(TorObj, 'haveUnchecked', Torrent.HaveUnchecked);
    Torrent.DownloadedEver := JsonGetInt64(TorObj, 'downloadedEver', Torrent.DownloadedEver);
    Torrent.UploadedEver := JsonGetInt64(TorObj, 'uploadedEver', Torrent.UploadedEver);
    Torrent.RateDownload := JsonGetInt64(TorObj, 'rateDownload', Torrent.RateDownload);
    Torrent.RateUpload := JsonGetInt64(TorObj, 'rateUpload', Torrent.RateUpload);
    Torrent.UploadRatio := JsonGetFloat(TorObj, 'uploadRatio', Torrent.UploadRatio);
    Torrent.ETA := JsonGetInt64(TorObj, 'eta', Torrent.ETA);
    Torrent.ActivityDate := JsonGetInt64(TorObj, 'activityDate', Torrent.ActivityDate);
    Torrent.AddedDate := JsonGetInt64(TorObj, 'addedDate', Torrent.AddedDate);
    Torrent.DoneDate := JsonGetInt64(TorObj, 'doneDate', Torrent.DoneDate);
    Torrent.DownloadDir := JsonGetStr(TorObj, 'downloadDir', Torrent.DownloadDir);
    Torrent.IsPrivate := JsonGetBool(TorObj, 'isPrivate', Torrent.IsPrivate);
    Torrent.ErrorString := JsonGetStr(TorObj, 'errorString', '');
    Torrent.Creator := JsonGetStr(TorObj, 'creator', '');
    Torrent.Comment := JsonGetStr(TorObj, 'comment', '');
    Torrent.PieceCount := JsonGetInt(TorObj, 'pieceCount', 0);
    Torrent.PieceSize := JsonGetInt64(TorObj, 'pieceSize', 0);
    Torrent.SecondsDownloading := JsonGetInt64(TorObj, 'secondsDownloading', 0);
    Torrent.SecondsSeeding := JsonGetInt64(TorObj, 'secondsSeeding', 0);
    Torrent.HonorsSessionLimits := JsonGetBool(TorObj, 'honorsSessionLimits', True);
    Torrent.DownloadLimited := JsonGetBool(TorObj, 'downloadLimited', False);
    Torrent.DownloadLimit := JsonGetInt64(TorObj, 'downloadLimit', 100);
    Torrent.UploadLimited := JsonGetBool(TorObj, 'uploadLimited', False);
    Torrent.UploadLimit := JsonGetInt64(TorObj, 'uploadLimit', 100);
    Torrent.SeedRatioMode := JsonGetInt(TorObj, 'seedRatioMode', TR_RATIOLIMIT_GLOBAL);
    Torrent.SeedRatioLimit := JsonGetFloat(TorObj, 'seedRatioLimit', 2.0);
    Torrent.SeedIdleMode := JsonGetInt(TorObj, 'seedIdleMode', 0);
    Torrent.SeedIdleLimit := JsonGetInt(TorObj, 'seedIdleLimit', 30);
    Torrent.PeerLimit := JsonGetInt(TorObj, 'peer-limit', 50);
    Torrent.TrackerPaused := JsonGetBool(TorObj, 'tracker_paused', JsonGetBool(TorObj, 'tracker-paused', False));
    Torrent.TrackerAutoPause := JsonGetBool(TorObj, 'tracker_auto_pause', JsonGetBool(TorObj, 'tracker-auto-pause', False));
    Torrent.MagnetLink := JsonGetStr(TorObj, 'magnetLink', Torrent.MagnetLink);

    FilesArr := TorObj.Find('files') as TJSONArray;
    StatsArr := TorObj.Find('fileStats') as TJSONArray;
    if FilesArr <> nil then
    begin
      SetLength(Torrent.Files, FilesArr.Count);
      for I := 0 to FilesArr.Count - 1 do
      begin
        SubObj := FilesArr.Items[I] as TJSONObject;
        Torrent.Files[I].Index := I;
        if SubObj <> nil then
        begin
          Torrent.Files[I].Name := JsonGetStr(SubObj, 'name', '');
          Torrent.Files[I].Length := JsonGetInt64(SubObj, 'length', 0);
          Torrent.Files[I].BytesCompleted := JsonGetInt64(SubObj, 'bytesCompleted', 0);
        end;
        Torrent.Files[I].Wanted := True;
        Torrent.Files[I].Priority := TR_PRI_NORMAL;
        if (StatsArr <> nil) and (I < StatsArr.Count) then
        begin
          StatObj := StatsArr.Items[I] as TJSONObject;
          if StatObj <> nil then
          begin
            Torrent.Files[I].Wanted := JsonGetBool(StatObj, 'wanted', True);
            Torrent.Files[I].Priority := JsonGetInt(StatObj, 'priority', TR_PRI_NORMAL);
          end;
        end;
      end;
    end;

    PeersArr := TorObj.Find('peers') as TJSONArray;
    if PeersArr <> nil then
    begin
      SetLength(Torrent.Peers, PeersArr.Count);
      for I := 0 to PeersArr.Count - 1 do
      begin
        SubObj := PeersArr.Items[I] as TJSONObject;
        if SubObj <> nil then
        begin
          Torrent.Peers[I].Address := JsonGetStr(SubObj, 'address', '');
          Torrent.Peers[I].Port := JsonGetInt(SubObj, 'port', 0);
          Torrent.Peers[I].ClientName := JsonGetStr(SubObj, 'clientName', '');
          Torrent.Peers[I].FlagStr := JsonGetStr(SubObj, 'flagStr', '');
          Torrent.Peers[I].Progress := JsonGetFloat(SubObj, 'progress', 0.0);
          Torrent.Peers[I].RateToClient := JsonGetInt64(SubObj, 'rateToClient', 0);
          Torrent.Peers[I].RateToPeer := JsonGetInt64(SubObj, 'rateToPeer', 0);
          Torrent.Peers[I].IsEncrypted := JsonGetBool(SubObj, 'isEncrypted', False);
          Torrent.Peers[I].IsUTP := JsonGetBool(SubObj, 'isUTP', False);
        end;
      end;
    end;

    TrkArr := TorObj.Find('trackerStats') as TJSONArray;
    if TrkArr <> nil then
    begin
      SetLength(Torrent.Trackers, TrkArr.Count);
      for I := 0 to TrkArr.Count - 1 do
      begin
        SubObj := TrkArr.Items[I] as TJSONObject;
        if SubObj <> nil then
        begin
          Torrent.Trackers[I].Id := JsonGetInt(SubObj, 'id', I);
          Torrent.Trackers[I].Tier := JsonGetInt(SubObj, 'tier', 0);
          Torrent.Trackers[I].Announce := JsonGetStr(SubObj, 'announce', '');
          Torrent.Trackers[I].Host := ExtractTrackerHost(Torrent.Trackers[I].Announce);
          Torrent.Trackers[I].LastAnnounceResult := JsonGetStr(SubObj, 'lastAnnounceResult', '');
          Torrent.Trackers[I].LastAnnounceTime := JsonGetInt64(SubObj, 'lastAnnounceTime', 0);
          Torrent.Trackers[I].LastAnnounceSucceeded := JsonGetBool(SubObj, 'lastAnnounceSucceeded', False);
          Torrent.Trackers[I].SeederCount := JsonGetInt(SubObj, 'seederCount', -1);
          Torrent.Trackers[I].LeecherCount := JsonGetInt(SubObj, 'leecherCount', -1);
          Torrent.Trackers[I].DownloadCount := JsonGetInt(SubObj, 'downloadCount', -1);
        end;
      end;
    end;
  finally
    Resp.Free;
  end;
end;

{ อ่านไฟล์ .torrent แปลงเป็น Base64 แล้วส่งคำสั่ง `torrent-add` พร้อมระบุไฟล์ที่ไม่ต้องการดาวน์โหลด (files-unwanted) }
function TTransmissionRpcClient.AddTorrentFile(const FileName, DownloadDir: string;
  StartImmediately: Boolean; Priority: Integer; const UnwantedFiles: array of Integer;
  out AddedName: string): Boolean;
var
  FS: TFileStream;
  RawBytes: string;
  Encoded: string;
  Args, Resp, RespArgs, AddedObj: TJSONObject;
  UnwantedArr: TJSONArray;
  I: Integer;
begin
  AddedName := '';
  RawBytes := '';
  if not FileExists(FileName) then
  begin
    FLastError := 'File not found: ' + FileName;
    Exit(False);
  end;

  FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(RawBytes, FS.Size);
    if FS.Size > 0 then
      FS.ReadBuffer(RawBytes[1], FS.Size);
    Encoded := EncodeStringBase64(RawBytes);
  finally
    FS.Free;
  end;

  Args := TJSONObject.Create;
  Args.Add('metainfo', Encoded);
  if FIsLocalSession and ((Trim(DownloadDir) = '') or (not IsDirectoryWritable(DownloadDir))) then
    Args.Add('download-dir', StringReplace(GetCurrentUserDownloadsDir, '\', '/', [rfReplaceAll]))
  else if Trim(DownloadDir) <> '' then
    Args.Add('download-dir', StringReplace(DownloadDir, '\', '/', [rfReplaceAll]));
  Args.Add('paused', not StartImmediately);
  Args.Add('bandwidthPriority', Priority);

  if Length(UnwantedFiles) > 0 then
  begin
    UnwantedArr := TJSONArray.Create;
    for I := Low(UnwantedFiles) to High(UnwantedFiles) do
      UnwantedArr.Add(UnwantedFiles[I]);
    Args.Add('files-unwanted', UnwantedArr);
  end;

  Result := SendRpcRequest('torrent-add', Args, Resp);
  if not Result then Exit;
  try
    RespArgs := Resp.Find('arguments') as TJSONObject;
    if RespArgs <> nil then
    begin
      AddedObj := RespArgs.Find('torrent-added') as TJSONObject;
      if AddedObj = nil then
        AddedObj := RespArgs.Find('torrent-duplicate') as TJSONObject;
      if AddedObj <> nil then
        AddedName := JsonGetStr(AddedObj, 'name', ExtractFileName(FileName));
    end;
  finally
    Resp.Free;
  end;
end;

{ เพิ่มทอร์เรนต์ผ่านลิงก์ Magnet หรือ HTTP URL ด้วยคำสั่ง `torrent-add` }
function TTransmissionRpcClient.AddTorrentUrl(const MagnetOrUrl, DownloadDir: string;
  StartImmediately: Boolean; Priority: Integer; out AddedName: string): Boolean;
var
  Args, Resp, RespArgs, AddedObj: TJSONObject;
begin
  AddedName := '';
  Args := TJSONObject.Create;
  Args.Add('filename', Trim(MagnetOrUrl));
  if FIsLocalSession and ((Trim(DownloadDir) = '') or (not IsDirectoryWritable(DownloadDir))) then
    Args.Add('download-dir', StringReplace(GetCurrentUserDownloadsDir, '\', '/', [rfReplaceAll]))
  else if Trim(DownloadDir) <> '' then
    Args.Add('download-dir', StringReplace(DownloadDir, '\', '/', [rfReplaceAll]));
  Args.Add('paused', not StartImmediately);
  Args.Add('bandwidthPriority', Priority);

  Result := SendRpcRequest('torrent-add', Args, Resp);
  if not Result then Exit;
  try
    RespArgs := Resp.Find('arguments') as TJSONObject;
    if RespArgs <> nil then
    begin
      AddedObj := RespArgs.Find('torrent-added') as TJSONObject;
      if AddedObj = nil then
        AddedObj := RespArgs.Find('torrent-duplicate') as TJSONObject;
      if AddedObj <> nil then
        AddedName := JsonGetStr(AddedObj, 'name', MagnetOrUrl);
    end;
  finally
    Resp.Free;
  end;
end;

{ สร้าง JSON Object ที่มีอาร์เรย์ `"ids": [...]` (หากอาร์เรย์ว่างหมายถึงทุกทอร์เรนต์) }
function BuildIdsArg(const Ids: array of Integer): TJSONObject;
var
  Arr: TJSONArray;
  I: Integer;
begin
  Result := TJSONObject.Create;
  if Length(Ids) > 0 then
  begin
    Arr := TJSONArray.Create;
    for I := Low(Ids) to High(Ids) do
      Arr.Add(Ids[I]);
    Result.Add('ids', Arr);
  end;
end;

function TTransmissionRpcClient.StartTorrents(const Ids: array of Integer;
  Immediate: Boolean): Boolean;
var
  Resp: TJSONObject;
  RpcMethod: string;
begin
  if Immediate then
    RpcMethod := 'torrent-start-now'
  else
    RpcMethod := 'torrent-start';
  Result := SendRpcRequest(RpcMethod, BuildIdsArg(Ids), Resp);
  Resp.Free;
end;

function TTransmissionRpcClient.StopTorrents(const Ids: array of Integer): Boolean;
var
  Resp: TJSONObject;
begin
  Result := SendRpcRequest('torrent-stop', BuildIdsArg(Ids), Resp);
  Resp.Free;
end;

function TTransmissionRpcClient.VerifyTorrents(const Ids: array of Integer): Boolean;
var
  Resp: TJSONObject;
begin
  Result := SendRpcRequest('torrent-verify', BuildIdsArg(Ids), Resp);
  Resp.Free;
end;

function TTransmissionRpcClient.ReannounceTorrents(const Ids: array of Integer): Boolean;
var
  Resp: TJSONObject;
begin
  Result := SendRpcRequest('torrent-reannounce', BuildIdsArg(Ids), Resp);
  Resp.Free;
end;

function TTransmissionRpcClient.RemoveTorrents(const Ids: array of Integer;
  DeleteFiles: Boolean): Boolean;
var
  Args, Resp: TJSONObject;
begin
  Args := BuildIdsArg(Ids);
  Args.Add('delete-local-data', DeleteFiles);
  Result := SendRpcRequest('torrent-remove', Args, Resp);
  Resp.Free;
end;

function TTransmissionRpcClient.SetTorrentLocation(const Ids: array of Integer;
  const NewDir: string; MoveData: Boolean): Boolean;
var
  Args, Resp: TJSONObject;
begin
  Args := BuildIdsArg(Ids);
  Args.Add('location', StringReplace(NewDir, '\', '/', [rfReplaceAll]));
  Args.Add('move', MoveData);
  Result := SendRpcRequest('torrent-set-location', Args, Resp);
  Resp.Free;
end;

function TTransmissionRpcClient.RenameTorrentPath(TorrentId: Integer;
  const OldPath, NewName: string): Boolean;
var
  Args, Resp: TJSONObject;
  IdsArr: TJSONArray;
begin
  Args := TJSONObject.Create;
  IdsArr := TJSONArray.Create;
  IdsArr.Add(TorrentId);
  Args.Add('ids', IdsArr);
  Args.Add('path', OldPath);
  Args.Add('name', NewName);
  Result := SendRpcRequest('torrent-rename-path', Args, Resp);
  Resp.Free;
end;

function TTransmissionRpcClient.QueueMove(const Ids: array of Integer;
  const DirectionMethod: string): Boolean;
var
  Resp: TJSONObject;
begin
  Result := SendRpcRequest(DirectionMethod, BuildIdsArg(Ids), Resp);
  Resp.Free;
end;

function TTransmissionRpcClient.SetTorrentOptions(TorrentId: Integer;
  Args: TJSONObject): Boolean;
var
  IdsArr: TJSONArray;
  Resp: TJSONObject;
begin
  if Args = nil then Exit(False);
  IdsArr := TJSONArray.Create;
  IdsArr.Add(TorrentId);
  Args.Add('ids', IdsArr);
  Result := SendRpcRequest('torrent-set', Args, Resp);
  Resp.Free;
end;

function TTransmissionRpcClient.SetTorrentsTrackerPaused(const Ids: array of Integer;
  Paused: Boolean): Boolean;
var
  Args, Resp: TJSONObject;
begin
  Args := BuildIdsArg(Ids);
  Args.Add('tracker_paused', Paused);
  Result := SendRpcRequest('torrent-set', Args, Resp);
  Resp.Free;
end;

function TTransmissionRpcClient.SetTorrentsTrackerAutoPause(const Ids: array of Integer;
  AutoPause: Boolean): Boolean;
var
  Args, Resp: TJSONObject;
begin
  Args := BuildIdsArg(Ids);
  Args.Add('tracker_auto_pause', AutoPause);
  Result := SendRpcRequest('torrent-set', Args, Resp);
  Resp.Free;
end;

function TTransmissionRpcClient.TestPeerPort(out IsOpen: Boolean): Boolean;
var
  Resp, RespArgs: TJSONObject;
begin
  IsOpen := False;
  Result := SendRpcRequest('port-test', nil, Resp);
  if not Result then Exit;
  try
    RespArgs := Resp.Find('arguments') as TJSONObject;
    if RespArgs <> nil then
      IsOpen := JsonGetBool(RespArgs, 'port-is-open', False);
  finally
    Resp.Free;
  end;
end;

function TTransmissionRpcClient.UpdateBlocklist(out RulesCount: Integer): Boolean;
var
  Resp, RespArgs: TJSONObject;
begin
  RulesCount := 0;
  Result := SendRpcRequest('blocklist-update', nil, Resp);
  if not Result then Exit;
  try
    RespArgs := Resp.Find('arguments') as TJSONObject;
    if RespArgs <> nil then
      RulesCount := JsonGetInt(RespArgs, 'blocklist-size', 0);
  finally
    Resp.Free;
  end;
end;

function TTransmissionRpcClient.QueryFreeSpace(const DirPath: string;
  out FreeBytes: Int64): Boolean;
var
  Args, Resp, RespArgs: TJSONObject;
begin
  FreeBytes := -1;
  Args := TJSONObject.Create;
  Args.Add('path', StringReplace(DirPath, '\', '/', [rfReplaceAll]));
  Result := SendRpcRequest('free-space', Args, Resp);
  if not Result then Exit;
  try
    RespArgs := Resp.Find('arguments') as TJSONObject;
    if RespArgs <> nil then
      FreeBytes := JsonGetInt64(RespArgs, 'size-bytes', -1);
  finally
    Resp.Free;
  end;
end;

{ ส่งต่อคำขอ JSON-RPC ดิบจากหน้าเว็บ (Web UI) ไปยัง RPC Server เบื้องหลังพร้อมจัดการ Session Token }
function TTransmissionRpcClient.ForwardRawRpc(const RequestJson: string;
  out ResponseJson: string): Boolean;
var
  Http: TFPHTTPClient;
  ReqStream, RespStream: TStringStream;
  Attempt: Integer;
  NewSid: string;
begin
  Result := False;
  ResponseJson := '{"result":"connection-error"}';

  Http := TFPHTTPClient.Create(nil);
  try
    if FIsLocalSession then
    begin
      Http.ConnectTimeout := 800;
      Http.IOTimeout := 3000;
    end
    else
    begin
      Http.ConnectTimeout := 2500;
      Http.IOTimeout := 5000;
    end;
    Http.AllowRedirect := False;
    if FUsername <> '' then
    begin
      Http.UserName := FUsername;
      Http.Password := FPassword;
    end;

    for Attempt := 1 to 2 do
    begin
      Http.RequestHeaders.Clear;
      Http.RequestHeaders.Add('Content-Type: application/json');
      if FSessionId <> '' then
        Http.RequestHeaders.Add('X-Transmission-Session-Id: ' + FSessionId);

      ReqStream := TStringStream.Create(RequestJson);
      RespStream := TStringStream.Create('');
      try
        Http.RequestBody := ReqStream;
        try
          Http.Post(GetRpcUrl, RespStream);
        except
          on E: Exception do
          begin
            if Http.ResponseStatusCode <> 409 then
              Exit(False);
          end;
        end;

        if Http.ResponseStatusCode = 409 then
        begin
          NewSid := ExtractHeaderValue(Http.ResponseHeaders, 'X-Transmission-Session-Id');
          if NewSid <> '' then
          begin
            FSessionId := NewSid;
            Continue;
          end;
        end;

        if Http.ResponseStatusCode = 200 then
        begin
          ResponseJson := RespStream.DataString;
          Result := True;
          Break;
        end;
      finally
        Http.RequestBody := nil;
        ReqStream.Free;
        RespStream.Free;
      end;
    end;
  finally
    Http.Free;
  end;
end;

{ เรียกใช้งาน `transmission-create.exe` เพื่อสร้างไฟล์ .torrent จากไฟล์หรือโฟลเดอร์ }
function TTransmissionRpcClient.CreateTorrentFile(const SourcePath,
  OutputTorrentFile: string; Trackers: TStrings; const Comment: string;
  IsPrivate: Boolean; out LogOutput: string): Boolean;
var
  AppDir, CreateExe: string;
  Proc: TProcess;
  OutSL: TStringList;
  I: Integer;
begin
  Result := False;
  LogOutput := '';
  AppDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));

  CreateExe := AppDir + 'transmission-create.exe';
  if not FileExists(CreateExe) then
  begin
    CreateExe := IncludeTrailingPathDelimiter(GetEmbeddedBinDir(FDataDir)) + 'transmission-create.exe';
    if not EnsureEmbeddedAsset('TR_CREATE_Z', CreateExe) then
      CreateExe := '';
  end;
  if not FileExists(CreateExe) then
    CreateExe := ExpandFileName(AppDir + '..\build\utils\transmission-create.exe');
  if not FileExists(CreateExe) then
    CreateExe := ExpandFileName(AppDir + '..\..\build\utils\transmission-create.exe');

  if not FileExists(CreateExe) then
  begin
    FLastError := 'transmission-create.exe not found in build/utils/';
    LogOutput := FLastError;
    Exit(False);
  end;

  Proc := TProcess.Create(nil);
  OutSL := TStringList.Create;
  try
    Proc.Executable := CreateExe;
    Proc.CurrentDirectory := ExtractFilePath(CreateExe);
    Proc.Options := [poWaitOnExit, poUsePipes, poNoConsole, poStderrToOutPut];
    Proc.Parameters.Add('-o');
    Proc.Parameters.Add(OutputTorrentFile);
    if IsPrivate then
      Proc.Parameters.Add('-p');
    if Trim(Comment) <> '' then
    begin
      Proc.Parameters.Add('-c');
      Proc.Parameters.Add(Trim(Comment));
    end;
    if Trackers <> nil then
    begin
      for I := 0 to Trackers.Count - 1 do
        if Trim(Trackers[I]) <> '' then
        begin
          Proc.Parameters.Add('-t');
          Proc.Parameters.Add(Trim(Trackers[I]));
        end;
    end;
    Proc.Parameters.Add(SourcePath);
    Proc.Execute;
    OutSL.LoadFromStream(Proc.Output);
    LogOutput := OutSL.Text;
    Result := (Proc.ExitStatus = 0) and FileExists(OutputTorrentFile);
    if not Result and (FLastError = '') then
      FLastError := Trim(LogOutput);
  finally
    OutSL.Free;
    Proc.Free;
  end;
end;

end.
