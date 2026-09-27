# 향후 할 일

## 구버전 패키지 (10.4 Sydney, 11 Alexandria, 12 Athens)

BPL은 그 릴리스의 컴파일러로 만들어야 한다. 패키지는 그 릴리스의 런타임 패키지(`rtl290.bpl`, `vcl290.bpl`, `designide290.bpl` 등)를 이름으로 불러오고, 13에서 만든 `RADAgent370.bpl`은 `rtl370.bpl`을 찾으므로 12에서 로드되지 않는다. 컴파일러가 만드는 패키지 형식과 ToolsAPI 인터페이스 배치도 릴리스마다 다르다.

1. 각 릴리스가 설치된 PC(또는 VM)를 준비한다. 여러 릴리스를 한 PC에 함께 설치해도 된다.
2. 그 PC에서 `scripts\build-tests.cmd -Version <ver>`로 컴파일과 시험을 확인하고, 나오는 컴파일 오류를 고친다(RTL/VCL 세부 API 차이가 예상된다).
3. IDE에서 확인한다: 채팅 창 열기와 대화, 저장·다시 읽기, 승인 카드, 컴파일과 메시지 뷰, 폼 도구(빈 이벤트 핸들러, FMX 폼 캡처), 도킹 복원, 테마 색, DelphiLSP(`bin\DelphiLSP.exe`).
4. 한 PC에 필요한 릴리스가 모두 있으면 `scripts\package.ps1`이 모두 담은 설치 파일을 만든다. PC가 나뉘면 각 PC의 `artifacts\package\payload\<ver>`를 한 PC의 같은 위치로 모은 뒤 설치 파일을 만드는 단계가 필요하다(`package.ps1`에 모아 둔 payload로 만드는 옵션 추가).
5. 확인이 끝난 릴리스를 README "한계"의 미확인 목록에서 뺀다.

## omp 새 버전 따라가기

설치 파일은 omp가 없을 때 GitHub **최신** 릴리스를 받는다(`installer\RADAgent.iss`). RAD Agent가 확인한 버전(검증 버전, 지금 18.2.11)은 코드와 문서에 고정되어 있으므로, omp가 새로 나올 때마다 둘 사이가 벌어진다. 새 사용자는 확인하지 않은 omp로 시작하게 되고, omp가 프로토콜·옵션·설정 키·도구 등록 방식을 바꾸면 채팅이 깨질 수 있다. RAD Agent가 시작할 때 하는 호환성 검사(`RADAgent.OmpProbe`)는 문제를 알리기만 하고 막지는 않는다.

새 omp 릴리스가 나오면(최소 한 달에 한 번 확인: `gh release list -R can1357/oh-my-pi`):

1. 새 omp를 설치하고(`omp update` 또는 릴리스의 `omp-windows-x64.exe`) `scripts\build-tests.cmd`를 돌린다. 끝부분의 실제 omp 검사(`RunLiveOmpProbe`)가 명령줄 옵션, `ready`·RPC 프로토콜, `set_host_tools`, `tools.xdevInlineDevices`, 명령 목록, 설정 목록, 사용량 보고를 확인한다.
2. omp 릴리스 노트에서 RPC 프레임, 명령줄 옵션, 설정 키, 승인 문구, 슬래시 명령(`RADAgent.SlashRoutes`의 터미널 전용 목록) 변경을 찾아 반영한다. 새로 기대는 곳은 `RADAgent.OmpProbe`나 `tests\OmpCompatTests.pas`에도 넣는다(AGENTS.md).
3. IDE에서 한 바퀴 확인한다: 채팅, 승인 카드, `rad.*` 도구(폼, 컴파일, 디자인 도구), `/btw`, 세션 목록·되돌리기, 설정 창의 모델·계정·사용량.
4. 문제가 없으면 검증 버전을 올린다: `RADAgent.OmpProbe`의 `TestedOmpVersion`, AGENTS.md·DESIGN.md·README(요구 사항과 "검증 범위")·`.agents\skills\omp-rpc`의 버전, 사이트의 요구 사항. RAD Agent를 새 버전으로 릴리스한다.
5. 문제가 있어 바로 고칠 수 없으면, 그 omp 버전을 README "한계"에 적고 사용자에게 알린다. 필요하면 설치 파일이 최신 대신 받을 상한 버전을 두는 방법을 검토한다(지금은 최신만 받는다).
