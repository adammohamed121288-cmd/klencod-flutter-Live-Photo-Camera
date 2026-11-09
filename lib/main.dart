
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:gal/gal.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LivePhotoApp());
}

class LivePhotoApp extends StatelessWidget {
  const LivePhotoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Live Photo Camera',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Colors.yellow,
          secondary: Colors.blue,
        ),
      ),
      home: const CameraScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? controller;
  List<CameraDescription> cameras = [];

  bool initialized = false;
  bool liveEnabled = true;
  bool busy = false;
  bool flashEnabled = false;
  bool frontCamera = false;

  String status = 'جاهز للتصوير';
  String? lastPhoto;
  String? lastVideo;

  @override
  void initState() {
    super.initState();
    initializeCamera();
  }

  Future<void> initializeCamera() async {
    try {
      cameras = await availableCameras();

      if (cameras.isEmpty) {
        setState(() => status = 'لا توجد كاميرا على الجهاز');
        return;
      }

      final selected = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      await setupController(selected);
    } catch (e) {
      setState(() => status = 'تعذر تشغيل الكاميرا');
    }
  }

  Future<void> setupController(CameraDescription camera) async {
    final old = controller;

    if (old != null) {
      await old.dispose();
    }

    final newController = CameraController(
      camera,
      ResolutionPreset.max,
      enableAudio: false,
    );

    controller = newController;

    await newController.initialize();
    await newController.setFlashMode(FlashMode.off);

    if (!mounted) return;

    setState(() {
      initialized = true;
      status = 'جاهز للتصوير';
    });
  }

  Future<void> switchCamera() async {
    if (busy || cameras.length < 2) return;

    setState(() {
      busy = true;
      initialized = false;
    });

    try {
      frontCamera = !frontCamera;

      final selected = cameras.firstWhere(
        (c) => c.lensDirection ==
            (frontCamera
                ? CameraLensDirection.front
                : CameraLensDirection.back),
      );

      await setupController(selected);
    } catch (e) {
      setState(() => status = 'تعذر تبديل الكاميرا');
    }

    if (mounted) setState(() => busy = false);
  }

  Future<void> toggleFlash() async {
    if (controller == null || !initialized) return;

    try {
      flashEnabled = !flashEnabled;

      await controller!.setFlashMode(
        flashEnabled ? FlashMode.torch : FlashMode.off,
      );

      setState(() {});
    } catch (e) {
      setState(() => status = 'الفلاش غير مدعوم');
    }
  }

  Future<void> takeLivePhoto() async {
    if (controller == null || !initialized || busy) return;

    setState(() {
      busy = true;
      status = liveEnabled
          ? 'جاري تسجيل اللحظة...'
          : 'جاري التقاط الصورة...';
    });

    try {
      XFile? video;

      if (liveEnabled) {
        await controller!.startVideoRecording();

        // تسجيل فيديو قصير يمثل لحظة Live Photo
        await Future.delayed(const Duration(seconds: 3));

        video = await controller!.stopVideoRecording();

        lastVideo = video.path;

        await Gal.putVideo(video.path);
      }

      final photo = await controller!.takePicture();

      await Gal.putImage(photo.path);

      if (!mounted) return;

      setState(() {
        lastPhoto = photo.path;
        status = 'تم حفظ الصورة بنجاح ✓';
        busy = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ الصورة والفيديو في المعرض 📸'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        busy = false;
        status = 'حدث خطأ أثناء التصوير';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e')),
      );
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  Widget circleButton(
    IconData icon,
    VoidCallback action, {
    Color color = Colors.white,
  }) {
    return IconButton(
      onPressed: action,
      icon: Icon(icon, color: color, size: 29),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            SizedBox(
              height: 65,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  circleButton(
                    flashEnabled ? Icons.flash_on : Icons.flash_off,
                    toggleFlash,
                    color: flashEnabled ? Colors.yellow : Colors.white,
                  ),

                  GestureDetector(
                    onTap: () {
                      setState(() => liveEnabled = !liveEnabled);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: liveEnabled
                            ? Colors.yellow
                            : Colors.grey.shade800,
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.radio_button_checked,
                            color: liveEnabled ? Colors.black : Colors.white,
                            size: 17,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            liveEnabled ? 'LIVE' : 'LIVE OFF',
                            style: TextStyle(
                              color: liveEnabled
                                  ? Colors.black
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  circleButton(Icons.settings, () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: Colors.grey.shade900,
                        title: const Text('إعدادات الكاميرا'),
                        content: const Text(
                          'Live Photo Camera\nالإصدار 1.0.0',
                          textDirection: TextDirection.rtl,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('إغلاق'),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),

            // Camera preview
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFF171717),
                  child: initialized &&
                          controller != null &&
                          controller!.value.isInitialized
                      ? CameraPreview(controller!)
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(
                                color: Colors.yellow,
                              ),
                              const SizedBox(height: 15),
                              Text(status),
                            ],
                          ),
                        ),
                ),
              ),
            ),

            // Zoom buttons
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  zoomButton('0.5x'),
                  zoomButton('1x', selected: true),
                  zoomButton('2x'),
                ],
              ),
            ),

            Text(
              status,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
            ),

            const SizedBox(height: 12),

            // Camera modes
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Text('فيديو', style: TextStyle(color: Colors.white54)),
                Text('صورة', style: TextStyle(color: Colors.yellow)),
                Text('LIVE', style: TextStyle(color: Colors.yellow)),
                Text('بورتريه', style: TextStyle(color: Colors.white54)),
              ],
            ),

            const SizedBox(height: 25),

            // Bottom controls
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: lastPhoto == null
                        ? null
                        : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PhotoViewer(
                                  photoPath: lastPhoto!,
                                  videoPath: lastVideo,
                                ),
                              ),
                            );
                          },
                    child: Container(
                      width: 55,
                      height: 55,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: lastPhoto != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                File(lastPhoto!),
                                fit: BoxFit.cover,
                              ),
                            )
                          : const Icon(
                              Icons.photo_library,
                              color: Colors.white,
                            ),
                    ),
                  ),

                  GestureDetector(
                    onTap: takeLivePhoto,
                    child: Container(
                      width: 82,
                      height: 82,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 4,
                        ),
                      ),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: busy
                            ? const Padding(
                                padding: EdgeInsets.all(18),
                                child: CircularProgressIndicator(
                                  color: Colors.black,
                                  strokeWidth: 3,
                                ),
                              )
                            : const SizedBox(),
                      ),
                    ),
                  ),

                  circleButton(
                    Icons.cameraswitch,
                    switchCamera,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 25),
            Container(
              width: 110,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget zoomButton(String label, {bool selected = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: selected ? Colors.yellow : Colors.black54,
        shape: BoxShape.circle,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.black : Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

// شاشة عرض الصورة
class PhotoViewer extends StatelessWidget {
  final String photoPath;
  final String? videoPath;

  const PhotoViewer({
    super.key,
    required this.photoPath,
    this.videoPath,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Live Photo'),
        actions: [
          if (videoPath != null)
            const Padding(
              padding: EdgeInsets.all(15),
              child: Text(
                'LIVE',
                style: TextStyle(
                  color: Colors.yellow,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Image.file(
                File(photoPath),
                fit: BoxFit.contain,
              ),
            ),
          ),
          if (videoPath != null)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'تم حفظ مقطع الحركة في معرض الفيديوهات',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          const SizedBox(height: 25),
        ],
      ),
    );
  }
}
