import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/routes.dart';
import '../../core/theme.dart';
import '../../models/solver_result.dart';
import '../../models/topic.dart';
import '../../models/unit.dart';
import '../../providers/units_provider.dart';
import '../../services/api_exception.dart';
import '../../services/solver_service.dart';
import '../../widgets/error_view.dart';
import '../../widgets/formula_card.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/glass_scaffold.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/motion.dart';
import '../../widgets/topic_card.dart';
import '../../widgets/tutor_response_card.dart';

/// Smart Question Solver: the student types the chapter, the question and (optionally)
/// the book's answer; the AI solves it step by step in the textbook pattern.
class SolverScreen extends StatefulWidget {
  const SolverScreen({super.key, this.inTab = false});

  /// Shown as a Home tab (the Home screen paints the background).
  final bool inTab;

  /// Picks the syllabus unit a typed chapter name refers to (for "AI Tutor se poochein").
  /// Words of 3+ letters are compared; a 5-letter prefix counts ("trigonometry" finds
  /// "Trigonometric"). Returns null when nothing matches.
  static Unit? matchUnit(String chapter, List<Unit> units) {
    List<String> words(String text) => text
        .toLowerCase()
        .split(RegExp('[^a-z0-9]+'))
        .where((String w) => w.length >= 3)
        .toList();
    bool same(String a, String b) =>
        a == b ||
        (a.length >= 5 &&
            b.length >= 5 &&
            a.substring(0, 5) == b.substring(0, 5));

    final List<String> wanted = words(chapter);
    Unit? best;
    int bestScore = 0;
    for (final Unit unit in units) {
      final List<String> title = words(unit.title);
      final int score = wanted
          .where((String w) => title.any((String t) => same(w, t)))
          .length;
      if (score > bestScore) {
        best = unit;
        bestScore = score;
      }
    }
    return best;
  }

  @override
  State<SolverScreen> createState() => _SolverScreenState();
}

class _SolverScreenState extends State<SolverScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _chapter = TextEditingController();
  final TextEditingController _question = TextEditingController();
  final TextEditingController _bookAnswer = TextEditingController();
  final FocusNode _questionFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  final GlobalKey _resultKey = GlobalKey();

  bool _solving = false;
  ApiException? _error;
  SolverResult? _result;

  @override
  void dispose() {
    _chapter.dispose();
    _question.dispose();
    _bookAnswer.dispose();
    _questionFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _solve() async {
    if (_solving || !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _solving = true;
      _error = null;
      _result = null;
    });
    try {
      final SolverResult result = await context.read<SolverService>().solve(
        chapter: _chapter.text,
        question: _question.text,
        bookAnswer: _bookAnswer.text,
      );
      if (mounted) {
        setState(() => _result = result);
        _scrollToResult();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e);
      }
    } finally {
      if (mounted) {
        setState(() => _solving = false);
      }
    }
  }

  void _scrollToResult() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? target = _resultKey.currentContext;
      if (target != null && target.mounted) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// "Dobara Solve Karo": keep the chapter, clear the rest, start again at the top.
  void _reset() {
    setState(() {
      _result = null;
      _error = null;
      _question.clear();
      _bookAnswer.clear();
    });
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    _questionFocus.requestFocus();
  }

  /// Opens the AI tutor with this question, in the unit the chapter name refers to.
  Future<void> _askTutor(SolverResult result) async {
    final UnitsProvider units = context.read<UnitsProvider>();
    await units.loadUnits();
    if (!mounted) {
      return;
    }
    final List<Unit> all = units.units.data ?? const <Unit>[];
    final Unit? unit =
        SolverScreen.matchUnit(result.chapter, all) ?? await _pickUnit(all);
    if (unit == null || !mounted) {
      return;
    }
    await units.loadTopics(unit.id);
    if (!mounted) {
      return;
    }
    final List<Topic> topics = units.topicsFor(unit.id).data ?? const <Topic>[];
    if (topics.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Is unit ke topics load nahi ho sake. Dobara try karein.',
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).pushNamed(
      Routes.tutor,
      arguments: TutorRouteArgs(
        topic: topics.first,
        unit: unit,
        initialQuestion: result.question.length > ApiConfig.maxQuestionLength
            ? result.question.substring(0, ApiConfig.maxQuestionLength)
            : result.question,
      ),
    );
  }

  Future<Unit?> _pickUnit(List<Unit> units) {
    return showModalBottomSheet<Unit>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheet) => SafeArea(
        child: ListView(
          key: const ValueKey<String>('unit-picker'),
          shrinkWrap: true,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Yeh sawal kis unit ka hai?'),
            ),
            for (final Unit unit in units)
              ListTile(
                title: Text('Unit ${unit.unitNumber}: ${unit.title}'),
                onTap: () => Navigator.of(sheet).pop(unit),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SolverResult? result = _result;
    return GlassScaffold(
      background: !widget.inTab,
      title: 'Sawal Hal Karo',
      body: ListView(
        key: const ValueKey<String>('solver-list'),
        controller: _scroll,
        padding: const EdgeInsets.only(top: 4, bottom: 32),
        children: <Widget>[
          _buildForm(),
          if (_solving)
            const GlassCard(
              key: ValueKey<String>('solver-loading'),
              child: LoadingWidget(
                message:
                    'Sawal hal ho raha hai... har qadam likha ja raha hai.\n'
                    '(20-40 seconds lag sakte hain)',
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ErrorView(error: _error!, compact: true, onRetry: _solve),
            ),
          if (result != null)
            KeyedSubtree(
              key: _resultKey,
              child: SolverResultView(
                result: result,
                onSolveAgain: _reset,
                onAskTutor: () => _askTutor(result),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    final GlassPalette p = context.palette;
    return GlassCard(
      key: const ValueKey<String>('solver-form'),
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Jo sawal samajh nahi aaya, yahan likhein. Hum har qadam '
              'samjha kar hal karenge.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: 14),
            TextFormField(
              key: const ValueKey<String>('solver-chapter'),
              controller: _chapter,
              enabled: !_solving,
              maxLength: ApiConfig.maxSolverChapterLength,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Chapter ka naam likhein',
                hintText: 'e.g. Complex Numbers, Vectors',
                prefixIcon: Icon(Icons.menu_book_rounded),
                counterText: '',
              ),
              validator: (String? v) => (v ?? '').trim().isEmpty
                  ? 'Chapter ka naam zaroori hai'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey<String>('solver-question'),
              controller: _question,
              focusNode: _questionFocus,
              enabled: !_solving,
              minLines: 3,
              maxLines: 8,
              maxLength: ApiConfig.maxSolverQuestionLength,
              decoration: const InputDecoration(
                labelText: 'Apna sawal',
                hintText: 'Apna sawal yahan likhein...',
                alignLabelWithHint: true,
              ),
              validator: (String? v) =>
                  (v ?? '').trim().isEmpty ? 'Sawal likhna zaroori hai' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey<String>('solver-book-answer'),
              controller: _bookAnswer,
              enabled: !_solving,
              maxLength: ApiConfig.maxSolverBookAnswerLength,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _solve(),
              decoration: const InputDecoration(
                labelText: 'Book ka jawab (optional)',
                hintText: 'Agar book mein jawab diya hai to likhein',
                prefixIcon: Icon(Icons.fact_check_outlined),
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),
            GradientButton(
              key: const ValueKey<String>('solve-button'),
              onPressed: _solving ? null : _solve,
              icon: const Icon(Icons.search_rounded),
              // The search icon is the 🔍; no emoji in the label as well.
              child: Text(_solving ? 'Hal ho raha hai...' : 'Hal Karo'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Urdu ordinal step labels: "Pehla Qadam", "Doosra Qadam", ...
String stepLabel(int number) {
  const List<String> ordinals = <String>[
    'Pehla',
    'Doosra',
    'Teesra',
    'Chautha',
    'Paanchwan',
    'Chhata',
    'Saatwan',
    'Aathwan',
    'Nawan',
    'Daswan',
  ];
  return number >= 1 && number <= ordinals.length
      ? '${ordinals[number - 1]} Qadam'
      : 'Qadam $number';
}

/// The solved question: header, steps, formulas, concepts, answer, tip, buttons.
class SolverResultView extends StatelessWidget {
  const SolverResultView({
    super.key,
    required this.result,
    required this.onSolveAgain,
    required this.onAskTutor,
  });

  final SolverResult result;
  final VoidCallback onSolveAgain;
  final VoidCallback onAskTutor;

  @override
  Widget build(BuildContext context) {
    final GlassPalette p = context.palette;
    return Column(
      key: const ValueKey<String>('solver-result'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _Header(result: result),
        if (result.warning != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: WarningBox(message: result.warning!),
          ),
        if (result.isStructured) ...<Widget>[
          const SectionHeader('Hal (Solution)', icon: Icons.stairs_rounded),
          for (final SolverStep step in result.steps)
            SolverStepCard(
              key: ValueKey<String>('solver-step-${step.stepNumber}'),
              step: step,
              initiallyExpanded: step.stepNumber == 1,
            ),
          if (result.formulasApplied.isNotEmpty) ...<Widget>[
            const SectionHeader('Formulas', icon: Icons.functions_rounded),
            _Chips(
              key: const ValueKey<String>('solver-formulas'),
              items: result.formulasApplied,
              color: p.accent,
              mono: true,
            ),
          ],
          if (result.keyConcepts.isNotEmpty) ...<Widget>[
            const SectionHeader('Key Concepts', icon: Icons.lightbulb_outline),
            _Chips(
              key: const ValueKey<String>('solver-concepts'),
              items: result.keyConcepts,
              color: p.accent,
            ),
          ],
          _AnswerCard(result: result),
        ] else
          GlassCard(
            key: const ValueKey<String>('solver-plain-solution'),
            child: SelectableText(result.solution),
          ),
        _ProTip(tip: result.proTip),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: GradientButton(
            key: const ValueKey<String>('solve-again'),
            onPressed: onSolveAgain,
            icon: const Icon(Icons.refresh_rounded),
            child: const Text('Dobara Solve Karo'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: OutlinedButton.icon(
            key: const ValueKey<String>('ask-tutor'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: onAskTutor,
            icon: const Icon(Icons.smart_toy_rounded),
            label: const Text('AI Tutor se poochein'),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.result});

  final SolverResult result;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Appear(
      child: GlassCard(
        key: const ValueKey<String>('solver-header'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      gradient: context.palette.accentGradient,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      result.chapter,
                      key: const ValueKey<String>('solver-chapter-badge'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelLarge.weight(
                        FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DifficultyBadge(difficulty: result.difficulty),
              ],
            ),
            if (result.methodUsed.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                'Tareeqa: ${result.methodUsed}',
                key: const ValueKey<String>('solver-method'),
                style: text.titleMedium.weight(FontWeight.w600),
              ),
            ],
            const SizedBox(height: 6),
            Text(result.question, style: text.bodyMedium),
          ],
        ),
      ),
    );
  }
}

/// One step (Qadam), expandable: explanation, formula and calculation.
class SolverStepCard extends StatelessWidget {
  const SolverStepCard({
    super.key,
    required this.step,
    this.initiallyExpanded = false,
  });

  final SolverStep step;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final GlassPalette p = context.palette;
    return Appear(
      child: GlassCard(
        blur: false,
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          leading: GradientCircle(size: 34, child: Text('${step.stepNumber}')),
          title: Text(
            stepLabel(step.stepNumber),
            style: text.titleSmall.weight(FontWeight.w700),
          ),
          subtitle: Text(step.title, style: text.bodySmall),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Divider(color: p.glassBorder, height: 1),
            const SizedBox(height: 10),
            Text(step.explanation, style: text.bodyMedium),
            if (step.formulaUsed != null)
              _MathBox(
                key: const ValueKey<String>('step-formula'),
                label: 'Formula',
                value: step.formulaUsed!,
                color: p.accent,
              ),
            if (step.calculation != null)
              _MathBox(
                key: const ValueKey<String>('step-calculation'),
                label: 'Calculation',
                value: step.calculation!,
                color: p.secondary,
              ),
          ],
        ),
      ),
    );
  }
}

class _MathBox extends StatelessWidget {
  const _MathBox({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                .weight(FontWeight.w700, color: color),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: mathTextStyle.copyWith(fontSize: 14, color: color),
          ),
        ],
      ),
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips({
    super.key,
    required this.items,
    required this.color,
    this.mono = false,
  });

  final List<String> items;
  final Color color;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: <Widget>[
          for (final String item in items)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Text(
                item,
                style: (mono ? mathTextStyle : const TextStyle()).copyWith(
                  fontSize: 13,
                  color: context.palette.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.result});

  final SolverResult result;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final GlassPalette p = context.palette;
    final bool hasBook = result.bookAnswer != null;
    final bool match = result.answerVerified;
    return Appear(
      child: GlassCard(
        key: const ValueKey<String>('solver-answer'),
        margin: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        tint: hasBook ? (match ? p.success : p.error) : null,
        borderColor: hasBook ? (match ? p.success : p.error) : null,
        glowColor: hasBook && match ? p.success : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Jawab', style: text.labelLarge),
            const SizedBox(height: 2),
            SelectableText(
              result.ourAnswer,
              key: const ValueKey<String>('solver-our-answer'),
              style: mathTextStyle.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: p.textPrimary,
              ),
            ),
            if (hasBook) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                match
                    ? '✅ Book ke jawab se match karta hai!'
                    : '❌ Book ke jawab se match nahi',
                key: const ValueKey<String>('book-match'),
                style: text.titleSmall.weight(
                  FontWeight.w700,
                  color: match ? p.success : p.error,
                ),
              ),
              if (!match)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Book ka jawab: ${result.bookAnswer}\n'
                    'Book mein kabhi kabhi print ki ghalti hoti hai — apne '
                    'teacher se confirm karein.',
                    key: const ValueKey<String>('book-mismatch-note'),
                    style: text.bodySmall,
                  ),
                ),
            ],
            const SizedBox(height: 10),
            GlassPill(
              key: const ValueKey<String>('solver-sympy-badge'),
              icon: result.sympyVerified
                  ? Icons.check_circle_rounded
                  : Icons.help_outline_rounded,
              color: result.sympyVerified ? p.success : p.textSecondary,
              label: result.sympyVerified ? 'SymPy verified' : 'Not verified',
            ),
          ],
        ),
      ),
    );
  }
}

class _ProTip extends StatelessWidget {
  const _ProTip({required this.tip});

  final String tip;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color amber = context.palette.secondary;
    return Appear(
      child: GlassCard(
        key: const ValueKey<String>('solver-pro-tip'),
        tint: amber,
        borderColor: amber.withValues(alpha: 0.7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('💡', style: TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Exam Tip',
                    style: text.titleSmall.weight(
                      FontWeight.w700,
                      color: amber,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(tip, style: text.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
