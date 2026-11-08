"""Перевірка APK перед публікацією: у ньому не має бути особистих даних розробника.

    python tool/check_release_apk.py build/app/outputs/flutter-apk/app-release.apk

Шукає в кожному файлі APK (зокрема в скомпільованому libapp.so):
  * ім'я користувача ОС і шляхи на кшталт `C:/Users/...`, `/Users/...` — Flutter
    вшиває шлях до згенерованого dart_plugin_registrant.dart, тож збирати треба
    з літери диска (subst), а не з домашньої теки;
  * маркери з private_markers.local.txt (поза git): IP, імена, назви скриптів.

Код виходу 0 — чисто; 1 — знайдено, не публікувати (перелік — усе одразу).
"""
import getpass
import pathlib
import re
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
MARKERS_FILE = ROOT / 'private_markers.local.txt'

# Шлях домашньої теки у файловому URI чи звичайному вигляді.
# /home/<ім'я> не беремо: /home/ubuntu — типова стартова тека застосунку, а не
# дані розробника; його власне ім'я ловить маркер «ім'я користувача ОС».
HOME_PATH = re.compile(rb'(?i)(?:[a-z]:[/\\]+users[/\\]+|/Users/)[^/\\\x00"\' ]{2,}')


def markers():
    out = []
    user = getpass.getuser().strip()
    if user:
        out.append(user)
    if MARKERS_FILE.exists():
        for line in MARKERS_FILE.read_text(encoding='utf-8').splitlines():
            line = line.strip()
            if line and not line.startswith('#'):
                out.append(line)
    return sorted({m.lower() for m in out})


def main(apk):
    words = markers()
    problems = []
    with zipfile.ZipFile(apk) as z:
        for info in z.infolist():
            data = z.read(info)
            low = data.lower()
            for i, w in enumerate(words, 1):
                if w.encode('utf-8') in low:
                    problems.append(f'{info.filename}: особистий маркер №{i}')
            for m in sorted(set(HOME_PATH.findall(data)))[:3]:
                problems.append(f'{info.filename}: шлях домашньої теки ({m[:12].decode("latin-1")}…)')
    if not MARKERS_FILE.exists():
        print('⚠ private_markers.local.txt немає — перевірено лише ім\'я користувача й шляхи')
    if problems:
        print(f'Знайдено проблем: {len(problems)} — APK НЕ публікувати:')
        for p in problems:
            print('  -', p)
        print('Що робити: збирати з літери диска (subst V: <тека проєкту>), прибрати маркер з коду.')
        return 1
    print(f'Чисто: {apk} — перевірено {len(words)} маркер(ів) і шляхи домашніх тек у всіх файлах APK.')
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
