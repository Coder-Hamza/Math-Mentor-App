import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/routes.dart';
import '../../models/unit.dart';
import '../../providers/auth_provider.dart';
import '../../providers/units_provider.dart';
import '../../widgets/error_view.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/unit_card.dart';
import '../../core/theme.dart';

/// The 12 syllabus units.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<UnitsProvider>().loadUnits(),
    );
  }

  Future<void> _confirmLogout() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Logout karein?'),
        content: const Text('Aap ko dobara login karna hoga.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      if (!mounted) {
        return;
      }
      // The app root reacts to the status change and opens the login screen.
      await context.read<AuthProvider>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final UnitsProvider provider = context.watch<UnitsProvider>();
    final Loadable<List<Unit>> state = provider.units;
    final String? name = context.select<AuthProvider, String?>(
      (AuthProvider a) => a.user?.firstName,
    );

    final Widget body;
    if (!state.hasData && state.error != null) {
      body = ErrorView(
        error: state.error!,
        onRetry: () => provider.loadUnits(force: true),
      );
    } else if (!state.hasData) {
      body = const LoadingWidget(message: 'Units load ho rahe hain...');
    } else {
      final List<Unit> units = state.data!;
      body = RefreshIndicator(
        onRefresh: () => provider.loadUnits(force: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: <Widget>[
            _Greeting(name: name),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: ErrorView(
                  error: state.error!,
                  compact: true,
                  onRetry: () => provider.loadUnits(force: true),
                ),
              ),
            for (final Unit unit in units)
              UnitCard(
                key: ValueKey<String>('unit-${unit.id}'),
                unit: unit,
                onTap: () =>
                    Navigator.of(context)
                        .pushNamed(Routes.unit, arguments: unit),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.appName),
        actions: <Widget>[
          IconButton(
            key: const ValueKey<String>('logout-button'),
            tooltip: 'Logout',
            icon: const Icon(Icons.logout_rounded),
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: body,
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            name == null ? 'Assalam-o-Alaikum!' : 'Assalam-o-Alaikum, $name!',
            style: text.titleLarge.weight(FontWeight.w600),
          ),
          Text(
            'Aaj kaunsa unit parhenge? (${AppStrings.tagline})',
            style: text.bodyMedium?.copyWith(color: AppColors.unverified),
          ),
        ],
      ),
    );
  }
}
