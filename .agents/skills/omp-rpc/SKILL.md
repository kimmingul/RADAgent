---
name: omp-rpc
description: omp 18.2.8 --mode rpc JSONL 계약. ready 프레임, prompt, abort, host-tools. Use when starting omp, writing the Delphi RPC client, or handling host tool calls. DelphiLSP는 이 스킬이 아니라 delphi-lsp 스킬로 연결한다.
---

# omp RPC

엔진은 설치된 omp 18.2.8이다. 기본 명령:

```text
omp --mode rpc
```

자식의 cwd는 활성 `.dproj` 디렉터리다. `--cwd`로 그 경로를 넘긴다. `@file` 인자는 RPC 모드에서 거부되므로 쓰지 않는다.

DelphiLSP는 이 프로세스에 붙이지 않는다. omp가 `.omp/lsp.json`으로 별도 인스턴스를 띄운다.

## 전송

- stdin: 명령. stdout: `ready`, 응답, 세션 이벤트, host-tool 요청.
- 한 줄에 JSON 객체 하나. 빈 줄은 무시한다.
- `ready`를 읽기 전에 어떤 명령도 보내지 않는다.
- 명령에 `id` 문자열을 넣는다. 응답의 `id`로 짝을 맞춘다. 출력 순서로 짝을 맞추지 않는다.
- stdout을 읽는 동안 stdin에 쓴다. stdout을 닫으면 자식이 멈춘 것처럼 보인다.

## ready

기동 직후 stdout에 이 프레임이 온다. 이 프레임 전 프롬프트는 금지다.

```json
{"type":"ready","protocolVersion":1,"supportedProtocolVersions":[1,2],"maxFrameBytes":1048576,"maxReassembledFrameBytes":67108864}
```

v1만 구현해도 된다. v2 `negotiate_protocol`은 64MiB까지 재조립이 필요할 때만 보낸다. 물리 프레임 한도는 1MiB다.

## prompt

```json
{"id":"req-1","type":"prompt","message":"텍스트"}
```

`prompt` 응답의 `success: true`는 접수다. 턴 종료가 아니다.

- 에이전트 턴은 `agent_end`이고 `isTerminal`이 `false`가 아닐 때 끝이다.
- `data.agentInvoked: false` 또는 이후 `prompt_result`는 로컬에서 끝난 프롬프트다.
- 이미 스트리밍 중이면 `streamingBehavior`가 필요하다. `"steer"` 또는 `"followUp"`. 없으면 실패한다.

## abort

```json
{"id":"req-2","type":"abort"}
```

진행 중인 턴을 끊는다. 자식을 죽이지 않는다. 프로세스를 끝내는 것은 IDE 종료와 패키지 해제일 때뿐이다. stdin을 닫으면 자식은 출력을 비운 뒤 코드 0으로 나간다.

## host-tools

IDE 동작은 호스트 도구로만 연다. `ready` 다음, 첫 `prompt` 전에 등록한다.

```json
{"id":"req-3","type":"set_host_tools","tools":[{"name":"tool_name","description":"...","parameters":{"type":"object","properties":{},"additionalProperties":false}}]}
```

다시 보내면 이전 호스트 도구 집합을 통째로 바꾼다.

omp가 도구를 호출하면 stdout:

```json
{"type":"host_tool_call","id":"host_1","toolCallId":"...","toolName":"tool_name","arguments":{}}
```

완료는 stdin. 실패면 `isError: true`.

```json
{"type":"host_tool_result","id":"host_1","result":{"content":[{"type":"text","text":"..."}]}}
```

취소 프레임 `host_tool_cancel`의 `targetId`가 호출 `id`다. 취소되면 결과를 보내지 않는다.

호스트 도구 구현은 메인 스레드로 넘겨 ToolsAPI를 호출한다. 버퍼 반영 도구는 사용자 승인 없이 버퍼를 고치지 않는다.

## 응답

성공: `{"id":"...","type":"response","command":"prompt","success":true}`

실패: `{"type":"response","command":"...","success":false,"error":"..."}`

깨진 JSON은 `command: "parse"` 실패로 돌아오고 루프는 계속된다. 그 한 줄만 버리고 다음 줄을 읽는다.
