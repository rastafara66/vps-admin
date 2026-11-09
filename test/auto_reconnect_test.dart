// Самостійне перепідключення.
//
// 09.11.2026, власник: «кожен раз коли переключаюсь на VPS admin треба
// відновлювати з'єднання, коли тиснеш це 10 разів підряд - це дратує».
// Android заморожує застосунок у фоні, і SSH за цей час відмирає.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vps_admin/auto_reconnect.dart';
import 'package:vps_admin/services/ssh_service.dart';

/// Стан SSH без мережі; переходи — як у справжнього SshService.
class _FakeSsh extends SshService {
  bool connected = true;
  bool lost = false;
  SshStatus st = SshStatus.connected;
  bool alive = true;
  int checks = 0;

  @override
  bool get isConnected => connected;
  @override
  bool get connectionLost => lost;
  @override
  SshStatus get status => st;

  void _apply(bool c, bool l, SshStatus s) {
    connected = c;
    lost = l;
    st = s;
    notifyListeners();
  }

  /// Обрив сам по собі (мережа, сон, фон).
  void drop() => _apply(false, true, SshStatus.disconnected);

  /// Кнопка «Від'єднатися».
  void userDisconnect() => _apply(false, false, SshStatus.disconnected);

  @override
  Future<bool> checkAlive({Duration timeout = const Duration(seconds: 5)}) async {
    checks++;
    if (alive) return true;
    drop();
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSsh ssh;
  late AutoReconnect auto;
  late int attempts;
  late int failFirst; // скільки перших спроб невдалі
  late DateTime clock;

  Future<void> reconnect() async {
    attempts++;
    // Як SshService.connect: спершу «підключення…», обрив скинуто.
    ssh._apply(false, false, SshStatus.connecting);
    await Future<void>.delayed(Duration.zero);
    if (attempts > failFirst) {
      ssh._apply(true, false, SshStatus.connected);
    } else {
      ssh._apply(false, false, SshStatus.error);
    }
  }

  setUp(() {
    ssh = _FakeSsh();
    attempts = 0;
    failFirst = 0;
    clock = DateTime(2026, 11, 9, 12);
    auto = AutoReconnect(
      ssh: ssh,
      reconnect: reconnect,
      retryDelays: const [Duration.zero, Duration.zero, Duration.zero],
      now: () => clock,
    )..start(observeLifecycle: false);
  });
  tearDown(() => auto.dispose());

  void lifecycle(AppLifecycleState s) => auto.didChangeAppLifecycleState(s);

  test('обрив, поки застосунок на екрані, — підключається сам', () async {
    ssh.drop();
    await auto.idle;
    expect(attempts, 1);
    expect(ssh.isConnected, isTrue);
  });

  test('обрив у фоні — нічого не робить, доки не повернулись; після повернення — підключено', () async {
    lifecycle(AppLifecycleState.inactive);
    lifecycle(AppLifecycleState.hidden);
    lifecycle(AppLifecycleState.paused);
    ssh.drop();
    await auto.idle;
    expect(attempts, 0, reason: 'у фоні мережа заморожена — не смикати');

    lifecycle(AppLifecycleState.resumed);
    await auto.idle;
    expect(attempts, 1);
    expect(ssh.isConnected, isTrue);
  });

  test('від\'єднались кнопкою — самі не підключаємось', () async {
    ssh.userDisconnect();
    lifecycle(AppLifecycleState.paused);
    lifecycle(AppLifecycleState.resumed);
    await auto.idle;
    expect(attempts, 0);
  });

  test('сервер недоступний: кілька спроб і тиша; наступне повернення — знову спроби', () async {
    failFirst = 100;
    ssh.drop();
    await auto.idle;
    expect(attempts, 3);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(attempts, 3, reason: 'без нескінченного циклу');

    failFirst = 3; // мережа повернулась
    lifecycle(AppLifecycleState.paused);
    lifecycle(AppLifecycleState.resumed);
    await auto.idle;
    expect(attempts, 4);
    expect(ssh.isConnected, isTrue);
  });

  test('друга невдала спроба, третя вдала — підключено', () async {
    failFirst = 2;
    ssh.drop();
    await auto.idle;
    expect(attempts, 3);
    expect(ssh.isConnected, isTrue);
  });

  test('після довгої паузи «живе» з\'єднання перевіряється; мертве — нове', () async {
    ssh.alive = false;
    lifecycle(AppLifecycleState.paused);
    clock = clock.add(const Duration(minutes: 5));
    lifecycle(AppLifecycleState.resumed);
    await auto.idle;
    expect(ssh.checks, 1);
    expect(attempts, 1);
    expect(ssh.isConnected, isTrue);
  });

  test('коротка пауза (шторка, перемикач) — без зайвої перевірки', () async {
    lifecycle(AppLifecycleState.paused);
    clock = clock.add(const Duration(seconds: 3));
    lifecycle(AppLifecycleState.resumed);
    await auto.idle;
    expect(ssh.checks, 0);
    expect(attempts, 0);
  });
}
