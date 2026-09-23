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

stdin에는 JSONL만 쓴다. 일반 텍스트 한 줄이면 omp가 죽는다. `@file`은 RPC가 거절한다. 프레임 원문은 채팅에 찍지 않고 `%TEMP%\DelphiAgent\rpc.log`에만 남긴다.

## 지금 되는 것

- 64-bit IDE에서 Tools 또는 View의 DelphiAgent 도킹 창.
- `omp --mode rpc`. `ready` 뒤에만 명령. 모델 응답 스트림.
- 상태줄: `[연결됨|대기|오류]  pid=  프로젝트=  폴더=` 와 `get_state`의 모델명.
- 프로젝트 해석: 프로젝트 그룹, 열린 모듈, 에디터 옆 `.dproj`, 마지막 캐시. 없으면 `프로젝트=없음`.
- 슬래시 명령은 모달로 고른 뒤 기존 RPC만 전송.
- omp가 보내는 `extension_ui_request`의 select, confirm, input, editor는 모달. notify와 setStatus는 로그.
- host-tool: `rad.compile`, `rad.open_buffer`, `rad.insert_at_caret`, `rad.list_dirty`, `rad.read_buffer`, `rad.apply_edit`.
- 디버거 host-tool: `rad.debug_state`, `rad.debug_stack`(최대 64프레임), `rad.debug_evaluate`(부작용 없음), `rad.debug_breakpoints`. 실행 제어는 하지 않는다. 평가가 `erDeferred`로 오면 기다리지 않고 오류로 돌려준다.
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
| host-tool 이름과 스키마 | `DelphiAgent.HostToolDefs.BuildSetHostToolsFrame` |
| host-tool 실행 | `DelphiAgent.HostTools.ExecuteHostTool` |
| 디버거 host-tool | `DelphiAgent.DebugTools.ExecuteDebugTool` |
| 컴파일 | `DelphiAgent.Compile.BuildActiveProjectJson` |
| RPC 프로세스 | `DelphiAgent.RpcClient` |

## 아직 하지 않은 것

폼 디자이너 host-tool, 디버거 실행 제어(실행, 스텝, 중단점 추가), Ghost Text, `IOTAAIPlugin`, KAI, 터미널 임베드는 하지 않았다. 디자이너를 넣을 때도 omp가 ToolsAPI를 직접 부르게 하지 말고, 지금 host-tool과 같은 방식으로 BPL이 메인 스레드에서 호출하게 한다. host-tool을 추가하면 `HostToolDefs`에 이름과 스키마를 넣고, `tests/ProtocolTests.dpr`의 `all host tools declared` 목록도 고친다.

## 빌드

64-bit IDE가 BPL을 열고 있으면 덮어쓸 수 없다. IDE를 종료한 뒤 `scripts\build-win64.cmd`를 실행한다. 결과:

`C:\Users\Public\Documents\Embarcadero\Studio\37.0\Bpl\Win64\DelphiAgent370.bpl`

이미 설치되어 있으면 IDE를 다시 연다. 32-bit는 `scripts\build-win32.cmd`와 `Bpl\DelphiAgent370.bpl`이다. 한 BPL을 양쪽 Known Packages에 넣지 않는다.

## 테스트

`scripts\build-tests.cmd`를 실행한다. `tests\ProtocolTests.dpr`을 Win64로 빌드하고 실행하며, 실패 개수를 종료 코드로 돌려준다. `TestLiveReady`는 실제 `omp`를 띄워 `ping` 프롬프트를 보낸다.

## 검증 기록

2026-09-23 19시 기준.

| 항목 | 결과 |
| --- | --- |
| `scripts\build-win32.cmd` | 성공. 경고 없음 |
| `scripts\build-win64.cmd` | 성공. 경고 없음 |
| `scripts\build-tests.cmd` (omp 18.2.11) | 59개 전부 통과 |
| 프로젝트 스킬 | `.agents/skills`로 옮김. omp `get_available_commands`에 `skill:delphi-lsp`, `skill:delphi-toolsapi`, `skill:omp-rpc`가 나온다 |
| 사용자 RAD 스킬 | `~/.omp/agent/config.yml`의 `skills.ignoredSkills`에 `debugging`, `ide-file-operations`, `project-management`를 넣었다. omp에서만 빠지고 다른 에이전트에는 영향이 없다 |
| 개발용 DelphiLSP | `.omp/lsp.json`과 손으로 만든 `src/DelphiAgent.delphilsp.json`으로 definition과 diagnostics를 확인했다 |
| Win32 IDE 등록 | 안 됨. `Known Packages`에 항목이 없다 |
| Win64 IDE 등록 | `Known Packages x64`에 `DelphiAgent370.bpl`만 있다. 없는 파일을 가리키던 `DelphiAgent.bpl` 항목은 지웠다 |
| 디버거 host-tool | 빌드만 확인했다. IDE 디버그 세션에서는 아직 확인하지 않았다 |

## MVP 한 바퀴 확인 절차 (미확인)

AGENTS.md 범위 조건이다. 폼 디자이너는 이것이 통과한 뒤에 시작한다. 64-bit IDE에서 한 번, 32-bit IDE에서 한 번 한다. 한 번에 30분쯤 걸린다.

각 단계는 **할 일**, **입력할 문장**, **통과 조건**으로 되어 있다. 통과 조건과 다르면 거기서 멈추고, 단계 번호와 화면에 보인 내용을 알려 준다. 원인은 `%TEMP%\DelphiAgent\rpc.log`에서 찾는다.

입력할 문장은 DelphiAgent 창 아래 입력칸에 그대로 붙여 넣고 **보내기**를 누른다. 경로 `C:\Users\kimmi\AppData\Local\Temp\DelphiAgentSmoke`는 이 PC의 `%TEMP%\DelphiAgentSmoke`다. 다른 PC에서는 그 PC의 경로로 바꾼다.

### 화면 설명

DelphiAgent 창의 구성은 다음과 같다.

- 위: 채팅 기록. 보낸 문장은 `> `로 시작한다.
- 아래: 입력칸, 그리고 **보내기**, **중지**, **컴파일**, **파일** 버튼.
- 맨 아래: 상태줄.

omp가 IDE 도구(`rad.*`)를 부른 사실은 채팅에 보이지 않는다. 확인하려면 PowerShell에서 다음을 실행한다.

```powershell
Select-String -Path "$env:TEMP\DelphiAgent\rpc.log" -Pattern '"toolName":"rad\.[a-z_]+"' | Select-Object -Last 3
```

### 알려진 문제 (이 절차는 이것들을 피하도록 짜여 있다)

- `rad.apply_edit`는 스냅샷 충돌을 검사하지 않는다. 충돌 검사는 `rad.insert_at_caret`에만 있다. 그래서 충돌 확인(6단계)은 `rad.insert_at_caret`로 한다.
- `rad.apply_edit`에 `content`(파일 전체 교체)를 주면 기존 텍스트를 지우지 않고 맨 앞에 끼워 넣는다. 그래서 4~5단계는 줄 범위(`startLine`, `endLine`, `newText`)로만 요청한다.
- 프로젝트를 열기 전에 DelphiAgent 창을 열면 omp가 엉뚱한 폴더에서 뜬다. 처음 **보내기**를 누를 때 다시 뜨면서 그 문장은 버려진다. 그래서 준비 단계에서 프로젝트를 먼저 연다.

### 준비 (IDE마다 한 번)

1. 열려 있는 RAD Studio를 모두 닫는다.
2. 저장소에서 `scripts\build-win64.cmd`를 실행한다. 32-bit 차례에는 `scripts\build-win32.cmd`를 실행한다.
3. `scripts\prepare-smoke.cmd`를 실행한다. `%TEMP%\DelphiAgentSmoke`에 확인용 VCL 앱 `Smoke.dpr`, `MainForm.pas`, `MainForm.dfm`이 새로 복사된다. 원본은 `tests\smoke`다.
4. PowerShell에서 이전 로그를 지운다.

   ```powershell
   Remove-Item "$env:TEMP\DelphiAgent\rpc.log" -ErrorAction SilentlyContinue
   ```

5. IDE를 실행한다. 64-bit는 `%BDS%\bin64\bds.exe`, 32-bit는 `%BDS%\bin\bds.exe`다.
   - 32-bit에서는 먼저 Component → Install Packages → Add로 `C:\Users\Public\Documents\Embarcadero\Studio\37.0\Bpl\DelphiAgent370.bpl`을 등록한다.
6. Tools → Options를 연다. 왼쪽 위 검색칸에 `Autosave`를 입력하고 **Editor files**의 체크를 끈다. 켜져 있으면 빌드할 때 파일이 저장되어 "저장하지 않는다" 확인이 무의미해진다.
7. File → Open Project로 `%TEMP%\DelphiAgentSmoke\Smoke.dpr`을 연다. Project Manager에서 `MainForm.pas`를 더블클릭하고, F12로 코드 탭을 연다.
8. 확인에 쓰는 줄 번호는 다음과 같다.

   | 줄 | 내용 |
   | --- | --- |
   | 30 | `Result := Result + Index;` |
   | 37 | `Answer := Total(10);` |
   | 38 | `Label1.Caption := 'Total=' + IntToStr(Answer);` |

9. View(또는 Tools) → **DelphiAgent**로 창을 연다.

확인 중에 IDE가 "파일이 디스크에서 바뀌었다"고 물으면, omp가 디스크 파일을 직접 고친 것이다. **아니오**를 누르고 그 단계를 실패로 알려 준다.

### 1. 연결

- **할 일:** 창을 연 뒤 5~20초 기다린다.
- **통과 조건:**
  - 상태줄이 `[연결됨]  pid=<0이 아닌 숫자>  프로젝트=Smoke  폴더=...\DelphiAgentSmoke  모델=<모델명>`이다.
  - **보내기** 버튼이 눌린다.
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
  - `%TEMP%\DelphiAgent\`에 `snap-<숫자>-MainForm.pas` 파일이 있고, 그 안에 `Sum=`이 있다. 숫자는 수정된 파일 순서라 0이 아닐 수 있다.
  - 메모장으로 연 `%TEMP%\DelphiAgentSmoke\MainForm.pas`(디스크 원본)는 여전히 `Total=`이다.

### 4. 승인 전에는 버퍼가 바뀌지 않는다 (취소)

- **입력할 문장:**

  ```text
  디스크 파일은 절대 수정하지 마. rad.apply_edit 도구만 써서 버퍼를 고쳐줘. path는 C:\Users\kimmi\AppData\Local\Temp\DelphiAgentSmoke\MainForm.pas, startLine과 endLine은 모두 "38", newText는 "  Label1.Caption := 'Answer=' + IntToStr(Answer);" 뒤에 줄바꿈 \r\n을 붙인 문자열이야.
  ```

- **할 일:** 제목이 `DelphiAgent`인 승인 창이 뜬다. 창 안에는 파일 경로와 새 줄이 보인다. 창이 떠 있는 동안 뒤의 에디터 38줄이 아직 `Sum=`인지 본다. 그다음 **취소**를 누른다.
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

- **할 일:** 에디터에서 38줄 끝에 캐럿을 둔다.
- **입력할 문장:**

  ```text
  먼저 bash로 sleep 20을 실행하고, 끝나면 rad.insert_at_caret 도구로 text "  // agent" 를 삽입해줘. 디스크 파일은 수정하지 마.
  ```

- **할 일:** 보낸 직후 20초 안에 에디터를 클릭하고, 30줄 끝에 스페이스를 하나 친다. omp가 bash 실행 확인을 물으면 승인한다.
- **통과 조건:**
  - 승인 창이 뜨지 않는다.
  - 채팅에 `충돌: 스냅샷 이후 버퍼가 바뀌어 반영하지 않았습니다. ...MainForm.pas`가 찍힌다.
  - 버퍼 어디에도 `// agent`가 없다.
- **대조 확인:** 같은 문장을 다시 보내되 이번에는 에디터를 건드리지 않는다. 승인 창이 뜨고, **승인**하면 캐럿 위치(38줄 끝)에 `  // agent`가 들어간다.

### 7. 컴파일 성공이 메시지 뷰에 보인다

- **할 일:** DelphiAgent 창의 **컴파일** 버튼을 누른다. 컴파일 진행 창은 뜨지 않을 수 있다.
- **통과 조건:**
  - 채팅에 `컴파일 ok`가 찍힌다.
  - Messages 창(View → Messages)에 `DelphiAgent` 도구 이름으로 `빌드 성공` 줄이 있다.
  - 탭의 수정 표시가 그대로 남아 있다. 저장되지 않았다.
- **입력할 문장:**

  ```text
  rad.compile 도구로 빌드하고 결과 JSON의 ok, config, platform 값만 알려줘.
  ```

- **통과 조건:** `ok`가 `true`이고, `config`와 `platform`이 IDE Project Manager에 보이는 활성 구성과 같다.

### 8. 컴파일 오류 위치가 메시지 뷰와 같다

- **할 일:** 37줄의 `Total(10)`을 `Totl(10)`로 고치고 **컴파일** 버튼을 누른다.
- **통과 조건:**
  - 채팅에 `컴파일 실패`가 찍힌다.
  - Messages 창에 `[dcc64 Error]`(32-bit 프로젝트면 `[dcc32 Error]`) `MainForm.pas(37): E2003 Undeclared identifier: 'Totl'` 같은 줄과 DelphiAgent의 `빌드 실패` 줄이 있다.
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

- **할 일:** 답이 흘러나오기 시작하면 **중지**를 누른다.
- **통과 조건:**
  - 몇 초 안에 출력이 멈춘다.
  - 상태줄의 pid가 1단계에서 적어 둔 값과 같다.
  - 이어서 `안녕`을 보내면 답이 온다.

### 10. 디버거 도구는 읽기만 한다

- **할 일:**
  1. 30줄 왼쪽 여백을 클릭해 중단점을 건다(F5).
  2. Run → Run(F9)으로 실행한다.
  3. `DelphiAgent Smoke` 창의 **Run** 버튼을 누른다. IDE가 30줄에서 멈춘다.
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
