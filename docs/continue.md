# 다음 작업을 위한 메모

2026-09-23에 MVP 채팅까지 동작하는 상태에서 멈춘 기록이다. 새 아키텍처를 만들지 말고, 여기와 `DESIGN.md`, `AGENTS.md`를 기준으로 잇는다.

## 목적

RAD Studio 안에서 사람이 쓰는 폼 디자이너, 디버거 같은 IDE 기능을 활용해 코딩을 돕는 oh-my-pi(omp) 에이전트다.

터미널에 omp 화면을 임베드하지 않는다. ToolsAPI는 `bds.exe` 안에서만 호출할 수 있으므로, BPL이 host-tool을 열고 omp가 RPC로 그 도구를 부른다.

## 두 층

| 층 | 하는 일 | 하지 말 것 |
| --- | --- | --- |
| 채팅창 → 기존 omp RPC | `/model`, `/fast`, `/thinking`, `/effort`, `/clear`, `/goal`, `/switch`처럼 omp가 이미 처리하는 명령 | Delphi로 omp 명령을 새로 만들기. 없는 `type`을 발명하기 |
| BPL host-tool | IDE 안에만 있는 동작. 컴파일, 버퍼, 읽기 전용 디버거, 나중에는 디자이너 | omp가 ToolsAPI를 직접 호출하게 하기. KAI, Ghost Text, `IOTAAIPlugin` |

stdin에는 JSONL만 쓴다. 일반 텍스트 한 줄이면 omp가 죽는다. `@file`은 RPC가 거절한다. 프레임 원문은 채팅에 찍지 않고 `%TEMP%\RADAgent\rpc.log`에만 남긴다.

## 지금 되는 것

- 32/64-bit IDE에서 Tools 또는 View의 RADAgent 도킹 창. 대화와 omp는 `ChatSession`이 가지고, 창은 뷰다. 창을 닫거나 디버그 레이아웃으로 바뀌어도 omp pid와 기록이 그대로이고, 다시 열면 기록을 다시 그린다.
- `omp --mode rpc`. `ready` 뒤에만 명령. 응답은 WebView2 페이지(`src\chat`)에 마크다운으로 스트리밍. 도구 실행은 접힌 줄(✓/✗, 시간, 결과), 파일 위치는 에디터로 가는 링크.
- 채팅 창 전체가 WebView2 페이지다: 위 막대(세션 제목·프로젝트·새 세션·내보내기·설정), 가운데 한 칸 기록, 입력 상자와 아래 줄(첨부·승인 방식·모델·생각 수준·컨텍스트·연결). 프레임은 `ChatStatus`로 상태를 보내고 `ChatPageCommands`로 요청을 처리한다. 작업 중에는 보내기가 중지로 바뀌고 기록 끝에 `✳ 하는 일 · 경과`가 보인다.
- 입력(`composer.js`): 여러 줄, Enter 보내기(한글 조합 중 제외), Shift+Enter 줄바꿈, ↑ 기록, `/` 명령 목록(`get_available_commands`). Esc는 목록만 닫고 도킹 창은 숨지 않는다.
- 입력 위 칩: 활성 파일, `+ 선택 N–M줄`(켜면 선택 코드를 프롬프트에 붙임), 저장 안 한 파일 수.
- 도구 묶음(`tools.js`): 답 사이의 생각·도구·하위 에이전트를 `도구 N개 사용 · 실패 N ›` 한 줄로. 파일 카드: `IAgentApproval.ChangeApplied`가 반영된 편집의 `+N -M`과 첫 변경 줄을 보낸다.
- `＋` 메뉴(`plusmenu.js`, `RADAgent.ChatExtensions`): 파일·사진(600KB 이하 사진은 prompt `images`, v1 프레임 1MiB 한도), 폴더(`/add-dir`), 커넥터(MCP, `/mcp enable|disable`), 플러그인(`omp plugin enable|disable`, 확장 모듈은 프로젝트 `disabledExtensions` + omp 재시작).
- 승인 방식 선택은 IDE 변경 승인도 정한다(항상 묻기 = 변경마다, 쓰기 허용 = 턴마다 한 번, 권한 무시 = 묻지 않음, 처음 값 권한 무시). `tools.approvalMode`를 `<프로젝트>\.omp\radagent.yml`에 쓰고 omp를 같은 세션으로 다시 시작한다(RPC에 바꾸는 명령이 없음).
- 위 막대: 세션 제목(세션 목록, `switch_session` 후 `get_messages_page`로 기록 표시), 새 세션, 내보내기(`export_html`), 설정. 색은 IDE 테마를 따르고 테마 변경 통지를 받는다.
- 진행 표시: 생각(`thinking_delta`), 도구 입력(`toolcall_delta`), 도구 중간 출력(`tool_execution_update`, 250ms 간격, 끝 8000자), 하위 에이전트(`set_subagent_subscription progress`), 작업 목록(`todo` 도구 뒤 `get_state.todoPhases`), 재시도·모델 대체. 페이지가 `display` 메시지로 항목별로 숨긴다.
- 설정 창: 채팅 표시·글자 크기·고대비(레지스트리), 모델·생각 수준·OAuth 로그인(RPC), 역할별 모델·스킬/확장/하위 에이전트·omp 도구 승인·기본 생각 수준(`<프로젝트>\.omp\radagent.yml`, `--config`), omp 경로·추가 인자. omp 설정이 바뀌면 같은 세션 파일로 다시 시작(`switch_session`). 턴이 도는 중이면 턴이 끝난 뒤 다시 시작한다.
- 승인은 채팅 안 카드(`approval.js`, `RADAgent.ChatApprovalCard`)로 묻는다. 줄 diff(앞뒤 3줄), 중지 시 모두 거부. WebView2가 없으면 모달 승인 창.
- 계획 모드(`RADAgent.ChatPlan`): 승인 방식 `계획`, `rad.submit_plan` → `docs\plans\yyyy-mm-dd-hhnn-<slug>.md`, 계획 카드의 진행 → 이전 방식으로 omp 재시작 후 `@계획서` 프롬프트. `docs` 파일은 `Project.AddFile`로 Project Manager에 보인다.
- `@` 파일 메뉴(`composer.js`, `ChatStatus.PageFiles`). 보내기 전에 저장하므로 `@경로`는 디스크 그대로다.
- 디스크 기준(`IdeFiles`, `ChatDiskSync`): 프롬프트 전·`rad.*` 변경 후 저장, omp 도구 끝·턴 끝에 바뀐 모듈 `Refresh`, 사용자가 고치던 모듈은 충돌 알림. omp 도구 승인도 채팅 카드.
- git 체크포인트(`GitRepo`, `ChatCheckpoints`, `checkpoints.js`): 저장소가 없으면 `git init`, 메시지마다 `refs/radagent/cp/`, 메시지의 `↶ 여기로 되돌리기`/`⑂ 여기서 브랜치`. IDE가 뒤에 있으면 승인 요청과 턴 끝에 작업 표시줄이 깜빡인다.
- `/btw` 곁가지 질문(`RADAgent.ChatBtw`, `BtwRunner`, `BtwStore`, `btw.js`): 질문마다 `omp --mode rpc --no-tools --fork <대화>`(이어 묻기는 `--resume <주제 세션>`), 채팅 접힌 카드 + 위 막대 `BTW` 메모 창. 저장 위치 `%LOCALAPPDATA%\RADAgent\btw\<프로젝트>\`.
- 에디터 오른쪽 클릭 `RADAgent: 선택 영역 설명/고치기`, 메시지 창 오른쪽 클릭 `RADAgent: 빌드 오류 고치기`.
- WebView2는 rtl `Winapi.WebView2`와 BPL 옆 `RADAgent\WebView2Loader.dll`로 띄운다. 실패하면 글자 기록으로 계속한다. 배포는 `docs/install.md`.
- 프로젝트 해석: 프로젝트 그룹, 열린 모듈, 에디터 옆 `.dproj`, 마지막 캐시. 없으면 `프로젝트=없음`.
- 슬래시 명령은 모달로 고른 뒤 기존 RPC만 전송.
- omp가 보내는 `extension_ui_request`의 select, confirm, input, editor는 모달. notify와 setStatus는 로그.
- host-tool: `rad.compile`, `rad.open_buffer`, `rad.insert_at_caret`(코드 편집은 omp의 디스크 도구).
- 디버거 읽기 host-tool: `rad.debug_state`, `rad.debug_stack`(최대 64프레임), `rad.debug_evaluate`(부작용 없음), `rad.debug_breakpoints`. 평가가 `erDeferred`로 오면 기다리지 않고 오류로 돌려준다.
- 디버거 실행 제어 host-tool: `rad.debug_run`(프로세스가 없으면 IDE `RunRunCommand`로 빌드·실행, 멈춰 있으면 계속), `rad.debug_step`(`mode` over/into/return), `rad.debug_pause`, `rad.debug_reset`, `rad.debug_add_breakpoint`(`file`, `line`). 모두 승인 뒤에만 하고, 최대 5초 동안 디버그 이벤트를 처리한 뒤 `rad.debug_state`와 같은 JSON을 돌려준다. 메모리 쓰기는 없다.
- 폼 디자이너 host-tool: `rad.form_components`, `rad.form_properties`(읽기 전용, 이벤트는 메서드 이름), `rad.form_set_property`, `rad.form_add_component`, `rad.form_delete_component`, `rad.form_rename_component`(`newName`), `rad.form_set_event`(`event`, `handler`, 빈 handler는 연결 해제). 바꾸는 도구는 승인 후 디자이너에만 반영하고 저장하지 않는다. 대상은 `.pas` 절대 경로이고, 모듈이 닫혀 있으면 연다. 폼 자체는 지우거나 이름을 바꾸지 않는다. 이름을 바꾸면 디자이너가 기본 이름 핸들러(`Button1Click`)도 바꾼다.
- 캐럿 삽입은 승인 전에 버퍼를 고치지 않고, 승인 뒤 저장한다.
- omp 실행 파일은 PATH의 `omp.exe`, 없으면 `%LOCALAPPDATA%\omp\omp.exe`.

메뉴 등록은 `ViewsMenu`, `ViewMenu`, `ToolsMenu`, `HelpMenu` 순으로 있는 이름에만 `AddActionMenu`한다. RAD Studio 13.2의 View 메뉴 컴포넌트 이름은 `ViewsMenu`다. `ViewMenu`로 고정하면 패키지 로드가 실패한다.

프레임 DFM은 `src/RADAgent.DockForm.dfm`이고 비어 있다. 컨트롤은 `HostFrameCreated`의 `BuildUi`에서 만든다.

## 슬래시 → RPC

| 입력 | 전송 |
| --- | --- |
| 일반 문장 | `prompt` |
| `/clear`, `/new` | 확인 후 `new_session` |
| `/abort`, 중지 버튼 | `abort` |
| `/model` | `get_available_models` 후 모달에서 고르면 `set_model`. 취소하면 명령을 보내지 않음 |
| `/model <provider> <modelId>` | `set_model`. 파싱 실패 시 원문을 `prompt` |
| `/fast`, `/fast on\|off` | 필요하면 on/off 모달, 그 다음 `set_fast_mode` |
| `/thinking <level>`, `/effort <level>` | `set_thinking_level`. 수준이 없으면 모달 |
| `/goal`, `/switch`, 그 외 `/` | 원문을 `prompt.message`로 전달 |

`ready` 직후 순서는 `set_host_tools`, `get_state`, `get_available_commands`다.

## 코드 위치

| 내용 | 위치 |
| --- | --- |
| 페이지 상태·요청 | `RADAgent.ChatStatus`, `RADAgent.ChatPageCommands` |
| 대화, omp | `RADAgent.ChatSession` |
| 이벤트 → 페이지 메시지, 기록 | `RADAgent.ChatStream` |
| 설정 창 | `RADAgent.SettingsDialog`, `SettingsAccount`, `SettingsProject` |
| 프로젝트 omp 설정 | `RADAgent.OmpSettings`, `OmpCatalog` |
| 보내기, 세션, 내보내기, host-tool 실행 | `RADAgent.ChatActions` |
| RPC 이벤트 해석 | `RADAgent.RpcEvents.ParseAgentEvent` |
| 채팅 페이지 | `src\chat\chat.js`, `tools.js`, `activity.js`, `topbar.js`, `composer.js`, `markdown.js`, 스타일 `chat.css`·`activity.css`·`chrome.css`, 메시지는 `RADAgent.ChatPageMessages` |
| WebView2 | `RADAgent.WebView2Host` |
| 오른쪽 클릭 메뉴 | `RADAgent.IdeMenus` |
| 프로젝트 해석 | `RADAgent.IdeContext.CurrentProject`, `ActiveProjectFile` |
| 슬래시 분류 | `RADAgent.ChatCommand.ClassifyChat` |
| 모달 | `RADAgent.AskDialog` |
| host-tool 이름과 스키마 | `RADAgent.HostToolDefs.BuildSetHostToolsFrame` |
| host-tool 실행 | `RADAgent.HostTools.ExecuteHostTool` |
| 저장·다시 읽기, 충돌 | `RADAgent.IdeFiles`, `RADAgent.ChatDiskSync` |
| 체크포인트·되돌리기 | `RADAgent.GitRepo`, `RADAgent.ChatCheckpoints` |
| 디버거 읽기 host-tool | `RADAgent.DebugTools.ExecuteDebugTool` |
| 디버거 실행 제어 | `RADAgent.DebugControl.ExecuteDebugControl` |
| 승인 계약 | `RADAgent.Approval.IAgentApproval` |
| 폼 디자이너 host-tool | `RADAgent.FormTools.ExecuteFormTool`, 변경은 `RADAgent.FormEdits` |
| 컴파일 | `RADAgent.Compile.BuildActiveProjectJson` |
| RPC 프로세스 | `RADAgent.RpcClient` |

## 아직 하지 않은 것

Ghost Text, `IOTAAIPlugin`, KAI, 터미널 임베드는 하지 않았다. KAI와 터미널 임베드는 AGENTS.md와 이 문서의 원칙상 하지 않는다. Ghost Text와 `IOTAAIPlugin`은 `DESIGN.md` 비범위다. 새 IDE 기능도 omp가 ToolsAPI를 직접 부르게 하지 말고, 지금 host-tool과 같은 방식으로 BPL이 메인 스레드에서 호출하게 한다. 상태를 바꾸는 host-tool은 `IAgentApproval.ApproveChange`로 승인받는다. host-tool을 추가하면 `HostToolDefs`에 이름과 스키마를 넣고, `tests/ProtocolTests.dpr`의 `all host tools declared` 목록도 고친다.

## 빌드

64-bit IDE가 BPL을 열고 있으면 덮어쓸 수 없다. IDE를 종료한 뒤 `scripts\build-win64.cmd`를 실행한다. 결과:

`C:\Users\Public\Documents\Embarcadero\Studio\37.0\Bpl\Win64\RADAgent370.bpl`

이미 설치되어 있으면 IDE를 다시 연다. 32-bit는 `scripts\build-win32.cmd`와 `Bpl\RADAgent370.bpl`이다. 한 BPL을 양쪽 Known Packages에 넣지 않는다.

## 테스트

`scripts\build-tests.cmd`를 실행한다. `tests\ProtocolTests.dpr`을 Win64로 빌드하고 실행하며, 실패 개수를 종료 코드로 돌려준다. `TestLiveReady`는 실제 `omp`를 띄워 `ping` 프롬프트를 보낸다.

## 검증 기록

2026-09-23 20시 기준.

| 항목 | 결과 |
| --- | --- |
| `scripts\build-win32.cmd` | 성공. 경고 없음 |
| `scripts\build-win64.cmd` | 성공. 경고 없음 |
| `scripts\build-tests.cmd` (omp 18.2.11) | 전부 통과 |
| 프로젝트 스킬 | `.agents/skills`로 옮김. omp `get_available_commands`에 `skill:delphi-lsp`, `skill:delphi-toolsapi`, `skill:omp-rpc`가 나온다 |
| 사용자 RAD 스킬 | `~/.omp/agent/config.yml`의 `skills.ignoredSkills`에 `debugging`, `ide-file-operations`, `project-management`를 넣었다. omp에서만 빠지고 다른 에이전트에는 영향이 없다 |
| 개발용 DelphiLSP | `.omp/lsp.json`과 손으로 만든 `src/RADAgent.delphilsp.json`으로 definition과 diagnostics를 확인했다 |
| Win32 IDE 등록 | `Known Packages`에 `Bpl\RADAgent370.bpl`. 옛 `DelphiAgent370.bpl` 항목은 `Known Packages`와 `Disabled Packages`에서 지웠다(32-bit IDE가 켜져 있는 동안 레지스트리를 고치면 IDE가 닫힐 때 옛 목록을 다시 쓴다) |
| Win64 IDE 등록 | `Known Packages x64`에 `Win64\RADAgent370.bpl`만 있다 |
| 디버거 host-tool | 64-bit, 32-bit IDE 디버그 세션에서 확인했다 (MVP 10단계) |
| MVP 한 바퀴 | 64-bit IDE 1~10단계 통과, 32-bit IDE 1~10단계 통과. 아래 "MVP 확인 결과" |
| 폼 디자이너 host-tool | 64-bit IDE: 목록, Button1 속성 읽기(DFM과 같음), Caption 변경 취소와 승인, `TEdit` 추가(160,20), 없는 클래스 거절을 확인했다. 디스크 `.pas`, `.dfm`은 그대로이고 버퍼에 `Edit1: TEdit;` 필드가 생긴다. 32-bit IDE: Caption 변경, `TEdit` 추가, 목록을 확인했다. 오류 창 없음 |
| 폼 디자이너 편집 추가분 | 64-bit IDE: `Button1`→`RunButton` 이름 변경(필드와 `Button1Click`→`RunButtonClick`이 같이 바뀜), 폼 `OnCreate`→`FormCreate` 새 스텁, `Label1.OnClick` 연결, `Label1` 삭제 취소와 승인(필드 제거). 디스크 파일 그대로. 32-bit IDE: 이름 변경, 이벤트 연결, 삭제 확인 |
| 디버거 실행 제어 | 64-bit IDE: 중단점 추가(30줄), 실행(running), 앱 버튼 → 30줄 정지, step over → 29줄, return, 계속 → 30줄, 종료, 다시 실행 → 일시 정지 → 종료 취소와 승인. 32-bit IDE: 중단점, 실행, step over → 29줄, 종료. 오류 창 없음 |
| `rpc.log` | 읽기 스레드와 메인 스레드가 동시에 쓰면 줄이 빠졌다(`agent_end` 누락). 쓰기를 임계 구역으로 묶었고, 프롬프트 3개에 `agent_end` 3개를 확인했다 |
| 채팅 UI (WebView2) | 64-bit IDE: 마크다운 표·코드 강조·복사, 도구 줄(✓, 시간), 파일 링크 → 에디터 14줄 이동, 상태줄 진행 표시(`도구 실행 중: rad.apply_edit · 8초`)와 중지/보내기 활성, 선택 영역 첨부(24–31줄), 승인 diff 창, `/mo` 명령 목록과 Enter 선택, Shift+Enter 여러 줄, 에디터·메시지 창 오른쪽 클릭 메뉴(빌드 오류를 고쳐 37줄 복구), 세션 목록 전환과 기록 표시, HTML 내보내기, 고대비, 디버그 레이아웃에서 창과 omp pid 유지. 32-bit IDE: WebView2(x86 로더) 렌더링, 명령 목록이 입력 위에 뜸, Esc로 창이 숨지 않음, 창을 닫았다 열어도 같은 pid와 기록, 고대비. IDE 종료 시 오류 창 없음. IDE 테마 전환 통지는 코드만 있고 테마를 실제로 바꿔 보지는 않았다 |
| 진행 표시·설정 창 | 64-bit IDE: 작업 목록 패널(2/2), 도구 줄의 `입력` 칸, bash 출력, 생각(162자) 접힘 줄, 하위 에이전트 줄(`✓ scout LineCounter … completed`). 설정 창 5개 탭, 역할별 전역 값 힌트, 스킬 끄기 → `radagent.yml`에 `skill:find-skills` → 다시 시작 후 `--config`로 뜬 omp의 명령 목록에서 빠짐, 전역에서 제외된 스킬은 체크되지 않음, 다시 켜면 파일 삭제. 다시 시작 후 같은 세션 기록(메시지 2개) 복원. 생각 끄기 후 턴에 생각 줄 없음. 32-bit IDE: 작업 목록·도구 줄, 설정 창, 한글 확인 창. 오류 창 없음 |
| 로그인 | 원인: `SendRaw`가 `extension_ui_response`의 `id`까지 새 요청 id로 바꿔 omp가 답을 버렸다(모든 확인·선택·입력 답이 무시됨). 첫 로그인이 코드 입력을 10분 기다리는 동안 omp가 다른 명령에 답하지 않아 다음 로그인들이 멈췄다. 고친 뒤: 답은 요청 id 유지, 로그인 중에는 버튼이 `로그인 취소: 이름`, 입력 창 취소나 이 버튼은 omp를 같은 세션으로 다시 시작(omp는 취소해도 코드를 다시 묻고 로그인 중단 명령이 없음). OpenRouter 취소 뒤 Kimi Code 로그인에서 브라우저가 다시 열림, Kimi 장치 코드 로그인 취소 후 다시 로그인도 열림 |
| Claude Desktop형 화면 | 64-bit IDE: 위 막대(새 대화·Smoke·아이콘), 입력 상자·아래 줄, `MainForm.pas` 칩, bash와 `rad.apply_edit`을 쓰는 턴에서 `도구 10개 사용 실패 1 ›` 묶음(펼치면 생각 2개와 도구 8개), 작업 중 `✳ 응답 기다리는 중 · 24초`와 중지 단추, 승인 후 파일 카드 `MainForm.pas +1 -0`. `/mo` 명령 목록, 입력에서 Esc 뒤에도 도킹 창 유지. 승인 방식을 쓰기 허용으로 바꾸면 `radagent.yml`에 `tools.approvalMode: write`, omp pid가 바뀌고 같은 세션 기록 복원, 권한 무시로 되돌리면 파일 삭제. 목록 안 들여쓴 코드 블록이 코드로 보임. 32-bit IDE: 같은 배치, 도구 묶음, 코드 블록. 오류 창 없음 |
| + 메뉴 | 64-bit IDE: 파일 또는 사진 추가·폴더 추가·커넥터›·플러그인›·프로젝트 컴파일. 커넥터: 시험용 `demo-docs`(프로젝트 `.omp\mcp.json`)를 끄자 `/mcp disable demo-docs`로 그 파일에 `enabled: false`, 켜자 다시 지워짐. 플러그인: `orca-prefill` 끄기 → `radagent.yml`에 `extension-module:orca-prefill`, omp 재시작, 다시 켜면 파일 삭제. 사진 `red.png` 첨부 → prompt 프레임에 `images`, 답 "흰 배경 위에 가로로 긴 빨간색 직사각형". 폴더 추가 → omp `command_output` "Added …". 32-bit IDE: 메뉴와 커넥터 목록. 오류 창 없음 |
| 프로젝트 맞춤 도구 | 64-bit IDE, VCL Smoke: 명령줄에 `--config omp-host.yml --append-system-prompt project-guide.md`, `.omp/lsp.json` 생성, 도구 28개(폼 도구 포함). "메모장 UI" 요청 → `rad.form_apply`로 Memo1·MainMenu1, 메뉴 항목, `rad.apply_edits`로 핸들러, 컴파일 오류 0. 여기서 찾은 ShortCut 텍스트(`Ctrl+N`) 변환 실패를 고쳤다. FMX 프로젝트: 안내에 `Framework: FMX`, "계산기 UI" 요청이 턴마다 한 번 승인으로 승인 1번, 31초, `form_apply`로 TEdit 3개·TButton, 컴파일 오류 0, 파일 카드 `Unit1.pas +10 -2`. 콘솔 프로젝트: 폼 도구 없이 등록, `project_info` → `set_build_config`(Release) → `new_module kind=form`(IDE가 VCL 프레임워크를 켤지 물음) → 폼 도구 8개가 다시 등록되고 `form_apply`로 Button1. 32-bit IDE: FMX 프로젝트에서 도구 28개, 안내 `Framework: FMX`. C++Builder 프로젝트는 확인하지 않음 |
| 작업 언어 영어 규칙 | omp 18.2.11, claude-opus-5-5, 생각 medium, 같은 한국어 질문(MainForm.pas·Smoke.dpr 읽고 개선점 3가지) 규칙 없음/있음 각 2회: 출력 토큰 1469·1413 / 1453·1419. 규칙이 없어도 생각은 이미 영어였고(한글 0자), 출력은 한국어 최종 답이 대부분이라 줄지 않았다. 설정은 남기되 기본 꺼짐. |
| 디스크 기준·git 체크포인트 | `build-tests` ALL PASSED(임시 저장소: init·.gitignore·첫 커밋, 체크포인트가 HEAD를 안 움직임, 프롬프트 보존, 되돌리기로 바뀐 파일 복원·새 파일 삭제, 되돌리기 취소, 브랜치 전환). 64-bit IDE, 새 Smoke: `git init` 알림, 메시지 1 → `cp/000001`, omp `edit`가 디스크를 고치고 에디터가 대화상자 없이 다시 읽음. 메시지 2 뒤 `↶ 여기로 되돌리기` → `// second` 사라짐(디스크·에디터), `before-restore/000001`, omp `branch`로 대화 1개로 줄고 메시지 2가 입력칸에. 불러온 기록의 메시지에도 되돌리기 단추. `⑂ 여기서 브랜치` → `radagent/<시각>` 브랜치, `git status` 깨끗. 항상 묻기에서 omp `edit` 승인 카드 → 승인 → 반영. `rad.form_apply` 승인 후 `.dfm`/`.pas` 저장됨. 32-bit IDE: 메시지 → 체크포인트, 디스크 편집 다시 읽기. |
| 메뉴 아이콘 | 64-bit·32-bit IDE: View 메뉴 RADAgent 항목에 `MenuIcon` 아이콘(INTAServices280.AddImage, 16·32px). 원본 그래픽을 넘긴 뒤 해제해도 그려져 IDE가 복사함을 확인. 에디터·메시지 오른쪽 클릭 메뉴는 IDE가 항목 비트맵을 그리지 않아(두 메뉴에서 확인) 글자만 둔다. |
| omp 업데이트 대비 | `build-tests` ALL PASSED: v2 조각 재조립(1.5MB 한글 프레임, 끊긴 조각 거절, 1MiB 넘는 물리 줄 버림), 프로토콜 선택, 승인 선택지 뜻 맞춤, `agentInvoked:false`/`prompt_result`/`command_output`, 실제 omp 18.2.11 호환성 검사 10항목 통과. 64-bit IDE: 시작 때 `negotiate_protocol` v2 성공, 레지스트리 `OmpCheckedVersion=18.2.11` 기록, `/context` 출력이 표로 보이고 턴이 끝남, 설정 → 고급 → omp 호환성 검사 대화상자 10항목 통과. 32-bit IDE: `/context` 동일. |
| /btw 곁가지 질문 | 64-bit IDE, Smoke: 본 턴(`rad.read_buffer` 표 정리)이 도는 중에 `/btw` → 본 턴 `agent_end` 전에 별도 자식(`--no-tools --fork`)이 대화 요약으로 답, 본 대화 프롬프트에 btw 없음. 카드 이어 묻기 → `--resume`으로 앞 답을 기억. 메모 창: 목록·펼침·삭제 확인·새 질문, 스트리밍 중 머리글 `중지` → abort 프레임, 0.7초 뒤 `agent_end`, 부분 답 `중지됨`. IDE 다시 시작 후 메모 유지, 채팅 창 다시 열면 카드 재표시. `# `으로 시작하는 스트리밍 답에서 `markdown.js`가 멈추던 문제 고침. 32-bit IDE: `/b` 메뉴에 `/btw <질문>`, 답 카드. |
| 채팅 승인·계획·@ 파일 | 64-bit IDE, Smoke: `@Ma` → `MainForm.dfm/.pas` 목록, 선택 후 질문에 도구 없이 답. 더티 `MainForm.pas`의 `@MainForm.pas`가 `@...\snap-0-MainForm.pas`로 바뀌고 저장 안 한 주석을 읽음. 항상 묻기에서 `rad.apply_edits` 승인 카드 → 승인(`✓ 승인됨`, 파일 카드), 거부(`{"ok":false,"cancelled":true}`), 중지로 떠 있는 카드 거부와 abort. 계획 모드: `docs\plans\2026-09-24-0130-add-clear-button.md`(여섯 절), 계획 카드, Project Manager에 `docs`, 진행 → 항상 묻기로 돌아가 `rad.form_apply` 승인 카드. 오류 대화상자 없음. 32-bit IDE: `@Sm` 목록, 권한 무시 편집 반영. |
| 승인 방식 통합 | 64-bit IDE, Smoke: 권한 무시에서 `rad.apply_edits`가 승인 창 없이 반영. 항상 묻기로 바꾸자 `radagent.yml`에 `approvalMode: always-ask`, 편집 두 번에 RADAgent 승인 창 두 번(omp의 `Allow tool: write` 창은 자동 통과). 쓰기 허용에서 편집 두 번에 승인 창 한 번. 권한 무시로 되돌리자 파일 삭제. 마지막 줄 편집마다 파일 끝에 빈 줄이 늘던 문제(버퍼 전체를 다시 쓰면 IDE가 마지막 줄바꿈을 남김)와 모델이 줄 번호를 잘못 세던 문제를 고쳐, 두 턴 뒤에도 `end.` 뒤 빈 줄 없이 정확한 위치에 들어감(`rad.read_buffer`가 `N|` 줄 번호를 줌). 컴파일 오류 0 |
| RADAgent 이름 바꾸기 | `build-tests` ALL PASSED. 64-bit IDE: 옛 `...\37.0\DelphiAgent` 레지스트리 키가 `...\RADAgent`로 옮겨지고 옛 키는 지워짐, 프로젝트 `.omp\delphiagent.yml` → `radagent.yml`, `refs/delphiagent/cp/000007` → `refs/radagent/cp/000007`, `%LOCALAPPDATA%\DelphiAgent\btw` → `RADAgent\btw`. View 메뉴 `RADAgent` 항목과 아이콘. 32-bit IDE: 같은 메뉴·아이콘. 오류 창 없음 |
| 여러 언어 화면 | `build-tests` ALL PASSED: 네 번역 표가 영어 키 374개(+ `.one` 8개)를 모두 갖고 자리표시자가 같음, 한국어 전환, 모르는 키, `.one` 단수 문구, 페이지 문자열 메시지. 64-bit IDE(Windows 한국어): 처음 `자동 (한국어)`, 설정에서 English → 채팅 제목·입력칸·승인 방식·생각 수준이 바로 영어, IDE를 다시 켜도 영어. Français → 설정 창·재시작 확인 창·채팅이 프랑스어, 쓰기 허용에서 `rad.form_apply` 승인 카드(`Demande d'approbation`, `+ Ajouter Button2 : TButton`), 승인 후 답. 32-bit IDE: Deutsch → 컴파일 턴 `1 Tool verwendet`, 체크포인트 단추 `Hierhin zurückkehren`/`Branch ab hier`. 日本語 → 설정 창과 채팅, `ツールを 1 個使用`. 자동으로 되돌리면 한국어, 레지스트리 `Language`는 빈 값. 에디터 오른쪽 클릭에 `RADAgent: 선택 영역 설명/고치기`. 이미 보낸 알림은 보낸 때의 언어로 남는다. 입력 아래 줄은 좁은 창에서도 한 줄(선택 상자가 줄어듦). 오류 창 없음 |
| 중지가 듣지 않던 문제 | 원인: ollama 연결 실패로 omp가 보낸 `auto_retry_start`의 `delayMs`가 소수(484.54)였고 `JsonInt`의 `AsInt64`가 `EConvertError`를 내 읽기 스레드가 끝났다. omp는 살아 있었지만 아무도 stdout을 읽지 않아 abort 답·턴 끝이 오지 않았다. 고침: `JsonInt`는 반올림, 읽을 수 없는 프레임은 버리고 읽기를 계속(`RpcDispatch.Deliver`), 시험에 소수 `delayMs` 추가(고치기 전 실패 확인). 중지(`RADAgent.ChatStop`): abort 후 5초 또는 두 번째 누름이면 omp를 끝내고 같은 세션으로 다시 시작. 64-bit IDE: omp를 일시 정지시킨 턴에서 중지 한 번 → 7.6초 뒤 새 omp, 두 번 누름 → 3.4초, 앞 대화 기록 복원, 정상 omp는 abort로 0.3초에 끝나고 재시작 없음. 32-bit IDE: 일시 정지 → 7.9초 뒤 새 omp, 이어서 질문에 답. 오류 창 없음 |
| IDE Git 연동 멈춤 | 32-bit IDE에서 에디터 오른쪽 클릭 때 IDE가 멈췄다. 스택: `gitide370 TGitClient.IsVersioned` → `ReadFile`. IDE의 Git 실행 파일 설정(`HKCU\...\37.0\VersionInsight\Git\Executable`)이 `git-cmd.exe`여서 `cmd /K`가 끝나지 않았다. RADAgent가 프로젝트를 git 저장소로 만들면 IDE Git 연동이 켜져 드러난다. RADAgent 코드 문제가 아니고 설정을 `cmd\git.exe`로 바꾸면 된다(README에 적음) |
| Kai 종료 AV | 아래 절 참고. RADAgent 원인이 아니다. Kai를 PC에서 삭제한 뒤에는 재현되지 않는다 |

### Kai 종료 AV

64-bit IDE를 닫을 때 `Access violation at address 00007FFC8B476DDA in module 'coreide370.bpl' (offset 666DDA). Read of address 0000000000000010.`이 뜨고 이어서 `Runtime error 231`이 두 번 뜬 뒤 IDE가 죽는 문제다.

- 조건: `.dproj` 없이 `.dpr`을 열어 IDE가 프로젝트를 새로 만든 상태에서 IDE를 닫고, "Save changes to project Smoke?"에 **No**를 누른다.
- 원인: Kai 패키지(`Kai370.bpl`). 주소는 `coreide370.bpl`의 `GetModuleCount`이고, 프로젝트가 닫힌 뒤 비어 있는 모듈 목록을 읽는다.
- 2026-09-23 격리 결과 (같은 조건, 64-bit IDE):

  | Known Packages x64 | AV |
  | --- | --- |
  | 전부 | 있음 |
  | RADAgent 뺌 | 있음 |
  | RAD Agent 뺌 | 있음 |
  | Kai만 뺌 (RADAgent 창 열어 둠) | 없음 |
  | RADAgent, RAD Agent 뺌 (Kai만 남김) | 있음 |
  | Kai, RAD Agent, RADAgent 뺌 | 없음 |
  | 전부, `Smoke.dproj`을 열고 RADAgent 창 열어 둠 | 없음 |
  | 전부, `Smoke.dproj`, 수정한 `MainForm.pas`를 저장 안 하고 닫음 | 없음 |

- 대응: 확인용 앱에 `Smoke.dproj`을 넣었다. Kai는 참조하지도 래핑하지도 않으므로 코드로 막지 않는다.
- 2026-09-23 Kai 삭제 후 재확인 (RADAgent, RAD Agent 로드, RADAgent 창 연결 상태로 닫음):

  | 연 파일 | 닫을 때 | 결과 |
  | --- | --- | --- |
  | `Smoke.dpr` (`.dproj` 없음) | Confirm → No | 오류 창 없음, 종료 코드 0. 2회 |
  | `Smoke.dproj` | Confirm 없음 | 오류 창 없음 |

## MVP 확인 결과 (2026-09-23)

아래 두 절(결과와 절차)은 저장하지 않던 시절(스냅샷, `rad.apply_edit`)의 기록이다. 2026-09-24부터는 디스크 기준과 git 체크포인트로 바뀌었으므로, 3·4·5·6단계는 위 "검증 기록"의 "디스크 기준·git 체크포인트" 줄로 대신한다.

64-bit IDE와 32-bit IDE에서 아래 절차를 모두 진행했다. 확인용 프로젝트의 활성 플랫폼은 두 IDE 모두 Win64다. 결과는 IDE 창, 채팅창, 메시지 뷰, `rpc.log`, 디스크 파일을 직접 읽어 확인했다. IDE가 오류 창을 띄우는지도 매 단계 확인했고, 오류 창은 한 번도 뜨지 않았다.

| 단계 | 64-bit | 32-bit |
| --- | --- | --- |
| 1 연결 | 통과. 상태줄 pid가 omp 자식 pid와 같다 | 통과 |
| 2 일반 질문 | 통과 | 통과 |
| 3 스냅샷 | 통과. `snap-0-MainForm.pas`에 `Sum=`, 디스크는 `Total=` | 통과 |
| 4 승인 취소 | 통과. 승인 창이 떠 있는 동안 38줄은 `Sum=` | 통과 |
| 5 승인 | 통과. 한 번의 실행 취소 단위로 `Sum=`로 돌아가고, 다시 실행하면 `Answer=` | 통과 |
| 6 충돌, 캐럿 삽입 | 통과 (절차를 고쳐서) | 통과 |
| 7 컴파일 성공 | 통과. `Debug`, `Win64`. 디스크 변경 없음 | 통과 |
| 8 컴파일 오류 | 코드를 고친 뒤 통과. `MainForm.pas`, 37, 13, `E2003 Undeclared identifier: 'Totl'` | 통과 |
| 9 중지 | 통과. pid 같음, 이어서 답이 옴 | 통과 |
| 10 디버거 | 통과. 30줄, `Total(10)` → `Button1Click`, Index=1, Count=10, 중단점 30줄 enabled | 통과 |

이 확인 중에 고친 것:

- 8단계: `rad.compile`의 `errors`가 컴파일러 오류 대신 `Smoke.dproj`, 0, 0, `빌드 실패`만 돌려줬다. `IOTAModuleErrors.GetErrors('')`는 항상 비어 있고, 파일 이름을 넘겨야 Error Insight 결과가 나온다. 편집 직후 빌드하면 Error Insight가 몇 초 늦으므로, 빌드가 실패하고 오류가 없으면 최대 8초 동안 메시지를 처리하며 다시 읽는다. `RADAgent.Compile.CollectErrors`, `CollectErrorsAfterFailure`.
- 채팅창: 모델 답의 줄바꿈(`\n`)이 `TMemo`에 보이지 않아 표가 한 줄로 붙었다. `AppendLog`에서 CRLF로 바꾼다. 한 턴 안의 텍스트 블록끼리도 붙어 있었으므로 `text_end`에서 줄을 바꾼다.
- 10단계: `rad.debug_stack`의 `header`에 폼 전체가 인자로 덤프되어 결과가 129KB였고, omp가 중간 프레임을 잘랐다. 헤더를 240자로 자른다. 같은 호출이 14KB가 됐다.

남은 것:

- Error Insight가 잡지 못하는 오류(링커 오류 등)는 여전히 `빌드 실패` 한 줄만 나온다. 공개 ToolsAPI에는 메시지 뷰의 컴파일러 메시지를 읽는 API가 없다.

## MVP 한 바퀴 확인 절차

AGENTS.md 범위 조건이다. 폼 디자이너는 이것이 통과한 뒤에 시작한다. 64-bit IDE에서 한 번, 32-bit IDE에서 한 번 한다. 한 번에 30분쯤 걸린다.

각 단계는 **할 일**, **입력할 문장**, **통과 조건**으로 되어 있다. 통과 조건과 다르면 거기서 멈추고, 단계 번호와 화면에 보인 내용을 알려 준다. 원인은 `%TEMP%\RADAgent\rpc.log`에서 찾는다.

입력할 문장은 RADAgent 창 아래 입력 상자에 그대로 붙여 넣고 Enter(또는 오른쪽 ↑)를 누른다. 경로 `C:\Users\kimmi\AppData\Local\Temp\RADAgentSmoke`는 이 PC의 `%TEMP%\RADAgentSmoke`다. 다른 PC에서는 그 PC의 경로로 바꾼다.

### 화면 설명

RADAgent 창의 구성은 다음과 같다.

- 위 막대: 세션 제목(누르면 세션 목록), 프로젝트 이름, **＋**(새 세션), **⤓**(내보내기), **⚙**(설정).
- 가운데: 채팅 기록. 보낸 문장은 오른쪽 말풍선이다.
- 아래: 입력 상자(오른쪽 ↑가 보내기, 작업 중에는 ■ 중지). 그 아래 줄에 **＋**(파일 경로 넣기, 컴파일), 승인 방식, 모델, 생각 수준, 컨텍스트 원, 연결 점.

omp가 IDE 도구(`rad.*`)를 부르면 채팅에 접힌 도구 줄로 보인다. 로그에서 확인하려면 PowerShell에서 다음을 실행한다.

```powershell
Select-String -Path "$env:TEMP\RADAgent\rpc.log" -Pattern '"toolName":"rad\.[a-z_]+"' | Select-Object -Last 3
```

### 이 절차로 확인하는 수정 (2026-09-23)

- `rad.apply_edit`도 스냅샷 충돌을 검사한다. 프롬프트를 보낼 때 열린 버퍼 전부를 기억하므로, 저장된 버퍼도 검사 대상이다. 6단계에서 확인한다.
- `rad.apply_edit`의 `content`는 버퍼 전체를 교체한다. 예전에는 맨 앞에 끼워 넣었다.
- 줄 범위 교체에서 `newText` 끝에 줄바꿈이 없으면 붙인다. 4~5단계에서 확인한다.
- 프로젝트를 RADAgent 창보다 나중에 열어도, 그 순간 omp가 프로젝트 폴더에서 다시 뜬다. 채팅에 `프로젝트 폴더가 바뀌어 omp를 다시 시작합니다`가 찍힌다. 준비 7~9번의 순서를 바꿔 확인할 수 있다.

### 준비 (IDE마다 한 번)

1. 열려 있는 RAD Studio를 모두 닫는다.
2. 저장소에서 `scripts\build-win64.cmd`를 실행한다. 32-bit 차례에는 `scripts\build-win32.cmd`를 실행한다.
3. `scripts\prepare-smoke.cmd`를 실행한다. `%TEMP%\RADAgentSmoke`에 확인용 VCL 앱 `Smoke.dproj`, `Smoke.dpr`, `MainForm.pas`, `MainForm.dfm`이 새로 복사된다. 원본은 `tests\smoke`다.
4. PowerShell에서 이전 로그를 지운다.

   ```powershell
   Remove-Item "$env:TEMP\RADAgent\rpc.log" -ErrorAction SilentlyContinue
   ```

5. IDE를 실행한다. 64-bit는 `%BDS%\bin64\bds.exe`, 32-bit는 `%BDS%\bin\bds.exe`다.
   - 32-bit에서는 먼저 Component → Install Packages → Add로 `C:\Users\Public\Documents\Embarcadero\Studio\37.0\Bpl\RADAgent370.bpl`을 등록한다.
6. Tools → Options를 연다. 왼쪽 위 검색칸에 `Autosave`를 입력하고 **Editor files**의 체크를 끈다. 켜져 있으면 빌드할 때 파일이 저장되어 "저장하지 않는다" 확인이 무의미해진다.
7. File → Open Project로 `%TEMP%\RADAgentSmoke\Smoke.dproj`을 연다. `Smoke.dpr`을 열지 않는다(위 "Kai 종료 AV"). Project Manager에서 `MainForm.pas`를 더블클릭하고, F12로 코드 탭을 연다.
8. 확인에 쓰는 줄 번호는 다음과 같다.

   | 줄 | 내용 |
   | --- | --- |
   | 30 | `Result := Result + Index;` |
   | 37 | `Answer := Total(10);` |
   | 38 | `Label1.Caption := 'Total=' + IntToStr(Answer);` |

9. View(또는 Tools) → **RADAgent**로 창을 연다.

확인 중에 IDE가 "파일이 디스크에서 바뀌었다"고 물으면, omp가 디스크 파일을 직접 고친 것이다. **아니오**를 누르고 그 단계를 실패로 알려 준다.

### 1. 연결

- **할 일:** 창을 연 뒤 5~20초 기다린다.
- **통과 조건:**
  - 입력 아래 줄 오른쪽 점이 초록이고 모델 이름이 보인다. 위 막대 제목에 마우스를 올리면 `프로젝트 Smoke · pid <0이 아닌 숫자> · ...\RADAgentSmoke`가 보인다.
  - 입력 상자에 글자를 넣으면 ↑ 단추가 켜진다.
  - 이 pid를 적어 둔다. 9단계에서 비교한다.

### 2. 일반 질문

- **입력할 문장:**

  ```text
  MainForm.pas의 Total 함수가 무엇을 계산하는지 한 문장으로 설명해줘. 파일은 수정하지 마.
  ```

- **통과 조건:** 채팅에 `> MainForm.pas의 ...`가 찍히고, 이어서 "1부터 Count까지의 합"이라는 취지의 답이 흘러나온다.

### 3. 저장 안 한 편집이 omp에 전달된다 (스냅샷)

- **할 일:** 에디터 38줄의 `'Total='`을 `'Sum='`으로 고친다. **저장하지 않는다.** 탭 이름에 수정 표시가 붙는다.
- **입력할 문장:**

  ```text
  이 메시지에 붙은 Dirty buffer snapshots 파일을 읽고, MainForm.pas 38번째 줄의 Label1.Caption 접두사 문자열이 무엇인지만 알려줘. 파일은 수정하지 마.
  ```

- **통과 조건:**
  - 답이 `Sum=`이다. `Total=`이라고 하면 실패다.
  - `%TEMP%\RADAgent\`에 `snap-<숫자>-MainForm.pas` 파일이 있고, 그 안에 `Sum=`이 있다. 숫자는 수정된 파일 순서라 0이 아닐 수 있다.
  - 메모장으로 연 `%TEMP%\RADAgentSmoke\MainForm.pas`(디스크 원본)는 여전히 `Total=`이다.

### 4. 승인 전에는 버퍼가 바뀌지 않는다 (취소)

- **입력할 문장:**

  ```text
  디스크 파일은 절대 수정하지 마. rad.apply_edit 도구만 써서 버퍼를 고쳐줘. path는 C:\Users\kimmi\AppData\Local\Temp\RADAgentSmoke\MainForm.pas, startLine과 endLine은 모두 "38", newText는 "  Label1.Caption := 'Answer=' + IntToStr(Answer);" 야.
  ```

- **할 일:** 제목이 `RADAgent`인 승인 창이 뜬다. 창 안에는 파일 경로와 새 줄이 보인다. 창이 떠 있는 동안 뒤의 에디터 38줄이 아직 `Sum=`인지 본다. 그다음 **취소**를 누른다.
- **통과 조건:**
  - 승인 창이 떠 있는 동안 버퍼가 바뀌지 않는다.
  - 취소 뒤에도 38줄은 `Sum=`이다.
  - omp는 취소되었다고 답한다.
  - PowerShell 명령 결과에 `"toolName":"rad.apply_edit"`가 있다.

### 5. 승인하면 버퍼만 바뀌고 저장되지 않는다

- **입력할 문장:**

  ```text
  방금 요청을 똑같이 다시 시도해줘. 이번에는 승인할게.
  ```

- **할 일:** 승인 창에서 **승인**을 누른다.
- **통과 조건:**
  - 에디터 38줄이 `  Label1.Caption := 'Answer=' + IntToStr(Answer);`로 바뀐다.
  - 37줄과 39줄은 그대로이고, 줄이 붙거나 빈 줄이 생기지 않는다.
  - 탭에 수정 표시가 남아 있다.
  - 메모장으로 연 디스크 원본은 여전히 `Total=`이다.
  - Ctrl+Z 한 번이면 `Sum=`으로 돌아간다. 확인한 뒤 Ctrl+Shift+Z(또는 Ctrl+Y)로 다시 `Answer=`로 되돌린다.

### 6. 스냅샷 뒤에 사람이 고치면 덮어쓰지 않는다 (충돌)

- **입력할 문장:**

  ```text
  먼저 bash로 sleep 20을 실행하고, 끝나면 rad.apply_edit 도구로 path C:\Users\kimmi\AppData\Local\Temp\RADAgentSmoke\MainForm.pas, startLine과 endLine "30", newText "    Result := Result + Index * 1;" 로 버퍼를 고쳐줘. 디스크 파일은 수정하지 마.
  ```

- **할 일:** 보낸 직후 20초 안에 에디터를 클릭하고, 37줄 끝에 ` // user`를 친다. 스페이스 하나는 안 된다. 에디터가 줄 끝 공백을 지워 버퍼가 스냅샷과 같아지므로 충돌이 나지 않는다. omp가 bash 실행 확인을 물으면 승인한다.
- **통과 조건:**
  - 승인 창이 뜨지 않는다.
  - 채팅에 `충돌: 스냅샷 이후 버퍼가 바뀌어 반영하지 않았습니다. ...MainForm.pas`가 찍힌다.
  - 30줄은 `Result := Result + Index;` 그대로다.
- **대조 확인:** 같은 문장을 다시 보내되 이번에는 에디터를 건드리지 않는다. 승인 창이 뜨고, **승인**하면 30줄만 `Result := Result + Index * 1;`로 바뀐다.
- **캐럿 삽입:** 38줄 끝에 캐럿을 두고 `rad.insert_at_caret 도구로 text "  // agent" 를 삽입해줘.`를 보낸다. 승인하면 38줄 끝에 `  // agent`가 붙는다.

### 7. 컴파일 성공이 메시지 뷰에 보인다

- **할 일:** 입력 아래 줄의 **＋** → **프로젝트 컴파일**을 누른다. 컴파일 진행 창은 뜨지 않을 수 있다.
- **통과 조건:**
  - 채팅에 `컴파일 성공`이 찍힌다.
  - Messages 창(View → Messages)에 `RADAgent` 도구 이름으로 `빌드 성공` 줄이 있다.
  - 탭의 수정 표시가 그대로 남아 있다. 저장되지 않았다.
- **입력할 문장:**

  ```text
  rad.compile 도구로 빌드하고 결과 JSON의 ok, config, platform 값만 알려줘.
  ```

- **통과 조건:** `ok`가 `true`이고, `config`와 `platform`이 IDE Project Manager에 보이는 활성 구성과 같다.

### 8. 컴파일 오류 위치가 메시지 뷰와 같다

- **할 일:** 37줄의 `Total(10)`을 `Totl(10)`로 고치고 **＋** → **프로젝트 컴파일**을 누른다.
- **통과 조건:**
  - 채팅에 `컴파일 실패. 오류는 메시지 창에 있습니다.`가 찍힌다.
  - Messages 창에 `[dcc64 Error]`(32-bit 프로젝트면 `[dcc32 Error]`) `MainForm.pas(37): E2003 Undeclared identifier: 'Totl'` 같은 줄과 RADAgent의 `빌드 실패` 줄이 있다.
- **입력할 문장:**

  ```text
  rad.compile 도구로 빌드하고 errors 배열의 file, line, col, msg를 그대로 보여줘.
  ```

- **통과 조건:** `line`이 37이고, `msg`가 Messages 창의 오류 문장과 같다.
- **정리:** 37줄을 `Total(10)`으로 되돌린다.

### 9. 중지는 턴만 끊고 omp는 살아 있다

- **입력할 문장:**

  ```text
  1부터 100까지 숫자마다 그 숫자의 특징을 한 줄씩 써줘.
  ```

- **할 일:** 답이 흘러나오기 시작하면 입력 상자 오른쪽 ■(중지)를 누른다.
- **통과 조건:**
  - 몇 초 안에 출력이 멈춘다.
  - 위 막대 제목의 툴팁 pid가 1단계에서 적어 둔 값과 같다.
  - 이어서 `안녕`을 보내면 답이 온다.

### 10. 디버거 도구는 읽기만 한다

- **할 일:**
  1. 30줄 왼쪽 여백을 클릭해 중단점을 건다(F5).
  2. Run → Run(F9)으로 실행한다.
  3. `RADAgent Smoke` 창의 **Run** 버튼을 누른다. IDE가 30줄에서 멈춘다.
- **입력할 문장:**

  ```text
  rad.debug_state, rad.debug_stack, rad.debug_breakpoints를 차례로 호출하고, rad.debug_evaluate로 Index와 Count를 각각 평가해서 결과를 그대로 보여줘. 실행을 재개하거나 코드를 고치지 마.
  ```

- **통과 조건:**
  - state: `"state":"stopped"`, `file`이 `MainForm.pas`, `line`이 30이다.
  - stack: 첫 프레임에 `Total(10)`이, 그다음 프레임에 `Button1Click`이 들어 있다. 앞에 `MainForm.` 같은 유닛 이름이 붙을 수 있다. Call Stack 창(Ctrl+Alt+S)과 순서가 같다.
  - evaluate: `Index` = 1, `Count` = 10이다. Evaluate/Modify 창(Ctrl+F7) 값과 같다.
  - breakpoints: `MainForm.pas` 30줄, `enabled: true`이다. Breakpoints 창(Ctrl+Alt+B)과 같다.
  - 답이 끝난 뒤에도 IDE는 여전히 30줄에 멈춰 있다. 파란 실행 위치 화살표가 그대로이고 Smoke 창은 응답하지 않는다.
- **정리:** Run → Program Reset(Ctrl+F2).

### 끝난 뒤

- 결과는 "64-bit: 1~10 통과" 또는 "32-bit: 6단계 실패, 채팅에 ○○가 찍힘"처럼 알려 준다. 그 결과를 이 문서의 검증 기록에 옮기고, 실패한 단계는 고친다.
- 다른 비트 IDE로 할 때는 그 IDE를 닫고, 준비 1번부터 다시 한다. `prepare-smoke.cmd`가 확인용 앱을 새로 복사한다.
