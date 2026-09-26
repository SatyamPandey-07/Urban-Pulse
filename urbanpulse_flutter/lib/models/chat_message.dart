import 'trip_models.dart';

/// Port of `ChatMessage.kt`.
class ChatMessage {
  ChatMessage(
    this.message, {
    required this.isUser,
    int? timestamp,
    this.isLoading = false,
    this.mcqQuestion,
    this.generatedTrip,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  final String message;
  final bool isUser;
  final int timestamp;
  final bool isLoading;
  final QuickMcqQuestion? mcqQuestion;
  final TripPlan? generatedTrip;
}
