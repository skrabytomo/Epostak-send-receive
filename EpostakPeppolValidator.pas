unit EpostakPeppolValidator;

interface

uses
  Windows, SysUtils, StrUtils, Classes, WinInet, ComObj, Variants;

type
  TPeppolValidationResult = record
    Valid: Boolean;
    VES: string;
    ErrorCount: Integer;
    Errors: TStringList;
  end;

function PeppolValidatorAvailable: Boolean;
function ValidatePeppolXMLFile(const AFileName: string;
  out AResult: TPeppolValidationResult): Boolean;
function ValidatePeppolXMLText(const AXML: string;
  out AResult: TPeppolValidationResult): Boolean;
procedure FreePeppolValidationResult(var AResult: TPeppolValidationResult);

implementation

function FindValidatorJar: string;
var
  Candidates: TStringList;
  I, P: Integer;
  EnvJar, Base: string;
begin
  Result := '';
  Candidates := TStringList.Create;
  try
    EnvJar := Trim(GetEnvironmentVariable('EPOSTAK_PEPPOL_VALIDATOR_JAR'));
    if EnvJar <> '' then Candidates.Add(EnvJar);

    Base := ExtractFilePath(ParamStr(0));
    Candidates.Add(Base + 'EpostakPeppolValidator.jar');
    Candidates.Add(Base + 'peppol-validator' + PathDelim + 'target' +
      PathDelim + 'EpostakPeppolValidator.jar');

    for I := 0 to Candidates.Count - 1 do
      if FileExists(Candidates[I]) then
      begin
        Result := Candidates[I];
        Exit;
      end;
  finally
    Candidates.Free;
  end;
end;

function FindJavaExe: string;
var
  JavaHome: string;
  Candidate: string;
begin
  Result := '';
  JavaHome := Trim(GetEnvironmentVariable('JAVA_HOME'));
  if JavaHome <> '' then
  begin
    Candidate := IncludeTrailingPathDelimiter(JavaHome) + 'bin' + PathDelim + 'java.exe';
    if FileExists(Candidate) then
    begin
      Result := Candidate;
      Exit;
    end;
  end;

  Candidate := IncludeTrailingPathDelimiter(GetEnvironmentVariable('WINDIR')) +
    'System32' + PathDelim + 'java.exe';
  if FileExists(Candidate) then
    Result := Candidate
  else
    Result := 'java.exe';
end;

function PeppolValidatorAvailable: Boolean;
var
  JavaExe: string;
  Buffer: array[0..MAX_PATH - 1] of Char;
begin
  JavaExe := FindJavaExe;
  Result := (FindValidatorJar <> '') and
            (SearchPath(nil, PChar(JavaExe), nil, SizeOf(Buffer), Buffer, nil) > 0);
end;

function QuoteArg(const S: string): string;
begin
  Result := '"' + StringReplace(S, '"', '"', [rfReplaceAll]) + '"';
end;

function RunProcessCapture(const ACommandLine: string; out AOutput: string;
  out AExitCode: Cardinal): Boolean;
var
  SA: TSecurityAttributes;
  ReadPipe, WritePipe: THandle;
  SI: TStartupInfo;
  PI: TProcessInformation;
  Buffer: array[0..4095] of Byte;
  ReadBytes: DWORD;
  Cmd: string;
  H: THandle;
begin
  Result := False;
  AOutput := '';
  AExitCode := Cardinal(-1);
  ReadPipe := 0;
  WritePipe := 0;
  FillChar(SA, SizeOf(SA), 0);
  SA.nLength := SizeOf(SA);
  SA.bInheritHandle := True;

  if not CreatePipe(ReadPipe, WritePipe, @SA, 0) then Exit;
  try
    SetHandleInformation(ReadPipe, HANDLE_FLAG_INHERIT, 0);

    FillChar(SI, SizeOf(SI), 0);
    SI.cb := SizeOf(SI);
    SI.dwFlags := STARTF_USESTDHANDLES;
    SI.hStdOutput := WritePipe;
    SI.hStdError := WritePipe;
    SI.hStdInput := GetStdHandle(STD_INPUT_HANDLE);

    FillChar(PI, SizeOf(PI), 0);
    Cmd := ACommandLine;
    if not CreateProcess(nil, PChar(Cmd), nil, nil, True,
      CREATE_NO_WINDOW, nil, nil, SI, PI) then
      Exit;

    CloseHandle(WritePipe);
    WritePipe := 0;

    WaitForSingleObject(PI.hProcess, INFINITE);
    GetExitCodeProcess(PI.hProcess, AExitCode);

    repeat
      ReadBytes := 0;
      if not ReadFile(ReadPipe, Buffer[0], SizeOf(Buffer), ReadBytes, nil) then Break;
      if ReadBytes > 0 then
      begin
        SetLength(Cmd, ReadBytes);
        Move(Buffer[0], Cmd[1], ReadBytes);
        AOutput := AOutput + Cmd;
      end;
    until ReadBytes = 0;

    CloseHandle(PI.hThread);
    CloseHandle(PI.hProcess);
    Result := True;
  finally
    if WritePipe <> 0 then CloseHandle(WritePipe);
    if ReadPipe <> 0 then CloseHandle(ReadPipe);
  end;
end;

function JsonUnescape(const S: string): string;
var
  I: Integer;
  Hex: string;
begin
  Result := '';
  I := 1;
  while I <= Length(S) do
  begin
    if (S[I] = '') and (I < Length(S)) then
    begin
      Inc(I);
      case S[I] of
        '"': Result := Result + '"';
        '': Result := Result + '';
        '/': Result := Result + '/';
        'n': Result := Result + #10;
        'r': Result := Result + #13;
        't': Result := Result + #9;
        'b': Result := Result + #8;
        'f': Result := Result + #12;
        'u':
          begin
            if I + 4 <= Length(S) then
            begin
              Hex := Copy(S, I + 1, 4);
              Result := Result + WideChar(StrToIntDef('$' + Hex, Ord('?')));
              Inc(I, 4);
            end;
          end;
      else
        Result := Result + S[I];
      end;
    end
    else
      Result := Result + S[I];
    Inc(I);
  end;
end;

function JsonIntAfter(const AJSON, AName: string; AStart: Integer): Integer;
var
  P, StartPos, EndPos: Integer;
  Search: string;
begin
  Result := 0;
  Search := '"' + AName + '"';
  P := PosEx(Search, AJSON, AStart);
  if P = 0 then Exit;
  P := P + Length(Search);
  while (P <= Length(AJSON)) and (AJSON[P] <> ':') do Inc(P);
  if P > Length(AJSON) then Exit;
  Inc(P);
  while (P <= Length(AJSON)) and (AJSON[P] in [' ', #9, #10, #13]) do Inc(P);
  StartPos := P;
  EndPos := P;
  while (EndPos <= Length(AJSON)) and (AJSON[EndPos] in ['0'..'9', '-']) do Inc(EndPos);
  Result := StrToIntDef(Copy(AJSON, StartPos, EndPos - StartPos), 0);
end;

function JsonStringAfter(const AJSON, AName: string; AStart: Integer): string;
var
  P, StartPos, EndPos: Integer;
  Search: string;
begin
  Result := '';
  Search := '"' + AName + '"';
  P := PosEx(Search, AJSON, AStart);
  if P = 0 then Exit;
  P := P + Length(Search);
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
       ((EndPos = StartPos) or (AJSON[EndPos - 1] <> '')) then Break;
    Inc(EndPos);
  end;
  if EndPos <= Length(AJSON) then
    Result := JsonUnescape(Copy(AJSON, StartPos, EndPos - StartPos));
end;

procedure InitResult(var AResult: TPeppolValidationResult);
begin
  FillChar(AResult, SizeOf(AResult), 0);
  AResult.Errors := TStringList.Create;
end;

procedure FreePeppolValidationResult(var AResult: TPeppolValidationResult);
begin
  if AResult.Errors <> nil then AResult.Errors.Free;
  FillChar(AResult, SizeOf(AResult), 0);
end;

function ValidatePeppolXMLFile(const AFileName: string;
  out AResult: TPeppolValidationResult): Boolean;
var
  Jar, JavaExe, Cmd, Output, S: string;
  ExitCode: Cardinal;
  P, I: Integer;
begin
  InitResult(AResult);
  Result := False;

  if not FileExists(AFileName) then
  begin
    AResult.Errors.Add('XML súbor neexistuje: ' + AFileName);
    Exit;
  end;

  Jar := FindValidatorJar;
  if Jar = '' then
  begin
    AResult.Errors.Add('Peppol validator JAR nie je nainštalovaný. Spustite peppol-validator' +
      PathDelim + 'build-validator.bat.');
    Exit;
  end;

  JavaExe := FindJavaExe;
  Cmd := QuoteArg(JavaExe) + ' -Xss2m -jar ' + QuoteArg(Jar) + ' auto ' + QuoteArg(AFileName);

  if not RunProcessCapture(Cmd, Output, ExitCode) then
  begin
    AResult.Errors.Add('Nepodarilo sa spustiť Peppol validator.');
    Exit;
  end;

  P := Pos('{"valid":', Output);
  if P = 0 then
  begin
    if Trim(Output) <> '' then
      AResult.Errors.Add(Trim(Output))
    else
      AResult.Errors.Add('Validator nevrátil výsledok (exit code ' + IntToStr(ExitCode) + ').');
    Exit;
  end;

  S := Copy(Output, P, MaxInt);
  AResult.Valid := Pos('"valid":true', S) > 0;
  AResult.VES := JsonStringAfter(S, 'ves', 1);
  AResult.ErrorCount := JsonIntAfter(S, 'errorCount', 1);

  I := 1;
  while True do
  begin
    P := PosEx('"message":"', S, I);
    if P = 0 then Break;
    S := S; // keep compiler-compatible with old Delphi
    AResult.Errors.Add(JsonStringAfter(Copy(Output, P, MaxInt), 'message', 1));
    I := P + 10;
  end;

  Result := True;
end;

function ValidatePeppolXMLText(const AXML: string;
  out AResult: TPeppolValidationResult): Boolean;
var
  TempFile: string;
  FS: TFileStream;
begin
  TempFile := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP')) +
    Format('epostak-peppol-%d.xml', [GetTickCount]);
  FS := TFileStream.Create(TempFile, fmCreate);
  try
    if Length(AXML) > 0 then
      FS.WriteBuffer(AXML[1], Length(AXML));
  finally
    FS.Free;
  end;
  try
    Result := ValidatePeppolXMLFile(TempFile, AResult);
  finally
    DeleteFile(TempFile);
  end;
end;

end.
