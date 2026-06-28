import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

/// Провайдери AI для вкладки «AI».
enum AiProvider { anthropic, openai, gemini, custom }

extension AiProviderX on AiProvider {
  String get wire => name;

  static AiProvider fromWire(String? s) =>
      AiProvider.values.firstWhere((p) => p.name == s,
          orElse: () => AiProvider.anthropic);

  String get label => switch (this) {
        AiProvider.anthropic => 'Claude (Anthropic)',
        AiProvider.openai => 'ChatGPT (OpenAI)',
        AiProvider.gemini => 'Gemini (Google)',
        AiProvider.custom => 'OpenAI-сумісний (свій)',
      };

  String get defaultModel => suggestedModels.first;

  /// Поширені моделі для швидкого вибору (можна вписати й будь-яку свою).
  List<String> get suggestedModels => switch (this) {
        AiProvider.anthropic => const [
            'claude-opus-4-8',
            'claude-sonnet-4-6',
            'claude-haiku-4-5-20251001',
          ],
        AiProvider.openai => const ['gpt-4o', 'gpt-4o-mini', 'o3-mini'],
        AiProvider.gemini => const [
            'gemini-2.0-flash',
            'gemini-2.5-pro',
            'gemini-1.5-flash',
          ],
        AiProvider.custom => const ['llama3.1', 'qwen2.5', 'mistral'],
      };

  /// Де взяти ключ (підказка в налаштуваннях).
  String get keyHint => switch (this) {
        AiProvider.anthropic => 'console.anthropic.com → API keys',
        AiProvider.openai => 'platform.openai.com → API keys',
        AiProvider.gemini => 'aistudio.google.com → API key',
        AiProvider.custom => 'ключ вашого сервісу (OpenRouter, Groq, Ollama…)',
      };

  bool get needsBaseUrl => this == AiProvider.custom;
}

/// Системний промпт (мовно-нейтральний — відповідає мовою користувача).
const String aiSystemPrompt = '''
You are a VPS administration assistant inside the "VPS Admin" mobile app.
The user manages a Linux server (Ubuntu, Docker) from their phone over SSH.
Reply concisely, in the same language the user writes in.
When you suggest terminal actions, put EACH command in its own ```bash …``` block
so the app can show a "Run" button. Do not invent command output — the user will run
the command and paste the result. Warn explicitly before destructive actions
(rm, DROP, force push, restarting production).
''';

/// Уніфікований клієнт до різних AI-провайдерів.
class AiClient {
  final AiProvider provider;
  final String apiKey;
  final String model;
  final String? baseUrl; // лише для custom (має закінчуватись на /v1)

  AiClient({
    required this.provider,
    required this.apiKey,
    required this.model,
    this.baseUrl,
  });

  Future<String> send(List<ChatMessage> history) {
    switch (provider) {
      case AiProvider.anthropic:
        return _anthropic(history);
      case AiProvider.gemini:
        return _gemini(history);
      case AiProvider.openai:
      case AiProvider.custom:
        return _openai(history);
    }
  }

  // ── Anthropic (Claude) ───────────────────────────────────────────────
  Future<String> _anthropic(List<ChatMessage> history) async {
    final resp = await http.post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode({
        'model': model,
        'max_tokens': 2048,
        'system': aiSystemPrompt,
        'messages': history.map((m) => m.toApi()).toList(),
      }),
    );
    final j = _ok(resp, 'Anthropic');
    final content = j['content'] as List? ?? const [];
    final buf = StringBuffer();
    for (final block in content) {
      if (block is Map && block['type'] == 'text') {
        buf.write(block['text'] as String? ?? '');
      }
    }
    return _nonEmpty(buf.toString());
  }

  // ── OpenAI та OpenAI-сумісні ─────────────────────────────────────────
  Future<String> _openai(List<ChatMessage> history) async {
    final base = provider == AiProvider.custom
        ? (baseUrl ?? '').trim().replaceAll(RegExp(r'/+$'), '')
        : 'https://api.openai.com/v1';
    if (base.isEmpty) throw 'Не задано base URL для OpenAI-сумісного сервісу.';
    final messages = [
      {'role': 'system', 'content': aiSystemPrompt},
      ...history.map((m) => m.toApi()),
    ];
    final resp = await http.post(
      Uri.parse('$base/chat/completions'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({'model': model, 'messages': messages}),
    );
    final j = _ok(resp, provider == AiProvider.custom ? 'AI' : 'OpenAI');
    final choices = j['choices'] as List? ?? const [];
    if (choices.isEmpty) return _nonEmpty('');
    final msg = (choices.first as Map)['message'] as Map?;
    return _nonEmpty(msg?['content'] as String? ?? '');
  }

  // ── Google Gemini ────────────────────────────────────────────────────
  Future<String> _gemini(List<ChatMessage> history) async {
    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey');
    final contents = history
        .map((m) => {
              'role': m.role == 'assistant' ? 'model' : 'user',
              'parts': [
                {'text': m.text}
              ],
            })
        .toList();
    final resp = await http.post(
      uri,
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'system_instruction': {
          'parts': [
            {'text': aiSystemPrompt}
          ]
        },
        'contents': contents,
      }),
    );
    final j = _ok(resp, 'Gemini');
    final cands = j['candidates'] as List? ?? const [];
    if (cands.isEmpty) return _nonEmpty('');
    final parts =
        ((cands.first as Map)['content'] as Map?)?['parts'] as List? ?? const [];
    final buf = StringBuffer();
    for (final p in parts) {
      if (p is Map) buf.write(p['text'] as String? ?? '');
    }
    return _nonEmpty(buf.toString());
  }

  // ── helpers ──────────────────────────────────────────────────────────
  Map<String, dynamic> _ok(http.Response resp, String name) {
    if (resp.statusCode != 200) {
      final body = utf8.decode(resp.bodyBytes);
      String detail = body;
      try {
        final j = jsonDecode(body);
        detail = (j['error']?['message'] as String?) ??
            (j['error']?.toString()) ??
            body;
      } catch (_) {}
      if (detail.length > 300) detail = detail.substring(0, 300);
      throw '$name ${resp.statusCode}: $detail';
    }
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  String _nonEmpty(String s) {
    final t = s.trim();
    return t.isEmpty ? '(порожня відповідь)' : t;
  }
}

/// Витягти ```bash / ```sh / ``` блоки — кандидати на виконання по SSH.
List<String> extractCommands(String markdown) {
  final re = RegExp(r'```(?:bash|sh|shell|console)?\n([\s\S]*?)```',
      multiLine: true);
  final out = <String>[];
  for (final m in re.allMatches(markdown)) {
    final code = m.group(1)?.trim() ?? '';
    if (code.isNotEmpty) out.add(code);
  }
  return out;
}
