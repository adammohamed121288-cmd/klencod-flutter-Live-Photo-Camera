
import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  List<CameraDescription> cameras = [];

  try {
    cameras = await availableCameras();
  } catch (_) {
    // The app will show an error screen if no camera is available.
  }

  runApp(LivePhotoApp(cameras: cameras));
}

class LivePhotoApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const LivePhotoApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Live Photo Camera',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF00E5FF),
        ),
        useMaterial3: true,
      ),
      home: CameraHome(cameras: cameras),
    );
  }
}

class CameraHome extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraHome({super.key, required this.cameras});

  @override
  State<CameraHome> createState() => _CameraHomeState();
}

class _CameraHomeState extends State<CameraHome>
    with WidgetsBindingObserver {
  CameraController? _controller;

  bool _initializing = true;
  bool _busy = false;
  bool _liveEnabled = true;
  bool _flashEnabled = false;
  bool _frontCamera = false;

  double _zoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;

  String? _error;
  String? _lastPhotoPath;
  String? _lastVideoPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) {
      setState(() {
        _initializing = false;
        _error = 'لم يتم العثور على كاميرا في هذا الجهاز.';
      });
      return;
    }

    setState(() {
      _initializing = true;
      _error = null;
    });

    try {
      final description = widget.cameras.firstWhere(
        (camera) => _frontCamera
            ? camera.lensDirection == CameraLensDirection.front
            : camera.lensDirection == CameraLensDirection.back,
        orElse: () => widget.cameras.first,
      );

      final oldController = _controller;
      _controller = null;
      await oldController?.dispose();

      final controller = CameraController(
        description,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();

      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = await controller.getMaxZoomLevel();
      _zoom = 1.0.clamp(_minZoom, _maxZoom);

      await controller.setZoomLevel(_zoom);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = _cameraErrorMessage(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'حدث خطأ أثناء تشغيل الكاميرا: $e';
      });
    }
  }

  String _cameraErrorMessage(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
        return 'يرجى السماح للتطبيق باستخدام الكاميرا من إعدادات الهاتف.';
      case 'CameraAccessDeniedWithoutPrompt':
        return 'صلاحية الكاميرا مرفوضة. فعّلها من إعدادات التطبيق.';
      case 'CameraAccessRestricted':
        return 'الوصول إلى الكاميرا مقيد على هذا الجهاز.';
      default:
        return 'تعذر تشغيل الكاميرا: ${e.description ?? e.code}';
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      controller.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _switchCamera() async {
    if (_busy || widget.cameras.length < 2) return;

    setState(() {
      _frontCamera = !_frontCamera;
      _flashEnabled = false;
    });

    await _initializeCamera();
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      final nextValue = !_flashEnabled;

      await controller.setFlashMode(
        nextValue ? FlashMode.torch : FlashMode.off,
      );

      if (!mounted) return;
      setState(() => _flashEnabled = nextValue);
    } catch (_) {
      _showMessage('الفلاش غير مدعوم أو غير متاح الآن.');
    }
  }

  Future<void> _changeZoom(double value) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final newZoom = value.clamp(_minZoom, _maxZoom);

    try {
      await controller.setZoomLevel(newZoom);
      if (mounted) setState(() => _zoom = newZoom);
    } catch (_) {
      _showMessage('تعذر تغيير مستوى التقريب.');
    }
  }

  Future<void> _capture() async {
    final controller = _controller;

    if (_busy ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        controller.value.isRecordingVideo) {
      return;
    }

    setState(() => _busy = true);

    String? videoPath;

    try {
      if (_liveEnabled) {
        await controller.startVideoRecording();

        // A short silent video is recorded for the LIVE effect.
        await Future.delayed(const Duration(seconds: 2));

        final video = await controller.stopVideoRecording();
        videoPath = video.path;
      }

      final photo = await controller.takePicture();

      // Save files to the device gallery.
      if (_liveEnabled && videoPath != null) {
        await Gal.putVideo(videoPath);
      }

      await Gal.putImage(photo.path);

      if (!mounted) return;

      setState(() {
        _lastPhotoPath = photo.path;
        _lastVideoPath = videoPath;
        _busy = false;
      });

      _showMessage(
        _liveEnabled
            ? 'تم حفظ الصورة والفيديو في المعرض بنجاح.'
            : 'تم حفظ الصورة في المعرض بنجاح.',
      );
    } on CameraException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _showMessage(_cameraErrorMessage(e));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _showMessage('حدث خطأ أثناء التصوير أو الحفظ: $e');
      }
    }
  }

  Future<void> _showLastPhoto() async {
    final path = _lastPhotoPath;
    if (path == null || !File(path).existsSync()) {
      _showMessage('لم تلتقط أي صورة حتى الآن.');
      return;
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF151515),
        insetPadding: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    height: 180,
                    child: Center(child: Text('تعذر عرض الصورة')),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_lastVideoPath != null)
                const Text(
                  'تم حفظ فيديو LIVE منفصل في المعرض.',
                  style: TextStyle(color: Colors.white70),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, textAlign: TextAlign.center),
          backgroundColor: const Color(0xFF222222),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      body: SafeArea(
        child: _initializing
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF00E5FF),
                ),
              )
            : _error != null || controller == null
                ? _buildErrorScreen()
                : _buildCameraScreen(controller),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_rounded,
              color: Color(0xFF00E5FF),
              size: 65,
            ),
            const SizedBox(height: 18),
            Text(
              _error ?? 'الكاميرا غير متاحة.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _initializeCamera,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraScreen(CameraController controller) {
    return Column(
      children: [
        _buildTopBar(),
        Expanded(
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(controller),
                if (_busy)
                  Container(
                    color: Colors.black26,
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF00E5FF),
                      ),
                    ),
                  ),
                Positioned(
                  top: 16,
                  left: 16,
                  child: _liveBadge(),
                ),
                Positioned(
                  bottom: 22,
                  left: 0,
                  right: 0,
                  child: _buildZoomControls(),
                ),
              ],
            ),
          ),
        ),
        _buildBottomControls(),
      ],
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LIVE PHOTO',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              Text(
                'CAMERA',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
          Row(
            children: [
              _circleButton(
                icon: _flashEnabled ? Icons.flash_on : Icons.flash_off,
                onTap: _toggleFlash,
                active: _flashEnabled,
              ),
              const SizedBox(width: 12),
              _circleButton(
                icon: Icons.cameraswitch_rounded,
                onTap: _switchCamera,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _liveBadge() {
    return GestureDetector(
      onTap: () {
        if (_busy) return;
        setState(() => _liveEnabled = !_liveEnabled);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.65),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: _liveEnabled
                ? const Color(0xFF00E5FF)
                : Colors.white30,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.circle,
              size: 9,
              color: _liveEnabled ? Colors.redAccent : Colors.white38,
            ),
            const SizedBox(width: 7),
            Text(
              _liveEnabled ? 'LIVE ON' : 'LIVE OFF',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomControls() {
    if (_maxZoom <= _minZoom) return const SizedBox.shrink();

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.65),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('1x', style: TextStyle(fontSize: 12)),
            SizedBox(
              width: 140,
              child: Slider(
                value: _zoom.clamp(_minZoom, _maxZoom),
                min: _minZoom,
                max: _maxZoom,
                activeColor: const Color(0xFF00E5FF),
                onChanged: _busy ? null : _changeZoom,
              ),
            ),
            Text(
              '${_zoom.toStringAsFixed(1)}x',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: _showLastPhoto,
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: const Color(0xFF222222),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: Colors.white24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _lastPhotoPath != null &&
                          File(_lastPhotoPath!).existsSync()
                      ? Image.file(
                          File(_lastPhotoPath!),
                          fit: BoxFit.cover,
                        )
                      : const Icon(
                          Icons.photo_library_outlined,
                          color: Colors.white70,
                        ),
                ),
              ),
              GestureDetector(
                onTap: _busy ? null : _capture,
                child: Container(
                  width: 78,
                  height: 78,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _busy
                          ? Colors.white30
                          : const Color(0xFF00E5FF),
                      width: 3,
                    ),
                  ),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: _busy
                        ? const Padding(
                            padding: EdgeInsets.all(17),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt_rounded,
                            color: Colors.black,
                            size: 30,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 54, height: 54),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _liveEnabled ? 'اضغط لالتقاط LIVE PHOTO' : 'وضع التصوير العادي',
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 11,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return GestureDetector(
      onTap: _busy ? null : onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF00E5FF).withOpacity(0.18)
              : const Color(0xFF222222),
          shape: BoxShape.circle,
          border: Border.all(
            color: active
                ? const Color(0xFF00E5FF)
                : Colors.white12,
          ),
        ),
        child: Icon(
          icon,
          color: active ? const Color(0xFF00E5FF) : Colors.white,
          size: 21,
        ),
      ),
    );
  }
}
