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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
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
              decoration: InputDecoration(
                hintText: enabled ? hint : 'Chat is unavailable right now',
                hintStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surfaceCard,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: AppColors.surfaceBorder, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: AppColors.surfaceBorder, width: 1),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: AppColors.surfaceBorder, width: 1),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.attach_file_rounded, size: 20, color: AppColors.textSecondary),
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
                  backgroundColor: isListening ? scheme.error : null,
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
