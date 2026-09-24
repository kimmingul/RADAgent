# DelphiLSP 설정

DelphiLSP는 omp가 띄우는 별도 프로세스다. BPL은 DelphiLSP를 기동하지 않고, IDE 프로세스 안의 DelphiLSP에 attach하지 않는다.

omp가 쓸 바이너리는 `%BDS%\bin64\DelphiLSP.exe`다. `%BDS%\bin\DelphiLSP.exe`는 32-bit IDE용이라 omp에 넣지 않는다. 설치본만 사용한다. 실행 파일을 저장소에 복사하지 않는다.

`%BDS%` 기본값: `C:\Program Files (x86)\Embarcadero\Studio\37.0`

스키마의 원본은 `templates/omp.lsp.json`이다. 필드를 템플릿 밖으로 옮기지 않는다.

## 절차

1. IDE에서 대상 프로젝트를 연다.
2. Tools > Options > User Interface > Editor > Language > Code Insight 에서 Generate LSP Config를 켠다.
3. 프로젝트를 닫았다가 연다. `<Project>.delphilsp.json`이 `.dproj` 옆에 생긴다. 이 파일은 생성물이다. 커밋하지 않는다.
4. `templates/omp.lsp.json`을 활성 `.dproj` 디렉터리의 `.omp/lsp.json`으로 복사한다. `.omp/`는 세션 산물이므로 커밋하지 않는다.
5. `command`의 `{{BDS}}`를 설치 경로로 바꾼다. 결과는 `%BDS%\bin64\DelphiLSP.exe`다.
6. `settings.settingsFile`의 `{{PROJECT_DELPHILSP_JSON}}`을 그 프로젝트의 `file:///` URI로 바꾼다. 예: `file:///D:/repo/App/App.delphilsp.json`. 역슬래시를 넣지 않는다.
7. `initOptions`는 템플릿 그대로 둔다. `serverType=controller`, `agentCount=2`, `returnDccFlags=true`, `returnHoverModel=true`, `storeProjectSettings=false`.
8. `fileTypes`, `languageId`, `rootMarkers`, `warmupTimeoutMs`도 템플릿 그대로 둔다.

omp는 `initOptions`를 LSP `initializationOptions`로, `settings`를 `workspace/didChangeConfiguration`으로 보낸다. 서버가 URI를 무시하면 그때 `settingsFile` 위치만 고친다.

`rootMarkers`는 cwd, 즉 활성 `.dproj` 디렉터리만 본다. 상위 폴더의 `.dproj`로는 서버가 뜨지 않는다.

## omp만으로 확인

BPL을 띄우지 않고, 활성 프로젝트 디렉터리에서 `omp --mode rpc`를 실행한다. `.omp/lsp.json`이 그 디렉터리에 있으면 omp가 `%BDS%\bin64\DelphiLSP.exe`를 따로 띄운다. definition과 references는 Debug 구성에서 `$Y`가 켜진 DCU가 있어야 나온다.

## 확인된 동작

2026-09-23, DelphiLSP 37.0(Win64) 기준. definition과 diagnostics는 된다. references는 `-32601 Method not found`로 거절된다. hover는 `-32603 Internal server error`가 났다. 참조 검색은 `grep`으로 한다.

## 이 저장소를 고칠 때

`.dproj`가 `src/`에 있고 omp는 저장소 루트에서 뜬다. `rootMarkers`는 cwd만 보므로 이 저장소에서는 `["src"]`를 쓴다. 두 파일 모두 기계마다 경로가 달라서 커밋하지 않는다. `.gitignore`가 `.omp/`와 `*.delphilsp.json`을 무시한다.

1. 저장소 루트의 `.omp/lsp.json`에 템플릿을 펼친다. `rootMarkers`만 `["src"]`로 바꾸고, `settingsFile`은 `file:///D:/repo/RADAgent/src/RADAgent.delphilsp.json`처럼 적는다.
2. `src/RADAgent.delphilsp.json`은 IDE에서 `src\RADAgent.dproj`를 Generate LSP Config를 켠 채로 열면 생긴다. 2026-09-23에 있는 파일은 다른 프로젝트의 생성본에서 `project`, `projectFiles`, `-TX.bpl`, `-LUrtl;vcl;designide`, `-$D+ -$L+ -$Y+`만 바꿔 손으로 만든 것이다. IDE가 새로 만들면 그 파일로 덮어쓴다.
3. omp에서 `lsp reload`를 실행한 뒤, definition으로 동작을 확인한다.
