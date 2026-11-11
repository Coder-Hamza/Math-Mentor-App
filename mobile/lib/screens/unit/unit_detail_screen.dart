import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes.dart';
import '../../models/topic.dart';
import '../../models/unit.dart';
import '../../providers/units_provider.dart';
import '../../widgets/error_view.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/glass_scaffold.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/topic_card.dart';
import '../../core/theme.dart';

/// Topics of one unit, each with a colour-coded difficulty badge.
class UnitDetailScreen extends StatefulWidget {
  const UnitDetailScreen({super.key, required this.unit});

  final Unit unit;

  @override
  State<UnitDetailScreen> createState() => _UnitDetailScreenState();
}

class _UnitDetailScreenState extends State<UnitDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<UnitsProvider>().loadTopics(widget.unit.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final UnitsProvider provider = context.watch<UnitsProvider>();
    final Loadable<List<Topic>> state = provider.topicsFor(widget.unit.id);
    Future<void> reload() => provider.loadTopics(widget.unit.id, force: true);

    final List<Widget> content;
    if (!state.hasData && state.error != null) {
      content = <Widget>[ErrorView(error: state.error!, onRetry: reload)];
    } else if (!state.hasData) {
      content = <Widget>[
        const LoadingWidget(message: 'Topics load ho rahe hain...'),
      ];
    } else {
      content = <Widget>[
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ErrorView(
              error: state.error!,
              compact: true,
              onRetry: reload,
            ),
          ),
        for (final Topic topic in state.data!)
          TopicCard(
            key: ValueKey<String>('topic-${topic.id}'),
            topic: topic,
            onTap: () => Navigator.of(context).pushNamed(
              Routes.topic,
              arguments: TopicRouteArgs(topic: topic, unit: widget.unit),
            ),
          ),
      ];
    }

    return GlassScaffold(
      title: 'Unit ${widget.unit.unitNumber}',
      body: RefreshIndicator(
        onRefresh: reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: <Widget>[
            _UnitHeader(unit: widget.unit),
            ...content,
          ],
        ),
      ),
    );
  }
}

class _UnitHeader extends StatelessWidget {
  const _UnitHeader({required this.unit});

  final Unit unit;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return GlassCard(
      key: const ValueKey<String>('unit-header'),
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          GradientText(unit.title, style: text.headlineSmall),
          const SizedBox(height: 6),
          GlassPill(
            label: 'Textbook page ${unit.pageNumber}',
            color: context.palette.secondary,
            icon: Icons.menu_book_rounded,
          ),
          if (unit.description != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(unit.description!, style: text.bodyMedium),
          ],
        ],
      ),
    );
  }
}
