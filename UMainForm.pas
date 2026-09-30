unit UMainForm;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  StdCtrls, ComCtrls, ExtCtrls, IniFiles, FileCtrl, DB, ADODB,
  EpostakClient, EpostakDemoCreds, EpostakPeppolEAS;

type
  TFARiadok = record
    PCRiadku:   Integer;
    Text:       string;
    Mnozstvo:   Double;
    MJ:         string;
    CenaJedn:   Double;
    CenaBezDPH: Double;
    DPHSadzba:  Double;
    DPHSuma:    Double;
    CenaCelkom: Double;
  end;

  TDPHSubtotal = record
    Sadzba:    Double;
    ZakladBez: Double;
    SumaDPH:   Double;
  end;

  TFormMain = class(TForm)
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    Label6: TLabel;
    Label7: TLabel;
    Label8: TLabel;
    edtBaseURL: TEdit;
    edtParticipantId: TEdit;
    edtClientId: TEdit;
    edtClientSecret: TEdit;
    btnSaveConfig: TButton;
    btnUseFirmA: TButton;
    btnUseFirmB: TButton;
    edtXMLFile: TEdit;
    btnBrowseXML: TButton;
    edtReceiverId: TEdit;
    btnSend: TButton;
    lvInbox: TListView;
    edtSaveFolder: TEdit;
    btnBrowseFolder: TButton;
    btnCheckInbox: TButton;
    btnDownloadSelected: TButton;
    btnAcknowledgeSelected: TButton;
    memLog: TMemo;
    dlgOpenXML: TOpenDialog;
    // InTime DB controls
    lblDBConn: TLabel;
    btnConnectDB: TButton;
    lblIDSpolLic: TLabel;
    cmbSpolLic: TComboBox;
    btnLoadInvoices: TButton;
    lvInvoices: TListView;
    btnLoadFromDB: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnSaveConfigClick(Sender: TObject);
    procedure btnUseFirmAClick(Sender: TObject);
    procedure btnUseFirmBClick(Sender: TObject);
    procedure btnBrowseXMLClick(Sender: TObject);
    procedure btnSendClick(Sender: TObject);
    procedure btnBrowseFolderClick(Sender: TObject);
    procedure btnCheckInboxClick(Sender: TObject);
    procedure btnDownloadSelectedClick(Sender: TObject);
    procedure btnAcknowledgeSelectedClick(Sender: TObject);
    procedure btnUseSandboxClick(Sender: TObject);
    procedure btnUseProductionClick(Sender: TObject);
    procedure btnConnectDBClick(Sender: TObject);
    procedure btnLoadInvoicesClick(Sender: TObject);
    procedure btnLoadFromDBClick(Sender: TObject);
  private
    FClient:     TEpostakClient;
    FInboxItems: TEpostakDocumentListResult;
    FDBConn:     TADOConnection;
    FLastXML:    string;
    function  ConfigFileName: string;
    procedure Log(const AMsg: string);
    function  MakeClient: TEpostakClient;
    function  LoadRawBytesFromFile(const AFileName: string): string;
    procedure RefreshInboxList;
    function  GetSelectedDocId: string;
    function  GetSelectedDocIds: TStringList;
    procedure SetupColumns;
    function  FormatISODateTime(const AISO: string): string;
    function  ShortDocType(const AFullType: string): string;
    // InTime DB
    procedure ConnectDB;
    function  DBQuery(const ASQL: string): TADOQuery;
    function  XMLEscape(const S: string): string;
    function  MJToUnitCode(const MJ: string): string;
    function  DPHTaxCategory(const Sadzba: Double): string;
    function  F2(const V: Double): string;
    function  F4(const V: Double): string;
    function  NewGUID: string;
    function  GenerujUBLInvoice(AIDDokladu: Integer; AIDSpolLic: Integer; const ASupplierParticipantId, AReceiverParticipantId: string): string;
  end;

var
  FormMain: TFormMain;

const
  DOC_TYPE_ID = 'urn:oasis:names:specification:ubl:schema:xsd:Invoice-2::Invoice' +
    '##urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0::2.1';
  PROCESS_ID  = 'urn:fdc:peppol.eu:2017:poacc:billing:01:1.0';

implementation

{$R *.dfm}

// ============================================================================
// HELPERS
// ============================================================================

function TFormMain.XMLEscape(const S: string): string;
begin
  Result := S;
  Result := StringReplace(Result, '&',  '&amp;',  [rfReplaceAll]);
  Result := StringReplace(Result, '<',  '&lt;',   [rfReplaceAll]);
  Result := StringReplace(Result, '>',  '&gt;',   [rfReplaceAll]);
  Result := StringReplace(Result, '"',  '&quot;', [rfReplaceAll]);
  Result := StringReplace(Result, '''', '&apos;', [rfReplaceAll]);
end;

function TFormMain.MJToUnitCode(const MJ: string): string;
var M: string;
begin
  M := LowerCase(Trim(MJ));
  if      M = 'ks'  then Result := 'H87'
  else if M = 'hod' then Result := 'HUR'
  else if M = 'h'   then Result := 'HUR'
  else if M = 'nh'  then Result := 'HUR'
  else if M = 'm'   then Result := 'MTR'
  else if M = 'm2'  then Result := 'MTK'
  else if M = 'm3'  then Result := 'MTQ'
  else if M = 'kg'  then Result := 'KGM'
  else if M = 'km'  then Result := 'KMT'
  else if M = 'l'   then Result := 'LTR'
  else if M = 't'   then Result := 'TNE'
  else                    Result := 'C62';
end;

function TFormMain.DPHTaxCategory(const Sadzba: Double): string;
begin
  if Sadzba = 0 then Result := 'Z' else Result := 'S';
end;

function TFormMain.F2(const V: Double): string;
begin
  // Peppol/UBL xs:decimal requires a dot as decimal separator.
  Result := FloatToStrF(V, ffFixed, 10, 2);
  Result := StringReplace(Result, DecimalSeparator, '.', [rfReplaceAll]);
end;

function TFormMain.F4(const V: Double): string;
begin
  // Peppol/UBL xs:decimal requires a dot as decimal separator.
  Result := FloatToStrF(V, ffFixed, 10, 4);
  Result := StringReplace(Result, DecimalSeparator, '.', [rfReplaceAll]);
end;

function TFormMain.NewGUID: string;
var G: TGUID;
begin
  CreateGUID(G);
  Result := Copy(GUIDToString(G), 2, 36);
end;

function TFormMain.ConfigFileName: string;
begin
  Result := ChangeFileExt(Application.ExeName, '.ini');
end;

procedure TFormMain.Log(const AMsg: string);
begin
  memLog.Lines.Add(AMsg);
  memLog.SelStart := Length(memLog.Text);
  SendMessage(memLog.Handle, EM_SCROLLCARET, 0, 0);
  Application.ProcessMessages;
end;

function TFormMain.LoadRawBytesFromFile(const AFileName: string): string;
var
  FS: TFileStream;
  BOMSize: Integer;
begin
  Result := '';
  FS := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    if FS.Size > 0 then
    begin
      SetLength(Result, FS.Size);
      FS.ReadBuffer(Result[1], FS.Size);
      BOMSize := 0;
      if (Length(Result) >= 3) and
         (Ord(Result[1]) = $EF) and (Ord(Result[2]) = $BB) and (Ord(Result[3]) = $BF) then
        BOMSize := 3;
      if BOMSize > 0 then Delete(Result, 1, BOMSize);
    end;
  finally
    FS.Free;
  end;
end;

function TFormMain.FormatISODateTime(const AISO: string): string;
var DT: TDateTime;
begin
  try
    DT := EncodeDate(
      StrToIntDef(Copy(AISO, 1, 4), 2026),
      StrToIntDef(Copy(AISO, 6, 2), 1),
      StrToIntDef(Copy(AISO, 9, 2), 1)) +
      EncodeTime(
      StrToIntDef(Copy(AISO, 12, 2), 0),
      StrToIntDef(Copy(AISO, 15, 2), 0),
      StrToIntDef(Copy(AISO, 18, 2), 0), 0);
    Result := FormatDateTime('dd.mm.yyyy hh:nn', DT);
  except
    Result := AISO;
  end;
end;

function TFormMain.ShortDocType(const AFullType: string): string;
var P: Integer;
begin
  Result := AFullType;
  P := Pos('::', Result);
  if P > 0 then
  begin
    Result := Copy(Result, P + 2, MaxInt);
    P := Pos('##', Result);
    if P > 0 then Result := Copy(Result, 1, P - 1);
  end;
  if Result = '' then Result := AFullType;
end;

procedure TFormMain.SetupColumns;
begin
  // Inbox columns
  lvInbox.ViewStyle := vsReport;
  lvInbox.Columns.Clear;
  with lvInbox.Columns.Add do begin Caption := '#';               Width := 30;  end;
  with lvInbox.Columns.Add do begin Caption := 'Cislo dokumentu'; Width := 180; end;
  with lvInbox.Columns.Add do begin Caption := 'Odosielatel';     Width := 130; end;
  with lvInbox.Columns.Add do begin Caption := 'Prijemca';        Width := 130; end;
  with lvInbox.Columns.Add do begin Caption := 'Typ';             Width := 80;  end;
  with lvInbox.Columns.Add do begin Caption := 'Vytvorene';       Width := 120; end;
  with lvInbox.Columns.Add do begin Caption := 'Stav';            Width := 90;  end;

  // Invoice grid columns
  lvInvoices.ViewStyle := vsReport;
  lvInvoices.Columns.Clear;
  with lvInvoices.Columns.Add do begin Caption := 'Cislo FA';     Width := 70;  end;
  with lvInvoices.Columns.Add do begin Caption := 'Datum';        Width := 90;  end;
  with lvInvoices.Columns.Add do begin Caption := 'Splatnost';    Width := 90;  end;
  with lvInvoices.Columns.Add do begin Caption := 'Odberatel';    Width := 280; end;
  with lvInvoices.Columns.Add do begin Caption := 'Suma';         Width := 100; end;
  with lvInvoices.Columns.Add do begin Caption := 'Uhradena';     Width := 70;  end;
end;

procedure TFormMain.RefreshInboxList;
var i: Integer; Item: TListItem;
begin
  lvInbox.Items.Clear;
  for i := 0 to High(FInboxItems.Documents) do
  begin
    Item := lvInbox.Items.Add;
    Item.Caption := IntToStr(i + 1);
    Item.SubItems.Add(FInboxItems.Documents[i].DocumentId);
    Item.SubItems.Add(FInboxItems.Documents[i].SenderParticipantId);
    Item.SubItems.Add(FInboxItems.Documents[i].ReceiverParticipantId);
    Item.SubItems.Add(ShortDocType(FInboxItems.Documents[i].DocumentTypeId));
    Item.SubItems.Add(FormatISODateTime(FInboxItems.Documents[i].CreationDateTime));
    Item.SubItems.Add('RECEIVED');
  end;
end;

function TFormMain.GetSelectedDocId: string;
begin
  Result := '';
  if lvInbox.Selected <> nil then
    Result := lvInbox.Selected.SubItems[0];
end;

function TFormMain.GetSelectedDocIds: TStringList;
var i: Integer;
begin
  Result := TStringList.Create;
  for i := 0 to lvInbox.Items.Count - 1 do
    if lvInbox.Items[i].Selected then
      Result.Add(lvInbox.Items[i].SubItems[0]);
end;

function TFormMain.MakeClient: TEpostakClient;
var NeedNew: Boolean;
begin
  if (edtClientId.Text = '') or (edtClientSecret.Text = '') then
    raise Exception.Create('Vyplnte ClientId a ClientSecret.');
  if edtParticipantId.Text = '' then
    raise Exception.Create('Vyplnte Participant Id.');
  NeedNew := True;
  if FClient <> nil then
  begin
    NeedNew := not FClient.ConfigMatches(edtBaseURL.Text, edtClientId.Text,
      edtClientSecret.Text, edtParticipantId.Text);
    if NeedNew then begin FClient.Free; FClient := nil; end;
  end;
  if FClient = nil then
  begin
    FClient := TEpostakClient.Create(edtBaseURL.Text, edtClientId.Text,
      edtClientSecret.Text, edtParticipantId.Text);
    Log('Novy klient vytvoreny.');
  end;
  Result := FClient;
end;

// ============================================================================
// INTIME DB
// ============================================================================

function TFormMain.DBQuery(const ASQL: string): TADOQuery;
begin
  if (FDBConn = nil) or not FDBConn.Connected then
    raise Exception.Create('Nie ste pripojeny k InTime databaze.');
  Result := TADOQuery.Create(nil);
  Result.Connection := FDBConn;
  Result.SQL.Text := ASQL;
  Result.Open;
end;

function TFormMain.GenerujUBLInvoice(AIDDokladu: Integer; AIDSpolLic: Integer; const ASupplierParticipantId, AReceiverParticipantId: string): string;
var
  SB:        TStringList;
  Q:         TADOQuery;
  Riadky:    array of TFARiadok;
  DPHGroups: array of TDPHSubtotal;
  i, Count:  Integer;
  CisloDokladu:    Integer;
  DatumDokladu:    TDateTime;
  DatumSplatnosti: TDateTime;
  Mena:            string;
  VarSymbol:       string;
  CenaBezDPH:      Double;
  DPHSuma:         Double;
  CenaCelkom:      Double;
  SupNazov, SupUlica, SupMesto, SupPSC, SupICO, SupDIC, SupIBAN: string;
  SupplierParticipantScheme, SupplierParticipantValue: string;
  ReceiverParticipantScheme, ReceiverParticipantValue: string;
  P: Integer;
  CusNazov, CusUlica, CusMesto, CusPSC, CusICO, CusDIC:          string;

  procedure A(const S: string);
  begin SB.Add(S); end;

begin
  Result := '';

  SupplierParticipantValue := Trim(ASupplierParticipantId);
  P := Pos(':', SupplierParticipantValue);
  if P <= 1 then
    raise Exception.Create('Neplatny Supplier Participant ID: ' + ASupplierParticipantId);
  SupplierParticipantScheme := Copy(SupplierParticipantValue, 1, P - 1);
  Delete(SupplierParticipantValue, 1, P);
  SupplierParticipantValue := Trim(SupplierParticipantValue);
  if SupplierParticipantValue = '' then
    raise Exception.Create('Neplatny Supplier Participant ID: ' + ASupplierParticipantId);

  if (FDBConn <> nil) and FDBConn.Connected then
  begin
    EnsurePeppolEASTable(FDBConn);
    if not PeppolEASIsActive(FDBConn, SupplierParticipantScheme) then
      raise Exception.Create('Neplatne alebo neaktivne Supplier schemeID: ' + SupplierParticipantScheme);
  end;

  ReceiverParticipantValue := Trim(AReceiverParticipantId);
  P := Pos(':', ReceiverParticipantValue);
  if P <= 1 then
    raise Exception.Create('Neplatny Receiver Participant ID: ' + AReceiverParticipantId);
  ReceiverParticipantScheme := Copy(ReceiverParticipantValue, 1, P - 1);
  Delete(ReceiverParticipantValue, 1, P);
  ReceiverParticipantValue := Trim(ReceiverParticipantValue);
  if ReceiverParticipantValue = '' then
    raise Exception.Create('Neplatny Receiver Participant ID: ' + AReceiverParticipantId);

  if (FDBConn <> nil) and FDBConn.Connected then
    if not PeppolEASIsActive(FDBConn, ReceiverParticipantScheme) then
      raise Exception.Create('Neplatne alebo neaktivne Receiver schemeID: ' + ReceiverParticipantScheme);

  SB := TStringList.Create;
  try
    // --- HLAVICKA + CUSTOMER ---
    Q := DBQuery(
      'SELECT h.CISLO_DOKLADU, h.DATUM_DOKLADU, h.DATUM_SPLATNOSTI, ' +
      'h.CENA_BEZ_DPH, h.DPH_SUMA, h.CENA_CELKOM, h.MENA, h.VAR_SYMBOL, ' +
      'f.NAZOV_SPOLOCNOSTI, f.ULICA, f.MESTO, f.PSC, f.ICO, f.DIC ' +
      'FROM EVID_FA_HLAVICKA h ' +
      'JOIN FIRMY f ON f.ID = h.ID_FIRMY ' +
      'WHERE h.ID_DOKLADU = ' + IntToStr(AIDDokladu) +
      ' AND h.ID_SPOL_LIC = ' + IntToStr(AIDSpolLic));
    try
      if Q.Eof then begin Log('CHYBA: Faktura nenajdena.'); Exit; end;
      CisloDokladu    := Q.FieldByName('CISLO_DOKLADU').AsInteger;
      DatumDokladu    := Q.FieldByName('DATUM_DOKLADU').AsDateTime;
      DatumSplatnosti := Q.FieldByName('DATUM_SPLATNOSTI').AsDateTime;
      CenaBezDPH      := Q.FieldByName('CENA_BEZ_DPH').AsFloat;
      DPHSuma         := Q.FieldByName('DPH_SUMA').AsFloat;
      CenaCelkom      := Q.FieldByName('CENA_CELKOM').AsFloat;
      Mena            := Trim(Q.FieldByName('MENA').AsString);
      VarSymbol       := Trim(Q.FieldByName('VAR_SYMBOL').AsString);
      CusNazov        := Trim(Q.FieldByName('NAZOV_SPOLOCNOSTI').AsString);
      CusUlica        := Trim(Q.FieldByName('ULICA').AsString);
      CusMesto        := Trim(Q.FieldByName('MESTO').AsString);
      CusPSC          := Trim(Q.FieldByName('PSC').AsString);
      CusICO          := Trim(Q.FieldByName('ICO').AsString);
      CusDIC          := Trim(Q.FieldByName('DIC').AsString);
    finally Q.Free; end;

    // --- SUPPLIER ---
    Q := DBQuery(
      'SELECT NAZOV_SPOLOCNOSTI, ULICA, MESTO, PSC, ICO, DIC, CISLO_UCTU ' +
      'FROM GLB_LICENCIE WHERE ID_SPOLOCNOSTI = ' + IntToStr(AIDSpolLic));
    try
      if Q.Eof then begin Log('CHYBA: GLB_LICENCIE nenajdene.'); Exit; end;
      SupNazov := Trim(Q.FieldByName('NAZOV_SPOLOCNOSTI').AsString);
      SupUlica := Trim(Q.FieldByName('ULICA').AsString);
      SupMesto := Trim(Q.FieldByName('MESTO').AsString);
      SupPSC   := Trim(Q.FieldByName('PSC').AsString);
      SupICO   := Trim(Q.FieldByName('ICO').AsString);
      SupDIC   := Trim(Q.FieldByName('DIC').AsString);
      SupIBAN  := StringReplace(Trim(Q.FieldByName('CISLO_UCTU').AsString), ' ', '', [rfReplaceAll]);
    finally Q.Free; end;

    // --- LOAD RIADKY ---
    Q := DBQuery(
      'SELECT PC_RIADKU, TEXT, MNOZSTVO, MJ, CENA_JEDN, ' +
      'CENA_BEZ_DPH, DPH_SADZBA, DPH_SUMA, CENA_CELKOM ' +
      'FROM EVID_FA_RIADKY ' +
      'WHERE ID_DOKLADU = ' + IntToStr(AIDDokladu) +
      ' AND ID_SPOL_LIC = ' + IntToStr(AIDSpolLic) +
      ' ORDER BY PC_RIADKU');
    try
      Count := 0;
      while not Q.Eof do
      begin
        SetLength(Riadky, Count + 1);
        Riadky[Count].PCRiadku   := Q.FieldByName('PC_RIADKU').AsInteger;
        Riadky[Count].Text       := Trim(Q.FieldByName('TEXT').AsString);
        Riadky[Count].Mnozstvo   := Q.FieldByName('MNOZSTVO').AsFloat;
        Riadky[Count].MJ         := Trim(Q.FieldByName('MJ').AsString);
        Riadky[Count].CenaJedn   := Q.FieldByName('CENA_JEDN').AsFloat;
        Riadky[Count].CenaBezDPH := Q.FieldByName('CENA_BEZ_DPH').AsFloat;
        Riadky[Count].DPHSadzba  := Q.FieldByName('DPH_SADZBA').AsFloat;
        Riadky[Count].DPHSuma    := Q.FieldByName('DPH_SUMA').AsFloat;
        Riadky[Count].CenaCelkom := Q.FieldByName('CENA_CELKOM').AsFloat;
        Inc(Count);
        Q.Next;
      end;
    finally Q.Free; end;

    if Count = 0 then begin Log('CHYBA: Faktura nema riadky.'); Exit; end;

    // --- LOAD DPH GROUPS ---
    Q := DBQuery(
      'SELECT DPH_SADZBA, SUM(CENA_BEZ_DPH) AS ZAK_BEZ, SUM(DPH_SUMA) AS ZAK_DPH ' +
      'FROM EVID_FA_RIADKY ' +
      'WHERE ID_DOKLADU = ' + IntToStr(AIDDokladu) +
      ' AND ID_SPOL_LIC = ' + IntToStr(AIDSpolLic) +
      ' GROUP BY DPH_SADZBA ORDER BY DPH_SADZBA');
    try
      Count := 0;
      while not Q.Eof do
      begin
        SetLength(DPHGroups, Count + 1);
        DPHGroups[Count].Sadzba    := Q.FieldByName('DPH_SADZBA').AsFloat;
        DPHGroups[Count].ZakladBez := Q.FieldByName('ZAK_BEZ').AsFloat;
        DPHGroups[Count].SumaDPH   := Q.FieldByName('ZAK_DPH').AsFloat;
        Inc(Count);
        Q.Next;
      end;
    finally Q.Free; end;

    // =========================================================
    // BUILD XML
    // =========================================================
    A('<?xml version="1.0" encoding="UTF-8"?>');
    A('<Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"');
    A('  xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"');
    A('  xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">');
    A('  <cbc:CustomizationID>urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0</cbc:CustomizationID>');
    A('  <cbc:ProfileID>urn:fdc:peppol.eu:2017:poacc:billing:01:1.0</cbc:ProfileID>');
    A('  <cbc:ID>' + XMLEscape(IntToStr(CisloDokladu)) + '</cbc:ID>');
    A('  <cbc:IssueDate>' + FormatDateTime('yyyy-mm-dd', DatumDokladu) + '</cbc:IssueDate>');
    A('  <cbc:DueDate>' + FormatDateTime('yyyy-mm-dd', DatumSplatnosti) + '</cbc:DueDate>');
    A('  <cbc:InvoiceTypeCode>380</cbc:InvoiceTypeCode>');
    A('  <cbc:DocumentCurrencyCode>' + XMLEscape(Mena) + '</cbc:DocumentCurrencyCode>');
    // Required data validation must happen before XML generation.
    // For now VAR_SYMBOL is used as Buyer Reference (BT-10).
    if Trim(VarSymbol) = '' then
    begin
      ShowMessage('Vyplnte variabilny symbol (Buyer Reference) alebo cislo objednavky (PO).' +
        #13#10 + 'Fakturu nie je mozne odoslat.');
      Exit;
    end;

    if Trim(Mena) = '' then
    begin
      ShowMessage('Fakturu nie je mozne odoslat: chyba mena faktury.');
      Exit;
    end;

    if Trim(SupNazov) = '' then
    begin
      ShowMessage('Fakturu nie je mozne odoslat: chyba nazov dodavatela.');
      Exit;
    end;

    if Trim(CusNazov) = '' then
    begin
      ShowMessage('Fakturu nie je mozne odoslat: chyba nazov odberatela.');
      Exit;
    end;

    if DatumDokladu = 0 then
    begin
      ShowMessage('Fakturu nie je mozne odoslat: chyba datum vystavenia.');
      Exit;
    end;

    if DatumSplatnosti = 0 then
    begin
      ShowMessage('Fakturu nie je mozne odoslat: chyba datum splatnosti.');
      Exit;
    end;

    for i := 0 to High(Riadky) do
      if Riadky[i].Mnozstvo = 0 then
      begin
        ShowMessage('Fakturu nie je mozne odoslat: riadok ' +
          IntToStr(Riadky[i].PCRiadku) + ' ma nulove mnozstvo.');
        Exit;
      end;

    A('  <cbc:BuyerReference>' + XMLEscape(Trim(VarSymbol)) + '</cbc:BuyerReference>');

    // SUPPLIER
    A('  <cac:AccountingSupplierParty><cac:Party>');
    A('    <cbc:EndpointID schemeID="' + XMLEscape(SupplierParticipantScheme) + '">' +
      XMLEscape(SupplierParticipantValue) + '</cbc:EndpointID>');
    A('    <cac:PostalAddress>');
    A('      <cbc:StreetName>' + XMLEscape(SupUlica) + '</cbc:StreetName>');
    A('      <cbc:CityName>' + XMLEscape(SupMesto) + '</cbc:CityName>');
    A('      <cbc:PostalZone>' + XMLEscape(SupPSC) + '</cbc:PostalZone>');
    A('      <cac:Country><cbc:IdentificationCode>SK</cbc:IdentificationCode></cac:Country>');
    A('    </cac:PostalAddress>');
    A('    <cac:PartyTaxScheme>');
    A('      <cbc:CompanyID>SK' + XMLEscape(SupDIC) + '</cbc:CompanyID>');
    A('      <cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme>');
    A('    </cac:PartyTaxScheme>');
    A('    <cac:PartyLegalEntity>');
    A('      <cbc:RegistrationName>' + XMLEscape(SupNazov) + '</cbc:RegistrationName>');
    A('      <cbc:CompanyID>' + XMLEscape(SupICO) + '</cbc:CompanyID>');
    A('    </cac:PartyLegalEntity>');
    A('  </cac:Party></cac:AccountingSupplierParty>');

    // CUSTOMER
    A('  <cac:AccountingCustomerParty><cac:Party>');
    A('    <cbc:EndpointID schemeID="' + XMLEscape(ReceiverParticipantScheme) + '">' +
      XMLEscape(ReceiverParticipantValue) + '</cbc:EndpointID>');
    A('    <cac:PostalAddress>');
    A('      <cbc:StreetName>' + XMLEscape(CusUlica) + '</cbc:StreetName>');
    A('      <cbc:CityName>' + XMLEscape(CusMesto) + '</cbc:CityName>');
    A('      <cbc:PostalZone>' + XMLEscape(CusPSC) + '</cbc:PostalZone>');
    A('      <cac:Country><cbc:IdentificationCode>SK</cbc:IdentificationCode></cac:Country>');
    A('    </cac:PostalAddress>');
    A('    <cac:PartyTaxScheme>');
    A('      <cbc:CompanyID>SK' + XMLEscape(CusDIC) + '</cbc:CompanyID>');
    A('      <cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme>');
    A('    </cac:PartyTaxScheme>');
    A('    <cac:PartyLegalEntity>');
    A('      <cbc:RegistrationName>' + XMLEscape(CusNazov) + '</cbc:RegistrationName>');
    A('      <cbc:CompanyID>' + XMLEscape(CusICO) + '</cbc:CompanyID>');
    A('    </cac:PartyLegalEntity>');
    A('  </cac:Party></cac:AccountingCustomerParty>');

    // PAYMENT
    A('  <cac:PaymentMeans>');
    A('    <cbc:PaymentMeansCode>30</cbc:PaymentMeansCode>');
    A('    <cac:PayeeFinancialAccount><cbc:ID>' + XMLEscape(SupIBAN) + '</cbc:ID></cac:PayeeFinancialAccount>');
    A('  </cac:PaymentMeans>');

    // TAX TOTAL
    A('  <cac:TaxTotal>');
    A('    <cbc:TaxAmount currencyID="' + Mena + '">' + F2(DPHSuma) + '</cbc:TaxAmount>');
    for i := 0 to High(DPHGroups) do
    begin
      A('    <cac:TaxSubtotal>');
      A('      <cbc:TaxableAmount currencyID="' + Mena + '">' + F2(DPHGroups[i].ZakladBez) + '</cbc:TaxableAmount>');
      A('      <cbc:TaxAmount currencyID="' + Mena + '">' + F2(DPHGroups[i].SumaDPH) + '</cbc:TaxAmount>');
      A('      <cac:TaxCategory>');
      A('        <cbc:ID>' + DPHTaxCategory(DPHGroups[i].Sadzba) + '</cbc:ID>');
      A('        <cbc:Percent>' + F2(DPHGroups[i].Sadzba) + '</cbc:Percent>');
      A('        <cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme>');
      A('      </cac:TaxCategory>');
      A('    </cac:TaxSubtotal>');
    end;
    A('  </cac:TaxTotal>');

    // MONETARY TOTALS
    A('  <cac:LegalMonetaryTotal>');
    A('    <cbc:LineExtensionAmount currencyID="' + Mena + '">' + F2(CenaBezDPH) + '</cbc:LineExtensionAmount>');
    A('    <cbc:TaxExclusiveAmount currencyID="' + Mena + '">' + F2(CenaBezDPH) + '</cbc:TaxExclusiveAmount>');
    A('    <cbc:TaxInclusiveAmount currencyID="' + Mena + '">' + F2(CenaCelkom) + '</cbc:TaxInclusiveAmount>');
    A('    <cbc:PayableAmount currencyID="' + Mena + '">' + F2(CenaCelkom) + '</cbc:PayableAmount>');
    A('  </cac:LegalMonetaryTotal>');

    // INVOICE LINES
    for i := 0 to High(Riadky) do
    begin
      A('  <cac:InvoiceLine>');
      A('    <cbc:ID>' + IntToStr(Riadky[i].PCRiadku) + '</cbc:ID>');
      A('    <cbc:InvoicedQuantity unitCode="' + MJToUnitCode(Riadky[i].MJ) + '">' + F4(Riadky[i].Mnozstvo) + '</cbc:InvoicedQuantity>');
      A('    <cbc:LineExtensionAmount currencyID="' + Mena + '">' + F2(Riadky[i].CenaBezDPH) + '</cbc:LineExtensionAmount>');
      A('    <cac:Item>');
      // PEPPOL-EN16931-R008 requires Item/Name when an Item is present.
      if Trim(Riadky[i].Text) <> '' then
        A('      <cbc:Name>' + XMLEscape(Riadky[i].Text) + '</cbc:Name>')
      else
        A('      <cbc:Name>Polozka ' + IntToStr(Riadky[i].PCRiadku) + '</cbc:Name>');
      A('      <cac:ClassifiedTaxCategory>');
      A('        <cbc:ID>' + DPHTaxCategory(Riadky[i].DPHSadzba) + '</cbc:ID>');
      A('        <cbc:Percent>' + F2(Riadky[i].DPHSadzba) + '</cbc:Percent>');
      A('        <cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme>');
      A('      </cac:ClassifiedTaxCategory>');
      A('    </cac:Item>');
      A('    <cac:Price>');
      // R120: line net amount must match quantity * net unit price.
      // The DB line amount is authoritative, so derive the unit price from
      // that amount instead of using a separately rounded DB unit price.
      if Riadky[i].Mnozstvo = 0 then
        raise Exception.Create('Neplatne mnozstvo na riadku ' +
          IntToStr(Riadky[i].PCRiadku) + ': 0');
      A('      <cbc:PriceAmount currencyID="' + Mena + '">' +
        F4(Riadky[i].CenaBezDPH / Riadky[i].Mnozstvo) + '</cbc:PriceAmount>');
      A('    </cac:Price>');
      A('  </cac:InvoiceLine>');
    end;

    A('</Invoice>');
    Result := SB.Text;
  finally
    SB.Free;
  end;
end;

// ============================================================================
// FORM EVENTS
// ============================================================================

procedure TFormMain.FormCreate(Sender: TObject);
var Ini: TIniFile; UpdatedCount: Integer;
begin
  SetupColumns;
  FDBConn  := nil;
  FLastXML := '';

  edtBaseURL.Text      := EPOSTAK_SANDBOX_BASE_URL;
  edtParticipantId.Text := FIRM_A_ID;
  edtClientId.Text     := FIRM_A_CLIENT_ID;
  edtClientSecret.Text := FIRM_A_CLIENT_SECRET;
  edtReceiverId.Text   := FIRM_B_ID;
  edtSaveFolder.Text   := ExtractFilePath(Application.ExeName) + 'inbox';

  if FileExists(ConfigFileName) then
  begin
    Ini := TIniFile.Create(ConfigFileName);
    try
      edtBaseURL.Text       := Ini.ReadString('EPOSTAK', 'BaseURL',       edtBaseURL.Text);
      edtParticipantId.Text := Ini.ReadString('EPOSTAK', 'ParticipantId', edtParticipantId.Text);
      edtClientId.Text      := Ini.ReadString('EPOSTAK', 'ClientId',      edtClientId.Text);
      edtClientSecret.Text  := Ini.ReadString('EPOSTAK', 'ClientSecret',  edtClientSecret.Text);
      edtReceiverId.Text    := Ini.ReadString('EPOSTAK', 'ReceiverId',    edtReceiverId.Text);
      edtSaveFolder.Text    := Ini.ReadString('EPOSTAK', 'SaveFolder',    edtSaveFolder.Text);
      Log('Konfiguracia nacitana z ' + ConfigFileName);
    finally
      Ini.Free;
    end;
  end;

  dlgOpenXML.Filter := 'XML subory (*.xml)|*.xml|Vsetky (*.*)|*.*';

  // Auto-connect to InTime DB on startup
  ConnectDB;
  if (FDBConn <> nil) and FDBConn.Connected then
  begin
    try
      EnsurePeppolEASTable(FDBConn);
      if PeppolEASNeedsUpdate(FDBConn) then
      begin
        Log('Peppol EAS: aktualizujem ciselnik...');
        if UpdatePeppolEAS(FDBConn, UpdatedCount) then
          Log('Peppol EAS: aktualizovanych ' + IntToStr(UpdatedCount) + ' zaznamov.')
        else
          Log('Peppol EAS: aktualizacia sa nepodarila, pouzivam lokalny ciselnik.');
      end
      else
        Log('Peppol EAS: lokalny ciselnik je aktualny.');
    except
      on E: Exception do Log('Peppol EAS: chyba aktualizacie - ' + E.Message);
    end;
  end;
end;

procedure TFormMain.FormDestroy(Sender: TObject);
begin
  if FClient <> nil then
  begin
    try FClient.RevokeToken; except end;
    FreeAndNil(FClient);
  end;
  if FDBConn <> nil then
  begin
    try FDBConn.Close; except end;
    FreeAndNil(FDBConn);
  end;
end;

procedure TFormMain.btnSaveConfigClick(Sender: TObject);
var Ini: TIniFile;
begin
  Ini := TIniFile.Create(ConfigFileName);
  try
    Ini.WriteString('EPOSTAK', 'BaseURL',       edtBaseURL.Text);
    Ini.WriteString('EPOSTAK', 'ParticipantId', edtParticipantId.Text);
    Ini.WriteString('EPOSTAK', 'ClientId',      edtClientId.Text);
    Ini.WriteString('EPOSTAK', 'ClientSecret',  edtClientSecret.Text);
    Ini.WriteString('EPOSTAK', 'ReceiverId',    edtReceiverId.Text);
    Ini.WriteString('EPOSTAK', 'SaveFolder',    edtSaveFolder.Text);
    Log('Konfiguracia ulozena.');
  finally
    Ini.Free;
  end;
end;

procedure TFormMain.btnUseFirmAClick(Sender: TObject);
begin
  edtParticipantId.Text := FIRM_A_ID;
  edtClientId.Text      := FIRM_A_CLIENT_ID;
  edtClientSecret.Text  := FIRM_A_CLIENT_SECRET;
  edtReceiverId.Text    := FIRM_B_ID;
  Log('Nastavene: Firma A -> Firma B');
end;

procedure TFormMain.btnUseFirmBClick(Sender: TObject);
begin
  edtParticipantId.Text := FIRM_B_ID;
  edtClientId.Text      := FIRM_B_CLIENT_ID;
  edtClientSecret.Text  := FIRM_B_CLIENT_SECRET;
  edtReceiverId.Text    := FIRM_A_ID;
  Log('Nastavene: Firma B');
end;

procedure TFormMain.btnUseSandboxClick(Sender: TObject);
begin
  edtBaseURL.Text := EPOSTAK_SANDBOX_BASE_URL;
  Log('URL: Sandbox');
end;

procedure TFormMain.btnUseProductionClick(Sender: TObject);
begin
  edtBaseURL.Text := EPOSTAK_PRODUCTION_BASE_URL;
  Log('URL: Produkcia — uistite sa ze mate produkcne credentials.');
end;

procedure TFormMain.btnBrowseXMLClick(Sender: TObject);
begin
  if dlgOpenXML.Execute then edtXMLFile.Text := dlgOpenXML.FileName;
end;

procedure TFormMain.btnBrowseFolderClick(Sender: TObject);
var Dir: string;
begin
  Dir := edtSaveFolder.Text;
  if SelectDirectory('Priecinok pre stahovanie', '', Dir) then
    edtSaveFolder.Text := Dir;
end;

// ============================================================================
// INTIME DB BUTTONS
// ============================================================================

procedure TFormMain.btnConnectDBClick(Sender: TObject);
begin
  ConnectDB;
end;

procedure TFormMain.ConnectDB;
const
  DB_CONNSTR =
    'Driver={Firebird/InterBase(r) driver};' +
    'DBNAME=192.168.1.15:C:\Dochadzka.NET\DOCHADZKA.GDB;' +
    'UID=SYSDBA;' +
    'PWD=masterkey;' +
    'CHARSET=WIN1250;';
begin
  if FDBConn <> nil then
  begin
    if FDBConn.Connected then
    begin
      Log('DB: uz pripojena.');
      Exit;
    end;
    FreeAndNil(FDBConn);
  end;

  FDBConn := TADOConnection.Create(nil);
  FDBConn.LoginPrompt := False;
  FDBConn.ConnectionString := DB_CONNSTR;
  try
    FDBConn.Open;
    Log('OK: Pripojeny k 192.168.1.15:C:\Dochadzka.NET\DOCHADZKA.GDB');
    btnConnectDB.Caption := 'Pripojeny';
  except
    on E: Exception do
    begin
      FreeAndNil(FDBConn);
      Log('CHYBA pripojenia: ' + E.Message);
      Log('Poziadavka: Firebird ODBC driver nainstalovany, server dostupny na 192.168.1.15');
    end;
  end;
end;

procedure TFormMain.btnLoadInvoicesClick(Sender: TObject);
var
  Q:        TADOQuery;
  Item:     TListItem;
  IDSpolLic: Integer;
  Year:     Integer;
begin
  lvInvoices.Items.Clear;
  if cmbSpolLic.ItemIndex < 0 then
  begin
    // Load spolocnosti into combo
    try
      Q := DBQuery('SELECT ID_SPOLOCNOSTI, NAZOV_SPOLOCNOSTI FROM GLB_LICENCIE ORDER BY NAZOV_SPOLOCNOSTI');
      try
        cmbSpolLic.Items.Clear;
        while not Q.Eof do
        begin
          cmbSpolLic.Items.AddObject(
            Trim(Q.FieldByName('NAZOV_SPOLOCNOSTI').AsString),
            TObject(Q.FieldByName('ID_SPOLOCNOSTI').AsInteger));
          Q.Next;
        end;
        if cmbSpolLic.Items.Count > 0 then cmbSpolLic.ItemIndex := 0;
      finally Q.Free; end;
    except
      on E: Exception do begin Log('CHYBA nacitania spolocnosti: ' + E.Message); Exit; end;
    end;
  end;

  if cmbSpolLic.ItemIndex < 0 then begin Log('Ziadne spolocnosti.'); Exit; end;

  IDSpolLic := Integer(cmbSpolLic.Items.Objects[cmbSpolLic.ItemIndex]);
  Year := StrToIntDef(FormatDateTime('yyyy', Now), 2026);

  Log('Nacitavam faktury FV za ' + IntToStr(Year) + ' pre ' +
      cmbSpolLic.Items[cmbSpolLic.ItemIndex] + '...');
  try
    Q := DBQuery(
      'SELECT h.ID_DOKLADU, h.ID_SPOL_LIC, h.CISLO_DOKLADU, h.DATUM_DOKLADU, ' +
      'h.DATUM_SPLATNOSTI, h.CENA_CELKOM, h.MENA, h.UHRADENA, ' +
      'f.NAZOV_SPOLOCNOSTI ' +
      'FROM EVID_FA_HLAVICKA h JOIN FIRMY f ON f.ID = h.ID_FIRMY ' +
      'WHERE h.ID_SPOL_LIC = ' + IntToStr(IDSpolLic) +
      ' AND h.TYP_DOKLADU = ''FV''' +
      ' AND h.OBDOBIE = ' + IntToStr(Year) +
      ' ORDER BY h.CISLO_DOKLADU DESC');
    try
      while not Q.Eof do
      begin
        Item := lvInvoices.Items.Add;
        Item.Caption := IntToStr(Q.FieldByName('CISLO_DOKLADU').AsInteger);
        Item.SubItems.Add(FormatDateTime('dd.mm.yyyy', Q.FieldByName('DATUM_DOKLADU').AsDateTime));
        Item.SubItems.Add(FormatDateTime('dd.mm.yyyy', Q.FieldByName('DATUM_SPLATNOSTI').AsDateTime));
        Item.SubItems.Add(Trim(Q.FieldByName('NAZOV_SPOLOCNOSTI').AsString));
        Item.SubItems.Add(F2(Q.FieldByName('CENA_CELKOM').AsFloat) + ' ' +
                          Trim(Q.FieldByName('MENA').AsString));
        Item.SubItems.Add(Trim(Q.FieldByName('UHRADENA').AsString));
        // Hidden: ID_DOKLADU and ID_SPOL_LIC in Data
        Item.Data := Pointer(Q.FieldByName('ID_DOKLADU').AsInteger);
        Item.SubItems.Add(IntToStr(Q.FieldByName('ID_SPOL_LIC').AsInteger));
        Q.Next;
      end;
      Log('Nacitanych ' + IntToStr(lvInvoices.Items.Count) + ' faktur.');
    finally Q.Free; end;
  except
    on E: Exception do Log('CHYBA: ' + E.Message);
  end;
end;

procedure TFormMain.btnLoadFromDBClick(Sender: TObject);
var
  IDDokladu: Integer;
  IDSpolLic: Integer;
begin
  if lvInvoices.Selected = nil then
  begin
    Log('CHYBA: Vyberte fakturu zo zoznamu.');
    Exit;
  end;

  IDDokladu := Integer(lvInvoices.Selected.Data);
  IDSpolLic := StrToIntDef(lvInvoices.Selected.SubItems[5], 1);

  Log('Generujem UBL XML: faktura c.' + lvInvoices.Selected.Caption +
      ' | ' + lvInvoices.Selected.SubItems[2] + '...');

  FLastXML := GenerujUBLInvoice(IDDokladu, IDSpolLic,
    Trim(edtParticipantId.Text), Trim(edtReceiverId.Text));

  if FLastXML = '' then
  begin
    Log('CHYBA: XML sa nepodarilo vygenerovat.');
    Exit;
  end;

  edtXMLFile.Text := '';
  Log('OK: XML vygenerovany (' + IntToStr(Length(FLastXML)) + ' znakov). Kliknite ODOSLAT.');
end;

// ============================================================================
// SEND
// ============================================================================

procedure TFormMain.btnSendClick(Sender: TObject);
var
  Client: TEpostakClient;
  UblXml, DocId: string;
begin
  if Trim(edtBaseURL.Text) = '' then begin Log('CHYBA: Vyplnte Base URL.'); Exit; end;
  if Trim(edtParticipantId.Text) = '' then begin Log('CHYBA: Vyplnte Participant ID.'); Exit; end;
  if Trim(edtReceiverId.Text) = '' then begin Log('CHYBA: Vyplnte Prijemcu.'); Exit; end;

  // Priority: FLastXML (from DB) > file > sample
  if FLastXML <> '' then
  begin
    UblXml := FLastXML;
    Log('Pouzivam XML z InTime DB...');
  end
  else if Trim(edtXMLFile.Text) <> '' then
  begin
    if not FileExists(edtXMLFile.Text) then begin Log('CHYBA: Subor neexistuje.'); Exit; end;
    Log('Nacitavam XML zo suboru: ' + edtXMLFile.Text);
    UblXml := LoadRawBytesFromFile(edtXMLFile.Text);
  end
  else
  begin
    Log('CHYBA: Nacitajte fakturu z DB (tlacidlo "Nacitaj z InTime") alebo vyberte XML subor.');
    Exit;
  end;

  if Trim(UblXml) = '' then begin Log('CHYBA: XML je prazdny.'); Exit; end;

  try
    Client := MakeClient;
  except
    on E: Exception do begin Log('CHYBA: ' + E.Message); Exit; end;
  end;

  DocId := NewGUID;
  Log('Odosielam ' + DocId + '...');
  try
    Client.SendInvoice(
      DocId,
      DOC_TYPE_ID,
      PROCESS_ID,
      edtParticipantId.Text,
      edtReceiverId.Text,
      UblXml
    );
    FLastXML := ''; // clear after successful send
    Log('OK — Faktura odoslana. DocumentId: ' + DocId);
  except
    on E: Exception do
    begin
      if Pos('HTTP 422', E.Message) > 0 then
      begin
        Log('CHYBA 422: XML nepreslo Peppol validaciou.');
        Log('Detail: ' + E.Message);
        Log('Validator: https://peppol.helger.com/public/menuitem-validation-bis3');
      end
      else if Pos('HTTP 502', E.Message) > 0 then
      begin
        Log('CHYBA 502: Prijemca nie je v Peppol sieti.');
        Log(E.Message);
      end
      else
        Log('CHYBA: ' + E.Message);
    end;
  end;
end;

// ============================================================================
// INBOX
// ============================================================================

procedure TFormMain.btnCheckInboxClick(Sender: TObject);
var Client: TEpostakClient;
begin
  try Client := MakeClient; except on E: Exception do begin Log('CHYBA: ' + E.Message); Exit; end; end;
  Log('Kontrolujem inbox...');
  try
    FInboxItems := Client.ListReceived('RECEIVED', 100);
    RefreshInboxList;
    Log('Najdenych ' + IntToStr(Length(FInboxItems.Documents)) + ' dokumentov.');
  except
    on E: Exception do Log('CHYBA: ' + E.Message);
  end;
end;

procedure TFormMain.btnDownloadSelectedClick(Sender: TObject);
var Client: TEpostakClient; DocId, XML, SavePath: string;
begin
  DocId := GetSelectedDocId;
  if DocId = '' then begin Log('Vyberte dokument.'); Exit; end;
  try Client := MakeClient; except on E: Exception do begin Log('CHYBA: ' + E.Message); Exit; end; end;
  ForceDirectories(edtSaveFolder.Text);
  SavePath := IncludeTrailingBackslash(edtSaveFolder.Text) + DocId + '.xml';
  Log('Stahujem ' + DocId + '...');
  try
    XML := Client.GetDocumentXML(DocId);
    SaveRawBytesToFile(SavePath, XML);
    Log('ULOZENE: ' + SavePath);
  except
    on E: Exception do Log('CHYBA: ' + E.Message);
  end;
end;

procedure TFormMain.btnAcknowledgeSelectedClick(Sender: TObject);
var Client: TEpostakClient; DocIds: TStringList; i, OkCount, FailCount: Integer;
begin
  DocIds := GetSelectedDocIds;
  try
    if DocIds.Count = 0 then begin Log('Vyberte dokumenty.'); Exit; end;
    try Client := MakeClient; except on E: Exception do begin Log('CHYBA: ' + E.Message); Exit; end; end;
    Log('Potvrdzujem ' + IntToStr(DocIds.Count) + ' dokumentov...');
    OkCount := 0; FailCount := 0;
    for i := 0 to DocIds.Count - 1 do
    begin
      try
        Client.AcknowledgeDocument(DocIds[i]);
        Inc(OkCount);
        Log('  OK: ' + DocIds[i]);
        if i < DocIds.Count - 1 then Sleep(1000);
      except
        on E: Exception do begin Inc(FailCount); Log('  CHYBA: ' + DocIds[i] + ' - ' + E.Message); end;
      end;
    end;
    Log('HOTOVO: ' + IntToStr(OkCount) + ' OK, ' + IntToStr(FailCount) + ' chyb.');
    btnCheckInboxClick(nil);
  finally
    DocIds.Free;
  end;
end;

end.
