import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/response_media.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/binary_response_view.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/media_temp_file.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Plays a video/audio response via media_kit. Bytes are written to a temp
/// file via [writeMediaTempFile] and opened. On web (stub throws) or on any
/// init failure (test VM, missing native libs), degrades to the binary save
/// card.
class MediaResponseView extends StatefulWidget {
  const MediaResponseView({
    required this.bytes,
    required this.isVideo,
    required this.contentType,
    required this.url,
    super.key,
  });

  final Uint8List bytes;
  final bool isVideo;
  final String? contentType;
  final String? url;

  @override
  State<MediaResponseView> createState() => _MediaResponseViewState();
}

class _MediaResponseViewState extends State<MediaResponseView> {
  Player? _player;
  VideoController? _videoController;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      final ext = mediaExtension(
        contentType: widget.contentType,
        url: widget.url,
      );
      final path = await writeMediaTempFile(widget.bytes, ext);
      final player = Player();
      final vc = widget.isVideo ? VideoController(player) : null;
      await player.open(Media('file://$path'), play: false);
      if (!mounted) {
        unawaited(player.dispose());
        return;
      }
      setState(() {
        _player = player;
        _videoController = vc;
      });
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    final player = _player;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    if (_failed) {
      return BinaryResponseView(
        bytes: widget.bytes,
        contentType: widget.contentType,
        url: widget.url,
        placeholderBody: '',
      );
    }
    if (player == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.isVideo && _videoController != null) {
      return Video(controller: _videoController!);
    }
    return _AudioTransport(player: player);
  }
}

/// Minimal play/pause + seek bar for audio.
class _AudioTransport extends StatelessWidget {
  const _AudioTransport({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    final layout = context.appLayout;
    return Padding(
      padding: EdgeInsets.all(layout.pagePadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          StreamBuilder<bool>(
            stream: player.stream.playing,
            initialData: false,
            builder: (context, snap) {
              final playing = snap.data ?? false;
              return IconButton(
                key: const ValueKey('audio_play_pause'),
                iconSize: layout.iconSize,
                icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
                onPressed: player.playOrPause,
              );
            },
          ),
          StreamBuilder<Duration>(
            stream: player.stream.position,
            initialData: Duration.zero,
            builder: (context, posSnap) {
              return StreamBuilder<Duration>(
                stream: player.stream.duration,
                initialData: Duration.zero,
                builder: (context, durSnap) {
                  final dur = durSnap.data ?? Duration.zero;
                  final pos = posSnap.data ?? Duration.zero;
                  final maxMs = dur.inMilliseconds == 0
                      ? 1.0
                      : dur.inMilliseconds.toDouble();
                  return Slider(
                    value: pos.inMilliseconds
                        .clamp(0, maxMs.toInt())
                        .toDouble(),
                    max: maxMs,
                    onChanged: (v) => player.seek(
                      Duration(milliseconds: v.toInt()),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
