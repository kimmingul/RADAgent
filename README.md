# RAD Agent

**RAD Agent — an agentic coding assistant for Delphi, powered by oh-my-pi**

RAD Studio IDE 안에 도킹되는 AI 코딩 에이전트다. design-time 패키지(BPL)로 설치하고, 에이전트 루프는 사용자가 설치한 [oh-my-pi](https://github.com/can1357/oh-my-pi)(omp)가 맡는다. RAD Agent는 omp를 `omp --mode rpc` 자식 프로세스로 띄우고, 채팅 화면과 IDE 기능(에디터, 폼 디자이너, 컴파일, 디버거, 메시지 뷰)을 omp에 이어 준다. 창은 Tools 또는 View 메뉴의 RAD Agent다.

제품 페이지: https://kimmingul.github.io/RADAgent/ · 다운로드: [Releases](https://github.com/kimmingul/RADAgent/releases)

## 요구사항

- Windows, RAD Studio 13.2(BDS 37.0) 32-bit 또는 64-bit IDE. 10.4 Sydney, 11 Alexandria, 12 Athens도 빌드되게 맞춰 두었다(아래 "한계").
- omp. 검증 버전 18.2.11. 없으면 설치 프로그램이 그 버전을 GitHub에서 받아 `%LOCALAPPDATA%\omp\omp.exe`에 설치한다. RAD Agent는 PATH의 omp, 그다음 그 위치를 쓰고, 다른 경로는 설정에서 지정한다.
- Edge WebView2 런타임(Windows 10/11에 보통 들어 있다). 없으면 채팅은 글자 화면으로 동작한다.
- git(체크포인트용). 없으면 체크포인트만 꺼진다.
- 선택: C++Builder 프로젝트의 코드 탐색에 [clangd](https://github.com/clangd/clangd/releases). 설정 창에서 받아 설치할 수 있다.

## 설치

`RADAgent-Setup-<버전>.exe`(Nanum Space Co., Ltd. 서명)를 실행한다. 관리자 권한은 필요 없다.

1. RAD Studio를 모두 닫는다. 켜져 있으면 설치 프로그램이 닫으라고 한다.
2. 이 PC에 설치된 RAD Studio 중 설치 파일에 들어 있는 IDE가 목록에 나온다(13은 32비트·64비트 IDE 따로). RAD Agent를 넣을 IDE를 고른다.
3. 파일은 `%LOCALAPPDATA%\Programs\RADAgent\<BDS 버전>\<Win32|Win64>\`에 들어가고, 그 IDE의 `Known Packages`(64비트 IDE는 `Known Packages x64`)에 등록된다. 같은 이름의 다른 RAD Agent 등록은 지운다(두 개는 함께 로드되지 않는다).
4. omp가 없으면 설치 직전에 검증된 omp(18.2.11, 약 230MB)를 GitHub에서 받아 SHA-256을 확인한 뒤 `%LOCALAPPDATA%\omp`에 설치하고 사용자 PATH에 더한다. 받지 못하면 omp 없이 계속할지 묻는다. omp는 RAD Agent를 제거해도 남는다. WebView2 런타임이 없으면 마지막 화면에서 설치 페이지를 열 수 있다.
5. IDE를 켜고 Tools 또는 View → RAD Agent 로 창을 연다.

제거는 Windows 설정 → 앱에서 RAD Agent를 고른다. 등록과 파일을 지우고, RAD Agent 설정과 데이터(IDE 설정, `/btw` 메모, 받은 clangd, 채팅 브라우저 데이터)까지 지울지 묻는다.

소스에서 직접 빌드해 설치하는 방법과 설치 파일을 만드는 방법은 [docs/install.md](docs/install.md)에 있다.

| RAD Studio | BDS | 32-bit IDE BPL | 64-bit IDE BPL |
| --- | --- | --- | --- |
| 10.4 Sydney | 21.0 | `RADAgent270.bpl` | 없음 |
| 11 Alexandria | 22.0 | `RADAgent280.bpl` | 없음 |
| 12 Athens | 23.0 | `RADAgent290.bpl` | 없음 |
| 13 Florence | 37.0 | `RADAgent370.bpl` | `RADAgent370.bpl`(Win64) |

## 기능

### 채팅

- 모델 답은 마크다운(표, 코드 블록과 Pascal/C++ 강조, 목록, 링크)으로 보인다. 코드 블록은 복사할 수 있고, `MainForm.pas(37)` 같은 파일 위치를 누르면 에디터가 그 줄을 연다.
- 도구 호출은 `도구 N개 사용 ›` 한 줄로 묶이고, 펼치면 도구별 입력과 결과가 보인다. 생각, 도구 입력, 실행 중 출력, 하위 에이전트, 작업 목록, 재시도·모델 대체도 보이며 설정에서 항목마다 끌 수 있다.
- 작업 중 표시는 답하는 모델을 만든 회사의 로고다. 답한 모델이 바뀌면 답 위에 모델 이름이 붙는다.
- 위 막대: 세션 제목(누르면 세션 목록), 새 세션, HTML 내보내기, `BTW` 메모, 설정.
- 입력 상자: Enter 보내기, Shift+Enter 줄바꿈, ↑ 이전 문장, `/` 명령 목록, `@` 프로젝트 파일. 위에 활성 파일, 선택 영역(누르면 프롬프트에 붙음), 저장 안 한 파일 수가 보인다.
- 입력 아래 줄: `＋` 메뉴, 승인 방식, 모델(검색 가능한 목록), 생각 수준, 컨텍스트 사용량 원, 연결 점.
- omp가 작업하는 중에도 입력할 수 있다. Enter는 진행 중인 턴에 끼워 넣고(다음 단계에서 읽음), Ctrl+Enter는 턴이 끝난 뒤 보낸다. 입력이 비어 있으면 단추와 Esc는 중지다. 중지는 abort를 보내고, 5초 안에 끝나지 않거나 한 번 더 누르면 omp를 다시 시작해 같은 대화로 잇는다.
- `!명령`은 omp 셸에서 실행하고 출력이 채팅과 컨텍스트에 들어간다.
- 자동 재시도를 기다리는 알림에는 `재시도 취소`가 있다. 하위 에이전트 줄을 누르면 그 에이전트의 대화가 보인다.
- 컨텍스트 원을 누르면 사용량 패널이 뜬다: 컨텍스트 윈도우 사용률과 토큰, 이 세션의 입력·출력·캐시 토큰과 비용, 지금 공급자의 플랜 한도(5시간·주간·모델별 사용률과 재설정 시각). 제목 줄을 누르면 `/usage` 전체 보고서.
- 턴이 끝나면 답 아래에 끝난 시각과 걸린 시간(`완료 14:32:05 · 3분 12초`, 중지한 턴은 `중지 …`)이 보인다. 다시 불러온 대화와 지난 세션도 omp가 기록한 시각으로 같은 줄을 보여 주고, 내 메시지에 마우스를 올리면 보낸 시각이 보인다. 같은 내용이 IDE 메시지 창에도 한 줄 남는다.
- 승인이 필요하거나 답이 끝났을 때 IDE가 뒤에 있으면 작업 표시줄 단추가 깜빡이고, 답이 끝났으면 Windows 알림도 뜬다(누르면 IDE가 앞으로 온다, 설정에서 끌 수 있다). 채팅 창을 닫거나 디버그 레이아웃으로 바뀌어도 대화는 그대로다.
- 색은 IDE 테마를 따른다. 화면 언어는 English, 日本語, Deutsch, Français, 한국어(처음 값은 Windows 표시 언어).

### 명령

- omp가 제공하는 명령(`/usage`, `/context`, `/compact`, `/handoff`, `/mcp`, `/memory`, `/todo`, `/skill:*` 등)은 omp가 실행하고 결과가 채팅에 보인다.
- `/model`, `/fast`, `/thinking`은 선택 창을, `/new`는 확인 창을 띄운다.
- omp 터미널 화면에만 있는 명령은 RAD Agent가 처리한다:
  - `/clear`: 컨텍스트를 비우고 같은 이름으로 이어 간다. 이전 부분은 세션 목록에 남는다.
  - `/delete`: 확인 후 이 세션 파일을 지우고 새 세션.
  - `/resume`: 세션 목록. `/tree`: 세션 트리. `/branch`(`/rewind`), `/fork`: 고른 내 메시지 직전에서 대화를 갈라 그 메시지를 입력칸에 되돌린다.
  - `/copy`(마지막 답), `/copy code`(그 마지막 코드 블록), `/login [provider]`, `/restart`, `/settings`, `/extensions`, `/agents`, `/plan`, `/hotkeys`, `/hub`, `/queue <메시지>`.
  - `/version`: RAD Agent·omp·IDE 버전 한 줄(복사 버튼)과 릴리스 노트 링크. 문제를 알릴 때 붙인다.
- `/btw <질문>`: 곁가지 질문. 지금 대화를 복제한 별도 omp가 도구 없이 답하므로 작업 중에도 되고 본 대화에는 들어가지 않는다. 주제별로 이어 묻기, 검색, 삭제가 되는 메모 창에 남는다.

### IDE 연동

- 디스크가 기준이다. 보내기 직전과 IDE 변경 직후에 저장 안 한 파일을 저장한다. omp는 자기 도구로 디스크 파일을 고치고, IDE가 바뀐 파일을 다시 읽는다. 그 사이 사용자가 같은 파일을 고치고 있었으면 덮어쓰지 않고 충돌을 알린다.
- 프로젝트를 보고 omp에 줄 도구와 안내(언어, 프레임워크, 폼 목록, 작업 규칙)를 정한다. 폼이 있을 때만 폼 도구를 준다.
- RAD Studio 스킬: 언어에 맞는 `radstudio-delphi` 또는 `radstudio-cpp`(명명 규칙, 유닛·폼·프로젝트 파일 구조, 객체 수명, VCL/FMX 사용 패턴과 차이, 폼 디자이너 규칙)를 omp에 준다. 모델은 코드를 쓰거나 이름을 정하기 전에 읽고, 프로젝트 자체의 규칙(`AGENTS.md`, 기존 코드)이 우선한다. 컴포넌트 속성은 스킬에 적지 않고 `rad.form_properties`와 RAD Studio 설치본의 `source` 폴더에서 찾게 한다. 사용자가 설정한 `skills.customDirectories`는 그대로 유지된다.
- 코드 탐색: Delphi는 IDE가 만든 `<프로젝트>.delphilsp.json`이 있으면 DelphiLSP를 omp에 연결한다([docs/lsp-setup.md](docs/lsp-setup.md)). 없으면 Generate LSP Config를 켜라고 알린다.
- 폼 디자이너: 컴포넌트 목록·속성 읽기, 폼 스크린샷(모델이 레이아웃을 눈으로 확인), 속성 변경, 컴포넌트 추가·삭제·이름 변경(폼 자체 포함), 이벤트 연결, 여러 변경을 묶은 `rad.form_apply`. FMX 메뉴 항목·리스트 박스 항목처럼 항목 컨테이너 안의 컴포넌트도 부모 아래에 만든다. 여러 폼의 속성 일괄 변경은 `rad.form_text_edit`(속성 줄만, 구문·속성 이름 검사, 승인 한 번)로 하며, 설정에서 끌 수 있다.
- 비시각 컴포넌트(메뉴, 대화상자, 타이머, 액션·이미지 목록, 데이터 접근): 새로 만들면 폼 아래쪽 한 줄에 종류별로 모아 놓는다. 흩어진 폼은 `rad.form_arrange_nonvisual`로 한 번에 정리하고, 아이콘 위치(`Left`/`Top`)는 속성 도구와 폼 텍스트 편집으로도 바꿀 수 있다.
- UI 작성 방식(프로젝트 설정, 처음 값 "폼 디자이너 필수"): 폼·대화상자·메뉴·툴바·패널처럼 고정된 UI는 디자이너 도구로 만들고, 데이터에 따라 개수나 종류가 달라지는 컨트롤만 코드로 만들라고 omp에 안내한다. "자유"로 바꾸면 코드 작성도 허용한다.
- 새 모듈: `rad.new_module`로 폼·프레임·데이터 모듈·유닛을 추가한다. 유닛 이름은 필수이고 용도가 드러나야 한다: 프로젝트 네임스페이스(대부분의 유닛이 쓰는 접두사) 안에서 폼은 `Form`/`Dialog`, 프레임은 `Frame`, 데이터 모듈은 `DataModule`로 끝난다(`Nanum.UI.PivotSaveDialog`). `UnitN`은 받지 않는다. 기존 유닛은 `rad.rename_unit`으로 이름을 바꾸며, 폼 파일·프로젝트·다른 유닛의 `uses`가 함께 바뀐다.
- 디버거: 상태, 호출 스택, 부작용 없는 식 평가, 중단점 목록. 승인 후 실행·계속, 스텝, 일시 정지, 종료, 중단점 추가. 에이전트가 실행한 프로그램이 예외를 내면 예외 알림 창을 Break로 닫고, 예외 위치에 멈춘 채 메시지를 결과로 돌려준다.
- 에디터 오른쪽 클릭 메뉴 `RAD Agent: 선택 영역 설명/고치기`, 메시지 창 오른쪽 클릭 메뉴 `RAD Agent: 빌드 오류 고치기`.

### 승인과 체크포인트

- 승인 방식 하나로 omp 도구와 IDE 변경을 함께 정한다: 항상 묻기(변경마다), 쓰기 허용(턴마다 한 번), 권한 무시(묻지 않음, 처음 값). 승인은 채팅 안의 카드(줄 diff와 승인/거부)로 묻는다.
- 계획: 아무것도 바꾸지 않고 `<프로젝트>\docs\plans\`에 계획서를 쓴다. `이 계획대로 진행`을 누르면 이전 방식으로 돌아가 구현을 시작한다.
- 프로젝트 폴더가 git 저장소가 아니면 처음에 `git init`, Delphi `.gitignore`, 첫 커밋을 만든다.
- 메시지마다 보내기 직전 상태를 체크포인트(`refs/radagent/cp/`)로 남긴다. 사용자의 브랜치·index·HEAD는 바뀌지 않는다. 내 메시지에서 `↶ 여기로 되돌리기`(파일과 대화를 그 메시지 전으로) 또는 `⑂ 여기서 브랜치`(여기에 git 브랜치까지)를 고를 수 있고, 되돌리기 전 상태도 남는다.

### `＋` 메뉴와 설정

- `＋` 메뉴: 파일·사진 첨부(작은 사진은 이미지로 보냄), 작업 폴더 추가, MCP 서버 켜기/끄기, 플러그인·확장 켜기/끄기, 프로젝트 컴파일.
- 설정 창:
  - 채팅 표시: 보일 항목, 글자 크기, 고대비, 화면 언어, 작업 끝 Windows 알림.
  - 계정·모델: 모델, 생각 수준, OAuth 로그인.
  - 역할별 모델, 확장(스킬·확장·하위 에이전트, MCP 목록).
  - 고급(이 프로젝트): omp 도구 승인, 기본 생각 수준, UI 작성 방식, 폼 텍스트 편집, 자동 압축, 자동 재시도, 작업 중 메시지 처리 방식. omp 설정은 `<프로젝트>\.omp\radagent.yml`에 저장해 omp에 넘기며 전역 omp 설정은 바꾸지 않는다. UI 작성 방식과 폼 텍스트 편집은 `<프로젝트>\.omp\radagent-ide.json`에 저장한다.
  - 고급(이 PC): omp 실행 파일과 추가 인자, clangd 경로와 설치, omp 호환성 검사.
  - 창 아래쪽: RAD Agent 버전(IDE 비트), omp 버전, 릴리스 노트 링크.

### 버전 확인

- Help → About의 설치 제품 목록과 IDE 시작 화면에 `RAD Agent <버전>`이 나온다.
- 설정 창 아래쪽, `/version` 명령, `%TEMP%\RADAgent\rpc.log`의 `version` 줄에 RAD Agent·omp·IDE(`bds.exe`) 버전이 있다.
- 새 버전을 설치한 뒤 처음 채팅을 열면 한 번 "업데이트됨" 알림과 릴리스 노트 링크가 나온다.

### C++Builder

`.cbproj`(VCL, FMX)도 같은 도구를 쓴다.

- C++ 디자이너는 이벤트를 연결해도 코드를 쓰지 않으므로 RAD Agent가 `.h`의 선언과 `.cpp`의 본문을 쓴다.
- 빌드가 실패하면 바뀐 `.cpp`를 활성 플랫폼 컴파일러로 다시 컴파일해 파일·줄·메시지를 돌려준다.
- clangd가 있으면 컴파일러가 실제로 쓰는 헤더·타깃·매크로와 프로젝트 옵션으로 설정을 만들어 omp에 연결한다(정의 이동, 참조, 오류).

### omp 업데이트 대응

omp 버전이 바뀌면 처음 시작할 때 모델을 부르지 않는 호환성 검사를 뒤에서 한 번 한다(명령줄 옵션, RPC 프로토콜, `rad.*` 도구 등록, 응답 필드, 설정 키, 사용량 보고). 결과는 채팅에 알리고 설정에서 다시 볼 수 있다. omp가 RPC v2를 제공하면 1MiB가 넘는 응답도 잃지 않고 받는다.

## 한계

- **검증 범위**: RAD Studio 13.2와 omp 18.2.11에서 확인했다. 10.4·11·12는 빌드되게 맞췄을 뿐 아직 빌드·실행 확인을 하지 않았다. 10.3 이하는 도킹 창 API가 없어 지원하지 않는다.
- **구버전 차이**: 11·12에는 64-bit IDE가 없어 32-bit IDE만 쓴다. 10.4에서는 View 메뉴 항목에 아이콘이 없다. 64-bit DelphiLSP가 없는 릴리스에서는 32-bit `bin\DelphiLSP.exe`를 쓴다. C++ `bcc64x`(Win64x)는 12.1부터다.
- **DelphiLSP**: 정의 이동과 진단은 되지만 참조 검색과 hover는 DelphiLSP가 거절한다. 참조는 grep으로 찾는다.
- **clangd(C++)**: 일반 clangd는 `__property`를 몰라 VCL 속성의 정보·이동이 없고, `System.hpp`와 폼 생성자에서 늘 나는 오류가 있다(omp 안내문에 무시하라고 적는다). 참조는 열린 파일 기준이다. Win64(bcc64) 설정은 확인하지 않았다. 최종 확인은 컴파일이다.
- **omp 터미널 전용 명령**: `/goal`, `/loop`, `/vibe`, `/tan`, `/omfg`, `/cleanse`, `/plan-review`, `/collab`, `/join`, `/leave`, `/pause`, `/live`, `/record`, `/git`, `/debug`, `/setup`, `/skills`, `/logout`, `/open`은 omp가 RPC로 제공하지 않아 쓸 수 없다고 알린다. 터미널에서 omp를 실행해 쓴다.
- **대화 갈래**: `/tree`, `/branch`, `/fork`로 갈라지면 새 세션 파일로 이어지므로 `/tree`는 지금 세션 파일 안의 갈래만 보인다. 이 명령들은 파일을 되돌리지 않는다(파일까지는 메시지의 체크포인트).
- **사용량 패널**: 플랜 이름은 omp가 알려 주는 공급자만 보인다(Anthropic은 공급자 이름으로 대신한다). 한도는 omp가 보고하는 공급자만 나온다.
- **강제 중지**: 응답하지 않는 omp를 강제로 다시 시작하면 그 턴의 진행 중이던 내용은 사라진다.
- **폼 파일**: 폼과 프로젝트 파일은 omp의 일반 편집 도구로 고치지 않는다. 바이너리 폼 파일은 텍스트 일괄 수정 대상이 아니다.
- **FMX 폼 이벤트**: FMX 디자이너의 폼 클래스는 드래그 이벤트(`OnDragOver`, `OnDragDrop` 등)를 내놓지 않아 디자이너로 연결할 수 없다. 이때 도구는 연결 가능한 이벤트 목록을 돌려주고, 나머지는 `OnCreate`에서 코드로 연결하게 한다.
- **IDE Git 연동**: 체크포인트 때문에 프로젝트가 git 저장소가 되면 IDE의 Git 연동도 켜진다. Tools → Options → Version Control → Git의 실행 파일이 `git-cmd.exe`면 IDE가 에디터 오른쪽 클릭 메뉴에서 멈추므로 `C:\Program Files\Git\cmd\git.exe`로 지정한다.
- **로그**: RPC 원문은 `%TEMP%\RADAgent\rpc.log`에만 남는다(20MB가 넘으면 `rpc.1.log`로 돌린다).

## 개발

- 구조: [DESIGN.md](DESIGN.md). 규칙: [AGENTS.md](AGENTS.md). 향후 할 일: [docs/todo.md](docs/todo.md).
- 빌드: `scripts\build-win32.cmd`, `scripts\build-win64.cmd` (`-Version <ver>`로 릴리스 선택).
- 시험: `scripts\build-tests.cmd [-Version <ver>]`. 설치된 omp로 호환성 검사와 핸드셰이크까지 한다.
- 설치 파일: `scripts\package.ps1`(서명 포함). [docs/install.md](docs/install.md)의 "설치 파일 만들기".
- 시험 프로젝트: `scripts\prepare-smoke.cmd`(Delphi VCL), `scripts\prepare-smoke-cpp.cmd`(C++Builder).

## 라이선스

[MIT License](LICENSE). 개인·기업 모두 무료로 쓰고, 소스를 고치고, 다시 배포할 수 있다. 설치 프로그램은 이 라이선스를 보여 주고 동의를 받는다.

## 고지

- Powered by [oh-my-pi](https://github.com/can1357/oh-my-pi) (MIT). RAD Agent는 omp를 설치 파일에 담지 않는다. 사용자가 설치한 omp를 실행하고, 없으면 설치할 때 공식 릴리스를 받아 설치한다.
- Provider and model logos are trademarks of their owners; the icons come from [lobe-icons](https://github.com/lobehub/lobe-icons) (MIT).
- clangd is part of the LLVM project (Apache-2.0 with LLVM exception); RAD Agent downloads it only when the user asks.
- Delphi and RAD Studio are registered trademarks of Embarcadero Technologies, Inc. RAD Agent is an independent project, not affiliated with or endorsed by Embarcadero.
