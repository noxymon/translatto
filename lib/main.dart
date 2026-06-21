import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screen_translate/ocr_service.dart';
import 'package:screen_translate/translation_service.dart';
import 'package:screen_translate/capture_service.dart';
import 'package:screen_translate/overlay_painter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: OverlayWindowScreen(),
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Screen Translator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xff89b4fa),
        scaffoldBackgroundColor: const Color(0xff181825),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xff89b4fa),
          secondary: Color(0xffcba6f7),
          surface: Color(0xff1e1e2e),
        ),
      ),
      home: const MainDashboardScreen(),
    );
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
  bool _isModelReady = false;
  String _modelStatusMessage = "Checking Gemma model...";
  
  final _ocrService = OcrService();
  final _translationService = TranslationService();
  final _captureService = CaptureService();
  StreamSubscription? _mainListenerSubscription;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _initServices();
  }

  Future<void> _initServices() async {
    // 1. Check current overlay active state to synchronize dashboard button state
    final active = await FlutterOverlayWindow.isActive();
    setState(() {
      _isOverlayRunning = active;
    });

    // 2. Resolve local documents directory for model path to avoid Android crash
    final docDir = await getApplicationDocumentsDirectory();
    final modelPath = "${docDir.path}/gemma-4-E2B-it.litertlm";
    final modelExists = await File(modelPath).exists();
    
    if (modelExists) {
      try {
        setState(() {
          _modelStatusMessage = "Loading Gemma model into memory...";
        });
        await _translationService.init(modelPath);
        setState(() {
          _isModelReady = true;
          _modelStatusMessage = "Gemma model loaded and ready.";
        });
      } catch (e) {
        setState(() {
          _isModelReady = false;
          _modelStatusMessage = "Failed to load model: $e";
        });
      }
    } else {
      setState(() {
        _isModelReady = false;
        _modelStatusMessage = "Gemma Model Missing!\nPlace 'gemma-4-E2B-it.litertlm' (2.58 GB) in documents folder:\n$modelPath";
      });
    }

    // 3. Listen to capture requests sent from the overlay window isolate
    _mainListenerSubscription = FlutterOverlayWindow.overlayListener.listen((data) async {
      if (data == "capture") {
        await _runTranslationFlowAndSendToOverlay();
      }
    });
  }

  Future<void> _runTranslationFlowAndSendToOverlay() async {
    if (!_isModelReady) {
      await FlutterOverlayWindow.shareData({
        "status": "error",
        "message": "Gemma model not ready. Please open the main app dashboard.",
      });
      return;
    }

    try {
      final path = await _captureService.captureScreen();
      if (path == null) {
        await FlutterOverlayWindow.shareData({"status": "no_text"});
        return;
      }

      final ocrBlocks = await _ocrService.extractText(path);
      if (ocrBlocks.isEmpty) {
        await FlutterOverlayWindow.shareData({"status": "no_text"});
        return;
      }

      // Get screen physical dimensions dynamically
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final physicalSize = view.physicalSize;

      // Important fix: Translate blocks SEQUENTIALLY to prevent concurrent LiteRT inference crash/OOM
      final List<Map<String, dynamic>> list = [];
      for (final block in ocrBlocks) {
        try {
          final translatedText = await _translationService.translate(block.text);
          final rect = block.boundingBox;
          list.add({
            'text': translatedText,
            'rect': [rect.left, rect.top, rect.right, rect.bottom],
          });
        } catch (e) {
          debugPrint("Failed to translate block: ${block.text}, error: $e");
          // Brittle recovery: Fallback to original Japanese text so screen overlay doesn't crash completely
          final rect = block.boundingBox;
          list.add({
            'text': block.text,
            'rect': [rect.left, rect.top, rect.right, rect.bottom],
          });
        }
      }

      await FlutterOverlayWindow.shareData({
        "status": "success",
        "translations": list,
        "imageWidth": physicalSize.width,
        "imageHeight": physicalSize.height,
      });

    } catch (e) {
      debugPrint("Translation flow error in main isolate: $e");
      await FlutterOverlayWindow.shareData({
        "status": "error",
        "message": "Capture failed: ${e.toString()}",
      });
    }
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
        height: 120,
        width: 120,
      );
      setState(() {
        _isOverlayRunning = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gemma Screen Translator"),
        backgroundColor: const Color(0xff1e1e2e),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Model Status Info Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xff1e1e2e),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isModelReady ? const Color(0xffa6e3a1) : const Color(0xfff38ba8),
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    _isModelReady ? Icons.check_circle : Icons.warning,
                    size: 48,
                    color: _isModelReady ? const Color(0xffa6e3a1) : const Color(0xfff38ba8),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Translation Model Status",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _modelStatusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _isModelReady ? const Color(0xffa6adc8) : const Color(0xfff38ba8),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Translator Details Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xff1e1e2e),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xff313244)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.translate, size: 48, color: Color(0xff89b4fa)),
                  SizedBox(height: 12),
                  Text(
                    "Japanese to English",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 6),
                  Text(
                    "Offline Gemma 4 LiteRT-LM translation",
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
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
    );
  }

  @override
  void dispose() {
    _mainListenerSubscription?.cancel();
    _ocrService.dispose();
    _translationService.dispose();
    _captureService.stopCaptureSession();
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
  StreamSubscription? _overlaySubscription;
  String? _errorMessage;
  Timer? _errorTimer;

  @override
  void initState() {
    super.initState();
    // Listen to translation results shared by the main app isolate
    _overlaySubscription = FlutterOverlayWindow.overlayListener.listen((data) {
      if (data is Map) {
        if (data["status"] == "no_text") {
          setState(() {
            _isTranslating = false;
            _translations = [];
            _showTranslationLayer = false;
            _errorMessage = null;
          });
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
            );
          }).toList();

          setState(() {
            _isTranslating = false;
            _translations = list;
            _imageSize = Size(
              (data["imageWidth"] as num).toDouble(),
              (data["imageHeight"] as num).toDouble(),
            );
            _showTranslationLayer = true;
            _errorMessage = null;
          });

          // Resize overlay size to fullscreen to display translations
          FlutterOverlayWindow.resizeOverlay(-1, -1, false);
        }
      }
    });
  }

  @override
  void dispose() {
    _overlaySubscription?.cancel();
    _errorTimer?.cancel();
    super.dispose();
  }

  Future<void> _startTranslationFlow() async {
    if (_isTranslating) return;
    setState(() {
      _isTranslating = true;
      _errorMessage = null;
    });
    // Request translation from the main app isolate
    await FlutterOverlayWindow.shareData("capture");
  }

  Future<void> _closeTranslationLayer() async {
    setState(() {
      _showTranslationLayer = false;
      _translations = [];
    });
    // Restore window layout back to small FAB trigger dimensions
    await FlutterOverlayWindow.resizeOverlay(120, 120, true);
  }

  @override
  Widget build(BuildContext context) {
    if (_showTranslationLayer) {
      return GestureDetector(
        onTap: _closeTranslationLayer,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: CustomPaint(
            size: Size.infinite,
            painter: OverlayPainter(
              translations: _translations,
              imageSize: _imageSize,
            ),
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
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xff1e1e2e).withAlpha(230),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xff89b4fa), width: 3),
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
                      ? const CircularProgressIndicator(color: Color(0xff89b4fa))
                      : const Icon(Icons.g_translate, color: Color(0xff89b4fa), size: 36),
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
                  color: const Color(0xfff38ba8).withAlpha(230),
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
