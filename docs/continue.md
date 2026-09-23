# 다음 작업을 위한 메모

2026-09-23에 MVP 채팅까지 동작하는 상태에서 멈춘 기록이다. 새 아키텍처를 만들지 말고, 여기와 `DESIGN.md`, `AGENTS.md`를 기준으로 잇는다.

## 목적

RAD Studio 안에서 사람이 쓰는 폼 디자이너, 디버거 같은 IDE 기능을 활용해 코딩을 돕는 oh-my-pi(omp) 에이전트다.

터미널에 omp 화면을 임베드하지 않는다. ToolsAPI는 `bds.exe` 안에서만 호출할 수 있으므로, BPL이 host-tool을 열고 omp가 RPC로 그 도구를 부른다.

## 두 층

| 층 | 하는 일 | 하지 말 것 |
| --- | --- | --- |
| 채팅창 → 기존 omp RPC | `/model`, `/fast`, `/thinking`, `/effort`, `/clear`, `/goal`, `/switch`처럼 omp가 이미 처리하는 명령 | Delphi로 omp 명령을 새로 만들기. 없는 `type`을 발명하기 |
| BPL host-tool | IDE 안에만 있는 동작. 컴파일, 버퍼, 나중에는 디자이너와 디버거 | omp가 ToolsAPI를 직접 호출하게 하기. KAI, Ghost Text, `IOTAAIPlugin` |

stdin에는 JSONL만 쓴다. 일반 텍스트 한 줄이면 omp가 죽는다. `@file`은 RPC가 거절한다. 프레임 원문은 채팅에 찍지 않고 `%TEMP%\DelphiAgent\rpc.log`에만 남긴다.

## 지금 되는 것

- 64-bit IDE에서 Tools 또는 View의 DelphiAgent 도킹 창.
- `omp --mode rpc`. `ready` 뒤에만 명령. 모델 응답 스트림.
- 상태줄: `[연결됨|대기|오류]  pid=  프로젝트=  폴더=` 와 `get_state`의 모델명.
- 프로젝트 해석: 프로젝트 그룹, 열린 모듈, 에디터 옆 `.dproj`, 마지막 캐시. 없으면 `프로젝트=없음`.
- 슬래시 명령은 모달로 고른 뒤 기존 RPC만 전송.
- omp가 보내는 `extension_ui_request`의 select, confirm, input, editor는 모달. notify와 setStatus는 로그.
- host-tool: `rad.compile`, `rad.open_buffer`, `rad.insert_at_caret`, `rad.list_dirty`, `rad.read_buffer`, `rad.apply_edit`.
- `rad.apply_edit`와 캐럿 삽입은 적용을 누르기 전에 버퍼를 고치지 않는다. 디스크 Save는 하지 않는다.
- omp 실행 파일은 PATH의 `omp.exe`, 없으면 `%LOCALAPPDATA%\omp\omp.exe`.

메뉴 등록은 `ViewsMenu`, `ViewMenu`, `ToolsMenu`, `HelpMenu` 순으로 있는 이름에만 `AddActionMenu`한다. RAD Studio 13.2의 View 메뉴 컴포넌트 이름은 `ViewsMenu`다. `ViewMenu`로 고정하면 패키지 로드가 실패한다.

프레임 DFM은 `src/DelphiAgent.DockForm.dfm`이다. `TTimer`는 DFM에 없고 `FrameCreated`에서만 만든다.

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
| 상태줄 | `DelphiAgent.DockForm.RefreshStatus` |
| 프로젝트 해석 | `DelphiAgent.IdeContext.CurrentProject`, `ActiveProjectFile` |
| 슬래시 분류 | `DelphiAgent.ChatCommand.ClassifyChat` |
| 모달 | `DelphiAgent.AskDialog` |
| host-tool 실행 | `DelphiAgent.HostTools.ExecuteHostTool` |
| 컴파일 | `DelphiAgent.Compile.BuildActiveProjectJson` |
| RPC 프로세스 | `DelphiAgent.RpcClient` |

한 파일은 400줄을 넘기지 않는다. 넘기면 같은 책임 안에서만 나눈다.

## 아직 하지 않은 것

폼 디자이너 host-tool, 디버거 host-tool, Ghost Text, `IOTAAIPlugin`, KAI, 터미널 임베드는 하지 않았다. 디자이너나 디버거를 넣을 때도 omp가 ToolsAPI를 직접 부르게 하지 말고, 지금 host-tool과 같은 방식으로 BPL이 메인 스레드에서 호출하게 한다.

## 빌드

64-bit IDE가 BPL을 열고 있으면 덮어쓸 수 없다. IDE를 종료한 뒤 `scripts\build-win64.cmd`를 실행한다. 결과:

`C:\Users\Public\Documents\Embarcadero\Studio\37.0\Bpl\Win64\DelphiAgent370.bpl`

이미 설치되어 있으면 IDE를 다시 연다. 32-bit는 `scripts\build-win32.cmd`와 `Bpl\DelphiAgent370.bpl`이다. 한 BPL을 양쪽 Known Packages에 넣지 않는다.
