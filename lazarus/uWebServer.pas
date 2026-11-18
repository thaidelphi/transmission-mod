{******************************************************************************
 * ยูนิต: uWebServer.pas
 * คำอธิบาย:
 *   เซิร์ฟเวอร์ HTTP ในตัวแบบ Multi-threaded (`TFPHTTPServer` รันบน `TThread` แยก)
 *   สำหรับให้บริการหน้าเว็บควบคุมบิตทอร์เรนต์ (`web_ui/index.html`) และทำหน้าที่เป็น
 *   JSON-RPC Proxy Gateway ที่พาธ `/transmission/rpc`
 *
 * คุณสมบัติหลัก:
 *   1. รันบนพอร์ตเริ่มต้น `9092` (เปลี่ยนพอร์ตได้ในหน้าต่าง Preferences -> Remote / Web)
 *   2. รองรับการตรวจสอบสิทธิ์แบบ HTTP Basic Authentication (`WWW-Authenticate`)
 *   3. ส่งต่อคำขอ `/transmission/rpc` ไปยัง `TTransmissionRpcClient.ForwardRawRpc`
 *      ทำให้หน้าเว็บสามารถควบคุมทั้ง Local Session และ Remote Session ได้โดยไม่ติด CORS
 ******************************************************************************}
unit uWebServer;

{$mode objfpc}{$H+}
{$HINTS OFF}

interface

uses
  Classes, SysUtils, fphttpserver, base64, uTypes, uRpcClient;

type
  TWebServerThread = class;

  { TTransmissionWebServer: คลาสควบคุมการเปิด/ปิดและจัดการคำขอของ Web UI Server }
  TTransmissionWebServer = class
  private
    FRpc: TTransmissionRpcClient; // อ้างอิงไปยัง RPC Client หลักของโปรแกรม
    FPort: Word;                  // พอร์ต HTTP ที่เปิดรับการเชื่อมต่อ (ค่าเริ่มต้น 9092)
    FEnabled: Boolean;            // สถานะการเปิดใช้งาน Web Server
    FAuthEnabled: Boolean;        // เปิดการถามรหัสผ่าน HTTP Basic Auth หรือไม่
    FUsername: string;            // ชื่อผู้ใช้สำหรับเข้าหน้าเว็บ
    FPassword: string;            // รหัสผ่านสำหรับเข้าหน้าเว็บ
    FThread: TWebServerThread;    // เธรดเบื้องหลังที่รัน TFPHTTPServer
    function FindWebUiHtmlPath: string;
    function CheckBasicAuth(ARequest: TFPHTTPConnectionRequest): Boolean;
    procedure HandleRequest(Sender: TObject; var ARequest: TFPHTTPConnectionRequest;
      var AResponse: TFPHTTPConnectionResponse);
  public
    constructor Create(ARpc: TTransmissionRpcClient);
    destructor Destroy; override;

    { เริ่มต้น / หยุด / รีสตาร์ท HTTP Server }
    procedure StartServer;
    procedure StopServer;
    procedure RestartServer;

    { คืนค่า URL สำหรับเปิดหน้าเว็บในเบราว์เซอร์ เช่น "http://127.0.0.1:9092/" }
    function GetWebUrl: string;
    function IsRunning: Boolean;
    function LastError: string;

    property Port: Word read FPort write FPort;
    property Enabled: Boolean read FEnabled write FEnabled;
    property AuthEnabled: Boolean read FAuthEnabled write FAuthEnabled;
    property Username: string read FUsername write FUsername;
    property Password: string read FPassword write FPassword;
  end;

  { TWebServerThread: เธรดแยกสำหรับรัน Blocking Accept Loop ของ TFPHTTPServer }
  TWebServerThread = class(TThread)
  private
    FServer: TFPHTTPServer;
    FRunning: Boolean;
    FLastError: string;
  protected
    procedure Execute; override;
  public
    constructor Create(APort: Word; AHandler: THTTPServerRequestHandler);
    destructor Destroy; override;
    procedure StopHttp;
    property Running: Boolean read FRunning;
    property LastError: string read FLastError;
  end;

implementation

{ TWebServerThread }

constructor TWebServerThread.Create(APort: Word; AHandler: THTTPServerRequestHandler);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FRunning := False;
  FLastError := '';
  FServer := TFPHTTPServer.Create(nil);
  FServer.Port := APort;
  FServer.Threaded := True;
  // กำหนด AcceptIdleTimeout เพื่อไม่ให้ socket accept() ค้างถาวรและสามารถปิดโปรแกรมได้ทันที
  FServer.AcceptIdleTimeout := 100;
  FServer.OnRequest := AHandler;
  Start;
end;

destructor TWebServerThread.Destroy;
begin
  StopHttp;
  FreeAndNil(FServer);
  inherited Destroy;
end;

procedure TWebServerThread.Execute;
begin
  if Terminated then Exit;
  FRunning := True;
  FLastError := '';
  try
    FServer.Active := True;
  except
    on E: Exception do
      FLastError := E.Message;
  end;
  FRunning := False;
end;

procedure TWebServerThread.StopHttp;
begin
  Terminate;
  if (FServer <> nil) and FServer.Active then
  begin
    try
      FServer.Active := False;
    except
    end;
  end;
  FRunning := False;
end;

{ TTransmissionWebServer }

constructor TTransmissionWebServer.Create(ARpc: TTransmissionRpcClient);
begin
  inherited Create;
  FRpc := ARpc;
  FPort := 9092;
  FEnabled := True;
  FAuthEnabled := False;
  FUsername := 'admin';
  FPassword := '';
  FThread := nil;
end;

destructor TTransmissionWebServer.Destroy;
begin
  StopServer;
  inherited Destroy;
end;

procedure TTransmissionWebServer.StartServer;
begin
  if not FEnabled then Exit;
  if FThread <> nil then Exit;
  try
    FThread := TWebServerThread.Create(FPort, @HandleRequest);
  except
    FreeAndNil(FThread);
  end;
end;

procedure TTransmissionWebServer.StopServer;
begin
  if FThread <> nil then
  begin
    FThread.StopHttp;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
end;

procedure TTransmissionWebServer.RestartServer;
begin
  StopServer;
  if FEnabled then
    StartServer;
end;

function TTransmissionWebServer.GetWebUrl: string;
begin
  if FEnabled then
    Result := Format('http://127.0.0.1:%d/', [FPort])
  else
    Result := Format('http://%s:%d/', [FRpc.Host, FRpc.Port]);
end;

function TTransmissionWebServer.IsRunning: Boolean;
begin
  Result := (FThread <> nil) and FThread.Running;
end;

function TTransmissionWebServer.LastError: string;
begin
  if FThread <> nil then
    Result := FThread.LastError
  else
    Result := '';
end;

{ ค้นหาไฟล์ HTML ของหน้าเว็บ Web UI จากโฟลเดอร์ `web_ui/index.html` }
function TTransmissionWebServer.FindWebUiHtmlPath: string;
var
  AppDir, Candidate: string;
begin
  AppDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));

  Candidate := AppDir + 'web_ui\index.html';
  if FileExists(Candidate) then Exit(Candidate);

  if FRpc <> nil then
    Candidate := IncludeTrailingPathDelimiter(GetEmbeddedBinDir(FRpc.DataDir)) + 'index.html'
  else
    Candidate := IncludeTrailingPathDelimiter(GetEmbeddedBinDir('')) + 'index.html';
  if EnsureEmbeddedAsset('TR_WEBUI_Z', Candidate) then Exit(Candidate);

  Candidate := ExpandFileName(AppDir + '..\lazarus\web_ui\index.html');
  if FileExists(Candidate) then Exit(Candidate);

  Candidate := ExpandFileName(AppDir + '..\web\public_html\index.html');
  if FileExists(Candidate) then Exit(Candidate);

  Result := '';
end;

{ ตรวจสอบ Header `Authorization: Basic <base64>` กรณีผู้ใช้เปิดใช้งานรหัสผ่านหน้าเว็บ }
function TTransmissionWebServer.CheckBasicAuth(ARequest: TFPHTTPConnectionRequest): Boolean;
var
  AuthHeader, Expected: string;
begin
  if not FAuthEnabled or (FUsername = '') then
    Exit(True);

  AuthHeader := Trim(ARequest.Authorization);
  Expected := 'Basic ' + EncodeStringBase64(FUsername + ':' + FPassword);
  Result := SameText(AuthHeader, Expected);
end;

{ เมธอดหลักในการตอบกลับคำขอ HTTP ทั้งหน้าเว็บ HTML และคำสั่ง `/transmission/rpc` }
procedure TTransmissionWebServer.HandleRequest(Sender: TObject;
  var ARequest: TFPHTTPConnectionRequest;
  var AResponse: TFPHTTPConnectionResponse);
var
  UriPath, HtmlPath, RespJson: string;
  SL: TStringList;
begin
  // 1. ตรวจสอบสิทธิ์ HTTP Basic Auth หากเปิดใช้งานไว้
  if not CheckBasicAuth(ARequest) then
  begin
    AResponse.Code := 401;
    AResponse.CodeText := 'Unauthorized';
    AResponse.CustomHeaders.Values['WWW-Authenticate'] := 'Basic realm="Transmission Web UI"';
    AResponse.Content := '401 Unauthorized';
    Exit;
  end;

  UriPath := ARequest.URI;
  if Pos('?', UriPath) > 0 then
    UriPath := Copy(UriPath, 1, Pos('?', UriPath) - 1);

  // 2. หากเป็นคำขอ JSON-RPC ที่ `/transmission/rpc` ให้ส่งต่อไปยัง FRpc.ForwardRawRpc
  if SameText(UriPath, '/transmission/rpc') or SameText(UriPath, '/rpc') then
  begin
    AResponse.ContentType := 'application/json; charset=utf-8';
    AResponse.CustomHeaders.Values['Access-Control-Allow-Origin'] := '*';
    if SameText(ARequest.Method, 'OPTIONS') then
    begin
      AResponse.Code := 200;
      AResponse.Content := '';
      Exit;
    end;
    FRpc.ForwardRawRpc(ARequest.Content, RespJson);
    AResponse.Code := 200;
    AResponse.Content := RespJson;
    Exit;
  end;

  // 3. เสิร์ฟหน้าเว็บแอปพลิเคชัน `web_ui/index.html`
  HtmlPath := FindWebUiHtmlPath;
  if (HtmlPath <> '') and FileExists(HtmlPath) then
  begin
    SL := TStringList.Create;
    try
      SL.LoadFromFile(HtmlPath);
      AResponse.Code := 200;
      AResponse.ContentType := 'text/html; charset=utf-8';
      AResponse.Content := SL.Text;
    finally
      SL.Free;
    end;
  end
  else
  begin
    AResponse.Code := 200;
    AResponse.ContentType := 'text/html; charset=utf-8';
    AResponse.Content := '<html><body><h3>Transmission Web UI</h3><p>web_ui/index.html not found.</p></body></html>';
  end;
end;

end.
