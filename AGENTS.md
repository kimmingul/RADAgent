# DelphiAgent

RAD Studio 13.2 (BDS 37.0) design-time BPL. 에이전트 루프는 omp 18.2.11이다. Delphi로 다시 구현하지 않는다.

상세 절차는 스킬에 있다. 여기 규칙과 스킬이 충돌하면 여기 규칙을 따른다.

- ToolsAPI: `.agents/skills/delphi-toolsapi/SKILL.md`
- RPC: `.agents/skills/omp-rpc/SKILL.md`
- LSP: `.agents/skills/delphi-lsp/SKILL.md`
- 구조: `DESIGN.md`

## 언어

- Delphi 12/13 Object Pascal. 컴파일러는 BDS 37.0.
- 유닛 하나는 책임 하나. `DESIGN.md`의 모듈을 한 유닛에 합치지 않는다.
- 한 파일은 400줄을 넘기지 않는다. 넘기면 같은 책임 안에서 유닛을 나눈다.
- 식별자, 유닛 이름, 파일 이름은 ASCII Pascal.
- 사용자가 보는 문자열은 한글. 로그 접두사와 프로토콜 필드 이름은 영어.
- 문자열은 `UnicodeString`. IDE 버퍼를 `AnsiString`으로 왕복하지 않는다.
- 시크릿과 API 키를 소스, DFM, 프로젝트 설정, 커밋에 넣지 않는다.

## 패키지

- design-time BPL. `Requires`: `rtl`, `vcl`, `designide`.
- 다른 패키지를 Requires에 넣지 않는다. designide는 IDE에 있는 것을 참조만 한다. 재배포하지 않는다.
- Win32와 Win64를 각각 빌드한다. 출력 경로를 같이 쓰지 않는다.
  - Win32 → `$(BDSCOMMONDIR)\Bpl\DelphiAgent370.bpl`
  - Win64 → `$(BDSCOMMONDIR)\Bpl\Win64\DelphiAgent370.bpl`
- Win32 BPL은 `%BDS%\bin\bds.exe`에만 등록한다.
- Win64 BPL은 `%BDS%\bin64\bds.exe`에만 등록한다.
- 한 BPL을 양쪽 Known Packages에 넣지 않는다. 비트가 다른 BPL은 그 IDE가 로드하지 못한다.
- BPL은 패키지다. 일반 DLL로 바꿔 ToolsAPI를 노출하지 않는다.
- 공개 진입은 패키지 `Register` / `Finalization`뿐이다.

## ToolsAPI

- 공개 ToolsAPI만 호출한다. IDE 비공개 유닛을 uses에 넣지 않는다.
- KAI 패키지를 참조하거나 래핑하지 않는다.
- Wizard는 `IOTAWizard`이고 `RegisterPackageWizard`으로 등록한다.
- 도킹 Chat은 `INTACustomDockableForm`이다. `INTAServices270.RegisterDockableForm` 호출은 `Register` 안에서 한다.
- 에디터와 활성 프로젝트는 `IOTAEditorServices`와 `GetActiveProject`으로 읽는다.
- 컴파일은 활성 프로젝트의 `IOTAProjectBuilder.BuildProject(cmOTABuild, True)`이다. `Build`라는 메서드는 없다. `True`는 대기이다.
- 완료 통지는 `IOTACompileServices`에 등록한 `IOTACompileNotifier`로 받는다.
- 메시지 뷰는 `IOTAMessageServices`만 사용한다. 컴파일러 콘솔을 긁지 않는다.
- ToolsAPI 호출은 IDE 메인 스레드에서만 한다. RPC 수신 스레드에서 직접 호출하지 않는다.
- 패키지를 내릴 때 notifier, 도킹 폼, omp 자식을 해제한다.

## omp

- omp는 자식 프로세스다. 기본 명령은 `omp --mode rpc`이다.
- 전송은 stdin/stdout JSONL이다. 한 줄에 JSON 객체 하나.
- `ready` 프레임을 읽기 전에 `prompt`를 보내지 않는다.
- 자식의 cwd는 활성 `.dproj`가 있는 디렉터리다.
- 중단은 `abort` 프레임이다. 프로세스를 바로 죽이는 것이 중단의 기본 동작이 아니다.
- IDE 상태 변경은 host-tools 콜백으로만 한다. omp 도구가 IDE 메모리를 직접 쓰지 않는다.
- `/btw` 곁가지 질문은 도구 없는 별도 omp 자식(`--fork` 대화 또는 `--resume` 주제 세션)이 답한다. 본 대화에 넣지 않는다.
- 프레임 필드와 순서는 omp-rpc 스킬을 따른다. 여기에 프로토콜을 복붙하지 않는다.

## DelphiLSP

- DelphiLSP는 omp가 LSP 설정으로 띄우는 별도 프로세스다.
- IDE 프로세스 안의 DelphiLSP에 attach하지 않는다.
- `%BDS%\bin\DelphiLSP.exe`는 32-bit IDE용이다. omp에는 쓰지 않는다.
- omp에 연결하는 바이너리는 `%BDS%\bin64\DelphiLSP.exe`이다. 템플릿의 자리표시자를 그 경로로 바꾼다.
- 설치본을 사용한다. DelphiLSP.exe를 저장소에 넣거나 재배포하지 않는다.
- pasls, delphi-lookup, ACP Registry로 LSP를 대체하지 않는다.
- 설정 파일 생성과 `.omp/lsp.json` 필드는 delphi-lsp 스킬과 `templates/omp.lsp.json`이 기준이다.

## 더티 버퍼

- 프롬프트 직전에 수정된 IDE 버퍼를 스냅샷한다.
- 자동 저장 기본값은 꺼짐이다. 그 스냅샷 때문에 저장하지 않는다.
- IDE 버퍼·폼·디버거 변경의 승인은 입력 아래 줄의 승인 방식(omp `tools.approvalMode`)을 따른다: 항상 묻기 = 변경마다, 쓰기 허용 = 턴마다 한 번, 권한 무시 = 묻지 않음. 처음 값은 권한 무시다. 승인은 채팅 안 카드로 묻는다. `계획` 방식은 아무것도 바꾸지 않고 `docs\plans`에 계획서만 쓴다.
- 권한 무시여도 저장하지 않고, IDE에서 되돌릴 수 있게 버퍼 API로만 반영한다.
- `IOTAEditorServices` 버퍼 API로 IDE 버퍼를 갱신한다.
- 스냅샷 이후 사용자가 같은 버퍼를 고쳤으면 덮어쓰지 않고 충돌로 보여 준다.

## 범위

- 먼저 도킹 Chat, RPC, 스냅샷, 승인 후 버퍼 반영, 컴파일, 메시지 뷰가 한 바퀴 돌아야 한다.
- 그 전에 Ghost Text, `IOTAAIPlugin`, 폼 디자이너를 넣지 않는다.
- 동작하는 MVP 전에 큰 리팩터를 하지 않는다. 실패하는 테스트나 깨진 수동 확인이 있을 때만 구조를 바꾼다.
- `src/` 밖에 앱 코드를 두지 않는다. 하네스 문서와 템플릿은 루트, `.agents/`, `.grok/`에 둔다.

## 검증

- 패키지 변경 후 Win32와 Win64를 각각 빌드한다. 한 비트만 확인하고 끝내지 않는다.
- 디버그 호스트는 그 BPL과 같은 비트의 `bds.exe`이다. 파라미터는 `-pDelphi`이다.
- 컴파일 오류는 메시지 뷰에서 확인하고, 성공을 빌드 대화상자만으로 단정하지 않는다.
