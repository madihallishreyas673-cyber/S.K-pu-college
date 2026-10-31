import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config.dart';
import '../theme.dart';

String friendly(Object e) => e.toString().replaceFirst('Exception: ', '');

void toast(BuildContext c, String m, {bool error = false}) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? AppColors.coral : AppColors.surfaceHi));
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator(color: AppColors.brass));
}

class ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const ErrorView(this.error, this.onRetry, {super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, size: 44, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(friendly(error), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 15)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ]),
        ),
      );
}

class EmptyView extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyView(this.icon, this.text, {super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 44, color: AppColors.muted),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 15)),
          ]),
        ),
      );
}

/// Logo in the upper-left with the school name beside it.
class BrandBar extends StatelessWidget {
  const BrandBar({super.key});
  @override
  Widget build(BuildContext context) => Row(children: [
        Image.asset('assets/logo.png', width: 52, height: 52),
        const SizedBox(width: 12),
        Expanded(child: Text(AppConfig.schoolName, style: display(18), maxLines: 2, overflow: TextOverflow.ellipsis)),
      ]);
}

class PinField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  const PinField(this.controller, {super.key, this.label = '6-digit PIN'});
  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, counterText: '', prefixIcon: const Icon(Icons.lock_outline)),
      );
}

Color attColor(double pct, double threshold, {bool none = false}) {
  if (none) return AppColors.muted;
  if (pct < threshold) return AppColors.coral;
  if (pct < threshold + 5) return AppColors.amber;
  return AppColors.mint;
}

class PercentRing extends StatelessWidget {
  final double pct, size;
  final Color color;
  final String? label;
  const PercentRing({super.key, required this.pct, required this.color, this.size = 150, this.label});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: (pct / 100).clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => SizedBox(
          width: size, height: size,
          child: CustomPaint(
            painter: _RingPainter(v, color),
            child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${pct.toStringAsFixed(pct == pct.roundToDouble() ? 0 : 1)}%', style: display(size * 0.2)),
              if (label != null) Text(label!, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ])),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color color;
  _RingPainter(this.v, this.color);
  @override
  void paint(Canvas canvas, Size s) {
    final stroke = s.width * 0.09;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, s.width - stroke, s.height - stroke);
    final bg = Paint()..style = PaintingStyle.stroke..strokeWidth = stroke..color = AppColors.surfaceHi;
    final fg = Paint()..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.round..color = color;
    canvas.drawArc(rect, 0, math.pi * 2, false, bg);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * v, false, fg);
  }
  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color;
}

class StatChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const StatChip(this.label, this.value, {super.key, this.color = AppColors.text});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
          child: Column(children: [
            Text(value, style: display(22, c: color)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        ),
      );
}

class ComingSoonTile extends StatelessWidget {
  final IconData icon;
  final String title;
  const ComingSoonTile(this.icon, this.title, {super.key});
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: 0.55,
        child: Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => toast(context, '$title arrives in Stage 2.'),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Icon(icon, color: AppColors.muted),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const Text('Stage 2', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                ]),
              ]),
            ),
          ),
        ),
      );
}
