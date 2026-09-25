# 패키지 설치

design-time BPL이다. Requires는 `rtl`, `vcl`, `designide`뿐이다. designide는 IDE에 있는 것을 참조만 한다. 재배포하지 않는다.

한 BPL을 32-bit IDE와 64-bit IDE에 같이 등록하지 않는다. 비트가 다른 BPL은 그 IDE가 로드하지 못한다.

| IDE | 출력 | Known Packages |
| --- | --- | --- |
| 32-bit `%BDS%\bin\bds.exe` | `$(BDSCOMMONDIR)\Bpl\RADAgent<nnn>.bpl` | `HKCU\Software\Embarcadero\BDS\<ver>\Known Packages` |
| 64-bit `%BDS%\bin64\bds.exe` (13) | `$(BDSCOMMONDIR)\Bpl\Win64\RADAgent370.bpl` | `HKCU\Software\Embarcadero\BDS\37.0\Known Packages x64` |

`<nnn>`은 `{$LIBSUFFIX AUTO}`가 정한다: 10.4 `270`(21.0), 11 `280`(22.0), 12 `290`(23.0), 13 `370`(37.0). 지원 하한은 10.4다.

## 빌드

같은 비트의 IDE가 그 BPL을 열고 있으면 덮어쓸 수 없다. 그 IDE를 종료한 뒤 빌드한다.

```bat
scripts\build-win32.cmd [-Version 22.0]
scripts\build-win64.cmd [-Version 37.0]
```

릴리스는 `-Version`, 없으면 `%BDS%`, 그다음 레지스트리(`HKLM\SOFTWARE\WOW6432Node\Embarcadero\BDS\<ver>\RootDir`)의 가장 새 지원 릴리스다(`scripts\bds.ps1`). 찾지 못하거나 지원하지 않는 릴리스면 컴파일러를 호출하지 않고 오류로 끝난다. 64-bit IDE가 없는 릴리스에서 `build-win64.cmd`는 건너뛴다.

### 채팅 화면(WebView2)

채팅 기록은 Edge WebView2로 그린다. 패키지 Requires는 그대로 `rtl`, `vcl`, `designide`이고, `vcledge`(TEdgeBrowser)는 쓰지 않는다. RAD Agent가 선언한 WebView2 인터페이스(`RADAgent.WebView2Api`, Microsoft WebView2.h의 vtable 순서)로 직접 띄운다. rtl `Winapi.WebView2`는 릴리스마다 내용이 달라 쓰지 않는다.

- 빌드 스크립트가 BPL 옆 `RADAgent\` 폴더에 `chat\`(src\chat의 HTML/CSS/JS)과 그 비트의 `WebView2Loader.dll`을 복사한다. Win32는 `Bpl\RADAgent\`, Win64는 `Bpl\Win64\RADAgent\`다.
- `WebView2Loader.dll`은 `scripts\fetch-webview2.ps1`이 NuGet의 `Microsoft.Web.WebView2` 고정 버전에서 한 번 받아 `third_party\webview2\`에 둔다. Microsoft 서명을 확인하고, 저장소에는 넣지 않는다(`.gitignore`).
- 실행하는 PC에는 Edge WebView2 런타임이 있어야 한다. Windows 11에는 기본으로 있다.
- 브라우저 데이터는 `%LOCALAPPDATA%\RADAgent\WebView2`에 둔다.
- WebView2를 띄우지 못하면 채팅 창은 이유를 적고 글자만 보여 주는 화면으로 계속 동작한다.

## 64-bit IDE

1. `scripts\build-win64.cmd`로 `$(BDSCOMMONDIR)\Bpl\Win64\RADAgent370.bpl`을 만든다(RAD Studio 13만).
2. `%BDS%\bin64\bds.exe`만 실행한다.
3. Component → Install Packages 를 연다.
4. Add 로 Win64 BPL만 고른다. 이 키는 `Known Packages x64`다.
5. 확인한 뒤 Tools 또는 View → RAD Agent 로 도킹 Chat을 연다. View 메뉴 컴포넌트 이름은 `ViewsMenu`다.

Win32 BPL을 이 대화상자에 넣지 않는다.

## 32-bit IDE

1. `scripts\build-win32.cmd [-Version <ver>]`로 `$(BDSCOMMONDIR)\Bpl\RADAgent<nnn>.bpl`을 만든다.
2. `%BDS%\bin\bds.exe`만 실행한다.
3. Component → Install Packages 를 연다.
4. Add 로 Win32 BPL만 고른다. 이 키는 `Known Packages`다.
5. 확인한 뒤 Tools 또는 View → RAD Agent 로 도킹 Chat을 연다.

Win64 BPL을 이 대화상자에 넣지 않는다.

디버그 호스트는 그 BPL과 같은 비트의 `bds.exe`이고, 파라미터는 `-pDelphi`다.

## 설치 파일 만들기

`scripts\package.ps1`이 설치 파일 `dist\RADAgent-Setup-<버전>.exe`를 만든다. RAD Studio를 모두 닫고 실행한다.

```powershell
scripts\package.ps1                  # 이 PC에 설치된 지원 릴리스 전부, 서명
scripts\package.ps1 -Versions 37.0   # RAD Studio 13만
scripts\package.ps1 -NoSign          # 서명 없는 시험용
```

하는 일:

1. 릴리스마다 Win32(64-bit IDE가 있으면 Win64도)를 `build.ps1`로 빌드한다. 구버전 BPL은 그 릴리스가 설치된 PC에서만 만들 수 있다.
2. `artifacts\package\payload\<BDS 버전>\<Win32|Win64>\`에 BPL, `RADAgent\chat\`, 그 비트의 `WebView2Loader.dll`(Microsoft 서명 확인)을 모은다.
3. BPL에 Nanum Space 인증서로 서명하고 타임스탬프를 붙인다(SHA-256, GlobalSign RFC 3161).
4. omp: `RADAgent.OmpProbe`의 `TestedOmpVersion`(검증 버전)과 GitHub가 공개한 그 릴리스 `omp-windows-x64.exe`의 SHA-256을 설치 파일에 넣는다. 설치할 때 omp가 없으면 그 파일을 받아 해시를 확인하고 `%LOCALAPPDATA%\omp`에 둔다.
5. Inno Setup 6(`installer\RADAgent.iss`)으로 설치 파일을 만들고, 설치 파일과 제거 프로그램에도 같은 인증서로 서명한다. 서명과 타임스탬프를 확인한 뒤 SHA-256을 출력한다.

버전은 `src\RADAgent.dproj`의 버전 정보(`VerInfo_*`)다. 회사 이름과 저작권도 거기 있다.

### 서명 준비 (이 PC에 한 번)

- Nanum Space EV 코드 서명 인증서가 든 SafeNet USB 토큰을 꽂는다. SafeNet Authentication Client가 인증서를 `CurrentUser\My`에 둔다(지문 `3CE49DE1124F325082FA90BDE4944756D1626251`).
- `scripts\release\set-signing-pin.ps1`: 토큰 PIN을 Windows 자격 증명 관리자(`RADAgent.CodeSign.TokenPin`, 현재 사용자)에 넣고 바로 확인한다. PIN은 명령줄·파일·로그에 남지 않는다.
- `scripts\release\enable-sac-single-logon.ps1`: SafeNet "Single Logon"을 켜 로그온 세션마다 PIN을 한 번만 쓰게 한다(관리자 권한, 로그오프 후 적용).
- Windows SDK의 `signtool.exe`, Inno Setup 6(`winget install JRSoftware.InnoSetup`).

PIN이 틀려 토큰 잠금 해제가 실패하면 한 시간 동안 다시 시도하지 않는다(토큰 PIN 재시도 횟수 보호). PIN을 확인한 뒤 `set-signing-pin.ps1`을 다시 실행한다.

