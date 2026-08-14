# feat-recipe-pagination — 레시피 목록 페이지네이션 대응

## 문제 상황

레시피가 늘면서 메인 화면이 뜨지 않았다. `GET /api/v1/recipes` 가 전체 목록을 내려주고,
홈은 그 전부를 `ListView(children:)` 안의 `Column` 에 eager 렌더한다(`main_shell.dart`
"전체 레시피" 섹션). 백엔드를 페이지네이션으로 바꾸면서 응답이 배열 → 페이지 envelope 으로
바뀌었고, 클라이언트 파싱을 여기에 맞춘다.

## 검토한 대안

- **배열 유지 + `X-Total-Count` 헤더** — 프론트/테스트를 안 건드려도 됐지만, 메타가 헤더에 숨어
  이후 더보기 구현이 덜 명시적이 된다. 채택하지 않았다.
- **envelope 채택(채택)** — `{items, page, size, totalElements, hasNext}`. 계약 파괴 변경이라
  파싱과 테스트를 함께 고쳤다.

## 최종 결정

### 1. `findAll` 만 envelope 파싱, `_findSummaries` 는 그대로

`RecipeRepository._findSummaries` 는 `/recipes`, `/home/recent-recipes`, `/favorites` 세 곳이
공유하는데 이번에 페이지네이션된 건 `/recipes` 뿐이다. 공용 디코더를 바꾸면 나머지 둘이 깨지므로
`findAll` 만 자체 파싱 경로를 갖는다.

```dart
Future<List<RecipeSummary>> findAll({int page = 0, int size = 10})
```

### 2. `hasNext` / `totalElements` 는 지금 버린다

무한 스크롤 UI 는 이번 범위가 아니다. 쓰는 화면이 없는 값을 미리 모델로 끌어올리지 않고,
더보기를 붙일 때 반환 타입을 함께 바꾼다.

### 3. 로컬 필터링 화면은 `size: 100` 으로 조회한다

검색(`SearchScreen`)과 복구 시 제목 매칭은 서버 검색 없이 받은 목록을 클라이언트에서 훑는다.
기본 10건이면 검색이 사실상 망가지므로 서버 상한과 같은 `_localScanPageSize = 100` 으로 받는다.
홈(`_loadCatalog`)은 기본 10건 그대로다.

## 주요 변경 파일

- `lib/features/recipe/data/recipe_api.dart` — `findAll({page, size})` envelope 파싱
- `lib/features/mvp/main_shell.dart` — `_localScanPageSize`, 검색·딥링크 조회에 `size: 100`
- `test/features/recipe/data/recipe_api_test.dart` — 기대 URL `?page=0&size=10`, 응답 본문 envelope
- `test/features/mvp/home_review_recovery_test.dart` — fake 의 `findAll` 시그니처 정합

## 검증

```bash
dart format . && flutter analyze && flutter test
```

**주의**: 이번 작업 환경(WSL)에는 Windows용 Flutter SDK만 있어 위 세 명령을 실행하지 못했다.
Windows 셸에서 반드시 한 번 돌리고 커밋할 것. 백엔드 쪽은 `./gradlew build` 로 검증했다.

## 이후 작업에서 지킬 것

- 홈 "전체 레시피" 는 이제 10건에서 멈춘다. 더보기/무한 스크롤을 붙일 때 `findAll` 이 `hasNext` 를
  같이 돌려주도록 반환 타입을 바꾼다.
- 무한 스크롤을 `ListView.builder` 로 만들 경우, 진입 애니메이션을 `itemBuilder` 안에 넣지 않는다
  (뷰포트 재진입마다 재생됨 — `docs/feat-motion.md`).
- 카탈로그가 100건을 넘으면 클라이언트 검색이 상위 100건만 보게 된다. 그 전에 서버 검색
  엔드포인트가 필요하다.
