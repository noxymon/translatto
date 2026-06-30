// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screen_translate/ocr_service.dart';
import 'package:screen_translate/translation_service.dart';
import 'package:screen_translate/capture_service.dart';
import 'package:screen_translate/overlay_painter.dart';
import 'package:screen_translate/overlay_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  OverlayBridge.init();

  final prefs = await SharedPreferences.getInstance();
  final themeStr = prefs.getString("theme_mode") ?? "dark";
  final themeMode = ThemeMode.values.firstWhere(
    (e) => e.name == themeStr,
    orElse: () => ThemeMode.dark,
  );
  themeNotifier.value = themeMode;

  final targetLang = prefs.getString("target_language") ?? "English";
  targetLanguageNotifier.value = targetLang;

  final engine = prefs.getString("translation_engine") ?? "local";
  translationEngineNotifier.value = engine;
  final apiKey = prefs.getString("deepseek_api_key") ?? "";
  deepseekApiKeyNotifier.value = apiKey;

  // Start listener and model init in the background; UI starts immediately.
  unawaited(_initServicesAndListenForCapture());
  runApp(const MyApp());
}

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  OverlayBridge.init();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: OverlayWindowScreen(),
  ));
}

final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);
final targetLanguageNotifier = ValueNotifier<String>("English");
final translationEngineNotifier = ValueNotifier<String>("local"); // "local" or "cloud"
final deepseekApiKeyNotifier = ValueNotifier<String>("");

const List<String> supportedLanguages = [
  "English",
  "Indonesia",
  "Indonesian",
  "Japanese",
  "Chinese",
  "French",
  "Spanish",
  "German",
  "Italian",
  "Korean",
  "Portuguese",
  "Russian",
  "Hindi",
  "Arabic",
  "Vietnamese",
];

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'Screen Translator',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: const Color(0xff1e90ff),
            scaffoldBackgroundColor: const Color(0xfff5f5f5),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xff1e90ff),
              foregroundColor: Colors.white,
            ),
            colorScheme: const ColorScheme.light(
              primary: Color(0xff1e90ff),
              secondary: Color(0xff00bfff),
              surface: Colors.white,
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: const Color(0xff89b4fa),
            scaffoldBackgroundColor: const Color(0xff181825),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xff1e1e2e),
            ),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xff89b4fa),
              secondary: Color(0xffcba6f7),
              surface: Color(0xff1e1e2e),
            ),
          ),
          themeMode: themeMode,
          home: const MainDashboardScreen(),
        );
      },
    );
  }
}

final _ocrService = OcrService();
final _translationService = TranslationService();
final _captureService = CaptureService();

/// Notifies the dashboard UI of model load state changes.
final _modelStatusNotifier = ValueNotifier<({bool ready, String message})>(
  (ready: false, message: "Checking local model..."),
);

bool _isTranslationInProgress = false;
bool _cancelRequested = false;

Future<void> _runTranslationFlowAndSendToOverlay() async {
  if (!_modelStatusNotifier.value.ready) {
    await OverlayBridge.send({
      "status": "error",
      "message": "Translation engine not ready. Please open the main app dashboard.",
    });
    return;
  }

  if (_isTranslationInProgress) {
    debugPrint("[Main] Translation already in progress. Ignoring request.");
    return;
  }
  _isTranslationInProgress = true;
  _cancelRequested = false;
  debugPrint("[Main] Capture request received. Starting translation flow.");

  try {
    if (_cancelRequested) return;
    final captureData = await _captureService.captureScreen();
    if (_cancelRequested) return;
    await OverlayBridge.send({"status": "capturing_done"});
    if (_cancelRequested) return;

    if (captureData == null) {
      debugPrint("[Main] captureScreen() returned null.");
      await OverlayBridge.send({"status": "no_text"});
      return;
    }

    final path = captureData['path'] as String;
    final imageWidth = (captureData['width'] as num).toDouble();
    final imageHeight = (captureData['height'] as num).toDouble();
    final cropY = (captureData['cropY'] as num?)?.toDouble() ?? 0.0;
    debugPrint("[Main] Screen captured: $path ($imageWidth x $imageHeight) cropY=$cropY");

    final ocrBlocks = await _ocrService.extractText(path);
    if (_cancelRequested) return;
    debugPrint("[Main] OCR found ${ocrBlocks.length} blocks.");
    if (ocrBlocks.isEmpty) {
      await OverlayBridge.send({"status": "no_text"});
      return;
    }

    final List<OcrBlock> blocksToTranslate = ocrBlocks.where((b) => b.text.trim().isNotEmpty).toList();

    if (blocksToTranslate.isEmpty) {
      debugPrint("[Main] No text blocks detected.");
      await OverlayBridge.send({"status": "no_text"});
      return;
    }

    final blockRecords = blocksToTranslate.map((b) => (
      text: b.text,
      x: b.boundingBox.left.toInt(),
      y: b.boundingBox.top.toInt(),
      sourceLanguage: b.recognizedLanguage,
    )).toList();
    final translatedTexts = await _translationService.translateBatch(
      blockRecords,
      targetLanguage: targetLanguageNotifier.value,
      isCancelled: () => _cancelRequested,
    );
    if (_cancelRequested) return;
    debugPrint("[Main] Translated ${translatedTexts.length} blocks.");

    final List<Map<String, dynamic>> list = [];
    for (int i = 0; i < blocksToTranslate.length; i++) {
      final block = blocksToTranslate[i];
      final rect = block.boundingBox;
      final text = (i < translatedTexts.length && translatedTexts[i].isNotEmpty)
          ? translatedTexts[i]
          : block.text;
      final originalLineCount = block.text.split('\n').length;
      list.add({
        'text': text,
        'rect': [rect.left, rect.top, rect.right, rect.bottom],
        'originalLineCount': originalLineCount,
      });
    }

    await OverlayBridge.send({
      "status": "success",
      "translations": list,
      "imageWidth": imageWidth,
      "imageHeight": imageHeight,
      "cropY": cropY,
    });
  } catch (e) {
    if (_cancelRequested) {
      debugPrint("[Main] Translation flow clean abort due to cancellation.");
      return;
    }
    debugPrint("[Main] Translation flow error: $e");
    await OverlayBridge.send({
      "status": "error",
      "message": "Capture failed: ${e.toString()}",
    });
  } finally {
    _isTranslationInProgress = false;
  }
}

Future<void> _initServicesAndListenForCapture() async {
  debugPrint("[Main] _initServicesAndListenForCapture() called — setting up OverlayBridge listener now.");
  // Set listener FIRST — before any await — so it's active as early as possible.
  OverlayBridge.messages.listen(
    (data) async {
      debugPrint("[Main] OverlayBridge received: $data (type: ${data.runtimeType})");
      if (data == "capture") {
        await _runTranslationFlowAndSendToOverlay();
      } else if (data == "cancel") {
        _cancelRequested = true;
      } else if (data == "stop_and_exit") {
        await FlutterOverlayWindow.closeOverlay();
        await _captureService.stopCaptureSession();
        exit(0);
      } else if (data == "overlay_ready") {
        OverlayBridge.send({"status": "theme_changed", "theme": themeNotifier.value.name});
        OverlayBridge.send({"status": "language_changed", "language": targetLanguageNotifier.value});
      }
    },
    onError: (e) => debugPrint("[Main] OverlayBridge error: $e"),
    onDone: () => debugPrint("[Main] OverlayBridge stream closed!"),
  );
  themeNotifier.addListener(() {
    OverlayBridge.send({"status": "theme_changed", "theme": themeNotifier.value.name});
  });
  targetLanguageNotifier.addListener(() {
    OverlayBridge.send({"status": "language_changed", "language": targetLanguageNotifier.value});
  });
  debugPrint("[Main] OverlayBridge.messages.listen() registered.");

  if (translationEngineNotifier.value == "cloud") {
    final apiKey = deepseekApiKeyNotifier.value;
    if (apiKey.isNotEmpty) {
      _translationService.configureCloud(apiKey: apiKey);
      _modelStatusNotifier.value = (ready: true, message: "Cloud translation ready (DeepSeek v4 Flash).");
      debugPrint("[Main] Cloud translation configured.");
    } else {
      _modelStatusNotifier.value = (ready: false, message: "Cloud mode selected but no API key set.\nGo to Settings to add your DeepSeek API key.");
    }
  } else {
    final docDir = await getApplicationDocumentsDirectory();
    final modelPath = "${docDir.path}/gemma-4-E2B-it.litertlm";
    final modelExists = await File(modelPath).exists();

    if (modelExists) {
      try {
        _modelStatusNotifier.value = (ready: false, message: "Loading local model into memory...");
        final board = await _captureService.getDeviceBoard();
        await _translationService.init(modelPath, deviceBoard: board);
        _modelStatusNotifier.value = (ready: true, message: "Local model loaded and ready.");
        debugPrint("[Main] Model initialized successfully.");
      } catch (e) {
        _modelStatusNotifier.value = (ready: false, message: "Failed to load model: $e");
      }
    } else {
      _modelStatusNotifier.value = (
        ready: false,
        message: "Local Model Missing!\nPlace 'gemma-4-E2B-it.litertlm' (2.58 GB) in documents folder:\n$modelPath",
      );
    }
  }
}

class MainDashboardScreen extends StatefulWidget {
  const MainDashboardScreen({super.key});

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> {
  bool _overlayPermissionGranted = false;
  bool _isOverlayRunning = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _syncOverlayState();
  }

  Future<void> _syncOverlayState() async {
    final active = await FlutterOverlayWindow.isActive();
    if (mounted) setState(() => _isOverlayRunning = active);
  }

  Future<void> _checkPermissions() async {
    final granted = await FlutterOverlayWindow.isPermissionGranted();
    setState(() {
      _overlayPermissionGranted = granted;
    });
  }

  Future<void> _requestPermission() async {
    final granted = await FlutterOverlayWindow.requestPermission();
    setState(() {
      _overlayPermissionGranted = granted ?? false;
    });
  }

  Future<void> _toggleOverlay() async {
    if (!_overlayPermissionGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please grant overlay permissions first")),
      );
      return;
    }

    if (_isOverlayRunning) {
      await FlutterOverlayWindow.closeOverlay();
      await _captureService.stopCaptureSession();
      setState(() {
        _isOverlayRunning = false;
      });
    } else {
      final double devicePixelRatio = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
      final int sizePx = (140 * devicePixelRatio).round();

      // Start projection capture session first. Shows casting permission prompt.
      final success = await _captureService.startCaptureSession();
      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Screen capture permission denied")),
          );
        }
        return;
      }

      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        flag: OverlayFlag.defaultFlag,
        alignment: OverlayAlignment.centerRight,
        height: sizePx,
        width: sizePx,
      );
      setState(() {
        _isOverlayRunning = true;
      });
      await _captureService.minimizeApp();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Screen Translator"),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Model Status Info Card
              ValueListenableBuilder(
                valueListenable: _modelStatusNotifier,
                builder: (context, status, _) {
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: status.ready ? const Color(0xffa6e3a1) : const Color(0xfff38ba8),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          status.ready ? Icons.check_circle : Icons.warning,
                          size: 48,
                          color: status.ready ? const Color(0xffa6e3a1) : const Color(0xfff38ba8),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          "Translation Model Status",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          status.message,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: status.ready 
                                ? (Theme.of(context).brightness == Brightness.dark 
                                    ? const Color(0xffa6adc8) 
                                    : Colors.black87) 
                                : const Color(0xfff38ba8),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              // Translator Details Card
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      ValueListenableBuilder<String>(
                        valueListenable: translationEngineNotifier,
                        builder: (context, engine, _) {
                          return Text(
                            engine == "cloud" ? "Cloud Model (DeepSeek)" : "Local Model (Gemma)",
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Translate to:", style: TextStyle(fontSize: 14)),
                          ValueListenableBuilder<String>(
                            valueListenable: targetLanguageNotifier,
                            builder: (context, targetLang, _) {
                              return DropdownButton<String>(
                                value: targetLang,
                                dropdownColor: Theme.of(context).colorScheme.surface,
                                onChanged: (newLang) async {
                                  if (newLang != null) {
                                    targetLanguageNotifier.value = newLang;
                                    final prefs = await SharedPreferences.getInstance();
                                    await prefs.setString("target_language", newLang);
                                  }
                                },
                                items: supportedLanguages.map((lang) {
                                  return DropdownMenuItem<String>(
                                    value: lang,
                                    child: Text(lang),
                                  );
                                }).toList(),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _overlayPermissionGranted ? null : _requestPermission,
                icon: const Icon(Icons.security),
                label: Text(_overlayPermissionGranted ? "Overlay Permission Granted" : "Grant Overlay Permission"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xffa6e3a1),
                  foregroundColor: const Color(0xff11111b),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _toggleOverlay,
                icon: Icon(_isOverlayRunning ? Icons.stop : Icons.play_arrow),
                label: Text(_isOverlayRunning ? "Stop Screen Overlay" : "Start Screen Overlay"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: _isOverlayRunning ? const Color(0xfff38ba8) : const Color(0xff89b4fa),
                  foregroundColor: const Color(0xff11111b),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

class OverlayWindowScreen extends StatefulWidget {
  const OverlayWindowScreen({super.key});

  @override
  State<OverlayWindowScreen> createState() => _OverlayWindowScreenState();
}

class _OverlayWindowScreenState extends State<OverlayWindowScreen> {
  bool _isTranslating = false;
  bool _showTranslationLayer = false;
  List<TranslatedBlock> _translations = [];
  Size _imageSize = Size.zero;
  double _cropY = 0.0;
  bool _showMenu = false;
  StreamSubscription? _overlaySubscription;
  String? _errorMessage;
  Timer? _errorTimer;
  Timer? _translationTimeoutTimer;
  ThemeMode _themeMode = ThemeMode.dark;
  String _targetLanguage = "English";

  @override
  void initState() {
    super.initState();
    // Listen to translation results shared by the main app isolate via custom bridge
    _overlaySubscription = OverlayBridge.messages.listen((data) {
      if (data is Map && data["status"] == "theme_changed") {
        final themeStr = data["theme"] as String?;
        if (themeStr != null) {
          setState(() {
            _themeMode = ThemeMode.values.firstWhere(
              (e) => e.name == themeStr,
              orElse: () => ThemeMode.dark,
            );
          });
        }
        return;
      }
      if (data is Map && data["status"] == "language_changed") {
        final language = data["language"] as String?;
        if (language != null) {
          setState(() {
            _targetLanguage = language;
          });
        }
        return;
      }
      if (data is Map && data["status"] == "capturing_done") {
        // Do not cancel timeout timer yet; only capture is done, translation is starting.
      } else {
        _translationTimeoutTimer?.cancel();
      }
      if (data is Map) {
        if (data["status"] == "capturing_done") {
          setState(() {
            _isTranslating = true;
          });
          FlutterOverlayWindow.resizeOverlay(140, 140, false);
        } else if (data["status"] == "no_text") {
          setState(() {
            _isTranslating = false;
            _translations = [];
            _showTranslationLayer = false;
            _errorMessage = "No text detected.";
          });
          _errorTimer?.cancel();
          _errorTimer = Timer(const Duration(seconds: 4), () {
            if (mounted) {
              setState(() {
                _errorMessage = null;
              });
            }
          });
          FlutterOverlayWindow.resizeOverlay(140, 140, true);
        } else if (data["status"] == "no_japanese_text") {
          setState(() {
            _isTranslating = false;
            _translations = [];
            _showTranslationLayer = false;
            _errorMessage = "No Japanese text detected.";
          });
          _errorTimer?.cancel();
          _errorTimer = Timer(const Duration(seconds: 4), () {
            if (mounted) {
              setState(() {
                _errorMessage = null;
              });
            }
          });
          FlutterOverlayWindow.resizeOverlay(140, 140, true);
        } else if (data["status"] == "error") {
          setState(() {
            _isTranslating = false;
            _translations = [];
            _showTranslationLayer = false;
            _errorMessage = data["message"] as String?;
          });
          _errorTimer?.cancel();
          _errorTimer = Timer(const Duration(seconds: 4), () {
            if (mounted) {
              setState(() {
                _errorMessage = null;
              });
            }
          });
          FlutterOverlayWindow.resizeOverlay(140, 140, true);
        } else if (data["status"] == "success") {
          final list = (data["translations"] as List).map((item) {
            final rectList = item["rect"] as List;
            return TranslatedBlock(
              text: item["text"] as String,
              rect: Rect.fromLTRB(
                (rectList[0] as num).toDouble(),
                (rectList[1] as num).toDouble(),
                (rectList[2] as num).toDouble(),
                (rectList[3] as num).toDouble(),
              ),
              originalLineCount: (item["originalLineCount"] as num?)?.toInt() ?? 1,
            );
          }).toList();

          final double imageWidth = (data["imageWidth"] as num).toDouble();
          final double imageHeight = (data["imageHeight"] as num).toDouble();
          final double cropY = (data["cropY"] as num?)?.toDouble() ?? 0.0;

          setState(() {
            _isTranslating = false;
            _translations = list;
            _imageSize = Size(imageWidth, imageHeight);
            _cropY = cropY;
            _showTranslationLayer = true;
            _errorMessage = null;
          });

          // Resize overlay size to fullscreen to display translations using positive logical dimensions
          // to bypass the typo bug in flutter_overlay_window which causes a crash with negative inputs.
          if (!mounted) return;
          final double devicePixelRatio = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
          final int widthDp = (imageWidth / devicePixelRatio).round();
          final int heightDp = ((imageHeight + cropY) / devicePixelRatio).round();
          FlutterOverlayWindow.resizeOverlay(widthDp, heightDp, false);
          FlutterOverlayWindow.moveOverlay(const OverlayPosition(0, 0));
        }
      }
    });
    OverlayBridge.send("overlay_ready");
  }

  @override
  void dispose() {
    _overlaySubscription?.cancel();
    _errorTimer?.cancel();
    _translationTimeoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _startTranslationFlow() async {
    debugPrint("[Overlay] _startTranslationFlow() called. _isTranslating=$_isTranslating");
    if (_isTranslating) {
      await _cancelTranslationFlow();
      return;
    }
    setState(() {
      _isTranslating = true;
      _errorMessage = null;
    });

    // Start a 120-second request watchdog timeout to prevent perpetual spinner if the main app is dead/killed
    _translationTimeoutTimer?.cancel();
    _translationTimeoutTimer = Timer(const Duration(seconds: 120), () {
      if (mounted && _isTranslating) {
        setState(() {
          _isTranslating = false;
          _errorMessage = "Timeout. Please open the main app.";
        });
        FlutterOverlayWindow.resizeOverlay(140, 140, true);
        _errorTimer?.cancel();
        _errorTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) {
            setState(() {
              _errorMessage = null;
            });
          }
        });
      }
    });

    // Immediately resize overlay to 1x1 on start of translation flow
    try {
      await FlutterOverlayWindow.resizeOverlay(1, 1, false);
    } catch (e) {
      debugPrint("[Overlay] Failed to resize overlay: $e");
    }

    // Wait 100 milliseconds
    await Future.delayed(const Duration(milliseconds: 100));

    if (!_isTranslating) {
      debugPrint("[Overlay] Translation flow was cancelled before capture request was sent.");
      return;
    }

    // Request translation from the main app isolate
    debugPrint("[Overlay] Calling OverlayBridge.send('capture') for target language: $_targetLanguage...");
    try {
      await OverlayBridge.send("capture");
      debugPrint("[Overlay] OverlayBridge.send('capture') completed");
    } catch (e) {
      debugPrint("[Overlay] OverlayBridge.send ERROR: $e");
      if (mounted) {
        setState(() {
          _isTranslating = false;
          _errorMessage = "Main app not active.";
        });
        _errorTimer?.cancel();
        _errorTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) {
            setState(() {
              _errorMessage = null;
            });
          }
        });
        await FlutterOverlayWindow.resizeOverlay(140, 140, true);
      }
    }
  }

  Future<void> _cancelTranslationFlow() async {
    debugPrint("[Overlay] Cancelling translation flow.");
    _translationTimeoutTimer?.cancel();
    setState(() {
      _isTranslating = false;
    });
    try {
      await FlutterOverlayWindow.resizeOverlay(140, 140, true);
    } catch (e) {
      debugPrint("[Overlay] Failed to resize overlay: $e");
    }
    try {
      await OverlayBridge.send("cancel");
    } catch (e) {
      debugPrint("[Overlay] Failed to send cancel request: $e");
    }
  }

  Future<void> _closeTranslationLayer() async {
    setState(() {
      _showTranslationLayer = false;
      _translations = [];
      _cropY = 0.0;
    });
    // Restore window layout back to small FAB trigger dimensions
    await FlutterOverlayWindow.resizeOverlay(140, 140, true);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark;
    if (_themeMode == ThemeMode.system) {
      isDark = MediaQuery.of(context).platformBrightness == Brightness.dark;
    } else {
      isDark = _themeMode == ThemeMode.dark;
    }

    final Color bgColor = isDark ? const Color(0xff1e1e2e) : const Color(0xffffffff);
    final Color accentColor = isDark ? const Color(0xff89b4fa) : const Color(0xff1e90ff);
    final Color errorColor = isDark ? const Color(0xfff38ba8) : const Color(0xffd20f39);
    final Color errorIconColor = isDark ? const Color(0xff11111b) : Colors.white;
    final Color backIconColor = isDark ? Colors.grey : Colors.grey[700]!;

    if (_showMenu) {
      return Material(
        color: Colors.transparent,
        child: Center(
          child: Container(
            width: 170,
            height: 70,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: bgColor.withAlpha(240),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accentColor, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(128),
                  blurRadius: 8,
                  spreadRadius: 2,
                )
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: backIconColor, size: 24),
                  onPressed: () {
                    setState(() {
                      _showMenu = false;
                    });
                    FlutterOverlayWindow.resizeOverlay(140, 140, true);
                  },
                  tooltip: 'Back',
                ),
                IconButton(
                  icon: Icon(Icons.open_in_new, color: accentColor, size: 24),
                  onPressed: () {
                    OverlayBridge.send("open_app");
                    setState(() {
                      _showMenu = false;
                    });
                    FlutterOverlayWindow.resizeOverlay(140, 140, true);
                  },
                  tooltip: 'Go to Main App',
                ),
                IconButton(
                  icon: Icon(Icons.exit_to_app, color: errorColor, size: 24),
                  onPressed: () async {
                    try {
                      await OverlayBridge.send("stop_and_exit");
                    } catch (_) {}
                    await FlutterOverlayWindow.closeOverlay();
                    exit(0);
                  },
                  tooltip: 'Stop & Exit',
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_showTranslationLayer) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! < -300) {
            _closeTranslationLayer();
          }
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: OverlayPainter(
                    translations: _translations,
                    imageSize: _imageSize,
                    cropY: _cropY,
                  ),
                ),
              ),
              Positioned(
                bottom: 24,
                right: 24,
                child: FloatingActionButton(
                  mini: true,
                  backgroundColor: errorColor,
                  foregroundColor: errorIconColor,
                  onPressed: _closeTranslationLayer,
                  child: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Center(
            child: GestureDetector(
              onTap: _startTranslationFlow,
              onLongPress: () async {
                setState(() {
                  _showMenu = true;
                });
                await FlutterOverlayWindow.resizeOverlay(180, 90, false);
              },
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: bgColor.withAlpha(230),
                  shape: BoxShape.circle,
                  border: Border.all(color: accentColor, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(128),
                      blurRadius: 10,
                      spreadRadius: 2,
                    )
                  ]
                ),
                child: Center(
                  child: _isTranslating
                      ? SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            color: accentColor,
                            strokeWidth: 3,
                          ),
                        )
                      : Icon(Icons.translate, size: 36, color: accentColor),
                ),
              ),
            ),
          ),
          if (_errorMessage != null)
            Positioned(
              bottom: 0,
              left: 5,
              right: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: errorColor.withAlpha(230),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  bool _isBatteryOptimizedIgnored = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkBatteryStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkBatteryStatus();
    }
  }

  Future<void> _checkBatteryStatus() async {
    final status = await _captureService.isIgnoringBatteryOptimizations();
    if (mounted) {
      setState(() {
        _isBatteryOptimizedIgnored = status;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Appearance",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeNotifier,
                  builder: (context, currentMode, _) {
                    return Column(
                      children: [
                        RadioListTile<ThemeMode>(
                          title: const Text("Dark Theme"),
                          value: ThemeMode.dark,
                          groupValue: currentMode,
                          onChanged: (mode) async {
                            if (mode != null) {
                              themeNotifier.value = mode;
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setString("theme_mode", mode.name);
                            }
                          },
                        ),
                        const Divider(height: 1),
                        RadioListTile<ThemeMode>(
                          title: const Text("Light Theme"),
                          value: ThemeMode.light,
                          groupValue: currentMode,
                          onChanged: (mode) async {
                            if (mode != null) {
                              themeNotifier.value = mode;
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setString("theme_mode", mode.name);
                            }
                          },
                        ),
                        const Divider(height: 1),
                        RadioListTile<ThemeMode>(
                          title: const Text("System Default"),
                          value: ThemeMode.system,
                          groupValue: currentMode,
                          onChanged: (mode) async {
                            if (mode != null) {
                              themeNotifier.value = mode;
                              final prefs = await SharedPreferences.getInstance();
                              await prefs.setString("theme_mode", mode.name);
                            }
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "Translation Engine",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ValueListenableBuilder<String>(
                  valueListenable: translationEngineNotifier,
                  builder: (context, engine, _) {
                    return Column(
                      children: [
                        RadioListTile<String>(
                          title: const Text("Local Model (Gemma 2B)"),
                          subtitle: const Text("Offline, on-device translation", style: TextStyle(fontSize: 12)),
                          value: "local",
                          groupValue: engine,
                          onChanged: (v) async {
                            if (v == null) return;
                            translationEngineNotifier.value = v;
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString("translation_engine", v);
                            _translationService.configureLocal();
                            _modelStatusNotifier.value = (ready: false, message: "Switched to local model. Restart required.");
                          },
                        ),
                        const Divider(height: 1),
                        RadioListTile<String>(
                          title: const Text("Cloud API (DeepSeek)"),
                          subtitle: const Text("Fast, high-quality. Requires API key.", style: TextStyle(fontSize: 12)),
                          value: "cloud",
                          groupValue: engine,
                          onChanged: (v) async {
                            if (v == null) return;
                            translationEngineNotifier.value = v;
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString("translation_engine", v);
                            final apiKey = deepseekApiKeyNotifier.value;
                            if (apiKey.isNotEmpty) {
                              _translationService.configureCloud(apiKey: apiKey);
                              _modelStatusNotifier.value = (ready: true, message: "Cloud translation ready (DeepSeek v4 Flash).");
                            } else {
                              _modelStatusNotifier.value = (ready: false, message: "Cloud mode selected but no API key set.");
                            }
                          },
                        ),
                        if (engine == "cloud")
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: ValueListenableBuilder<String>(
                              valueListenable: deepseekApiKeyNotifier,
                              builder: (context, apiKey, _) {
                                return TextField(
                                  obscureText: true,
                                  decoration: const InputDecoration(
                                    labelText: "DeepSeek API Key",
                                    hintText: "sk-...",
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  controller: TextEditingController(text: apiKey),
                                  onChanged: (value) async {
                                    deepseekApiKeyNotifier.value = value;
                                    final prefs = await SharedPreferences.getInstance();
                                    await prefs.setString("deepseek_api_key", value);
                                    if (value.isNotEmpty && translationEngineNotifier.value == "cloud") {
                                      _translationService.configureCloud(apiKey: value);
                                      _modelStatusNotifier.value = (ready: true, message: "Cloud translation ready (DeepSeek v4 Flash).");
                                    } else if (value.isEmpty && translationEngineNotifier.value == "cloud") {
                                      _modelStatusNotifier.value = (ready: false, message: "Cloud mode selected but no API key set.");
                                    }
                                  },
                                );
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "Background Execution",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: Icon(
                    _isBatteryOptimizedIgnored ? Icons.battery_charging_full : Icons.battery_alert,
                    color: _isBatteryOptimizedIgnored ? const Color(0xffa6e3a1) : const Color(0xfff38ba8),
                  ),
                  title: const Text("Battery Optimization"),
                  subtitle: Text(
                    _isBatteryOptimizedIgnored
                        ? "Excluded (App can run reliably in background)"
                        : "Optimized (Click to request exclusion)",
                    style: TextStyle(
                      fontSize: 12,
                      color: _isBatteryOptimizedIgnored ? const Color(0xffa6e3a1) : const Color(0xfff38ba8),
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await _captureService.requestIgnoreBatteryOptimizations();
                  },
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "Miscellaneous",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.feedback),
                      title: const Text("Feedback"),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _captureService.sendFeedback("1.0.0+1"),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.share),
                      title: const Text("Share the App"),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _captureService.shareApp(),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.star_rate),
                      title: const Text("Rate this App"),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _captureService.rateApp(),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.privacy_tip),
                      title: const Text("Privacy Policy"),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _captureService.openPrivacyPolicy(),
                    ),
                    const Divider(height: 1),
                    const ListTile(
                      leading: Icon(Icons.info),
                      title: Text("App Version"),
                      trailing: Text(
                        "1.0.0 (1)",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}