# 하위 에이전트 여러 개로 동시에 코딩하기

- 작성: 2026-09-24
- 대상: RAD Agent (omp 18.2.11, RAD Studio 13.2)
- 상태: 조사 끝, 구현 전
- 갱신(2026-09-24): RAD Agent가 디스크 기준(저장 후 omp가 디스크 편집, IDE가 다시 읽기)과 메시지별 git 체크포인트로 바뀌었다. 그래서 아래 "IDE 버퍼가 기준" 조건은 더 이상 없다. 지금은 서로 다른 `.pas` 파일을 맡은 하위 에이전트의 디스크 편집을 안내문으로 허용한다. 같은 파일 충돌을 막는 B의 버전 토큰과 소유권, C의 격리는 여전히 다음 단계 후보다.

## 목표

omp 메인 세션이 일을 나눠 하위 에이전트 여러 개에 맡기고, 하위 에이전트들이 동시에 코드를 고치게 한다. 지켜야 할 조건은 지금과 같다.

- IDE 버퍼가 기준이다. 디스크 파일만 바꾸고 열린 버퍼를 그대로 두지 않는다. 저장하지 않는다.
- IDE 변경은 입력 아래 승인 방식(항상 묻기, 쓰기 허용, 권한 무시)을 따른다.
- 사용자가 스냅샷 뒤에 고친 버퍼는 덮어쓰지 않고 충돌로 보여 준다.
- ToolsAPI는 메인 스레드에서만 부른다.

## 현재 상태

### RAD Agent

- 하위 에이전트는 읽기 전용 조사에만 쓴다. 프로젝트 안내문(`OmpLaunch.WriteProjectGuide`)이 그렇게 지시한다.
- IDE 도구 `rad.*`는 RPC `set_host_tools`로 메인 세션에만 등록된다.
- 채팅은 `set_subagent_subscription progress`로 하위 에이전트 진행 줄을 보여 준다.

### omp가 제공하는 것 (문서)

- `task` 도구는 같은 omp 프로세스 안에 자식 세션을 만든다. 동시 실행 수는 `task.maxConcurrency`(기본 32)로 제한한다 (omp://tools/task.md, omp://tools/eval.md).
- 하위 에이전트는 헤드리스라 `tools.approvalMode: yolo`로 돈다. 사용자 `tools.approval.<tool>` 설정만 적용된다 (omp://approval-mode.md "Subagents"). 그래서 하위 에이전트가 디스크에 쓰는 것은 RAD Agent 승인을 거치지 않는다.
- 격리: `task.isolation.enabled`를 켜면 하위 에이전트가 저장소 복사본에서 일한다.
  - 결과는 패치로 적용되거나, `omp/task/<id>` 브랜치로 커밋된 뒤 cherry-pick된다.
  - git 저장소가 필요하다.
  - Windows 백엔드는 ProjFS이고, 안 되면 재귀 복사를 쓴다 (omp://tools/task.md "Modes / Variants", "Errors").
- MCP 연결은 부모의 것을 프록시로 하위 에이전트와 공유한다 (omp://tools/task.md "Notes", omp://mcp-runtime-lifecycle.md).
- RPC 호스트는 하위 에이전트를 관찰만 한다: `subagent_*` 프레임, `get_subagents`, `get_subagent_messages`. 만들기, 조종, 중지 명령은 문서에 없다 (omp://rpc.md "Subagent subscriptions").
- 호스트 URI 스킴(`set_host_uri_schemes`)은 "프로세스 전역"이다. 하위 에이전트가 `<scheme>://…`을 읽고 쓰면 요청이 호스트로 돌아온다. 다만 `edit` 도구는 호스트 URI를 대상으로 하지 않고 `read`와 `write`만 된다 (omp://rpc.md "Host URI Sub-Protocol").

### 직접 확인한 것 (2026-09-24, omp 18.2.11, `omp --mode rpc --no-session`)

| 실험 | 결과 |
| --- | --- |
| `set_host_tools`로 `probe_tool`을 등록하고 `task` 하위 에이전트가 호출 | 실패. `No such tool: xd://probe_tool. Mounted devices: ast_edit, debug`. 호스트 도구는 하위 에이전트에게 보이지 않는다. |
| `set_host_uri_schemes`로 `ide`(writable)를 등록하고, 하위 에이전트가 `ide://probe/hello.txt`를 읽고 `ide://probe/out.txt`에 쓰기 | 성공. 호스트에 `host_uri_request`가 `read` 한 번, `write` 한 번(`content: "from-sub"`) 도착했고, 호스트 답이 하위 에이전트에게 전달됐다. |

### 다른 도구의 경험 (참고)

- 병렬 코딩 에이전트는 git worktree로 파일을 격리하고, 한 곳에서 통합(integrator)한다. 작업은 겹치지 않는 영역으로 나눈다 ([Claude Code worktree 가이드](https://claudedirectory.org/blog/claude-code-worktrees-guide), [worktree 격리와 소유권](https://codeongrass.com/blog/parallel-coding-agents-worktree-isolation-ownership/)).
- Anthropic의 연구용 다중 에이전트 경험 ([How we built our multi-agent research system](https://www.anthropic.com/engineering/multi-agent-research-system)):
  - 다중 에이전트는 채팅보다 토큰을 약 15배 쓴다.
  - "대부분의 코딩 작업은 연구보다 진짜로 병렬화할 수 있는 부분이 적다."
  - 각 하위 에이전트에게 목표, 출력 형식, 도구, 경계를 분명히 줘야 한다.

## 방안 비교

| 방안 | 동시 편집 | IDE 버퍼 기준 | 승인 | 컴파일 확인 | 조건 | 판단 |
| --- | --- | --- | --- | --- | --- | --- |
| A. 지금처럼 조사만 병렬 | 없음 | 지킴 | 지킴 | 메인 `rad.compile` | 없음 | 기준선 |
| B. `ide://` 호스트 URI 다리 | 파일 단위 | 지킴 | RAD Agent가 처리 | IDE 컴파일(직렬) | 없음 | **1단계 추천** |
| C. omp 격리(`task.isolation`) + 디스크→버퍼 동기화 | 복사본 단위 | 병합 뒤 동기화 | 병합 시점에 한 번 | 복사본마다 msbuild | git 필요, ProjFS 또는 복사 | 2단계, 큰 독립 작업용 |
| D. 최상위 세션 여러 개(탭) + worktree | 세션 단위 | 활성 세션만 | 세션마다 | 세션마다 msbuild | git 필요, UI 큼 | 보류 |
| E. MCP 서버로 `rad.*`를 하위 에이전트에 공개 | 도구 단위 | 지킴 | 지킴 | 가능 | 별도 프로세스와 IPC | 파일 밖 도구가 필요할 때만 |

### B를 1단계로 고르는 이유

- 하위 에이전트가 IDE와 통하는 길 중에 실험으로 확인한 것이 호스트 URI뿐이다. 이미 쓰는 RPC 연결 하나로 되고, 새 프로세스가 필요 없다.
- 쓰기가 RAD Agent로 돌아오므로 지금의 승인, 충돌 검사, 버퍼 반영(`BufferEdits`), 파일 카드를 그대로 쓴다. 하위 에이전트가 yolo로 돌아도 IDE 변경은 사용자의 승인 방식을 따른다.
- git이 없는 Delphi 프로젝트에서도 된다.

### B의 동작

- **읽기** `ide://<프로젝트 상대 경로>`:
  - 열린 버퍼면 저장 안 한 내용까지 돌려주고, 아니면 디스크 내용을 돌려준다.
  - `notes`에 `version: N`을 넣는다. N은 파일별로 버퍼가 바뀔 때마다 오른다.
- **쓰기**:
  - 전체 교체는 `ide://<경로>?v=N`에 쓴다.
  - 부분 편집은 `ide://edits/<경로>?v=N`에 `rad.apply_edits`와 같은 JSON 줄 편집을 쓴다. `edit` 도구가 호스트 URI를 못 쓰므로 큰 유닛을 통째로 다시 쓰지 않게 하려는 것이다.
  - N이 지금 버전과 다르면 거절하고 다시 읽으라고 답한다. 이것은 낙관적 동시성이다: 요청에 에이전트 식별자가 없어도, 같은 파일을 여러 에이전트가 고칠 때 덮어쓰기를 막는다.
- **쓰기 반영**: `ReplaceChanged` 또는 `ApplyEdits`로 버퍼에 반영하고 저장하지 않는다. 사용자가 고친 버퍼는 충돌로 거절한다.
- **컴파일** `ide://build` 읽기: IDE 컴파일을 메인 스레드에서 직렬로 돌리고 오류 JSON을 돌려준다. 다른 에이전트가 고치는 중인 파일의 오류도 섞이므로, 오류마다 파일 경로를 붙인다.
- **소유권**: 메인 세션이 작업을 나눌 때 각 하위 에이전트의 파일 목록을 `task` context에 적는다. 하위 에이전트는 `ide://w/<이름>/<경로>` 형식으로 써서 자기 이름을 밝힌다. RAD Agent는 파일마다 처음 쓴 이름을 기억하고, 다른 이름의 쓰기는 거절한다. 파일 카드에 에이전트 이름을 붙인다.
- **승인**:
  - 권한 무시: 바로 반영한다.
  - 쓰기 허용: 턴마다 한 번 묻는다. 하위 에이전트의 쓰기도 메인 턴 안이다.
  - 항상 묻기: 승인 카드를 큐로 쌓는다. 지금 `AskInChat`은 한 번에 하나만 기다리므로 여러 카드를 동시에 띄우고 각자 답하게 바꾼다.
- **통합**: 하위 에이전트가 모두 끝나면 메인 세션이 `rad.compile`로 확인하고 고친다. 컴파일 게이트는 메인 세션 하나다.

### 언제 나누나 (안내문 규칙)

- 서로 다른 유닛이나 파일에 닿는 독립 작업이 2개 이상일 때만 나눈다. 예: 폼 두 개, 유닛과 그 테스트, 여러 유닛의 같은 종류 수정.
- 동시에 도는 에이전트는 기본 3개까지로 둔다. 토큰 비용 때문이다.
- 폼 디자이너 변경(`rad.form_*`)과 디버거는 메인 세션에만 남긴다. 둘 다 IDE에 하나뿐인 상태다.

## 단계

1. **호스트 URI 배관**
   - 시작 때 `set_host_uri_schemes`로 `ide`를 등록한다.
   - `host_uri_request`와 `host_uri_cancel`을 받아 메인 스레드로 넘기고, `host_uri_result`로 답한다.
   - `RpcClient`는 400줄이라 먼저 나눈다. 수신 큐 처리(`Queue*`)를 별도 유닛으로 옮긴다.
2. **`IdeUri` 유닛**:
   - 경로 해석. 프로젝트 폴더와 열린 모듈 밖은 거절한다.
   - 읽기, 버전 표, 전체 쓰기, `edits` 쓰기, `build` 읽기, 열린 버퍼·저장 안 한 목록 읽기.
3. **승인 큐**: 여러 쓰기의 승인 카드를 동시에 띄우고 각자 답하게 한다. 중지하면 모두 거부한다.
4. **안내문**: 나누는 규칙, `ide://` 사용법, 소유권, 통합 순서를 적는다. 하위 에이전트용 문장은 `task` context에 들어가게 한다.
5. **화면**: 하위 에이전트 줄에 그 에이전트가 바꾼 파일을 붙이고, 파일 카드에 에이전트 이름을 붙인다.
6. **2단계(선택)**: 설정의 격리 모드 켜기.
   - git 저장소일 때만 `task.isolation.enabled`를 overlay로 켠다.
   - 병합 뒤 바뀐 파일을 버퍼에 맞춘다. 수정 안 된 버퍼는 `ReplaceChanged`로 반영하고, 수정된 버퍼는 충돌 카드로 보여 준다.
   - 복사본 컴파일은 msbuild 명령줄로 한다.

## 바뀔 파일

- 새 파일: `src/RADAgent.IdeUri.pas`, `src/RADAgent.HostUriQueue.pas`(가칭)
- `src/RADAgent.RpcClient.pas`, `src/RADAgent.RpcDispatch.pas`: 호스트 URI 프레임
- `src/RADAgent.ChatApprovalCard.pas`, `src/RADAgent.ChatApproval.pas`: 승인 큐
- `src/RADAgent.BufferEdits.pas`: 버전 표
- `src/RADAgent.OmpLaunch.pas`: 안내문
- `src/chat/activity.js`, `src/chat/tools.js`: 에이전트별 파일 표시
- `tests/`: 버전 충돌, 경로 탈출, 소유권 거절 단위 시험, 하위 에이전트 `ide://` 실시험
- `README.md`, `DESIGN.md`

## 위험

- **omp 동작 의존**: 하위 에이전트의 호스트 URI 접근은 문서가 "프로세스 전역"이라고만 말하고, 확인은 실험으로 했다. omp 업데이트 때 바뀔 수 있으므로 `ProtocolTests`에 실시험을 추가한다. 모델을 부르는 시험이라 비용이 들어서, 이 시험만 선택 실행으로 둔다.
- **모델 준수**: 버전 토큰과 소유권 규칙을 모델이 빠뜨릴 수 있다. 호스트가 거절하고 이유를 돌려주는 방식이므로, 틀려도 버퍼가 망가지지는 않는다.
- **전체 쓰기 비용**: 큰 유닛을 통째로 쓰면 토큰이 많이 든다. `edits` 끝점을 기본으로 안내한다.
- **컴파일 간섭**: 한 IDE에서 컴파일은 하나뿐이다. 하위 에이전트끼리 서로의 미완성 코드 때문에 실패할 수 있다. 하위 에이전트의 컴파일은 참고용으로 두고, 최종 게이트는 메인 세션이 맡는다.
- **승인 폭주**: 항상 묻기에서 에이전트 3개가 동시에 쓰면 카드가 많아진다. 쓰기 허용(턴마다 한 번)을 권하는 안내를 띄운다.
- **토큰 비용**: 병렬화는 토큰을 여러 배 쓴다. 나누는 기준(독립 작업 2개 이상)을 안내문에 넣는다.
- **2단계 격리**: git이 없거나 ProjFS를 쓸 수 없으면 재귀 복사가 되어 큰 프로젝트에서 느리다. 병합 뒤 버퍼 동기화가 사용자의 저장 안 한 변경과 충돌할 수 있다.

## 확인 방법

- 단위 시험:
  - 버전이 다른 쓰기는 거절된다.
  - `ide://../x`처럼 프로젝트 밖을 가리키면 거절된다.
  - 다른 에이전트가 소유한 파일에 쓰면 거절된다.
  - `edits` JSON이 `ApplyEdits`와 같은 결과를 낸다.
- 실시험 (`omp --mode rpc`, 모델 호출): 하위 에이전트 두 개가 서로 다른 파일을 `ide://`로 읽고 쓰고, 두 쓰기가 모두 호스트에 도착한다.
- IDE (64-bit와 32-bit, Smoke 프로젝트):
  - "MainForm과 새 유닛 Calc를 동시에 고쳐줘"를 보낸다.
  - 하위 에이전트 2개가 동시에 돌고, 각 파일 카드에 에이전트 이름이 붙는다.
  - 저장되지 않은 버퍼에 반영되고, 메인 세션의 `rad.compile`이 통과한다.
  - 항상 묻기에서는 카드가 여러 개 떠도 각각 답할 수 있다.
  - 사용자가 같은 버퍼를 고치고 있으면 충돌로 거절된다.
