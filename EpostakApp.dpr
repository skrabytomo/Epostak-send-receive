program EpostakApp;

uses
  Forms,
  UMainForm in 'UMainForm.pas' {FormMain};

begin
  Application.Initialize;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
