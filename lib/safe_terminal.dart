import 'dart:math';

import 'package:xterm/xterm.dart';

/// Terminal з xterm 4.0.0 (остання версія) з виправленими командами
/// редагування на краях екрана.
///
/// 09.11.2026 на планшеті: після входу в tmux було видно лише верх екрана.
/// tmux стирає пробіл на початку рядка командою ESC [ 1 K, курсор при цьому
/// в колонці 0, а xterm звертався до клітинки -1 і кидав RangeError посеред
/// розбору — решта картинки губилась. Тест: test/terminal_render_test.dart
/// (там же гейт «лише SafeTerminal»).
class SafeTerminal extends Terminal {
  SafeTerminal({super.maxLines});

  /// ESC [ 1 K — стерти від початку рядка до курсора ВКЛЮЧНО.
  /// У xterm 4.0.0: без клітинки під курсором і падіння в колонці 0.
  @override
  void eraseLineLeft() => _eraseLineToCursor();

  /// ESC [ 1 J — стерти екран від початку до курсора включно.
  @override
  void eraseDisplayAbove() {
    final b = buffer;
    for (var y = 0; y < b.cursorY; y++) {
      final line = b.lines[y + b.scrollBack];
      line.isWrapped = false;
      line.eraseRange(0, viewWidth, cursor);
    }
    _eraseLineToCursor();
  }

  /// ESC [ Ps X — стерти Ps символів; 0 означає 1 (у xterm 4.0.0 — падіння
  /// в колонці 0).
  @override
  void eraseChars(int amount) => super.eraseChars(max(amount, 1));

  /// ESC [ Ps P — видалити Ps символів. Курсор «за краєм» після повного
  /// рядка вважається в останній колонці, як у xterm і VT100; 0 означає 1.
  @override
  void deleteChars(int amount) {
    final b = buffer;
    final start = b.cursorX;
    final count = min(max(amount, 1), viewWidth - start);
    if (count > 0) b.currentLine.removeCells(start, count, cursor);
  }

  void _eraseLineToCursor() {
    final line = buffer.currentLine;
    line.isWrapped = false;
    line.eraseRange(0, min(buffer.cursorX + 1, viewWidth), cursor);
  }
}
