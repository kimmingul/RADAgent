# DelphiAgent

RAD Studio 13.2 IDE 안의 design-time BPL이다. 에이전트 루프는 설치된 omp 18.2.11이고, Delphi로 다시 만들지 않는다. 도킹 창은 Tools 또는 View 메뉴의 DelphiAgent다. 이어서 할 일은 [docs/continue.md](docs/continue.md)에 적어 두었다.

## 요구사항

- Windows. RAD Studio 13.2 (BDS 37.0) 32-bit IDE와 64-bit IDE.
- `%BDS%` 기본값: `C:\Program Files (x86)\Embarcadero\Studio\37.0`
- 32-bit IDE: `%BDS%\bin\bds.exe`. 그 IDE 안의 DelphiLSP는 `%BDS%\bin\DelphiLSP.exe`이며, omp는 이 파일을 쓰지 않는다.
- 64-bit IDE: `%BDS%\bin64\bds.exe`. omp가 쓸 DelphiLSP는 항상 `%BDS%\bin64\DelphiLSP.exe`다.
- `omp` 18.2.11. PATH에 없으면 `%LOCALAPPDATA%\omp\omp.exe`. 진입점: `omp --mode rpc`

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

- 빈 IDE에서 DelphiAgent를 열면 상태줄 둘째 줄이 `프로젝트 없음`이다.
- VCL 앱을 연 뒤 DelphiAgent를 열면 둘째 줄에 `프로젝트 <이름> · pid <번호> · <폴더>`가 보인다.
- 채팅 창이 포커스여도 그 프로젝트 이름은 유지된다.
- `/clear` 뒤에 일반 질문을 보내고, 컴파일 버튼을 누르면 채팅에 `컴파일 성공`이 찍힌다.

컴파일 오류는 메시지 뷰에서 확인한다. 빌드 대화상자만으로 성공을 단정하지 않는다.

## 채팅에서 쓸 수 있는 것

채팅 기록은 WebView2 화면이다. 모델 답은 마크다운(표, 코드 블록과 Pascal 강조, 목록, 링크)으로 보이고, 코드 블록에는 복사 버튼이 있다. `MainForm.pas(37)` 같은 파일 위치를 누르면 에디터가 그 줄을 연다. omp가 부르는 도구는 접힌 줄로 보이고, 끝나면 ✓/✗와 걸린 시간이 붙는다. 펼치면 결과가 보인다.

상태줄 첫째 줄은 `● 연결됨 · 모델 · 컨텍스트 % · 지금 하는 일 · 경과 초`, 둘째 줄은 프로젝트, omp pid, 폴더다. 중지 버튼은 omp가 일할 때만 켜진다.

입력칸은 여러 줄이다. Enter는 보내기, Shift+Enter는 줄바꿈, 첫 줄에서 ↑는 이전에 보낸 문장이다. `/`를 치면 omp 명령 목록이 뜨고 Tab/Enter로 고른다. 입력칸 위 줄은 활성 파일, 선택한 줄, 저장 안 한 파일 수다. `선택 영역 포함`을 켜면 선택한 코드가 프롬프트에 붙는다.

위 도구 막대: `새 세션`, `세션 목록`(같은 프로젝트의 이전 세션으로 전환하고 기록을 다시 보여 줌), `내보내기`(대화를 HTML로 저장), `설정`. 색은 IDE 테마를 따르고, 테마를 바꾸면 채팅도 바뀐다.

채팅에는 답 말고도 omp 진행 내용이 보인다: 생각(접힘), 모델이 쓰는 도구 입력, 도구 실행 중 출력, 하위 에이전트, 위쪽 작업 목록, 재시도·모델 대체. `설정` 창에서 항목마다 켜고 끈다.

`설정` 창:

- 채팅 표시: 위 항목, 글자 크기, 고대비. 바로 적용.
- 계정·모델: 지금 대화의 모델과 생각 수준, OAuth 로그인. RPC로 바로 적용. API 키가 필요한 공급자는 터미널 omp의 `/login`을 쓴다.
- 역할별 모델, 확장(스킬·확장·하위 에이전트 켜고 끄기, MCP 목록), 고급(omp 도구 승인, 기본 생각 수준): 이 프로젝트에만 적용된다. `<프로젝트>\.omp\delphiagent.yml`에 저장하고 `--config`로 omp에 넘긴다. 전역 `~/.omp/agent/config.yml`은 바꾸지 않는다. 확인을 누르면 omp를 같은 세션으로 다시 시작할지 묻는다.
- 고급(이 PC): omp 실행 파일, 추가 인자, 저장 안 한 버퍼 스냅샷 여부.

에디터 오른쪽 클릭 메뉴에 `DelphiAgent: 선택 영역 설명/고치기`, 메시지 창 오른쪽 클릭 메뉴에 `DelphiAgent: 빌드 오류 고치기`가 있다. 승인이 필요하거나 답이 끝났을 때 IDE가 뒤에 있으면 작업 표시줄 단추가 깜빡인다. 채팅 창을 닫거나 디버그 레이아웃으로 바뀌어도 대화와 omp는 그대로다.

버퍼 편집 승인 창은 바뀌는 줄을 diff(빨강 삭제, 초록 추가, 앞뒤 3줄)로 보여 준다.

`/model`은 omp가 준 목록으로 모델을 고른다. `/fast`, `/thinking`, `/effort`는 모달에서 고른 뒤 기존 RPC만 보낸다. `/clear`는 확인 후 새 세션이다. 그 외 `/`로 시작하는 문장은 omp에 원문 그대로 넘긴다. `파일` 버튼은 고른 경로를 입력칸에 붙인다. `@file`은 쓰지 않는다.

IDE 도구는 `rad.compile`, `rad.open_buffer`, `rad.insert_at_caret`, `rad.list_dirty`, `rad.read_buffer`, `rad.apply_edit`이다. 버퍼를 고치는 도구는 적용을 누르기 전에는 쓰지 않고, 디스크에 자동 저장하지 않는다.

디버거 읽기 도구는 `rad.debug_state`, `rad.debug_stack`, `rad.debug_evaluate`, `rad.debug_breakpoints`이다. 식 평가는 부작용 없이 한다. 실행 제어 도구는 `rad.debug_run`(실행 또는 계속), `rad.debug_step`(over, into, return), `rad.debug_pause`, `rad.debug_reset`, `rad.debug_add_breakpoint`이다. 모두 승인 창에서 승인해야 동작하고, 끝나면 디버거 상태를 돌려준다. 디버기 메모리는 쓰지 않는다.

폼 디자이너 도구는 `rad.form_components`, `rad.form_properties`(읽기), `rad.form_set_property`, `rad.form_add_component`, `rad.form_delete_component`, `rad.form_rename_component`, `rad.form_set_event`이다. 바꾸는 도구는 승인한 뒤에 디자이너에만 반영하고 저장하지 않는다. 필드 선언과 이벤트 메서드는 디자이너가 유닛 버퍼에 고친다.

RPC 원문은 `%TEMP%\DelphiAgent\rpc.log`에만 남긴다. 채팅 로그에는 사용자 문장과 모델 응답만 보인다.
