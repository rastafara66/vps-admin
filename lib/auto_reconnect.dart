import 'dart:async';

import 'package:flutter/widgets.dart';

import 'services/ssh_service.dart';

/// Підключається знову сам, коли з'єднання обірвалось не з волі користувача.
///
/// 09.11.2026, власник: «кожен раз коли переключаюсь на VPS admin треба
/// відновлювати з'єднання … це дратує». Android заморожує застосунок у фоні,
/// і SSH за цей час відмирає. Постійні сесії (tmux) на сервері живуть далі,
/// тож досить підключитися знову — Термінал сам повернеться в сесію
/// («команда при відкритті терміналу»).
///
/// Правила:
/// * обрив на екрані — одразу кілька спроб ([retryDelays]), далі тиша;
/// * обрив у фоні — нічого, доки людина не повернеться в застосунок;
/// * «Від'єднатися» кнопкою — самі не підключаємось;
/// * повернення після паузи, довшої за [checkAfterPause], — «живе»
///   з'єднання перевіряється короткою командою: напівмертве (мережа змінилась,
///   сервер забув) інакше висіло б замість обриву.
class AutoReconnect with WidgetsBindingObserver {
  AutoReconnect({
    required this.ssh,
    required this.reconnect,
    this.retryDelays = const [
      Duration.zero,
      Duration(seconds: 2),
      Duration(seconds: 5),
    ],
    this.checkAfterPause = const Duration(seconds: 15),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SshService ssh;

  /// Підключитися до активного сервера (AppState.connectActive).
  final Future<void> Function() reconnect;

  final List<Duration> retryDelays;
  final Duration checkAfterPause;
  final DateTime Function() _now;

  bool _foreground = true;
  bool _observing = false;

  /// Обрив був, а з'єднання ще не відновлене.
  bool _pending = false;
  DateTime? _pausedAt;
  Future<void>? _running;

  /// Чекати, доки скінчиться поточна робота (для тестів).
  @visibleForTesting
  Future<void> get idle async {
    while (_running != null) {
      await _running;
    }
  }

  void start({bool observeLifecycle = true}) {
    ssh.addListener(_onSsh);
    if (observeLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
  }

  void dispose() {
    ssh.removeListener(_onSsh);
    if (_observing) WidgetsBinding.instance.removeObserver(this);
  }

  void _onSsh() {
    if (ssh.isConnected) {
      _pending = false;
      return;
    }
    // Свої ж спроби (connect спершу скидає стан) — не рішення користувача.
    if (_running != null) return;
    if (ssh.connectionLost) {
      _pending = true;
      if (_foreground) _run(_retry);
    } else if (ssh.status == SshStatus.disconnected) {
      _pending = false; // від'єднались кнопкою
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_foreground) return;
        _foreground = true;
        final paused = _pausedAt == null ? Duration.zero : _now().difference(_pausedAt!);
        _pausedAt = null;
        _run(() => _onResumed(paused));
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (!_foreground) return;
        _foreground = false;
        _pausedAt = _now();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _onResumed(Duration paused) async {
    if (ssh.isConnected) {
      if (paused < checkAfterPause) return;
      if (await ssh.checkAlive()) return;
      _pending = true; // checkAlive сам позначив обрив
    }
    if (_pending) await _retry();
  }

  Future<void> _retry() async {
    for (final d in retryDelays) {
      if (d > Duration.zero) await Future<void>.delayed(d);
      if (!_foreground || !_pending) return;
      try {
        await reconnect();
      } catch (_) {}
      if (ssh.isConnected) {
        _pending = false;
        return;
      }
    }
  }

  /// Одна робота за раз. Позначка ставиться ДО старту: перевірка з'єднання
  /// синхронно сповіщає про обрив, і без позначки почалась би друга серія спроб.
  void _run(Future<void> Function() job) {
    if (_running != null) return;
    final done = Completer<void>();
    _running = done.future;
    job().catchError((Object _) {}).whenComplete(() {
      _running = null;
      done.complete();
    });
  }
}
