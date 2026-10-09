import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'services/api_services.dart';
import 'services/remini_care_config.dart';
import 'theme/remini_care_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _ready = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loadError = null);
    try {
      await ReminiCareConfig.loadConfig();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _loadError = '設定讀取失敗，點此重試');
    }
  }

  String? _missingConfiguration() {
    final llm = ReminiCareConfig.getValue('selectedLlmProvider');
    final image = ReminiCareConfig.getValue('selectedImageProvider');
    final speech = ReminiCareConfig.getValue('selectedSpeechProvider');
    final llmKey = switch (llm) {
      'openai' => ReminiCareConfig.openaiApiKey,
      'gemini' => ReminiCareConfig.geminiApiKey,
      'custom' => ReminiCareConfig.getValue('CUSTOM_LLM_API_KEY'),
      _ => ReminiCareConfig.nvidiaApiKey,
    };
    final imageKey = switch (image) {
      'cloudflare' => ReminiCareConfig.getValue('CLOUDFLARE_IMAGE_APP_TOKEN'),
      'openai' => ReminiCareConfig.openaiApiKey,
      'custom' => ReminiCareConfig.getValue('CUSTOM_IMAGE_API_KEY'),
      _ => ReminiCareConfig.siliconFlowApiKey,
    };
    final speechOk = speech == 'ncku'
        ? ReminiCareConfig.nckuSttToken.isNotEmpty &&
              ReminiCareConfig.nckuTtsToken.isNotEmpty
        : ReminiCareConfig.yatingApiKey.isNotEmpty;
    if (llmKey.isEmpty) return '請設定目前 LLM Provider 的 API Key。';
    if (imageKey.isEmpty) return '請設定目前生圖 Provider 的 API Key。';
    if (!speechOk) return '請設定目前語音服務需要的 Token。';
    return ReminiCareConfig.validateProviderSettings({});
  }

  void _start() {
    final message = _missingConfiguration();
    if (message == null) {
      context.push('/life_screen');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(label: '設定', onPressed: _showSettingsDialog),
        ),
      );
    }
  }

  Future<void> _showSettingsDialog() async {
    final controllers = {
      for (final field in ReminiCareConfig.fields)
        field.apiKey: TextEditingController(
          text: ReminiCareConfig.getValue(field.apiKey),
        ),
    };
    var llm = ReminiCareConfig.getValue('selectedLlmProvider');
    var image = ReminiCareConfig.getValue('selectedImageProvider');
    var speech = ReminiCareConfig.getValue('selectedSpeechProvider');
    var fixedFlow = ReminiCareConfig.debugFixedFlow;
    var saving = false;
    String? validationError;

    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final visibleKeys = <String>{
            switch (llm) {
              'openai' => 'OPENAI_API_KEY',
              'gemini' => 'GEMINI_API_KEY',
              'custom' => 'CUSTOM_LLM_API_KEY',
              _ => 'NVIDIA_API_KEY',
            },
            switch (llm) {
              'openai' => 'OPENAI_LLM_MODEL',
              'gemini' => 'GEMINI_LLM_MODEL',
              'custom' => 'CUSTOM_LLM_MODEL',
              _ => 'NVIDIA_LLM_MODEL',
            },
            switch (image) {
              'cloudflare' => 'CLOUDFLARE_IMAGE_APP_TOKEN',
              'openai' => 'OPENAI_API_KEY',
              'custom' => 'CUSTOM_IMAGE_API_KEY',
              _ => 'SILICONFLOW_API_KEY',
            },
            if (speech == 'ncku') ...{
              'NCKU_TTS_TOKEN',
              'NCKU_STT_TOKEN',
            } else
              'YATING_API_KEY',
            'VOICE_MAX_RECORD_LIMIT',
            'VOICE_INTRO_SILENCE_SECONDS',
            'VOICE_CHAT_SILENCE_SECONDS',
            'WAKE_WORDS_START',
            'WAKE_WORDS_END',
            'WAKE_WORDS_RESTART',
            if (llm == 'custom') 'CUSTOM_LLM_BASE_URL',
            if (image == 'custom') ...{
              'CUSTOM_IMAGE_BASE_URL',
              'CUSTOM_IMAGE_MODEL',
            },
            if (image == 'cloudflare') 'CLOUDFLARE_IMAGE_WORKER_URL',
          };
          final llmPreset = switch (llm) {
            'nvidia' => 'https://integrate.api.nvidia.com/v1',
            'openai' => 'https://api.openai.com/v1',
            'gemini' =>
              'https://generativelanguage.googleapis.com/v1beta/openai',
            _ => '自訂 OpenAI-compatible 端點與模型',
          };
          final imagePreset = switch (image) {
            'cloudflare' => 'FLUX.2 Klein 4B（支援生成與改圖，透過安全 Worker）',
            'siliconflow' =>
              'https://api.siliconflow.com/v1  •  Qwen/Qwen-Image（支援改圖）',
            'openai' => 'https://api.openai.com/v1  •  gpt-image-2',
            _ => '自訂 OpenAI-compatible 端點（僅標準生成）',
          };
          return AlertDialog(
            title: const Text('ReminiCare AI 設定'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (kDebugMode)
                      SwitchListTile(
                        key: const ValueKey('debug-fixed-flow'),
                        title: const Text('固定測試流程'),
                        subtitle: const Text('固定四個主題與問題；下次進入回憶流程生效。'),
                        value: fixedFlow,
                        onChanged: saving
                            ? null
                            : (value) =>
                                  setDialogState(() => fixedFlow = value),
                      ),
                    _ProviderDropdown(
                      label: '語言模型',
                      value: llm,
                      options: const {
                        'nvidia': 'NVIDIA',
                        'openai': 'OpenAI',
                        'gemini': 'Google Gemini',
                        'custom': 'Custom OpenAI-compatible',
                      },
                      onChanged: (value) => setDialogState(() => llm = value),
                    ),
                    _ProviderInfo(label: 'LLM', value: llmPreset),
                    _ProviderDropdown(
                      label: '生圖服務',
                      value: image,
                      options: const {
                        'cloudflare': 'Cloudflare Workers AI（支援改圖）',
                        'siliconflow': 'SiliconFlow（支援改圖）',
                        'openai': 'OpenAI',
                        'custom': 'Custom OpenAI-compatible（僅生成）',
                      },
                      onChanged: (value) => setDialogState(() => image = value),
                    ),
                    _ProviderInfo(label: '生圖', value: imagePreset),
                    _ProviderDropdown(
                      label: '語音服務',
                      value: speech,
                      options: const {'yating': '雅婷', 'ncku': '成大 NCKU'},
                      onChanged: (value) =>
                          setDialogState(() => speech = value),
                    ),
                    const Divider(height: 34),
                    for (final field in ReminiCareConfig.fields.where(
                      (f) => visibleKeys.contains(f.apiKey),
                    ))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: TextField(
                          controller: controllers[field.apiKey],
                          obscureText: field.isSecure,
                          decoration: InputDecoration(
                            labelText: field.displayName,
                            hintText: field.hintText,
                            helperText: switch (field.apiKey) {
                              'VOICE_INTRO_SILENCE_SECONDS' ||
                              'VOICE_CHAT_SILENCE_SECONDS' =>
                                '開始說話後，連續安靜這段時間才自動結束；尚未說話最多等待 15 秒。',
                              'VOICE_MAX_RECORD_LIMIT' =>
                                '單次錄音總時限，與說完後等待時間分開計算。',
                              _ => null,
                            },
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    if (validationError != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          validationError!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final values = {
                          for (final entry in controllers.entries)
                            entry.key: entry.value.text,
                          if (kDebugMode)
                            ReminiCareConfig.debugFlowKey: fixedFlow.toString(),
                          'selectedLlmProvider': llm,
                          'selectedImageProvider': image,
                          'selectedSpeechProvider': speech,
                        };
                        final error = ReminiCareConfig.validateProviderSettings(
                          values,
                        );
                        if (error != null) {
                          return setDialogState(() => validationError = error);
                        }
                        setDialogState(() {
                          saving = true;
                          validationError = null;
                        });
                        try {
                          await ReminiCareConfig.saveConfig(values);
                          ApiServices().resetCache();
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        } catch (_) {
                          if (dialogContext.mounted) {
                            setDialogState(() {
                              saving = false;
                              validationError = '設定儲存失敗，原設定已保留，請重試。';
                            });
                          }
                        }
                      },
                child: Text(saving ? '儲存中…' : '儲存並套用'),
              ),
            ],
          );
        },
      ),
    );
    await Navigator.of(context, rootNavigator: true).push(route);
    // Keep text controllers alive until the dialog exit transition unmounts.
    await route.completed;
    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('ReminiCare AI'),
      actions: [
        IconButton(
          onPressed: () => context.push('/tts_cache_screen'),
          icon: const Icon(Icons.cleaning_services_rounded),
          tooltip: '語音快取',
        ),
        IconButton(
          onPressed: () => context.push('/history_screen'),
          icon: const Icon(Icons.history_rounded),
          tooltip: '回憶紀錄',
        ),
        IconButton(
          onPressed: _showSettingsDialog,
          icon: const Icon(Icons.settings_outlined),
          tooltip: '設定',
        ),
        const SizedBox(width: 72),
      ],
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(31),
                child: Image.asset(
                  'assets/images/life_home.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 30),
            Text(
              '一起聊聊以前的生活',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ReminiCareBreakpoints.titleSize(context),
              ),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _ready ? _start : (_loadError != null ? _load : null),
              style: FilledButton.styleFrom(
                backgroundColor: ReminiCareTheme.yellow,
                foregroundColor: ReminiCareTheme.ink,
                minimumSize: const Size(280, 76),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(38),
                ),
              ),
              child: Text(
                _ready ? '開始回憶' : (_loadError ?? '載入設定中…'),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProviderDropdown extends StatelessWidget {
  const _ProviderDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });
  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: DropdownButtonFormField<String>(
      initialValue: options.containsKey(value) ? value : options.keys.first,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: options.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    ),
  );
}

class _ProviderInfo extends StatelessWidget {
  const _ProviderInfo({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF5F5F5),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text('$label：$value', style: const TextStyle(fontSize: 13)),
  );
}
