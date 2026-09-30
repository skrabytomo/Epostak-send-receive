unit EpostakDemoCreds;

{ ============================================================================
  Verejne demo credentialy zo sandboxu (https://epostak.sk/api/docs).
  Pouzitelne LEN na https://dev.epostak.sk/sapi/v1, nie na produkcii.

  FIRM_B_CLIENT_SECRET je zamerne prazdny - na docs stranke je zobrazeny
  zamaskovany. Skopirujte realnu hodnotu priamo zo stranky (tlacidlo Copy
  pri "Firma B - prijimatel") predtym, nez budete testovat prijem.
  ============================================================================ }

interface

const
  EPOSTAK_SANDBOX_BASE_URL    = 'https://dev.epostak.sk/sapi/v1';
  EPOSTAK_PRODUCTION_BASE_URL = 'https://epostak.sk/sapi/v1'; // doplnit po ziskani prod pristupov

  FIRM_A_ID            = '0245:0000000001'; // odosielatel
  FIRM_A_CLIENT_ID     = '487d008a-b3a5-49d0-be3e-ba45cc9c4ffe';
  FIRM_A_CLIENT_SECRET = 'sk_live_test_5e188b91708ca938e1ee50678b345a3c152b4d4a83d31eac';

  FIRM_B_ID            = '0245:0000000002'; // prijimatel
  FIRM_B_CLIENT_ID     = 'b6649c59-2f9d-4ae2-a750-af257c455478';
  FIRM_B_CLIENT_SECRET = 'sk_live_test_e8a28d2e5ec006b2e27a3a1a92739fd93f1d71e70abe6733';

{ Vrati True a naplni ClientId/ClientSecret, ak AParticipantId zodpoveda
  jednej z dvoch znamych demo firiem. Inak False (vtedy pouzite vlastne
  ClientId/ClientSecret, napr. z .ini suboru). }
function ResolveDemoCredentials(const AParticipantId: string;
  out AClientId, AClientSecret: string): Boolean;

{ Pre demo ucely: ak posielate ako Firma A, protistrana je Firma B a naopak.
  Vrati '' ak AParticipantId nie je jedna zo znamych demo firiem. }
function AutoPairParticipant(const AParticipantId: string): string;

implementation

function ResolveDemoCredentials(const AParticipantId: string;
  out AClientId, AClientSecret: string): Boolean;
begin
  Result := True;
  if AParticipantId = FIRM_A_ID then
  begin
    AClientId := FIRM_A_CLIENT_ID;
    AClientSecret := FIRM_A_CLIENT_SECRET;
  end
  else if AParticipantId = FIRM_B_ID then
  begin
    AClientId := FIRM_B_CLIENT_ID;
    AClientSecret := FIRM_B_CLIENT_SECRET;
  end
  else
  begin
    AClientId := '';
    AClientSecret := '';
    Result := False;
  end;
end;

function AutoPairParticipant(const AParticipantId: string): string;
begin
  if AParticipantId = FIRM_A_ID then
    Result := FIRM_B_ID
  else if AParticipantId = FIRM_B_ID then
    Result := FIRM_A_ID
  else
    Result := '';
end;

end.
