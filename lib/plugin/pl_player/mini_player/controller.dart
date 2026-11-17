import 'dart:async' show scheduleMicrotask;
import 'dart:io' show Platform;

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/page_utils.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/utils.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// State of one in-app floating player session.
class MiniPlayerSession {
  MiniPlayerSession({
    required this.id,
    required this.player,
    required this.args,
    this.title,
    this.fromPush = false,
    this.videoRoute,
    this.onClosed,
  }) : aspectRatio = _aspectRatioOf(player);

  final int id;
  final PlPlayerController player;

  /// Arguments of the video route that opened this session. Expanding a
  /// standalone window pushes the video page again with these arguments.
  final Map<String, dynamic> args;
  final String? title;
  final double aspectRatio;

  /// `true` when the video page is still in the navigator below the page
  /// that is currently shown (for example its up主 page). Expanding then pops
  /// back to that page instead of creating a new video page.
  final bool fromPush;
  final Route<dynamic>? videoRoute;

  /// Called when the window is closed while [fromPush] is `true`. The player
  /// stays alive for the hidden video page, which resumes at this position.
  final VoidCallback? onClosed;

  static double _aspectRatioOf(PlPlayerController player) {
    final width = player.width;
    final height = player.height;
    if (width != null && height != null && width > 0 && height > 0) {
      return width / height;
    }
    return 16 / 9;
  }
}

/// Owns the in-app floating player ("小窗播放").
///
/// The window either replaces the video page (back navigation) or stays over
/// a page pushed from the video page (for example the UP主 home). In both
/// cases the player must not be disposed together with the page. [owns] tells
/// the page whether the player has been handed over to this controller.
///
/// The controller lives for the whole app lifetime and is registered by
/// `main()`.
class MiniPlayerController extends GetxController {
  static MiniPlayerController get instance {
    if (Get.isRegistered<MiniPlayerController>()) {
      return Get.find<MiniPlayerController>();
    }
    return Get.put(MiniPlayerController(), permanent: true);
  }

  final Rxn<MiniPlayerSession> _session = Rxn<MiniPlayerSession>();
  MiniPlayerSession? get session => _session.value;

  /// Logical state, updated synchronously even when the UI update below is
  /// postponed because the widget tree is locked.
  MiniPlayerSession? _active;
  bool get isActive => _active != null;

  /// User dragged position in logical pixels. `null` means the default
  /// bottom right corner.
  final Rx<Offset?> offset = Rx<Offset?>(null);

  int _nextId = 0;
  bool _closing = false;

  @override
  void onInit() {
    super.onInit();
    PlPlayerController.onBeforeGetInstance = _onBeforeGetInstance;
    PlPlayerController.onDisposed = _onPlayerDisposed;
  }

  /// Takes over [player] so it survives the disposal of the video page.
  ///
  /// Returns `false` when the player is not the current shared instance or
  /// has not been initialized yet.
  bool open({
    required PlPlayerController player,
    required Map args,
    String? title,
    bool fromPush = false,
    Route<dynamic>? videoRoute,
    VoidCallback? onClosed,
  }) {
    if (_closing ||
        !identical(PlPlayerController.instance, player) ||
        player.playerCount != 1 ||
        player.videoController == null) {
      return false;
    }

    final previous = _active;
    if (previous != null && !identical(previous.player, player)) {
      close(stopPlayback: true);
    }

    final session = MiniPlayerSession(
      id: ++_nextId,
      player: player,
      args: Map<String, dynamic>.from(args),
      title: title,
      fromPush: fromPush,
      videoRoute: videoRoute,
      onClosed: onClosed,
    );
    _active = session;
    _setSession(session);
    if (Platform.isAndroid) {
      // The activity would otherwise enter PiP showing the list page.
      player.disableAutoEnterPip();
    }
    if (PlatformUtils.isMobile) {
      player.stopOrientationListener();
    }
    // Keep the media notification (if enabled) able to resume the video.
    PlPlayerController.setPlayCallBack(() => player.play());
    return true;
  }

  /// Whether [player] is currently rendered by the floating window.
  bool owns(PlPlayerController player) => identical(_active?.player, player);

  /// Closes the floating window.
  ///
  /// In [MiniPlayerSession.fromPush] mode the hidden video page still owns
  /// the player, so the player is paused instead of being disposed and the
  /// page can resume it (at [MiniPlayerSession.onClosed]'s saved position)
  /// when the user goes back. A standalone window disposes the player.
  void close({bool stopPlayback = true}) {
    if (_closing) {
      return;
    }
    _closing = true;
    final current = _active;
    _active = null;
    _setSession(null, clearOffset: true);

    try {
      if (stopPlayback && current != null) {
        if (current.fromPush) {
          if (current.videoRoute?.isActive == true) {
            current.player.pause();
            current.onClosed?.call();
          } else if (identical(
            PlPlayerController.instance,
            current.player,
          )) {
            current.player.dispose();
          }
        } else if (identical(PlPlayerController.instance, current.player)) {
          current.player.dispose();
        }
      }
      PlPlayerController.setPlayCallBack(null);
    } finally {
      _closing = false;
    }
  }

  /// Takes the player back when a video page that was minimized with a
  /// pushed page is shown again. The player is left running; the page reuses
  /// the existing [PlPlayerController].
  bool takeBackFromPush(
    PlPlayerController player,
    Route<dynamic>? route,
  ) {
    final current = _active;
    if (current == null ||
        !identical(current.player, player) ||
        !current.fromPush ||
        !identical(current.videoRoute, route)) {
      return false;
    }
    _active = null;
    _setSession(null);
    PlPlayerController.setPlayCallBack(null);
    return true;
  }

  /// Opens the full video page again at the current position.
  void expand() {
    final current = _active;
    if (current == null) {
      return;
    }
    if (current.fromPush) {
      final route = current.videoRoute;
      final navigator = Get.key.currentState;
      if (route != null && route.isActive && navigator != null) {
        navigator.popUntil((other) => identical(other, route));
        return;
      }
    }
    final progress = current.player.positionInMilliseconds;
    final autoplay = current.player.playerStatus.isPlaying;
    final args = Map<String, dynamic>.from(current.args);
    args['heroTag'] = Utils.makeHeroTag(args['cid'] ?? progress);
    args['progress'] = progress;
    args['autoplay'] = autoplay;
    close(stopPlayback: true);
    PageUtils.toDupNamed('/videoV', arguments: args);
  }

  void _onBeforeGetInstance() {
    // Another video page is about to take over the player. Release the
    // floating window first. A standalone window disposes the player; a
    // window created from a pushed page keeps it for the new page.
    if (isActive) {
      close(stopPlayback: true);
    }
  }

  void _onPlayerDisposed(PlPlayerController player) {
    if (owns(player)) {
      close(stopPlayback: false);
    }
  }

  /// Updates the reactive UI state. Setting Rx values while the widget tree is
  /// locked (for example while a page is unmounted) throws, so defer in that
  /// case.
  void _setSession(MiniPlayerSession? value, {bool clearOffset = false}) {
    void apply() {
      _session.value = value;
      if (clearOffset) {
        offset.value = null;
      }
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      scheduleMicrotask(apply);
    } else {
      apply();
    }
  }
}
