unit uWebServer;

{$mode objfpc}{$H+}
{$HINTS OFF}

interface

uses
  Classes, SysUtils, fphttpserver, base64, uRpcClient;

type
  TWebServerThread = class;

  { TTransmissionWebServer }
  TTransmissionWebServer = class
  private
    FRpc: TTransmissionRpcClient;
    FPort: Word;
    FEnabled: Boolean;
    FAuthEnabled: Boolean;
    FUsername: string;
    FPassword: string;
    FThread: TWebServerThread;
    function FindWebUiHtmlPath: string;
    function CheckBasicAuth(ARequest: TFPHTTPConnectionRequest): Boolean;
    procedure HandleRequest(Sender: TObject; var ARequest: TFPHTTPConnectionRequest;
      var AResponse: TFPHTTPConnectionResponse);
  public
    constructor Create(ARpc: TTransmissionRpcClient);
    destructor Destroy; override;

    procedure StartServer;
    procedure StopServer;
    procedure RestartServer;
    function GetWebUrl: string;

    property Port: Word read FPort write FPort;
    property Enabled: Boolean read FEnabled write FEnabled;
    property AuthEnabled: Boolean read FAuthEnabled write FAuthEnabled;
    property Username: string read FUsername write FUsername;
    property Password: string read FPassword write FPassword;
  end;

  { TWebServerThread }
  TWebServerThread = class(TThread)
  private
    FServer: TFPHTTPServer;
  protected
    procedure Execute; override;
  public
    constructor Create(APort: Word; AHandler: THTTPServerRequestHandler);
    destructor Destroy; override;
    procedure StopHttp;
  end;

implementation

{ TWebServerThread }

constructor TWebServerThread.Create(APort: Word; AHandler: THTTPServerRequestHandler);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FServer := TFPHTTPServer.Create(nil);
  FServer.Port := APort;
  FServer.Threaded := True;
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
  try
    FServer.Active := True;
  except
  end;
end;

procedure TWebServerThread.StopHttp;
begin
  if (FServer <> nil) and FServer.Active then
  begin
    try
      FServer.Active := False;
    except
    end;
  end;
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

function TTransmissionWebServer.FindWebUiHtmlPath: string;
var
  AppDir, Candidate: string;
begin
  AppDir := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));

  Candidate := AppDir + 'web_ui\index.html';
  if FileExists(Candidate) then Exit(Candidate);

  Candidate := ExpandFileName(AppDir + '..\lazarus\web_ui\index.html');
  if FileExists(Candidate) then Exit(Candidate);

  Candidate := ExpandFileName(AppDir + '..\web\public_html\index.html');
  if FileExists(Candidate) then Exit(Candidate);

  Result := '';
end;

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

procedure TTransmissionWebServer.HandleRequest(Sender: TObject;
  var ARequest: TFPHTTPConnectionRequest;
  var AResponse: TFPHTTPConnectionResponse);
var
  UriPath, HtmlPath, RespJson: string;
  SL: TStringList;
begin
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
