import 'package:flutter/material.dart';

import '../../core/app_colors.dart';

/// Text field with a mic / send button that flips depending on the input,
/// like the original composer. Disabled while the agent is busy or when chat
/// isn't available.
class YatriComposer extends StatelessWidget {
  const YatriComposer({
    required this.controller,
    required this.enabled,
    required this.hint,
    required this.isListening,
    required this.onSend,
    required this.onMic,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final bool isListening;
  final ValueChanged<String> onSend;
  final VoidCallback onMic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final bgFill = isDark ? AppColors.surfaceCard : const Color(0xFFF1F5F9);
    final borderColor = isDark ? AppColors.surfaceBorder : const Color(0xFFE2E8F0);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgDark : Colors.white,
        border: Border(top: BorderSide(color: isDark ? AppColors.surfaceBorder : const Color(0xFFE2E8F0), width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: enabled ? onSend : null,
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                hintText: enabled ? hint : 'Chat is unavailable right now',
                hintStyle: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppColors.textSecondary : const Color(0xFF94A3B8),
                ),
                filled: true,
                fillColor: bgFill,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: borderColor, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: borderColor, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: scheme.primary, width: 1.5),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: borderColor, width: 1),
                ),
                suffixIcon: IconButton(
                  icon: Icon(Icons.attach_file_rounded, size: 20, color: scheme.onSurfaceVariant),
                  tooltip: 'Attach document or itinerary',
                  onPressed: () {},
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final hasText = controller.text.trim().isNotEmpty;
              return IconButton.filled(
                tooltip: hasText ? 'Send' : (isListening ? 'Stop listening' : 'Speak'),
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  backgroundColor: isListening ? scheme.error : scheme.primary,
                  foregroundColor: isListening ? scheme.onError : scheme.onPrimary,
                ),
                onPressed: !enabled
                    ? null
                    : hasText
                    ? () => onSend(controller.text)
                    : onMic,
                icon: Icon(
                  hasText
                      ? Icons.send_rounded
                      : (isListening ? Icons.stop_rounded : Icons.mic_rounded),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
