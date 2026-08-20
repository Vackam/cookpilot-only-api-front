# 레시피 카탈로그 서버 검색·페이지네이션 (메인 저장소에서 이식)

메인 저장소(`Cook-Pilot/frontend`) 커밋 `1561ddc`(#52)의 화면을 only-api 쪽으로 옮긴 작업이다.
`docs/feat-recipe-pagination.md`가 남겨 둔 후속("카탈로그가 100건을 넘으면 클라이언트 검색이
상위 100건만 보게 된다. 그 전에 서버 검색 엔드포인트가 필요하다")에 대응한다.

## 문제 상황

검색 화면이 `GET /api/v1/recipes?size=100`으로 카탈로그 앞부분을 받아 제목·설명만 앱에서
필터링했다. 서버 상한이 100건이라 카탈로그(현재 1,150건)의 뒤쪽 레시피는 검색에 아예 걸리지
않는다. 재료로는 검색할 수 없고, 결과는 한 화면에 전부 쏟아진다.

## 검토한 대안

- **클라이언트 필터 유지 + `size` 상향** — 서버 상한이 100이라 늘릴 곳이 없다. 상한을 올려도
  전체 카탈로그를 매번 내려받는 비용이 남는다.
- **`hasNext`/`totalElements`로 기존 목록에 페이지 이동만 붙이기** — 페이지 이동은 생기지만
  검색어가 서버에 가지 않아 문제의 절반(뒤쪽 레시피가 안 잡힘)이 그대로다.
- **메인의 검색 화면을 이식하되 계약은 only-api 백엔드에 맞춘다(채택)**.

## 최종 결정

### 1. 계약은 메인이 아니라 only-api 백엔드 실물에 맞춘다

메인은 검색을 별도 봉투(`pageSize`/`totalPages`/`totalItems`, page 1-base)로 열었지만,
only-api 백엔드(2026-08-20 `localhost:8080` 실측)는 **목록 API와 같은 봉투에 0-base page**다.

```
GET /api/v1/recipes/search?title=&ingredient=&page=0&size=9
→ {"items": [RecipeSummary...], "page": 0, "size": 9, "totalElements": 1150, "hasNext": true}
```

- `title`·`ingredient`를 함께 주면 **AND**다(실측: 가지 26건 ∩ 두부 157건 → 4건).
- 둘 다 비면 전체 카탈로그를 페이지로 돌려준다.
- `size` 상한은 목록과 같은 100. 101을 보내면 400.

봉투가 목록과 같으므로 모델도 하나로 둔다 — `RecipePage{items, page, size, totalElements,
hasNext}`. `findAll`은 같은 파서를 타고 `items`만 돌려준다(호출부 시그니처 유지). 화면이 쓰는
마지막 페이지 번호는 서버가 주지 않아 `totalPages` 계산 게터로 파생시킨다.

### 2. page는 안에서 0-base, 보여줄 때만 +1

서버 계약이 0-base라 상태(`_page`)와 요청은 0부터 센다. `_RecipePagination`이 `${page + 1} /
$totalPages`로 그린다. 두 기준을 화면 중간에서 섞지 않는다.

### 3. 입력은 두 칸, 검색은 명시적 제출

요리 이름(`title`)과 재료(`ingredient`)는 독립 입력이다. 입력할 때마다 즉시 검색하지 않는다 —
한글 조합 중에 요청이 반복된다. 페이지 크기는 9로 고정.

### 4. 페이지 이동은 네 개까지

처음·이전·다음·마지막만 둔다. ±5 점프를 더하면 탭 타겟(48dp) 일곱 개가 논리 폭 360dp
기기에서 한 줄에 안 들어가 마지막 버튼이 다음 줄로 밀린다(메인 저장소 실기기 제보,
2026-08-19).

### 5. 메인과 달라진 부분

- 색·여백·탭 타겟은 하드코딩 대신 디자인 토큰(`context.color`/`space`)을 쓴다.
- 인증 헤더는 `BetaUserSession`을 그대로 탄다(메인은 `AuthSession`으로 갈아탄 상태).

## 검증

- `recipe_api_test` — 검색 URL 쿼리·사용자 헤더·봉투 파싱·`totalPages` 올림, 잘못된 `items`
  형식 거부
- `recipe_search_screen_test` — 제목·재료 제출, 다음/마지막/처음 이동(0-base 요청 ↔ 1-base
  표시), 초기화, 1080×2400(3x) 기기에서 페이지 컨트롤이 한 줄인지
- 실서버(`localhost:8080`) 실측으로 계약 확인 — 봉투 키, 0-base, AND 조건, size 상한 400
- `dart format --set-exit-if-changed .` / `flutter analyze` 0건 / `flutter test` 437개 통과

## 이후 작업에서 지킬 것

- 결과 개수는 현재 페이지 항목 수가 아니라 서버 `totalElements`를 표시한다.
- 검색 조건을 바꾸거나 초기화하면 0페이지부터 다시 조회한다.
- page는 0-base가 기준이다. 1-base는 화면 표시에서만 만든다.
- 조리 세션 복원의 제목 매칭은 아직 `findAll(size: 100)`을 쓴다. 카탈로그가 이미 1,150건이라
  100건 밖의 레시피는 제목으로 복원되지 않는다 — 이쪽도 검색 엔드포인트로 옮길 것.
