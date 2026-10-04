import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/sync/sync_coordinator.dart';
import '../../../core/sync/supabase_sync_client.dart';
import 'sync_conflicts_page.dart';

String syncStatusText(SyncStatus status) => switch (status) {
  SyncStatus.disabled => '本地模式',
  SyncStatus.authRequired => '需要登录',
  SyncStatus.synced => '已同步',
  SyncStatus.syncing => '同步中',
  SyncStatus.pending => '待同步',
  SyncStatus.conflict => '存在冲突',
};

class SyncStatusBadge extends StatelessWidget {
  final SyncCoordinator coordinator;
  final VoidCallback onOpen;
  const SyncStatusBadge({
    super.key,
    required this.coordinator,
    required this.onOpen,
  });
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: coordinator,
    builder: (context, _) => TextButton.icon(
      onPressed: onOpen,
      icon: Icon(
        coordinator.status == SyncStatus.conflict
            ? Icons.sync_problem
            : Icons.cloud_outlined,
        size: 18,
      ),
      label: Text(syncStatusText(coordinator.status)),
    ),
  );
}

class SyncCenter extends StatefulWidget {
  final SyncCoordinator coordinator;
  const SyncCenter({super.key, required this.coordinator});
  @override
  State<SyncCenter> createState() => _SyncCenterState();
}

class _SyncCenterState extends State<SyncCenter> {
  final _email = TextEditingController(), _code = TextEditingController();
  bool _busy = false;
  String? _message;
  Future<void> _action(
    Future<void> Function() action, {
    String? success,
  }) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) setState(() => _message = success);
    } catch (error) {
      if (mounted) {
        setState(
          () => _message =
              error is SyncFailure && error.code == 'account_mismatch'
              ? '此工作区已绑定另一个账户，请使用独立工作区。'
              : '操作未完成。本地数据已保留，请检查网络或登录配置后重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.coordinator,
    builder: (context, _) {
      final sync = widget.coordinator;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('同步中心', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(syncStatusText(sync.status)),
          Text('待同步 ${sync.pendingCount} · 未解决冲突 ${sync.conflictCount}'),
          const Text('本地编辑立即保存，云同步在后台进行。退出登录会保留本地数据及待同步操作。'),
          if (!sync.configured)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('未配置 Supabase，当前使用完整本地模式。'),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed:
                    !sync.configured ||
                        _busy ||
                        sync.status == SyncStatus.syncing
                    ? null
                    : () => _action(sync.resume),
                child: const Text('立即同步'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        SyncConflictsPage(repository: sync.conflicts),
                  ),
                ),
                child: const Text('打开冲突中心'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _action(sync.signOut),
                child: const Text('退出同步账户'),
              ),
            ],
          ),
          if (sync.errorCode != null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('同步未完成，待同步内容已保留，可重试。'),
            ),
          if (sync.configured) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: '邮箱'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _code,
              decoration: const InputDecoration(labelText: '邮箱验证码'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: [
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _action(
                          () => sync.requestOtp(_email.text),
                          success: '验证码已发送，请检查邮箱。',
                        ),
                  child: const Text('发送验证码'),
                ),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => _action(() async {
                          await sync.signIn(_email.text, _code.text);
                          _code.clear();
                          unawaited(sync.syncOnce());
                        }),
                  child: const Text('登录并开启同步'),
                ),
              ],
            ),
          ],
          if (_message != null) Text(_message!),
        ],
      );
    },
  );
}
