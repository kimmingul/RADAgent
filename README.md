# DelphiAgent

RAD Studio 13.2 IDE 안의 design-time BPL이다. 에이전트 루프는 설치된 omp 18.2.8이고, Delphi로 다시 만들지 않는다. 도킹 창은 Tools 또는 View 메뉴의 DelphiAgent다. 이어서 할 일은 [docs/continue.md](docs/continue.md)에 적어 두었다.

## 요구사항

- Windows. RAD Studio 13.2 (BDS 37.0) 32-bit IDE와 64-bit IDE.
- `%BDS%` 기본값: `C:\Program Files (x86)\Embarcadero\Studio\37.0`
- 32-bit IDE: `%BDS%\bin\bds.exe`. 그 IDE 안의 DelphiLSP는 `%BDS%\bin\DelphiLSP.exe`이며, omp는 이 파일을 쓰지 않는다.
- 64-bit IDE: `%BDS%\bin64\bds.exe`. omp가 쓸 DelphiLSP는 항상 `%BDS%\bin64\DelphiLSP.exe`다.
- `omp` 18.2.8. PATH에 없으면 `%LOCALAPPDATA%\omp\omp.exe`. 진입점: `omp --mode rpc`

DelphiLSP.exe는 IDE 설치본만 사용한다. 이 저장소에 복사하지 않는다. BPL은 `DelphiLSP.exe`를 실행하지 않는다. omp가 `templates/omp.lsp.json`을 활성 프로젝트의 `.omp/lsp.json`으로 펼쳐 별도 프로세스로 띄운다. 절차는 [docs/lsp-setup.md](docs/lsp-setup.md)다.

## BPL 설치 위치

한 BPL을 양쪽 IDE에 등록하지 않는다. 클릭 경로는 [docs/install.md](docs/install.md)와 같다.

| IDE | 출력 | 레지스트리 |
| --- | --- | --- |
| Win32 (`bin\bds.exe`) | `$(BDSCOMMONDIR)\Bpl\DelphiAgent370.bpl` | `HKCU\Software\Embarcadero\BDS\37.0\Known Packages` |
| Win64 (`bin64\bds.exe`) | `$(BDSCOMMONDIR)\Bpl\Win64\DelphiAgent370.bpl` | `HKCU\Software\Embarcadero\BDS\37.0\Known Packages x64` |

### 64-bit IDE 설치

1. 64-bit IDE가 켜져 있으면 종료한다.
2. `scripts\build-win64.cmd`를 실행한다.
3. `%BDS%\bin64\bds.exe`를 실행한다.
4. Component → Install Packages → Add 에서 `$(BDSCOMMONDIR)\Bpl\Win64\DelphiAgent370.bpl`만 고른다.
5. Tools 또는 View → DelphiAgent 로 도킹 Chat을 연다. RAD Studio 13.2의 View 메뉴 이름은 `ViewsMenu`다.

### 32-bit IDE 설치

1. 32-bit IDE가 켜져 있으면 종료한다.
2. `scripts\build-win32.cmd`를 실행한다.
3. `%BDS%\bin\bds.exe`를 실행한다.
4. Component → Install Packages → Add 에서 `$(BDSCOMMONDIR)\Bpl\DelphiAgent370.bpl`만 고른다.
5. Tools 또는 View → DelphiAgent 로 도킹 Chat을 연다.

`%BDS%`가 없고 `C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat`도 없으면 빌드 스크립트는 `call rsvars.bat` 단계에서 실패한다. 그 경우 가정한 경로는 `C:\Program Files (x86)\Embarcadero\Studio\37.0`이다.

## 첫 검증 시나리오

- 빈 IDE에서 DelphiAgent를 열면 상태줄이 `프로젝트=없음`이다.
- VCL 앱을 연 뒤 DelphiAgent를 열면 `프로젝트=<이름> 폴더=<경로>`가 보인다.
- 채팅 창이 포커스여도 그 프로젝트 이름은 유지된다.
- `/clear` 뒤에 일반 질문을 보내고, 컴파일 버튼이 `ok`를 반환한다.

컴파일 오류는 메시지 뷰에서 확인한다. 빌드 대화상자만으로 성공을 단정하지 않는다.

## 채팅에서 쓸 수 있는 것

상태줄은 `[연결됨|대기|오류]  pid=  프로젝트=  폴더=`이다. 프로젝트가 없으면 `프로젝트=없음`과 빈 폴더를 숨기지 않고 보여 준다.

`/model`은 omp가 준 목록으로 모델을 고른다. `/fast`, `/thinking`, `/effort`는 모달에서 고른 뒤 기존 RPC만 보낸다. `/clear`는 확인 후 새 세션이다. 그 외 `/`로 시작하는 문장은 omp에 원문 그대로 넘긴다. `파일` 버튼은 고른 경로를 입력칸에 붙인다. `@file`은 쓰지 않는다.

IDE 도구는 `rad.compile`, `rad.open_buffer`, `rad.insert_at_caret`, `rad.list_dirty`, `rad.read_buffer`, `rad.apply_edit`이다. 버퍼를 고치는 도구는 적용을 누르기 전에는 쓰지 않고, 디스크에 자동 저장하지 않는다. 폼 디자이너와 디버거는 아직 없다.

RPC 원문은 `%TEMP%\DelphiAgent\rpc.log`에만 남긴다. 채팅 로그에는 사용자 문장과 모델 응답만 보인다.
