import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// Обгортка shell-каналу Терміналу, яка після закриття каналу не пускає
/// в нього вже нічого: ні введення, ні зміну розміру, ні повторне закриття.
///
/// Чому це важливо: OpenSSH на будь-який запит до закритого каналу рве
/// ВСЕ з'єднання («server_input_channel_req: unknown channel N»). Типовий
/// випадок — shell завершився (exit), клавіатура ховається, вікно терміналу
/// змінює розмір, і застосунок шле «window-change» у мертвий канал: з'єднання
/// падає разом із «Інфо», «Файлами» й рештою.
class ShellLink {
  final void Function(Uint8List data) _write;
  final void Function(int width, int height) _resize;
  final void Function() _close;
  bool _open = true;

  ShellLink({
    required void Function(Uint8List data) write,
    required void Function(int width, int height) resize,
    required void Function() close,
    required Future<void> done,
  })  : _write = write,
        _resize = resize,
        _close = close {
    // Помилка завершення теж означає, що каналу більше немає.
    done.then((_) => _open = false, onError: (_) => _open = false);
  }

  factory ShellLink.ssh(SSHSession s) => ShellLink(
        write: s.write,
        resize: s.resizeTerminal,
        close: s.close,
        done: s.done,
      );

  bool get isOpen => _open;

  void send(String text) {
    if (_open) _guard(() => _write(Uint8List.fromList(utf8.encode(text))));
  }

  void resize(int width, int height) {
    if (_open) _guard(() => _resize(width, height));
  }

  /// Закрити з нашого боку (напр. «Відкрити знову»). Якщо сервер уже закрив
  /// канал — нічого не надсилаємо.
  void close() {
    if (!_open) return;
    _open = false;
    _guard(_close);
  }

  /// Обірване з'єднання (транспорт мертвий, а канал про кінець так і не
  /// повідомив): dartssh2 кидає «Transport is closed» одразу або — у close() —
  /// з асинхронної частини, яку try/catch не ловить (09.11.2026, планшет).
  /// Помилка означає, що каналу більше немає.
  void _guard(void Function() action) {
    runZonedGuarded(() {
      try {
        action();
      } catch (_) {
        _open = false;
      }
    }, (_, __) => _open = false);
  }
}
