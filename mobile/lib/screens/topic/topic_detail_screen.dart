import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/routes.dart';
import '../../models/formula.dart';
import '../../models/topic.dart';
import '../../models/unit.dart';
import '../../providers/units_provider.dart';
import '../../services/storage_service.dart';
import '../../widgets/error_view.dart';
import '../../widgets/formula_card.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/topic_card.dart';
import '../../core/theme.dart';

/// Topic overview: formulas, the "Ask AI Tutor" button, and recent questions.
class TopicDetailScreen extends StatefulWidget {
  const TopicDetailScreen({super.key, required this.topic, required this.unit});

  final Topic topic;
  final Unit unit;

  @override
  State<TopicDetailScreen> createState() => _TopicDetailScreenState();
}

class _TopicDetailScreenState extends State<TopicDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<UnitsProvider>().loadFormulas(widget.topic.id),
    );
  }

  Future<void> _openTutor([String? question]) async {
    await Navigator.of(context).pushNamed(
      Routes.tutor,
      arguments: TutorRouteArgs(
        topic: widget.topic,
        unit: widget.unit,
        initialQuestion: question,
      ),
    );
    if (mounted) {
      setState(() {}); // refresh "Recent questions"
    }
  }

  @override
  Widget build(BuildContext context) {
    final UnitsProvider provider = context.watch<UnitsProvider>();
    final Loadable<List<Formula>> formulas = provider.formulasFor(
      widget.topic.id,
    );
    final List<String> recent = context.read<StorageService>().recentQuestions(
      widget.topic.id,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.topic.title, overflow: TextOverflow.ellipsis),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: <Widget>[
          _TopicHeader(topic: widget.topic, unit: widget.unit),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: FilledButton.icon(
              key: const ValueKey<String>('ask-ai-button'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.black87,
              ),
              onPressed: _openTutor,
              icon: const Icon(Icons.smart_toy_rounded),
              label: const Text('Ask AI Tutor'),
            ),
          ),
          const _SectionTitle(title: 'Formulas', icon: Icons.functions_rounded),
          ..._formulaSection(formulas, provider),
          if (recent.isNotEmpty) ...<Widget>[
            const _SectionTitle(
              title: 'Recent questions',
              icon: Icons.history_rounded,
            ),
            Card(
              child: Column(
                children: <Widget>[
                  for (final String question in recent)
                    ListTile(
                      leading: const Icon(Icons.chat_bubble_outline_rounded),
                      title: Text(
                        question,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _openTutor(question),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _formulaSection(
    Loadable<List<Formula>> state,
    UnitsProvider provider,
  ) {
    Future<void> reload() =>
        provider.loadFormulas(widget.topic.id, force: true);
    if (!state.hasData && state.error != null) {
      return <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ErrorView(error: state.error!, compact: true, onRetry: reload),
        ),
      ];
    }
    if (!state.hasData) {
      return const <Widget>[LoadingWidget(size: 32)];
    }
    if (state.data!.isEmpty) {
      return const <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('Is topic ke liye formulas abhi nahi hain.'),
        ),
      ];
    }
    return <Widget>[
      for (final Formula formula in state.data!)
        FormulaCard(
          key: ValueKey<String>('formula-${formula.id}'),
          formula: formula,
        ),
    ];
  }
}

class _TopicHeader extends StatelessWidget {
  const _TopicHeader({required this.topic, required this.unit});

  final Topic topic;
  final Unit unit;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      color: AppColors.primary,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Unit ${unit.unitNumber} · ${unit.title}',
            style: text.bodySmall?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  topic.title,
                  style: text.titleLarge.weight(
                    FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: DifficultyBadge(difficulty: topic.difficulty),
              ),
            ],
          ),
          if (topic.description != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              topic.description!,
              style: text.bodyMedium?.copyWith(color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                .weight(FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
