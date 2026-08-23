import 'dart:async';

import 'package:elevenlabs_agents/elevenlabs_agents.dart';

import '../application/cooking_coach_controller.dart';

/// ElevenLabs Agents로 붙는 코치 엔진(PoC). 마이크·재생·에코 캔슬·음성
/// barge-in을 SDK(WebRTC/LiveKit)가 전부 처리하므로 오디오 포트가 없고,
/// [interrupt]도 no-op이다 — 말하는 도중 목소리로 끊는 게 기본 동작이다.
///
/// 에이전트가 호출하는 client tool 하나의 실행부. 수행 결과를 사용자에게
/// 읽어줄 한국어 문장으로 반환하면 도구 응답으로 에이전트에 전달된다.
typedef CoachToolHandler = String Function(Map<String, dynamic> args);

/// 세션에서 확정된 발화 한 턴. 사용자 발화는 SDK가 전사한 텍스트다.
typedef CoachTranscriptHandler =
    void Function(String text, {required bool isUser});

/// 레시피 컨텍스트는 dynamic variable(`recipe_context`)로 넣는다. 대시보드
/// 에이전트의 시스템 프롬프트가 `{{recipe_context}}`여야 한다(docs 참고).
final class ElevenLabsCoachController implements CookingCoachEngine {
  ElevenLabsCoachController({
    required this.fetchConversationToken,
    required this.buildRecipePrompt,
    required this.onStateChanged,
    this.onTranscriptTurn,
    this.toolHandlers = const {},
    ConversationClient Function(
      ConversationCallbacks callbacks,
      Map<String, ClientTool> clientTools,
    )?
    clientFactory,
  }) : _clientFactory =
           clientFactory ??
           ((callbacks, clientTools) => ConversationClient(
             callbacks: callbacks,
             clientTools: clientTools,
           ));

  /// 백엔드에서 conversation token을 발급받는다. 에이전트는 private이라 이 토큰
  /// 없이는 연결할 수 없다 — API 키·agent ID는 서버에만 있다.
  final Future<String> Function() fetchConversationToken;

  /// 이번 요리의 재료·단계 전문을 담은 시스템 프롬프트를 만든다.
  final String Function() buildRecipePrompt;
  final CookingCoachStateHandler onStateChanged;

  /// 세션이 살아 있는 동안의 발화를 화면에 넘긴다. 코치를 껐다 켜면 SDK
  /// 세션이 0턴에서 시작하므로, 이어붙일 대화를 앱이 들고 있어야 한다.
  final CoachTranscriptHandler? onTranscriptTurn;

  /// 대시보드에 정의한 client tool 이름 → 실행부. 이름이 정확히 일치해야
  /// 호출이 도착한다(docs의 대시보드 설정 참고).
  final Map<String, CoachToolHandler> toolHandlers;

  final ConversationClient Function(
    ConversationCallbacks callbacks,
    Map<String, ClientTool> clientTools,
  )
  _clientFactory;

  CookingCoachPhase _phase = CookingCoachPhase.idle;
  ConversationClient? _client;
  int _generation = 0;
  bool _disposed = false;

  @override
  CookingCoachPhase get phase => _phase;

  @override
  bool get isActive => _phase != CookingCoachPhase.idle;

  @override
  Future<void> start(String recipeId) async {
    if (_disposed || _phase != CookingCoachPhase.idle) {
      return;
    }
    final generation = ++_generation;
    _emit(CookingCoachPhase.connecting, 'AI 코치를 연결하고 있어요.');

    final client = _clientFactory(
      ConversationCallbacks(
        onDisconnect: (details) {
          if (_isCurrent(generation) && _phase != CookingCoachPhase.stopping) {
            unawaited(_teardown(generation, message: '코치 연결이 끝났어요.'));
          }
        },
        onMessage: ({required message, required source}) {
          if (_isCurrent(generation)) {
            onTranscriptTurn?.call(message, isUser: source == Role.user);
          }
        },
        onError: (message, [context]) {
          if (_isCurrent(generation)) {
            unawaited(_teardown(generation, message: 'AI 코치 연결에 문제가 생겼어요.'));
          }
        },
      ),
      {
        for (final entry in toolHandlers.entries)
          entry.key: _HandlerClientTool(entry.value),
      },
    );
    _client = client;

    try {
      // prompt override 대신 dynamic variable로 주입한다. SDK 0.6.1이
      // prompt override를 API 규격(객체)이 아닌 문자열로 보내 서버가
      // 세션을 거절하는 버그가 있다(1008 validation error 실측).
      // 대시보드 에이전트의 시스템 프롬프트가 {{recipe_context}}여야 한다.
      final conversationToken = await fetchConversationToken();
      if (!_isCurrent(generation)) {
        return;
      }
      await client.startSession(
        conversationToken: conversationToken,
        dynamicVariables: {'recipe_context': buildRecipePrompt()},
      );
      if (!_isCurrent(generation)) {
        return;
      }
      _emit(CookingCoachPhase.live, '코치가 듣고 있어요. 말하는 중에 끼어들어도 돼요.');
    } catch (_) {
      if (_isCurrent(generation)) {
        await _teardown(generation, message: 'AI 코치를 시작하지 못했어요.');
      }
    }
  }

  /// 음성 barge-in이 SDK에 내장돼 있어 탭 가로채기가 필요 없다.
  @override
  void interrupt() {}

  /// 단계 이동 같은 진행 상황을 대화 흐름을 끊지 않고 에이전트에 주입한다.
  @override
  void updateContext(String text) {
    if (_phase != CookingCoachPhase.live) {
      return;
    }
    _client?.sendContextualUpdate(text);
  }

  @override
  Future<void> stop() async {
    if (_phase == CookingCoachPhase.idle ||
        _phase == CookingCoachPhase.stopping) {
      return;
    }
    final generation = _generation;
    _emit(CookingCoachPhase.stopping, null);
    await _teardown(generation, message: 'AI 코치를 껐어요.');
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _generation++;
    final client = _client;
    _client = null;
    if (client != null) {
      unawaited(_swallow(client.endSession));
    }
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  Future<void> _teardown(int generation, {String? message}) async {
    if (!_isCurrent(generation)) {
      return;
    }
    _generation++;
    final client = _client;
    _client = null;
    if (client != null) {
      await _swallow(client.endSession);
    }
    if (!_disposed) {
      _emit(CookingCoachPhase.idle, message);
    }
  }

  Future<void> _swallow(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // 정리 실패가 화면 흐름을 막지 않게 한다.
    }
  }

  void _emit(CookingCoachPhase phase, String? message) {
    if (_disposed) {
      return;
    }
    _phase = phase;
    onStateChanged(phase, message);
  }
}

/// [CoachToolHandler]를 SDK의 [ClientTool]로 감싼다. 결과 문장을 도구
/// 응답으로 돌려줘 에이전트가 수행 결과를 음성으로 안내하게 한다.
final class _HandlerClientTool implements ClientTool {
  _HandlerClientTool(this._handler);

  final CoachToolHandler _handler;

  @override
  Future<ClientToolResult?> execute(Map<String, dynamic> parameters) async {
    try {
      return ClientToolResult.success({'message': _handler(parameters)});
    } catch (error) {
      return ClientToolResult.failure('$error');
    }
  }
}
