# feat/coach-transcript-#1 — 코치 대화 로그 저장·재주입

## 문제 상황

조리 중 코치를 껐다 켜면 이전 맥락이 전부 사라진다. `ElevenLabsCoachController`가
SDK 콜백 중 `onDisconnect`, `onError`만 물려 놔서 발화 텍스트가 앱 메모리에
들어오지도 않았다. 대화가 남는 곳은 ElevenLabs 대시보드 한 곳뿐이었다.

SDK 0.6.1에는 서버 쪽 대화 이어받기가 없다(`startSession`이 받는 건 `agentId`,
`conversationToken`, `dynamicVariables`뿐). 재시작 세션은 항상 0턴에서 시작하므로
이어붙이기는 앱이 해야 한다.

## 검토한 대안 — 요약을 누가 만드는가

이슈 [#1](https://github.com/Vackam/cookpilot-only-api-front/issues/1) 논의 결과.

| 후보 | 판단 |
| --- | --- |
| 앱이 LLM 직접 호출 | 배제. Gemini API 키는 앱에 넣지 않는다(`HttpExceptionAdvicePort` 주석에 이미 명시된 원칙). |
| 백엔드 요약 | 조리 후 기록·리뷰 연결(이슈 2번 목적)에는 맞지만, 코치 재시작용으로는 Gemini 호출과 실패 폴백이 하나씩 더 붙는다. |
| **ElevenLabs 에이전트 자신** | 채택. 대화를 이미 전부 알고 있고, 분당 과금 세션이 이미 도는 중이라 추가 비용·왕복이 없다. |

## 최종 결정

- **요약 주체는 ElevenLabs 에이전트.** client tool `save_context`를 7번째로 추가하고,
  프롬프트에 "조리 상황이 정리될 때마다 세 줄 이내로 요약해 `save_context`를
  호출하라"를 넣는다. 앱은 `summary` 인자를 받아 저장만 한다.
  - 코치를 끄는 시점이 예측 불가(강제 종료, 배터리 방전)라 종료 시점 한 번이 아니라
    **상황이 바뀔 때마다** 갱신하게 했다.
  - 도구 응답은 빈 문자열이다. 요약 저장은 사용자에게 들릴 이유가 없다.
- **저장은 기존 패턴 그대로.** `CoachTranscriptStore`가 `shared_preferences`에 한 덩어리
  JSON으로 쓴다(`cookpilot.coach_transcript.v1`). `CookingSessionStore`와 같은 모양이다.
  - `CoachTranscriptRecorder`가 발화를 메모리에 쌓고 2초 debounce로 쓴다. 매 턴 저장은
    로그 전체를 다시 쓰는 비용을 턴 수만큼 낸다.
  - 상한 200턴. 넘으면 오래된 턴부터 버린다.
  - 저장값에 `sessionId`를 함께 넣고, 복원 시 이번 조리 세션과 다르면 버리고 지운다.
- **재주입 프롬프트는 상태와 대화를 갈라놓는다.** 30분 전 "타이머 맞췄어요"가 현재
  사실로 읽히는 것을 막기 위해 충돌 시 상태가 이긴다고 못 박았다.

  ```
  [현재 상태 — 이것이 사실이다]
  사용자는 지금 5단계를 진행 중입니다: (지시문)
  타이머: 일시정지, 남은 시간 3분 20초
  ...

  [지난 대화 — 참고용, 위 현재 상태와 어긋나면 위를 따른다]
  이번 조리에서 이미 나눈 대화입니다. ... 처음부터 인사하지 말고 바로 이어서 도와주세요.
  지난 상황 요약:
  - 양파 대신 대파 사용
  직전 대화 6턴:
  사용자: ...
  코치: ...
  ```

  - 직전 대화는 8턴만 넣는다. 오래된 대화는 도움이 아니라 방해다.
  - 재인사 억제는 `AgentOverrides.firstMessage` 대신 **프롬프트 한 줄**로 했다.
    override는 대시보드 Security 토글이 필요할 수 있고 실기기 확인 전에는 단정할 수
    없다(이슈 본문 "확인이 필요한 것" 참고). 프롬프트로 안 잡히면 그때 override를
    검토한다.
- **전사본은 조리 완료 시 반드시 지운다.** `shared_preferences`는 암호화되지 않는다.
  `_finishCooking`에서 active session `clear()` 직후 `CoachTranscriptRecorder.clear()`가
  돈다. clear 뒤에는 늦게 도착한 발화·debounce가 로그를 되살리지 못하게 영구히 막는다
  (`PendingReviewDraftStore`가 겪은 문제와 같은 모양).
  - 조리를 끝내지 않고 화면을 나가면 지우지 않고 flush만 한다 — "이어서 조리하기"로
    돌아올 수 있다.

## 실기기 검증에서 드러난 두 가지 (2026-08-19)

껐다 켜는 재주입 자체는 동작했지만 두 가지가 걸렸다.

### 1. 코치가 이전 단계로 못 보낸다

client tool에 `next_step`만 있었다. 화면 버튼(`onPrevStep`)과 STT
(`VoiceIntentType.previous`)는 `_moveCookingStep(-1)`을 쓰는데 코치에게만 그
손잡이가 없었다. `previous_step`을 같은 실행부에 붙였다.

### 2. 재료 대체가 "지난 대화"로 밀려 사실 취급을 못 받는다

갈비→대패 삼겹살, 양파→파로 바꿔 놓고 코치를 껐다 켜면, 코치가 갈비·양파를
먼저 설명하고 대패·파는 "이전 대화에서 그렇게 바꿨죠"로 격하했다.

원인은 설계대로다. `_coachRecipePrompt()`가 재료를 `widget.recipe.ingredients`
원본으로 찍었고, 대체 사실은 `save_context` 요약이나 직전 8턴 —
`[지난 대화 — 참고용, 위 현재 상태와 어긋나면 위를 따른다]` 블록 — 에만
들어갔다. "충돌 시 현재 상태가 이긴다"는 규칙이 그대로 작동해 원본 재료가
이긴 것이다.

**검토한 대안**

| 후보 | 판단 |
| --- | --- |
| `save_context` 요약을 `[현재 상태]` 블록으로 옮긴다 | 코드 변경은 최소지만 요약이 자유 텍스트라 대체 항목이 빠지거나 흐려질 수 있고, `save_context`가 대시보드에 등록돼 있어야만 동작한다. |
| **`substitute_ingredient` client tool 추가** | 채택. 대체가 원래 재료 → 대체 재료의 구조화된 앱 상태가 되므로 "현재 상태가 이긴다" 규칙과 충돌하지 않는다. |

**최종 결정**

- 도구 `substitute_ingredient(original, replacement)`를 추가하고, 앱이
  `CoachTranscriptRecorder`에 원래 재료 → 대체 재료 맵으로 들고 있는다.
  저장·세션 검증·조리 완료 시 정리는 전사본과 같은 수명을 탄다.
- **재료 목록을 `[현재 상태]` 블록 안으로 옮겼다.** 재료는 조리 중에 바뀌는
  사실이라 정적 레시피 정보와 같은 자리에 둘 수 없다. 단계 목록은 그대로
  블록 밖에 남는다.

  ```
  [현재 상태 — 이것이 사실이다]
  재료 (이번 조리 확정본):
  - 대패 삼겹살 300g ← 갈비 대체
  - 파 1개 (선택) ← 양파 대체
  사용자는 지금 3단계를 진행 중입니다: ...
  ```

- 대체 이름 매칭은 **정확히 일치할 때만** 한다. `contains`로 넓히면 `파`가
  `양파`에 걸리는 식의 오매칭이 생긴다. 레시피 표기와 다른 이름으로 온
  대체는 목록 끝에 `- 마늘가루 ← 다진 마늘 대체`로 따로 붙여 빠뜨리지 않는다.
- 상한 30개. 넘으면 **새 대체를 무시한다** — 턴과 달리 오래된 것을 버리면
  코치가 이미 확정한 재료를 잊는다. 이미 있는 재료를 다시 바꾸는 것은 상한과
  무관하게 허용한다.
- 저장값의 대체 항목이 하나라도 손상되면 로그 전체를 버린다. 재료를 반쯤
  잘못 아는 코치가 아예 모르는 코치보다 위험하다.

## 범위에서 뺀 것

- **인터넷 끊김 자동 재연결.** 저장·재주입이 먼저 있어야 재연결이 의미가 있어 이번
  브랜치는 수동으로 껐다 켜는 경로만 다룬다. 다음 브랜치로 미룸.
- **조리 후 기록(이슈 2번 목적).** 리뷰·개인 버전 생성 연결은 백엔드 몫이고, 이번
  변경은 완료 시점에 로그를 지우기 때문에 그 경로가 붙으면 clear 시점을 다시 잡아야
  한다.

## 검증

- `dart format`·`flutter analyze` 0건, `flutter test` 전체 통과.
- `test/features/cooking/application/coach_transcript_store_test.dart` — 왕복 저장,
  손상 JSON·손상 턴·상한 초과 저장값 폐기, clear, **재료 대체 왕복·손상 항목
  폐기·대체 상한 초과 폐기**.
- `test/features/cooking/application/coach_transcript_recorder_test.dart` — debounce
  한 번만 저장, flush 즉시 저장, 빈 발화 폐기, 요약 갱신, 상한 트림, 다른 세션 로그
  폐기, **clear 뒤 늦은 발화가 되살리지 못함**, 저장 실패 재시도, **재료 대체
  최신 하나만 유지·상한 도달 시 새 대체만 무시·clear가 대체도 지움**.
- `test/features/mvp/cook_session_coach_transcript_test.dart` — 조리 완료 시 전사본
  정리, 지난 세션 전사본 폐기, **재료 대체가 `[현재 상태]` 재료 목록에 반영되고
  대체만 있을 때는 `[지난 대화]` 블록이 붙지 않음**.
- `previous_step`은 기존 `_moveCookingStep(-1)` 실행부를 그대로 쓰고, 화면 버튼·STT
  경로 테스트가 이미 그 실행부를 덮는다. client tool 배선 자체는
  `ElevenLabsCoachController`와 같은 이유로 실기기 검증에 맡긴다.
- `ElevenLabsCoachController`는 SDK 콘크리트 클래스 래핑이라 기존 방침대로 단위 테스트
  없이 실기기 검증으로 대신한다.

## 이후 작업에서 지킬 것

- **대시보드에 client tool 3종을 추가 등록해야 한다** (이름 정확히 일치).
  - `save_context` — 파라미터 `summary`: string. "Wait for response"는 **끄는**
    편이 낫다(켜면 빈 `message`를 코치가 읽으려 할 수 있다). 등록 전까지 요약은
    저장되지 않고 원문 8턴만 재주입된다.
  - `previous_step` — 파라미터 없음. "Wait for response" 켬.
  - `substitute_ingredient` — 파라미터 `original`: string, `replacement`: string.
    "Wait for response" 켬. **등록 전까지 재료 대체는 앱에 남지 않는다** — 코치가
    말로만 수긍하고 재시작하면 원본 재료로 돌아간다.
- 시스템 프롬프트는 여전히 `{{recipe_context}}` 한 줄이어야 한다. 재주입 블록은 앱이
  이 변수 안에 넣는다.
- 실기기에서 확인할 것: (1) 껐다 켰을 때 재인사가 사라지는지, (2) 에이전트가
  `save_context`를 실제로 부르는지, (3) 요약이 음성으로 새지 않는지,
  (4) "이전 단계로 돌아가자"에 `previous_step`이 호출되는지, (5) 재료를 바꾸면
  `substitute_ingredient`가 호출되고 껐다 켠 뒤에도 바뀐 재료로 안내하는지.
- 요약이 원문 8턴보다 나은지 확인되기 전에는 턴 수·debounce를 더 만지지 말 것.
