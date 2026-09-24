---
name: delphi-lsp
description: RAD Studio 13.2 설치본 DelphiLSP를 omp LSP 설정으로만 연결한다. Generate LSP Config, .delphilsp.json, .omp/lsp.json. Use when configuring DelphiLSP or definition/references. pasls, delphi-lookup, ACP Registry, IDE 프로세스 attach는 사용하지 않는다.
---

# DelphiLSP

omp가 별도 DelphiLSP 프로세스를 띄운다. `bds.exe` 안에 이미 있는 DelphiLSP에는 attach하지 않는다. 바이너리를 저장소에 복사하지 않는다.

| IDE | 그 IDE가 쓰는 서버 | omp가 쓸 서버 |
| --- | --- | --- |
| 32-bit `%BDS%\bin\bds.exe` | `%BDS%\bin\DelphiLSP.exe` | 사용하지 않음 |
| 64-bit `%BDS%\bin64\bds.exe` | `%BDS%\bin64\DelphiLSP.exe` | 이 경로 |

`%BDS%` 기본값: `C:\Program Files (x86)\Embarcadero\Studio\37.0`

## 프로젝트 설정 파일

1. IDE에서 대상 프로젝트를 연다.
2. Tools > Options > User Interface > Editor > Language > Code Insight 에서 Generate LSP Config를 켠다.
3. 프로젝트를 닫았다가 연다. `<Project>.delphilsp.json`이 `.dproj` 옆에 생긴다.
4. 그 파일은 생성물이다. 커밋하지 않는다. `.gitignore`가 `*.delphilsp.json`을 무시한다.
5. omp에 넘길 값은 그 파일의 `file:///` URI다. 예: `file:///D:/repo/App/App.delphilsp.json`. 역슬래시를 넣지 않는다.

## omp 설정

RADAgent는 omp를 띄울 때 활성 Delphi 프로젝트 옆에 `<Project>.delphilsp.json`이 있으면 아래 규칙으로 `.omp/lsp.json`을 직접 쓴다(`RADAgent.OmpLaunch.EnsureDelphiLsp`). 손으로 만들 필요는 이 저장소를 고칠 때뿐이다.


스키마의 원본은 `templates/omp.lsp.json`이다. 활성 `.dproj` 디렉터리의 `.omp/lsp.json`으로 펼친다. `.omp/`는 세션 산물이므로 커밋하지 않는다.

- `command`: 템플릿의 `{{BDS}}`를 설치 경로로 바꾼 64-bit `DelphiLSP.exe`.
- `settings.settingsFile`: `{{PROJECT_DELPHILSP_JSON}}` 자리에 위 URI.
- `initOptions`: `serverType=controller`, `agentCount=2`, `returnDccFlags=true`, `returnHoverModel=true`, `storeProjectSettings=false`.
- `fileTypes`: `.pas` `.dpr` `.dpk` `.pp` `.inc`
- `languageId`: `pascal`
- `rootMarkers`: `*.dproj` `*.dpr` `*.groupproj`
- `warmupTimeoutMs`: `60000`

omp는 `initOptions`를 LSP `initializationOptions`로, `settings`를 `workspace/didChangeConfiguration`으로 보낸다. 필드를 템플릿 밖으로 옮기지 않는다. 서버가 URI를 무시하면 그때 `settingsFile` 위치만 고친다. pasls로 갈아타지 않는다.

`rootMarkers`는 cwd(활성 `.dproj` 디렉터리)만 본다. 상위 폴더의 `.dproj`로는 서버가 뜨지 않는다.

## 되는 요청

2026-09-23 DelphiLSP 37.0(Win64)에서 확인한 결과. Debug DCU가 없는 이 저장소에서도 definition과 diagnostics는 된다. references는 `-32601 Method not found`로 거절되고, hover는 `-32603`이 난다. 참조 검색은 `grep`으로 한다. 이 저장소 자체에 쓰는 설정은 `docs/lsp-setup.md`의 "이 저장소를 고칠 때"를 따른다.
