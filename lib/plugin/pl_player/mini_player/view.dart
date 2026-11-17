import 'dart:async' show Timer;
import 'dart:io' show Platform;

import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/mini_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/mini_player/layout.dart';
import 'package:PiliPlus/plugin/pl_player/models/play_status.dart';
import 'package:PiliPlus/utils/duration_utils.dart';
import 'package:PiliPlus/utils/ios/pip_helper.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Global floating player layer. It must be placed above the navigator so it
/// stays visible on every page.
class MiniPlayerOverlay extends StatelessWidget {
  const MiniPlayerOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final miniPlayer = MiniPlayerController.instance;
    return Obx(() {
      final session = miniPlayer.session;
      if (session == null) {
        return const SizedBox.shrink();
      }

      final screen = MediaQuery.sizeOf(context);
      final padding = MediaQuery.paddingOf(context);
      final size = miniPlayerSize(
        aspectRatio: session.aspectRatio,
        screen: screen,
      );
      final position = clampMiniPlayerOffset(
        offset:
            miniPlayer.offset.value ??
            defaultMiniPlayerOffset(
              screen: screen,
              padding: padding,
              size: size,
            ),
        screen: screen,
        padding: padding,
        size: size,
      );

      return Positioned(
        left: position.dx,
        top: position.dy,
        width: size.width,
        height: size.height,
        child: _MiniPlayerCard(
          key: ValueKey(session.id),
          session: session,
          onDrag: (delta) {
            miniPlayer.offset.value = clampMiniPlayerOffset(
              offset: (miniPlayer.offset.value ?? position) + delta,
              screen: screen,
              padding: padding,
              size: size,
            );
          },
        ),
      );
    });
  }
}

class _MiniPlayerCard extends StatefulWidget {
  const _MiniPlayerCard({
    super.key,
    required this.session,
    required this.onDrag,
  });

  final MiniPlayerSession session;
  final ValueChanged<Offset> onDrag;

  @override
  State<_MiniPlayerCard> createState() => _MiniPlayerCardState();
}

class _MiniPlayerCardState extends State<_MiniPlayerCard>
    with WidgetsBindingObserver {
  late final PlPlayerController _player = widget.session.player;

  final RxBool _playing = false.obs;
  final RxBool _completed = false.obs;

  bool _pausedByLifecycle = false;

  /// How long the controls stay visible after the last touch interaction.
  static const Duration _controlsDuration = Duration(seconds: 3);

  Timer? _hideTimer;

  /// Desktop: the pointer is over the window.
  bool _hovering = false;

  /// Touch devices: revealed by a tap, hidden again after
  /// [_controlsDuration] or when the video page is opened.
  bool _touchControls = false;

  bool _appActive = true;

  /// The overlay controls are hidden by default. Desktop reveals them while
  /// the pointer is over the window; touch devices reveal them with a tap.
  bool get _showControls =>
      _appActive && (PlatformUtils.isDesktop ? _hovering : _touchControls);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _player.addStatusLister(_onStatus);
    _onStatus(_player.playerStatus);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _player.removeStatusLister(_onStatus);
    super.dispose();
  }

  void _onStatus(PlayerStatus status) {
    _playing.value = status.isPlaying;
    _completed.value = status.isCompleted;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isActive = state == AppLifecycleState.resumed;
    if (_appActive != isActive) {
      _hideTimer?.cancel();
      setState(() {
        _appActive = isActive;
        if (!isActive) {
          _touchControls = false;
        }
      });
    }
    // Keep playing in the system PiP window.
    if (Platform.isIOS && IOSPipHelper.isActive) {
      return;
    }
    if (_player.continuePlayInBackground.value) {
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_player.playerStatus.isPlaying) {
        _pausedByLifecycle = true;
        _player.pause();
      }
    } else if (_pausedByLifecycle) {
      _pausedByLifecycle = false;
      _player.play();
    }
  }

  void _setHovering(bool value) {
    if (_hovering == value) return;
    setState(() => _hovering = value);
  }

  /// Touch devices reveal the controls with the first tap and open the video
  /// page on the next tap. Desktop opens the video page right away.
  void _onTapVideo() {
    if (!PlatformUtils.isDesktop && !_touchControls) {
      _showTouchControls();
      return;
    }
    _expand();
  }

  void _showTouchControls() {
    if (PlatformUtils.isDesktop) return;
    if (!_touchControls) {
      setState(() => _touchControls = true);
    }
    _restartHideTimer();
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    if (PlatformUtils.isDesktop) return;
    _hideTimer = Timer(_controlsDuration, () {
      if (!mounted || !_touchControls) return;
      setState(() => _touchControls = false);
    });
  }

  void _togglePlay() {
    _restartHideTimer();
    if (_player.playerStatus.isCompleted) {
      _player.play(repeat: true);
    } else if (_player.playerStatus.isPlaying) {
      _player.pause();
    } else {
      _player.play();
    }
  }

  void _close() {
    MiniPlayerController.instance.close();
  }

  void _expand() {
    MiniPlayerController.instance.expand();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final videoController = _player.videoController;
    if (videoController == null) {
      return const SizedBox.shrink();
    }

    final card = Material(
      elevation: 8,
      shadowColor: Colors.black54,
      color: Colors.black,
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTapVideo,
        onPanUpdate: (details) => widget.onDrag(details.delta),
        child: Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.contain,
              child: SimpleVideo(
                controller: videoController,
                fill: Colors.black,
              ),
            ),
            Center(
              child: _FadingControls(
                visible: _showControls,
                child: Obx(
                  () => _player.isBuffering.value && _playing.value
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : _MiniIconButton(
                          icon: _completed.value
                              ? Icons.replay
                              : _playing.value
                              ? Icons.pause
                              : Icons.play_arrow,
                          tooltip: _completed.value
                              ? '重新播放'
                              : _playing.value
                              ? '暂停'
                              : '播放',
                          size: 40,
                          onTap: _togglePlay,
                        ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: _FadingControls(
                visible: _showControls,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MiniIconButton(
                      icon: Icons.fullscreen,
                      tooltip: '打开视频页',
                      onTap: _expand,
                    ),
                    const SizedBox(width: 4),
                    _MiniIconButton(
                      icon: Icons.close,
                      tooltip: '关闭小窗',
                      onTap: _close,
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 20, 10, 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xCC000000)],
                  ),
                ),
                child: Row(
                  children: [
                    if (widget.session.title case final title?
                        when title.isNotEmpty) ...[
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ] else
                      const Spacer(),
                    Obx(
                      () => Text(
                        '${DurationUtils.formatDuration(_player.position.value)}'
                        ' / '
                        '${DurationUtils.formatDuration(_player.duration.value)}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Obx(() {
                final duration = _player.duration.value;
                return LinearProgressIndicator(
                  minHeight: 2,
                  value: duration > 0
                      ? (_player.position.value / duration)
                            .clamp(0.0, 1.0)
                            .toDouble()
                      : 0,
                  backgroundColor: Colors.white24,
                  color: theme.colorScheme.primary,
                );
              }),
            ),
          ],
        ),
      ),
    );

    if (!PlatformUtils.isDesktop) {
      return card;
    }
    return MouseRegion(
      onEnter: (_) => _setHovering(true),
      onExit: (_) => _setHovering(false),
      child: card,
    );
  }
}

class _FadingControls extends StatelessWidget {
  const _FadingControls({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: child,
      ),
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.size = 28,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: Colors.black45,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: Colors.white, size: size * 0.62),
          ),
        ),
      ),
    );
  }
}
