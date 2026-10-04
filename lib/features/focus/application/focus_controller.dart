import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../domain/focus/focus_session.dart';
import '../data/focus_repository.dart';

class FocusController extends ChangeNotifier {
  final FocusRepository repository;
  final DateTime Function() _clock;
  FocusSession? session;
  Duration recordedBeforeSession = Duration.zero;
  bool busy = false;
  bool _disposed = false;
  int _version = 0;
  StreamSubscription<FocusSession?>? _subscription;
  FocusController(this.repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  DateTime get now => _clock();
  Duration get elapsed => session?.elapsed(now.toUtc()) ?? Duration.zero;
  Duration get totalTaskDuration => recordedBeforeSession + elapsed;
  void watch() {
    _subscription ??= repository.watchActive().listen((value) async {
      final version = ++_version;
      if (busy || _disposed) return;
      if (value != null) {
        final prior = await repository.priorDuration(value.taskId, value.id);
        if (_disposed || busy || version != _version) return;
        session = value;
        recordedBeforeSession = prior;
      } else if (session?.isActive ?? false) {
        session = null;
      }
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> recover() async {
    final version = ++_version;
    final value = await repository.activeSession();
    final prior = value == null
        ? Duration.zero
        : await repository.priorDuration(value.taskId, value.id);
    if (_disposed || version != _version) return;
    session = value;
    recordedBeforeSession = prior;
    notifyListeners();
  }

  Future<void> _run(Future<FocusSession> Function() action) async {
    if (busy) throw StateError('专注操作正在保存');
    _version++;
    busy = true;
    if (!_disposed) notifyListeners();
    try {
      final value = await action();
      final prior = await repository.priorDuration(value.taskId, value.id);
      if (_disposed) return;
      session = value;
      recordedBeforeSession = prior;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> start(String taskId, {String? planBlockId}) =>
      _run(() => repository.start(taskId, now, planBlockId: planBlockId));
  Future<void> pause() => _run(() => repository.pause(now));
  Future<void> resume() => _run(() => repository.resume(now));
  Future<void> complete({
    bool completeTask = true,
    bool removeFutureBlocks = false,
  }) => _run(
    () => repository.complete(
      now,
      completeTask: completeTask,
      removeFutureBlocks: removeFutureBlocks,
    ),
  );
  Future<void> markBlocked() => _run(() => repository.markBlocked(now));
  @override
  void dispose() {
    _disposed = true;
    _version++;
    _subscription?.cancel();
    super.dispose();
  }
}
