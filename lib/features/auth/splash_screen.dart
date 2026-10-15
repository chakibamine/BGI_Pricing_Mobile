import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';

const brandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [AppColors.navyDeep, AppColors.navy, AppColors.blue],
);

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.navyDeep,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(gradient: brandGradient),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandMark(),
                SizedBox(height: 32),
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.amberBright),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.dark = true, this.compact = false});

  /// True on a navy background.
  final bool dark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : context.palette.textPrimary;
    final size = compact ? 52.0 : 72.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.amberBright, AppColors.amber],
            ),
            borderRadius: BorderRadius.circular(size * 0.28),
            boxShadow: [
              BoxShadow(
                color: AppColors.amberBright.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            'BGI',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              fontSize: compact ? 16 : 22,
            ),
          ),
        ),
        SizedBox(height: compact ? 10 : 16),
        Text(
          'BGI Pricing',
          style: TextStyle(
            color: fg,
            fontSize: compact ? 20 : 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Prix d’achat carburants',
          style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 13.5),
        ),
      ],
    );
  }
}
