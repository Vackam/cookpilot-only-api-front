import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/api/api_config.dart';
import '../../user/data/beta_user_repository.dart';
import '../domain/recipe.dart';

class RecipeSummary {
  const RecipeSummary({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.hasPersonalVersion,
    required this.latestPersonalVersionId,
    this.favorite = false,
    this.lastCookedAt,
    this.lastRating,
    this.favoritedAt,
    this.cookingMethod,
    this.dishType,
    this.hashtags = const [],
  });

  factory RecipeSummary.fromJson(Map<String, dynamic> json) {
    return RecipeSummary(
      id: _requiredString(json, 'id'),
      title: _requiredString(json, 'title'),
      description: json['description'] as String? ?? '',
      imageUrl: json['imageUrl'] as String? ?? '',
      hasPersonalVersion: json['hasPersonalVersion'] as bool? ?? false,
      latestPersonalVersionId: json['latestPersonalVersionId'] as String?,
      favorite: json['favorite'] as bool? ?? json['favoritedAt'] != null,
      lastCookedAt: _optionalDateTime(json['lastCookedAt']),
      lastRating: (json['lastRating'] as num?)?.toInt(),
      favoritedAt: _optionalDateTime(json['favoritedAt']),
      cookingMethod: json['cookingMethod'] as String?,
      dishType: json['dishType'] as String?,
      hashtags: _stringList(json['hashtags']),
    );
  }

  final String id;
  final String title;
  final String description;
  final String imageUrl;
  final bool hasPersonalVersion;
  final String? latestPersonalVersionId;
  final bool favorite;
  final DateTime? lastCookedAt;
  final int? lastRating;
  final DateTime? favoritedAt;

  /// 끓이기·굽기·볶기·찌기·튀기기 중 하나. 서버가 '기타'는 null로 준다.
  final String? cookingMethod;

  /// 반찬·일품·후식·밥·국·찌개 중 하나. 서버가 '기타'는 null로 준다.
  final String? dishType;

  final List<String> hashtags;

  /// 칩으로 그릴 순서. 분류가 앞, 해시태그가 뒤.
  List<String> get tagLabels => [?dishType, ?cookingMethod, ...hashtags];
}

class RecipePage {
  const RecipePage({
    required this.items,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.hasNext,
  });

  factory RecipePage.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'];
    if (itemsJson is! List ||
        itemsJson.any((item) => item is! Map<String, dynamic>)) {
      throw const RecipeApiException('레시피 목록 응답 형식이 올바르지 않습니다.');
    }

    return RecipePage(
      items: itemsJson
          .map((item) => RecipeSummary.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      page: _requiredInt(json, 'page'),
      size: _requiredInt(json, 'size'),
      totalElements: _requiredInt(json, 'totalElements'),
      hasNext: json['hasNext'] as bool? ?? false,
    );
  }

  final List<RecipeSummary> items;

  /// 0부터 센다. 서버 계약이 그렇다 — 화면에 보여줄 때만 +1 한다.
  final int page;
  final int size;
  final int totalElements;
  final bool hasNext;

  /// 마지막 페이지 번호+1. 결과가 없으면 0.
  int get totalPages => size <= 0 ? 0 : (totalElements + size - 1) ~/ size;
}

class PersonalRecipeVersionSummary {
  const PersonalRecipeVersionSummary({
    required this.id,
    required this.recipeId,
    required this.versionNumber,
    required this.title,
    required this.summary,
    required this.createdAt,
  });

  factory PersonalRecipeVersionSummary.fromJson(Map<String, dynamic> json) {
    return PersonalRecipeVersionSummary(
      id: _requiredString(json, 'id'),
      recipeId: _requiredString(json, 'recipeId'),
      versionNumber: _requiredInt(json, 'versionNumber'),
      title: _requiredString(json, 'title'),
      summary: _optionalString(json, 'summary'),
      createdAt: _requiredDateTime(json, 'createdAt'),
    );
  }

  final String id;
  final String recipeId;
  final int versionNumber;
  final String title;
  final String summary;
  final DateTime createdAt;
}

class PersonalRecipeVersionDetail {
  const PersonalRecipeVersionDetail({
    required this.id,
    required this.versionNumber,
    required this.title,
    required this.summary,
    required this.createdAt,
    required this.ingredients,
    required this.steps,
  });

  factory PersonalRecipeVersionDetail.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    final ingredientsJson = json['ingredients'];
    final stepsJson = json['steps'];
    if (version is! Map<String, dynamic> ||
        ingredientsJson is! List ||
        stepsJson is! List) {
      throw const RecipeApiException('개인 레시피 응답 형식이 올바르지 않습니다.');
    }
    if (ingredientsJson.any((item) => item is! Map<String, dynamic>) ||
        stepsJson.any((item) => item is! Map<String, dynamic>)) {
      throw const RecipeApiException('개인 레시피 항목 형식이 올바르지 않습니다.');
    }

    return PersonalRecipeVersionDetail(
      id: _requiredString(version, 'id'),
      versionNumber: _requiredInt(version, 'versionNumber'),
      title: _requiredString(version, 'title'),
      summary: _optionalString(version, 'summary'),
      createdAt: _requiredDateTime(version, 'createdAt'),
      ingredients: ingredientsJson
          .map(
            (item) => _personalVersionIngredientFromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(growable: false),
      steps: stepsJson
          .map((item) => _stepFromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  final String id;
  final int versionNumber;
  final String title;
  final String summary;
  final DateTime createdAt;
  final List<Ingredient> ingredients;
  final List<CookStep> steps;
}

/// 서버가 태그를 안 실어 주면(구버전) 빈 목록으로 떨어진다.
List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}

class RecipeApiException implements Exception {
  const RecipeApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class RecipeRepository {
  RecipeRepository({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? cookPilotApiBaseUrl();

  final http.Client _client;
  final String _baseUrl;

  /// 전체 레시피는 서버가 페이지 단위로 내려준다.
  Future<List<RecipeSummary>> findAll({int page = 0, int size = 10}) async {
    final result = await _findPage('/api/v1/recipes?page=$page&size=$size');
    return result.items;
  }

  /// 서버 검색. 조건이 비면 전체 카탈로그를 페이지로 훑는다.
  ///
  /// `title`과 `ingredient`를 함께 주면 둘 다 만족하는 결과만 온다(AND).
  /// [size] 상한은 서버와 같은 100 — 넘기면 400이 온다.
  Future<RecipePage> search({
    String title = '',
    String ingredient = '',
    int page = 0,
    int size = 9,
  }) async {
    final query = Uri(
      queryParameters: {
        'title': title.trim(),
        'ingredient': ingredient.trim(),
        'page': '$page',
        'size': '$size',
      },
    ).query;
    return _findPage('/api/v1/recipes/search?$query');
  }

  Future<RecipePage> _findPage(String path) async {
    final response = await _get(path);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const RecipeApiException('레시피 목록 응답 형식이 올바르지 않습니다.');
    }
    return RecipePage.fromJson(decoded);
  }

  Future<List<RecipeSummary>> findRecent() async {
    return _findSummaries('/api/v1/home/recent-recipes');
  }

  Future<List<RecipeSummary>> findFavorites() async {
    return _findSummaries('/api/v1/favorites');
  }

  Future<PersonalRecipeVersionDetail> findPersonalVersionDetail(
    String versionId,
  ) async {
    final response = await _get('/api/v1/personal-versions/$versionId');
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const RecipeApiException('개인 레시피 응답 형식이 올바르지 않습니다.');
    }
    return PersonalRecipeVersionDetail.fromJson(decoded);
  }

  Future<List<PersonalRecipeVersionSummary>> findPersonalVersions(
    String recipeId,
  ) async {
    final response = await _get('/api/v1/recipes/$recipeId/personal-versions');
    final decoded = jsonDecode(response.body);
    if (decoded is! List ||
        decoded.any((item) => item is! Map<String, dynamic>)) {
      throw const RecipeApiException('개인 레시피 목록 응답 형식이 올바르지 않습니다.');
    }
    return decoded
        .map(
          (item) => PersonalRecipeVersionSummary.fromJson(
            item as Map<String, dynamic>,
          ),
        )
        .toList(growable: false);
  }

  Future<void> addFavorite(String recipeId) async {
    await _request('PUT', '/api/v1/recipes/$recipeId/favorite', {200});
  }

  Future<void> removeFavorite(String recipeId) async {
    await _request('DELETE', '/api/v1/recipes/$recipeId/favorite', {204});
  }

  Future<List<RecipeSummary>> _findSummaries(String path) async {
    final response = await _get(path);
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const RecipeApiException('레시피 목록 응답 형식이 올바르지 않습니다.');
    }

    return decoded
        .map((item) => RecipeSummary.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Recipe> findByRecipeId(String recipeId) {
    return findById(
      RecipeSummary(
        id: recipeId,
        title: '',
        description: '',
        imageUrl: '',
        hasPersonalVersion: false,
        latestPersonalVersionId: null,
      ),
    );
  }

  Future<Recipe> findById(RecipeSummary summary) async {
    final response = await _get('/api/v1/recipes/${summary.id}');
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const RecipeApiException('레시피 상세 응답 형식이 올바르지 않습니다.');
    }

    final ingredientsJson = decoded['ingredients'];
    final stepsJson = decoded['steps'];
    if (ingredientsJson is! List || stepsJson is! List) {
      throw const RecipeApiException('레시피 재료 또는 조리 단계가 없습니다.');
    }

    final responseId = _requiredString(decoded, 'id');
    if (responseId != summary.id) {
      throw const RecipeApiException('요청한 레시피와 다른 상세 응답을 받았습니다.');
    }

    final ingredients = ingredientsJson
        .map(
          (item) => _ingredientFromJson(
            item as Map<String, dynamic>,
            requireOriginalIngredientId: true,
          ),
        )
        .toList(growable: false);
    final steps = stepsJson
        .map((item) => _stepFromJson(item as Map<String, dynamic>))
        .toList(growable: false);

    return Recipe(
      id: responseId,
      title: _requiredString(decoded, 'title'),
      description: decoded['description'] as String? ?? '',
      baseServings: (decoded['baseServings'] as num?)?.toDouble() ?? 1,
      imageUrl: decoded['imageUrl'] as String? ?? '',
      ingredients: ingredients,
      steps: steps,
      hasPersonalVersion: summary.hasPersonalVersion,
      latestPersonalVersionId: summary.latestPersonalVersionId,
      favorite: summary.favorite,
      cookingMethod: decoded['cookingMethod'] as String?,
      dishType: decoded['dishType'] as String?,
      hashtags: _stringList(decoded['hashtags']),
    );
  }

  Future<http.Response> _get(String path) async {
    return _translateTransportErrors(() async {
      final uri = Uri.parse('$_baseUrl$path');
      final response = await _client
          .get(uri, headers: BetaUserSession.requestHeaders)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw RecipeApiException(
          '서버 요청에 실패했습니다. (${response.statusCode})',
          statusCode: response.statusCode,
        );
      }
      return response;
    });
  }

  Future<http.Response> _request(
    String method,
    String path,
    Set<int> successCodes,
  ) async {
    return _translateTransportErrors(() async {
      final uri = Uri.parse('$_baseUrl$path');
      final request = http.Request(method, uri);
      request.headers.addAll(BetaUserSession.requestHeaders);
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 8));
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(const Duration(seconds: 8));
      if (!successCodes.contains(response.statusCode)) {
        throw RecipeApiException('서버 요청에 실패했습니다. (${response.statusCode})');
      }
      return response;
    });
  }

  Future<T> _translateTransportErrors<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on TimeoutException {
      throw const RecipeApiException('서버 응답 시간이 초과되었습니다.');
    } on http.ClientException {
      throw const RecipeApiException('서버에 연결하지 못했습니다.');
    }
  }
}

Ingredient _ingredientFromJson(
  Map<String, dynamic> json, {
  bool requireOriginalIngredientId = false,
}) {
  return _ingredientFromJsonWithId(
    json,
    _ingredientIdFromJson(json, required: requireOriginalIngredientId),
  );
}

Ingredient _personalVersionIngredientFromJson(Map<String, dynamic> json) {
  final origin = _personalVersionIngredientOriginFromJson(json);
  if (!json.containsKey('originalIngredientId')) {
    throw const RecipeApiException('개인 버전 재료 ID가 없습니다.');
  }
  final value = json['originalIngredientId'];
  final String? originalIngredientId;
  if (origin == _PersonalVersionIngredientOrigin.added) {
    if (value != null) {
      throw const RecipeApiException('ADDED 개인 버전 재료 ID는 null이어야 합니다.');
    }
    originalIngredientId = null;
  } else {
    if (value is! String ||
        !_canonicalUuidPattern.hasMatch(value) ||
        value == _nilUuid) {
      throw const RecipeApiException('개인 버전 원본 재료 ID 형식이 올바르지 않습니다.');
    }
    originalIngredientId = value;
  }
  return _ingredientFromJsonWithId(json, originalIngredientId);
}

Ingredient _ingredientFromJsonWithId(
  Map<String, dynamic> json,
  String? originalIngredientId,
) {
  final amount = json['amount'];
  final unit = json['unit'] as String? ?? '';
  return Ingredient(
    originalIngredientId: originalIngredientId,
    name: _requiredString(json, 'name'),
    amount: (amount as num?)?.toDouble(),
    unit: unit,
    isRequired: json['required'] as bool? ?? false,
  );
}

String? _ingredientIdFromJson(
  Map<String, dynamic> json, {
  required bool required,
}) {
  final value = json['id'] ?? json['originalIngredientId'];
  if (value == null) {
    if (required) {
      throw const RecipeApiException('기본 레시피 재료 ID가 없습니다.');
    }
    return null;
  }
  if (value is! String ||
      !_canonicalUuidPattern.hasMatch(value) ||
      value == _nilUuid) {
    throw const RecipeApiException('레시피 재료 ID 형식이 올바르지 않습니다.');
  }
  return value;
}

enum _PersonalVersionIngredientOrigin { original, modified, added }

_PersonalVersionIngredientOrigin _personalVersionIngredientOriginFromJson(
  Map<String, dynamic> json,
) {
  return switch (json['origin']) {
    'ORIGINAL' => _PersonalVersionIngredientOrigin.original,
    'MODIFIED' => _PersonalVersionIngredientOrigin.modified,
    'ADDED' => _PersonalVersionIngredientOrigin.added,
    _ => throw const RecipeApiException('개인 버전 재료 origin 형식이 올바르지 않습니다.'),
  };
}

CookStep _stepFromJson(Map<String, dynamic> json) {
  final stepIndex = (json['stepIndex'] as num?)?.toInt() ?? 0;
  final seconds = (json['timerSeconds'] as num?)?.toInt() ?? 0;
  final caution = json['cautionNote'] as String?;
  final instruction = _requiredString(json, 'instruction');
  return CookStep(
    originalStepId: json['id'] as String? ?? json['originalStepId'] as String?,
    stepIndex: stepIndex,
    instruction: instruction,
    timerSeconds: json['timerSeconds'] == null ? null : seconds,
    cautionNote: caution,
    imageUrl: json['imageUrl'] as String? ?? '',
  );
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw RecipeApiException('$key 값이 없습니다.');
  }
  return value;
}

String _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return '';
  if (value is! String) {
    throw RecipeApiException('$key 형식이 올바르지 않습니다.');
  }
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num) {
    throw RecipeApiException('$key 값이 없습니다.');
  }
  return value.toInt();
}

DateTime? _optionalDateTime(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value);
}

DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
  final value = _optionalDateTime(json[key]);
  if (value == null) {
    throw RecipeApiException('$key 값이 없습니다.');
  }
  return value;
}

final _canonicalUuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-'
  r'[0-9a-f]{4}-[0-9a-f]{12}$',
);

const _nilUuid = '00000000-0000-0000-0000-000000000000';
