# feat/elevenlabs-coach — 음성 코치 ElevenLabs Agents PoC

## 문제 상황

Gemini Live 직결 코치(only-api)는 실기기(A52)에서 self barge-in을 half-duplex
게이트로 막았지만, 그 대가로 코치 발화 중 음성 가로채기를 잃었다(탭 버튼으로 대체).
레벨(RMS) 기반 음성 판별은 실측으로 불가 판정 — AEC 잔여 에코(RMS ~936)가 사용자
목소리(~305)보다 3배 컸다. 근본 원인은 마이크(record)와 재생(flutter_pcm_sound)이
분리된 플러그인이라 참조 신호 기반 AEC를 쓸 수 없는 구조.

## 검토한 대안

1. **WebRTC APM 네이티브 직접 통합** — 참조 신호 AEC를 우리가 감는 것. Gemini 유지
   가능하지만 네이티브 작업 며칠 + 기기 튜닝. 보류.
2. **LiveKit + Gemini Live** — Gemini 유지 + full-duplex. 백엔드에 에이전트 서버
   운영이 추가돼 PoC로는 무겁다. 장기 후보로 남김.
3. **ElevenLabs Agents SDK** — WebRTC(LiveKit) 스택이 SDK에 내장, 에코 캔슬·음성
   barge-in·턴테이킹이 그대로 나온다. 분당 과금(무료 15분/월)이지만 PoC 목적에
   가장 빠르다 — 채택.

## 최종 결정

- 브랜치는 only-api에서 파생. `CookingCoachEngine` 인터페이스를 추출해 화면이
  엔진을 갈아 끼운다. PoC 통과 후 이 브랜치는 **ElevenLabs 단일 엔진**으로
  정리 — Gemini 직결 경로(세션·오디오 포트·record/flutter_pcm_sound/
  web_socket_channel 의존성)는 삭제했고 only-api 브랜치에 보존돼 있다.
  `COACH_ENGINE` dart-define도 제거.
- `cooking/data/elevenlabs_coach_controller.dart` — `elevenlabs_agents` SDK 래퍼.
  오디오 포트 없음(SDK가 마이크·재생·AEC 소유), `interrupt()`는 no-op(음성
  barge-in 내장), 화면의 탭 가로채기 버튼은 이 엔진에서 숨긴다.
- 레시피 컨텍스트는 dynamic variable(`recipe_context`)로 주입(화면이 Recipe로
  생성). 원래 `overrides.agent.prompt`로 설계했으나 **SDK 0.6.1 버그**로 전환:
  API 규격은 `agent.prompt`가 객체(`{"prompt": "..."}`)인데 SDK가 문자열로
  보내서 서버가 세션을 1008 validation error로 즉시 끊는다(WebSocket 직접
  접속 프로브로 실측 확정). dynamic variable 경로는 SDK가 규격대로 보낸다.
- 따라서 대시보드 에이전트의 시스템 프롬프트는 `{{recipe_context}}` 한 줄이어야
  한다. Gemini 경로의 "백엔드가 토큰에 잠금"과 달리 클라이언트 주입이다 —
  PoC 한정 타협이고, 정식 도입 시 백엔드 conversation token 발급으로 옮긴다.
- 에이전트 ID는 `--dart-define ELEVENLABS_AGENT_ID=...`(env.dev.json, 미커밋).
- 코치 화면 상태 문구는 엔진 이름을 따라간다(ElevenLabs/Gemini Live).

## ElevenLabs 대시보드 설정 (수동, 1회)

1. https://elevenlabs.io 가입 → Agents → Create agent
2. 설정: LLM(Gemini Flash 계열 권장), 언어 `Korean`, 목소리 선택,
   first message는 짧은 한국어 인사
3. **시스템 프롬프트를 `{{recipe_context}}` 한 줄로 교체** — 앱이 세션마다
   이 dynamic variable에 레시피 전문을 넣는다. Security 탭의 override 허용
   토글은 필요 없다(SDK 버그로 override 경로를 쓰지 않음, 위 참고).
4. PoC는 public agent로 시작(인증 없음) → agent_id 복사
5. `env.dev.json`의 `ELEVENLABS_AGENT_ID`에 붙여넣고
   `flutter run --dart-define-from-file=env.dev.json`

## client tools와 세션 컨텍스트

음성은 ElevenLabs가 전부 소유(STT→LLM→TTS)하므로 타이머·단계 조작은
client tool로 프론트에 위임한다 — 예전 STT 라우터가 로컬에서 처리하던
것의 펑션 콜 버전이다(문자열 파싱 없음, LLM이 구조화된 호출을 보냄).
에이전트가 도구를 호출하면 앱이 기존 `*FromVoice` 실행부를 재사용하고,
결과 문장을 도구 응답(`message`)으로 돌려줘 코치가 읽어준다.

| 도구 이름 | 파라미터 | 동작 |
| --- | --- | --- |
| `start_timer` | 없음 | 현재 단계 프리셋 타이머 시작(일시정지면 재개) |
| `extend_timer` | `seconds`(number, LLM 프롬프트) | 타이머 시간 추가(미지정 시 60초) |
| `pause_timer` | 없음 | 실행 중 타이머 일시정지 + OS 알람 취소 |
| `resume_timer` | 없음 | 일시정지 타이머 재개 + OS 알람 재예약 |
| `reset_timer` | 없음 | 프리셋 시간으로 리셋(정지 상태, 연장분 폐기) |
| `next_step` | 없음 | 다음 단계로 이동, 새 단계 안내를 응답으로 반환 |

대시보드에서 위 6개를 **Client tool**로 등록해야 하며(이름 정확히 일치,
"Wait for response" 켬), 등록 전에는 에이전트가 말로만 응답한다.

이후 `previous_step`, `save_context`, `substitute_ingredient`가 추가됐다 —
`docs/feat-coach-transcript-#1.md` 참고.

세션 컨텍스트 동기화:
- 연결 시점 프롬프트에 현재 단계 번호·안내를 포함한다.
- 조리 중 단계가 바뀌면(버튼·STT·next_step 모두) `contextual_update`로
  코치에게 실시간 통지한다 — 대화 턴을 만들지 않고 배경 지식만 갱신.
- 코치가 켜져 있어도 조리 UI(단계·타이머)를 그대로 보여준다(전체 화면
  점유 제거). 코치 활성 중 단계 이동 시 로컬 TTS 단계 읽기는 생략한다 —
  코치 음성과 겹치고 TTS 소리가 코치 마이크로 들어가기 때문.

## 검증

- `dart format`·`flutter analyze` 0건, 기존 테스트 회귀 없음(engine 인터페이스
  추출은 기존 팩토리 주입과 호환).
- ElevenLabs 어댑터는 SDK 콘크리트 클래스 래핑이라 단위 테스트 없이 실기기
  검증으로 대신한다(PoC). 정식 도입 시 세션 경계를 포트로 추출해 테스트 추가.
- 실기기 E2E(A52, 2026-08-11) **통과**: 연결 → 인사말 → 레시피 인지 →
  **말하는 도중 음성으로 끊기(barge-in)** → 코치 끄기 정상 종료.
- SDK 버그 진단 과정: override 미전송 시 세션 유지·전송 시 즉시 종료로 격리
  → `wss://api.elevenlabs.io/v1/convai/conversation`에 직접 붙는 Dart 프로브로
  객체형 prompt는 통과, SDK와 같은 문자열형은 1008 거절임을 재현.

## 이후 작업에서 지킬 것

- 분당 과금 — 무료 티어 15분/월. 테스트 세션은 짧게 끊을 것.
- PoC 판정 기준: 음성 barge-in 체감 + 한국어 턴테이킹 품질이 Gemini 경로 대비
  확실히 나은가. 아니면 LiveKit+Gemini(대안 2)로 회귀.
- 정식 도입 시: private agent + 백엔드 conversation token 발급(ElevenLabs
  API key는 서버에만), 사용자별 사용량 제한. dynamic variable은 토큰에 잠기지
  않고 클라이언트가 보내는 구조라, 컨텍스트 변조가 문제되면 커스텀 LLM 서버
  경유를 검토. 세션 결과(대화 로그)를 리뷰 흐름에 연결할지 결정.
- SDK가 prompt override를 객체로 보내도록 고쳐지면(>0.6.1) override 경로 복귀
  검토 — 그때는 대시보드 Security의 프롬프트 override 허용 토글이 다시 필요.
