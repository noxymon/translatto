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
  
  final _ocrService = OcrService();
  final _translationService = TranslationService();
  final _captureService = CaptureService();

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _initServices();
  }

  Future<void> _initServices() async {
    // 1. Resolve local documents directory for model path to avoid Android crash
    final docDir = await getApplicationDocumentsDirectory();
    final modelPath = "${docDir.path}/gemma-4-E2B-it.litertlm";
    
    // 2. Warm up translation service in main isolate
    await _translationService.init(modelPath);

    // 3. Listen to capture requests sent from the overlay window isolate
    FlutterOverlayWindow.overlayListener.listen((data) async {
      if (data == "capture") {
        await _runTranslationFlowAndSendToOverlay();
      }
    });
  }

  Future<void> _runTranslationFlowAndSendToOverlay() async {
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

      final List<Map<String, dynamic>> list = [];
      for (final block in ocrBlocks) {
        final translatedText = await _translationService.translate(block.text);
        final rect = block.boundingBox;
        list.add({
          'text': translatedText,
          'rect': [rect.left, rect.top, rect.right, rect.bottom],
        });
      }

      await FlutterOverlayWindow.shareData({
        "status": "success",
        "translations": list,
        "imageWidth": physicalSize.width,
        "imageHeight": physicalSize.height,
      });

    } catch (e) {
      debugPrint("Translation flow error in main isolate: $e");
      await FlutterOverlayWindow.shareData({"status": "no_text"});
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
      setState(() {
        _isOverlayRunning = false;
      });
    } else {
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
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xff1e1e2e),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xff313244)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.translate, size: 64, color: Color(0xff89b4fa)),
                  SizedBox(height: 16),
                  Text(
                    "Japanese to English",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Offline Gemma 4 LiteRT-LM translation",
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: _overlayPermissionGranted ? null : _requestPermission,
              icon: const Icon(Icons.security),
              label: Text(_overlayPermissionGranted ? "Permission Granted" : "Grant Overlay Permission"),
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
    _ocrService.dispose();
    _translationService.dispose();
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

  @override
  void initState() {
    super.initState();
    // Listen to translation results shared by the main app isolate
    FlutterOverlayWindow.overlayListener.listen((data) {
      if (data is Map) {
        if (data["status"] == "no_text") {
          setState(() {
            _isTranslating = false;
            _translations = [];
            _showTranslationLayer = false;
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
          });

          // Resize overlay size to fullscreen to display translations
          FlutterOverlayWindow.resizeOverlay(-1, -1, false);
        }
      }
    });
  }

  Future<void> _startTranslationFlow() async {
    if (_isTranslating) return;
    setState(() {
      _isTranslating = true;
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
      body: Center(
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
    );
  }
}
