import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/routes.dart';
import '../../models/unit.dart';
import '../../providers/auth_provider.dart';
import '../../providers/units_provider.dart';
import '../../widgets/error_view.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/glass_scaffold.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/unit_card.dart';
import '../practice/practice_screen.dart';
import '../progress/progress_screen.dart';
import '../../core/theme.dart';

/// Home: bottom navigation with Units, Practice and Progress tabs.
///
/// Tabs are built the first time they are opened (so Practice does not fetch questions
/// until the student goes there). Practice keeps its state while switching tabs; Progress
/// shows its cached data instantly and refreshes every time it is opened.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  static const int unitsTab = 0;
  static const int practiceTab = 1;
  static const int progressTab = 2;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = HomeScreen.unitsTab;
  final Set<int> _opened = <int>{HomeScreen.unitsTab};
  int _progressVisits = 0;

  void _select(int tab) {
    setState(() {
      _tab = tab;
      _opened.add(tab);
      if (tab == HomeScreen.progressTab) {
        _progressVisits++;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Android back on the Practice/Progress tab goes to Units instead of closing the app.
    return PopScope<Object?>(
      canPop: _tab == HomeScreen.unitsTab,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) {
          _select(HomeScreen.unitsTab);
        }
      },
      child: _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    final GlassPalette p = context.palette;
    return GlassScaffold(
      showAppBar: false,
      body: IndexedStack(
        index: _tab,
        children: <Widget>[
          const UnitsTab(),
          if (_opened.contains(HomeScreen.practiceTab))
            PracticeScreen(
              inTab: true,
              onHome: () => _select(HomeScreen.unitsTab),
            )
          else
            const SizedBox.shrink(),
          if (_opened.contains(HomeScreen.progressTab))
            ProgressScreen(key: ValueKey<int>(_progressVisits))
          else
            const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: GlassBottomBar(
        child: BottomNavigationBar(
          key: const ValueKey<String>('bottom-nav'),
          currentIndex: _tab,
          onTap: _select,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: p.accent,
          unselectedItemColor: p.textSecondary,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.menu_book_rounded),
              label: 'Units',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.edit_note_rounded),
              label: 'Practice',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_rounded),
              label: 'Progress',
            ),
          ],
        ),
      ),
    );
  }
}

/// The 12 syllabus units (first tab).
class UnitsTab extends StatefulWidget {
  const UnitsTab({super.key});

  @override
  State<UnitsTab> createState() => _UnitsTabState();
}

class _UnitsTabState extends State<UnitsTab> {
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

    return GlassScaffold(
      background: false,
      titleWidget: GradientText(
        AppStrings.appName,
        style: Theme.of(context).textTheme.titleLarge.weight(FontWeight.w700),
      ),
      actions: <Widget>[
        IconButton(
          key: const ValueKey<String>('logout-button'),
          tooltip: 'Logout',
          icon: const Icon(Icons.logout_rounded),
          onPressed: _confirmLogout,
        ),
      ],
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
            style: text.bodyMedium?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
