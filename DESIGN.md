# DelphiAgent 설계

design-time BPL이 RAD Studio IDE 안에서 Chat을 띄우고, omp 18.2.11 자식 프로세스에 JSONL RPC로 프롬프트를 넘긴다. 에이전트 루프, 도구 실행, LSP 세션은 omp가 소유한다.

## 아키텍처

```
+-------------------- bds.exe (32-bit 또는 64-bit, 하나만) --------------------+
| DelphiAgent BPL (그 IDE와 같은 비트)                                          |
|                                                                              |
|  Wizard                                                                      |
|    Register 시 DockForm 등록                                                 |
|  DockForm (Chat)                                                             |
|    |  프롬프트 직전                                                           |
|    v                                                                         |
|  DirtyBuffers  ---- 읽기 ---- IdeContext                                     |
|    |  스냅샷 (저장하지 않음)                    활성 .dproj, 에디터 버퍼       |
|    v                                                                         |
|  RpcClient  ==== JSONL stdin/stdout ===>  omp --mode rpc                     |
|    ^                                         cwd = .dproj 디렉터리           |
|    |  host_tool_call / result                 tools + 자체 LSP               |
|  HostTools                                      |                            |
|    승인 후 IDE 버퍼 반영                        v                            |
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
| DockForm | `INTACustomDockableForm` Chat. 프롬프트 입력, 스트림 표시, 승인, 중단. |
| RpcClient | `omp --mode rpc` 자식 프로세스와 읽기 스레드. `ready` 전 프롬프트 금지. |
| RpcProtocol | JSONL 프레임 생성과 판별. ToolsAPI 없음. |
| RpcDispatch | stdout 줄을 프레임 종류별로 나눠 이벤트로 넘긴다. ToolsAPI 없음. |
| ChatCommand | 채팅 입력을 기존 omp RPC 프레임으로 분류한다. 새 명령 `type`을 만들지 않는다. |
| AskDialog | `extension_ui_request`와 슬래시 명령 선택 모달. |
| Options | omp 실행 파일, 명령줄, `%TEMP%\DelphiAgent` 로그 경로. |
| IdeContext | 활성 `.dproj` 경로, 열린 모듈, 에디터 버퍼 위치. |
| DirtyBuffers | 프롬프트 전 더티 버퍼 스냅샷과 충돌 판정. 자동 저장 기본 꺼짐. |
| Compile | 활성 프로젝트 빌드와 완료 통지. 결과는 메시지 뷰로 보낸다. |
| HostToolDefs | host-tool 이름과 `set_host_tools` 스키마. ToolsAPI 없음. |
| HostTools | host-tool 호출을 도구별 구현으로 나눠 보낸다. 버퍼 읽기, 컴파일. 메인 스레드에서만 ToolsAPI를 호출한다. |
| BufferEdits | 승인 후 IDE 버퍼 반영(줄 범위, 전체, 캐럿 삽입). 스냅샷 이후 버퍼가 바뀌었으면 반영하지 않는다. 저장하지 않는다. |
| DebugTools | 디버거 상태, 호출 스택, 부작용 없는 식 평가, 중단점 목록. 읽기 전용. 실행 제어는 하지 않는다. |

## 데이터 흐름

1. 사용자가 DockForm에 프롬프트를 보낸다.
2. DirtyBuffers가 수정된 IDE 버퍼의 사본을 `%TEMP%\DelphiAgent`에 쓰고 그 경로를 프롬프트에 붙인다. 원본 파일은 저장하지 않는다.
3. RpcClient가 `ready`를 받은 뒤에만 `prompt` 프레임을 쓴다.
4. omp가 도구와 LSP로 답을 만든다. DelphiLSP는 omp 설정의 별도 인스턴스다.
5. omp가 파일을 고치면 패치는 디스크에 남는다. IDE 버퍼는 아직 그대로다.
6. 사용자가 승인하면 HostTools가 그 텍스트를 IDE 버퍼에 쓴다.
7. Compile이 활성 프로젝트를 빌드한다. 오류와 성공은 메시지 뷰에 올린다.
8. BPL을 다시 빌드한 경우에는 같은 비트의 IDE에 그 BPL만 다시 로드한다.

## 더티 버퍼

- 프롬프트를 보내기 직전에, 수정된 버퍼마다 텍스트와 파일 경로를 스냅샷한다.
- 자동 저장은 기본 꺼짐이다. 세션에서 사용자가 켜기 전에는 저장하지 않는다.
- omp의 디스크 패치는 승인 전이다. 승인 없이 IDE 버퍼를 덮어쓰지 않는다.
- 승인 후에는 IDE 에디터 API로 버퍼를 갱신한다. 열린 버퍼와 디스크가 어긋나게 두지 않는다.
- 스냅샷과 다른 사용자 편집이 있으면 덮어쓰지 않고 DockForm에 충돌을 보여 준다.

## 비범위

- Ghost Text
- `IOTAAIPlugin`
- 폼 디자이너 (1차)
- KAI MCP, KAI 패키지, KAI 상표
- DelphiLSP를 IDE 프로세스에 attach
- DelphiLSP.exe 또는 designide 재배포
- omp 에이전트 루프의 Delphi 재구현

## 진행 메모

채팅과 `omp --mode rpc`까지는 동작한다. 이후에도 터미널 임베드는 하지 않는다. IDE에만 있는 기능은 host-tool로 열고, omp에 이미 있는 명령은 채팅창이 기존 RPC로 보낸다. 디버거는 읽기 전용 host-tool만 있다. 폼 디자이너는 아직 없다. 이어서 볼 위치는 `docs/continue.md`다.
