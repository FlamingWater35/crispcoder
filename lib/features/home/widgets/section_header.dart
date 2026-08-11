import 'package:flutter/material.dart';

/// Section header with count badge and an animated expand/collapse chevron.
///
/// Tapping the header toggles the section; the rotation is driven by an
/// internal [AnimationController] so both the chevron and the section content
/// animate in sync without external state plumbing.
class SectionHeader extends StatefulWidget {
  const SectionHeader({
    super.key,
    required this.title,
    required this.count,
    required this.onToggle,
    required this.isExpanded,
    this.icon,
  });

  final String title;
  final int count;
  final IconData? icon;
  final VoidCallback onToggle;
  final bool isExpanded;

  @override
  State<SectionHeader> createState() => _SectionHeaderState();
}

class _SectionHeaderState extends State<SectionHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _chevron;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: widget.isExpanded ? 1 : 0,
    );
    _chevron = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void didUpdateWidget(SectionHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isExpanded != widget.isExpanded) {
      if (widget.isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: widget.onToggle,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
        child: Row(
          children: [
            if (widget.icon != null) ...[
              Icon(
                widget.icon,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                widget.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            // Count badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${widget.count}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 4),
            RotationTransition(
              turns: Tween(begin: 0.0, end: 0.5).animate(_chevron),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
