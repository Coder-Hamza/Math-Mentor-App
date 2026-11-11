import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../models/topic.dart';
import '../../models/tutor_response.dart';
import '../../models/unit.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/error_view.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/tutor_response_card.dart';

/// One question and its answer (or error) in the conversation.
class TutorExchange {
  TutorExchange(this.question);

  final String question;
  TutorResponse? response;
  ApiException? error;
  bool loading = true;
}

/// Chat with the AI tutor about one topic.
class TutorScreen extends StatefulWidget {
  const TutorScreen({
    super.key,
    required this.topic,
    required this.unit,
    this.initialQuestion,
  });

  final Topic topic;
  final Unit unit;

  /// Pre-fills the input (e.g. from "Recent questions"); never sent automatically,
  /// so free-tier AI quota is only used when the student taps Send.
  final String? initialQuestion;

  @override
  State<TutorScreen> createState() => _TutorScreenState();
}

class _TutorScreenState extends State<TutorScreen> {
  late final TextEditingController _input = TextEditingController(
    text: widget.initialQuestion,
  );
  final ScrollController _scroll = ScrollController();
  final List<TutorExchange> _exchanges = <TutorExchange>[];
  TutorLanguage _language = TutorLanguage.urduEnglish;

  bool get _busy => _exchanges.any((TutorExchange e) => e.loading);

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String question = _input.text.trim();
    if (question.isEmpty || _busy) {
      return;
    }
    final TutorExchange exchange = TutorExchange(question);
    setState(() {
      _exchanges.add(exchange);
      _input.clear();
    });
    FocusScope.of(context).unfocus();
    await context.read<StorageService>().addRecentQuestion(
      widget.topic.id,
      question,
    );
    await _ask(exchange);
  }

  Future<void> _ask(TutorExchange exchange) async {
    final ApiService api = context.read<ApiService>();
    setState(() {
      exchange
        ..loading = true
        ..error = null;
    });
    _scrollToEnd();
    try {
      exchange.response = await api.askTutor(
        topicId: widget.topic.id,
        question: exchange.question,
        language: _language,
      );
    } on ApiException catch (e) {
      exchange.error = e;
    }
    if (!mounted) {
      return;
    }
    setState(() => exchange.loading = false);
    _scrollToEnd();
  }

  void _scrollToEnd() {
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

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('AI Tutor'),
            Text(
              widget.topic.title,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: Colors.white70),
            ),
          ],
        ),
        actions: <Widget>[
          PopupMenuButton<TutorLanguage>(
            key: const ValueKey<String>('language-menu'),
            tooltip: 'Jawab ki zubaan (answer language)',
            icon: const Icon(Icons.translate_rounded),
            initialValue: _language,
            onSelected: (TutorLanguage value) =>
                setState(() => _language = value),
            itemBuilder: (_) => <PopupMenuEntry<TutorLanguage>>[
              for (final TutorLanguage language in TutorLanguage.values)
                PopupMenuItem<TutorLanguage>(
                  value: language,
                  child: Text(language.label),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _ContextBanner(
            topic: widget.topic,
            unit: widget.unit,
            language: _language,
          ),
          Expanded(
            child: _exchanges.isEmpty
                ? _EmptyState(
                    topic: widget.topic,
                    onSuggestion: (String s) => _input.text = s,
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _exchanges.length,
                    itemBuilder: (_, int i) => _ExchangeView(
                      exchange: _exchanges[i],
                      onRetry: () => _ask(_exchanges[i]),
                    ),
                  ),
          ),
          _InputBar(controller: _input, busy: _busy, onSend: _send),
        ],
      ),
    );
  }
}

class _ContextBanner extends StatelessWidget {
  const _ContextBanner({
    required this.topic,
    required this.unit,
    required this.language,
  });

  final Topic topic;
  final Unit unit;
  final TutorLanguage language;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('tutor-context'),
      width: double.infinity,
      color: AppColors.primary.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        'Unit ${unit.unitNumber}: ${unit.title} › ${topic.title} · ${language.label}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.topic, required this.onSuggestion});

  final Topic topic;
  final ValueChanged<String> onSuggestion;

  @override
  Widget build(BuildContext context) {
    final List<String> suggestions = <String>[
      '${topic.title} ko example ke saath samjhayein',
      '${topic.title} ka aik board exam jaisa sawal hal karein',
    ];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        const Icon(Icons.smart_toy_rounded, size: 64, color: AppColors.primary),
        const SizedBox(height: 12),
        Text(
          'Is topic ke bare mein koi bhi sawal poochein.\nJawab step-by-step milega.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final String s in suggestions)
              ActionChip(label: Text(s), onPressed: () => onSuggestion(s)),
          ],
        ),
      ],
    );
  }
}

class _ExchangeView extends StatelessWidget {
  const _ExchangeView({required this.exchange, required this.onRetry});

  final TutorExchange exchange;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final Widget answer;
    if (exchange.loading) {
      answer = const LoadingWidget(
        key: ValueKey<String>('tutor-loading'),
        message: 'MathMentor soch raha hai... (10–20 seconds lag sakte hain)',
      );
    } else if (exchange.error != null) {
      answer = Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 40, 6),
        child: ErrorView(
          error: exchange.error!,
          compact: true,
          onRetry: onRetry,
        ),
      );
    } else {
      answer = TutorResponseCard(response: exchange.response!);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _QuestionBubble(text: exchange.question),
        answer,
      ],
    );
  }
}

class _QuestionBubble extends StatelessWidget {
  const _QuestionBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.fromLTRB(56, 8, 16, 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.busy,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final bool canSend = !busy && controller.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: TextField(
                key: const ValueKey<String>('tutor-input'),
                controller: controller,
                minLines: 1,
                maxLines: 4,
                maxLength: ApiConfig.maxQuestionLength,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(hintText: AppStrings.askHint),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: IconButton.filled(
                key: const ValueKey<String>('send-button'),
                tooltip: 'Send',
                onPressed: canSend ? onSend : null,
                icon: const Icon(Icons.send_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
