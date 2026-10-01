program EpostakApp;

uses
  Forms,
  UMainForm in 'UMainForm.pas' {FormMain},
  EpostakPeppolEAS in 'EpostakPeppolEAS.pas',
  EpostakClient in 'EpostakClient.pas',
  EpostakDemoCreds in 'EpostakDemoCreds.pas';

begin
  Application.Initialize;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
