import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_log.dart';

/// Wraps the root Navigator so the entry remains visible above pages and dialogs.
class AppLogOverlay extends StatefulWidget {
  const AppLogOverlay({
    super.key,
    required this.child,
    required this.navigatorKey,
    this.log,
  });
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  final AppLog? log;
  @override
  State<AppLogOverlay> createState() => _AppLogOverlayState();
}

class _AppLogOverlayState extends State<AppLogOverlay> {
  bool _showing = false;
  Future<void> _open() async {
    final navigator = widget.navigatorKey.currentState;
    if (_showing || navigator == null) return;
    setState(() => _showing = true);
    try {
      await navigator.push<void>(
        MaterialPageRoute(builder: (_) => AppLogScreen(log: widget.log)),
      );
    } finally {
      if (mounted) setState(() => _showing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      Positioned(
        top: 4,
        right: 8,
        child: SafeArea(
          child: SizedBox(
            width: 56,
            height: 48,
            child: FilledButton.tonal(
              key: const ValueKey('app-log-button'),
              onPressed: _showing ? null : _open,
              style: FilledButton.styleFrom(padding: EdgeInsets.zero),
              child: Semantics(
                label: '執行紀錄',
                child: const Text('Log', style: TextStyle(fontSize: 18)),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

class AppLogScreen extends StatefulWidget {
  const AppLogScreen({super.key, this.log});
  final AppLog? log;
  @override
  State<AppLogScreen> createState() => _AppLogScreenState();
}

class _AppLogScreenState extends State<AppLogScreen> {
  late final AppLog _log = widget.log ?? AppLog.instance;
  late final Timer _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('執行紀錄'),
      actions: const [SizedBox(width: 72)],
    ),
    body: AnimatedBuilder(
      animation: _log,
      builder: (context, _) {
        final entries = _log.entries.reversed.toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '本次執行 ${_log.elapsed.inSeconds} 秒・${entries.length}/${_log.capacity} 筆・最新在上方',
                    key: const ValueKey('app-log-summary'),
                    style: const TextStyle(fontSize: 20),
                  ),
                  TextButton.icon(
                    onPressed: entries.isEmpty
                        ? null
                        : () async {
                            await Clipboard.setData(
                              ClipboardData(text: _log.exportText()),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已複製紀錄')),
                              );
                            }
                          },
                    icon: const Icon(Icons.copy),
                    label: const Text('複製'),
                  ),
                  TextButton.icon(
                    key: const ValueKey('clear-app-log'),
                    onPressed: entries.isEmpty ? null : _log.clear,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('清除'),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '只記錄本次執行的事件與耗時；重新啟動後清空。',
                style: TextStyle(fontSize: 17),
              ),
            ),
            const Divider(),
            Expanded(
              child: entries.isEmpty
                  ? const Center(child: Text('尚無執行紀錄'))
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (_, index) {
                        final entry = entries[index];
                        return Padding(
                          key: ValueKey('log-entry-${entry.id}'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: SelectableText(
                            entry.line,
                            style: TextStyle(
                              fontSize: 20,
                              fontFamily: 'Consolas',
                              color: entry.isError ? Colors.red.shade800 : null,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    ),
  );
}
