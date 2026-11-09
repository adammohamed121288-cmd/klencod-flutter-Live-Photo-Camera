import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:video_player/video_player.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Error initializing cameras: $e');
  }
  runApp(const LivePhotoApp());
}

class LivePhotoApp extends StatelessWidget {
  const LivePhotoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CameraScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isLivePhotoEnabled = true;
  bool _isCapturing = false;
  int _selectedCameraIndex = 0;

  @override
  void initState() {
    super.initState();
    if (cameras.isNotEmpty) {
      _initCamera(_selectedCameraIndex);
    }
  }

  Future<void> _initCamera(int cameraIndex) async {
    _controller = CameraController(
      cameras[cameraIndex],
      ResolutionPreset.max,
      enableAudio: true,
    );
    try {
      await _controller!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error starting camera: $e');
    }
  }

  // التقاط الـ Live Photo (فيديو قصير + صورة ثابتة)
  Future<void> _takeLivePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) return;

    setState(() => _isCapturing = true);

    try {
      final directory = await getTemporaryDirectory();
      final String timeStamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String imagePath = path.join(directory.path, 'IMG_$timeStamp.jpg');
      final String videoPath = path.join(directory.path, 'VID_$timeStamp.mp4');

      if (_isLivePhotoEnabled) {
        // 1. تسجيل فيديو قصير لمدة 1.5 ثانية
        await _controller!.startVideoRecording();
        await Future.delayed(const Duration(milliseconds: 1500));
        XFile videoFile = await _controller!.stopVideoRecording();
        await videoFile.saveTo(videoPath);

        // 2. التقاط الصورة الثابتة
        XFile imageFile = await _controller!.takePicture();
        await imageFile.saveTo(imagePath);

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LivePhotoPreviewScreen(
                imagePath: imagePath,
                videoPath: videoPath,
              ),
            ),
          );
        }
      } else {
        // التقاط صورة عادية فقط
        XFile imageFile = await _controller!.takePicture();
        await imageFile.saveTo(imagePath);

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LivePhotoPreviewScreen(
                imagePath: imagePath,
                videoPath: null,
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error taking Live Photo: $e');
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.yellow)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // الشريط العلوي بنمط الآيفون
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(CupertinoIcons.flash_action, color: Colors.white),
                    onPressed: () {},
                  ),
                  // زر تفعيل أو إلغاء الـ Live Photo
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isLivePhotoEnabled = !_isLivePhotoEnabled;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _isLivePhotoEnabled ? Colors.yellow : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        CupertinoIcons.livephoto,
                        color: _isLivePhotoEnabled ? Colors.black : Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(CupertinoIcons.chevron_up, color: Colors.white),
                    onPressed: () {},
                  ),
                ],
              ),
            ),

            // شاشة معاينة الكاميرا
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: CameraPreview(_controller!),
              ),
            ),

            // أزرار التحكم بالأسفل
            Container(
              height: 140,
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // أيقونة المعرض المصغرة
                  Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey[800],
                    ),
                  ),

                  // زر الالتقاط (شاتر آيفون)
                  GestureDetector(
                    onTap: _takeLivePhoto,
                    child: Container(
                      width: 75,
                      height: 75,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _isCapturing ? Colors.red : Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),

                  // زر تبديل الكاميرا (أمامية/خلفية)
                  IconButton(
                    icon: const Icon(CupertinoIcons.switch_camera, color: Colors.white, size: 30),
                    onPressed: () {
                      if (cameras.length > 1) {
                        _selectedCameraIndex = (_selectedCameraIndex + 1) % cameras.length;
                        _initCamera(_selectedCameraIndex);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// شاشة معاينة الصورة وتشغيل الفيديو عند الضغط المطول (Live Photo Playback)
class LivePhotoPreviewScreen extends StatefulWidget {
  final String imagePath;
  final String? videoPath;

  const LivePhotoPreviewScreen({
    super.key,
    required this.imagePath,
    this.videoPath,
  });

  @override
  State<LivePhotoPreviewScreen> createState() => _LivePhotoPreviewScreenState();
}

class _LivePhotoPreviewScreenState extends State<LivePhotoPreviewScreen> {
  VideoPlayerController? _videoController;
  bool _isPlayingVideo = false;

  @override
  void initState() {
    super.initState();
    if (widget.videoPath != null) {
      _videoController = VideoPlayerController.file(File(widget.videoPath!))
        ..initialize().then((_) {
          setState(() {});
        });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _startLivePlay() {
    if (_videoController != null && _videoController!.value.isInitialized) {
      setState(() => _isPlayingVideo = true);
      _videoController!.seekTo(Duration.zero);
      _videoController!.play();
    }
  }

  void _stopLivePlay() {
    if (_videoController != null) {
      _videoController!.pause();
      setState(() => _isPlayingVideo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: widget.videoPath != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(CupertinoIcons.livephoto, color: Colors.yellow, size: 18),
                  SizedBox(width: 6),
                  Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 14)),
                ],
              )
            : null,
      ),
      body: Center(
        child: GestureDetector(
          onLongPressStart: (_) => _startLivePlay(),
          onLongPressEnd: (_) => _stopLivePlay(),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // عرض الصورة الثابتة الأساسية
              Image.file(File(widget.imagePath)),

              // تشغيل الفيديو فوقها عند الضغط المطول
              if (_isPlayingVideo && _videoController != null && _videoController!.value.isInitialized)
                AspectRatio(
                  aspectRatio: _videoController!.value.aspectRatio,
                  child: VideoPlayer(_videoController!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
