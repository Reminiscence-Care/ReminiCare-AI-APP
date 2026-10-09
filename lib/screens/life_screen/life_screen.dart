import 'dart:async';

import 'package:flutter/material.dart';

import 'controllers/life_screen_controller.dart';
import 'widgets/stage_views.dart';

class LifeScreen extends StatefulWidget {
  const LifeScreen({super.key, this.controllerFactory});
  final LifeScreenController Function()? controllerFactory;

  @override
  State<LifeScreen> createState() => _LifeScreenState();
}

class _LifeScreenState extends State<LifeScreen> with WidgetsBindingObserver {
  late final LifeScreenController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = (widget.controllerFactory?.call() ?? LifeScreenController())
      ..addListener(_refresh);
    _controller.initialize();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_refresh);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_controller.interruptAudio());
    }
  }

  Future<void> _back() async {
    await _controller.leave();
    if (mounted) Navigator.maybePop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_controller.leave());
      },
      child: Scaffold(
        appBar: AppBar(
          actions: const [SizedBox(width: 72)],
          title: _controller.debugFixedFlow
              ? const Text('固定測試流程', key: ValueKey('debug-flow-banner'))
              : null,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          leading: IconButton(
            onPressed: _back,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 30),
            tooltip: '返回',
          ),
        ),
        body: SafeArea(
          child: ReminiCareViewport(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: LifeStageView(
                key: ValueKey(_controller.stage),
                controller: _controller,
                onDone: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
