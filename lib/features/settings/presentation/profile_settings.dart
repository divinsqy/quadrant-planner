import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/settings/app_preferences.dart';
import '../data/preferences_repository.dart';

class ProfileSettings extends StatefulWidget {
  final PreferencesRepository preferences;

  const ProfileSettings({
    super.key,
    required this.preferences,
  });

  @override
  State<ProfileSettings> createState() => _ProfileSettingsState();
}

class _ProfileSettingsState extends State<ProfileSettings> {
  final TextEditingController _nicknameController = TextEditingController();
  StreamSubscription<AppPreferences>? _subscription;
  AppPreferences _current = AppPreferences.defaults();
  bool _dirty = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant ProfileSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferences == widget.preferences) {
      return;
    }
    _subscription?.cancel();
    _listen();
  }

  void _listen() {
    _subscription = widget.preferences.watch().listen((value) {
      _current = value;
      if (!_dirty) {
        _nicknameController.text = value.nickname;
      }
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _save() async {
    final nickname = _nicknameController.text.trim();
    await widget.preferences.save(
      AppPreferences(
        nickname: nickname,
        importanceThreshold: _current.importanceThreshold,
        urgencyThreshold: _current.urgencyThreshold,
      ),
    );
    if (mounted) {
      setState(() {
        _dirty = false;
        _saved = true;
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '个人资料',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nicknameController,
            onChanged: (_) {
              _dirty = true;
              _saved = false;
            },
            decoration: const InputDecoration(
              labelText: '昵称',
              hintText: '例如 Divins',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: _save,
                child: const Text('保存昵称'),
              ),
              if (_saved) ...[
                const SizedBox(width: 12),
                const Text('已保存'),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
