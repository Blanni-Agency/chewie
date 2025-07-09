import 'dart:async';

import 'package:chewie/src/chewie_progress_colors.dart';
import 'package:chewie/src/models/option_item.dart';
import 'package:chewie/src/models/options_translation.dart';
import 'package:chewie/src/models/subtitle_model.dart';
import 'package:chewie/src/notifiers/player_notifier.dart';
import 'package:chewie/src/player_with_controls.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
// APPLE FULLSCREEN FIX: Import for user agent detection
import 'dart:html' as html;

typedef ChewieRoutePageBuilder =
    Widget Function(
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      ChewieControllerProvider controllerProvider,
    );

/// A Video Player with Material and Cupertino skins.
///
/// `video_player` is pretty low level. Chewie wraps it in a friendly skin to
/// make it easy to use!
class Chewie extends StatefulWidget {
  const Chewie({super.key, required this.controller});

  /// The [ChewieController]
  final ChewieController controller;

  @override
  ChewieState createState() {
    return ChewieState();
  }
}

class ChewieState extends State<Chewie> {
  bool _isFullScreen = false;

  // APPLE FULLSCREEN FIX: Add timer management
  final List<Timer> _activeTimers = [];

  bool get isControllerFullScreen => widget.controller.isFullScreen;
  late PlayerNotifier notifier;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(listener);
    notifier = PlayerNotifier.init();
  }

  @override
  void dispose() {
    widget.controller.removeListener(listener);
    notifier.dispose();
    // APPLE FULLSCREEN FIX: Cancel all active timers
    _cancelAllTimers();
    super.dispose();
  }

  @override
  void didUpdateWidget(Chewie oldWidget) {
    if (oldWidget.controller != widget.controller) {
      widget.controller.addListener(listener);
    }
    super.didUpdateWidget(oldWidget);
    if (_isFullScreen != isControllerFullScreen) {
      widget.controller._isFullScreen = _isFullScreen;
    }
  }

  Future<void> listener() async {
    if (isControllerFullScreen && !_isFullScreen) {
      print("APPLE FIX: Entering fullscreen");
      _isFullScreen = isControllerFullScreen;
      await _pushFullScreenWidget(context);
    } else if (_isFullScreen) {
      print("APPLE FIX: Exiting fullscreen");
      Navigator.of(
        context,
        rootNavigator: widget.controller.useRootNavigator,
      ).pop();
      _isFullScreen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChewieControllerProvider(
      controller: widget.controller,
      child: ChangeNotifierProvider<PlayerNotifier>.value(
        value: notifier,
        builder: (context, w) => const PlayerWithControls(),
      ),
    );
  }

  Widget _buildFullScreenVideo(
    BuildContext context,
    Animation<double> animation,
    ChewieControllerProvider controllerProvider,
  ) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Container(
        alignment: Alignment.center,
        color: Colors.black,
        child: controllerProvider,
      ),
    );
  }

  AnimatedWidget _defaultRoutePageBuilder(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    ChewieControllerProvider controllerProvider,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        return _buildFullScreenVideo(context, animation, controllerProvider);
      },
    );
  }

  Widget _fullScreenRoutePageBuilder(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final controllerProvider = ChewieControllerProvider(
      controller: widget.controller,
      child: ChangeNotifierProvider<PlayerNotifier>.value(
        value: notifier,
        builder: (context, w) => const PlayerWithControls(),
      ),
    );

    if (widget.controller.routePageBuilder == null) {
      return _defaultRoutePageBuilder(
        context,
        animation,
        secondaryAnimation,
        controllerProvider,
      );
    }
    return widget.controller.routePageBuilder!(
      context,
      animation,
      secondaryAnimation,
      controllerProvider,
    );
  }

  Future<dynamic> _pushFullScreenWidget(BuildContext context) async {
    final TransitionRoute<void> route = PageRouteBuilder<void>(
      pageBuilder: _fullScreenRoutePageBuilder,
    );

    onEnterFullScreen();

    if (!widget.controller.allowedScreenSleep) {
      WakelockPlus.enable();
    }

    print(
      "APPLE FIX: Before Navigator.push - Video playing: ${widget.controller.videoPlayerController.value.isPlaying}",
    );
    print(
      "APPLE FIX: Before Navigator.push - Video position: ${widget.controller.videoPlayerController.value.position}",
    );

    await Navigator.of(
      context,
      rootNavigator: widget.controller.useRootNavigator,
    ).push(route);

    print(
      "APPLE FIX: After Navigator.pop - Video playing: ${widget.controller.videoPlayerController.value.isPlaying}",
    );
    print(
      "APPLE FIX: After Navigator.pop - Video position: ${widget.controller.videoPlayerController.value.position}",
    );

    if (kIsWeb) {
      // APPLE FULLSCREEN FIX: Skip reinitialization on Apple browsers to prevent video destruction

      bool _isAppleGrover = _isAppleBrowser();
      print("_isAppleGrover ===>>> $_isAppleGrover");
      if (!_isAppleGrover) {
        print(
          "APPLE FIX: Using original _reInitializeControllers for non-Apple browser",
        );
        _reInitializeControllers();
      } else {
        // For Apple browsers, use smooth exit like smooth entry
        print("APPLE FIX: Using onExitFullScreen for Apple browser");
        onExitFullScreen();
      }
    }

    _isFullScreen = false;
    widget.controller.exitFullScreen();

    if (!widget.controller.allowedScreenSleep) {
      WakelockPlus.disable();
    }
  }

  void onEnterFullScreen() {
    print("APPLE FIX: onEnterFullScreen called");
    print(
      "APPLE FIX: Video playing before fullscreen: ${widget.controller.videoPlayerController.value.isPlaying}",
    );
    print(
      "APPLE FIX: Video position before fullscreen: ${widget.controller.videoPlayerController.value.position}",
    );

    final videoWidth = widget.controller.videoPlayerController.value.size.width;
    final videoHeight =
        widget.controller.videoPlayerController.value.size.height;

    print("APPLE FIX: Video size: ${videoWidth}x${videoHeight}");
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);

    // if (widget.controller.systemOverlaysOnEnterFullScreen != null) {
    //   /// Optional user preferred settings
    //   SystemChrome.setEnabledSystemUIMode(
    //     SystemUiMode.manual,
    //     overlays: widget.controller.systemOverlaysOnEnterFullScreen,
    //   );
    // } else {
    //   /// Default behavior
    //   SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    // }

    if (widget.controller.deviceOrientationsOnEnterFullScreen != null) {
      /// Optional user preferred settings
      SystemChrome.setPreferredOrientations(
        widget.controller.deviceOrientationsOnEnterFullScreen!,
      );
    } else {
      final isLandscapeVideo = videoWidth > videoHeight;
      final isPortraitVideo = videoWidth < videoHeight;

      /// Default behavior
      /// Video w > h means we force landscape
      if (isLandscapeVideo) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
      /// Video h > w means we force portrait
      else if (isPortraitVideo) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
      /// Otherwise if h == w (square video)
      else {
        SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      }
    }

    print("APPLE FIX: onEnterFullScreen completed");
    print(
      "APPLE FIX: Video playing after fullscreen setup: ${widget.controller.videoPlayerController.value.isPlaying}",
    );
    print(
      "APPLE FIX: Video position after fullscreen setup: ${widget.controller.videoPlayerController.value.position}",
    );

    // APPLE FULLSCREEN FIX: Check and fix desync when entering fullscreen
    if (kIsWeb && _isAppleBrowser()) {
      print("APPLE FIX: Checking for desync on fullscreen ENTRY");
      Timer(const Duration(milliseconds: 100), () {
        _checkAndFixFullscreenDesync();
      });
      Timer(const Duration(milliseconds: 300), () {
        _checkAndFixFullscreenDesync();
      });
      Timer(const Duration(milliseconds: 500), () {
        _checkAndFixFullscreenDesync();
      });
    }
  }

  void onExitFullScreen() {
    print("APPLE FIX: onExitFullScreen called");

    // CAPTURE STATE IMMEDIATELY before Flutter destroys DOM
    final wasPlaying = widget.controller.videoPlayerController.value.isPlaying;
    final currentPosition =
        widget.controller.videoPlayerController.value.position;

    print(
      "APPLE FIX: Captured state - playing: $wasPlaying, position: $currentPosition",
    );

    final videoWidth = widget.controller.videoPlayerController.value.size.width;
    final videoHeight =
        widget.controller.videoPlayerController.value.size.height;
    print("APPLE FIX: Video size: ${videoWidth}x${videoHeight}");

    // Restore system UI overlays after fullscreen
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: widget.controller.systemOverlaysAfterFullScreen,
    );

    // Restore device orientations after fullscreen
    SystemChrome.setPreferredOrientations(
      widget.controller.deviceOrientationsAfterFullScreen,
    );

    print("APPLE FIX: System UI configured");

    // FORCE IMMEDIATE RECREATION - assume DOM will be destroyed
    print("APPLE FIX: Forcing immediate recreation with captured state");
    _forceImmediateRecreation(wasPlaying, currentPosition);
  }

  ///When viewing full screen on web, returning from full screen causes original video to lose the picture.
  ///We re initialise controllers for web only when returning from full screen
  void _reInitializeControllers() {
    print(
      "APPLE FIX: _reInitializeControllers called (original Chewie behavior)",
    );
    final prevPosition = widget.controller.videoPlayerController.value.position;
    print("APPLE FIX: Saving position before reinit: $prevPosition");
    widget.controller.videoPlayerController.initialize().then((_) async {
      print("APPLE FIX: VideoPlayerController.initialize() completed");
      widget.controller._initialize();
      print("APPLE FIX: ChewieController._initialize() completed");
      widget.controller.videoPlayerController.seekTo(prevPosition);
      print("APPLE FIX: seekTo($prevPosition) completed");
      await widget.controller.videoPlayerController.play();
      print("APPLE FIX: play() completed");
      widget.controller.videoPlayerController.pause();
      print("APPLE FIX: pause() completed - reinit finished");
    });
  }

  // APPLE FULLSCREEN FIX: Force immediate recreation with captured state
  void _forceImmediateRecreation(bool wasPlaying, Duration position) {
    print("APPLE FIX: _forceImmediateRecreation called");
    print(
      "APPLE FIX: Target state - playing: $wasPlaying, position: $position",
    );

    widget.controller.videoPlayerController
        .initialize()
        .then((_) async {
          print("APPLE FIX: VideoPlayerController.initialize() completed");

          // Set looping state
          await widget.controller.videoPlayerController.setLooping(
            widget.controller.looping,
          );
          print("APPLE FIX: Looping configured");

          // Restore position
          await widget.controller.videoPlayerController.seekTo(position);
          print("APPLE FIX: Position restored to $position");

          // Restore playing state
          if (wasPlaying) {
            await widget.controller.videoPlayerController.play();
            print("APPLE FIX: Video playing restored");
          } else {
            print("APPLE FIX: Video kept paused as it was");
          }

          print("APPLE FIX: Immediate recreation completed successfully");
        })
        .catchError((error) {
          print("APPLE FIX: Error during immediate recreation: $error");
        });
  }

  // APPLE FULLSCREEN FIX: Detect Apple browsers (Safari, Chrome on macOS)
  bool _isAppleBrowser() {
    if (!kIsWeb) return false;
    try {
      final userAgent = html.window.navigator.userAgent;
      print("APPLE FIX: User Agent: $userAgent");
      final isApple =
          userAgent.contains('Mac OS X') || userAgent.contains('Macintosh');
      print("APPLE FIX: Is Apple Browser: $isApple");
      return isApple;
    } catch (e) {
      print("APPLE FIX: Error detecting browser: $e");
      return false;
    }
  }

  // APPLE FULLSCREEN FIX: Check and fix desync when entering or exiting fullscreen
  void _checkAndFixFullscreenDesync() {
    try {
      final controller = widget.controller.videoPlayerController;
      final videoElements = html.document.getElementsByTagName('video');

      print("APPLE FIX: _checkAndFixFullscreenDesync called");
      print(
        "APPLE FIX: Controller says playing: ${controller.value.isPlaying}",
      );

      if (videoElements.isNotEmpty) {
        final video = videoElements.first as html.VideoElement;
        print("APPLE FIX: DOM video paused: ${video.paused}");

        // If controller says playing but DOM is paused (common Apple fullscreen bug)
        if (controller.value.isPlaying && video.paused) {
          print(
            "APPLE FIX: DESYNC DETECTED - Controller says playing but DOM is paused",
          );
          print("APPLE FIX: Forcing DOM video to play");

          video
              .play()
              .then((_) {
                print("APPLE FIX: DOM video play successful");
              })
              .catchError((error) {
                print("APPLE FIX: DOM video play failed: $error");
                // Try controller play as fallback
                controller
                    .play()
                    .then((_) {
                      print("APPLE FIX: Controller play fallback successful");
                    })
                    .catchError((controllerError) {
                      print(
                        "APPLE FIX: Controller play fallback failed: $controllerError",
                      );
                    });
              });
        }
        // If both are paused, force both to play
        else if (!controller.value.isPlaying && video.paused) {
          print("APPLE FIX: Both paused, forcing both to play");
          video.play();
          controller
              .play()
              .then((_) {
                print("APPLE FIX: Both forced to play successful");
              })
              .catchError((error) {
                print("APPLE FIX: Controller play failed: $error");
              });
        } else {
          print("APPLE FIX: Controller and DOM are in sync");
        }
      } else {
        print("APPLE FIX: No video elements found");
      }
    } catch (e) {
      print("APPLE FIX: Error in _checkAndFixFullscreenDesync: $e");
    }
  }

  // APPLE FULLSCREEN FIX: Timer management functions
  void _addTimer(Timer timer) {
    _activeTimers.add(timer);
  }

  void _cancelAllTimers() {
    final timerCount = _activeTimers.length;
    for (final timer in _activeTimers) {
      timer.cancel();
    }
    _activeTimers.clear();
    print("APPLE FIX: Cancelled $timerCount active timers");
  }
}

/// The ChewieController is used to configure and drive the Chewie Player
/// Widgets. It provides methods to control playback, such as [pause] and
/// [play], as well as methods that control the visual appearance of the player,
/// such as [enterFullScreen] or [exitFullScreen].
///
/// In addition, you can listen to the ChewieController for presentational
/// changes, such as entering and exiting full screen mode. To listen for
/// changes to the playback, such as a change to the seek position of the
/// player, please use the standard information provided by the
/// `VideoPlayerController`.
class ChewieController extends ChangeNotifier {
  ChewieController({
    required this.videoPlayerController,
    this.optionsTranslation,
    this.aspectRatio,
    this.autoInitialize = false,
    this.autoPlay = false,
    this.draggableProgressBar = true,
    this.startAt,
    this.looping = false,
    this.fullScreenByDefault = false,
    this.cupertinoProgressColors,
    this.materialProgressColors,
    this.materialSeekButtonFadeDuration = const Duration(milliseconds: 300),
    this.materialSeekButtonSize = 26,
    this.placeholder,
    this.overlay,
    this.showControlsOnInitialize = true,
    this.showOptions = true,
    this.optionsBuilder,
    this.additionalOptions,
    this.showControls = true,
    this.transformationController,
    this.zoomAndPan = false,
    this.maxScale = 2.5,
    this.subtitle,
    this.showSubtitles = false,
    this.subtitleBuilder,
    this.customControls,
    this.errorBuilder,
    this.bufferingBuilder,
    this.allowedScreenSleep = true,
    this.isLive = false,
    this.allowFullScreen = true,
    this.allowMuting = true,
    this.allowPlaybackSpeedChanging = true,
    this.useRootNavigator = true,
    this.playbackSpeeds = const [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2],
    this.systemOverlaysOnEnterFullScreen,
    this.deviceOrientationsOnEnterFullScreen,
    this.systemOverlaysAfterFullScreen = SystemUiOverlay.values,
    this.deviceOrientationsAfterFullScreen = DeviceOrientation.values,
    this.routePageBuilder,
    this.progressIndicatorDelay,
    this.hideControlsTimer = defaultHideControlsTimer,
    this.controlsSafeAreaMinimum = EdgeInsets.zero,
    this.pauseOnBackgroundTap = false,
  }) : assert(
         playbackSpeeds.every((speed) => speed > 0),
         'The playbackSpeeds values must all be greater than 0',
       ) {
    _initialize();
  }

  ChewieController copyWith({
    VideoPlayerController? videoPlayerController,
    OptionsTranslation? optionsTranslation,
    double? aspectRatio,
    bool? autoInitialize,
    bool? autoPlay,
    bool? draggableProgressBar,
    Duration? startAt,
    bool? looping,
    bool? fullScreenByDefault,
    ChewieProgressColors? cupertinoProgressColors,
    ChewieProgressColors? materialProgressColors,
    Duration? materialSeekButtonFadeDuration,
    double? materialSeekButtonSize,
    Widget? placeholder,
    Widget? overlay,
    bool? showControlsOnInitialize,
    bool? showOptions,
    Future<void> Function(BuildContext, List<OptionItem>)? optionsBuilder,
    List<OptionItem> Function(BuildContext)? additionalOptions,
    bool? showControls,
    TransformationController? transformationController,
    bool? zoomAndPan,
    double? maxScale,
    Subtitles? subtitle,
    bool? showSubtitles,
    Widget Function(BuildContext, dynamic)? subtitleBuilder,
    Widget? customControls,
    WidgetBuilder? bufferingBuilder,
    Widget Function(BuildContext, String)? errorBuilder,
    bool? allowedScreenSleep,
    bool? isLive,
    bool? allowFullScreen,
    bool? allowMuting,
    bool? allowPlaybackSpeedChanging,
    bool? useRootNavigator,
    Duration? hideControlsTimer,
    EdgeInsets? controlsSafeAreaMinimum,
    List<double>? playbackSpeeds,
    List<SystemUiOverlay>? systemOverlaysOnEnterFullScreen,
    List<DeviceOrientation>? deviceOrientationsOnEnterFullScreen,
    List<SystemUiOverlay>? systemOverlaysAfterFullScreen,
    List<DeviceOrientation>? deviceOrientationsAfterFullScreen,
    Duration? progressIndicatorDelay,
    Widget Function(
      BuildContext,
      Animation<double>,
      Animation<double>,
      ChewieControllerProvider,
    )?
    routePageBuilder,
    bool? pauseOnBackgroundTap,
  }) {
    return ChewieController(
      draggableProgressBar: draggableProgressBar ?? this.draggableProgressBar,
      videoPlayerController:
          videoPlayerController ?? this.videoPlayerController,
      optionsTranslation: optionsTranslation ?? this.optionsTranslation,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      autoInitialize: autoInitialize ?? this.autoInitialize,
      autoPlay: autoPlay ?? this.autoPlay,
      startAt: startAt ?? this.startAt,
      looping: looping ?? this.looping,
      fullScreenByDefault: fullScreenByDefault ?? this.fullScreenByDefault,
      cupertinoProgressColors:
          cupertinoProgressColors ?? this.cupertinoProgressColors,
      materialProgressColors:
          materialProgressColors ?? this.materialProgressColors,
      zoomAndPan: zoomAndPan ?? this.zoomAndPan,
      maxScale: maxScale ?? this.maxScale,
      controlsSafeAreaMinimum:
          controlsSafeAreaMinimum ?? this.controlsSafeAreaMinimum,
      transformationController:
          transformationController ?? this.transformationController,
      materialSeekButtonFadeDuration:
          materialSeekButtonFadeDuration ?? this.materialSeekButtonFadeDuration,
      materialSeekButtonSize:
          materialSeekButtonSize ?? this.materialSeekButtonSize,
      placeholder: placeholder ?? this.placeholder,
      overlay: overlay ?? this.overlay,
      showControlsOnInitialize:
          showControlsOnInitialize ?? this.showControlsOnInitialize,
      showOptions: showOptions ?? this.showOptions,
      optionsBuilder: optionsBuilder ?? this.optionsBuilder,
      additionalOptions: additionalOptions ?? this.additionalOptions,
      showControls: showControls ?? this.showControls,
      showSubtitles: showSubtitles ?? this.showSubtitles,
      subtitle: subtitle ?? this.subtitle,
      subtitleBuilder: subtitleBuilder ?? this.subtitleBuilder,
      customControls: customControls ?? this.customControls,
      errorBuilder: errorBuilder ?? this.errorBuilder,
      bufferingBuilder: bufferingBuilder ?? this.bufferingBuilder,
      allowedScreenSleep: allowedScreenSleep ?? this.allowedScreenSleep,
      isLive: isLive ?? this.isLive,
      allowFullScreen: allowFullScreen ?? this.allowFullScreen,
      allowMuting: allowMuting ?? this.allowMuting,
      allowPlaybackSpeedChanging:
          allowPlaybackSpeedChanging ?? this.allowPlaybackSpeedChanging,
      useRootNavigator: useRootNavigator ?? this.useRootNavigator,
      playbackSpeeds: playbackSpeeds ?? this.playbackSpeeds,
      systemOverlaysOnEnterFullScreen:
          systemOverlaysOnEnterFullScreen ??
          this.systemOverlaysOnEnterFullScreen,
      deviceOrientationsOnEnterFullScreen:
          deviceOrientationsOnEnterFullScreen ??
          this.deviceOrientationsOnEnterFullScreen,
      systemOverlaysAfterFullScreen:
          systemOverlaysAfterFullScreen ?? this.systemOverlaysAfterFullScreen,
      deviceOrientationsAfterFullScreen:
          deviceOrientationsAfterFullScreen ??
          this.deviceOrientationsAfterFullScreen,
      routePageBuilder: routePageBuilder ?? this.routePageBuilder,
      hideControlsTimer: hideControlsTimer ?? this.hideControlsTimer,
      progressIndicatorDelay:
          progressIndicatorDelay ?? this.progressIndicatorDelay,
      pauseOnBackgroundTap: pauseOnBackgroundTap ?? this.pauseOnBackgroundTap,
    );
  }

  static const defaultHideControlsTimer = Duration(seconds: 3);

  /// If false, the options button in MaterialUI and MaterialDesktopUI
  /// won't be shown.
  final bool showOptions;

  /// Pass your translations for the options like:
  /// - PlaybackSpeed
  /// - Subtitles
  /// - Cancel
  ///
  /// Buttons
  ///
  /// These are required for the default `OptionItem`'s
  final OptionsTranslation? optionsTranslation;

  /// Build your own options with default chewieOptions shiped through
  /// the builder method. Just add your own options to the Widget
  /// you'll build. If you want to hide the chewieOptions, just leave them
  /// out from your Widget.
  final Future<void> Function(
    BuildContext context,
    List<OptionItem> chewieOptions,
  )?
  optionsBuilder;

  /// Add your own additional options on top of chewie options
  final List<OptionItem> Function(BuildContext context)? additionalOptions;

  /// Define here your own Widget on how your n'th subtitle will look like
  Widget Function(BuildContext context, dynamic subtitle)? subtitleBuilder;

  /// Add a List of Subtitles here in `Subtitles.subtitle`
  Subtitles? subtitle;

  /// Determines whether subtitles should be shown by default when the video starts.
  ///
  /// If set to `true`, subtitles will be displayed automatically when the video
  /// begins playing. If set to `false`, subtitles will be hidden by default.
  bool showSubtitles;

  /// The controller for the video you want to play
  final VideoPlayerController videoPlayerController;

  /// Initialize the Video on Startup. This will prep the video for playback.
  final bool autoInitialize;

  /// Play the video as soon as it's displayed
  final bool autoPlay;

  /// Non-Draggable Progress Bar
  final bool draggableProgressBar;

  /// Start video at a certain position
  final Duration? startAt;

  /// Whether or not the video should loop
  final bool looping;

  /// Wether or not to show the controls when initializing the widget.
  final bool showControlsOnInitialize;

  /// Whether or not to show the controls at all
  final bool showControls;

  /// Controller to pass into the [InteractiveViewer] component.
  /// If it is required to control the transformation only via the controller,
  /// `zoomAndPan` should be set to false.
  final TransformationController? transformationController;

  /// Whether or not to allow zooming and panning.
  /// This can still be false, and the `transformationController` can be used to control the
  /// transformation.
  final bool zoomAndPan;

  /// Max scale when zooming
  final double maxScale;

  /// Defines customised controls. Check [MaterialControls] or
  /// [CupertinoControls] for reference.
  final Widget? customControls;

  /// When the video playback runs into an error, you can build a custom
  /// error message.
  final Widget Function(BuildContext context, String errorMessage)?
  errorBuilder;

  /// When the video is buffering, you can build a custom widget.
  final WidgetBuilder? bufferingBuilder;

  /// The Aspect Ratio of the Video. Important to get the correct size of the
  /// video!
  ///
  /// Will fallback to fitting within the space allowed.
  final double? aspectRatio;

  /// The colors to use for controls on iOS. By default, the iOS player uses
  /// colors sampled from the original iOS 11 designs.
  final ChewieProgressColors? cupertinoProgressColors;

  /// The colors to use for the Material Progress Bar. By default, the Material
  /// player uses the colors from your Theme.
  final ChewieProgressColors? materialProgressColors;

  // The duration of the fade animation for the seek button (Material Player only)
  final Duration materialSeekButtonFadeDuration;

  // The size of the seek button for the Material Player only
  final double materialSeekButtonSize;

  /// The placeholder is displayed underneath the Video before it is initialized
  /// or played.
  final Widget? placeholder;

  /// A widget which is placed between the video and the controls
  final Widget? overlay;

  /// Defines if the player will start in fullscreen when play is pressed
  final bool fullScreenByDefault;

  /// Defines if the player will sleep in fullscreen or not
  final bool allowedScreenSleep;

  /// Defines if the controls should be shown for live stream video
  final bool isLive;

  /// Defines if the fullscreen control should be shown
  final bool allowFullScreen;

  /// Defines if the mute control should be shown
  final bool allowMuting;

  /// Defines if the playback speed control should be shown
  final bool allowPlaybackSpeedChanging;

  /// Defines if push/pop navigations use the rootNavigator
  final bool useRootNavigator;

  /// Defines the [Duration] before the video controls are hidden. By default, this is set to three seconds.
  final Duration hideControlsTimer;

  /// Defines the set of allowed playback speeds user can change
  final List<double> playbackSpeeds;

  /// Defines the system overlays visible on entering fullscreen
  final List<SystemUiOverlay>? systemOverlaysOnEnterFullScreen;

  /// Defines the set of allowed device orientations on entering fullscreen
  final List<DeviceOrientation>? deviceOrientationsOnEnterFullScreen;

  /// Defines the system overlays visible after exiting fullscreen
  final List<SystemUiOverlay> systemOverlaysAfterFullScreen;

  /// Defines the set of allowed device orientations after exiting fullscreen
  final List<DeviceOrientation> deviceOrientationsAfterFullScreen;

  /// Defines a custom RoutePageBuilder for the fullscreen
  final ChewieRoutePageBuilder? routePageBuilder;

  /// Defines a delay in milliseconds between entering buffering state and displaying the loading spinner. Set null (default) to disable it.
  final Duration? progressIndicatorDelay;

  /// Adds additional padding to the controls' [SafeArea] as desired.
  /// Defaults to [EdgeInsets.zero].
  final EdgeInsets controlsSafeAreaMinimum;

  /// Defines if the player should pause when the background is tapped
  final bool pauseOnBackgroundTap;

  static ChewieController of(BuildContext context) {
    final chewieControllerProvider =
        context.dependOnInheritedWidgetOfExactType<ChewieControllerProvider>()!;

    return chewieControllerProvider.controller;
  }

  bool _isFullScreen = false;

  bool get isFullScreen => _isFullScreen;

  bool get isPlaying => videoPlayerController.value.isPlaying;

  Future<dynamic> _initialize() async {
    await videoPlayerController.setLooping(looping);

    if ((autoInitialize || autoPlay) &&
        !videoPlayerController.value.isInitialized) {
      await videoPlayerController.initialize();
    }

    if (autoPlay) {
      if (fullScreenByDefault) {
        enterFullScreen();
      }

      await videoPlayerController.play();
    }

    if (startAt != null) {
      await videoPlayerController.seekTo(startAt!);
    }

    if (fullScreenByDefault) {
      videoPlayerController.addListener(_fullScreenListener);
    }
  }

  Future<void> _fullScreenListener() async {
    if (videoPlayerController.value.isPlaying && !_isFullScreen) {
      enterFullScreen();
      videoPlayerController.removeListener(_fullScreenListener);
    }
  }

  void enterFullScreen() {
    _isFullScreen = true;
    notifyListeners();
  }

  void exitFullScreen() {
    _isFullScreen = false;
    notifyListeners();
  }

  void toggleFullScreen() {
    _isFullScreen = !_isFullScreen;
    notifyListeners();
  }

  void togglePause() {
    isPlaying ? pause() : play();
  }

  Future<void> play() async {
    await videoPlayerController.play();
  }

  // ignore: avoid_positional_boolean_parameters
  Future<void> setLooping(bool looping) async {
    await videoPlayerController.setLooping(looping);
  }

  Future<void> pause() async {
    await videoPlayerController.pause();
  }

  Future<void> seekTo(Duration moment) async {
    await videoPlayerController.seekTo(moment);
  }

  Future<void> setVolume(double volume) async {
    await videoPlayerController.setVolume(volume);
  }

  void setSubtitle(List<Subtitle> newSubtitle) {
    subtitle = Subtitles(newSubtitle);
  }
}

class ChewieControllerProvider extends InheritedWidget {
  const ChewieControllerProvider({
    super.key,
    required this.controller,
    required super.child,
  });

  final ChewieController controller;

  @override
  bool updateShouldNotify(ChewieControllerProvider oldWidget) =>
      controller != oldWidget.controller;
}
