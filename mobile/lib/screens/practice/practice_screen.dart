import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/practice_question.dart';
import '../../models/practice_result.dart';
import '../../services/api_exception.dart';
import '../../services/practice_service.dart';
import '../../widgets/error_view.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/practice_result_card.dart';
import '../../widgets/topic_card.dart';

/// A practice session: [PracticeService.defaultCount] random questions, one at a time,
/// graded by the server; then a summary.
///
/// The correct answer is only known (and shown) after the student submits.
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({
    super.key,
    this.unitId,
    this.title = 'Practice',
    this.onHome,
  });

  /// Practise one unit only (from the weak-topics list); null = all units.
  final int? unitId;
  final String title;

  /// What "Home" does on the summary; defaults to closing this screen.
  final VoidCallback? onHome;

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  final TextEditingController _answer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final Stopwatch _stopwatch = Stopwatch();

  List<PracticeQuestion>? _questions;
  ApiException? _loadError;
  bool _loading = false;

  int _index = 0;
  String? _selectedOption;
  bool _submitting = false;
  ApiException? _submitError;
  PracticeResult? _result;
  final List<PracticeResult> _results = <PracticeResult>[];
  bool _finished = false;

  PracticeQuestion get _question => _questions![_index];

  String get _currentAnswer =>
      _question.isMcq ? (_selectedOption ?? '') : _answer.text.trim();

  int get _sessionPoints =>
      _results.fold(0, (int sum, PracticeResult r) => sum + r.pointsEarned);

  @override
  void initState() {
    super.initState();
    _answer.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _answer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final List<PracticeQuestion> questions = await context
          .read<PracticeService>()
          .randomQuestions(unitId: widget.unitId);
      if (!mounted) {
        return;
      }
      setState(() {
        _questions = questions;
        _index = 0;
        _results.clear();
        _finished = false;
        _resetAnswer();
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _loadError = e);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _resetAnswer() {
    _answer.clear();
    _selectedOption = null;
    _result = null;
    _submitError = null;
    _stopwatch
      ..reset()
      ..start();
  }

  Future<void> _submit() async {
    final String answer = _currentAnswer;
    if (answer.isEmpty || _submitting || _result != null) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final PracticeResult result = await context
          .read<PracticeService>()
          .submit(
            questionId: _question.id,
            answer: answer,
            timeTakenSeconds: _stopwatch.elapsed.inSeconds,
          );
      if (!mounted) {
        return;
      }
      _stopwatch.stop();
      setState(() {
        _result = result;
        _results.add(result);
      });
      _scrollToBottom();
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _submitError = e);
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  /// Bring the result card and the "next" button into view.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _next() {
    setState(() {
      if (_index + 1 < _questions!.length) {
        _index++;
        _resetAnswer();
        if (_scroll.hasClients) {
          _scroll.jumpTo(0);
        }
      } else {
        _finished = true;
        _stopwatch.stop();
      }
    });
  }

  void _goHome() {
    if (widget.onHome != null) {
      widget.onHome!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          if (_results.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  '⭐ $_sessionPoints',
                  key: const ValueKey<String>('session-points'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const LoadingWidget(message: 'Sawaal load ho rahe hain...');
    }
    if (_loadError != null) {
      return ErrorView(error: _loadError!, onRetry: _load);
    }
    final List<PracticeQuestion>? questions = _questions;
    if (questions == null) {
      return const SizedBox.shrink();
    }
    if (questions.isEmpty) {
      return _EmptyPractice(onHome: _goHome);
    }
    if (_finished) {
      return PracticeSummary(
        results: _results,
        total: questions.length,
        onPlayAgain: _load,
        onHome: _goHome,
      );
    }
    return _buildQuestion(questions.length);
  }

  Widget _buildQuestion(int total) {
    final PracticeQuestion question = _question;
    final PracticeResult? result = _result;
    final bool answered = result != null;
    final bool isLast = _index + 1 >= total;

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 32),
      children: <Widget>[
        QuestionCard(question: question, number: _index + 1, total: total),
        if (question.isMcq)
          for (int i = 0; i < question.options!.length; i++)
            McqOptionButton(
              key: ValueKey<String>('option-$i'),
              letter: optionLetters[i],
              text: question.options![i],
              selected: _selectedOption == question.options![i],
              state: _optionState(question.options![i], result),
              onTap: answered
                  ? null
                  : () =>
                        setState(() => _selectedOption = question.options![i]),
            )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              key: const ValueKey<String>('answer-input'),
              controller: _answer,
              enabled: !answered && !_submitting,
              maxLength: ApiConfig.maxQuestionLength,
              minLines: 1,
              maxLines: question.questionType == QuestionType.long ? 4 : 2,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                hintText: 'Apna jawab likhein (e.g. 3/2, 2 + 3i, x = 1, y = 2)',
              ),
            ),
          ),
        if (_submitError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ErrorView(
              error: _submitError!,
              compact: true,
              onRetry: _submit,
            ),
          ),
        if (!answered)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: FilledButton.icon(
              key: const ValueKey<String>('submit-answer'),
              onPressed: _currentAnswer.isEmpty || _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_submitting ? 'Check ho raha hai...' : 'Submit'),
            ),
          )
        else ...<Widget>[
          const SizedBox(height: 8),
          PracticeResultCard(result: result),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: FilledButton.icon(
              key: const ValueKey<String>('next-question'),
              onPressed: _next,
              icon: Icon(
                isLast ? Icons.flag_rounded : Icons.arrow_forward_rounded,
              ),
              label: Text(isLast ? 'Result dekhein' : 'Agla Sawaal'),
            ),
          ),
        ],
      ],
    );
  }

  static OptionState _optionState(String option, PracticeResult? result) {
    if (result == null) {
      return OptionState.open;
    }
    if (option == result.correctAnswer) {
      return OptionState.correct;
    }
    return OptionState.other;
  }
}

/// Question number, difficulty, unit and the question itself.
class QuestionCard extends StatelessWidget {
  const QuestionCard({
    super.key,
    required this.question,
    required this.number,
    required this.total,
  });

  final PracticeQuestion question;
  final int number;
  final int total;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      key: const ValueKey<String>('question-card'),
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  'Sawaal $number/$total',
                  key: const ValueKey<String>('question-counter'),
                  style: text.labelLarge.weight(
                    FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                const Spacer(),
                DifficultyBadge(difficulty: question.difficulty),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Unit ${question.unitNumber}: ${question.unitTitle} · '
              '${question.topicTitle}',
              style: text.bodySmall?.copyWith(color: AppColors.unverified),
            ),
            const SizedBox(height: 12),
            Text(
              question.questionText,
              style: text.titleMedium.weight(FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

enum OptionState { open, correct, other }

/// One MCQ choice. After grading, the right option turns green.
class McqOptionButton extends StatelessWidget {
  const McqOptionButton({
    super.key,
    required this.letter,
    required this.text,
    required this.selected,
    required this.state,
    this.onTap,
  });

  final String letter;
  final String text;
  final bool selected;
  final OptionState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (state) {
      OptionState.correct => AppColors.verified,
      OptionState.other when selected => AppColors.failed,
      _ when selected => AppColors.primary,
      _ => AppColors.unverified,
    };
    final bool highlighted = selected || state == OptionState.correct;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: highlighted ? color.withValues(alpha: 0.1) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color, width: highlighted ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: color,
                  child: Text(
                    letter,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(text)),
                if (state == OptionState.correct)
                  const Icon(Icons.check_circle, color: AppColors.verified)
                else if (state == OptionState.other && selected)
                  const Icon(Icons.cancel, color: AppColors.failed),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// End of a session: points, right/wrong counts, play again or go home.
class PracticeSummary extends StatelessWidget {
  const PracticeSummary({
    super.key,
    required this.results,
    required this.total,
    required this.onPlayAgain,
    required this.onHome,
  });

  final List<PracticeResult> results;
  final int total;
  final VoidCallback onPlayAgain;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final int correct = results.where((PracticeResult r) => r.isCorrect).length;
    final int wrong = results.length - correct;
    final int points = results.fold(
      0,
      (int sum, PracticeResult r) => sum + r.pointsEarned,
    );
    return ListView(
      key: const ValueKey<String>('practice-summary'),
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Text(
          correct == total ? '🎉' : '📘',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 56),
        ),
        const SizedBox(height: 8),
        Text(
          'Session mukammal!',
          textAlign: TextAlign.center,
          style: text.headlineSmall.weight(FontWeight.w700),
        ),
        const SizedBox(height: 24),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                _SummaryRow(
                  key: const ValueKey<String>('summary-points'),
                  label: 'Points earned',
                  value: '🏆 $points',
                ),
                _SummaryRow(
                  key: const ValueKey<String>('summary-correct'),
                  label: 'Sahi (correct)',
                  value: '✅ $correct',
                ),
                _SummaryRow(
                  key: const ValueKey<String>('summary-wrong'),
                  label: 'Ghalat (wrong)',
                  value: '❌ $wrong',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: const ValueKey<String>('play-again'),
          onPressed: onPlayAgain,
          icon: const Icon(Icons.replay_rounded),
          label: const Text('Dobara Khelo'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey<String>('practice-home'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
          ),
          onPressed: onHome,
          icon: const Icon(Icons.home_rounded),
          label: const Text('Home'),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: text.bodyLarge)),
          Text(value, style: text.titleMedium.weight(FontWeight.w700)),
        ],
      ),
    );
  }
}

class _EmptyPractice extends StatelessWidget {
  const _EmptyPractice({required this.onHome});

  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.inbox_outlined,
              size: 56,
              color: AppColors.unverified,
            ),
            const SizedBox(height: 12),
            const Text(
              'Abhi practice ke liye koi sawaal nahi.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onHome, child: const Text('Home')),
          ],
        ),
      ),
    );
  }
}
