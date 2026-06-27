import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

/// Тонкий клієнт Anthropic Claude API (Messages).
/// Ключ ANTHROPIC_API_KEY вводиться в налаштуваннях і лежить у secure storage.
class ClaudeService {
  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _version = '2023-06-01';

  /// Системний промпт: AI може пропонувати команди у ```bash блоках,
  /// які користувач потім (з підтвердженням) виконує по SSH.
  static const systemPrompt = '''
Ти — асистент-адміністратор VPS усередині мобільного додатка «VPS Admin».
Користувач керує Linux-сервером (Ubuntu, Docker, Odoo) з телефона по SSH.
Відповідай українською, стисло й по суті.
Коли пропонуєш дії в терміналі — давай КОЖНУ команду окремим блоком ```bash …```,
щоб додаток показав кнопку «Виконати». Не вигадуй вивід команд — його дасть користувач,
виконавши команду. Перед деструктивними діями (rm, DROP, force push, pg_dump на prod,
рестарт prod) — явно попереджай.
''';

  final String apiKey;
  final String model;

  ClaudeService({required this.apiKey, required this.model});

  /// Надіслати історію діалогу й отримати відповідь асистента.
  Future<String> send(List<ChatMessage> history) async {
    final resp = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': _version,
      },
      body: jsonEncode({
        'model': model,
        'max_tokens': 2048,
        'system': systemPrompt,
        'messages': history.map((m) => m.toApi()).toList(),
      }),
    );

    if (resp.statusCode != 200) {
      final body = utf8.decode(resp.bodyBytes);
      String detail = body;
      try {
        final j = jsonDecode(body) as Map<String, dynamic>;
        detail = (j['error']?['message'] as String?) ?? body;
      } catch (_) {}
      throw 'Claude API ${resp.statusCode}: $detail';
    }

    final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final content = j['content'] as List? ?? const [];
    final buf = StringBuffer();
    for (final block in content) {
      if (block is Map && block['type'] == 'text') {
        buf.write(block['text'] as String? ?? '');
      }
    }
    final text = buf.toString().trim();
    return text.isEmpty ? '(порожня відповідь)' : text;
  }
}

/// Витягти ```bash / ```sh / ``` блоки з тексту відповіді — кандидати на виконання.
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
