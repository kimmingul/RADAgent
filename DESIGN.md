# RADAgent 설계

design-time BPL이 RAD Studio IDE 안에서 Chat을 띄우고, omp 18.2.11 자식 프로세스에 JSONL RPC로 프롬프트를 넘긴다. 에이전트 루프, 도구 실행, LSP 세션은 omp가 소유한다.

## 아키텍처

```
+-------------------- bds.exe (32-bit 또는 64-bit, 하나만) --------------------+
| RADAgent BPL (그 IDE와 같은 비트)                                          |
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
| OmpLaunch | omp를 띄우기 전에 쓰는 파일: rad.* 문서를 시스템 프롬프트에 넣는 `omp-host.yml`(`tools.xdevInlineDevices`), 프로젝트 안내 `project-guide.md`(`--append-system-prompt`), Delphi 프로젝트의 `.omp/lsp.json`. |
| HostToolDefs | 프로필에 맞춘 rad.* 목록: 폼이 있을 때만 폼 도구, VCL/FMX와 Delphi/C++ 문구. |
| FormBatch / ModuleCreator | `rad.form_apply`(폼 변경 묶음, 승인 한 번), `rad.new_module`(폼·프레임·데이터 모듈·유닛 추가). |
| ChatExtensions | 입력 상자 `＋` 메뉴의 IDE 쪽: 첨부 파일·사진(prompt images), 작업 폴더 추가, 커넥터(MCP)와 플러그인 목록과 켜기/끄기. |
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
| ChatPageMessages | 채팅 페이지(`src\chat`)로 보내는 JSON 메시지. 페이지는 `chat.js`(기록), `tools.js`(도구 묶음·파일 카드), `activity.js`(생각·입력·하위 에이전트·작업 목록), `topbar.js`, `composer.js`(입력 상자와 아래 줄)로 나뉜다. |
| WebView2Host / WebView2Handlers | rtl `Winapi.WebView2`와 BPL 옆 `WebView2Loader.dll`로 WebView2를 띄운다. 가상 호스트로 페이지를 싣고, 페이지 밖 이동과 새 창을 막는다. |
| ChatFallback | WebView2를 못 띄울 때의 글자 기록. |
| ChatInput | WebView2 대체 화면의 VCL 입력칸: 여러 줄, 보낸 문장 기록, `/` 명령 목록. |
| ChatTheme | IDE 테마 색(IOTAIDEThemingServices), 고대비·글자 크기 반영, 테마 변경 통지. |
| AgentSettings | RADAgent 자체 설정(IDE 레지스트리 키): 채팅 표시 항목, 글자 크기, 고대비, 화면 언어, omp 경로·추가 인자. |
| Lang | 화면 문자열: English, 日本語, Deutsch, Français, 한국어. `src\lang\<코드>.json`을 `RADAgentResources.rc`로 RCDATA에 넣고 `Tr`/`TrF`로 부른다. 없는 키는 영어, 그다음 키 이름. `<키>.one`은 첫 값이 1일 때의 문구. 채팅 페이지에는 `page.*` 키를 `strings` 메시지로 보내고 페이지는 `T()`와 `data-i18n`으로 쓴다. 처음 값은 Windows 표시 언어(없으면 영어). omp가 읽는 글은 번역하지 않고 영어로 둔다. ToolsAPI 없음. |
| LegacyNames | 옛 이름 DelphiAgent로 남은 설정을 한 번 옮긴다: IDE 레지스트리 키, `.omp\delphiagent.yml`, `/btw` 메모 폴더, `refs/delphiagent/` 체크포인트. ToolsAPI 없음. |
| SettingsDialog / SettingsUi / SettingsAccount / SettingsProject | 설정 창. 채팅 표시, 계정·모델(RPC로 바로 적용), 역할별 모델·확장·고급(프로젝트 omp 설정). |
| OmpSettings / OmpCatalog / OmpCli | 프로젝트 omp 설정 파일 `<프로젝트>\.omp\radagent.yml`(`--config`로 전달)과 omp가 읽는 스킬·확장·하위 에이전트·MCP 목록. `omp config list`를 읽기만 하고 전역 설정은 쓰지 않는다. |
| EditorContext | 활성 파일, 선택 영역, 저장 안 한 파일 수, 링크로 파일 열기. |
| Sessions | 같은 프로젝트의 omp 세션 파일 목록과 선택. |
| ChatAttention | IDE가 뒤에 있을 때 작업 표시줄 깜빡임. |
| IdeMenus | 에디터와 메시지 창 오른쪽 클릭 메뉴 항목. |
| DockKeeper | 디버그 시작·종료로 데스크톱이 바뀐 뒤 채팅을 다시 보여 준다. |
| ApprovalDialog / LineDiff | 승인 창과 줄 diff. |
| RpcClient | `omp --mode rpc` 자식 프로세스와 읽기 스레드. `ready` 전 프롬프트 금지. 이벤트는 RpcEvents로 해석해 메인 스레드에 넘긴다. |
| RpcEvents | stdout 프레임을 이벤트(텍스트, 생각, 도구 입력·시작·중간 출력·끝, 하위 에이전트, 재시도, 알림, 턴 끝)로 해석한다. ToolsAPI 없음. |
| RpcResponses / RpcJson | 명령 응답(명령 목록, 상태·작업 목록, 기록 페이지, 모델, 생각 수준, 로그인 공급자) 해석과 공용 JSON 읽기. ToolsAPI 없음. |
| RpcProtocol | JSONL 프레임 생성과 판별. ToolsAPI 없음. |
| RpcDispatch | stdout 줄을 프레임 종류별로 나눠 이벤트로 넘긴다. ToolsAPI 없음. |
| ChatCommand | 채팅 입력을 기존 omp RPC 프레임으로 분류한다. 새 명령 `type`을 만들지 않는다. |
| AskDialog | `extension_ui_request`와 슬래시 명령 선택 모달. |
| Options | omp 실행 파일, 명령줄(인자 인용), `%TEMP%\RADAgent` 로그 경로, 자식이 일찍 끝난 이유(stderr 마지막 줄), 공통 `--config` 내용. |
| RpcChunks | RPC v2 `rpc_chunk` 조각을 원래 프레임으로 되돌린다(순서·크기·끊김 검사). |
| OmpProbe | 설치된 omp 호환성 검사: 버전, 명령줄 옵션, RPC 시작·프로토콜, `rad.*` 등록과 xd:// 연결, 응답 필드, `config list`. 모델 호출 없음. 시험과 IDE가 같이 쓴다. |
| OmpCheck | omp 버전이 바뀌면 첫 시작 때 OmpProbe를 뒤에서 돌려 채팅에 알리고, 설정 창에서 바로 돌린다. |
| MenuIcon | `resources\MenuIcon-16/32.png`(`RADAgentResources.rc`의 RCDATA)를 IDE 이미지 목록에 넣어 View 메뉴 항목 아이콘으로 쓴다. |
| IdeContext | 활성 `.dproj` 경로, 열린 모듈, 에디터 버퍼 위치. |
| IdeFiles | 프로젝트 모듈 저장, 디스크에서 바뀐 모듈 다시 읽기(`Refresh`), 사용자가 고치던 모듈은 충돌로 돌려준다. 지워진 파일의 모듈은 닫는다. |
| ChatDiskSync | 프롬프트 전·`rad.*` 변경 후 저장, omp 도구가 끝날 때와 턴 끝에 다시 읽기, 충돌 알림. |
| GitRepo | git 실행, `git init`과 `.gitignore`, 별도 index로 만드는 체크포인트 커밋(`refs/radagent/`), 되돌리기, 체크포인트에서 브랜치. ToolsAPI 없음. |
| ChatCheckpoints | 프로젝트 저장소 보장, 메시지마다 체크포인트, 채팅의 되돌리기·브랜치(파일은 git, 대화는 omp `get_entries`/`branch`). |
| Compile | 활성 프로젝트 빌드와 완료 통지. 결과는 메시지 뷰로 보낸다. |
| HostToolDefs | host-tool 이름과 `set_host_tools` 스키마. ToolsAPI 없음. |
| HostTools | host-tool 호출을 도구별 구현으로 나눠 보낸다. 버퍼 읽기, 컴파일. 메인 스레드에서만 ToolsAPI를 호출한다. |
| Approval | 상태를 바꾸는 host-tool이 쓰는 사용자 승인 계약(`IAgentApproval`). ChatSession이 구현한다. |
| BufferEdits | 승인 후 캐럿 위치에 삽입(`rad.insert_at_caret`). 코드 편집은 omp의 디스크 편집이다. |
| DebugTools | 디버거 상태, 호출 스택, 부작용 없는 식 평가, 중단점 목록. 읽기 전용. |
| DebugControl | 승인 후 실행·계속, 스텝(over, into, return), 일시 정지, 종료, 소스 중단점 추가. 디버기 메모리는 쓰지 않는다. |
| FormDesigner | 유닛의 폼 디자이너 찾기, 이름→컴포넌트, 속성 값 문자열화, 디자이너 수정 통지. |
| FormTools | `rad.form_*` 분배와 읽기(컴포넌트 목록, published 속성). |
| FormEdits | 승인 후 속성 변경, 컴포넌트 추가·삭제·이름 변경, 이벤트 연결. 끝나면 ChatDiskSync가 저장한다. |

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

## 진행 메모

채팅과 `omp --mode rpc`까지는 동작한다. 이후에도 터미널 임베드는 하지 않는다. IDE에만 있는 기능은 host-tool로 열고, omp에 이미 있는 명령은 채팅창이 기존 RPC로 보낸다. 디버거는 읽기 도구와 승인 후 실행 제어가 있다. 폼 디자이너는 읽기와 승인 후 편집(속성, 추가, 삭제, 이름, 이벤트)이 있다. 이어서 볼 위치는 `docs/continue.md`다.
