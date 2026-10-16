import 'package:fl_lib/fl_lib.dart';
import 'package:material_ui/material_ui.dart';

/// A button's menu: fl_lib's context menu, dropped from the button, so it is
/// the same object as the menu a right click opens (`showContextMenu`) — the
/// same [ContextMenuAction]s, drawn by the same rows.
class MenuBtn extends StatelessWidget {
  const MenuBtn({super.key, required this.actions, required this.builder});

  final List<ContextMenuAction> actions;

  /// The button; call the argument to open the menu.
  final Widget Function(VoidCallback open) builder;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (ctx) => builder(() {
        final box = ctx.findRenderObject();
        showContextMenu(
          ctx,
          actions,
          at: box is RenderBox && box.hasSize ? box.localToGlobal(box.size.bottomLeft(Offset.zero)) : null,
        );
      }),
    );
  }
}
