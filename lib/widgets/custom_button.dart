import 'package:flutter/material.dart';
import '../core/constants.dart';

/// A reusable elevated button using the app's primary color.
///
/// Usage:
/// ```dart
/// CustomButton(
///   text: 'Continue',
///   onPressed: () { /* action */ },
/// )
///
/// // Fixed width variant
/// CustomButton(
///   text: 'Submit',
///   onPressed: () {},
///   width: 200,
/// )
///
/// // Loading state
/// CustomButton(
///   text: 'Submit',
///   onPressed: () {},
///   isLoading: true,
/// )
/// ```
class CustomButton extends StatelessWidget {
  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.width,
    this.height = 52,
    this.isLoading = false,
    this.icon,
    this.backgroundColor,
    this.foregroundColor,
    this.borderRadius = 14,
  });

  final String text;
  final VoidCallback? onPressed;

  /// Optional fixed width. Defaults to [double.infinity] (full width).
  final double? width;

  /// Button height. Defaults to 52.
  final double height;

  /// Shows a spinner and disables the button while true.
  final bool isLoading;

  /// Optional leading icon.
  final IconData? icon;

  /// Override background color (defaults to [AppColors.primary]).
  final Color? backgroundColor;

  /// Override foreground/text color (defaults to white).
  final Color? foregroundColor;

  /// Corner radius. Defaults to 14.
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? AppColors.primary;
    final fg = foregroundColor ?? AppColors.white;
    final bool disabled = onPressed == null || isLoading;

    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: disabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: disabled ? AppColors.textHint : bg,
          foregroundColor: fg,
          disabledBackgroundColor: AppColors.divider,
          disabledForegroundColor: AppColors.textHint,
          elevation: disabled ? 0 : 2,
          shadowColor: bg.withOpacity(0.40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
        child: isLoading
            ? SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(fg),
          ),
        )
            : Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 8),
            ],
            Text(
              text,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}