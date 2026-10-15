import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/chat_backup.dart';
import '../services/backup_files.dart';
import '../services/chat_controller.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({
    super.key,
    required this.controller,
    this.files,
    this.codec,
  });
  final ChatController controller;
  final BackupFiles? files;
  final BackupCodec? codec;
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen>
    with WidgetsBindingObserver {
  final _password = TextEditingController(), _confirm = TextEditingController();
  ChatController get c => widget.controller;
  BackupFiles get files => widget.files ?? c.backupFiles;
  late final codec = widget.codec ?? BackupCodec();
  BackupData? _preview;
  BackupMerge? _plan;
  bool _busy = false, _canMove = false, _move = false;
  String? _notice;
  int _generation = 0, _accessToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_changed);
    _notice = c.backupNotice;
    c.backupNotice = null;
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _clearSecrets();
      if (mounted) setState(() {});
    }
  }

  void _clearSecrets() {
    _generation++;
    _password.clear();
    _confirm.clear();
    _preview = null;
    _plan = null;
    _move = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_changed);
    _clearSecrets();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool _valid(int generation, int access) =>
      mounted &&
      generation == _generation &&
      access == c.accessRevision &&
      c.appAccessible &&
      c.appForeground;
  String _error(Object error) => error is FormatException
      ? error.message
      : 'Could not complete the backup operation. Please retry.';

  Future<void> _export() async {
    final generation = ++_generation, access = c.accessRevision;
    final password = _password.text;
    setState(() {
      _busy = true;
      _notice = null;
      _preview = null;
      _plan = null;
    });
    try {
      BackupCodec.checkPassword(password);
      if (password != _confirm.text) {
        throw const FormatException('Backup passwords do not match.');
      }
      final data = await c.backupSnapshot();
      if (!_valid(generation, access)) return;
      final bytes = await codec.encrypt(data, password);
      if (!_valid(generation, access)) return;
      _password.clear();
      _confirm.clear();
      final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
        ':',
        '-',
      );
      final saved = await files.save(bytes, 'localchat-$stamp.lcbackup');
      final notice = saved
          ? 'Encrypted backup saved. Keep its password somewhere safe.'
          : 'Export cancelled.';
      c.backupNotice = notice;
      if (mounted) setState(() => _notice = notice);
    } catch (e) {
      if (_valid(generation, access)) {
        setState(() => _notice = _error(e));
      } else if (!mounted) {
        c.backupNotice = 'Export did not finish. Please try again.';
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    _clearSecrets();
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final Uint8List? bytes = await files.pick();
      // This callback may outlive a navigator removed by app locking.
      if (bytes != null) {
        c.backupFilePicked(
          bytes,
          notice: 'Encrypted file selected. Enter its password to preview.',
        );
      } else if (mounted) {
        setState(() => _notice = 'File selection cancelled.');
      }
    } catch (e) {
      c.backupNotice = _error(e);
      if (mounted) setState(() => _notice = _error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlock() async {
    final generation = ++_generation, access = c.accessRevision;
    final bytes = c.pendingBackup;
    if (bytes == null) return;
    final password = _password.text;
    setState(() {
      _busy = true;
      _notice = null;
      _preview = null;
      _plan = null;
    });
    try {
      final data = await codec.decrypt(bytes, password);
      if (!_valid(generation, access)) return;
      final current = await c.backupSnapshot();
      if (!_valid(generation, access)) return;
      final plan = planBackup(current, data);
      _password.clear();
      _confirm.clear();
      setState(() {
        _preview = data;
        _plan = plan;
        _accessToken = access;
        _move = false;
        _canMove =
            current.peers.isEmpty &&
            current.messages.isEmpty &&
            current.drafts.isEmpty &&
            current.groupDrafts.isEmpty &&
            current.groups.isEmpty;
      });
    } catch (e) {
      if (_valid(generation, access)) {
        setState(() => _notice = _error(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final data = _preview;
    if (data == null) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final result = await c.restoreBackup(
        data,
        moveIdentity: _move,
        accessToken: _accessToken,
      );
      final notice =
          'Imported ${result.newChats} chats, ${result.newMessages} messages, '
          '${result.newDrafts} drafts and ${result.data.stars.length} stars. Skipped ${result.duplicates} duplicates; '
          'kept ${result.conflicts} conflicting messages and ${result.keptDrafts} existing drafts.';
      c.backupFilePicked(null, notice: notice);
      if (mounted && generation == _generation) {
        _clearSecrets();
        setState(() => _notice = notice);
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(
          () =>
              _notice = c.store.identityRecoveryRequired ? c.error : _error(e),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController controller, String label, String key) =>
      TextField(
        key: ValueKey(key),
        controller: controller,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(labelText: label),
        enabled: !_busy,
      );

  @override
  Widget build(BuildContext context) {
    final data = _preview, plan = _plan;
    return Scaffold(
      appBar: AppBar(title: const Text('Chat backups')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Save an encrypted .lcbackup file and transfer it offline to another phone. '
              'The file includes direct and group history, drafts, starred messages, pin/archive choices and your messaging identity. '
              'Anyone with the file and password can read it and use that identity.',
            ),
            const SizedBox(height: 12),
            const Text(
              'Choose a separate password of at least 12 characters. '
              'There is no password recovery. Your app PIN, biometric settings, themes and display name '
              'on the destination phone stay as they are.',
            ),
            if (c.isDemo)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Demo backups only import into the browser demo. Imported demo history still resets on reload.',
                ),
              ),
            if (_notice != null || c.backupNotice != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _notice ?? c.backupNotice!,
                  key: const ValueKey('backup-notice'),
                ),
              ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    LinearProgressIndicator(),
                    SizedBox(height: 8),
                    Text('Working on your backup…'),
                  ],
                ),
              ),
            if (data == null) ...[
              const SizedBox(height: 20),
              _field(_password, 'Backup password', 'backup-password'),
              const SizedBox(height: 12),
              _field(_confirm, 'Confirm password for export', 'backup-confirm'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy || !c.initialized ? null : _export,
                icon: const Icon(Icons.file_upload_outlined),
                label: const Text('Export encrypted backup'),
              ),
              const Divider(height: 40),
              OutlinedButton.icon(
                onPressed: _busy || !c.initialized ? null : _pick,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Choose backup file'),
              ),
              if (c.pendingBackup != null) ...[
                const SizedBox(height: 12),
                const Text(
                  'Encrypted file ready. Enter its password above. '
                  'If the file picker locks the app, unlock and return here to continue.',
                ),
                FilledButton(
                  onPressed: _busy ? null : _unlock,
                  child: const Text('Preview import'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () {
                          _clearSecrets();
                          c.backupFilePicked(null);
                          setState(() => _notice = null);
                        },
                  child: const Text('Discard selected file'),
                ),
              ],
            ] else if (plan != null) ...[
              const SizedBox(height: 20),
              Text(
                'Import preview',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                'From ${data.name} • ${DateTime.fromMillisecondsSinceEpoch(data.created).toLocal()}',
              ),
              Text(
                '${data.peers.length} direct chats • ${data.groups.length} groups • '
                '${data.messages.length + data.groups.fold<int>(0, (sum, g) => sum + (g['messages'] as List).length)} messages • ${data.drafts.length + data.groupDrafts.length} drafts • ${data.stars.length} stars',
              ),
              const SizedBox(height: 12),
              Text(
                'Add ${plan.newChats} chats, ${plan.newMessages} messages, ${plan.newDrafts} drafts and ${plan.data.stars.length} stars. '
                'Skip ${plan.duplicates} duplicates. Keep ${plan.conflicts} conflicting existing messages '
                'and ${plan.keptDrafts} existing drafts.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Existing chat names, pin/archive choices and read/delivery state are kept. '
                'New chats use the backup choices. Imported stars are added; an old backup can restore a star you removed. Counts are checked again when importing.',
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _move,
                onChanged: _busy || !_canMove
                    ? null
                    : (v) => setState(() => _move = v!),
                title: const Text('Transfer messaging identity'),
                subtitle: Text(
                  _canMove
                      ? 'For moving to this empty phone. Stop using LocalChat on the old phone afterward. '
                            'Peers recognize your identity; compare security codes again when reconnecting.'
                      : 'Requires an empty destination with no saved chats or drafts. This import keeps your current identity.',
                ),
              ),
              if (!_move)
                const Text(
                  'History-only import: this phone keeps its identity. '
                  'Existing peers may see it as a different person when connecting.',
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _import,
                child: Text(
                  _move ? 'Import and transfer identity' : 'Import history',
                ),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () {
                        _clearSecrets();
                        c.backupFilePicked(null);
                        setState(() => _notice = 'Import cancelled.');
                      },
                child: const Text('Cancel import'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
