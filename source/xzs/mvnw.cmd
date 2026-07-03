@echo off
setlocal

set "BASE_DIR=%~dp0"
if "%BASE_DIR:~-1%"=="\" set "BASE_DIR=%BASE_DIR:~0,-1%"
set "WRAPPER_DIR=%BASE_DIR%\.mvn\wrapper"
set "WRAPPER_JAR=%WRAPPER_DIR%\maven-wrapper.jar"
set "WRAPPER_URL=https://repo.maven.apache.org/maven2/org/apache/maven/wrapper/maven-wrapper/3.3.2/maven-wrapper-3.3.2.jar"

if not exist "%WRAPPER_JAR%" (
    if not exist "%WRAPPER_DIR%" mkdir "%WRAPPER_DIR%"
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%WRAPPER_URL%' -OutFile '%WRAPPER_JAR%'"
    if errorlevel 1 (
        echo Error: failed to download maven-wrapper.jar from %WRAPPER_URL% 1>&2
        exit /b 1
    )
)

set "MAVEN_JAVA_EXE="
if not "%JAVA_HOME%"=="" if exist "%JAVA_HOME%\bin\java.exe" set "MAVEN_JAVA_EXE=%JAVA_HOME%\bin\java.exe"
if "%MAVEN_JAVA_EXE%"=="" (
    for /f "delims=" %%i in ('where java.exe 2^>NUL') do (
        if "%MAVEN_JAVA_EXE%"=="" set "MAVEN_JAVA_EXE=%%i"
    )
)

if "%MAVEN_JAVA_EXE%"=="" (
    echo Error: java.exe was not found. Set JAVA_HOME or add java.exe to PATH. 1>&2
    exit /b 1
)

"%MAVEN_JAVA_EXE%" %MAVEN_OPTS% -classpath "%WRAPPER_JAR%" "-Dmaven.multiModuleProjectDirectory=%BASE_DIR%" org.apache.maven.wrapper.MavenWrapperMain %MAVEN_CONFIG% %*
exit /b %ERRORLEVEL%
