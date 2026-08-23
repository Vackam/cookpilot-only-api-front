import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api/api_config.dart';

const cookPilotUserIdHeader = 'X-CookPilot-User-Id';
const anonymousUserIdempotencyHeader = 'Idempotency-Key';

const _userIdStorageKey = 'cookpilot_beta_user_id';
const _installationIdStorageKey = 'cookpilot_beta_installation_id';

class BetaUser {
  const BetaUser({
    required this.id,
    required this.displayName,
    required this.betaNumber,
  });

  factory BetaUser.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final displayName = json['displayName'];
    final betaNumber = json['betaNumber'];
    if (id is! String || !_isUuid(id) || displayName is! String) {
      throw const BetaUserException('사용자 발급 응답 형식이 올바르지 않습니다.');
    }
    return BetaUser(
      id: id,
      displayName: displayName,
      // 테스트 서버의 관리자 로그인 응답에는 betaNumber가 없다 — 표시용
      // 값이라 없으면 0으로 둔다.
      betaNumber: betaNumber is num ? betaNumber.toInt() : 0,
    );
  }

  final String id;
  final String displayName;
  final int betaNumber;
}

class BetaUserException implements Exception {
  const BetaUserException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BetaUserSession {
  static BetaUser? _currentUser;

  static BetaUser? get currentUser => _currentUser;
  static String? get userId => _currentUser?.id;

  static Map<String, String> get requestHeaders {
    final id = userId;
    if (id == null) {
      throw const BetaUserException('베타 사용자 세션이 준비되지 않았습니다.');
    }
    return {cookPilotUserIdHeader: id};
  }

  static void setCurrentUser(BetaUser user) {
    _currentUser = user;
  }

  static void clear() {
    _currentUser = null;
  }
}

abstract interface class BetaUserStorage {
  Future<String?> readUserId();

  Future<bool> writeUserId(String userId);

  Future<String?> readInstallationId();

  Future<bool> writeInstallationId(String installationId);
}

class SharedPreferencesBetaUserStorage implements BetaUserStorage {
  const SharedPreferencesBetaUserStorage();

  Future<SharedPreferences> _preferences() => SharedPreferences.getInstance();

  @override
  Future<String?> readUserId() async {
    return (await _preferences()).getString(_userIdStorageKey);
  }

  @override
  Future<bool> writeUserId(String userId) async {
    return (await _preferences()).setString(_userIdStorageKey, userId);
  }

  @override
  Future<String?> readInstallationId() async {
    return (await _preferences()).getString(_installationIdStorageKey);
  }

  @override
  Future<bool> writeInstallationId(String installationId) async {
    return (await _preferences()).setString(
      _installationIdStorageKey,
      installationId,
    );
  }
}

class BetaUserRepository {
  BetaUserRepository({
    http.Client? client,
    String? baseUrl,
    BetaUserStorage? storage,
    this.requestTimeout = const Duration(seconds: 8),
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? cookPilotApiBaseUrl(),
       _storage = storage ?? const SharedPreferencesBetaUserStorage();

  static Future<BetaUser>? _pendingUser;

  final http.Client _client;
  final String _baseUrl;
  final BetaUserStorage _storage;
  final Duration requestTimeout;

  Future<BetaUser> ensureUser() {
    final current = BetaUserSession.currentUser;
    if (current != null) return Future.value(current);

    final pending = _pendingUser;
    if (pending != null) return pending;

    late final Future<BetaUser> request;
    request = _ensureUser().whenComplete(() {
      if (identical(_pendingUser, request)) {
        _pendingUser = null;
      }
    });
    _pendingUser = request;
    return request;
  }

  Future<BetaUser> _ensureUser() async {
    final savedId = await _storage.readUserId();
    if (savedId != null && _isUuid(savedId)) {
      final savedUser = await _findSavedUser(savedId);
      if (savedUser != null) {
        BetaUserSession.setCurrentUser(savedUser);
        return savedUser;
      }
    }

    final installationId = await _ensureInstallationId();
    final createdUser = await _createAnonymousUser(installationId);
    final persisted = await _storage.writeUserId(createdUser.id);
    if (!persisted) {
      throw const BetaUserException('사용자 정보를 기기에 저장하지 못했습니다.');
    }
    BetaUserSession.setCurrentUser(createdUser);
    return createdUser;
  }

  /// 테스트 서버용 관리자 로그인. 성공하면 익명 발급과 같은 저장·세션 흐름을
  /// 타므로 이후 API 호출은 전부 이 계정으로 나간다 — 재설치해도 같은 계정.
  Future<BetaUser> loginAsAdmin({
    required String email,
    required String password,
  }) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/api/v1/users/admin-login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(requestTimeout);

    // 백엔드는 자격 불일치를 404로 숨긴다(docs/feat-admin-login.md).
    if (response.statusCode == 404) {
      throw const BetaUserException('이메일 또는 비밀번호가 올바르지 않습니다.');
    }
    if (response.statusCode != 200) {
      throw BetaUserException('로그인에 실패했습니다. (${response.statusCode})');
    }
    final user = _decodeUser(response.body);
    final persisted = await _storage.writeUserId(user.id);
    if (!persisted) {
      throw const BetaUserException('사용자 정보를 기기에 저장하지 못했습니다.');
    }
    BetaUserSession.setCurrentUser(user);
    return user;
  }

  Future<String> _ensureInstallationId() async {
    final savedId = await _storage.readInstallationId();
    if (savedId != null && _isUuid(savedId)) {
      return savedId;
    }

    final installationId = _generateUuidV4();
    final persisted = await _storage.writeInstallationId(installationId);
    if (!persisted) {
      throw const BetaUserException('기기 식별 정보를 저장하지 못했습니다.');
    }
    return installationId;
  }

  Future<BetaUser?> _findSavedUser(String userId) async {
    final response = await _client
        .get(
          Uri.parse('$_baseUrl/api/v1/users/me'),
          headers: {cookPilotUserIdHeader: userId},
        )
        .timeout(requestTimeout);

    if (_isUserNotFoundResponse(response)) return null;
    if (response.statusCode != 200) {
      throw BetaUserException(
        '저장된 사용자 정보를 확인하지 못했습니다. (${response.statusCode})',
      );
    }
    return _decodeUser(response.body);
  }

  Future<BetaUser> _createAnonymousUser(String installationId) async {
    final response = await _client
        .post(
          Uri.parse('$_baseUrl/api/v1/users/anonymous'),
          headers: {anonymousUserIdempotencyHeader: installationId},
        )
        .timeout(requestTimeout);

    if (response.statusCode != 201) {
      throw BetaUserException('베타 사용자 발급에 실패했습니다. (${response.statusCode})');
    }
    return _decodeUser(response.body);
  }

  BetaUser _decodeUser(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const BetaUserException('사용자 발급 응답 형식이 올바르지 않습니다.');
    }
    return BetaUser.fromJson(decoded);
  }

  bool _isUserNotFoundResponse(http.Response response) {
    if (response.statusCode != 404) {
      return false;
    }
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> &&
          decoded['code'] == 'USER_NOT_FOUND';
    } on FormatException {
      return false;
    }
  }

  String _generateUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

bool _isUuid(String value) {
  return RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
}
