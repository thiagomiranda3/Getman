import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:getman/core/theme/app_theme.dart';
import 'package:getman/core/utils/response_media.dart';
import 'package:getman/features/tabs/domain/entities/request_tab_entity.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_bloc.dart';
import 'package:getman/features/tabs/presentation/bloc/tabs_state.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/binary_response_view.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/csv_response_view.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/html_response_view.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/image_response_view.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/media_response_view.dart';
import 'package:getman/features/tabs/presentation/widgets/response/viewers/pdf_response_view.dart';

enum _MediaTab { preview, raw }

/// Renders a non-textual response: a PREVIEW/RAW toggle over the matching
/// viewer. RAW is always the binary card (size + Save); PREVIEW is the
/// kind-specific viewer, or a "not stored this session" placeholder when the
/// live bytes are gone (restored tab / older time-travel entry).
class ResponseMediaPanel extends StatefulWidget {
  const ResponseMediaPanel({required this.tabId, super.key});
  final String tabId;

  @override
  State<ResponseMediaPanel> createState() => _ResponseMediaPanelState();
}

class _ResponseMediaPanelState extends State<ResponseMediaPanel> {
  _MediaTab _tab = _MediaTab.preview;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TabsBloc, TabsState>(
      buildWhen: (p, n) {
        final pr = p.tabs.byId(widget.tabId)?.response;
        final nr = n.tabs.byId(widget.tabId)?.response;
        return pr?.bodyBytes?.length != nr?.bodyBytes?.length ||
            pr?.body != nr?.body ||
            contentTypeOf(pr?.headers ?? const {}) !=
                contentTypeOf(nr?.headers ?? const {});
      },
      builder: (context, state) {
        final tab = state.tabs.byId(widget.tabId);
        final resp = tab?.response;
        if (resp == null) return const SizedBox.shrink();
        final contentType = contentTypeOf(resp.headers);
        final kind = classifyResponseMedia(
          contentType: contentType,
          url: tab?.config.url,
          sniffBytes: resp.bodyBytes,
        );
        final bytes = resp.bodyBytes;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toggle(context),
            Expanded(
              child: _tab == _MediaTab.raw || bytes == null
                  ? (bytes == null && _tab == _MediaTab.preview
                        ? _notStored(context, resp.body)
                        : BinaryResponseView(
                            bytes: bytes,
                            contentType: contentType,
                            url: tab?.config.url,
                            placeholderBody: resp.body,
                          ))
                  : _viewer(context, kind, bytes, contentType, tab?.config.url),
            ),
          ],
        );
      },
    );
  }

  Widget _viewer(
    BuildContext context,
    ResponseMediaKind kind,
    Uint8List bytes,
    String? contentType,
    String? url,
  ) {
    switch (kind) {
      case ResponseMediaKind.image:
        return ImageResponseView(
          key: const ValueKey('media_preview_image'),
          bytes: bytes,
        );
      case ResponseMediaKind.textual:
        assert(false, 'textual responses must not reach _viewer');
        return const SizedBox.shrink();
      case ResponseMediaKind.csv:
        return CsvResponseView(
          key: const ValueKey('media_preview_csv'),
          bytes: bytes,
        );
      case ResponseMediaKind.html:
        return HtmlResponseView(
          key: const ValueKey('media_preview_html'),
          bytes: bytes,
        );
      case ResponseMediaKind.pdf:
        return PdfResponseView(
          key: const ValueKey('media_preview_pdf'),
          bytes: bytes,
        );
      case ResponseMediaKind.video:
        return MediaResponseView(
          key: const ValueKey('media_preview_video'),
          bytes: bytes,
          isVideo: true,
          contentType: contentType,
          url: url,
        );
      case ResponseMediaKind.audio:
        return MediaResponseView(
          key: const ValueKey('media_preview_audio'),
          bytes: bytes,
          isVideo: false,
          contentType: contentType,
          url: url,
        );
      case ResponseMediaKind.binary:
        return BinaryResponseView(
          bytes: bytes,
          contentType: contentType,
          url: url,
          placeholderBody: '',
        );
    }
  }

  Widget _notStored(BuildContext context, String placeholder) {
    final layout = context.appLayout;
    return Center(
      key: const ValueKey('media_preview_placeholder'),
      child: Padding(
        padding: EdgeInsets.all(layout.pagePadding),
        child: Text(
          'Media not stored this session — re-send to view.\n$placeholder',
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
    );
  }

  Widget _toggle(BuildContext context) {
    final layout = context.appLayout;
    Widget seg(String label, _MediaTab t) {
      final active = _tab == t;
      final bg = context.appPalette.selectorActive;
      return GestureDetector(
        onTap: () => setState(() => _tab = t),
        child: Container(
          key: ValueKey('media_toggle_$label'),
          margin: EdgeInsets.all(layout.tabSpacing),
          padding: EdgeInsets.symmetric(
            horizontal: layout.badgePaddingHorizontal + 4,
            vertical: layout.badgePaddingVertical + 2,
          ),
          decoration: BoxDecoration(
            color: active ? bg : Colors.transparent,
            border: Border.all(
              color: Theme.of(context).dividerColor,
              width: layout.borderThin,
            ),
            borderRadius: BorderRadius.circular(context.appShape.buttonRadius),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: layout.fontSizeSmall,
              fontWeight: context.appTypography.displayWeight,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: layout.pagePadding),
      child: Wrap(
        children: [
          seg('PREVIEW', _MediaTab.preview),
          seg('RAW', _MediaTab.raw),
        ],
      ),
    );
  }
}
