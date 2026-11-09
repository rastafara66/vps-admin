// Малювання терміналу: послідовності, якими tmux і повноекранні програми
// перемальовують екран, не мають ламати розбір виводу.
//
// 09.11.2026 на планшеті: Термінал увійшов у tmux, але показав лише верх
// екрана, без смуги tmux. xterm 4.0.0 на «стерти рядок зліва до курсора»
// (ESC [ 1 K) у колонці 0 звертався до клітинки -1 і кидав RangeError;
// решта виводу tmux губилась до наступної порції даних. tmux так стирає
// пробіл на початку рядка — тобто майже на кожному екрані.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

import 'package:vps_admin/safe_terminal.dart';

const _w = 20;
const _h = 6;

SafeTerminal _term() => SafeTerminal(maxLines: 100)..resize(_w, _h);

BufferLine _row(Terminal t, int y) => t.buffer.lines[y + t.buffer.scrollBack];

String _text(Terminal t, int y) => _row(t, y).getText().trimRight();

/// Клітинки рядка, де нічого не намальовано (стерті).
List<int> _blank(Terminal t, int y) => [
      for (var x = 0; x < _w; x++)
        if (_row(t, y).getCodePoint(x) == 0) x,
    ];

void main() {
  group('ESC [ 1 K — стерти рядок від початку до курсора', () {
    test('у колонці 0 не падає і стирає клітинку під курсором', () {
      final t = _term();
      t.write('abcdef\x1b[1G');
      expect(() => t.write('\x1b[1K'), returnsNormally);
      expect(_blank(t, 0).take(1), [0]);
      expect(_text(t, 0), 'bcdef');
    });

    test('у середині стирає до курсора включно (як xterm і VT100)', () {
      final t = _term();
      t.write('abcdef\x1b[4G\x1b[1K');
      expect(_blank(t, 0).where((x) => x < 6), [0, 1, 2, 3]);
      expect(_text(t, 0), 'ef');
    });

    test('у останній колонці стирає весь рядок', () {
      final t = _term();
      t.write('${'x' * _w}\x1b[${_w}G\x1b[1K');
      expect(_text(t, 0), '');
    });
  });

  test('ESC [ 1 J — стерти екран від початку до курсора включно', () {
    final t = _term();
    t.write('aaa\r\nbbb\r\ncccc\x1b[3;1H');
    expect(() => t.write('\x1b[1J'), returnsNormally);
    expect(_text(t, 0), '');
    expect(_text(t, 1), '');
    expect(_text(t, 2), 'ccc');
  });

  test('ESC [ 0 X — нуль означає один символ', () {
    final t = _term();
    t.write('abc\x1b[1G');
    expect(() => t.write('\x1b[0X'), returnsNormally);
    expect(_text(t, 0), 'bc');
  });

  // Так tmux перемальовує вікно: курсор на початок рядка, стерти пробіл
  // зліва, далі текст. Перевіряємо, що домальовано ВЕСЬ екран.
  test('перемальовування в стилі tmux доходить до останнього рядка', () {
    final t = _term();
    final out = StringBuffer('\x1b[?1049h\x1b[H\x1b[2J');
    for (var r = 1; r <= _h; r++) {
      out.write('\x1b[$r;1H\x1b[1K\x1b[2Grow $r');
    }
    expect(() => t.write(out.toString()), returnsNormally);
    for (var r = 1; r <= _h; r++) {
      expect(_text(t, r - 1), ' row $r'.trim(), reason: 'рядок $r');
    }
  });

  // Порода помилки: будь-яка команда стирання, вставки чи видалення на
  // краях екрана (перша/остання колонка й рядок, курсор «за краєм» після
  // повного рядка, широкі символи) не має кидати виняток і не має губити
  // вивід, що йде за нею.
  group('команди редагування на краях екрана', () {
    const seqs = [
      'K', '0K', '1K', '2K', 'J', '0J', '1J', '2J', '3J', //
      'X', '0X', '1X', '999X', 'P', '0P', '1P', '999P', //
      '@', '0@', '1@', '999@', 'L', '0L', '999L', 'M', '0M', '999M', //
      'S', '999S', 'T', '999T', 'G', '0G', '999G', 'd', '999d',
    ];
    final positions = <String, String>{
      'ліворуч угорі': '\x1b[1;1H',
      'праворуч угорі': '\x1b[1;${_w}H',
      'посередині': '\x1b[3;10H',
      'ліворуч унизу': '\x1b[$_h;1H',
      'праворуч унизу': '\x1b[$_h;${_w}H',
      'за краєм після повного рядка': '\x1b[2;1H${'z' * _w}',
      'на широкому символі': '\x1b[4;1H你好世界\x1b[4;2H',
      'після широкого символу': '\x1b[4;1H你好世界\x1b[4;3H',
    };
    for (final p in positions.entries) {
      for (final s in seqs) {
        test('ESC [ $s — ${p.key}', () {
          final t = _term();
          t.write('${'abcdefghij' * 2}\r\nline2\r\nline3');
          t.write(p.value);
          expect(() => t.write('\x1b[$s'), returnsNormally);
          expect(() => t.write('\x1b[1;1HOK'), returnsNormally);
          expect(_text(t, 0).startsWith('OK'), isTrue,
              reason: 'вивід після ESC [ $s загубився');
        });
      }
    }
  });

  test('у застосунку термінал створюється лише як SafeTerminal', () {
    final plain = RegExp(r'(?<![A-Za-z_])Terminal\(');
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('safe_terminal.dart'))
        .where((f) => plain.hasMatch(f.readAsStringSync()))
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty,
        reason: 'звичайний Terminal з xterm 4.0.0 падає на ESC [ 1 K у колонці 0');
  });
}
