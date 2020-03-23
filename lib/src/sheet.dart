import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'util.dart';

typedef SheetBuilder = Widget Function(BuildContext context, SheetState state);

typedef SheetListener = void Function(SheetState state);

/// How the snaps will be positioned.
enum SnapPositioning {
  /// Positions the snaps relative to the total
  /// available space (that is, the maximum height the widget can expand to).
  relativeToAvailableSpace,

  /// Positions the snaps relative to the total height
  /// of the sheet itself.
  relativeToSheetHeight,

  /// Positions the snaps at the given pixel offset. If the
  /// sheet is smaller than the offset, it will snap to the max possible offset.
  pixelOffset,
}

/// Defines how a [SlidingSheet] should snap, or if it should at all.
class SnapSpec {
  /// If true, the [SlidingSheet] will snap to the provided [snappings].
  /// If false, the [SlidingSheet] will slide from minExtent to maxExtent
  /// and then begin to scroll.
  final bool snap;

  /// The snap extents for a [SlidingSheet].
  ///
  /// The minimum and maximum values will represent the thresholds in which
  /// the [SlidingSheet] will slide. When the child of the sheet is bigger
  /// than the available space defined by the minimum and maximum extent,
  /// it will begin to scroll.
  final List<double> snappings;

  /// How the snaps will be positioned:
  /// - [SnapPositioning.relativeToAvailableSpace] positions the snaps relative to the total
  /// available space (that is, the maximum height the widget can expand to). All values must be between 0 and 1.
  /// - [SnapPositioning.relativeToSheetHeight] positions the snaps relative to the total size
  /// of the sheet itself. All values must be between 0 and 1.
  /// - [SnapPositioning.pixelOffset] positions the snaps at the given pixel offset. If the
  /// sheet is smaller than the offset, it will snap to the max possible offset.
  final SnapPositioning positioning;

  /// A callback function that gets called when the [SlidingSheet] snaps to an extent.
  final void Function(SheetState, double snap) onSnap;
  const SnapSpec({
    this.snap = true,
    this.snappings = const [0.4, 1.0],
    this.positioning = SnapPositioning.relativeToAvailableSpace,
    this.onSnap,
  })  : assert(snap != null),
        assert(snappings != null),
        assert(positioning != null);

  // The snap extent that makes header and footer fully visible without account for vertical padding on the [SlidingSheet].
  static const double headerFooterSnap = -1;
  // The snap extent that makes the header fully visible without account for top padding on the [SlidingSheet].
  static const double headerSnap = -2;
  // The snap extent that makes the footer fully visible without account for bottom padding on the [SlidingSheet].
  static const double footerSnap = -3;
  // The snap extent that expands the whole [SlidingSheet]
  static const double expanded = double.infinity;
  static _isSnap(double snap) =>
      snap == expanded || snap == headerFooterSnap || snap == headerSnap || snap == footerSnap;

  double get minSnap => snappings.first;
  double get maxSnap => snappings.last;

  SnapSpec copyWith({
    bool snap,
    List<double> snappings,
    SnapPositioning positioning,
    void Function(SheetState, double snap) onSnap,
  }) {
    return SnapSpec(
      snap: snap ?? this.snap,
      snappings: snappings ?? this.snappings,
      positioning: positioning ?? this.positioning,
      onSnap: onSnap ?? this.onSnap,
    );
  }

  @override
  String toString() {
    return 'SnapSpec(snap: $snap, snappings: $snappings, positioning: $positioning, onSnap: $onSnap)';
  }

  @override
  bool operator ==(Object o) {
    if (identical(this, o)) return true;

    return o is SnapSpec && o.snap == snap && listEquals(o.snappings, snappings) && o.positioning == positioning;
  }

  @override
  int get hashCode {
    return snap.hashCode ^ snappings.hashCode ^ positioning.hashCode;
  }
}

/// Defines the scroll effects, physics and more.
class ScrollSpec {
  /// Whether the containing ScrollView should overscroll.
  final bool overscroll;

  /// The color of the overscroll when [overscroll] is true.
  final Color overscrollColor;

  /// The physics of the containing ScrollView.
  final ScrollPhysics physics;
  const ScrollSpec({
    this.overscroll = true,
    this.overscrollColor,
    this.physics,
  });

  factory ScrollSpec.overscroll({Color color}) => ScrollSpec(overscrollColor: color);

  factory ScrollSpec.bouncingScroll() => ScrollSpec(physics: BouncingScrollPhysics());
}

/// A widget that can be dragged and scrolled in a single gesture and snapped
/// to a list of extents.
///
/// The [builder] parameter must not be null.
class SlidingSheet extends StatefulWidget {
  /// {@template sliding_sheet.builder}
  /// The builder for the main content of the sheet that will be scrolled if
  /// the content is bigger than the height that the sheet can expand to.
  /// {@endtemplate}
  final SheetBuilder builder;

  /// {@template sliding_sheet.headerBuilder}
  /// The builder for a header that will be displayed at the top of the sheet
  /// that wont be scrolled.
  /// {@endtemplate}
  final SheetBuilder headerBuilder;

  /// {@template sliding_sheet.footerBuilder}
  /// The builder for a footer that will be displayed at the bottom of the sheet
  /// that wont be scrolled.
  /// {@endtemplate}
  final SheetBuilder footerBuilder;

  /// {@template sliding_sheet.snapSpec}
  /// The [SnapSpec] that defines how the sheet should snap or if it should at all.
  /// {@endtemplate}
  final SnapSpec snapSpec;

  /// {@template sliding_sheet.duration}
  /// The base animation duration for the sheet. Swipes and flings may have a different duration.
  /// {@endtemplate}
  final Duration duration;

  /// {@template sliding_sheet.color}
  /// The background color of the sheet.
  /// {@endtemplate}
  final Color color;

  /// {@template sliding_sheet.backdropColor}
  /// The color of the shadow that is displayed behind the sheet.
  /// {@endtemplate}
  final Color backdropColor;

  /// {@template sliding_sheet.shadowColor}
  /// The color of the drop shadow of the sheet when [elevation] is > 0.
  /// {@endtemplate}
  final Color shadowColor;

  /// {@template sliding_sheet.elevation}
  /// The elevation of the sheet.
  /// {@endtemplate}
  final double elevation;

  /// {@template sliding_sheet.padding}
  /// The amount to inset the children of the sheet.
  /// {@endtemplate}
  final EdgeInsets padding;

  /// {@template sliding_sheet.addTopViewPaddingWhenAtFullscreen}
  /// If true, adds the top padding returned by
  /// `MediaQuery.of(context).viewPadding.top` to the [padding] when taking
  /// up the full screen.
  ///
  /// This can be used to easily avoid the content of the sheet from being
  /// under the statusbar, which is especially useful when having a header.
  /// {@endtemplate}
  final bool addTopViewPaddingOnFullscreen;

  /// {@template sliding_sheet.margin}
  /// The amount of the empty space surrounding the sheet.
  /// {@endtemplate}
  final EdgeInsets margin;

  /// {@template sliding_sheet.border}
  /// A border that will be drawn around the sheet.
  /// {@endtemplate}
  final Border border;

  /// {@template sliding_sheet.cornerRadius}
  /// The radius of the top corners of this sheet.
  /// {@endtemplate}
  final double cornerRadius;

  /// {@template sliding_sheet.cornerRadiusOnFullscreen}
  /// The radius of the top corners of this sheet when expanded to fullscreen.
  ///
  /// This parameter can be used to easily implement the common Material
  /// behaviour of sheets to go from rounded corners to sharp corners when
  /// taking up the full screen.
  /// {@endtemplate}
  final double cornerRadiusOnFullscreen;

  /// If true, will collapse the sheet when the sheets backdrop was tapped.
  final bool closeOnBackdropTap;

  /// {@template sliding_sheet.listener}
  /// A callback that will be invoked when the sheet gets dragged or scrolled
  /// with current state information.
  /// {@endtemplate}
  final SheetListener listener;

  /// {@template sliding_sheet.controller}
  /// A controller to control the state of the sheet.
  /// {@endtemplate}
  final SheetController controller;

  /// The route of the sheet when used in a bottom sheet dialog. This parameter
  /// is assigned internally and should not be explicitly assigned.
  final _SlidingSheetRoute route;

  /// {@template sliding_sheet.scrollSpec}
  /// The [ScrollSpec] of the containing ScrollView.
  /// {@endtemplate}
  final ScrollSpec scrollSpec;

  /// {@template sliding_sheet.maxWidth}
  /// The maximum width of the sheet.
  ///
  /// Usually set for large screens. By default the [SlidingSheet]
  /// expands to the total available width.
  /// {@endtemplate}
  final double maxWidth;

  /// {@template sliding_sheet.maxWidth}
  /// The minimum height of the sheet.
  ///
  /// By default, the sheet sizes itself as big as its children.
  /// {@endtemplate}
  final double minHeight;

  /// If true, closes the sheet when it is open and prevents the route
  /// from being popped.
  final bool closeSheetOnBackButtonPressed;
  SlidingSheet({
    Key key,
    @required this.builder,
    this.headerBuilder,
    this.footerBuilder,
    this.snapSpec = const SnapSpec(),
    this.duration = const Duration(milliseconds: 800),
    this.color = Colors.white,
    this.backdropColor,
    this.shadowColor = Colors.black54,
    this.elevation = 0.0,
    this.padding,
    this.addTopViewPaddingOnFullscreen = false,
    this.margin,
    this.border,
    this.cornerRadius = 0.0,
    this.cornerRadiusOnFullscreen,
    this.closeOnBackdropTap = false,
    this.listener,
    this.controller,
    this.route,
    this.scrollSpec = const ScrollSpec(overscroll: false),
    this.maxWidth = double.infinity,
    this.minHeight,
    this.closeSheetOnBackButtonPressed = false,
  })  : assert(builder != null),
        assert(duration != null),
        assert(snapSpec != null),
        assert(snapSpec.snappings.length >= 2, 'There must be at least two snappings to snap in between.'),
        assert(snapSpec.minSnap != snapSpec.maxSnap || route != null, 'The min and max snaps cannot be equal.'),
        super(key: key);

  @override
  _SlidingSheetState createState() => _SlidingSheetState();
}

class _SlidingSheetState extends State<SlidingSheet> with TickerProviderStateMixin {
  GlobalKey childKey;
  GlobalKey headerKey;
  GlobalKey footerKey;
  GlobalKey parentKey;

  Widget child;
  Widget header;
  Widget footer;

  List<double> snappings;

  double childHeight = 0;
  double headerHeight = 0;
  double footerHeight = 0;
  double availableHeight = 0;

  // Whether a dismiss was already triggered by the sheet itself
  // and thus further route pops can be safely ignored.
  bool dismissUnderway = false;
  // The current sheet extent.
  _SheetExtent extent;
  // The ScrollController for the sheet.
  _DragableScrollableSheetController controller;

  // Whether the sheet has drawn its first frame.
  bool get isLaidOut => availableHeight > 0 && childHeight > 0;
  // The total height of all sheet components.
  double get sheetHeight => childHeight + headerHeight + footerHeight + padding.vertical + borderHeight;
  // The maxiumum height that this sheet will cover.
  double get maxHeight => math.min(sheetHeight, availableHeight);
  bool get isCoveringFullExtent => sheetHeight >= availableHeight;

  double get currentExtent => extent?.currentExtent ?? minExtent;
  set currentExtent(double value) => extent?.currentExtent = value;
  double get headerExtent => isLaidOut ? (headerHeight + (borderHeight / 2)) / availableHeight : 0.0;
  double get footerExtent => isLaidOut ? (footerHeight + (borderHeight / 2)) / availableHeight : 0.0;
  double get headerFooterExtent => headerExtent + footerExtent;
  double get minExtent => snappings[fromBottomSheet ? 1 : 0].clamp(0.0, 1.0);
  double get maxExtent => snappings.last.clamp(0.0, 1.0);

  bool get fromBottomSheet => widget.route != null;
  ScrollSpec get scrollSpec => widget.scrollSpec;
  SnapSpec get snapSpec => widget.snapSpec;
  SnapPositioning get snapPositioning => snapSpec.positioning;

  double get borderHeight => (widget.border?.top?.width ?? 0) * 2;
  EdgeInsets get padding {
    final begin = widget.padding ?? const EdgeInsets.all(0);

    if (!widget.addTopViewPaddingOnFullscreen || !isLaidOut) {
      return begin;
    }

    final statusBarHeight = 24;
    final end = begin.copyWith(top: begin.top + statusBarHeight);
    return EdgeInsets.lerp(begin, end, lerpFactor);
  }

  double get cornerRadius {
    if (widget.cornerRadiusOnFullscreen == null) return widget.cornerRadius;
    return lerpDouble(widget.cornerRadius, widget.cornerRadiusOnFullscreen, lerpFactor);
  }

  double get lerpFactor {
    if (maxExtent != 1.0 && isLaidOut) return 0.0;

    final snap = snappings[math.max(snappings.length - 2, 0)];
    return Interval(
      snap >= 0.7 ? snap : 0.85,
      1.0,
    ).transform(currentExtent);
  }

  // The current state of this sheet.
  SheetState get state => SheetState(
        extent,
        extent: _reverseSnap(currentExtent),
        minExtent: _reverseSnap(minExtent),
        maxExtent: _reverseSnap(maxExtent),
        isLaidOut: isLaidOut,
      );

  @override
  void initState() {
    super.initState();
    // Assign the keys that will be used to determine the size of
    // the children.
    childKey = GlobalKey();
    headerKey = GlobalKey();
    footerKey = GlobalKey();
    parentKey = GlobalKey();

    _calculateSnappings();

    // Call the listener when the extent or scroll position changes.
    final listener = () {
      if (isLaidOut) {
        final state = this.state;
        widget.listener?.call(state);
        widget.controller?._state = state;
      }
    };

    controller = _DragableScrollableSheetController(
      this,
    )..addListener(listener);

    extent = _SheetExtent(
      controller,
      isFromBottomSheet: fromBottomSheet,
      snappings: snappings,
      listener: (extent) => listener(),
    );

    _assignSheetController();

    _measure();
    postFrame(() {
      if (fromBottomSheet) {
        // Snap to the initial snap with a one frame delay when the
        // extents have been correctly calculated.
        snapToExtent(minExtent);

        // When the route gets popped we animate fully out - not just
        // to the minExtent.
        widget.route.popped.then(
          (_) {
            if (!dismissUnderway) {
              controller.jumpTo(controller.offset);
              controller.snapToExtent(0.0, this, clamp: false);
            }
          },
        );
      } else {
        setState(() => currentExtent = minExtent);
      }
    });
  }

  // Measure the height of all sheet components.
  void _measure() {
    postFrame(() {
      final RenderBox child = childKey?.currentContext?.findRenderObject();
      final RenderBox header = headerKey?.currentContext?.findRenderObject();
      final RenderBox footer = footerKey?.currentContext?.findRenderObject();
      final RenderBox parent = parentKey?.currentContext?.findRenderObject();

      final isChildLaidOut = child?.hasSize == true;
      childHeight = isChildLaidOut ? child.size.height : 0;

      final isHeaderLaidOut = header?.hasSize == true;
      headerHeight = isHeaderLaidOut ? header.size.height : 0;

      final isFooterLaidOut = footer?.hasSize == true;
      footerHeight = isFooterLaidOut ? footer.size.height : 0;

      final isParentLaidOut = parent?.hasSize == true;
      availableHeight = isParentLaidOut ? parent.size.height : 0;

      _calculateSnappings();

      extent
        ..snappings = snappings
        ..targetHeight = math.min(sheetHeight, availableHeight)
        ..childHeight = childHeight
        ..headerHeight = headerHeight
        ..footerHeight = footerHeight
        ..availableHeight = availableHeight
        ..maxExtent = maxExtent
        ..minExtent = minExtent;
    });
  }

  @override
  void didUpdateWidget(SlidingSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    _measure();
    _assignSheetController();

    extent.snappings = snappings;
    // Animate to the next snap if the SnapSpec changed and the sheet
    // is currently not interacted with.
    if (oldWidget.snapSpec != snapSpec) {
      if (!controller.inInteraction) {
        controller.imitateFling();
      }
    }
  }

  // A snap is defined relative to its availableHeight.
  // Here we handle all available snap positions and normalize them
  // to the availableHeight.
  double _normalizeSnap(double snap) {
    void isValidRelativeSnap([String message]) {
      assert(
        SnapSpec._isSnap(snap) || (snap >= 0.0 && snap <= 1.0),
        message ?? 'Relative snap $snap is not between 0 and 1.',
      );
    }

    if (availableHeight > 0) {
      final maxPossibleExtent = isLaidOut ? (sheetHeight / availableHeight).clamp(0.0, 1.0) : 1.0;
      double extent = snap;
      switch (snapPositioning) {
        case SnapPositioning.relativeToAvailableSpace:
          isValidRelativeSnap();
          break;
        case SnapPositioning.relativeToSheetHeight:
          isValidRelativeSnap();
          extent = (snap * maxHeight) / availableHeight;
          break;
        case SnapPositioning.pixelOffset:
          extent = snap / availableHeight;
          break;
        default:
          return snap.clamp(0.0, 1.0);
      }

      if (snap == SnapSpec.headerSnap) {
        assert(header != null, 'There is no available header to snap to!');
        extent = headerExtent;
      } else if (snap == SnapSpec.footerSnap) {
        assert(footer != null, 'There is no available footer to snap to!');
        extent = footerExtent;
      } else if (snap == SnapSpec.headerFooterSnap) {
        assert(header != null || footer != null, 'There is neither a header nor a footer to snap to!');
        extent = headerFooterExtent;
      } else if (snap == double.infinity) {
        extent = maxPossibleExtent;
      }

      return math.min(extent, maxPossibleExtent).clamp(0.0, 1.0);
    } else {
      return snap.clamp(0.0, 1.0);
    }
  }

  // Reverse a normalized snap.
  double _reverseSnap(double snap) {
    if (isLaidOut && childHeight > 0) {
      switch (snapPositioning) {
        case SnapPositioning.relativeToAvailableSpace:
          return snap;
        case SnapPositioning.relativeToSheetHeight:
          return snap * (availableHeight / sheetHeight);
        case SnapPositioning.pixelOffset:
          return snap * availableHeight;
        default:
          return snap.clamp(0.0, 1.0);
      }
    } else {
      return snap.clamp(0.0, 1.0);
    }
  }

  void _calculateSnappings() => snappings = snapSpec.snappings.map(_normalizeSnap).toList()..sort();

  // Assign the controller functions to actual methods.
  void _assignSheetController() {
    final controller = widget.controller;
    if (controller != null) {
      // Assign the controller functions to the state functions.
      if (!fromBottomSheet) controller._rebuild = rebuild;
      controller._scrollTo = scrollTo;
      controller._snapToExtent = (snap, {duration}) => snapToExtent(_normalizeSnap(snap), duration: duration);
      controller._expand = () => snapToExtent(maxExtent);
      controller._collapse = () => snapToExtent(minExtent);
      controller._show = () async {
        if (state.isHidden) return snapToExtent(minExtent, clamp: false);
      };
      controller._hide = () async {
        if (state.isShown) return snapToExtent(0.0, clamp: false);
      };
    }
  }

  Future snapToExtent(double snap, {Duration duration, double velocity = 0, bool clamp}) async {
    if (!isLaidOut) return null;

    duration ??= widget.duration;
    if (!state.isAtTop) {
      duration *= 0.5;
      await controller.animateTo(
        0,
        duration: duration,
        curve: Curves.easeInCubic,
      );
    }

    return controller.snapToExtent(
      snap,
      this,
      duration: duration,
      velocity: velocity,
      clamp: clamp ?? (!fromBottomSheet || (fromBottomSheet && snap != 0.0)),
    );
  }

  Future scrollTo(double offset, {Duration duration, Curve curve}) async {
    if (!isLaidOut) return null;

    duration ??= widget.duration;
    if (!extent.isAtMax) {
      duration *= 0.5;
      await snapToExtent(
        maxExtent,
        duration: duration,
      );
    }

    return controller.animateTo(
      offset,
      duration: duration ?? widget.duration,
      curve: curve ?? (!extent.isAtMax ? Curves.easeOutCirc : Curves.ease),
    );
  }

  void _pop(double velocity) {
    if (fromBottomSheet && !dismissUnderway && Navigator.canPop(context)) {
      dismissUnderway = true;
      Navigator.pop(context);
    }

    snapToExtent(fromBottomSheet ? 0.0 : minExtent, velocity: velocity);
  }

  void rebuild() {
    _callBuilders();
    _measure();
  }

  void _callBuilders() {
    if (context != null) {
      header = _delegateInteractions(widget.headerBuilder?.call(context, state));
      footer = _delegateInteractions(widget.footerBuilder?.call(context, state));
      child = widget.builder?.call(context, state);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    rebuild();

    // ValueListenableBuilder is used to update the sheet irrespective of its children.
    final sheet = ValueListenableBuilder(
      valueListenable: extent._currentExtent,
      builder: (context, value, _) {
        // Wrap the scrollView in a ScrollConfiguration to
        // remove the default overscroll effect.
        Widget scrollView = ScrollConfiguration(
          behavior: ScrollBehavior(),
          child: SingleChildScrollView(
            controller: controller,
            physics: scrollSpec.physics ?? ScrollPhysics(),
            padding: EdgeInsets.only(
              top: header == null ? padding.top : 0.0,
              bottom: footer == null ? padding.bottom : 0.0,
            ),
            child: Container(
              key: childKey,
              child: child,
            ),
          ),
        );

        // Add the overscroll if required again if required
        if (scrollSpec.overscroll) {
          scrollView = GlowingOverscrollIndicator(
            axisDirection: AxisDirection.down,
            color: scrollSpec.overscrollColor ?? theme.accentColor,
            child: scrollView,
          );
        }

        // Hide the sheet for the first frame until the extents are
        // correctly measured.
        return Visibility(
          key: parentKey,
          visible: isLaidOut,
          maintainInteractivity: false,
          maintainSemantics: true,
          maintainSize: true,
          maintainState: true,
          maintainAnimation: true,
          child: Stack(
            children: <Widget>[
              if (widget.closeOnBackdropTap || (widget.backdropColor != null && widget.backdropColor.opacity != 0))
                GestureDetector(
                  onTap: widget.closeOnBackdropTap ? () => _pop(0.0) : null,
                  child: Opacity(
                    opacity: currentExtent != 0 ? (currentExtent / minExtent).clamp(0.0, 1.0) : 0.0,
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      color: widget.backdropColor,
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: widget.minHeight ?? 0.0,
                    maxWidth: widget.maxWidth ?? double.infinity,
                  ),
                  child: SizedBox.expand(
                    // Fractionally size the box until the header/footer would get clipped.
                    // Then translate the header/footer in and out of the view.
                    child: FractionallySizedBox(
                      heightFactor: isLaidOut ? currentExtent.clamp(headerFooterExtent, 1.0) : 1.0,
                      alignment: Alignment.bottomCenter,
                      child: FractionalTranslation(
                        translation: Offset(
                          0,
                          headerFooterExtent > 0.0
                              ? (1 - (currentExtent.clamp(0.0, headerFooterExtent) / headerFooterExtent))
                              : 0.0,
                        ),
                        child: _SheetContainer(
                          color: widget.color ?? Colors.white,
                          border: widget.border,
                          margin: widget.margin,
                          // Add the vertical padding to the scrollView when header or footer is
                          // not null in order to not clip the scrolling child.
                          padding: EdgeInsets.fromLTRB(
                            padding.left,
                            header != null ? padding.top : 0.0,
                            padding.right,
                            footer != null ? padding.bottom : 0.0,
                          ),
                          elevation: widget.elevation,
                          shadowColor: widget.shadowColor,
                          customBorders: BorderRadius.vertical(
                            top: Radius.circular(cornerRadius),
                          ),
                          child: Stack(
                            children: <Widget>[
                              Column(
                                children: <Widget>[
                                  SizedBox(height: headerHeight),
                                  Expanded(child: scrollView),
                                  SizedBox(height: footerHeight),
                                ],
                              ),
                              if (header != null)
                                Align(
                                  alignment: Alignment.topCenter,
                                  child: Container(
                                    key: headerKey,
                                    child: header,
                                  ),
                                ),
                              if (footer != null)
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    key: footerKey,
                                    child: footer,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (widget.closeSheetOnBackButtonPressed == false) {
      return sheet;
    }

    return WillPopScope(
      child: sheet,
      onWillPop: () async {
        if (!state.isCollapsed) {
          snapToExtent(minExtent);
          return false;
        }

        return true;
      },
    );
  }

  Widget _delegateInteractions(Widget child) {
    if (child == null) return child;

    double start = 0;
    double end = 0;

    void onDragEnd([double velocity = 0.0]) {
      controller.imitateFling(velocity);

      // If a header was dragged, but the scroll view is not at the top
      // animate to the top when the drag has ended.
      if (!state.isAtTop && (start - end).abs() > 5) {
        controller.animateTo(0.0, duration: widget.duration * .5, curve: Curves.ease);
      }
    }

    return GestureDetector(
      onVerticalDragStart: (details) {
        start = details.localPosition.dy;
        end = start;
      },
      onVerticalDragUpdate: (details) {
        end = details.localPosition.dy;
        final delta = swapSign(details.delta.dy);
        controller.imitiateDrag(delta);
      },
      onVerticalDragEnd: (details) {
        final velocity = swapSign(details.velocity.pixelsPerSecond.dy);
        onDragEnd(velocity);
      },
      onVerticalDragCancel: onDragEnd,
      child: child,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

class _SheetExtent {
  final bool isFromBottomSheet;
  final _DragableScrollableSheetController controller;
  List<double> snappings;
  double targetHeight = 0;
  double childHeight = 0;
  double headerHeight = 0;
  double footerHeight = 0;
  double availableHeight = 0;
  _SheetExtent(
    this.controller, {
    @required this.isFromBottomSheet,
    @required this.snappings,
    @required void Function(double) listener,
  }) {
    maxExtent = snappings.last.clamp(0.0, 1.0);
    minExtent = snappings.first.clamp(0.0, 1.0);
    _currentExtent = ValueNotifier(minExtent)..addListener(() => listener(currentExtent));
  }

  ValueNotifier<double> _currentExtent;
  double get currentExtent => _currentExtent.value;
  set currentExtent(double value) {
    assert(value != null);
    _currentExtent.value = math.min(value, maxExtent);
  }

  double get sheetHeight => childHeight + headerHeight + footerHeight;

  double maxExtent;
  double minExtent;
  double get additionalMinExtent => isAtMin ? 0.0 : 1.0;
  double get additionalMaxExtent => isAtMax ? 0.0 : 1.0;

  bool get isAtMax => currentExtent >= maxExtent;
  bool get isAtMin => currentExtent <= minExtent && minExtent != maxExtent;

  void addPixelDelta(double pixelDelta) {
    if (targetHeight == 0 || availableHeight == 0) return;
    currentExtent = (currentExtent + (pixelDelta / availableHeight));

    // The bottom sheet should be allowed to be dragged below its min extent.
    if (!isFromBottomSheet) currentExtent = currentExtent.clamp(minExtent, maxExtent);
  }

  double get scrollOffset {
    try {
      return math.max(controller.offset, 0);
    } catch (e) {
      return 0;
    }
  }

  bool get isAtTop => scrollOffset <= 0;

  bool get isAtBottom {
    try {
      return scrollOffset >= controller.position.maxScrollExtent;
    } catch (e) {
      return false;
    }
  }
}

class _DragableScrollableSheetController extends ScrollController {
  final _SlidingSheetState sheet;
  _DragableScrollableSheetController(this.sheet);

  _SheetExtent get extent => sheet.extent;
  void Function(double) get onPop => sheet._pop;
  Duration get duration => sheet.widget.duration;
  SnapSpec get snapSpec => sheet.snapSpec;

  double get currentExtent => extent.currentExtent;
  double get maxExtent => extent.maxExtent;
  double get minExtent => extent.minExtent;

  bool inDrag = false;
  bool animating = false;
  bool get inInteraction => inDrag || animating;

  _DraggableScrollableSheetScrollPosition _currentPosition;

  AnimationController controller;

  TickerFuture snapToExtent(
    double snap,
    TickerProvider vsync, {
    double velocity = 0,
    Duration duration,
    bool clamp = true,
  }) {
    _dispose();

    if (clamp) snap = snap.clamp(extent.minExtent, extent.maxExtent);
    final speedFactor = (math.max((currentExtent - snap).abs(), .25) / maxExtent) *
        (1 - ((velocity.abs() / 2000) * 0.3).clamp(.0, 0.3));
    duration = this.duration * speedFactor;

    controller = AnimationController(duration: duration, vsync: vsync);
    final tween = Tween(begin: extent.currentExtent, end: snap).animate(
      CurvedAnimation(parent: controller, curve: velocity.abs() > 300 ? Curves.easeOutCubic : Curves.ease),
    );

    animating = true;
    controller.addListener(() => this.extent.currentExtent = tween.value);
    return controller.forward()
      ..whenComplete(() {
        controller.dispose();
        animating = false;

        // Invoke the snap callback.
        snapSpec?.onSnap?.call(
          sheet.state,
          sheet._reverseSnap(snap),
        );
      });
  }

  void imitiateDrag(double delta) {
    inDrag = true;
    extent.addPixelDelta(delta);
  }

  void imitateFling([double velocity = 0.0]) {
    if (velocity != 0.0) {
      _currentPosition?.goBallistic(velocity);
    } else {
      inDrag = true;
      _currentPosition?.didEndScroll();
    }
  }

  @override
  _DraggableScrollableSheetScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition oldPosition,
  ) {
    _currentPosition = _DraggableScrollableSheetScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      extent: extent,
      onPop: onPop,
      scrollController: this,
    );

    return _currentPosition;
  }

  void _dispose() {
    if (animating) {
      controller?.stop();
      controller?.dispose();
    }
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }
}

class _DraggableScrollableSheetScrollPosition extends ScrollPositionWithSingleContext {
  final _SheetExtent extent;
  final void Function(double) onPop;
  final _DragableScrollableSheetController scrollController;
  _DraggableScrollableSheetScrollPosition({
    @required ScrollPhysics physics,
    @required ScrollContext context,
    ScrollPosition oldPosition,
    String debugLabel,
    @required this.extent,
    @required this.onPop,
    @required this.scrollController,
  })  : assert(extent != null),
        assert(onPop != null),
        assert(scrollController != null),
        super(
          physics: physics,
          context: context,
          oldPosition: oldPosition,
          debugLabel: debugLabel,
        );

  VoidCallback _dragCancelCallback;
  bool up = true;
  double lastVelocity = 0.0;

  bool get inDrag => scrollController.inDrag;
  set inDrag(bool value) => scrollController.inDrag = value;

  SnapSpec get snapBehavior => scrollController.snapSpec;
  ScrollSpec get scrollSpec => scrollController.sheet.scrollSpec;
  List<double> get snappings => extent.snappings;
  bool get fromBottomSheet => extent.isFromBottomSheet;
  bool get snap => snapBehavior.snap;
  bool get shouldScroll => pixels > 0.0 && extent.isAtMax;
  bool get isCoveringFullExtent => scrollController.sheet.isCoveringFullExtent;
  double get availableHeight => extent.targetHeight;
  double get currentExtent => extent.currentExtent;
  double get maxExtent => extent.maxExtent;
  double get minExtent => extent.minExtent;
  double get offset => scrollController.offset;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    // We need to provide some extra extent if we haven't yet reached the max or
    // min extents. Otherwise, a list with fewer children than the extent of
    // the available space will get stuck.
    return super.applyContentDimensions(
      minScrollExtent - extent.additionalMinExtent,
      maxScrollExtent + extent.additionalMaxExtent,
    );
  }

  @override
  void applyUserOffset(double delta) {
    up = delta.isNegative;
    inDrag = true;

    if (!shouldScroll &&
        (!(extent.isAtMin || extent.isAtMax) ||
            (extent.isAtMin && (delta < 0 || fromBottomSheet)) ||
            (extent.isAtMax && delta > 0))) {
      extent.addPixelDelta(-delta);
    } else if (!extent.isAtMin) {
      super.applyUserOffset(delta);
    }
  }

  @override
  void didEndScroll() {
    super.didEndScroll();

    if (inDrag &&
        ((snap && !extent.isAtMax && !extent.isAtMin && !shouldScroll) ||
            (fromBottomSheet && currentExtent < minExtent))) {
      goSnapped(0.0);
      inDrag = false;
    }
  }

  @override
  void goBallistic(double velocity) {
    up = !velocity.isNegative;
    lastVelocity = velocity;

    // There is an issue with the bouncing scroll physics that when the sheet doesn't cover the full extent
    // the bounce back of the simulation would be so fast to close the sheet again, although it was swiped
    // upwards. Here we soften the bounce back to prevent that from happening.
    if (velocity < 0 && !inDrag && (scrollSpec.physics is BouncingScrollPhysics) && !isCoveringFullExtent) {
      velocity /= 8;
    }

    if (velocity != 0) inDrag = false;

    if (velocity == 0.0 || (velocity.isNegative && shouldScroll) || (!velocity.isNegative && extent.isAtMax)) {
      super.goBallistic(velocity);
      return;
    }

    // Scrollable expects that we will dispose of its current _dragCancelCallback
    _dragCancelCallback?.call();
    _dragCancelCallback = null;

    snap ? goSnapped(velocity) : goUnsnapped(velocity);
  }

  void goSnapped(double velocity) {
    velocity = velocity.abs();
    const flingThreshold = 1700;

    if (velocity > flingThreshold) {
      if (!up) {
        // Pop from the navigator on down fling.
        onPop(velocity);
      } else if (currentExtent > 0.0) {
        scrollController.snapToExtent(maxExtent, context.vsync, velocity: velocity);
      }
    } else {
      const snapToNextThreshold = 300;

      // Find the next snap based on the velocity.
      double distance = double.maxFinite;
      double snap;
      final slow = velocity < snapToNextThreshold;
      final target = !slow
          ? ((up ? 1 : -1) * (((velocity * .45) * (1 - currentExtent)) / flingThreshold)) + currentExtent
          : currentExtent;

      void findSnap([bool greaterThanCurrent = true]) {
        for (var i = 0; i < snappings.length; i++) {
          final stop = snappings[i];
          final valid = slow || !greaterThanCurrent || ((up && stop >= target) || (!up && stop <= target));

          if (valid) {
            final dis = (stop - target).abs();
            if (dis < distance) {
              distance = dis;
              snap = stop;
            }
          }
        }
      }

      // First try to find a snap higher than the current extent.
      // If there is non (snap == null), find the next snap.
      findSnap();
      if (snap == null) findSnap(false);

      if (snap == 0.0) {
        onPop(velocity);
      } else if (snap != extent.currentExtent && currentExtent > 0) {
        scrollController.snapToExtent(
          snap.clamp(minExtent, maxExtent),
          context.vsync,
          velocity: velocity,
        );
      }
    }
  }

  void goUnsnapped(double velocity) async {
    // The iOS bouncing simulation just isn't right here - once we delegate
    // the ballistic back to the ScrollView, it will use the right simulation.
    final simulation = ClampingScrollSimulation(
      position: extent.currentExtent,
      velocity: velocity,
      tolerance: physics.tolerance,
    );

    final ballisticController = AnimationController.unbounded(
      debugLabel: '$runtimeType',
      vsync: context.vsync,
    );

    double lastDelta = 0;
    void _tick() {
      final double delta = ballisticController.value - lastDelta;
      lastDelta = ballisticController.value;
      extent.addPixelDelta(delta);
      if ((velocity > 0 && extent.isAtMax) ||
          (velocity < 0 && (!fromBottomSheet ? extent.isAtMin : currentExtent <= 0.0))) {
        // Make sure we pass along enough velocity to keep scrolling - otherwise
        // we just "bounce" off the top making it look like the list doesn't
        // have more to scroll.
        velocity = ballisticController.velocity + (physics.tolerance.velocity * ballisticController.velocity.sign);
        super.goBallistic(velocity);
        ballisticController.stop();

        // Pop the route when reaching 0.0 extent.
        if (fromBottomSheet && currentExtent <= 0.0) {
          onPop(0.0);
        }
      }
    }

    ballisticController.addListener(_tick);
    await ballisticController.animateWith(simulation);
    ballisticController.dispose();

    if (fromBottomSheet && currentExtent < minExtent && currentExtent > 0.0) {
      goSnapped(0.0);
    }
  }

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    // Save this so we can call it later if we have to [goBallistic] on our own.
    _dragCancelCallback = dragCancelCallback;
    return super.drag(details, dragCancelCallback);
  }
}

/// A data class containing state information about the [_SlidingSheetState].
class SheetState {
  /// The current extent the sheet covers.
  final double extent;

  /// The minimum extent that the sheet will cover.
  final double minExtent;

  /// The maximum extent that the sheet will cover
  /// until it begins scrolling.
  final double maxExtent;

  /// Whether the sheet has finished measuring its children and computed
  /// the correct extents. This takes until the first frame was drawn.
  final bool isLaidOut;

  /// The progress between [minExtent] and [maxExtent] of the current [extent].
  /// A progress of 1 means the sheet is fully expanded, while
  /// a progress of 0 means the sheet is fully collapsed.
  final double progress;

  /// The scroll offset when the content is bigger than the available space.
  final double scrollOffset;

  /// Whether the [SlidingSheet] has reached its maximum extent.
  final bool isExpanded;

  /// Whether the [SlidingSheet] has reached its minimum extent.
  final bool isCollapsed;

  /// Whether the [SlidingSheet] has a [scrollOffset] of zero.
  final bool isAtTop;

  /// Whether the [SlidingSheet] has reached its maximum scroll extent.
  final bool isAtBottom;

  /// Whether the sheet is hidden to the user.
  final bool isHidden;

  /// Whether the sheet is visible to the user.
  final bool isShown;
  SheetState(
    _SheetExtent _extent, {
    @required this.extent,
    @required this.isLaidOut,
    @required this.maxExtent,
    @required double minExtent,
    // On Bottomsheets it is possible for min and maxExtents to be the same (when you only set one snap).
    // Thus we have to account for this and set the minExtent to be zero.
  })  : minExtent = minExtent != maxExtent ? minExtent : 0.0,
        progress = isLaidOut ? ((extent - minExtent) / (maxExtent - minExtent)).clamp(0.0, 1.0) : 0.0,
        scrollOffset = _extent?.scrollOffset ?? 0,
        isExpanded = extent >= maxExtent,
        isCollapsed = extent <= minExtent,
        isAtTop = _extent?.isAtTop ?? true,
        isAtBottom = _extent?.isAtBottom ?? false,
        isHidden = extent <= 0.0,
        isShown = extent > 0.0;

  factory SheetState.inital() => SheetState(null, extent: 0.0, minExtent: 0.0, maxExtent: 1.0, isLaidOut: false);
}

/// A controller for a [SlidingSheet].
class SheetController {
  /// Animates the sheet to the [extent].
  ///
  /// The [extent] will be clamped to the minimum and maximum extent.
  /// If the scrolling child is not at the top, it will scroll to the top
  /// first and then animate to the specified extent.
  Future snapToExtent(double extent, {Duration duration}) => _snapToExtent?.call(extent, duration: duration);
  Future Function(double extent, {Duration duration}) _snapToExtent;

  /// Animates the scrolling child to a specified offset.
  ///
  /// If the sheet is not fully expanded it will expand first and then
  /// animate to the given [offset].
  Future scrollTo(double offset, {Duration duration, Curve curve}) =>
      _scrollTo?.call(offset, duration: duration, curve: curve);
  Future Function(double offset, {Duration duration, Curve curve}) _scrollTo;

  /// Calls every builder function of the sheet to rebuild the widgets with
  /// the current [SheetState].
  ///
  /// This function can be used to reflect changes on the [SlidingSheet]
  /// without calling `setState(() {})` on the parent widget if that would be
  /// too expensive.
  void rebuild() => _rebuild?.call();
  VoidCallback _rebuild;

  /// Fully collapses the sheet.
  ///
  /// Short-hand for calling `snapToExtent(minExtent)`.
  Future collapse() => _collapse?.call();
  Future Function() _collapse;

  /// Fully expands the sheet.
  ///
  /// Short-hand for calling `snapToExtent(maxExtent)`.
  Future expand() => _expand?.call();
  Future Function() _expand;

  /// Reveals the [SlidingSheet] if it is currently hidden.
  Future show() => _show?.call();
  Future Function() _show;

  /// Slides the sheet off to the bottom and hides it.
  Future hide() => _hide?.call();
  Future Function() _hide;

  SheetState _state;
  SheetState get state => _state;
}

/// Shows a [SlidingSheet] as a material design bottom sheet.
///
/// The `builder` parameter must not be null and is used to construct a [SlidingSheetDialog].
///
/// The `parentBuilder` parameter can be used to wrap the sheet inside a parent, for example a
/// [Theme] or [AnnotatedRegion].
///
/// The `resizeToAvoidBottomInset` parameter can be used to avoid the keyboard from obscuring
/// the content bottom sheet.
Future<T> showSlidingBottomSheet<T>(
  BuildContext context, {
  @required SlidingSheetDialog Function(BuildContext context) builder,
  Widget Function(BuildContext context, SlidingSheet sheet) parentBuilder,
  bool useRootNavigator = false,
  bool resizeToAvoidBottomInset = true,
}) {
  assert(builder != null);
  assert(useRootNavigator != null);
  assert(resizeToAvoidBottomInset != null);

  SlidingSheetDialog dialog = builder(context);

  final theme = Theme.of(context);
  final ValueNotifier<int> rebuilder = ValueNotifier(0);

  return Navigator.of(
    context,
    rootNavigator: useRootNavigator,
  ).push(
    _SlidingSheetRoute(
      duration: dialog.duration,
      builder: (context, animation, route) {
        return ValueListenableBuilder(
          valueListenable: rebuilder,
          builder: (context, value, _) {
            dialog = builder(context);
            if (dialog.controller != null) {
              dialog.controller._rebuild = () {
                rebuilder.value++;
              };
            }

            var snapSpec = dialog.snapSpec;
            if (snapSpec.snappings.first != 0.0) {
              snapSpec = snapSpec.copyWith(
                snappings: [0.0] + snapSpec.snappings,
              );
            }

            final sheet = SlidingSheet(
              route: route,
              snapSpec: snapSpec,
              duration: dialog.duration,
              color: dialog.color ??
                  theme.bottomSheetTheme.backgroundColor ??
                  theme.dialogTheme.backgroundColor ??
                  theme.dialogBackgroundColor ??
                  theme.backgroundColor,
              backdropColor: dialog.backdropColor,
              shadowColor: dialog.shadowColor,
              elevation: dialog.elevation,
              padding: dialog.padding,
              addTopViewPaddingOnFullscreen: dialog.addTopViewPaddingOnFullscreen,
              margin: dialog.margin,
              border: dialog.border,
              cornerRadius: dialog.cornerRadius,
              cornerRadiusOnFullscreen: dialog.cornerRadiusOnFullscreen,
              closeOnBackdropTap: dialog.dismissOnBackdropTap,
              builder: dialog.builder,
              headerBuilder: dialog.headerBuilder,
              footerBuilder: dialog.footerBuilder,
              listener: dialog.listener,
              controller: dialog.controller,
              scrollSpec: dialog.scrollSpec,
              maxWidth: dialog.maxWidth,
              closeSheetOnBackButtonPressed: false,
            );

            if (resizeToAvoidBottomInset) {
              return Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: sheet,
              );
            }

            if (parentBuilder != null) {
              return parentBuilder(context, sheet);
            }

            return sheet;
          },
        );
      },
    ),
  );
}

/// A wrapper class for a [SlidingSheet] to be shown as a model bottom sheet.
class SlidingSheetDialog {
  /// {@macro sliding_sheet.builder}
  final SheetBuilder builder;

  /// {@macro sliding_sheet.headerBuilder}
  final SheetBuilder headerBuilder;

  /// {@macro sliding_sheet.footerBuilder}
  final SheetBuilder footerBuilder;

  /// {@macro sliding_sheet.snapSpec}
  final SnapSpec snapSpec;

  /// {@macro sliding_sheet.duration}
  final Duration duration;

  /// {@macro sliding_sheet.color}
  final Color color;

  /// {@macro sliding_sheet.backdropColor}
  final Color backdropColor;

  /// {@macro sliding_sheet.shadowColor}
  final Color shadowColor;

  /// {@macro sliding_sheet.elevation}
  final double elevation;

  /// {@macro sliding_sheet.padding}
  final EdgeInsets padding;

  /// {@macro sliding_sheet.addTopViewPaddingWhenAtFullscreen}
  final bool addTopViewPaddingOnFullscreen;

  /// {@macro sliding_sheet.margin}
  final EdgeInsets margin;

  /// {@macro sliding_sheet.border}
  final Border border;

  /// {@macro sliding_sheet.cornerRadius}
  final double cornerRadius;

  /// {@macro sliding_sheet.cornerRadiusOnFullscreen}
  final double cornerRadiusOnFullscreen;

  /// If true, the sheet will be dismissed the backdrop
  /// was tapped.
  final bool dismissOnBackdropTap;

  /// {@macro sliding_sheet.listener}
  final SheetListener listener;

  /// {@macro sliding_sheet.controller}
  final SheetController controller;

  /// {@macro sliding_sheet.scrollSpec}
  final ScrollSpec scrollSpec;

  /// {@macro sliding_sheet.maxWidth}
  final double maxWidth;

  /// {@macro sliding_sheet.minHeight}
  final double minHeight;
  const SlidingSheetDialog({
    @required this.builder,
    this.headerBuilder,
    this.footerBuilder,
    this.snapSpec = const SnapSpec(),
    this.duration = const Duration(milliseconds: 800),
    this.color,
    this.backdropColor = Colors.black54,
    this.shadowColor,
    this.elevation = 0.0,
    this.padding,
    this.addTopViewPaddingOnFullscreen = false,
    this.margin,
    this.border,
    this.cornerRadius = 0.0,
    this.cornerRadiusOnFullscreen,
    this.dismissOnBackdropTap = true,
    this.listener,
    this.controller,
    this.scrollSpec = const ScrollSpec(overscroll: false),
    this.maxWidth = double.infinity,
    this.minHeight,
  });
}

/// A custom [Container] for a [SlidingSheet].
class _SheetContainer extends StatelessWidget {
  final double borderRadius;
  final double elevation;
  final Border border;
  final BorderRadius customBorders;
  final EdgeInsets margin;
  final EdgeInsets padding;
  final Widget child;
  final Color color;
  final Color shadowColor;
  final List<BoxShadow> boxShadows;
  final AlignmentGeometry alignment;
  _SheetContainer({
    Key key,
    this.child,
    this.border,
    this.color = Colors.transparent,
    this.borderRadius = 0.0,
    this.elevation = 0.0,
    this.shadowColor = Colors.black12,
    this.margin,
    this.customBorders,
    this.alignment,
    this.boxShadows,
    this.padding = const EdgeInsets.all(0),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final br = customBorders ?? BorderRadius.circular(borderRadius);

    final List<BoxShadow> boxShadow = boxShadows ?? elevation != 0
        ? [
            BoxShadow(
              color: shadowColor ?? Colors.black12,
              blurRadius: elevation,
              spreadRadius: 0,
            ),
          ]
        : const [];

    return Container(
      margin: margin,
      padding: padding,
      alignment: alignment,
      decoration: BoxDecoration(
        color: color,
        borderRadius: br,
        boxShadow: boxShadow,
        border: border,
        shape: BoxShape.rectangle,
      ),
      child: ClipRRect(
        borderRadius: br,
        child: child,
      ),
    );
  }
}

/// A transparent route for a bottom sheet dialog.
class _SlidingSheetRoute<T> extends PageRoute<T> {
  final Widget Function(BuildContext, Animation<double>, _SlidingSheetRoute<T>) builder;
  final Duration duration;
  _SlidingSheetRoute({
    @required this.builder,
    @required this.duration,
    RouteSettings settings,
  })  : assert(builder != null),
        super(
          settings: settings,
          fullscreenDialog: false,
        );

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => false;

  @override
  Color get barrierColor => null;

  @override
  String get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => duration;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      builder(context, animation, this);
}
