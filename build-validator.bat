@echo off
setlocal
cd /d "%~dp0"
where java >nul 2>&1
if errorlevel 1 (
  echo Java 17+ is required.
  exit /b 1
)
where mvn >nul 2>&1
if errorlevel 1 (
  echo Maven is required to build the validator.
  exit /b 2
)
mvn -f peppol-validator\pom.xml -DskipTests clean package
if errorlevel 1 exit /b %errorlevel%
copy /Y peppol-validator\target\EpostakPeppolValidator.jar EpostakPeppolValidator.jar >nul
if errorlevel 1 exit /b 3
echo.
echo OK: EpostakPeppolValidator.jar built and copied next to EpostakApp.exe.
endlocal
