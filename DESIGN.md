# RAD Agent 설계

design-time BPL이 RAD Studio IDE 안에서 Chat을 띄우고, omp 18.2.11 자식 프로세스에 JSONL RPC로 프롬프트를 넘긴다. 에이전트 루프, 도구 실행, LSP 세션은 omp가 소유한다.

## 아키텍처

```
+-------------------- bds.exe (32-bit 또는 64-bit, 하나만) --------------------+
| RAD Agent BPL (그 IDE와 같은 비트)                                         |
|                                                                              |
|  Wizard                                                                      |
|    Register 시 DockForm 등록                                                 |
|  DockForm (Chat 뷰, WebView2)  <-- 재표시 --  ChatSession (omp, 기록)        |
|    |  프롬프트 직전                                                           |
|    v                                                                         |
|  IdeFiles(저장) + GitRepo(체크포인트) --- IdeContext                          |
|    |  디스크가 기준                             활성 .dproj, 에디터 버퍼       |
|    v                                                                         |
|  RpcClient  ==== JSONL stdin/stdout ===>  omp --mode rpc                     |
|    ^                                         cwd = .dproj 디렉터리           |
|    |  host_tool_call / result                 tools + 자체 LSP               |
|  HostTools                                      |                            |
|    승인 후 IDE 변경, omp 디스크 편집은 다시 읽기 v                          |
|  Compile                                   DelphiLSP.exe                    |
|    BuildProject + CompileNotifier          omp가 기동한 별도 프로세스        |
|  메시지 뷰 (IOTAMessageServices)           IDE 안의 LSP에 attach 하지 않음   |
+------------------------------------------------------------------------------+
```

32-bit IDE는 Win32 BPL만, 64-bit IDE는 Win64 BPL만 로드한다.

## 모듈

| 모듈 | 책임 |
| --- | --- |
| Wizard | `IOTAWizard`. 패키지 `Register`에서 등록하고 IDE 종료 시 해제한다. |
| DockForm | `INTACustomDockableForm`의 Chat 프레임. WebView2 한 장만 담고 상태를 페이지에 보내며 페이지 요청을 처리한다. WebView2를 못 띄우면 글자 기록과 VCL 입력칸으로 대신한다. |
| ChatStatus | 위 막대와 입력 상자용 상태 메시지(연결, 모델, 생각 수준, 승인 방식, 컨텍스트, 하는 일, 세션 제목, 활성 파일·선택, 명령 목록). |
| ChatPageCommands | 페이지 요청(보내기, 중지, 승인 카드 답, 계획 진행, `@` 파일 목록, 세션, 내보내기, 설정, 컴파일, 파일 경로, 모델·생각 수준·승인 방식 변경, 링크) 처리. |
| ProjectProfile | 활성 프로젝트의 언어(Delphi, C++Builder), 프레임워크(VCL, FMX, 없음), 폼 목록. `rad.project_info`, `rad.set_build_config`, `rad.list_components`. |
| OmpLaunch | omp를 띄우기 전에 쓰는 파일(C++은 clangd 연결 포함): rad.* 문서를 시스템 프롬프트에 넣는 `omp-host-p<pid>.yml`(`tools.xdevInlineDevices`), 프로젝트 안내 `project-guide-p<pid>.md`(`--append-system-prompt`, 프로젝트의 UI 작성 방식 규칙 포함), Delphi 프로젝트의 `.omp/lsp.json`. |
| Skills | BPL 리소스의 RAD Studio 스킬(`src\skills\radstudio-delphi`, `radstudio-cpp`) 중 프로젝트 언어에 맞는 것을 `%TEMP%\RADAgent\skills\<언어>`에 쓰고, 사용자의 `skills.customDirectories` 뒤에 붙여 `--config`로 넘긴다. |
| HostToolDefs | 프로필에 맞춘 rad.* 목록: 폼이 있을 때만 폼 도구, VCL/FMX와 Delphi/C++ 문구. |
| FormBatch / ModuleCreator | `rad.form_apply`(폼 변경 묶음, 승인 한 번), `rad.new_module`(폼·프레임·데이터 모듈·유닛 추가, 파일 이름 `UnitN`을 정하고 폼 소스는 Delphi·C++ 모두 직접 준다). |
| FormShot | `rad.form_screenshot`: VCL은 `PaintTo`, FMX는 모듈과 디자이너를 보인 뒤 디자이너의 `FMTForm` 창(제목은 폼 `Caption`)을 화면에서 복사해 PNG. 도구 결과에 image 부분으로 보낸다. |
| FormText | `rad.form_text_edit`: 속성 줄만 텍스트로 일괄 수정, 구문(`ObjectTextToBinary`)과 속성 이름(살아 있는 컴포넌트) 검사, 승인 한 번, IdeFiles로 다시 읽기. |
| HandlerCode | 이벤트 핸들러 코드: Delphi는 디자이너 스텁에 주석 한 줄(빈 핸들러는 저장 때 지워짐), C++은 `.h` `__published` 선언과 `.cpp` 본문을 버퍼에 쓴다(C++ 디자이너는 코드를 쓰지 않음). |
| CppDiagnostics | C++ 빌드 실패 때 바뀐 `.cpp`를 활성 플랫폼 컴파일러(bcc64x/bcc64/bcc32c)로 다시 컴파일해 오류를 읽는다. |
| CppLsp | C++ 프로젝트의 clangd 연결: 활성 플랫폼 컴파일러의 헤더·타깃·매크로와 프로젝트 옵션으로 `.omp\clangd\compile_commands.json`, `.omp\lsp.json`. clangd는 설정 또는 PATH. |
| ClangdInstall | 설정 창의 clangd 설치: GitHub 최신 릴리스의 Windows zip을 뒤에서 받아 `%LOCALAPPDATA%\RADAgent\clangd\<버전>`에 푼다. |
| ProcessRun | 창 없이 콘솔 프로그램 실행과 출력 수집(git, C++ 컴파일러). |
| ChatExtensions | 입력 상자 `＋` 메뉴의 IDE 쪽: 첨부 파일·사진(prompt images), 작업 폴더 추가, MCP 서버와 플러그인 목록과 켜기/끄기. |
| ChatApproval | 채팅의 승인 계약 구현: 승인 카드(페이지가 없으면 승인 창), 충돌 알림, 버퍼에 반영된 편집의 파일 카드. |
| ChatApprovalCard | 채팅 안 승인 카드: diff 메시지를 보내고 답이 올 때까지 메시지를 돌린다. 중지하면 모두 거부. |
| ChatPlan | 계획 모드: 들어가기·나오기(omp 재시작), `rad.submit_plan`으로 `docs\plans` 계획서 작성, `docs` 파일 프로젝트 추가, 진행 후속 프롬프트. |
| ChatBtw | `/btw` 곁가지 질문: 질문마다 별도 omp 자식을 띄우고(타이머로 읽음) 채팅 카드와 메모 목록 메시지를 보낸다. 본 대화와 섞지 않는다. |
| BtwRunner | 곁가지 질문 omp 자식 하나: `--mode rpc --no-tools`, 대화 `--fork` 또는 주제 `--resume`, 프롬프트 하나, 중지는 abort 프레임. 막히지 않는 읽기. ToolsAPI 없음. |
| BtwStore | 곁가지 질문 메모(주제별 JSON과 주제 세션)를 `%LOCALAPPDATA%\RADAgent\btw\<프로젝트>`에 읽고 쓴다. |
| ChatSession | IDE당 대화 하나. omp 자식과 진행 상태를 가진다. 창을 닫거나 레이아웃이 바뀌어도 살아 있다. 설정을 바꾸면 같은 세션 파일로 omp를 다시 시작한다. 승인 계약을 구현한다. |
| ChatStream | 에이전트 이벤트를 페이지 메시지로 바꾸고 기록(재표시용)을 가진다: 답, 생각, 도구 입력·중간 출력·결과, 하위 에이전트, 작업 목록, 알림. |
| ChatCatalog | 설정 창용 모델, 생각 수준, 로그인 공급자 목록(RPC 응답). |
| ChatActions | 보내기(저장, 체크포인트, 선택 영역 첨부), 컴파일, 새 세션, 세션 전환과 기록 불러오기, 내보내기, host-tool 실행, 상태줄 문구. |
| ChatActivity | RPC 이벤트로 지금 하는 일(생각, 답 작성, 도구 실행, 압축)과 경과 시간을 정한다. |
| ChatPageMessages | 채팅 페이지(`src\chat`)로 보내는 JSON 메시지. 페이지는 `chat.js`(기록), `tools.js`(도구 묶음·파일 카드), `activity.js`(생각·입력·하위 에이전트·작업 목록), `topbar.js`, `composer.js`(입력 상자와 아래 줄), `panels.js`(시트와 사용량 패널), `clicks.js`(파일·코드·링크 클릭)로 나뉜다. |
| WebView2Api | WebView2 COM 인터페이스 선언(WebView2.h vtable 순서, 쓰지 않는 메서드는 자리만). 릴리스마다 다른 rtl `Winapi.WebView2`를 쓰지 않으려고 둔다. |
| WebView2Host / WebView2Handlers | `RADAgent.WebView2Api`로 WebView2를 띄운다. 가상 호스트로 페이지를 싣고, 페이지 밖 이동과 새 창을 막는다. 도킹·핀·레이아웃으로 창이 다시 만들어지면 브라우저를 숨은 최상위 창에 잠시 옮겼다가 다시 붙인다(WebView2는 `HWND_MESSAGE`를 부모로 받지 않는다). 그래도 브라우저가 없어졌으면 같은 환경에서 새로 띄우고 채팅을 다시 보여 준다(`PageLoads`). |
| WebView2Runtime | BPL 옆 `WebView2Loader.dll` 로드와 환경 만들기, 채팅 페이지·사용자 데이터 폴더, 브라우저가 기다리는 숨은 창. |
| ChatFallback | WebView2를 못 띄울 때의 글자 기록. |
| ChatInput | WebView2 대체 화면의 VCL 입력칸: 여러 줄, 보낸 문장 기록, `/` 명령 목록. |
| ChatTheme | IDE 테마 색(IOTAIDEThemingServices), 고대비·글자 크기 반영, 테마 변경 통지. |
| AgentSettings | RAD Agent 자체 설정(IDE 레지스트리 키): 채팅 표시 항목, 글자 크기, 고대비, 화면 언어, omp 경로·추가 인자. 프로젝트별 IDE 설정 `<프로젝트>\.omp\radagent-ide.json`: UI 작성 방식(`uiBuilding`), 폼 텍스트 편집(`formEditing`). |
| Lang | 화면 문자열: English, 日本語, Deutsch, Français, 한국어. `src\lang\<코드>.json`을 `RADAgentResources.rc`로 RCDATA에 넣고 `Tr`/`TrF`로 부른다. 없는 키는 영어, 그다음 키 이름. `<키>.one`은 첫 값이 1일 때의 문구. 채팅 페이지에는 `page.*` 키를 `strings` 메시지로 보내고 페이지는 `T()`와 `data-i18n`으로 쓴다. 처음 값은 Windows 표시 언어(없으면 영어). omp가 읽는 글은 번역하지 않고 영어로 둔다. ToolsAPI 없음. |
| SettingsDialog / SettingsUi / SettingsAccount / SettingsProject | 설정 창. 채팅 표시, 계정·모델(RPC로 바로 적용), 역할별 모델·확장·고급(프로젝트 omp 설정). |
| OmpSettings / OmpCatalog / OmpCli | 프로젝트 omp 설정 파일 `<프로젝트>\.omp\radagent.yml`(`--config`로 전달)과 omp가 읽는 스킬·확장·하위 에이전트·MCP 목록. `omp config list`를 읽기만 하고 전역 설정은 쓰지 않는다. |
| EditorContext | 활성 파일, 선택 영역, 저장 안 한 파일 수, 링크로 파일 열기. |
| Sessions | 같은 프로젝트의 omp 세션 파일 목록과 선택. |
| ChatStop | 중지 단추: abort를 보내고, 그 턴이 5초 안에 끝나지 않거나 다시 누르면 omp 자식을 끝내고 같은 세션으로 다시 시작한다. 자식이 멈추면(중지·재시작·프로젝트 전환) 기다리던 승인 카드와 `!` 셸 명령을 함께 끝낸다. 연결된 뒤 omp가 스스로 끝나면 같은 세션으로 다시 시작한다(1분에 한 번까지). |
| BrandTable / BrandIcons | provider·모델 → 로고. 규칙은 `src\chat\brands\brands.json`(RCDATA, 채팅 페이지 `brands.js`와 같은 파일). VCL 목록은 `resources\brands\Brands-*.png` 스프라이트로 owner-draw. |
| ChatAttention | IDE가 뒤에 있을 때 사용자를 부른다: 작업 표시줄 깜빡임, 끝난 턴의 Windows 알림(알림 영역 풍선, 누르면 IDE를 앞으로). |
| ChatTurnTime | 턴 끝 보고: 채팅의 끝난 시각·걸린 시간 줄(`turnEnd`의 started/ended/stopped, 다시 불러온 기록은 omp의 timestamp·completedAt), 메시지 창 한 줄, 뒤에 있을 때 알림. 턴마다 TurnLog에 남긴다. |
| TurnLog | RAD Agent가 본 턴의 시작·끝·중지를 프로젝트별로 `%LOCALAPPDATA%\RADAgent\turns\<해시>.jsonl`에 남긴다. omp가 답을 기록하지 않은 턴(출력 전에 중지)은 다시 불러올 때 여기서 끝 시각을 가져온다. ToolsAPI 없음. |
| IdeMenus | 에디터와 메시지 창 오른쪽 클릭 메뉴 항목. |
| DockKeeper | 디버그 시작·종료로 데스크톱이 바뀐 뒤 채팅을 다시 보여 준다. |
| ApprovalDialog / LineDiff | 승인 창과 줄 diff. |
| RpcClient | `omp --mode rpc` 자식 프로세스와 읽기 스레드. `ready` 전 프롬프트 금지. 이벤트는 RpcEvents로 해석해 메인 스레드에 넘긴다. |
| RpcEvents | stdout 프레임을 이벤트(텍스트, 생각, 도구 입력·시작·중간 출력·끝, 하위 에이전트, 재시도, 알림, 턴 끝)로 해석한다. ToolsAPI 없음. |
| RpcResponses / RpcJson | 명령 응답(명령 목록, 상태·작업 목록, 기록 페이지, 모델, 생각 수준, 로그인 공급자) 해석과 공용 JSON 읽기. ToolsAPI 없음. |
| RpcProtocol | JSONL 프레임 생성과 판별. ToolsAPI 없음. |
| RpcDispatch | stdout 줄을 프레임 종류별로 나눠 이벤트로 넘긴다. ToolsAPI 없음. |
| SlashRoutes | omp 터미널 전용 명령의 처리 방식(RAD Agent가 함, 터미널에서만, omp에 넘김). omp가 RPC 목록에 올린 이름이 먼저다. ToolsAPI 없음. |
| ChatSlash | 터미널 전용 명령 실행: `/clear`, `/delete`, `/resume`, `/tree`, `/branch`, `/fork`, `/copy`, `/login`, `/hub` 등을 RPC 요청과 RAD Agent 창으로, 하위 에이전트 대화 보기. |
| ChatQueue | 턴 옆의 일: 작업 중 보낸 메시지(`steer`, `follow_up`), `!` 셸 명령(`bash`, `abort_bash`), 재시도 취소(`abort_retry`). |
| ChatUsage / UsageReport | 컨텍스트 원의 사용량 패널: `get_session_stats`와 뒤에서 돌린 `omp usage --json --provider`(1분 보관), 공급자 한도를 창·그룹·재설정 시각으로. |
| SessionData | 세션 응답 해석(갈라질 메시지, 트리, 마지막 답·코드 블록, 하위 에이전트 대화, 셸 결과). ToolsAPI 없음. |
| ChatCommand | 채팅 입력을 기존 omp RPC 프레임으로 분류한다. 새 명령 `type`을 만들지 않는다. |
| AskDialog | `extension_ui_request`와 슬래시 명령 선택 모달. |
| Options | omp 실행 파일, 명령줄(인자 인용), `%TEMP%\RADAgent` 로그 경로(omp에 넘기는 파일과 stderr 로그는 IDE 프로세스마다 `-p<pid>`, 끝난 IDE의 것은 처음 쓸 때 지움, `rpc.log`는 20MB가 넘으면 `rpc.1.log`로 돌림, 새 `rpc.log` 첫 줄은 버전 줄), 자식이 일찍 끝난 이유(stderr 마지막 줄), 공통 `--config` 내용. |
| RpcChunks | RPC v2 `rpc_chunk` 조각을 원래 프레임으로 되돌린다(순서·크기·끊김 검사). |
| OmpProbe | 설치된 omp 호환성 검사: 버전, 명령줄 옵션, RPC 시작·프로토콜, `rad.*` 등록과 xd:// 연결, 응답 필드, `config list`. 모델 호출 없음. 시험과 IDE가 같이 쓴다. |
| OmpCheck | omp 버전이 바뀌면 첫 시작 때 OmpProbe를 뒤에서 돌려 채팅에 알리고, 설정 창에서 바로 돌린다. 이번 IDE에서 본 omp 버전을 기억한다. RAD Agent 버전이 지난번과 다르면 채팅에 한 번 알리고 릴리스 노트 링크를 붙인다(`SeenAgentVersion`). |
| AgentVersion | RAD Agent 버전(BPL 버전 정보, `RADAgent.dproj` 한 곳에서 올린다), IDE 비트, `bds.exe` 버전, 릴리스 노트 주소, 버그 보고용 버전 줄. ToolsAPI 없음. |
| AboutInfo | IDE 시작 화면과 Help → About의 설치 제품 목록에 RAD Agent 버전과 아이콘(`resources\PluginIcon-24/48.png`)을 넣고, 패키지를 내릴 때 뺀다. `rpc.log`에 버전 줄을 남긴다. |
| MenuIcon | `resources\MenuIcon-16/32.png`(`RADAgentResources.rc`의 RCDATA)를 IDE 이미지 목록에 넣어 View 메뉴 항목 아이콘으로 쓴다. `INTAServices280`이 없는 10.4에서는 아이콘 없이 둔다. |
| IdeContext | 활성 `.dproj` 경로, 열린 모듈, 에디터 버퍼 위치. |
| IdeFiles | 프로젝트 모듈 저장, 디스크에서 바뀐 모듈 다시 읽기, 사용자가 고치던 모듈은 충돌로 돌려준다. 지워진 파일의 모듈은 닫는다. 폼이 있는 모듈은 `Refresh` 대신 닫았다 다시 연다: `Refresh`는 글만 다시 읽고 폼 디자이너가 알던 클래스 모양(필드·메서드와 위치)은 그대로 두어, 다음 디자이너 변경이 필드를 엉뚱한 곳에 넣거나 파싱 오류로 실패하고 반쯤 지운 컴포넌트가 Object Inspector에 남는다(되돌리기 뒤의 접근 위반). 편집기 탭이 열려 있었으면 다시 보인다. |
| ChatDiskSync | 프롬프트 전·`rad.*` 변경 후 저장, omp 도구가 끝날 때와 턴 끝에 다시 읽기, 충돌 알림. |
| GitRepo | git 실행, `git init`과 `.gitignore`, 별도 index로 만드는 체크포인트 커밋(`refs/radagent/`, 보낸 시각 `RADAgent-Time` 트레일러), 되돌리기(이름이 바뀐 파일 포함, 지우지 못한 파일은 알림), 체크포인트에서 브랜치. ToolsAPI 없음. |
| ChatCheckpoints | 프로젝트 저장소 보장, 메시지마다 체크포인트(작업 중 보낸 steer·follow-up 포함), 채팅의 되돌리기·브랜치(파일은 git, 대화는 omp `get_entries`/`branch`). 기록의 메시지와 체크포인트는 문장이 아니라 omp가 메시지를 기록한 시각으로 짝짓는다. |
| Compile | 활성 프로젝트 빌드와 완료 통지. 결과는 메시지 뷰로 보낸다. |
| HostToolDefs | host-tool 이름과 `set_host_tools` 스키마. ToolsAPI 없음. |
| HostTools | host-tool 호출을 도구별 구현으로 나눠 보낸다. 버퍼 읽기, 컴파일. 메인 스레드에서만 ToolsAPI를 호출한다. IDE 예외는 도구 오류 결과로 바꾼다(오류 대화상자가 뜨면 턴이 멈춘다). |
| Approval | 상태를 바꾸는 host-tool이 쓰는 사용자 승인 계약(`IAgentApproval`). ChatSession이 구현한다. |
| BufferEdits | 승인 후 캐럿 위치에 삽입(`rad.insert_at_caret`). 코드 편집은 omp의 디스크 편집이다. |
| DebugTools | 디버거 상태, 호출 스택, 부작용 없는 식 평가, 중단점 목록. 읽기 전용. |
| DebugControl | 승인 후 실행·계속, 스텝(over, into, return), 일시 정지, 종료, 소스 중단점 추가. 디버기 메모리는 쓰지 않는다. |
| FormDesigner | 유닛의 폼 디자이너 찾기, 이름→컴포넌트, 속성 값 문자열화, 디자이너 수정 통지. |
| FormTools | `rad.form_*` 분배와 읽기(컴포넌트 목록, published 속성). |
| FormEdits | 승인 후 속성 변경, 컴포넌트 추가(FMX 항목 컨테이너 아래는 `IDesigner.CreateChild`, 그 밖에는 부모를 먼저 선택해 FMX 디자이너가 선택된 항목 안에 넣지 않게 한다)·삭제(먼저 폼을 선택해 Object Inspector가 지우는 컴포넌트를 붙들지 않게 한다)·이름 변경(폼 자체 포함). 끝나면 ChatDiskSync가 저장한다. |
| FormEvents | 승인 후 이벤트 연결·해제. 디자이너에 없는 이벤트면 연결 가능한 목록을 돌려준다. |

## 데이터 흐름

1. 사용자가 DockForm에 프롬프트를 보낸다.
2. ChatDiskSync가 프로젝트의 저장 안 한 모듈을 저장하고, ChatCheckpoints가 그 상태를 git 체크포인트로 남긴다.
3. RpcClient가 `ready`를 받은 뒤에만 `prompt` 프레임을 쓴다.
4. omp가 도구와 LSP로 답을 만든다. DelphiLSP는 omp 설정의 별도 인스턴스다.
5. omp는 자기 도구로 디스크 파일을 고친다(승인 방식에 따라 채팅 카드로 묻는다). 도구가 끝날 때마다 IdeFiles가 바뀐 모듈을 IDE에 다시 읽힌다.
6. 폼·디버거·프로젝트 변경은 `rad.*` host-tool로 승인 뒤 IDE에서 하고, 끝나면 저장한다.
7. Compile이 활성 프로젝트를 빌드한다. 오류와 성공은 메시지 뷰에 올린다.
8. BPL을 다시 빌드한 경우에는 같은 비트의 IDE에 그 BPL만 다시 로드한다.

## 파일과 체크포인트

- 디스크가 기준이다. 프롬프트 직전과 `rad.*` 변경 직후에 저장한다.
- omp가 바꾼 파일은 IDE에 다시 읽힌다. 사용자가 그 사이 고친 모듈은 덮어쓰지 않고 충돌로 알린다.
- 메시지마다 체크포인트 커밋(`refs/radagent/cp/NNNNNN`, 부모는 HEAD, 트리는 작업 폴더 전체)을 남긴다. 사용자 브랜치 기록은 바뀌지 않는다.
- 되돌리기: 지금 상태를 `refs/radagent/before-restore/`에 남기고, 체크포인트의 파일을 쓰고 그 뒤에 생긴 파일을 지운 뒤 IDE에 다시 읽힌다. 대화는 omp `branch`로 그 메시지 앞에서 갈라지고, 메시지는 입력칸으로 돌아온다. 브랜치는 여기에 `git branch`와 HEAD 전환을 더한다.

## 비범위

- Ghost Text
- `IOTAAIPlugin`
- KAI MCP, KAI 패키지, KAI 상표
- DelphiLSP를 IDE 프로세스에 attach
- DelphiLSP.exe 또는 designide 재배포
- omp 에이전트 루프의 Delphi 재구현
- 터미널 임베드. IDE에만 있는 기능은 host-tool로 열고, omp에 이미 있는 명령은 채팅창이 RPC로 보낸다.
