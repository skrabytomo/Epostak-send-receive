unit EpostakPeppolEAS;

interface

uses
  Windows, SysUtils, StrUtils, Classes, ADODB, WinInet, ComObj;

const
  PEPPOL_EAS_INDEX_URL   = 'https://docs.peppol.eu/edelivery/codelists/';
  PEPPOL_EAS_REFRESH_DAYS = 7;

function EnsurePeppolEASTable(AConn: TADOConnection): Boolean;
function UpdatePeppolEAS(AConn: TADOConnection; out AUpdatedCount: Integer): Boolean;
function PeppolEASNeedsUpdate(AConn: TADOConnection): Boolean;
function PeppolEASIsActive(AConn: TADOConnection; const ASchemeId: string): Boolean;

implementation

function SQLQuote(const S: string): string;
begin
  Result := '''' + StringReplace(S, '''', '''''', [rfReplaceAll]) + '''';
end;

function GetLatestEASUrl: string;
begin
  // Direct URL to Peppol EAS codelist XML v9.7 (2026-07-02)
  // Update this constant when OpenPeppol releases a new version
  Result := 'https://docs.peppol.eu/edelivery/codelists/v9.7/' +
    'Peppol%20Code%20Lists%20-%20Participant%20identifier%20schemes%20v9.7.xml';
end;

function DownloadTextFile(const AUrl, AFileName: string): Boolean;
var
  HInet, HUrl: HINTERNET;
  Buf: array[0..4095] of Byte;
  ReadBytes: DWORD;
  FS: TFileStream;
begin
  Result := False;
  HInet := InternetOpen('EpostakPeppolEAS/1.0', INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  if HInet = nil then Exit;
  try
    HUrl := InternetOpenUrl(HInet, PChar(AUrl), nil, 0,
      INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE, 0);
    if HUrl = nil then Exit;
    try
      FS := TFileStream.Create(AFileName, fmCreate);
      try
        repeat
          ReadBytes := 0;
          if not InternetReadFile(HUrl, @Buf[0], SizeOf(Buf), ReadBytes) then Exit;
          if ReadBytes > 0 then FS.WriteBuffer(Buf[0], ReadBytes);
        until ReadBytes = 0;
        Result := True;
      finally
        FS.Free;
      end;
    finally
      InternetCloseHandle(HUrl);
    end;
  finally
    InternetCloseHandle(HInet);
  end;
end;

function NodeValueByColumn(ARow: OleVariant; const AColumnRef: string): WideString;
var
  Nodes, N: OleVariant;
  I: Integer;
  Ref: string;
begin
  Result := '';
  Nodes := ARow.selectNodes('./*[local-name()="Value"]');
  for I := 0 to Nodes.length - 1 do
  begin
    N := Nodes.item(I);
    Ref := VarToStr(N.getAttribute('ColumnRef'));
    if SameText(Ref, AColumnRef) then
    begin
      Result := VarToStr(N.selectSingleNode('./*[local-name()="SimpleValue"]').text);
      Exit;
    end;
  end;
end;

function EnsurePeppolEASTable(AConn: TADOConnection): Boolean;
var
  Q: TADOQuery;
begin
  Result := False;
  if (AConn = nil) or not AConn.Connected then Exit;
  Q := TADOQuery.Create(nil);
  try
    Q.Connection := AConn;
    Q.SQL.Text :=
      'SELECT RDB$RELATION_NAME FROM RDB$RELATIONS ' +
      'WHERE RDB$RELATION_NAME = ''PEPPOL_EAS''';
    Q.Open;
    if Q.Eof then
    begin
      Q.Close;
      Q.SQL.Text :=
        'CREATE TABLE PEPPOL_EAS (' +
        'SCHEME_ID VARCHAR(10) NOT NULL,' +
        'COUNTRY_CODE VARCHAR(20),' +
        'SCHEME_NAME VARCHAR(250),' +
        'STATE VARCHAR(30),' +
        'REMOVAL_DATE DATE,' +
        'SOURCE_VERSION VARCHAR(20),' +
        'UPDATED_AT TIMESTAMP,' +
        'CONSTRAINT PK_PEPPOL_EAS PRIMARY KEY (SCHEME_ID))';
      Q.ExecSQL;
    end;
    Result := True;
  finally
    Q.Free;
  end;
end;

function UpdatePeppolEAS(AConn: TADOConnection; out AUpdatedCount: Integer): Boolean;
var
  TempFile, SourceUrl, SourceVersion: string;
  XML, Rows, Row, N: OleVariant;
  I: Integer;
  SchemeId, Country, SchemeName, State, RemovalDate: string;
  Q: TADOQuery;
begin
  Result := False;
  AUpdatedCount := 0;

  // Only update if table exists — do NOT create it here
  Q := TADOQuery.Create(nil);
  try
    Q.Connection := AConn;
    Q.SQL.Text :=
      'SELECT RDB$RELATION_NAME FROM RDB$RELATIONS ' +
      'WHERE RDB$RELATION_NAME = ''PEPPOL_EAS''';
    Q.Open;
    if Q.Eof then
    begin
      // Table doesn't exist — skip silently
      Exit;
    end;
  finally
    Q.Free;
  end;

  SourceUrl := GetLatestEASUrl;
  if SourceUrl = '' then Exit;

  TempFile := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) + 'peppol-eas.xml';
  if not DownloadTextFile(SourceUrl, TempFile) then Exit;

  try
    XML := CreateOleObject('MSXML2.DOMDocument.6.0');
    XML.async := False;
    XML.validateOnParse := False;
    if not XML.load(TempFile) then Exit;

    SourceVersion := VarToStr(XML.documentElement.getAttribute('version'));
    if SourceVersion = '' then SourceVersion := 'current';

    Rows := XML.selectNodes('//*[local-name()="Row"]');
    if Rows.length = 0 then Exit;

    Q := TADOQuery.Create(nil);
    try
      Q.Connection := AConn;
      AConn.BeginTrans;
      try
        for I := 0 to Rows.length - 1 do
        begin
          Row := Rows.item(I);
          SchemeId    := Trim(NodeValueByColumn(Row, 'iso6523'));
          if SchemeId = '' then Continue;
          Country     := Trim(NodeValueByColumn(Row, 'country'));
          SchemeName  := Trim(NodeValueByColumn(Row, 'scheme-name'));
          State       := Trim(NodeValueByColumn(Row, 'state'));
          RemovalDate := Trim(NodeValueByColumn(Row, 'removal-date'));

          Q.Close;
          Q.SQL.Text :=
            'UPDATE PEPPOL_EAS SET ' +
            'COUNTRY_CODE='     + SQLQuote(Country)      + ',' +
            'SCHEME_NAME='      + SQLQuote(SchemeName)   + ',' +
            'STATE='            + SQLQuote(State)         + ',' +
            'REMOVAL_DATE='     + IfThen(RemovalDate = '', 'NULL', SQLQuote(RemovalDate)) + ',' +
            'SOURCE_VERSION='   + SQLQuote(SourceVersion) + ',' +
            'UPDATED_AT=CURRENT_TIMESTAMP ' +
            'WHERE SCHEME_ID='  + SQLQuote(SchemeId);
          Q.ExecSQL;

          N := Q.RowsAffected;
          if N = 0 then
          begin
            Q.Close;
            Q.SQL.Text :=
              'INSERT INTO PEPPOL_EAS ' +
              '(SCHEME_ID,COUNTRY_CODE,SCHEME_NAME,STATE,REMOVAL_DATE,SOURCE_VERSION,UPDATED_AT) VALUES (' +
              SQLQuote(SchemeId)    + ',' +
              SQLQuote(Country)     + ',' +
              SQLQuote(SchemeName)  + ',' +
              SQLQuote(State)       + ',' +
              IfThen(RemovalDate = '', 'NULL', SQLQuote(RemovalDate)) + ',' +
              SQLQuote(SourceVersion) + ',CURRENT_TIMESTAMP)';
            Q.ExecSQL;
          end;
          Inc(AUpdatedCount);
        end;
        AConn.CommitTrans;
      except
        AConn.RollbackTrans;
        raise;
      end;
    finally
      Q.Free;
    end;
    Result := True;
  finally
    DeleteFile(TempFile);
  end;
end;

function PeppolEASNeedsUpdate(AConn: TADOConnection): Boolean;
var
  Q: TADOQuery;
  D: TDateTime;
begin
  Result := True;
  if (AConn = nil) or not AConn.Connected then Exit;
  Q := TADOQuery.Create(nil);
  try
    Q.Connection := AConn;
    Q.SQL.Text := 'SELECT MAX(UPDATED_AT) AS LAST_UPDATE FROM PEPPOL_EAS';
    try
      Q.Open;
    except
      Exit; // table doesn't exist
    end;
    if Q.Eof or Q.FieldByName('LAST_UPDATE').IsNull then Exit;
    D := Q.FieldByName('LAST_UPDATE').AsDateTime;
    Result := (Now - D) >= PEPPOL_EAS_REFRESH_DAYS;
  finally
    Q.Free;
  end;
end;

function PeppolEASIsActive(AConn: TADOConnection; const ASchemeId: string): Boolean;
var
  Q: TADOQuery;
begin
  Result := False;
  if (AConn = nil) or not AConn.Connected then Exit;
  Q := TADOQuery.Create(nil);
  try
    Q.Connection := AConn;
    Q.SQL.Text :=
      'SELECT STATE, REMOVAL_DATE FROM PEPPOL_EAS WHERE SCHEME_ID=' +
      SQLQuote(Trim(ASchemeId));
    try
      Q.Open;
    except
      Exit;
    end;
    if Q.Eof then Exit;
    Result := SameText(Trim(Q.FieldByName('STATE').AsString), 'active') and
              (Q.FieldByName('REMOVAL_DATE').IsNull or
               (Q.FieldByName('REMOVAL_DATE').AsDateTime > Date));
  finally
    Q.Free;
  end;
end;

end.
