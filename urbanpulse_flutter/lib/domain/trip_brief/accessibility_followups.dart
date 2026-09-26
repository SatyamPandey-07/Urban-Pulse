import '../../models/trip_brief.dart';
import '../../models/yatri_question.dart';

/// One follow-up question asked for a selected accessibility need.
class A11yFollowUp {
  const A11yFollowUp({
    required this.id,
    required this.need,
    required this.text,
    required this.multi,
    required this.options,
  });

  final String id;
  final AccessibilityNeed need;
  final String text;
  final bool multi;
  final List<QuestionOption> options;
}

/// Each selected need gets its own tailored questions, in this order.
abstract final class AccessibilityFollowUps {
  static const all = <A11yFollowUp>[
    A11yFollowUp(
      id: 'a11y.wheelchair.type',
      need: AccessibilityNeed.wheelchair,
      text: 'What kind of wheelchair support is needed?',
      multi: false,
      options: [
        QuestionOption(id: 'manual', label: 'Manual wheelchair', emoji: '♿'),
        QuestionOption(id: 'electric', label: 'Electric wheelchair', emoji: '🔌'),
        QuestionOption(
          id: 'transfer',
          label: 'Can transfer & walk a few steps',
          emoji: '🪑',
        ),
      ],
    ),
    A11yFollowUp(
      id: 'a11y.wheelchair.facilities',
      need: AccessibilityNeed.wheelchair,
      text: 'Which facilities are essential for you?',
      multi: true,
      options: [
        QuestionOption(id: 'step_free', label: 'Step-free entry', emoji: '🚪'),
        QuestionOption(id: 'lift', label: 'Lift / elevator', emoji: '🛗'),
        QuestionOption(id: 'toilet', label: 'Accessible toilet', emoji: '🚻'),
        QuestionOption(id: 'roll_in', label: 'Roll-in shower', emoji: '🚿'),
        QuestionOption(id: 'ramps', label: 'Ramps at stations', emoji: '📐'),
      ],
    ),
    A11yFollowUp(
      id: 'a11y.mobility.walking',
      need: AccessibilityNeed.limitedMobility,
      text: 'How far can you comfortably walk at a time?',
      multi: false,
      options: [
        QuestionOption(id: 'lt100', label: 'Under 100 m', emoji: '🐢'),
        QuestionOption(id: '100_500', label: '100 – 500 m', emoji: '🚶'),
        QuestionOption(id: '500_1000', label: '500 m – 1 km', emoji: '🚶‍♂️'),
        QuestionOption(id: 'gt1000', label: 'More than 1 km', emoji: '🥾'),
      ],
    ),
    A11yFollowUp(
      id: 'a11y.mobility.support',
      need: AccessibilityNeed.limitedMobility,
      text: 'What would make getting around easier?',
      multi: true,
      options: [
        QuestionOption(id: 'rest_stops', label: 'Frequent rest stops', emoji: '🪑'),
        QuestionOption(id: 'seating', label: 'Seating at venues', emoji: '💺'),
        QuestionOption(id: 'avoid_stairs', label: 'Avoid stairs', emoji: '🪜'),
        QuestionOption(id: 'walking_aid', label: 'I use a walking aid', emoji: '🦯'),
        QuestionOption(
          id: 'nothing',
          label: 'Nothing extra',
          emoji: '✅',
          exclusive: true,
        ),
      ],
    ),
    A11yFollowUp(
      id: 'a11y.visual.support',
      need: AccessibilityNeed.visual,
      text: 'What kind of visual assistance helps you most?',
      multi: true,
      options: [
        QuestionOption(id: 'audio', label: 'Audio guidance', emoji: '🔊'),
        QuestionOption(id: 'screen_reader', label: 'Screen-reader friendly info', emoji: '📱'),
        QuestionOption(id: 'guide', label: 'Sighted guide', emoji: '🤝'),
        QuestionOption(id: 'high_contrast', label: 'Large print / high contrast', emoji: '🔍'),
        QuestionOption(id: 'tactile', label: 'Tactile paths', emoji: '🧭'),
      ],
    ),
    A11yFollowUp(
      id: 'a11y.hearing.support',
      need: AccessibilityNeed.hearing,
      text: 'What kind of hearing assistance helps you most?',
      multi: true,
      options: [
        QuestionOption(id: 'visual_alerts', label: 'Text / visual alerts', emoji: '💬'),
        QuestionOption(id: 'sign_language', label: 'Sign-language guide', emoji: '🤟'),
        QuestionOption(id: 'hearing_loop', label: 'Hearing loop', emoji: '🦻'),
        QuestionOption(id: 'captions', label: 'Captioned tours', emoji: '📝'),
      ],
    ),
    A11yFollowUp(
      id: 'a11y.elderly.support',
      need: AccessibilityNeed.elderlyCare,
      text: 'What should we plan around for the elderly travellers?',
      multi: true,
      options: [
        QuestionOption(id: 'ground_floor', label: 'Ground floor / lift room', emoji: '🛗'),
        QuestionOption(id: 'medical', label: 'Medical facility nearby', emoji: '🏥'),
        QuestionOption(id: 'slow_pace', label: 'Slower pace', emoji: '🐢'),
        QuestionOption(id: 'porter', label: 'Station porter / assistance', emoji: '🧳'),
      ],
    ),
    A11yFollowUp(
      id: 'a11y.serviceAnimal.type',
      need: AccessibilityNeed.serviceAnimal,
      text: 'What kind of service animal is travelling with you?',
      multi: false,
      options: [
        QuestionOption(id: 'guide_dog', label: 'Guide dog', emoji: '🦮'),
        QuestionOption(id: 'hearing_dog', label: 'Hearing dog', emoji: '🐕'),
        QuestionOption(id: 'mobility_dog', label: 'Mobility assistance dog', emoji: '🐕‍🦺'),
        QuestionOption(id: 'other', label: 'Other', emoji: '🐾'),
      ],
    ),
    A11yFollowUp(
      id: 'a11y.cognitive.support',
      need: AccessibilityNeed.cognitiveSensory,
      text: 'What helps most with sensory or cognitive needs on a trip?',
      multi: true,
      options: [
        QuestionOption(id: 'quiet_low_crowd', label: 'Quiet, low-crowd places and times', emoji: '🤫'),
        QuestionOption(id: 'clear_schedule', label: 'A clear, predictable schedule', emoji: '🗓️'),
        QuestionOption(id: 'sensory_friendly', label: 'Sensory-friendly venues (light, sound)', emoji: '🎧'),
        QuestionOption(id: 'companion', label: 'A companion or caregiver travels with us', emoji: '🤝'),
        QuestionOption(id: 'buffer_time', label: 'Extra time between activities', emoji: '⏳'),
      ],
    ),
    A11yFollowUp(
      id: 'a11y.otherSpecial.support',
      need: AccessibilityNeed.otherSpecial,
      text: 'What should I plan around? (Describe anything else in the message box.)',
      multi: true,
      options: [
        QuestionOption(id: 'extra_time', label: 'Extra time for everything', emoji: '⏳'),
        QuestionOption(id: 'medical_nearby', label: 'Hospital or pharmacy close by', emoji: '🏥'),
        QuestionOption(id: 'rest_breaks', label: 'Frequent rest breaks', emoji: '🪑'),
        QuestionOption(id: 'medicine_storage', label: 'Medicine that needs a fridge', emoji: '💊'),
        QuestionOption(id: 'quiet_room', label: 'A quiet room to rest', emoji: '🛏️'),
      ],
    ),
  ];

  static A11yFollowUp? byId(String id) {
    for (final f in all) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// The follow-ups that apply to [needs], in asking order.
  static List<A11yFollowUp> forNeeds(Set<AccessibilityNeed> needs) => [
    for (final f in all)
      if (needs.contains(f.need)) f,
  ];
}
