import 'dart:async';

import 'package:cookpilot/features/recipe/data/recipe_api.dart';
import 'package:cookpilot/features/user/data/beta_user_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const baseUrl = 'http://example.test';
  const recipeId = '10000000-0000-0000-0000-000000000001';
  const userId = '90000000-0000-0000-0000-000000000001';

  setUp(() {
    BetaUserSession.setCurrentUser(
      const BetaUser(id: userId, displayName: '베타 사용자 1', betaNumber: 1),
    );
  });

  tearDown(BetaUserSession.clear);

  test('사용자 세션이 없으면 HTTP 요청을 보내지 않는다', () async {
    BetaUserSession.clear();
    var requestCount = 0;
    final repository = RecipeRepository(
      baseUrl: baseUrl,
      client: MockClient((_) async {
        requestCount++;
        return _jsonResponse('[]');
      }),
    );

    await expectLater(repository.findAll(), throwsA(isA<BetaUserException>()));
    expect(requestCount, 0);
  });

  test('목록 응답에서 레시피 요약과 개인 버전 여부를 읽는다', () async {
    final repository = RecipeRepository(
      baseUrl: baseUrl,
      client: MockClient((request) async {
        expect(
          request.url.toString(),
          '$baseUrl/api/v1/recipes?page=0&size=10',
        );
        expect(request.headers[cookPilotUserIdHeader], userId);
        return _jsonResponse('''
          {
            "items": [
              {
                "id": "$recipeId",
                "title": "라면",
                "description": "기본 라면",
                "imageUrl": null,
                "hasPersonalVersion": true,
                "latestPersonalVersionId": "20000000-0000-0000-0000-000000000001",
                "favorite": true
              }
            ],
            "page": 0,
            "size": 10,
            "totalElements": 1,
            "hasNext": false
          }
        ''');
      }),
    );

    final recipes = await repository.findAll();

    expect(recipes, hasLength(1));
    expect(recipes.single.title, '라면');
    expect(recipes.single.imageUrl, isEmpty);
    expect(recipes.single.hasPersonalVersion, isTrue);
    expect(recipes.single.favorite, isTrue);
  });

  test('상세 응답에서 재료와 조리 단계를 화면 모델로 변환한다', () async {
    const summary = RecipeSummary(
      id: recipeId,
      title: '라면',
      description: '기본 라면',
      imageUrl: '',
      hasPersonalVersion: false,
      latestPersonalVersionId: null,
    );
    final repository = RecipeRepository(
      baseUrl: baseUrl,
      client: MockClient((request) async {
        expect(request.url.toString(), '$baseUrl/api/v1/recipes/$recipeId');
        return _jsonResponse('''
          {
            "id": "$recipeId",
            "title": "라면",
            "description": "기본 라면",
            "baseServings": 1.0,
            "imageUrl": null,
            "ingredients": [
              {
                "id": "11000000-0000-0000-0000-000000000001",
                "name": "물",
                "amount": 500.0,
                "unit": "ml",
                "required": true
              }
            ],
            "steps": [
              {
                "stepIndex": 0,
                "instruction": "물을 끓이세요.",
                "timerSeconds": 90,
                "cautionNote": "화상 주의",
                "imageUrl": null
              },
              {
                "stepIndex": 1,
                "instruction": "면을 넣으세요.",
                "timerSeconds": null,
                "cautionNote": null,
                "imageUrl": null
              }
            ]
          }
        ''');
      }),
    );

    final recipe = await repository.findById(summary);

    expect(recipe.id, recipeId);
    expect(recipe.baseServings, 1);
    expect(
      recipe.ingredients.single.originalIngredientId,
      '11000000-0000-0000-0000-000000000001',
    );
    expect(recipe.ingredients.single.amountLabel, '500ml');
    expect(recipe.steps, hasLength(2));
    expect(recipe.steps.first.timerDuration, const Duration(seconds: 90));
    expect(recipe.steps.first.minutes, 2);
    expect(recipe.steps.first.description, contains('화상 주의'));
    expect(recipe.timerMinutes, 2);
  });

  test('기본 재료 ID 누락은 Recipe 생성 전에 거부해 ADD 경로에 들어가지 않는다', () async {
    const summary = RecipeSummary(
      id: recipeId,
      title: '라면',
      description: '기본 라면',
      imageUrl: '',
      hasPersonalVersion: false,
      latestPersonalVersionId: null,
    );
    final missingIdBody = _baseRecipeJson.replaceFirst(
      '"id": "11000000-0000-0000-0000-000000000001", ',
      '',
    );
    final repository = RecipeRepository(
      baseUrl: baseUrl,
      client: MockClient((_) async => _jsonResponse(missingIdBody)),
    );

    await expectLater(
      repository.findById(summary),
      throwsA(
        isA<RecipeApiException>().having(
          (exception) => exception.message,
          'message',
          contains('재료 ID'),
        ),
      ),
    );
  });

  test('기본 재료 ID가 canonical UUID가 아니면 상세 응답을 거부한다', () async {
    const summary = RecipeSummary(
      id: recipeId,
      title: '라면',
      description: '기본 라면',
      imageUrl: '',
      hasPersonalVersion: false,
      latestPersonalVersionId: null,
    );
    final invalidBodies = <String>[
      _baseRecipeJson.replaceFirst('11000000-0000-0000-0000-000000000001', ''),
      _baseRecipeJson.replaceFirst(
        '11000000-0000-0000-0000-000000000001',
        'not-a-uuid',
      ),
      _baseRecipeJson.replaceFirst(
        '11000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000000',
      ),
      _baseRecipeJson.replaceFirst(
        '"id": "11000000-0000-0000-0000-000000000001"',
        '"id": 7',
      ),
    ];

    for (final body in invalidBodies) {
      final repository = RecipeRepository(
        baseUrl: baseUrl,
        client: MockClient((_) async => _jsonResponse(body)),
      );

      await expectLater(
        repository.findById(summary),
        throwsA(
          isA<RecipeApiException>().having(
            (exception) => exception.message,
            'message',
            contains('재료 ID'),
          ),
        ),
      );
    }
  });

  test('개인 버전 상세의 합성된 재료와 단계를 읽는다', () async {
    const versionId = '20000000-0000-0000-0000-000000000001';
    final repository = RecipeRepository(
      baseUrl: baseUrl,
      client: MockClient((request) async {
        expect(
          request.url.toString(),
          '$baseUrl/api/v1/personal-versions/$versionId',
        );
        expect(request.headers[cookPilotUserIdHeader], userId);
        return _jsonResponse('''
          {
            "version": {
              "id": "$versionId",
              "versionNumber": 2,
              "title": "덜 짠 라면 v2",
              "summary": "스프를 줄인 버전",
              "createdAt": "2026-07-26T01:00:00Z"
            },
            "ingredients": [
              {
                "originalIngredientId": "11000000-0000-0000-0000-000000000001",
                "name": "물",
                "amount": 550,
                "unit": "ml",
                "required": true,
                "origin": "MODIFIED"
              },
              {
                "originalIngredientId": null,
                "name": "치즈",
                "amount": 1,
                "unit": "장",
                "required": false,
                "origin": "ADDED"
              }
            ],
            "steps": [
              {
                "stepIndex": 0,
                "originalStepId": null,
                "instruction": "물을 끓이세요.",
                "timerSeconds": 90,
                "cautionNote": null,
                "origin": "ORIGINAL"
              }
            ],
            "ingredientAdjustments": [],
            "stepAdjustments": []
          }
        ''');
      }),
    );

    final version = await repository.findPersonalVersionDetail(versionId);

    expect(version.id, versionId);
    expect(version.versionNumber, 2);
    expect(version.title, '덜 짠 라면 v2');
    expect(version.summary, '스프를 줄인 버전');
    expect(version.ingredients, hasLength(2));
    expect(
      version.ingredients.first.originalIngredientId,
      '11000000-0000-0000-0000-000000000001',
    );
    expect(version.ingredients.first.amountLabel, '550ml');
    expect(version.ingredients.last.originalIngredientId, isNull);
    expect(version.ingredients.last.amountLabel, '1장');
    expect(version.steps.single.timerSeconds, 90);
  });

  test('개인 버전 ORIGINAL MODIFIED는 canonical ID가 필요하고 ADDED는 ID가 없어야 한다', () {
    final addedWithoutIdKey = _personalVersionIngredient(
      origin: 'ADDED',
      originalIngredientId: null,
    )..remove('originalIngredientId');
    final invalidIngredients = <Map<String, dynamic>>[
      addedWithoutIdKey,
      _personalVersionIngredient(
        origin: 'ORIGINAL',
        originalIngredientId: null,
      ),
      _personalVersionIngredient(
        origin: 'MODIFIED',
        originalIngredientId: null,
      ),
      _personalVersionIngredient(
        origin: 'ORIGINAL',
        originalIngredientId: 'not-a-uuid',
      ),
      _personalVersionIngredient(
        origin: 'MODIFIED',
        originalIngredientId: '00000000-0000-0000-0000-000000000000',
      ),
      _personalVersionIngredient(
        origin: 'ORIGINAL',
        originalIngredientId: '11000000-0000-0000-0000-00000000000A',
      ),
      _personalVersionIngredient(origin: 'MODIFIED', originalIngredientId: 7),
      _personalVersionIngredient(
        origin: 'ADDED',
        originalIngredientId: '11000000-0000-0000-0000-000000000001',
      ),
    ];

    for (final ingredient in invalidIngredients) {
      expect(
        () => PersonalRecipeVersionDetail.fromJson(
          _personalVersionDetailJson(ingredient),
        ),
        throwsA(
          isA<RecipeApiException>().having(
            (exception) => exception.message,
            'message',
            contains('재료 ID'),
          ),
        ),
        reason: '잘못된 origin/ID 조합: $ingredient',
      );
    }
  });

  test('개인 버전 재료 origin 누락 unknown 잘못된 타입은 fail closed한다', () {
    final missingOrigin = _personalVersionIngredient(
      origin: 'ORIGINAL',
      originalIngredientId: '11000000-0000-0000-0000-000000000001',
    )..remove('origin');
    final invalidIngredients = <Map<String, dynamic>>[
      missingOrigin,
      _personalVersionIngredient(
        origin: 'REMOVED',
        originalIngredientId: '11000000-0000-0000-0000-000000000001',
      ),
      _personalVersionIngredient(
        origin: 1,
        originalIngredientId: '11000000-0000-0000-0000-000000000001',
      ),
    ];

    for (final ingredient in invalidIngredients) {
      expect(
        () => PersonalRecipeVersionDetail.fromJson(
          _personalVersionDetailJson(ingredient),
        ),
        throwsA(
          isA<RecipeApiException>().having(
            (exception) => exception.message,
            'message',
            contains('origin'),
          ),
        ),
        reason: '잘못된 origin: $ingredient',
      );
    }
  });

  test('레시피의 최근 개인 버전 목록을 읽는다', () async {
    const versionId = '20000000-0000-0000-0000-000000000001';
    final repository = RecipeRepository(
      baseUrl: baseUrl,
      client: MockClient((request) async {
        expect(
          request.url.toString(),
          '$baseUrl/api/v1/recipes/$recipeId/personal-versions',
        );
        expect(request.headers[cookPilotUserIdHeader], userId);
        return _jsonResponse('''
          [
            {
              "id": "$versionId",
              "recipeId": "$recipeId",
              "versionNumber": 3,
              "title": "덜 짠 라면 v3",
              "summary": "스프 20% 감소",
              "createdAt": "2026-07-26T01:00:00Z"
            }
          ]
        ''');
      }),
    );

    final versions = await repository.findPersonalVersions(recipeId);

    expect(versions, hasLength(1));
    expect(versions.single.id, versionId);
    expect(versions.single.versionNumber, 3);
    expect(versions.single.summary, '스프 20% 감소');
  });

  test('개인 버전 배열의 항목 형식이 잘못되면 API 예외로 변환한다', () async {
    const versionId = '20000000-0000-0000-0000-000000000001';
    final repository = RecipeRepository(
      baseUrl: baseUrl,
      client: MockClient(
        (_) async => _jsonResponse('''
          {
            "version": {
              "id": "$versionId",
              "title": "잘못된 개인 버전",
              "summary": ""
            },
            "ingredients": ["잘못된 항목"],
            "steps": []
          }
        '''),
      ),
    );

    await expectLater(
      repository.findPersonalVersionDetail(versionId),
      throwsA(isA<RecipeApiException>()),
    );
  });

  test('상세 응답 ID가 요청한 레시피와 다르면 거부한다', () async {
    const summary = RecipeSummary(
      id: recipeId,
      title: '라면',
      description: '기본 라면',
      imageUrl: '',
      hasPersonalVersion: false,
      latestPersonalVersionId: null,
    );
    final repository = RecipeRepository(
      baseUrl: baseUrl,
      client: MockClient(
        (_) async => _jsonResponse('''
          {
            "id": "10000000-0000-0000-0000-000000000099",
            "title": "다른 레시피",
            "ingredients": [
              {
                "id": "11000000-0000-0000-0000-000000000001",
                "name": "물",
                "amount": 500,
                "unit": "ml",
                "required": true
              }
            ],
            "steps": [
              {
                "stepIndex": 0,
                "instruction": "물을 끓이세요.",
                "timerSeconds": 90,
                "cautionNote": null,
                "imageUrl": null
              }
            ]
          }
        '''),
      ),
    );

    await expectLater(
      repository.findById(summary),
      throwsA(
        isA<RecipeApiException>().having(
          (exception) => exception.message,
          'message',
          contains('다른 상세 응답'),
        ),
      ),
    );
  });

  test('세션 복원은 저장된 레시피 ID로 상세를 직접 조회한다', () async {
    final requestedPaths = <String>[];
    final repository = RecipeRepository(
      baseUrl: baseUrl,
      client: MockClient((request) async {
        requestedPaths.add(request.url.path);
        return _jsonResponse(_baseRecipeJson);
      }),
    );

    final recipe = await repository.findByRecipeId(recipeId);

    expect(requestedPaths, ['/api/v1/recipes/$recipeId']);
    expect(recipe.id, recipeId);
    expect(recipe.title, '라면');
  });

  test('서버 오류 상태는 RecipeApiException으로 전달한다', () async {
    final repository = RecipeRepository(
      baseUrl: baseUrl,
      client: MockClient((_) async => http.Response('error', 500)),
    );

    expect(repository.findAll(), throwsA(isA<RecipeApiException>()));
  });

  test('없는 레시피의 404 상태를 복원 정책이 구분할 수 있게 전달한다', () async {
    final repository = RecipeRepository(
      baseUrl: baseUrl,
      client: MockClient((_) async => http.Response('not found', 404)),
    );

    await expectLater(
      repository.findByRecipeId(recipeId),
      throwsA(
        isA<RecipeApiException>().having(
          (exception) => exception.statusCode,
          'statusCode',
          404,
        ),
      ),
    );
  });

  test('최근 조리와 즐겨찾기 목록의 메타데이터를 읽는다', () async {
    final repository = RecipeRepository(
      baseUrl: baseUrl,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/recent-recipes')) {
          return _jsonResponse('''
            [{
              "id": "$recipeId",
              "title": "라면",
              "description": "기본 라면",
              "imageUrl": null,
              "lastCookedAt": "2026-07-25T01:00:00Z",
              "lastRating": 5,
              "hasPersonalVersion": true,
              "latestPersonalVersionId": null
            }]
          ''');
        }
        return _jsonResponse('''
          [{
            "id": "$recipeId",
            "title": "라면",
            "description": "기본 라면",
            "imageUrl": null,
            "favoritedAt": "2026-07-25T02:00:00Z",
            "hasPersonalVersion": false,
            "latestPersonalVersionId": null
          }]
        ''');
      }),
    );

    final recent = await repository.findRecent();
    final favorites = await repository.findFavorites();

    expect(recent.single.lastRating, 5);
    expect(recent.single.lastCookedAt, isNotNull);
    expect(favorites.single.favorite, isTrue);
    expect(favorites.single.favoritedAt, isNotNull);
  });

  test('즐겨찾기 추가와 삭제는 각 HTTP 메서드를 사용한다', () async {
    final methods = <String>[];
    final repository = RecipeRepository(
      baseUrl: baseUrl,
      client: MockClient((request) async {
        methods.add(request.method);
        return http.Response('', request.method == 'PUT' ? 200 : 204);
      }),
    );

    await repository.addFavorite(recipeId);
    await repository.removeFavorite(recipeId);

    expect(methods, ['PUT', 'DELETE']);
  });

  test('즐겨찾기 요청의 연결 오류를 RecipeApiException으로 변환한다', () async {
    final repository = RecipeRepository(
      baseUrl: baseUrl,
      client: MockClient(
        (_) async => throw http.ClientException('connection failed'),
      ),
    );

    await expectLater(
      repository.addFavorite(recipeId),
      throwsA(
        isA<RecipeApiException>().having(
          (exception) => exception.message,
          'message',
          contains('연결'),
        ),
      ),
    );
  });

  test('즐겨찾기 요청의 시간 초과를 RecipeApiException으로 변환한다', () async {
    final repository = RecipeRepository(
      baseUrl: baseUrl,
      client: MockClient(
        (_) async => throw TimeoutException('request timed out'),
      ),
    );

    await expectLater(
      repository.removeFavorite(recipeId),
      throwsA(
        isA<RecipeApiException>().having(
          (exception) => exception.message,
          'message',
          contains('초과'),
        ),
      ),
    );
  });
}

http.Response _jsonResponse(String body) {
  return http.Response(
    body,
    200,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

const _baseRecipeJson = '''
  {
    "id": "10000000-0000-0000-0000-000000000001",
    "title": "라면",
    "description": "기본 라면",
    "baseServings": 1,
    "imageUrl": null,
    "ingredients": [
      {"id": "11000000-0000-0000-0000-000000000001", "name": "물", "amount": 500, "unit": "ml", "required": true}
    ],
    "steps": [
      {
        "stepIndex": 0,
        "instruction": "물을 끓이세요.",
        "timerSeconds": 90,
        "cautionNote": null,
        "imageUrl": null
      }
    ]
  }
''';

Map<String, dynamic> _personalVersionIngredient({
  required Object? origin,
  required Object? originalIngredientId,
}) => <String, dynamic>{
  'originalIngredientId': originalIngredientId,
  'name': '물',
  'amount': 500,
  'unit': 'ml',
  'required': true,
  'origin': origin,
};

Map<String, dynamic> _personalVersionDetailJson(
  Map<String, dynamic> ingredient,
) => <String, dynamic>{
  'version': <String, dynamic>{
    'id': '20000000-0000-0000-0000-000000000001',
    'versionNumber': 2,
    'title': '덜 짠 라면 v2',
    'summary': '스프를 줄인 버전',
    'createdAt': '2026-07-26T01:00:00Z',
  },
  'ingredients': <Object?>[ingredient],
  'steps': <Object?>[],
};
