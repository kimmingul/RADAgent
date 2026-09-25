# 향후 할 일

## 구버전 패키지 (10.4 Sydney, 11 Alexandria, 12 Athens)

BPL은 그 릴리스의 컴파일러로 만들어야 한다. 패키지는 그 릴리스의 런타임 패키지(`rtl290.bpl`, `vcl290.bpl`, `designide290.bpl` 등)를 이름으로 불러오고, 13에서 만든 `RADAgent370.bpl`은 `rtl370.bpl`을 찾으므로 12에서 로드되지 않는다. 컴파일러가 만드는 패키지 형식과 ToolsAPI 인터페이스 배치도 릴리스마다 다르다.

1. 각 릴리스가 설치된 PC(또는 VM)를 준비한다. 여러 릴리스를 한 PC에 함께 설치해도 된다.
2. 그 PC에서 `scripts\build-tests.cmd -Version <ver>`로 컴파일과 시험을 확인하고, 나오는 컴파일 오류를 고친다(RTL/VCL 세부 API 차이가 예상된다).
3. IDE에서 확인한다: 채팅 창 열기와 대화, 저장·다시 읽기, 승인 카드, 컴파일과 메시지 뷰, 폼 도구(빈 이벤트 핸들러, FMX 폼 캡처), 도킹 복원, 테마 색, DelphiLSP(`bin\DelphiLSP.exe`).
4. 한 PC에 필요한 릴리스가 모두 있으면 `scripts\package.ps1`이 모두 담은 설치 파일을 만든다. PC가 나뉘면 각 PC의 `artifacts\package\payload\<ver>`를 한 PC의 같은 위치로 모은 뒤 설치 파일을 만드는 단계가 필요하다(`package.ps1`에 모아 둔 payload로 만드는 옵션 추가).
5. 확인이 끝난 릴리스를 README "한계"의 미확인 목록에서 뺀다.
