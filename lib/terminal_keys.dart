/// Чиста логіка терміналу без Flutter: клавіша Ctrl з екранної панелі,
/// послідовності tmux/screen і текст, який Термінал пише в shell при старті.
/// Винесено окремо, щоб покривалось юніт-тестами.
library;

/// Назва сесії, яку підставляють готові варіанти «tmux» / «screen».
/// Користувач змінює її у профілі сервера — у коді конкретних назв немає.
const kDefaultSessionName = 'main';

/// Підключитися до сесії tmux, а якщо її немає — створити.
String tmuxStartupCommand([String name = kDefaultSessionName]) =>
    'tmux new -A -s $name';

/// Те саме для screen: перепідключитися (від'єднавши інші екрани) або створити.
String screenStartupCommand([String name = kDefaultSessionName]) =>
    'screen -D -R -S $name';

/// Текст, який Термінал надсилає в shell одразу після відкриття:
/// перейти в стартову теку й виконати команду при відкритті (якщо є).
String shellStartupInput({String? dir, String? command}) {
  final b = StringBuffer();
  final d = dir?.trim() ?? '';
  if (d.isNotEmpty && d != '/') b.write('cd "$d"\n');
  final c = command?.trim() ?? '';
  if (c.isNotEmpty) b.write('$c\n');
  return b.toString();
}

/// Символ, який дає Ctrl + [ch] (один символ). null — така комбінація
/// керуючого символу не має, і символ іде як є.
///   a…z (і A…Z) → 0x01…0x1A;  [ \ ] ^ _ → 0x1B…0x1F;  пробіл і @ → 0x00;  ? → 0x7F.
String? ctrlChar(String ch) {
  if (ch.length != 1) return null;
  final c = ch.toLowerCase().codeUnitAt(0);
  if (c >= 0x61 && c <= 0x7a) return String.fromCharCode(c - 0x60);
  if (c >= 0x5b && c <= 0x5f) return String.fromCharCode(c - 0x40);
  if (c == 0x20 || c == 0x40) return String.fromCharCode(0);
  if (c == 0x3f) return String.fromCharCode(0x7f);
  return null;
}

/// Префікс tmux за замовчуванням — Ctrl+b.
const _tmuxPrefix = '\x02';

/// Команди tmux, доступні з меню панелі клавіш (типовий префікс Ctrl+b).
enum TmuxKey {
  detach('d'),
  newWindow('c'),
  nextWindow('n'),
  chooseSession('s'),
  scrollMode('[');

  final String key;
  const TmuxKey(this.key);

  /// Байти, які треба надіслати: префікс, потім клавіша.
  String get sequence => '$_tmuxPrefix$key';
}

/// Від'єднатися від screen: Ctrl+a, потім d.
const screenDetachSequence = '\x01d';
