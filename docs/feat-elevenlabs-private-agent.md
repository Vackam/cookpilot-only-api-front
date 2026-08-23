# feat/elevenlabs-private-agent — 코치 에이전트 private 전환(백엔드 토큰 발급)

## 문제 상황

`feat-elevenlabs-coach.md`의 PoC는 public agent + `ELEVENLABS_AGENT_ID`
dart-define으로 직접 연결했다. agent ID가 앱 바이너리에 박히고 에이전트가
public이라, ID만 추출하면 누구나 세션을 열어 크레딧을 소진할 수 있다.
같은 문서 "이후 작업"에 예고된 private agent + 백엔드 conversation token
발급으로 전환한다.

## 최종 결정

- `cooking/data/elevenlabs_session_api.dart` 신규 — 백엔드
  `POST /api/v1/ai-sessions/elevenlabs`에서 단기 conversation token을 받아온다.
  베타 사용자 헤더를 붙이고, 실패는 `ElevenLabsSessionApiException`으로 변환
  (`exception_advice_api.dart`와 같은 형태).
- `ElevenLabsCoachController`의 `agentId` 파라미터를
  `fetchConversationToken`(비동기 함수)으로 교체. `start()`가 연결 단계에서
  토큰을 받아 `startSession(conversationToken:)`으로 연결한다(SDK 0.6.1이
  private agent용 `conversationToken`을 공식 지원 — 패키지 소스로 확인).
  토큰 발급 실패는 기존 세션 시작 실패와 같은 경로('AI 코치를 시작하지
  못했어요.')로 떨어진다.
- 레시피 컨텍스트는 기존대로 dynamic variable(`recipe_context`)로 클라이언트가
  주입한다 — conversation token에는 Gemini Live 같은 컨텍스트 잠금이 없다.
- `ELEVENLABS_AGENT_ID` dart-define 제거(`env.example.json` 포함). agent ID와
  API 키는 백엔드 환경변수로 이동.

## 검증

- `test/features/cooking/data/elevenlabs_session_api_test.dart` — 헤더·URL·token
  파싱, 비200 상태 코드 보존, 형식 오류, 타임아웃.
- `dart format` 0건, `flutter analyze` 0건, `flutter test` 전체(409건) 통과.
- 실기기 E2E는 백엔드에 `ELEVENLABS_API_KEY`/`ELEVENLABS_AGENT_ID`를 설정하고
  대시보드에서 에이전트를 private으로 바꾼 뒤 수행한다.

## 이후 작업에서 지킬 것

- 에이전트를 private으로 바꾸면 이전 앱 빌드(public 직결)는 연결이 끊긴다 —
  프론트·백엔드를 같이 배포할 것.
- 토큰은 발급 직후 바로 연결해야 한다. 발급해 두고 재사용하지 말 것.
- dynamic variable이 여전히 클라이언트 주입이라 컨텍스트 변조 가능성은 남아
  있다(PoC 문서의 커스텀 LLM 서버 검토 항목 유지).
