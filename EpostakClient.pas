unit EpostakClient;

{ ============================================================================
  Klient pre epostak.sk SAPI-SK API (Peppol Access Point)
  Delphi 6 / WinInet - rovnaky transportny mechanizmus ako povodny Ep24Client.

  Podporuje: auth (client_credentials, refresh, revoke, status), odoslanie
  UBL dokumentu, zoznam prijatych dokumentov (s pagination), stiahnutie UBL
  prijateho dokumentu, potvrdenie (ack), retry pre retryable chyby.

  Doc: https://epostak.sk/api/docs
  ============================================================================ }

interface

uses
  Classes, SysUtils, Windows, WinInet;

type
  TEpostakResult = record
    HTTPStatus: Integer;
    ResponseBody: string;   // surove bajty tak, ako prisli po sieti (UTF-8)
    IsSuccess: Boolean;
    ErrorCode: string;
    ErrorMessage: string;
    RequestId: string;      // pre podporu - z chybovej odpovede
  end;

  TEpostakDocument = record
    DocumentId: string;
    DocumentTypeId: string;
    ProcessId: string;
    SenderParticipantId: string;
    ReceiverParticipantId: string;
    CreationDateTime: string;
  end;

  TEpostakDocumentList = array of TEpostakDocument;

  TEpostakDocumentListResult = record
    Documents: TEpostakDocumentList;
    NextPageToken: string;
  end;

  TEpostakRequestMethod = (eqGET, eqPOST);

  TEpostakClient = class
  private
    FBaseURL: string;              // napr. https://dev.epostak.sk/sapi/v1
    FClientId: string;
    FClientSecret: string;
    FParticipantId: string;        // X-Peppol-Participant-Id pouzity pre dalsie volania
    FAccessToken: string;
    FRefreshToken: string;         // pre /auth/renew
    FTokenExpiresAtUTC: TDateTime; // lokalny Now() - casovanie postacuje na TTL logiku

    function DoRequestInternal(const AMethod: TEpostakRequestMethod; const APath, ABody,
      AContentType: string; AIncludeAuth, AIncludeParticipant: Boolean;
      const AIdempotencyKey: string): TEpostakResult;

    function DoRequestWithRetry(const AMethod: TEpostakRequestMethod; const APath, ABody,
      AContentType: string; AIncludeAuth, AIncludeParticipant: Boolean;
      const AIdempotencyKey: string): TEpostakResult;

    function ExtractJSONString(const AJSON, AName: string): string;
    function ExtractJSONInt(const AJSON, AName: string; ADefault: Integer): Integer;
    function JSONEscape(const S: string): string;
    function JSONUnescape(const S: string): string;
    function GetUTCNowString: string;
    procedure EnsureToken;
    procedure CheckResult(const R: TEpostakResult; const AContext: string);
  public
    constructor Create(const ABaseURL, AClientId, AClientSecret, AParticipantId: string);

    function GenerateIdempotencyKey: string;
    procedure Authenticate;
    procedure RenewToken;
    procedure RevokeToken;
    function TokenStatus: Boolean;

    { Odosielanie - vrati providerDocumentId }
    function SendInvoice(const ADocumentId, ADocumentTypeId, AProcessId,
      ASenderParticipantId, AReceiverParticipantId, AUblXml: string): string;

    { Prijimanie - FParticipantId (z konstruktora) urcuje, ktoru schranku citame }
    function ListReceived(const AStatus: string = 'RECEIVED';
      ALimit: Integer = 100; const APageToken: string = ''): TEpostakDocumentListResult;
    function GetDocumentXML(const ADocumentId: string): string;
    procedure AcknowledgeDocument(const ADocumentId: string);

    function ConfigMatches(const ABaseURL, AClientId, AClientSecret,
      AParticipantId: string): Boolean;

    property ParticipantId: string read FParticipantId write FParticipantId;
  end;

{ Ulozi surove bajty (napr. z GetDocumentXML) do suboru presne tak ako prisli,
  bez akejkolvek ANSI/Unicode konverzie - dolezite, payload je uz UTF-8. }
procedure SaveRawBytesToFile(const AFileName, ARawBytes: string);

implementation


function FindMatchingBracket(const S: string; AOpenPos: Integer;
  AOpenChar, ACloseChar: Char): Integer;
var
  i, Depth: Integer;
  InString: Boolean;
begin
  Result := 0;
  Depth := 0;
  InString := False;
  i := AOpenPos;
  while i <= Length(S) do
  begin
    if InString then
    begin
      if S[i] = '\' then
        Inc(i) { preskocit escapovany znak }
      else if S[i] = '"' then
        InString := False;
    end
    else
    begin
      if S[i] = '"' then
        InString := True
      else if S[i] = AOpenChar then
        Inc(Depth)
      else if S[i] = ACloseChar then
      begin
        Dec(Depth);
        if Depth = 0 then
        begin
          Result := i;
          Exit;
        end;
      end;
    end;
    Inc(i);
  end;
end;

function UTF8FromAnsi(const S: string): string;
begin
  { Konvertuje lokalny ANSI retazec (napr. Windows-1250 diakritika) na
    bajtovy retazec obsahujuci UTF-8. Server (epostak.sk) ocakava UTF-8. }
  Result := UTF8Encode(WideString(S));
end;

procedure SaveRawBytesToFile(const AFileName, ARawBytes: string);
var
  FS: TFileStream;
begin
  FS := TFileStream.Create(AFileName, fmCreate);
  try
    if Length(ARawBytes) > 0 then
      FS.WriteBuffer(ARawBytes[1], Length(ARawBytes));
  finally
    FS.Free;
  end;
end;

{ ============================================================================
  TEpostakClient
  ============================================================================ }

constructor TEpostakClient.Create(const ABaseURL, AClientId, AClientSecret,
  AParticipantId: string);
begin
  inherited Create;
  FBaseURL := ABaseURL;
  while (Length(FBaseURL) > 0) and (FBaseURL[Length(FBaseURL)] = '/') do
    Delete(FBaseURL, Length(FBaseURL), 1);
  FClientId := AClientId;
  FClientSecret := AClientSecret;
  FParticipantId := AParticipantId;
  FAccessToken := '';
  FRefreshToken := '';
  FTokenExpiresAtUTC := 0;
end;

function TEpostakClient.GenerateIdempotencyKey: string;
var
  GUID: TGUID;
begin
  if CreateGUID(GUID) <> S_OK then
    raise Exception.Create('Nepodarilo sa vygenerovat UUID');
  Result := GUIDToString(GUID);
  if (Length(Result) >= 2) and (Result[1] = '{') and (Result[Length(Result)] = '}') then
    Result := Copy(Result, 2, Length(Result) - 2);
end;

function TEpostakClient.GetUTCNowString: string;
var
  ST: TSystemTime;
begin
  GetSystemTime(ST);
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', SystemTimeToDateTime(ST));
end;

{ ----------------------------------------------------------------------------
  JSON - minimalne pomocne funkcie (rovnaky styl ako povodny Ep24Client)
  ---------------------------------------------------------------------------- }

function TEpostakClient.ExtractJSONString(const AJSON, AName: string): string;
var
  P, StartPos, EndPos: Integer;
  SearchText: string;
begin
  Result := '';
  SearchText := '"' + AName + '"';
  P := Pos(SearchText, AJSON);
  if P = 0 then Exit;

  P := P + Length(SearchText);
  while (P <= Length(AJSON)) and (AJSON[P] <> ':') do Inc(P);
  if P > Length(AJSON) then Exit;
  Inc(P);
  while (P <= Length(AJSON)) and (AJSON[P] in [' ', #9, #10, #13]) do Inc(P);

  if (P > Length(AJSON)) or (AJSON[P] <> '"') then Exit;
  StartPos := P + 1;
  EndPos := StartPos;

  while EndPos <= Length(AJSON) do
  begin
    if (AJSON[EndPos] = '"') and
       ((EndPos = StartPos) or (AJSON[EndPos - 1] <> '\')) then
      Break;
    Inc(EndPos);
  end;

  if EndPos <= Length(AJSON) then
    Result := JSONUnescape(Copy(AJSON, StartPos, EndPos - StartPos));
end;

function TEpostakClient.ExtractJSONInt(const AJSON, AName: string;
  ADefault: Integer): Integer;
var
  P, StartPos, EndPos: Integer;
  SearchText, NumStr: string;
begin
  Result := ADefault;
  SearchText := '"' + AName + '"';
  P := Pos(SearchText, AJSON);
  if P = 0 then Exit;

  P := P + Length(SearchText);
  while (P <= Length(AJSON)) and (AJSON[P] <> ':') do Inc(P);
  if P > Length(AJSON) then Exit;
  Inc(P);
  while (P <= Length(AJSON)) and (AJSON[P] in [' ', #9, #10, #13]) do Inc(P);

  StartPos := P;
  EndPos := P;
  while (EndPos <= Length(AJSON)) and (AJSON[EndPos] in ['0'..'9', '-']) do
    Inc(EndPos);
  NumStr := Copy(AJSON, StartPos, EndPos - StartPos);
  if NumStr <> '' then
    Result := StrToIntDef(NumStr, ADefault);
end;

function TEpostakClient.JSONEscape(const S: string): string;
var
  i: Integer;
  c: Char;
begin
  Result := '';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    case c of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #8:  Result := Result + '\b';
      #9:  Result := Result + '\t';
      #10: Result := Result + '\n';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
    else
      if Ord(c) < $20 then
        Result := Result + '\u' + IntToHex(Ord(c), 4)
      else
        Result := Result + c;
    end;
  end;
end;

function TEpostakClient.JSONUnescape(const S: string): string;
var
  i: Integer;
begin
  Result := '';
  i := 1;
  while i <= Length(S) do
  begin
    if (S[i] = '\') and (i < Length(S)) then
    begin
      Inc(i);
      case S[i] of
        '"': Result := Result + '"';
        '\': Result := Result + '\';
        '/': Result := Result + '/';
        'b': Result := Result + #8;
        'f': Result := Result + #12;
        'n': Result := Result + #10;
        'r': Result := Result + #13;
        't': Result := Result + #9;
        'u':
          begin
            if i + 4 <= Length(S) then
            begin
              Result := Result + Chr(StrToIntDef('$' + Copy(S, i + 1, 4), 63));
              Inc(i, 4);
            end;
          end;
      else
        Result := Result + S[i];
      end;
    end
    else
      Result := Result + S[i];
    Inc(i);
  end;
end;

{ ----------------------------------------------------------------------------
  HTTP - WinInet (rovnaka technika ako povodny Ep24Client.DoRequest)
  ---------------------------------------------------------------------------- }

function TEpostakClient.DoRequestInternal(const AMethod: TEpostakRequestMethod;
  const APath, ABody, AContentType: string; AIncludeAuth, AIncludeParticipant: Boolean;
  const AIdempotencyKey: string): TEpostakResult;
var
  hSession, hConnect, hRequest: HINTERNET;
  Host: string;
  Port: Word;
  Flags: DWORD;
  Headers: string;
  ResponseStream: TMemoryStream;
  Buffer: array[0..4095] of Byte;
  BytesRead: DWORD;
  StatusCode: DWORD;
  StatusCodeLen: DWORD;
  Index: DWORD;
  ResponseText: string;
  MethodStr: string;
  BodyPtr: PChar;
  BodyLen: DWORD;
  UrlPath: string;
begin
  FillChar(Result, SizeOf(Result), 0);
  hSession := nil;
  hConnect := nil;
  hRequest := nil;
  ResponseStream := TMemoryStream.Create;

  try
    try
      Host := FBaseURL;
      UrlPath := '';
      if Pos('https://', Host) = 1 then
      begin
        Delete(Host, 1, 8);
        Port := INTERNET_DEFAULT_HTTPS_PORT;
      end
      else if Pos('http://', Host) = 1 then
      begin
        Delete(Host, 1, 7);
        Port := INTERNET_DEFAULT_HTTP_PORT;
      end
      else
        Port := INTERNET_DEFAULT_HTTP_PORT;

      { Host moze este obsahovat cestu (FBaseURL = https://dev.epostak.sk/sapi/v1) }
      Index := Pos('/', Host);
      if Index > 0 then
      begin
        UrlPath := Copy(Host, Index, MaxInt);
        Host := Copy(Host, 1, Index - 1);
      end;

      case AMethod of
        eqGET: MethodStr := 'GET';
        eqPOST: MethodStr := 'POST';
      end;

      hSession := InternetOpen('EpostakClient/1.0', INTERNET_OPEN_TYPE_PRECONFIG,
        nil, nil, 0);
      if hSession = nil then
        raise Exception.Create('InternetOpen zlyhal: ' + IntToStr(GetLastError));

      hConnect := InternetConnect(hSession, PChar(Host), Port,
        nil, nil, INTERNET_SERVICE_HTTP, 0, 0);
      if hConnect = nil then
        raise Exception.Create('InternetConnect zlyhal: ' + IntToStr(GetLastError));

      Flags := INTERNET_FLAG_RELOAD;
      if Port = INTERNET_DEFAULT_HTTPS_PORT then
        Flags := Flags or INTERNET_FLAG_SECURE;

      hRequest := HttpOpenRequest(hConnect, PChar(MethodStr), PChar(UrlPath + APath),
        'HTTP/1.1', nil, nil, Flags, 0);
      if hRequest = nil then
        raise Exception.Create('HttpOpenRequest zlyhal: ' + IntToStr(GetLastError));

      Headers := '';
      if AIncludeAuth then
        Headers := Headers + 'Authorization: Bearer ' + FAccessToken + #13#10;
      if AIncludeParticipant then
        Headers := Headers + 'X-Peppol-Participant-Id: ' + FParticipantId + #13#10;
      if AContentType <> '' then
        Headers := Headers + 'Content-Type: ' + AContentType + #13#10;
      Headers := Headers + 'Accept: application/json'#13#10;
      if AIdempotencyKey <> '' then
        Headers := Headers + 'Idempotency-Key: ' + AIdempotencyKey + #13#10;

      if ABody <> '' then
      begin
        BodyPtr := PChar(ABody);
        BodyLen := Length(ABody);
      end
      else
      begin
        BodyPtr := nil;
        BodyLen := 0;
      end;

      if not HttpSendRequest(hRequest, PChar(Headers), Length(Headers),
        BodyPtr, BodyLen) then
        raise Exception.Create('HttpSendRequest zlyhal: ' + IntToStr(GetLastError));

      StatusCode := 0;
      StatusCodeLen := SizeOf(StatusCode);
      Index := 0;
      if HttpQueryInfo(hRequest, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER,
        @StatusCode, StatusCodeLen, Index) then
        Result.HTTPStatus := StatusCode;

      repeat
        if not InternetReadFile(hRequest, @Buffer, SizeOf(Buffer), BytesRead) then
          raise Exception.Create('InternetReadFile zlyhal: ' + IntToStr(GetLastError));
        if BytesRead > 0 then
          ResponseStream.Write(Buffer, BytesRead);
      until BytesRead = 0;

      ResponseStream.Position := 0;
      if ResponseStream.Size > 0 then
      begin
        SetLength(ResponseText, ResponseStream.Size);
        ResponseStream.ReadBuffer(ResponseText[1], ResponseStream.Size);
      end
      else
        ResponseText := '';

      Result.ResponseBody := ResponseText;
      Result.IsSuccess := (Result.HTTPStatus >= 200) and (Result.HTTPStatus < 300);
      { Lepse parsovanie chyby - najprv skusime vnoreny error objekt }
      Result.ErrorCode := ExtractJSONString(ResponseText, 'code');
      Result.ErrorMessage := ExtractJSONString(ResponseText, 'message');
      Result.RequestId := ExtractJSONString(ResponseText, 'requestId');

    except
      on E: Exception do
      begin
        Result.HTTPStatus := 0;
        Result.IsSuccess := False;
        Result.ResponseBody := E.Message;
      end;
    end;
  finally
    if hRequest <> nil then InternetCloseHandle(hRequest);
    if hConnect <> nil then InternetCloseHandle(hConnect);
    if hSession <> nil then InternetCloseHandle(hSession);
    ResponseStream.Free;
  end;
end;

function TEpostakClient.DoRequestWithRetry(const AMethod: TEpostakRequestMethod;
  const APath, ABody, AContentType: string; AIncludeAuth, AIncludeParticipant: Boolean;
  const AIdempotencyKey: string): TEpostakResult;
const
  MAX_RETRIES = 3;
  RETRYABLE_CODES: array[0..2] of Integer = (409, 429, 503);
var
  Attempt: Integer;
  IsRetryable: Boolean;
  i: Integer;
  DelayMs: Integer;
begin
  for Attempt := 1 to MAX_RETRIES do
  begin
    Result := DoRequestInternal(AMethod, APath, ABody, AContentType,
      AIncludeAuth, AIncludeParticipant, AIdempotencyKey);

    if Result.IsSuccess then Exit;

    { Skontrolujeme ci je to retryable chyba }
    IsRetryable := False;
    for i := 0 to High(RETRYABLE_CODES) do
      if Result.HTTPStatus = RETRYABLE_CODES[i] then
      begin
        IsRetryable := True;
        Break;
      end;

    if not IsRetryable then Exit;

    { Exponencialny backoff: 1s, 2s, 4s }
    if Attempt < MAX_RETRIES then
    begin
      DelayMs := (1 shl (Attempt - 1)) * 1000;
      Sleep(DelayMs);
    end;
  end;
end;

{ ----------------------------------------------------------------------------
  Auth
  ---------------------------------------------------------------------------- }

procedure TEpostakClient.EnsureToken;
begin
  if (FAccessToken = '') or (Now > FTokenExpiresAtUTC) then
  begin
    if FRefreshToken <> '' then
      RenewToken
    else
      Authenticate;
  end;
end;

procedure TEpostakClient.CheckResult(const R: TEpostakResult; const AContext: string);
var
  Msg: string;
begin
  if not R.IsSuccess then
  begin
    Msg := Format('Epostak [%s] HTTP %d'#13#10'%s', [AContext, R.HTTPStatus, R.ResponseBody]);
    if R.ErrorCode <> '' then
      Msg := Msg + #13#10'Kod: ' + R.ErrorCode;
    if R.ErrorMessage <> '' then
      Msg := Msg + #13#10'Sprava: ' + R.ErrorMessage;
    if R.RequestId <> '' then
      Msg := Msg + #13#10'RequestId: ' + R.RequestId;
    raise Exception.Create(Msg);
  end;
end;

function TEpostakClient.ConfigMatches(const ABaseURL, AClientId, AClientSecret,
  AParticipantId: string): Boolean;
begin
  Result := (FBaseURL = ABaseURL) and
            (FClientId = AClientId) and
            (FClientSecret = AClientSecret) and
            (FParticipantId = AParticipantId);
end;

procedure TEpostakClient.Authenticate;
var
  Body, Utf8Body: string;
  R: TEpostakResult;
  ExpiresIn: Integer;
begin
  if (FClientId = '') or (FClientSecret = '') then
    raise Exception.Create('Epostak: chyba client_id/client_secret.');

  Body := '{"grant_type":"client_credentials","client_id":"' + JSONEscape(FClientId) +
    '","client_secret":"' + JSONEscape(FClientSecret) + '"}';
  Utf8Body := UTF8FromAnsi(Body);

  R := DoRequestWithRetry(eqPOST, '/auth/token', Utf8Body, 'application/json; charset=utf-8',
    False, False, '');
  CheckResult(R, 'Authenticate');

  FAccessToken := ExtractJSONString(R.ResponseBody, 'access_token');
  FRefreshToken := ExtractJSONString(R.ResponseBody, 'refresh_token');
  if FAccessToken = '' then
    raise Exception.Create('Epostak: token sa nepodarilo ziskat: ' + R.ResponseBody);

  ExpiresIn := ExtractJSONInt(R.ResponseBody, 'expires_in', 900);
  { Obnovime token o minutu skor, nez realne expiruje (TTL je 900s = 15 min). }
  FTokenExpiresAtUTC := Now + ((ExpiresIn - 60) / 86400);
end;

procedure TEpostakClient.RenewToken;
var
  Body, Utf8Body: string;
  R: TEpostakResult;
  ExpiresIn: Integer;
  OldRefresh: string;
begin
  if FRefreshToken = '' then
  begin
    Authenticate;
    Exit;
  end;

  OldRefresh := FRefreshToken;
  Body := '{"grant_type":"refresh_token","refresh_token":"' + JSONEscape(FRefreshToken) + '"}';
  Utf8Body := UTF8FromAnsi(Body);

  R := DoRequestWithRetry(eqPOST, '/auth/renew', Utf8Body, 'application/json; charset=utf-8',
    False, False, '');

  if not R.IsSuccess then
  begin
    { Ak renew zlyha (napr. replay protection), fallback na full auth }
    FRefreshToken := '';
    Authenticate;
    Exit;
  end;

  FAccessToken := ExtractJSONString(R.ResponseBody, 'access_token');
  FRefreshToken := ExtractJSONString(R.ResponseBody, 'refresh_token');
  if FAccessToken = '' then
    raise Exception.Create('Epostak: renew nevratil token: ' + R.ResponseBody);

  ExpiresIn := ExtractJSONInt(R.ResponseBody, 'expires_in', 900);
  FTokenExpiresAtUTC := Now + ((ExpiresIn - 60) / 86400);
end;

procedure TEpostakClient.RevokeToken;
var
  Body, Utf8Body: string;
  R: TEpostakResult;
begin
  if FAccessToken = '' then Exit;

  Body := '{"token":"' + JSONEscape(FAccessToken) + '"}';
  Utf8Body := UTF8FromAnsi(Body);

  R := DoRequestInternal(eqPOST, '/auth/revoke', Utf8Body, 'application/json; charset=utf-8',
    False, False, '');
  { Idempotentne - vzdy 200 aj ked uz bol revoked }

  FAccessToken := '';
  FRefreshToken := '';
  FTokenExpiresAtUTC := 0;
end;

function TEpostakClient.TokenStatus: Boolean;
var
  R: TEpostakResult;
begin
  if FAccessToken = '' then
  begin
    Result := False;
    Exit;
  end;

  R := DoRequestInternal(eqGET, '/auth/token/status', '', '', True, False, '');
  Result := R.IsSuccess and (Pos('"valid":true', R.ResponseBody) > 0);
end;

{ ----------------------------------------------------------------------------
  Odosielanie
  ---------------------------------------------------------------------------- }

function TEpostakClient.SendInvoice(const ADocumentId, ADocumentTypeId, AProcessId,
  ASenderParticipantId, AReceiverParticipantId, AUblXml: string): string;
var
  Meta, Body, Utf8Body, IdemKey, NowUtc: string;
  R: TEpostakResult;
  SavedParticipant: string;
begin
  if Length(ADocumentId) > 255 then
    raise Exception.Create('Epostak: documentId nesmie presahovat 255 znakov (má ' +
      IntToStr(Length(ADocumentId)) + ')');

  EnsureToken;
  IdemKey := GenerateIdempotencyKey;
  NowUtc := GetUTCNowString;

  Meta := '{"documentId":"' + JSONEscape(ADocumentId) +
    '","documentTypeId":"' + JSONEscape(ADocumentTypeId) +
    '","processId":"' + JSONEscape(AProcessId) +
    '","senderParticipantId":"' + JSONEscape(ASenderParticipantId) +
    '","receiverParticipantId":"' + JSONEscape(AReceiverParticipantId) +
    '","creationDateTime":"' + NowUtc + '"}';

  Body := '{"metadata":' + Meta + ',"payload":"' + JSONEscape(AUblXml) +
    '","payloadFormat":"XML","payloadEncoding":"UTF-8"}';
  Utf8Body := UTF8FromAnsi(Body);

  { X-Peppol-Participant-Id pri /document/send musi byt odosielatel }
  SavedParticipant := FParticipantId;
  FParticipantId := ASenderParticipantId;
  try
    R := DoRequestWithRetry(eqPOST, '/document/send', Utf8Body, 'application/json; charset=utf-8',
      True, True, IdemKey);
  finally
    FParticipantId := SavedParticipant;
  end;

  if R.HTTPStatus = 409 then
  begin
    Result := '';  { kalkulovana prazdna hodnota signalizuje duplicate }
    Exit;
  end;
  CheckResult(R, 'SendInvoice');
  Result := ExtractJSONString(R.ResponseBody, 'providerDocumentId');
end;

{ ----------------------------------------------------------------------------
  Prijimanie
  ---------------------------------------------------------------------------- }

function TEpostakClient.ListReceived(const AStatus: string;
  ALimit: Integer; const APageToken: string): TEpostakDocumentListResult;
var
  R: TEpostakResult;
  Path, JSON, ArrayContent, ItemJSON: string;
  ArrayStart, ArrayEnd, P, ItemEnd, Count: Integer;
begin
  SetLength(Result.Documents, 0);
  Result.NextPageToken := '';
  EnsureToken;

  Path := '/document/receive?status=' + AStatus + '&limit=' + IntToStr(ALimit);
  if APageToken <> '' then
    Path := Path + '&pageToken=' + APageToken;

  R := DoRequestWithRetry(eqGET, Path, '', '', True, True, '');
  CheckResult(R, 'ListReceived');
  JSON := R.ResponseBody;

  ArrayStart := Pos('[', JSON);
  if ArrayStart = 0 then Exit;
  ArrayEnd := FindMatchingBracket(JSON, ArrayStart, '[', ']');
  if ArrayEnd = 0 then Exit;

  ArrayContent := Copy(JSON, ArrayStart + 1, ArrayEnd - ArrayStart - 1);

  Count := 0;
  P := 1;
  while P <= Length(ArrayContent) do
  begin
    if ArrayContent[P] = '{' then
    begin
      ItemEnd := FindMatchingBracket(ArrayContent, P, '{', '}');
      if ItemEnd = 0 then Break;
      ItemJSON := Copy(ArrayContent, P, ItemEnd - P + 1);

      SetLength(Result.Documents, Count + 1);
      Result.Documents[Count].DocumentId := ExtractJSONString(ItemJSON, 'documentId');
      Result.Documents[Count].DocumentTypeId := ExtractJSONString(ItemJSON, 'documentTypeId');
      Result.Documents[Count].ProcessId := ExtractJSONString(ItemJSON, 'processId');
      Result.Documents[Count].SenderParticipantId := ExtractJSONString(ItemJSON, 'senderParticipantId');
      Result.Documents[Count].ReceiverParticipantId := ExtractJSONString(ItemJSON, 'receiverParticipantId');
      Result.Documents[Count].CreationDateTime := ExtractJSONString(ItemJSON, 'creationDateTime');
      Inc(Count);

      P := ItemEnd + 1;
    end
    else
      Inc(P);
  end;

  { Extrahujeme nextPageToken z root JSONu }
  Result.NextPageToken := ExtractJSONString(JSON, 'nextPageToken');
end;

function TEpostakClient.GetDocumentXML(const ADocumentId: string): string;
var
  R: TEpostakResult;
begin
  EnsureToken;
  R := DoRequestWithRetry(eqGET, '/document/receive/' + ADocumentId, '', '', True, True, '');
  CheckResult(R, 'GetDocumentXML');
  { payload je uz UTF-8 na urovni bajtov (server ho tak posiela); JSONUnescape
    len odstranuje JSON-strukturalne escapovanie (\" -> '"', "\n" -> LF...) }
  Result := ExtractJSONString(R.ResponseBody, 'payload');
end;

procedure TEpostakClient.AcknowledgeDocument(const ADocumentId: string);
var
  R: TEpostakResult;
begin
  EnsureToken;
  R := DoRequestWithRetry(eqPOST, '/document/receive/' + ADocumentId + '/acknowledge',
    '', '', True, True, '');
  CheckResult(R, 'AcknowledgeDocument');
end;

end.
