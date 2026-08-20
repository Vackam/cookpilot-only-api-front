# fix/image-decode-oom — 음식 사진 디코딩 메모리 초과로 iOS 앱 강제 종료

## 문제 상황

iPhone 16 Pro 실기기(릴리즈 빌드)에서 서버 연결 후 음식 사진이 뜨기 시작하면 앱이
곧바로 강제 종료됐다. 프로파일 모드로 붙여 잡은 크래시 지점:

```
EXC_RESOURCE (RESOURCE_TYPE_MEMORY: high watermark memory limit exceeded) (limit=3376 MB)
frame #0: Flutter`ycc_rgb_convert   ← libjpeg의 JPEG 디코딩 함수
```

즉 JPEG 디코딩 도중 iOS 앱 메모리 상한(약 3.3GB)을 넘어 시스템이 죽인 것이다.

## 원인

시드 데이터가 식품안전나라 레시피 1,164개로 확장되면서 원본급 사진이 섞여 들어왔다.
전체 이미지 1,156개의 헤더를 실측한 결과:

- 최대 4480×6720(30MP), 파일 최대 38.8MB
- 이런 원본급 사진이 수십 장 — 디코딩 시 **장당 약 112MB** (W×H×4바이트)
- 전체를 디코딩하면 합계 6.9GB로 상한의 2배

`FoodImage`가 `Image.network`를 디코딩 크기 제한 없이 사용해, 몇십 픽셀짜리 목록
썸네일 자리에도 원본 해상도 전체를 메모리에 폈다. 목록 스크롤로 이런 이미지가
수십 장 디코딩되는 순간 상한을 넘는다. 시뮬레이터·데스크톱은 메모리 상한이 느슨해
재현되지 않고, 실기기에서만 죽는다.

## 수정

`FoodImage`(모든 음식 사진이 지나가는 단일 관문)에 `cacheWidth`를 지정해 디코딩
해상도를 실제 표시 크기(논리 폭 × devicePixelRatio)로 제한했다. `width`가 없는
채움형 배치는 화면 폭을 상한으로 쓴다. 30MP 원본도 이제 표시 크기로만 디코딩된다
(장당 ~1MB 수준). 네트워크 다운로드 크기는 그대로다 — 디코딩 메모리만 줄인다.

## 검증

- 실기기(iPhone 16 Pro, 릴리즈 빌드)에서 수정 전 100% 재현 → 수정 후 동일 경로에서
  재현 안 됨.
- `dart format` / `flutter analyze` 0건 / `flutter test` 전체 통과.

## 알려진 약점·후속

- 근본적으로는 데이터 쪽 처리도 필요하다: 시드 파이프라인에서 썸네일 리사이즈
  또는 백엔드 이미지 프록시. 지금은 목록 한 화면을 그리는 데 장당 최대 39MB를
  **다운로드**하는 상태라(디코딩과 별개), 사용자 데이터 사용량 문제가 남아 있다.
- `cacheHeight`는 지정하지 않았다 — 폭만 제한하면 비율이 유지되고, 세로로 긴
  원본도 폭 기준으로 함께 줄어든다.

## only-api 이식 시 추가로 나온 것

메인 저장소 커밋 `de1b5f9`(#53)를 그대로 옮기면서 `layout_one_control.dart`의
`_PhotoSizeBadge`(kDebugMode 전용)가 한 줄 함께 바뀌었다.

배지는 원본 픽셀 크기를 재려고 `NetworkImage(...).resolve(...)`에 `onError` 없는
`ImageStreamListener`를 달고 있었다. 지금까지는 확대 화면의 `FoodImage`가 같은 캐시 키
(`NetworkImage`, scale 1.0)에 에러 리스너를 달아 줘서 로드 실패가 가려졌는데, `cacheWidth`가
붙으면서 `FoodImage` 쪽 키가 `ResizeImage`로 바뀌어 배지 스트림에 에러 리스너가 하나도
남지 않게 됐다. 그러면 로드 실패가 전역 오류로 올라간다(`cook_layout_test`의 확대 화면
테스트가 이걸로 깨졌다). 배지에 빈 `onError`를 달아 막았다 — 실패하면 배지는 '원본 ?'로 남는다.
