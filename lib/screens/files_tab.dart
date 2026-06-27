import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/ssh_service.dart';
import '../theme.dart';
import '../widgets.dart';
import 'file_editor_screen.dart';

/// SFTP-браузер: дерево тек, відкриття текстового файлу в редакторі.
class FilesTab extends StatelessWidget {
  const FilesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return RequireConnection(builder: (context) => const _Browser());
  }
}

class _Entry {
  final String name;
  final bool isDir;
  final bool isLink;
  final int size;
  _Entry(this.name, this.isDir, this.isLink, this.size);
}

class _Browser extends StatefulWidget {
  const _Browser();

  @override
  State<_Browser> createState() => _BrowserState();
}

class _BrowserState extends State<_Browser> {
  SftpClient? _sftp;
  String _path = '/';
  List<_Entry> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _path = context.read<AppState>().activeServer?.defaultDir ?? '/';
    _open();
  }

  Future<SftpClient> _client() async {
    _sftp ??= await context.read<SshService>().sftp();
    return _sftp!;
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sftp = await _client();
      final items = await sftp.listdir(_path);
      final list = <_Entry>[];
      for (final it in items) {
        final n = it.filename;
        if (n == '.' || n == '..') continue;
        final long = it.longname;
        // OpenSSH повертає longname у форматі `ls -l` (перший символ: d/l/-).
        final isDir = long.isNotEmpty && long.startsWith('d');
        final isLink = long.isNotEmpty && long.startsWith('l');
        list.add(_Entry(n, isDir, isLink, it.attr.size ?? 0));
      }
      list.sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        _entries = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _goto(String newPath) {
    setState(() => _path = _normalize(newPath));
    _open();
  }

  void _up() {
    if (_path == '/') return;
    final parts = _path.split('/')..removeWhere((e) => e.isEmpty);
    parts.removeLast();
    _goto('/${parts.join('/')}');
  }

  String _normalize(String p) {
    final parts = <String>[];
    for (final seg in p.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(seg);
      }
    }
    return '/${parts.join('/')}';
  }

  String _join(String name) => _path == '/' ? '/$name' : '$_path/$name';

  Future<void> _openFile(_Entry e) async {
    final l = AppLocalizations.of(context);
    final full = _join(e.name);
    if (e.size > 2 * 1024 * 1024) {
      _snack(l.fileTooLarge(_fmtSize(e.size)));
      return;
    }
    try {
      final sftp = await _client();
      final f = await sftp.open(full);
      final bytes = await f.readBytes();
      await f.close();
      if (bytes.contains(0)) {
        _snack(l.binaryFile);
        return;
      }
      final content = utf8.decode(bytes, allowMalformed: true);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FileEditorScreen(
          path: full,
          initialContent: content,
          onSave: (text) => _saveFile(full, text),
        ),
      ));
    } catch (e) {
      if (mounted) _snack(AppLocalizations.of(context).readError('$e'));
    }
  }

  Future<void> _saveFile(String path, String text) async {
    final sftp = await _client();
    final f = await sftp.open(
      path,
      mode: SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate,
    );
    await f.writeBytes(Uint8List.fromList(utf8.encode(text)));
    await f.close();
  }

  void _snack(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  String _fmtSize(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.appColors;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      children: [
        Container(
          color: c.panel,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_upward),
                tooltip: l.up,
                onPressed: _path == '/' ? null : _up,
              ),
              Expanded(
                child: Text(
                  _path,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: l.refresh,
                onPressed: _open,
              ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l.sftpError(_error!),
                        textAlign: TextAlign.center),
                  ),
                )
              : ListView.builder(
                  itemCount: _entries.length,
                  itemBuilder: (context, i) {
                    final e = _entries[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        e.isDir
                            ? Icons.folder
                            : (e.isLink ? Icons.link : Icons.description_outlined),
                        color: e.isDir ? c.folder : muted,
                        size: 20,
                      ),
                      title: Text(e.name,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 13)),
                      trailing: e.isDir
                          ? null
                          : Text(_fmtSize(e.size),
                              style: TextStyle(fontSize: 11, color: muted)),
                      onTap: () =>
                          e.isDir ? _goto(_join(e.name)) : _openFile(e),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
