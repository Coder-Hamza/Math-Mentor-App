import 'package:flutter/foundation.dart';

import '../models/formula.dart';
import '../models/topic.dart';
import '../models/unit.dart';
import '../services/api_service.dart';

/// Data + loading + error for one request.
class Loadable<T> {
  const Loadable({this.data, this.isLoading = false, this.error});

  final T? data;
  final bool isLoading;
  final ApiException? error;

  bool get hasData => data != null;
}

/// Syllabus content: units, topics per unit, formulas per topic (cached in memory).
class UnitsProvider extends ChangeNotifier {
  UnitsProvider(this._api);

  final ApiService _api;

  Loadable<List<Unit>> _units = const Loadable<List<Unit>>();
  final Map<int, Loadable<List<Topic>>> _topics =
      <int, Loadable<List<Topic>>>{};
  final Map<int, Loadable<List<Formula>>> _formulas =
      <int, Loadable<List<Formula>>>{};

  Loadable<List<Unit>> get units => _units;
  Loadable<List<Topic>> topicsFor(int unitId) =>
      _topics[unitId] ?? const Loadable<List<Topic>>();
  Loadable<List<Formula>> formulasFor(int topicId) =>
      _formulas[topicId] ?? const Loadable<List<Formula>>();

  Future<void> loadUnits({bool force = false}) async {
    if (_units.isLoading || (_units.hasData && !force)) {
      return;
    }
    _units = Loadable<List<Unit>>(data: _units.data, isLoading: true);
    notifyListeners();
    _units = await _load(_api.getUnits, previous: _units.data);
    notifyListeners();
  }

  Future<void> loadTopics(int unitId, {bool force = false}) async {
    final Loadable<List<Topic>> current = topicsFor(unitId);
    if (current.isLoading || (current.hasData && !force)) {
      return;
    }
    _topics[unitId] = Loadable<List<Topic>>(
      data: current.data,
      isLoading: true,
    );
    notifyListeners();
    _topics[unitId] = await _load(
      () => _api.getUnitTopics(unitId),
      previous: current.data,
    );
    notifyListeners();
  }

  Future<void> loadFormulas(int topicId, {bool force = false}) async {
    final Loadable<List<Formula>> current = formulasFor(topicId);
    if (current.isLoading || (current.hasData && !force)) {
      return;
    }
    _formulas[topicId] = Loadable<List<Formula>>(
      data: current.data,
      isLoading: true,
    );
    notifyListeners();
    _formulas[topicId] = await _load(
      () => _api.getTopicFormulas(topicId),
      previous: current.data,
    );
    notifyListeners();
  }

  /// Forget everything (on logout).
  void clear() {
    _units = const Loadable<List<Unit>>();
    _topics.clear();
    _formulas.clear();
    notifyListeners();
  }

  static Future<Loadable<T>> _load<T>(
    Future<T> Function() fetch, {
    T? previous,
  }) async {
    try {
      return Loadable<T>(data: await fetch());
    } on ApiException catch (e) {
      return Loadable<T>(
        data: previous,
        error: e,
      ); // keep stale data on refresh errors
    }
  }
}
