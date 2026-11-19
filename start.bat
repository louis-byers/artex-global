@echo off
rem 콘솔을 UTF-8 로 전환합니다. 그러지 않으면 이 파일의 한글이 GBK 터미널에서 깨집니다.
chcp 65001 >nul 2>&1
rem ARTEX 데몬 시작 스크립트(Windows)
rem
rem 사용법:
rem   start.bat                  포그라운드 실행(Ctrl-C 로 중지)
rem   start.bat -addr :9000      추가 인자는 artex 로 그대로 전달
rem
rem 이 스크립트는 한 가지만 합니다. artex.exe 를 실행하고, 프로세스가 종료되면 종료 코드를 보고 다시 띄울지 결정합니다.
rem
rem   0      사용자가 정상 중지  -> 루프 종료
rem   그 외  비정상 종료       -> 백오프 후 다시 실행(1->2->4…최대 60초)
rem
rem 업데이트는 소스에서 다시 빌드합니다. 이 스크립트는 바이너리를 내려받거나 교체하지 않습니다.

setlocal enabledelayedexpansion
cd /d "%~dp0"

set "BIN=artex.exe"
if not exist "%BIN%" (
	echo [artex] 실행 파일을 찾을 수 없습니다: %BIN% 1>&2
	exit /b 1
)

set "MAX_DELAY=60"
set /a delay=1

:loop
"%BIN%" %*
set "code=!ERRORLEVEL!"

if "!code!"=="0" (
	echo [artex] 정상 종료
	exit /b 0
)

echo [artex] 비정상 종료 ^(code=!code!^), !delay!s 후 재시작 1>&2
rem timeout 은 리디렉션된 콘솔에서 실패하므로 ping 으로 대체합니다(N초 지연에는 N+1 번 필요).
set /a pings=!delay!+1
ping -n !pings! 127.0.0.1 >nul 2>&1
set /a delay=!delay!*2
if !delay! gtr %MAX_DELAY% set /a delay=%MAX_DELAY%
goto loop
