# Overlay Dismissal UI & Gesture Design Spec

## Goal
Implement a circular Close button in the bottom-right corner and a swipe-up gesture detector for the translation overlay layer, ensuring the overlay is dismissed only when either action is triggered.

## Requirements
1. **Swipe-up Dismissal**:
   - Wrap the overlay translation layer in a `GestureDetector` that intercepts vertical drag gestures.
   - Trigger the dismissal function when a vertical drag ends with an upward velocity of at least 300 pixels per second.
2. **Bottom-Right Close Button**:
   - Add a pill or circular floating close button positioned in the bottom-right corner of the overlay screen.
   - Use a `mini` FloatingActionButton styled with the Catppuccin theme:
     - Background color: `0xfff38ba8` (Red)
     - Foreground icon color: `0xff11111b` (Base dark)
     - Margin: `24` logical DP from bottom and right edges.
3. **Dismissal Restriction**:
   - Tapping anywhere else on the overlay screen must not dismiss the translation layer. Only the Close button and the swipe-up gesture can trigger dismissal.

## Implementation Details

### Overlay Layer UI (lib/main.dart)

Replace the translation view representation in `Widget build(BuildContext context)` with:

```dart
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
                  ),
                ),
              ),
              Positioned(
                bottom: 24,
                right: 24,
                child: FloatingActionButton(
                  mini: true,
                  backgroundColor: const Color(0xfff38ba8),
                  foregroundColor: const Color(0xff11111b),
                  onPressed: _closeTranslationLayer,
                  child: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      );
    }
```
