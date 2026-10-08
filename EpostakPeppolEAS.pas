unit EpostakPeppolEAS;

interface

uses
  Windows, SysUtils, Classes, ADODB, ComObj, Variants;

const
  PEPPOL_EAS_INDEX_URL = 'https://docs.peppol.eu/edelivery/codelists/';
  PEPPOL_EAS_REFRESH_DAYS = 7;

function EnsurePeppolEASTable(AConn: TADOConnection): Boolean;
function UpdatePeppolEAS(AConn: TADOConnection; out AUpdatedCount: Integer; out ALastError: string): Boolean;
function PeppolEASNeedsUpdate(AConn: TADOConnection): Boolean;
function PeppolEASIsActive(AConn: TADOConnection; const ASchemeId: string): Boolean;

implementation

function SQLQuote(const S: string): string;
begin
  Result := '''' + StringReplace(S, '''', '''''', [rfReplaceAll]) + '''';
end;

function GetLatestEASUrl: string;
begin
  Result := 'https://docs.peppol.eu/edelivery/codelists/v9.7/' +
    'Peppol%20Code%20Lists%20-%20Participant%20identifier%20schemes%20v9.7.xml';
end;

function DownloadFile(const AUrl, AFileName: string): Boolean;
var
  HTTP:    OleVariant;
  Body:    OleVariant;
  DataPtr: Pointer;
  DataLen: Integer;
  FS:      TFileStream;
begin
  Result := False;
  if Trim(AUrl) = '' then Exit;
  try
    HTTP := CreateOleObject('MSXML2.ServerXMLHTTP.6.0');
    HTTP.open('GET', AUrl, False);
    HTTP.setOption(2, 13056);
    HTTP.send(EmptyParam);
    if HTTP.status <> 200 then Exit;
    Body    := HTTP.responseBody;
    DataLen := VarArrayHighBound(Body, 1) - VarArrayLowBound(Body, 1) + 1;
    DataPtr := VarArrayLock(Body);
    try
      FS := TFileStream.Create(AFileName, fmCreate);
      try
        FS.WriteBuffer(DataPtr^, DataLen);
      finally
        FS.Free;
      end;
    finally
      VarArrayUnlock(Body);
    end;
    Result := True;
  except
    Result := False;
  end;
end;



function NodeValueByColumn(ARow: OleVariant; const AColumnRef: string): string;
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

function TableExists(AConn: TADOConnection): Boolean;
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
    Result := not Q.Eof;
  finally
    Q.Free;
  end;
end;

function EnsurePeppolEASTable(AConn: TADOConnection): Boolean;
var
  Q: TADOQuery;
begin
  Result := False;
  if (AConn = nil) or not AConn.Connected then Exit;

  if TableExists(AConn) then
  begin
    Result := True;
    Exit;
  end;

  Q := TADOQuery.Create(nil);
  try
    Q.Connection := AConn;
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
    Result := True;
  finally
    Q.Free;
  end;
end;

function ParseISODate(const AValue: string; out ADate: TDateTime): Boolean;
var
  S: string;
  Y, M, D: Word;
begin
  Result := False;
  ADate := 0;
  S := Trim(AValue);
  if Length(S) <> 10 then Exit;
  if (S[5] <> '-') or (S[8] <> '-') then Exit;
  try
    Y := StrToInt(Copy(S, 1, 4));
    M := StrToInt(Copy(S, 6, 2));
    D := StrToInt(Copy(S, 9, 2));
    ADate := EncodeDate(Y, M, D);
    Result := True;
  except
    Result := False;
  end;
end;

function DateSQLLiteral(const AValue: string): string;
var
  D: TDateTime;
begin
  if Trim(AValue) = '' then
  begin
    Result := 'NULL';
    Exit;
  end;
  if not ParseISODate(AValue, D) then
    raise Exception.CreateFmt('Invalid Peppol EAS removal date: %s', [AValue]);
  Result := 'DATE ' + SQLQuote(FormatDateTime('yyyy-mm-dd', D));
end;

function UpdatePeppolEAS(AConn: TADOConnection; out AUpdatedCount: Integer; out ALastError: string): Boolean;
var
  TempFile, SourceUrl, SourceVersion: string;
  XML, Rows, Row, Root, FirstChild: OleVariant;
  I: Integer;
  SchemeId, Country, SchemeName, State, RemovalDate: string;
  Q: TADOQuery;
begin
  Result := False;
  AUpdatedCount := 0;
  ALastError := '';

  if (AConn = nil) or not AConn.Connected then begin ALastError := 'DB not connected'; Exit; end;
  if not TableExists(AConn) then begin ALastError := 'PEPPOL_EAS table not found'; Exit; end;

  SourceUrl := GetLatestEASUrl;
  TempFile := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) +
    Format('peppol-eas-%d.xml', [GetTickCount]);

  if not DownloadFile(SourceUrl, TempFile) then begin ALastError := 'Download failed: ' + SourceUrl; Exit; end;
  try
    XML := CreateOleObject('MSXML2.DOMDocument.6.0');
    XML.async := False;
    XML.validateOnParse := False;
    XML.resolveExternals := False;
    if not XML.load(TempFile) then begin ALastError := 'XML load failed: ' + VarToStr(XML.parseError.reason); Exit; end;

    Root := XML.documentElement;
    if VarIsNull(Root) or VarIsEmpty(Root) then begin ALastError := 'XML root element is null'; Exit; end;

    // Root is "participant-identifier-schemes", direct children are the scheme entries
    Rows := Root.childNodes;
    if Rows.length = 0 then
    begin
      ALastError := 'No child elements found under root: ' + VarToStr(Root.nodeName);
      Exit;
    end;
    // Log first child for structure diagnosis
    FirstChild := Rows.item(0);
    ALastError := 'First child: ' + VarToStr(FirstChild.nodeName) +
                  ' attrs: ' + VarToStr(FirstChild.xml);
    Exit; // temporary - remove after diagnosis

    SourceVersion := Trim(VarToStr(Root.getAttribute('version')));
    if SourceVersion = '' then SourceVersion := '9.7';

    Q := TADOQuery.Create(nil);
    try
      Q.Connection := AConn;
      AConn.BeginTrans;
      try
        Q.SQL.Text := 'DELETE FROM PEPPOL_EAS';
        Q.ExecSQL;

        for I := 0 to Rows.length - 1 do
        begin
          Row := Rows.item(I);
          SchemeId := Trim(NodeValueByColumn(Row, 'iso6523'));
          if SchemeId = '' then Continue;

          Country := Trim(NodeValueByColumn(Row, 'country'));
          SchemeName := Trim(NodeValueByColumn(Row, 'scheme-name'));
          State := Trim(NodeValueByColumn(Row, 'state'));
          RemovalDate := Trim(NodeValueByColumn(Row, 'removal-date'));

          Q.Close;
          Q.SQL.Text :=
            'INSERT INTO PEPPOL_EAS ' +
            '(SCHEME_ID,COUNTRY_CODE,SCHEME_NAME,STATE,REMOVAL_DATE,SOURCE_VERSION,UPDATED_AT) VALUES (' +
            SQLQuote(SchemeId) + ',' +
            SQLQuote(Country) + ',' +
            SQLQuote(SchemeName) + ',' +
            SQLQuote(State) + ',' +
            DateSQLLiteral(RemovalDate) + ',' +
            SQLQuote(SourceVersion) + ',CURRENT_TIMESTAMP)';
          Q.ExecSQL;
          Inc(AUpdatedCount);
        end;

        if AUpdatedCount = 0 then
          raise Exception.Create('Peppol EAS XML contained no usable participant schemes.');

        AConn.CommitTrans;
        Result := True;
      except
        AConn.RollbackTrans;
        raise;
      end;
    finally
      Q.Free;
    end;
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
  if not TableExists(AConn) then Exit;

  Q := TADOQuery.Create(nil);
  try
    Q.Connection := AConn;
    Q.SQL.Text := 'SELECT MAX(UPDATED_AT) AS LAST_UPDATE FROM PEPPOL_EAS';
    Q.Open;
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
    Q.Open;
    if Q.Eof then Exit;

    Result := SameText(Trim(Q.FieldByName('STATE').AsString), 'active') and
      (Q.FieldByName('REMOVAL_DATE').IsNull or
       (Q.FieldByName('REMOVAL_DATE').AsDateTime >= Date));
  finally
    Q.Free;
  end;
end;

end.
