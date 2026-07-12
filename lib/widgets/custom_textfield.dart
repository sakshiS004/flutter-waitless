import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants.dart';

class CustomTextField extends StatefulWidget {
  const CustomTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.isPassword = false,
    this.keyboardType,
    this.textInputAction,
    this.prefixIcon,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.enabled = true,
    this.maxLines = 1,
    this.inputFormatters,
    this.focusNode,
    this.autofillHints,
    this.obscureText, // Now valid
    this.suffixIcon,  // Now valid
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool isPassword;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final IconData? prefixIcon;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final bool enabled;
  final int maxLines;
  final List<TextInputFormatter>? inputFormatters;
  final FocusNode? focusNode;
  final Iterable<String>? autofillHints;

  // ADD THESE TWO LINES TO FIX THE ERRORS:
  final bool? obscureText;
  final Widget? suffixIcon;

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField> {
  // Use a local state variable that respects the passed in obscureText or isPassword
  late bool _internalObscure;

  @override
  void initState() {
    super.initState();
    // Initialize based on whether it's a password field or explicitly obscured
    _internalObscure = widget.obscureText ?? widget.isPassword;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      // If widget.obscureText is passed, use it. Otherwise use internal toggle.
      obscureText: _internalObscure,
      keyboardType: widget.isPassword
          ? TextInputType.visiblePassword
          : widget.keyboardType,
      textInputAction: widget.textInputAction,
      maxLines: widget.isPassword ? 1 : widget.maxLines,
      enabled: widget.enabled,
      inputFormatters: widget.inputFormatters,
      autofillHints: widget.autofillHints,
      style: const TextStyle(
        fontFamily: 'Nunito',
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        prefixIcon: widget.prefixIcon != null
            ? Icon(widget.prefixIcon, size: 20, color: AppColors.textSecondary)
            : null,
        // Priority 1: Custom Suffix Icon (for Re-auth popups)
        // Priority 2: Password Toggle Icon
        suffixIcon: widget.suffixIcon ?? (widget.isPassword
            ? IconButton(
          icon: Icon(
            _internalObscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 20,
            color: AppColors.textSecondary,
          ),
          onPressed: () => setState(() => _internalObscure = !_internalObscure),
          splashRadius: 20,
        )
            : null),
      ),
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onFieldSubmitted,
    );
  }
}