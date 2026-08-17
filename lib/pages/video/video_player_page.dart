import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../../l10n/app_localizations.dart';

class VideoPlayerPage extends HookConsumerWidget {
  final String videoUrl;

  const VideoPlayerPage({super.key, required this.videoUrl});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final videoPlayerController = useState<VideoPlayerController?>(null);
    final chewieController = useState<ChewieController?>(null);
    final isLoading = useState<bool>(true);
    final error = useState<String?>(null);

    useEffect(() {
      VideoPlayerController? controller;
      ChewieController? newChewieController;

      Future<void> initVideo() async {
        try {
          Uri? parsedUri;
          try {
            parsedUri = Uri.parse(videoUrl);
          } catch (e) {
            error.value = l10n.videoError;
            isLoading.value = false;
            return;
          }

          controller = VideoPlayerController.networkUrl(parsedUri);
          videoPlayerController.value = controller;
          await controller!.initialize();

          newChewieController = ChewieController(
            videoPlayerController: controller!,
            autoPlay: true,
            looping: true,
            fullScreenByDefault: true,
            allowedScreenSleep: false,
            deviceOrientationsOnEnterFullScreen: [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
            deviceOrientationsAfterFullScreen: [
              DeviceOrientation.portraitUp,
            ],
            placeholder: const Center(child: CircularProgressIndicator()),
          );
          chewieController.value = newChewieController;
          error.value = null;
        } catch (e) {
          error.value = l10n.unexpectedError(e.toString());
        } finally {
          isLoading.value = false;
        }
      }

      initVideo();

      return () {
        // 全屏中直接退出页面时恢复全局竖屏锁（main.dart）。
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
        videoPlayerController.value?.dispose();
        chewieController.value?.dispose();
      };
    }, [videoUrl]);

    if (isLoading.value) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (error.value != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(l10n.videoError),
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          titleTextStyle: const TextStyle(color: Colors.white),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              error.value!,
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (chewieController.value != null &&
        chewieController.value!.videoPlayerController.value.isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black, // Ensure black background for fullscreen
        body: Chewie(controller: chewieController.value!),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(
          l10n.initializingPlayer,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}
