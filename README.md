# RADAgent

**RADAgent — an agentic coding assistant for Delphi, powered by oh-my-pi**

RAD Studio 13.2 IDE 안의 design-time BPL이다. 에이전트 루프는 설치된 omp(검증 버전 18.2.11)이고, Delphi로 다시 만들지 않는다. 도킹 창은 Tools 또는 View 메뉴의 RADAgent다. 이어서 할 일은 [docs/continue.md](docs/continue.md)에 적어 두었다.

## 언어

화면 언어는 English, 日本語, Deutsch, Français(RAD Studio가 제공하는 언어)와 한국어다. 처음 값은 Windows 표시 언어이고, 그 언어가 없으면 영어다. 설정 → 채팅 표시 → Language에서 바꾸면 채팅 창이 바로 그 언어로 다시 그려진다. 문자열은 `src\lang\<코드>.json`(RCDATA로 BPL에 들어감)에 있고, 코드에서는 `RADAgent.Lang`의 `Tr`/`TrF`, 채팅 페이지에서는 `T()`와 `data-i18n`으로 부른다. 번역이 없는 키는 영어로 보인다.

## DelphiAgent에서 옮기기

이전 이름은 DelphiAgent였다. 새 BPL(`RADAgent370.bpl`)을 등록하고 옛 `DelphiAgent370.bpl` 등록은 지운다(두 IDE 모두). 처음 실행할 때 다음을 새 이름으로 옮긴다: IDE 레지스트리 설정(`...\DelphiAgent` → `...\RADAgent`), 프로젝트 `.omp\delphiagent.yml` → `.omp\radagent.yml`, `/btw` 메모(`%LOCALAPPDATA%\DelphiAgent\btw`), git 체크포인트 ref(`refs/delphiagent/` → `refs/radagent/`).

## 요구사항

- Windows. RAD Studio 13.2 (BDS 37.0) 32-bit IDE와 64-bit IDE.
- `%BDS%` 기본값: `C:\Program Files (x86)\Embarcadero\Studio\37.0`
- 32-bit IDE: `%BDS%\bin\bds.exe`. 그 IDE 안의 DelphiLSP는 `%BDS%\bin\DelphiLSP.exe`이며, omp는 이 파일을 쓰지 않는다.
- 64-bit IDE: `%BDS%\bin64\bds.exe`. omp가 쓸 DelphiLSP는 항상 `%BDS%\bin64\DelphiLSP.exe`다.
- `omp`: 검증 버전 18.2.11. PATH에 없으면 `%LOCALAPPDATA%\omp\omp.exe`. 진입점: `omp --mode rpc`. 다른 버전은 아래 "omp 업데이트"대로 확인한다.

DelphiLSP.exe는 IDE 설치본만 사용한다. 이 저장소에 복사하지 않는다. BPL은 `DelphiLSP.exe`를 실행하지 않는다. omp가 `templates/omp.lsp.json`을 활성 프로젝트의 `.omp/lsp.json`으로 펼쳐 별도 프로세스로 띄운다. 절차는 [docs/lsp-setup.md](docs/lsp-setup.md)다.

## BPL 설치 위치

한 BPL을 양쪽 IDE에 등록하지 않는다. 클릭 경로는 [docs/install.md](docs/install.md)와 같다.

| IDE | 출력 | 레지스트리 |
| --- | --- | --- |
| Win32 (`bin\bds.exe`) | `$(BDSCOMMONDIR)\Bpl\RADAgent370.bpl` | `HKCU\Software\Embarcadero\BDS\37.0\Known Packages` |
| Win64 (`bin64\bds.exe`) | `$(BDSCOMMONDIR)\Bpl\Win64\RADAgent370.bpl` | `HKCU\Software\Embarcadero\BDS\37.0\Known Packages x64` |

### 64-bit IDE 설치

1. 64-bit IDE가 켜져 있으면 종료한다.
2. `scripts\build-win64.cmd`를 실행한다.
3. `%BDS%\bin64\bds.exe`를 실행한다.
4. Component → Install Packages → Add 에서 `$(BDSCOMMONDIR)\Bpl\Win64\RADAgent370.bpl`만 고른다.
5. Tools 또는 View → RADAgent 로 도킹 Chat을 연다. RAD Studio 13.2의 View 메뉴 이름은 `ViewsMenu`다.

### 32-bit IDE 설치

1. 32-bit IDE가 켜져 있으면 종료한다.
2. `scripts\build-win32.cmd`를 실행한다.
3. `%BDS%\bin\bds.exe`를 실행한다.
4. Component → Install Packages → Add 에서 `$(BDSCOMMONDIR)\Bpl\RADAgent370.bpl`만 고른다.
5. Tools 또는 View → RADAgent 로 도킹 Chat을 연다.

`%BDS%`가 없고 `C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat`도 없으면 빌드 스크립트는 `call rsvars.bat` 단계에서 실패한다. 그 경우 가정한 경로는 `C:\Program Files (x86)\Embarcadero\Studio\37.0`이다.

## 파일 저장과 git 체크포인트

일반적인 agentic coding처럼 디스크가 기준이다.

- 메시지를 보내기 직전과 승인된 `rad.*` 변경(폼, 모듈, 캐럿 삽입) 직후에 프로젝트의 저장 안 한 파일을 저장한다.
- omp는 자기 read/edit/write 도구로 파일을 고치고, 도구가 끝날 때마다 IDE가 바뀐 파일을 다시 읽는다. 그 사이 사용자가 같은 파일을 고치고 있었으면 덮어쓰지 않고 채팅에 충돌을 알린다.
- 폼(`.dfm`)과 프로젝트 파일은 omp가 텍스트로 고치지 않고 `rad.form_*`/`rad.new_module`로만 바꾼다. 폼 디자이너와 디버거는 그대로 쓴다.
- 프로젝트 폴더가 git 저장소가 아니면 처음 omp를 시작할 때 `git init`, Delphi `.gitignore`, 첫 커밋을 만든다. git이 없으면 알리고 체크포인트만 끈다.
- 메시지마다 보내기 직전 상태를 체크포인트 커밋으로 남긴다(`refs/radagent/cp/`). 사용자의 브랜치·index·HEAD는 바뀌지 않는다.
- 채팅의 내 메시지에 마우스를 올리면:
  - `↶ 여기로 되돌리기`: 파일을 그 메시지 전 상태로 되돌리고(그 뒤에 생긴 파일은 지움), omp 대화도 그 메시지 앞에서 갈라진다. 메시지는 입력칸으로 돌아온다. 되돌리기 전 상태는 `refs/radagent/before-restore/`에 남는다.
  - `⑂ 여기서 브랜치`: 같은 되돌리기에 더해 그 체크포인트에서 `radagent/<시각>` git 브랜치를 만들어 옮겨 간다.
- omp가 일하는 중에는 되돌리지 않는다. IDE 실행 취소(Ctrl+Z)는 디스크에서 다시 읽은 뒤에는 이어지지 않으므로 되돌리기는 체크포인트로 한다.
- 프로젝트가 git 저장소가 되면 IDE의 Git 연동도 켜진다. Tools → Options → Version Control → Git의 실행 파일이 `git-cmd.exe`이면 IDE가 에디터 오른쪽 클릭 메뉴를 만들다 멈춘다(`git-cmd`가 `cmd /K`로 끝나지 않음). `C:\Program Files\Git\cmd\git.exe`로 지정한다.

## omp 업데이트

omp가 업데이트돼도 RADAgent가 계속 동작하도록 다음을 한다.

- **자동 호환성 검사**: IDE에서 omp를 처음 시작할 때 `omp --version`이 마지막으로 통과한 버전과 다르면, 뒤에서 호환성 검사를 한 번 돌린다. 모델은 부르지 않고 세션도 저장하지 않는다. 검사 항목은 다음과 같다.
  - RADAgent가 쓰는 명령줄 옵션
  - RPC 시작과 프로토콜
  - `rad.*` 도구 등록과 xd:// 장치 연결
  - `get_state`, 명령 목록, 생각 수준 응답
  - `config list --json`

  모두 통과하면 그 버전을 기억한다. 검증 버전(18.2.11)과 다르면 채팅에 "통과"를 한 번 알린다. 실패하면 무엇이 깨졌는지 경고한다. 설정 → 고급 → `omp 호환성 검사`로 언제든 다시 볼 수 있다.
- **프로토콜**: omp가 RPC v2를 제공하면 v2로 협상해 1MiB가 넘는 응답도 조각(`rpc_chunk`)으로 잃지 않고 받는다. 둘 다 없으면 이유를 보여 주고 연결하지 않는다.
- **시작 실패 이유**: omp가 모르는 옵션 등으로 바로 끝나면, 오류 대신 omp가 stderr에 남긴 마지막 줄(예: `Error: unknown flag: --x`)을 보여 준다.
- **omp가 혼자 끝낸 명령**: `/context` 같은 omp 내장 명령은 출력(`command_output`)을 채팅에 그대로 보여 주고, `agentInvoked: false`로 턴을 끝낸다. 작업 중 표시가 멈춰 있지 않는다.
- **승인 문구**: omp 승인 요청은 문서화된 `Allow tool:` 제목과 선택지의 뜻(Approve/Allow/Deny/Reject…)으로 알아본다. 선택지 순서나 정확한 낱말에 기대지 않는다.
- **개발자**: omp를 올린 뒤 `scripts\build-tests.cmd`를 돌린다. 설치된 omp로 같은 호환성 검사(`omp probe:` 줄)와 핸드셰이크 실시험을 한다.

## 첫 검증 시나리오

- 빈 IDE에서 RADAgent를 열면 상태줄 둘째 줄이 `프로젝트 없음`이다.
- VCL 앱을 연 뒤 RADAgent를 열면 둘째 줄에 `프로젝트 <이름> · pid <번호> · <폴더>`가 보인다.
- 채팅 창이 포커스여도 그 프로젝트 이름은 유지된다.
- `/clear` 뒤에 일반 질문을 보내고, 컴파일 버튼을 누르면 채팅에 `컴파일 성공`이 찍힌다.

컴파일 오류는 메시지 뷰에서 확인한다. 빌드 대화상자만으로 성공을 단정하지 않는다.

## 채팅에서 쓸 수 있는 것

채팅 기록은 WebView2 화면이다. 모델 답은 마크다운(표, 코드 블록과 Pascal 강조, 목록, 링크)으로 보이고, 코드 블록에는 복사 버튼이 있다. `MainForm.pas(37)` 같은 파일 위치를 누르면 에디터가 그 줄을 연다. omp가 부르는 도구는 접힌 줄로 보이고, 끝나면 ✓/✗와 걸린 시간이 붙는다. 펼치면 결과가 보인다.

상태줄 첫째 줄은 `● 연결됨 · 모델 · 컨텍스트 % · 지금 하는 일 · 경과 초`, 둘째 줄은 프로젝트, omp pid, 폴더다. 중지 버튼은 omp가 일할 때만 켜진다.

입력칸은 여러 줄이다. Enter는 보내기, Shift+Enter는 줄바꿈, 첫 줄에서 ↑는 이전에 보낸 문장이다. `/`를 치면 omp 명령 목록이 뜨고 Tab/Enter로 고른다. 입력칸 위 줄은 활성 파일, 선택한 줄, 저장 안 한 파일 수다. `선택 영역 포함`을 켜면 선택한 코드가 프롬프트에 붙는다.

채팅 창 전체가 WebView2 페이지다(Claude Desktop과 비슷한 배치). View 메뉴의 RADAgent 항목에는 `resources\MenuIcon-16/32.png` 아이콘이 붙는다(IDE 이미지 목록에 두 크기로 넣어 고DPI에서 선명하다). IDE 오른쪽 클릭 메뉴는 자기 이미지 목록만 그리므로 글자만 있다.

- 위 막대: 세션 제목(누르면 세션 목록), 프로젝트, `＋` 새 세션, `⤓` HTML 내보내기, `⚙` 설정.
- 가운데: 가운데 정렬된 한 칸. 내 메시지는 오른쪽 말풍선, 답은 테두리 없는 본문. 답 사이의 도구·생각은 `도구 N개 사용 ›` 한 줄로 묶이고 펼치면 도구별 입력과 결과가 보인다. 승인 후 버퍼에 반영된 편집은 파일 카드(`+N -M`, 누르면 에디터에서 그 줄로)로 보인다. 작업 중에는 끝에 `✳ 생각하는 중 · N초`.
- 입력 상자: Enter 보내기, Shift+Enter 줄바꿈, ↑ 이전 문장, `/` 명령 목록. 작업 중에는 보내기 단추가 중지(■)로 바뀐다. 작업 중 표시는 지금 모델을 만든 회사의 로고다(Claude·OpenAI는 돌고, 나머지는 맥박). 아래 줄의 모델 단추는 로고와 이름을 보이고, 누르면 provider별로 묶인 목록과 검색 칸이 뜬다. 답을 한 모델이 바뀌면 답 위에 로고와 모델 이름이 붙고, 모델 대체 알림에도 로고가 붙는다. 설정의 모델·로그인·역할별 모델 목록과 `/model` 창에도 로고가 있다. 로고 규칙은 `src\chat\brands\brands.json` 하나다(provider → 서비스 로고, 모델 이름 → 제작사 로고). 중지는 omp에 abort를 보내고, 5초 안에 턴이 끝나지 않거나 한 번 더 누르면 omp를 강제로 끝내고 같은 대화로 다시 시작한다(응답하지 않는 omp 대비). 위에 활성 파일, `+ 선택 N–M줄`(누르면 선택 영역을 붙임), 저장 안 한 파일 수.
- 입력 아래 줄: `＋` 메뉴(아래), 승인 방식(항상 묻기·쓰기 허용·권한 무시, omp 도구와 IDE 변경에 함께 적용, 이 프로젝트에 저장하고 omp를 같은 세션으로 다시 시작), 모델, 생각 수준, 컨텍스트 사용량 원, 연결 점.

IDE 기능을 omp에 맞춰 넘긴다:

- 프로젝트를 보고 도구를 고른다. 폼이 있을 때만 폼 도구를 등록하고, VCL/FMX와 Delphi/C++Builder에 맞는 사용법을 준다. 도구 사용법은 시스템 프롬프트에 들어 있어 omp가 따로 읽지 않는다.
- 프로젝트 안내(언어, 프레임워크, 폼 목록, 작업 규칙)를 omp 시스템 프롬프트에 덧붙인다.
- Delphi 프로젝트에 `<프로젝트>.delphilsp.json`이 있으면 `.omp/lsp.json`을 만들어 DelphiLSP를 연결한다. 없으면 IDE의 Generate LSP Config를 켜라고 한 번 알린다. C++Builder 프로젝트는 omp에 쓸 LSP가 없다(아래 C++Builder 절).
- 묶음 도구: `rad.form_apply`(컴포넌트 추가·속성·이벤트를 한 번에, 승인 한 번).
- 프로젝트 도구: `rad.project_info`, `rad.set_build_config`(구성·플랫폼), `rad.new_module`(폼·프레임·데이터 모듈·유닛), `rad.list_components`(팔레트 클래스).
- 승인 방식 하나로 omp 도구와 IDE 변경을 함께 정한다: 항상 묻기(IDE 변경마다 승인), 쓰기 허용(턴마다 한 번 승인), 권한 무시(묻지 않음, 처음 값). 어느 쪽이든 저장은 하지 않는다. `rad.*` 호출에 대한 omp 자체 확인은 RADAgent가 대신 통과시켜 두 번 묻지 않는다.
- 계획: 네 번째 승인 방식. omp를 always-ask로 다시 시작하고 디스크 도구는 거부, 바꾸는 `rad.*` 도구는 빼고 `rad.submit_plan`만 준다. 계획서는 `<프로젝트>\docs\plans\yyyy-mm-dd-hhnn-<slug>.md`(목표 / 현재 상태 / 단계 / 바뀔 파일 / 위험 / 확인 방법)로 쓰이고 채팅에 계획 카드가 뜬다. `이 계획대로 진행`은 이전 승인 방식으로 돌아가 `@계획서`로 구현을 시작한다. `docs` 아래 파일은 프로젝트에 추가되어 Project Manager에 보인다(프로젝트 파일은 저장하지 않음).
- 입력에서 `@`를 치면 프로젝트 폴더 파일 목록이 뜬다. 보내기 전에 저장하므로 `@경로`는 IDE에 보이는 내용이다.
- `/btw <질문>`: 곁가지 질문. 지금 대화를 복제(`--fork`)한 별도 omp 자식이 도구 없이 답하므로 에이전트가 작업 중이어도 되고, 본 대화에는 들어가지 않는다. 여러 번, 여러 주제를 물을 수 있다. 답은 채팅에 접힌 `BTW` 카드로 뜨고(이어 묻기·복사·메모에서 보기·중지), 모든 주제는 위 막대의 `BTW` 메모 창에 따로 남는다(검색, `이 대화만`, 이어 묻기, 삭제). `/btw`만 치면 메모 창이 열린다. 이어 묻기는 그 주제 자신의 세션(`--resume`)으로 이어 가므로, 처음 물은 시점의 대화 맥락과 그 주제의 앞 문답을 본다. 메모는 프로젝트 밖 `%LOCALAPPDATA%\RADAgent\btw\<프로젝트>\`에 저장된다.
- 하위 에이전트(task)는 `rad.*`를 볼 수 없다. 서로 다른 `.pas` 파일을 맡으면 디스크에서 동시에 고칠 수 있고, 폼·프로젝트 파일과 컴파일은 메인 세션이 한다(프로젝트 안내문에 적힘). 더 나아간 병렬 방안은 [docs/plans/2026-09-24-0930-parallel-subagents.md](docs/plans/2026-09-24-0930-parallel-subagents.md)에 있다.

`＋` 메뉴:

- 파일 또는 사진 추가: 여러 개 선택. 600KB 이하 사진(png, jpg, gif, webp)은 프롬프트 이미지로 보내고, 나머지는 경로를 붙인다. 입력 위 칩의 ✕로 뺀다.
- 폴더 추가: omp `/add-dir`로 이 세션의 작업 폴더를 더한다.
- 커넥터: 설정된 MCP 서버와 켜기/끄기 스위치. omp `/mcp enable|disable`로 바로 바꾼다. `커넥터 관리`는 설정 창 확장 탭.
- 플러그인: `omp plugin list`의 플러그인과 확장 모듈, 켜기/끄기 스위치. 플러그인은 `omp plugin enable|disable`, 확장 모듈은 이 프로젝트의 `disabledExtensions`에 쓰고 omp를 같은 세션으로 다시 시작한다.
- 프로젝트 컴파일.

색은 IDE 테마를 따르고, 테마를 바꾸면 채팅도 바뀐다.

채팅에는 답 말고도 omp 진행 내용이 보인다: 생각(접힘), 모델이 쓰는 도구 입력, 도구 실행 중 출력, 하위 에이전트, 위쪽 작업 목록, 재시도·모델 대체. `설정` 창에서 항목마다 켜고 끈다.

`설정` 창:

- 채팅 표시: 위 항목, 글자 크기, 고대비. 바로 적용.
- 계정·모델: 지금 대화의 모델과 생각 수준, OAuth 로그인. RPC로 바로 적용. API 키가 필요한 공급자는 터미널 omp의 `/login`을 쓴다.
- 역할별 모델, 확장(스킬·확장·하위 에이전트 켜고 끄기, MCP 목록), 고급(omp 도구 승인, 기본 생각 수준): 이 프로젝트에만 적용된다. `<프로젝트>\.omp\radagent.yml`에 저장하고 `--config`로 omp에 넘긴다. 전역 `~/.omp/agent/config.yml`은 바꾸지 않는다. 확인을 누르면 omp를 같은 세션으로 다시 시작할지 묻는다.
- 고급(이 PC): omp 실행 파일, 추가 인자, 작업 언어(켜면 생각·계획·하위 에이전트 지시는 영어, 답은 내 언어. 기본 꺼짐: 2026-09-24 측정에서 출력 토큰 차이가 없었다), `omp 호환성 검사` 단추.

에디터 오른쪽 클릭 메뉴에 `RADAgent: 선택 영역 설명/고치기`, 메시지 창 오른쪽 클릭 메뉴에 `RADAgent: 빌드 오류 고치기`가 있다. 승인이 필요하거나 답이 끝났을 때 IDE가 뒤에 있으면 작업 표시줄 단추가 깜빡인다. 채팅 창을 닫거나 디버그 레이아웃으로 바뀌어도 대화와 omp는 그대로다.

승인은 채팅 안의 카드로 묻는다. 바뀌는 줄 diff(빨강 삭제, 초록 추가, 앞뒤 3줄)와 승인/거부 단추가 있고, 중지를 누르면 떠 있는 카드는 거부된다. 채팅 페이지가 없을 때(WebView2 실패)만 모달 승인 창을 쓴다.

`/model`은 omp가 준 목록으로 모델을 고른다. `/fast`, `/thinking`, `/effort`는 모달에서 고른 뒤 기존 RPC만 보낸다. `/clear`는 확인 후 새 세션이다. 그 외 `/`로 시작하는 문장은 omp에 원문 그대로 넘긴다. `파일` 버튼은 고른 경로를 입력칸에 붙인다. `@file`은 쓰지 않는다.

IDE 도구는 `rad.compile`, `rad.open_buffer`, `rad.insert_at_caret`이다. 코드는 omp가 자기 read/edit/write 도구로 디스크에서 고치고, IDE가 다시 읽는다.

디버거 읽기 도구는 `rad.debug_state`, `rad.debug_stack`, `rad.debug_evaluate`, `rad.debug_breakpoints`이다. 식 평가는 부작용 없이 한다. 실행 제어 도구는 `rad.debug_run`(실행 또는 계속), `rad.debug_step`(over, into, return), `rad.debug_pause`, `rad.debug_reset`, `rad.debug_add_breakpoint`이다. 모두 승인 창에서 승인해야 동작하고, 끝나면 디버거 상태를 돌려준다. 디버기 메모리는 쓰지 않는다.

폼 디자이너 도구는 `rad.form_components`, `rad.form_properties`, `rad.form_screenshot`(읽기), `rad.form_set_property`, `rad.form_add_component`, `rad.form_delete_component`, `rad.form_rename_component`, `rad.form_set_event`이다. 바꾸는 도구는 승인한 뒤에 디자이너에만 반영하고 저장하지 않는다. 필드 선언과 이벤트 메서드는 디자이너가 유닛 버퍼에 고친다(C++ 이벤트 메서드는 RADAgent가 쓴다).

- `rad.form_screenshot`: 디자이너에 보이는 폼을 PNG로 돌려준다(VCL은 폼이 직접 그리고, FMX는 디자이너 창을 화면에서 복사한다). 레이아웃을 바꾼 뒤 모델이 겹침·정렬·잘린 글자를 눈으로 확인한다.
- `rad.form_text_edit`: 여러 폼·여러 컴포넌트의 속성을 한 번에 바꿀 때 `.dfm/.fmx` 텍스트를 고친다. 편집은 정확한 old/new 텍스트이고, object/inherited/end 줄은 바꿀 수 없어 컴포넌트 추가·삭제·이름 변경과 이벤트는 여전히 디자이너로 한다. 고친 텍스트가 폼 구문으로 읽히는지, 새 속성이 실제 컴포넌트에 있는지 검사한 뒤 전체 diff를 한 번 승인받고, 파일 인코딩을 지켜 쓰고 IDE가 폼을 다시 읽는다. 바이너리 폼 파일은 거절한다.

RPC 원문은 `%TEMP%\RADAgent\rpc.log`에만 남긴다. 채팅 로그에는 사용자 문장과 모델 응답만 보인다.

## C++Builder 프로젝트

`.cbproj`(VCL, FMX)도 Delphi 프로젝트와 같은 도구를 쓴다. 폼 도구, `rad.form_apply`, `rad.new_module`, `rad.compile`, 디버거(중단점, 호출 스택, C++ 식 평가), 체크포인트가 C++에서 동작한다.

- 이벤트 핸들러: C++ 디자이너는 이벤트를 연결해도 코드를 쓰지 않는다. 그래서 RADAgent가 C++ IDE와 같은 모양으로 `.h`의 `__published`에 `void __fastcall 이름(인자);`를, `.cpp`에 본문을 쓴 뒤 연결한다. 인자는 이벤트 형식에서 만든다(`TObject *Sender` 등). IDE는 저장할 때 본문이 빈 핸들러를 지우고 연결도 끊으므로, 새 핸들러 본문에는 주석 한 줄을 넣는다(Delphi도 같다).
- 새 모듈: `rad.new_module`은 `UnitN.cpp/.h`(Delphi는 `UnitN.pas`)를 이름을 정해 만든다. 폼 이름을 주어도(`AboutForm`) 클래스 이름이 맞는 소스를 직접 준다. IDE 기본 소스는 이름을 바꾸면 폼을 열지 못한다.
- 컴파일 오류: IDE는 C++ 오류를 Messages 창에만 보이고 Error Insight에도 없다. 빌드가 실패하면 활성 플랫폼의 컴파일러(Win64x `bcc64x`, Win64 `bcc64`, Win32 `bcc32c`)로 지난 성공 빌드 뒤 바뀐 `.cpp`(와 바뀐 헤더를 쓰는 `.cpp`)를 한 번 더 컴파일해 파일·줄·열·메시지를 돌려준다. 링크 오류는 Messages 창을 보라고 알린다.
- LSP (clangd): RAD Studio에는 omp가 쓸 C++ LSP가 없다(설치본 `cquery.exe`는 LLVM 5 기반이라 VCL 헤더에서 멈춘다). 설정 → 고급 → `clangd 설치`를 누르면 최신 Windows용 [clangd](https://github.com/clangd/clangd/releases)(LLVM, Apache-2.0, 약 30MB)를 `%LOCALAPPDATA%\RADAgent\clangd\<버전>`에 받아 경로를 채운다(다시 누르면 업데이트, 확인을 누르면 omp를 다시 시작). 직접 설치해 경로를 넣거나 PATH에 두어도 된다. 그러면 omp를 시작할 때 `.omp\clangd\compile_commands.json`과 `.omp\lsp.json`을 만든다. 컴파일 옵션은 활성 플랫폼 컴파일러가 실제로 쓰는 헤더·타깃·표준·매크로(`-###`, `-dM -E`)와 프로젝트 IncludePath·Defines에 `-D__published=public`을 더한 것이다. Win32(bcc32c)는 `i686-pc-windows-msvc`, Win64x(bcc64x)는 `x86_64-w64-windows-gnu`로 읽는다. clangd가 없으면 한 번 알리고 grep/read로 찾는다.
  - 되는 것: 정의·선언 이동(`.h`↔`.cpp`, VCL 헤더), 참조(열린 파일 기준), 필드·형식 정보, 오타·없는 멤버·인자 형식 같은 실제 오류.
  - 안 되는 것: 일반 clangd는 `__property`를 몰라 VCL 속성(Caption 등)의 정보·이동이 없다. `System.hpp`의 `__property` 오류와 폼 생성자 `TForm` 오류(Win32는 생성자 `fastcall` 오류도)가 늘 나오며, omp 안내문에 무시하라고 적는다. 최종 확인은 `rad.compile`이다.
  - 프로젝트에 `.cache\`가 생기지 않게 백그라운드 색인은 끈다. 그래서 참조는 열린 파일 기준이다.
- 시험 프로젝트: `scripts\prepare-smoke-cpp.cmd`가 `tests\smoke-cpp`를 `%TEMP%\RADAgentSmokeCpp\SmokeCpp.cbproj`로 복사한다. 64-bit IDE는 처음 열 때 플랫폼을 Windows 64-bit (Modern)로 바꾼다.

## 고지

- Powered by [oh-my-pi](https://github.com/can1357/oh-my-pi) (MIT). RADAgent는 omp를 함께 배포하지 않고, 사용자가 설치한 omp를 실행한다.
- Provider and model logos are trademarks of their owners; the icons come from [lobe-icons](https://github.com/lobehub/lobe-icons) (MIT).
- Delphi and RAD Studio are registered trademarks of Embarcadero Technologies, Inc. RADAgent is an independent project, not affiliated with or endorsed by Embarcadero.
