import 'package:flutter/material.dart';

import '../models/topic.dart';
import '../models/unit.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/topic/topic_detail_screen.dart';
import '../screens/tutor/tutor_screen.dart';
import '../screens/unit/unit_detail_screen.dart';

class Routes {
  Routes._();

  static const String splash = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String home = '/home';
  static const String unit = '/unit';
  static const String topic = '/topic';
  static const String tutor = '/tutor';
}

class TopicRouteArgs {
  const TopicRouteArgs({required this.topic, required this.unit});

  final Topic topic;
  final Unit unit;
}

class TutorRouteArgs {
  const TutorRouteArgs({
    required this.topic,
    required this.unit,
    this.initialQuestion,
  });

  final Topic topic;
  final Unit unit;
  final String? initialQuestion;
}

Route<dynamic> onGenerateRoute(RouteSettings settings) {
  final Object? args = settings.arguments;
  final Widget page = switch (settings.name) {
    Routes.splash => const SplashScreen(),
    Routes.login => const LoginScreen(),
    Routes.register => const RegisterScreen(),
    Routes.home => const HomeScreen(),
    Routes.unit when args is Unit => UnitDetailScreen(unit: args),
    Routes.topic when args is TopicRouteArgs => TopicDetailScreen(
      topic: args.topic,
      unit: args.unit,
    ),
    Routes.tutor when args is TutorRouteArgs => TutorScreen(
      topic: args.topic,
      unit: args.unit,
      initialQuestion: args.initialQuestion,
    ),
    _ => const SplashScreen(),
  };
  return MaterialPageRoute<void>(builder: (_) => page, settings: settings);
}
