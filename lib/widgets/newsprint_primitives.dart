import 'package:flutter/material.dart';

import '../core/theme.dart';

// Hallmark - genre: editorial - macrostructure: Brutal Newsprint Workbench - design-system: design.md - designed-as-app

class NewsprintPage extends StatelessWidget {
  const NewsprintPage({
    super.key,
    required this.kicker,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 16),
  });

  final String kicker;
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: AppTheme.panelDecoration(
                color: AppTheme.paper,
                accentTop: true,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              kicker.toUpperCase(),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(letterSpacing: 1.4),
                            ),
                            const SizedBox(height: 6),
                            Text(title, style: Theme.of(context).textTheme.headlineLarge),
                            if (subtitle != null) ...[
                              const SizedBox(height: 8),
                              Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
                            ],
                          ],
                        ),
                      ),
                      if (actions != null && actions!.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Wrap(spacing: 8, runSpacing: 8, children: actions!),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class NewsprintPanel extends StatelessWidget {
  const NewsprintPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.accentTop = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final bool accentTop;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: AppTheme.panelDecoration(
        color: color ?? AppTheme.paper,
        accentTop: accentTop,
      ),
      child: child,
    );
  }
}

class NewsprintSectionTitle extends StatelessWidget {
  const NewsprintSectionTitle({
    super.key,
    required this.label,
    this.detail,
  });

  final String label;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleLarge),
        if (detail != null) ...[
          const SizedBox(height: 4),
          Text(detail!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}

class NewsprintTag extends StatelessWidget {
  const NewsprintTag({
    super.key,
    required this.label,
    this.backgroundColor,
    this.textColor,
  });

  final String label;
  final Color? backgroundColor;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppTheme.ink,
        border: Border.all(color: AppTheme.ink, width: 2),
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: textColor ?? AppTheme.paper,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class NewsprintMetricStrip extends StatelessWidget {
  const NewsprintMetricStrip({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 112),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: AppTheme.panelDecoration(
        color: AppTheme.paperAlt,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.1,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: valueColor ?? AppTheme.ink,
                  fontFamilyFallback: AppTheme.monoFallback,
                ),
          ),
        ],
      ),
    );
  }
}

class NewsprintNotice extends StatelessWidget {
  const NewsprintNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.color,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? AppTheme.ink;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.panelDecoration(color: AppTheme.paperAlt),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: resolvedColor,
              border: Border.all(color: AppTheme.ink, width: 2),
            ),
            child: Icon(icon, size: 18, color: AppTheme.paper),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(message, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
