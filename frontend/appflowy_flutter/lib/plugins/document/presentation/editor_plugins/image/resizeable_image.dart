import 'dart:io';
import 'dart:math';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/prelude.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:string_validator/string_validator.dart';

enum ResizableImageState {
  loading,
  loaded,
  failed,
}

class ResizableImage extends StatefulWidget {
  const ResizableImage({
    super.key,
    required this.type,
    required this.alignment,
    required this.editable,
    required this.onResize,
    required this.width,
    required this.src,
    this.height,
    this.onDoubleTap,
    this.onStateChange,
  });

  final String src;
  final CustomImageType type;
  final double width;
  final double? height;
  final Alignment alignment;
  final bool editable;
  final VoidCallback? onDoubleTap;
  final ValueChanged<ResizableImageState>? onStateChange;

  final void Function(double width) onResize;

  @override
  State<ResizableImage> createState() => _ResizableImageState();
}

const _kImageBlockComponentMinWidth = 30.0;

class _ResizableImageState extends State<ResizableImage> {
  final documentService = DocumentService();

  double initialOffset = 0;
  double moveDistance = 0;
  Widget? _cacheImage;

  late double imageWidth;

  @visibleForTesting
  bool onFocus = false;

  UserProfilePB? _userProfilePB;

  @override
  void initState() {
    super.initState();

    imageWidth = widget.width;

    _userProfilePB = context.read<UserWorkspaceBloc?>()?.state.userProfile ??
        context.read<DocumentBloc>().state.userProfilePB;
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.alignment,
      child: SizedBox(
        width: max(_kImageBlockComponentMinWidth, imageWidth - moveDistance),
        height: widget.height,
        child: MouseRegion(
          onEnter: (_) => setState(() => onFocus = true),
          onExit: (_) => setState(() => onFocus = false),
          child: GestureDetector(
            onDoubleTap: widget.onDoubleTap,
            child: _buildResizableImage(context),
          ),
        ),
      ),
    );
  }

  Widget _buildResizableImage(BuildContext context) {
    Widget child;
    final src = widget.src;
    if (isURL(src)) {
      _cacheImage = FlowyNetworkImage(
        url: widget.src,
        width: imageWidth - moveDistance,
        userProfilePB: _userProfilePB,
        onImageLoaded: (isImageInCache) {
          if (isImageInCache) {
            widget.onStateChange?.call(ResizableImageState.loaded);
          }
        },
        progressIndicatorBuilder: (context, _, progress) {
          if (progress.totalSize != null) {
            if (progress.progress == 1) {
              widget.onStateChange?.call(ResizableImageState.loaded);
            } else {
              widget.onStateChange?.call(ResizableImageState.loading);
            }
          }

          return _buildLoading(context);
        },
        errorWidgetBuilder: (_, __, error) {
          widget.onStateChange?.call(ResizableImageState.failed);
          return _ImageLoadFailedWidget(
            width: imageWidth,
            error: error,
            onRetry: () {
              setState(() {
                final retryCounter = FlowyNetworkRetryCounter();
                retryCounter.clear(tag: src, url: src);
              });
            },
          );
        },
      );

      child = _cacheImage!;
    } else {
      // load local file
      _cacheImage ??= Image.file(File(src));
      child = _cacheImage!;
    }
    return Stack(
      children: [
        child,
        if (widget.editable) ...[
          _buildEdgeGesture(
            context,
            top: 0,
            left: 5,
            bottom: 0,
            width: 5,
            onUpdate: (distance) => setState(() => moveDistance = distance),
          ),
          _buildEdgeGesture(
            context,
            top: 0,
            right: 5,
            bottom: 0,
            width: 5,
            onUpdate: (distance) => setState(() => moveDistance = -distance),
          ),
        ],
      ],
    );
  }

  Widget _buildLoading(BuildContext context) {
    return SizedBox(
      height: 150,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.fromSize(
            size: const Size(18, 18),
            child: const CircularProgressIndicator(),
          ),
          SizedBox.fromSize(size: const Size(10, 10)),
          Text(AppFlowyEditorL10n.current.loading),
        ],
      ),
    );
  }

  Widget _buildEdgeGesture(
    BuildContext context, {
    double? top,
    double? left,
    double? right,
    double? bottom,
    double? width,
    void Function(double distance)? onUpdate,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      width: width,
      child: GestureDetector(
        onHorizontalDragStart: (details) {
          initialOffset = details.globalPosition.dx;
        },
        onHorizontalDragUpdate: (details) {
          if (onUpdate != null) {
            double offset = details.globalPosition.dx - initialOffset;
            if (widget.alignment == Alignment.center) {
              offset *= 2.0;
            }
            onUpdate(offset);
          }
        },
        onHorizontalDragEnd: (details) {
          imageWidth =
              max(_kImageBlockComponentMinWidth, imageWidth - moveDistance);
          initialOffset = 0;
          moveDistance = 0;

          widget.onResize(imageWidth);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: onFocus
              ? Center(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: const BorderRadius.all(
                        Radius.circular(5.0),
                      ),
                      border: Border.all(color: Colors.white),
                    ),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}

class _ImageLoadFailedWidget extends StatelessWidget {
  const _ImageLoadFailedWidget({
    required this.width,
    required this.error,
    required this.onRetry,
  });

  final double width;
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final error = _getErrorMessage();
    return Container(
      height: 160,
      width: width,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(4.0)),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FlowySvg(
            FlowySvgs.broken_image_xl,
            size: Size.square(36),
          ),
          FlowyText(
            AppFlowyEditorL10n.current.imageLoadFailed,
            fontSize: 14,
          ),
          const VSpace(4),
          if (error != null)
            FlowyText(
              error,
              textAlign: TextAlign.center,
              color: Theme.of(context).hintColor.withValues(alpha: 0.6),
              fontSize: 10,
              maxLines: 2,
            ),
          const VSpace(12),
          Listener(
            onPointerDown: (event) {
              onRetry();
            },
            child: OutlinedRoundedButton(
              text: LocaleKeys.chat_retry.tr(),
              onTap: () {},
            ),
          ),
        ],
      ),
    );
  }

  String? _getErrorMessage() {
    if (error is HttpExceptionWithStatus) {
      return 'Error ${(error as HttpExceptionWithStatus).statusCode}';
    }

    return null;
  }
}
