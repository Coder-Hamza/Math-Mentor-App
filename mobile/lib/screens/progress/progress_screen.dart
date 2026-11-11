import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/progress.dart';
import '../../services/api_exception.dart';
import '../../services/progress_service.dart';
import '../../widgets/error_view.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/progress_widgets.dart';

/// Points, accuracy, streak, per-unit progress bars and weak topics.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  ProgressSummary? _summary;
  List<WeakTopic> _weakTopics = const <WeakTopic>[];
  ApiException? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final ProgressService service = context.read<ProgressService>();
    try {
      // Future.wait handles both futures' errors and rethrows the first one.
      final List<Object> results = await Future.wait<Object>(<Future<Object>>[
        service.getProgress(),
        service.getWeakTopics(),
      ]);
      if (mounted) {
        setState(() {
          _summary = results[0] as ProgressSummary;
          _weakTopics = results[1] as List<WeakTopic>;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _practiseUnit(WeakTopic topic) {
    Navigator.of(context).pushNamed(
      Routes.practice,
      arguments: PracticeRouteArgs(
        unitId: topic.unitId,
        title: 'Practice: Unit ${topic.unitNumber}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meri Progress')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final ProgressSummary? summary = _summary;
    if (summary == null && _error != null) {
      return ErrorView(error: _error!, onRetry: _load);
    }
    if (summary == null) {
      return const LoadingWidget(message: 'Progress load ho rahi hai...');
    }
    final TextTheme text = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const ValueKey<String>('progress-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: <Widget>[
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ErrorView(error: _error!, compact: true, onRetry: _load),
            ),
          if (_loading) const LinearProgressIndicator(),
          StatsCard(summary: summary),
          _SectionTitle('Unit progress', style: text),
          for (final UnitProgress unit in summary.units)
            UnitProgressRow(
              key: ValueKey<String>('unit-progress-${unit.unitId}'),
              progress: unit,
            ),
          _SectionTitle('Weak topics', style: text),
          if (_weakTopics.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                summary.totalAttempted == 0
                    ? 'Practice shuru karein, phir yahan aap ke kamzor topics nazar aayenge.'
                    : 'Koi weak topic nahi. Shabash! 🌟',
                key: const ValueKey<String>('no-weak-topics'),
                style: text.bodyMedium?.copyWith(color: AppColors.unverified),
              ),
            )
          else
            for (final WeakTopic topic in _weakTopics)
              WeakTopicCard(
                key: ValueKey<String>('weak-topic-${topic.topicId}'),
                topic: topic,
                onPractice: () => _practiseUnit(topic),
              ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {required this.style});

  final String title;
  final TextTheme style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(title, style: style.titleMedium.weight(FontWeight.w700)),
    );
  }
}
