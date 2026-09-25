---
name: delphi-toolsapi
description: RAD Studio 13.2 ToolsAPI로 RAD Agent design-time BPL을 만들 때 따른다. IOTAWizard, 도킹 Chat, IOTAEditorServices, IOTAProjectBuilder, IOTACompileNotifier, IOTAMessageServices, 32/64 BPL 등록. Use when editing the BPL, ToolsAPI, dock form, compile, or message view.
---

# RAD Agent ToolsAPI

대상은 BDS 37.0 design-time 패키지이고, 10.4(21.0)·11(22.0)·12(23.0)에서도 컴파일되게 유지한다(AGENTS.md "구버전"). 공개 ToolsAPI만 사용한다. 비공개 IDE 유닛, KAI 패키지, designide 재배포는 하지 않는다.

## 패키지

1. design-time 패키지. `Requires`: `rtl`, `vcl`, `designide`.
2. 플랫폼은 Win32와 Win64. 다른 플랫폼은 추가하지 않는다.
3. 출력:
   - Win32 → `$(BDSCOMMONDIR)\Bpl\RADAgent370.bpl` (`{$LIBSUFFIX AUTO}`: 10.4 `270`, 11 `280`, 12 `290`)
   - Win64 → `$(BDSCOMMONDIR)\Bpl\Win64\RADAgent370.bpl` (64-bit IDE가 있는 13만)
   - 숫자 접미사 280 이상 ToolsAPI 인터페이스는 `{$IF CompilerVersion >= 35}`처럼 감싼다.
4. BPL은 패키지다. IDE가 `Register`를 호출한다. 같은 코드를 일반 DLL로 빼지 않는다.
5. 32-bit IDE는 `Known Packages`에 Win32 BPL만 둔다. 64-bit IDE는 `Known Packages x64`에 Win64 BPL만 둔다. 한 파일을 양쪽에 등록하지 않는다.
   - `HKCU\Software\Embarcadero\BDS\37.0\Known Packages`
   - `HKCU\Software\Embarcadero\BDS\37.0\Known Packages x64`

## 등록 순서

`Register` 안에서, IDE 시작 중 데스크톱 로드보다 늦지 않게:

1. `RegisterPackageWizard`에 `IOTAWizard`를 넘긴다.
2. `INTAServices270.RegisterDockableForm`에 `INTACustomDockableForm`을 넘긴다.
3. `IOTACompileServices.AddNotifier`에 `IOTACompileNotifier`를 넘긴다.

`Finalization`에서 역순으로 해제하고 omp 자식을 끝낸다.

`IOTAWizard`가 구현할 것: `GetIDString`, `GetName`, `GetState`, `Execute`. ID 문자열은 ASCII이고 바꾸지 않는다.

`INTACustomDockableForm`이 구현할 것: `GetCaption`(한글), `GetIdentifier`(ASCII, 번역하지 않음), `GetFrameClass`, `FrameCreated`. 프레임이 Chat UI다. `GetIdentifier`는 데스크톱 저장 키다.

## 에디터와 프로젝트

- 활성 프로젝트: `GetActiveProject`. nil이면 프롬프트를 보내지 않고 메시지 뷰에 이유를 쓴다.
- 열린 편집기: `IOTAEditorServices.TopView`와 `TopBuffer`. 모듈 목록이 필요하면 `IOTAModuleServices`를 순회한다.
- 더티 여부는 모듈 편집기의 `Modified`로 판단한다. 프롬프트 전에 `IOTAModule.Save(False, True)`로 저장한다.
- omp가 디스크에서 바꾼 파일은 `IOTAModule.Refresh(True)`로 다시 읽힌다. 사용자가 고치던 모듈은 다시 읽지 않고 충돌로 알린다. 파일이 지워졌으면 `CloseModule(True)`.
- 이 호출은 메인 스레드에서만 한다.

## 컴파일과 메시지

- `IOTAProjectBuilder.Build`는 없다.
- 호출: `(GetActiveProject as IOTAProject).ProjectBuilder.BuildProject(cmOTABuild, True)`.
- `True`는 빌드가 끝날 때까지 기다린다는 뜻이다.
- 결과 통지: `IOTACompileNotifier.ProjectCompileFinished`. 그룹 빌드는 `ProjectGroupCompileFinished`.
- 메시지 뷰: `IOTAMessageServices.AddTitleMessage`, `AddToolMessage`. 도구 접두사는 `RADAgent`.
- 컴파일 메시지를 지울 때는 `ClearCompilerMessages`만 쓴다. `ClearAllMessages`로 다른 도구 출력을 지우지 않는다.

## 디버거 host-tool

- `BorlandIDEServices`를 `IOTADebuggerServices`로 `Supports` 한다. 프로세스는 `ProcessCount > 0`일 때만 `CurrentProcess`로 얻는다.
- 멈춤 판정: `ProcessState in [psStopped, psFault, psResFault, psException]`.
- 호출 스택: `StartCallStackAccess`의 결과가 `csAccessible`일 때만 읽고, 항상 `EndCallStackAccess`를 부른다. `CallHeaders[i]`와 `GetCallPos`의 인덱스는 1부터 시작한다.
- 식 평가: `Evaluate(..., AllowSideEffects = False, ...)`. 결과가 `erDeferred`나 `erBusy`면 기다리지 않고 오류로 돌려준다.
- 실행, 계속, 스텝(over/into/return), 일시 정지, 종료, 중단점 추가는 `IAgentApproval.ApproveChange`로 사용자가 승인한 뒤에만 한다. 계속과 스텝은 `IOTAProcess.Run(TOTARunMode)`, 프로세스가 없을 때 실행은 IDE 액션 `RunRunCommand`, 중단점은 `NewSourceBreakpoint`이다.
- 디버기 메모리 쓰기와 식 평가의 부작용 허용은 host-tool로 열지 않는다.

## 폼 디자이너 host-tool

- 대상은 `.pas` 모듈의 `IOTAFormEditor`다. 네이티브 컴포넌트는 `INTAComponent.GetComponent`, 디자이너는 `INTAFormEditor.FormDesigner`로 얻는다.
- 변경(속성, 추가, 삭제, 이름 변경, 이벤트 연결)은 승인 뒤에만 하고, 끝나면 `IDesigner.Modified`를 부른다. 그 뒤 모듈을 저장한다(omp가 디스크에서 읽는다).
- `CreateComponent`는 컨트롤 위치를 무시하므로 만든 뒤 `SetBounds`로 놓는다. 이벤트는 `IDesigner.CreateMethod`로 기존 메서드를 쓰거나 빈 메서드를 만든다.

## 디버그

비트마다 호스트가 다르다. 64-bit BPL을 32-bit IDE로 디버그하지 않는다.

- Win64: Host Application `$(BDS)\bin64\bds.exe`, Parameters `-pDelphi`
- Win32: Host Application `$(BDS)\bin\bds.exe`, Parameters `-pDelphi`

IDE가 패키지를 잠그면 같은 비트의 BPL을 덮어쓸 수 없다. 그 IDE를 종료한 뒤 빌드한다.
