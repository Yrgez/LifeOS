import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LifeOSApp());
}

class AppColors {
  static const green = Color(0xFF00E676);
  static const violet = Color(0xFF7C4DFF);
  static const gold = Color(0xFFFFD700);
  static const red = Color(0xFFFF3D71);
  static const amber = Color(0xFFFFB300);
  static const card = Color(0xFF14181F);
  static const panel = Color(0xFF0D1015);
  static const field = Color(0xFF1E242E);
}

class LifeOSApp extends StatelessWidget {
  const LifeOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Life OS Ultimate Engine',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF090B0E),
        cardColor: AppColors.card,
        primaryColor: AppColors.green,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.green,
          secondary: AppColors.violet,
          surface: AppColors.card,
        ),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// УТИЛИТЫ
// ---------------------------------------------------------------------------

double _clampD(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

/// Поддержка запятой как десятичного разделителя (русская клавиатура).
double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.').replaceAll(' ', ''));
int? _int(String s) => int.tryParse(s.trim().replaceAll(' ', ''));
double _round1(double v) => (v * 10).round() / 10;
String _trimNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

String _fmtMoney(int v) {
  final s = v.abs().toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('\u00A0');
    b.write(s[i]);
  }
  return '${v < 0 ? '-' : ''}$b';
}

const _monthNames = ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];
const _dayNames = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
String _monthYear(DateTime d) => '${_monthNames[d.month - 1]} ${d.year}';
String _dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Формула 1RM: Бжицки до 10 повторов, Эпли дальше (Бжицки при больших повторах неточна).
double _oneRM(double weight, int reps) {
  if (reps <= 1) return weight;
  if (reps <= 10) return weight * (36 / (37 - reps));
  return weight * (1 + reps / 30.0);
}

/// Корреляция Пирсона по выровненным хвостам рядов.
double? _pearson(List<double> a, List<double> b) {
  final n = min(a.length, b.length);
  if (n < 3) return null;
  final x = a.sublist(a.length - n);
  final y = b.sublist(b.length - n);
  final mx = x.reduce((p, c) => p + c) / n;
  final my = y.reduce((p, c) => p + c) / n;
  double sxy = 0, sxx = 0, syy = 0;
  for (int i = 0; i < n; i++) {
    sxy += (x[i] - mx) * (y[i] - my);
    sxx += (x[i] - mx) * (x[i] - mx);
    syy += (y[i] - my) * (y[i] - my);
  }
  if (sxx == 0 || syy == 0) return null;
  return sxy / sqrt(sxx * syy);
}

void _drawText(Canvas canvas, String text, Offset offset, TextStyle style, {double anchor = 0, TextAlign align = TextAlign.start}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textAlign: align,
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, Offset(offset.dx - tp.width * anchor, offset.dy));
  tp.dispose();
}

// ---------------------------------------------------------------------------
// 1. МОДЕЛИ ДАННЫХ
// ---------------------------------------------------------------------------

class MuscleGroup {
  static const Map<String, double> defaultRecoveryHours = {
    'delts': 48, 'chest': 60, 'abs': 36, 'biceps': 48, 'forearms': 36, 'quads': 72,
    'traps': 48, 'lats': 72, 'triceps': 48, 'glutes': 72, 'hamstrings': 72, 'calves': 36,
  };

  final String id;
  final String name;
  final double recoveryHours; // за сколько часов мышца восстанавливается полностью
  DateTime? lastTrainedAt;
  double maxWeight;
  List<String> lastSets;
  List<double> history1RM;

  MuscleGroup({
    required this.id,
    required this.name,
    required this.recoveryHours,
    required this.lastTrainedAt,
    required this.maxWeight,
    required this.lastSets,
    required this.history1RM,
  });

  /// Восстановление считается от времени последней тренировки (раньше было статичным числом).
  double get recovery {
    final t = lastTrainedAt;
    if (t == null) return 1.0;
    final hours = DateTime.now().difference(t).inMinutes / 60.0;
    return _clampD(0.15 + 0.85 * hours / recoveryHours, 0.15, 1.0);
  }

  String get lastTrained {
    final t = lastTrainedAt;
    if (t == null) return 'Не тренировалась';
    final h = DateTime.now().difference(t).inHours;
    if (h < 1) return 'Только что';
    if (h < 24) return '$hч назад';
    return '${h ~/ 24} дн. назад';
  }

  Color get color {
    final r = recovery;
    if (r >= 0.8) return AppColors.green;
    if (r >= 0.45) return AppColors.amber;
    return AppColors.red;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'recoveryHours': recoveryHours,
        'lastTrainedAtMs': lastTrainedAt?.millisecondsSinceEpoch,
        'maxWeight': maxWeight,
        'lastSets': lastSets,
        'history1RM': history1RM,
      };

  factory MuscleGroup.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final rh = (json['recoveryHours'] as num?)?.toDouble() ?? defaultRecoveryHours[id] ?? 48.0;
    DateTime? at;
    if (json['lastTrainedAtMs'] is int) {
      at = DateTime.fromMillisecondsSinceEpoch(json['lastTrainedAtMs'] as int);
    } else if (json['recovery'] is num) {
      // миграция со старого формата: восстанавливаем время тренировки из процента
      final r = (json['recovery'] as num).toDouble();
      final frac = _clampD((r - 0.15) / 0.85, 0, 1);
      at = DateTime.now().subtract(Duration(minutes: (frac * rh * 60).round()));
    }
    final maxW = (json['maxWeight'] as num).toDouble();
    var hist = (json['history1RM'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? <double>[];
    if (hist.isEmpty) hist = [maxW];
    return MuscleGroup(
      id: id,
      name: json['name'],
      recoveryHours: rh,
      lastTrainedAt: at,
      maxWeight: maxW,
      lastSets: List<String>.from(json['lastSets'] ?? []),
      history1RM: hist,
    );
  }
}

class GoalCheckpoint {
  String title;
  bool isCompleted;
  GoalCheckpoint({required this.title, this.isCompleted = false});

  Map<String, dynamic> toJson() => {'title': title, 'isCompleted': isCompleted};
  factory GoalCheckpoint.fromJson(Map<String, dynamic> json) => GoalCheckpoint(
        title: json['title'],
        isCompleted: json['isCompleted'] ?? false,
      );
}

class GlobalGoal {
  final String id;
  String title;
  String category;
  List<GoalCheckpoint> checkpoints;

  GlobalGoal({required this.id, required this.title, required this.category, required this.checkpoints});

  double get progress {
    if (checkpoints.isEmpty) return 0;
    return checkpoints.where((c) => c.isCompleted).length / checkpoints.length;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'checkpoints': checkpoints.map((c) => c.toJson()).toList(),
      };

  factory GlobalGoal.fromJson(Map<String, dynamic> json) => GlobalGoal(
        id: json['id'],
        title: json['title'],
        category: json['category'],
        checkpoints: (json['checkpoints'] as List).map((c) => GoalCheckpoint.fromJson(c)).toList(),
      );
}

class AchievementItem {
  final String id;
  final String title;
  final String date;
  final String category;
  final String iconKey;

  const AchievementItem({
    required this.id,
    required this.title,
    required this.date,
    required this.category,
    this.iconKey = 'star',
  });

  IconData get icon {
    switch (iconKey) {
      case 'savings':
        return Icons.savings;
      case 'fitness':
        return Icons.fitness_center;
      case 'career':
        return Icons.trending_up;
      case 'verified':
        return Icons.verified;
      default:
        return Icons.stars;
    }
  }

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'date': date, 'category': category, 'iconKey': iconKey};

  factory AchievementItem.fromJson(Map<String, dynamic> json) => AchievementItem(
        id: json['id'],
        title: json['title'],
        date: json['date'],
        category: json['category'],
        iconKey: json['iconKey'] ?? 'star',
      );
}

class SalaryStep {
  final String year;
  final String role;
  final int salary;

  const SalaryStep({required this.year, required this.role, required this.salary});

  Map<String, dynamic> toJson() => {'year': year, 'role': role, 'salary': salary};
  factory SalaryStep.fromJson(Map<String, dynamic> json) => SalaryStep(
        year: json['year'],
        role: json['role'],
        salary: json['salary'],
      );
}

class GraphNode {
  final String id;
  String label;
  String category;
  Offset position; // ДОЛИ холста (0..1), а не пиксели — граф не «вылезает» на других экранах
  Color color;

  GraphNode({required this.id, required this.label, required this.category, required this.position, required this.color});

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'category': category,
        'fx': position.dx,
        'fy': position.dy,
        'color': color.toARGB32(),
      };

  factory GraphNode.fromJson(Map<String, dynamic> j) {
    double fx, fy;
    if (j['fx'] is num) {
      fx = (j['fx'] as num).toDouble();
      fy = (j['fy'] as num).toDouble();
    } else {
      // миграция со старого формата (пиксели)
      fx = ((j['dx'] as num?)?.toDouble() ?? 180) / 360;
      fy = ((j['dy'] as num?)?.toDouble() ?? 240) / 480;
    }
    return GraphNode(
      id: j['id'],
      label: j['label'],
      category: j['category'] ?? 'mind',
      position: Offset(_clampD(fx, 0.06, 0.94), _clampD(fy, 0.06, 0.94)),
      color: Color(j['color'] as int? ?? 0xFF00E676),
    );
  }
}

class GraphEdge {
  final String fromId;
  final String toId;
  const GraphEdge(this.fromId, this.toId);

  Map<String, dynamic> toJson() => {'fromId': fromId, 'toId': toId};
  factory GraphEdge.fromJson(Map<String, dynamic> json) => GraphEdge(json['fromId'] ?? '', json['toId'] ?? '');
}

// ---------------------------------------------------------------------------
// 2. АНАТОМИЧЕСКАЯ ГЕОМЕТРИЯ (пути строятся один раз)
// ---------------------------------------------------------------------------

class AnatomicalGeometry {
  static const double baseWidth = 300.0;
  static const double baseHeight = 480.0;

  static final Map<String, Path> frontPaths = {
    'delts': Path()
      ..moveTo(106, 74)..quadraticBezierTo(78, 80, 72, 105)..quadraticBezierTo(76, 122, 94, 126)..quadraticBezierTo(106, 110, 106, 74)..close()
      ..moveTo(194, 74)..quadraticBezierTo(222, 80, 228, 105)..quadraticBezierTo(224, 122, 206, 126)..quadraticBezierTo(194, 110, 194, 74)..close(),
    'chest': Path()
      ..moveTo(147, 78)..lineTo(112, 76)..quadraticBezierTo(98, 90, 102, 120)..quadraticBezierTo(122, 134, 147, 130)..close()
      ..moveTo(153, 78)..lineTo(188, 76)..quadraticBezierTo(202, 90, 198, 120)..quadraticBezierTo(178, 134, 153, 130)..close(),
    'abs': Path()
      ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(132, 138, 16, 18), const Radius.circular(3)))
      ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(152, 138, 16, 18), const Radius.circular(3)))
      ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(132, 160, 16, 18), const Radius.circular(3)))
      ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(152, 160, 16, 18), const Radius.circular(3)))
      ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(133, 182, 15, 20), const Radius.circular(4)))
      ..addRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(152, 182, 15, 20), const Radius.circular(4))),
    'biceps': Path()
      ..moveTo(93, 128)..quadraticBezierTo(74, 142, 78, 172)..quadraticBezierTo(92, 178, 98, 155)..close()
      ..moveTo(207, 128)..quadraticBezierTo(226, 142, 222, 172)..quadraticBezierTo(208, 178, 202, 155)..close(),
    'forearms': Path()
      ..moveTo(76, 180)..quadraticBezierTo(62, 205, 68, 238)..lineTo(82, 238)..quadraticBezierTo(92, 210, 88, 180)..close()
      ..moveTo(224, 180)..quadraticBezierTo(238, 205, 232, 238)..lineTo(218, 238)..quadraticBezierTo(208, 210, 212, 180)..close(),
    'quads': Path()
      ..moveTo(116, 218)..quadraticBezierTo(98, 260, 110, 318)..quadraticBezierTo(124, 332, 132, 328)..quadraticBezierTo(145, 305, 144, 222)..close()
      ..moveTo(184, 218)..quadraticBezierTo(202, 260, 190, 318)..quadraticBezierTo(176, 332, 168, 328)..quadraticBezierTo(155, 305, 156, 222)..close(),
    'calves': Path()
      ..moveTo(114, 345)..quadraticBezierTo(106, 375, 114, 430)..lineTo(130, 430)..quadraticBezierTo(138, 385, 130, 345)..close()
      ..moveTo(186, 345)..quadraticBezierTo(194, 375, 186, 430)..lineTo(170, 430)..quadraticBezierTo(162, 385, 170, 345)..close(),
  };

  static final Map<String, Path> backPaths = {
    'traps': Path()..moveTo(150, 52)..lineTo(182, 74)..lineTo(158, 146)..lineTo(150, 160)..lineTo(142, 146)..lineTo(118, 74)..close(),
    'lats': Path()
      ..moveTo(114, 98)..lineTo(142, 122)..lineTo(136, 192)..quadraticBezierTo(120, 176, 110, 138)..close()
      ..moveTo(186, 98)..lineTo(158, 122)..lineTo(164, 192)..quadraticBezierTo(180, 176, 190, 138)..close(),
    'triceps': Path()
      ..moveTo(93, 118)..quadraticBezierTo(74, 130, 76, 168)..quadraticBezierTo(90, 170, 94, 145)..close()
      ..moveTo(207, 118)..quadraticBezierTo(226, 130, 224, 168)..quadraticBezierTo(210, 170, 206, 145)..close(),
    'glutes': Path()
      ..moveTo(148, 202)..lineTo(116, 204)..quadraticBezierTo(106, 235, 124, 256)..quadraticBezierTo(146, 260, 148, 225)..close()
      ..moveTo(152, 202)..lineTo(184, 204)..quadraticBezierTo(194, 235, 176, 256)..quadraticBezierTo(154, 260, 152, 225)..close(),
    'hamstrings': Path()
      ..moveTo(118, 262)..quadraticBezierTo(108, 290, 116, 328)..quadraticBezierTo(132, 332, 144, 328)..quadraticBezierTo(146, 285, 144, 262)..close()
      ..moveTo(182, 262)..quadraticBezierTo(192, 290, 184, 328)..quadraticBezierTo(168, 332, 156, 328)..quadraticBezierTo(154, 285, 156, 262)..close(),
    'calves': Path()
      ..moveTo(116, 342)..quadraticBezierTo(100, 370, 114, 415)..lineTo(134, 415)..quadraticBezierTo(144, 370, 132, 342)..close()
      ..moveTo(184, 342)..quadraticBezierTo(200, 370, 186, 415)..lineTo(166, 415)..quadraticBezierTo(156, 370, 168, 342)..close(),
  };

  static Map<String, Path> pathsFor(bool front) => front ? frontPaths : backPaths;
}

// ---------------------------------------------------------------------------
// 3. УНИВЕРСАЛЬНЫЙ ДИАЛОГ-ФОРМА (контроллеры живут и умирают внутри State —
//    без ошибки "used after being disposed" при закрытии диалога)
// ---------------------------------------------------------------------------

class FieldSpec {
  final String key;
  final String label;
  final String initial;
  final bool numeric;
  final int lines;
  final Map<String, String>? options; // если задано — выпадающий список (value -> подпись)
  const FieldSpec(this.key, this.label, {this.initial = '', this.numeric = false, this.lines = 1, this.options});
}

Future<Map<String, String>?> showFormDialog(
  BuildContext context, {
  required String title,
  required List<FieldSpec> fields,
  required String actionLabel,
  Color accent = AppColors.green,
  Color actionTextColor = Colors.black,
  bool Function(Map<String, String>)? validate,
}) {
  return showDialog<Map<String, String>>(
    context: context,
    builder: (_) => _FormDialog(
      title: title,
      fields: fields,
      actionLabel: actionLabel,
      accent: accent,
      actionTextColor: actionTextColor,
      validate: validate,
    ),
  );
}

class _FormDialog extends StatefulWidget {
  final String title;
  final List<FieldSpec> fields;
  final String actionLabel;
  final Color accent;
  final Color actionTextColor;
  final bool Function(Map<String, String>)? validate;

  const _FormDialog({
    required this.title,
    required this.fields,
    required this.actionLabel,
    required this.accent,
    required this.actionTextColor,
    this.validate,
  });

  @override
  State<_FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<_FormDialog> {
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, String> _choices = {};

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      if (f.options != null) {
        _choices[f.key] = f.options!.containsKey(f.initial) ? f.initial : f.options!.keys.first;
      } else {
        _ctrls[f.key] = TextEditingController(text: f.initial);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> _collect() => {
        for (final e in _ctrls.entries) e.key: e.value.text.trim(),
        ..._choices,
      };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(widget.title, style: const TextStyle(fontSize: 16)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in widget.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: f.options != null
                    ? LabeledDropdown(
                        label: f.label,
                        value: _choices[f.key]!,
                        items: f.options!,
                        onChanged: (v) => setState(() => _choices[f.key] = v),
                      )
                    : TextField(
                        controller: _ctrls[f.key],
                        keyboardType: f.numeric
                            ? const TextInputType.numberWithOptions(decimal: true)
                            : (f.lines > 1 ? TextInputType.multiline : TextInputType.text),
                        minLines: f.lines,
                        maxLines: f.lines,
                        decoration: InputDecoration(labelText: f.label),
                      ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: widget.accent),
          onPressed: () {
            final v = _collect();
            if (widget.validate?.call(v) ?? true) Navigator.pop(context, v);
          },
          child: Text(widget.actionLabel, style: TextStyle(color: widget.actionTextColor, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

/// Выпадающий список без устаревшего DropdownButtonFormField.value.
class LabeledDropdown extends StatelessWidget {
  final String label;
  final Color? labelColor;
  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  const LabeledDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        labelStyle: labelColor == null ? null : TextStyle(color: labelColor, fontSize: 11),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.containsKey(value) ? value : null,
          isExpanded: true,
          isDense: true,
          dropdownColor: AppColors.field,
          items: [
            for (final e in items.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. ОСНОВНОЙ КОНТРОЛЛЕР ПРИЛОЖЕНИЯ
// ---------------------------------------------------------------------------

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> with WidgetsBindingObserver {
  static const _userName = 'Александр';

  static const Map<String, String> _metricNames = {
    'steps': 'Шаги (7 дн)',
    'calories': 'Калории (7 дн)',
    'chest': 'Жим груди 1RM',
    'quads': 'Присед 1RM',
    'graph': 'Узлы Графа',
  };
  static const Map<String, String> _metricUnits = {
    'steps': 'шагов',
    'calories': 'ккал',
    'chest': 'кг',
    'quads': 'кг',
    'graph': 'узлов',
  };
  static const Set<String> _weeklyMetrics = {'steps', 'calories', 'graph'};

  int _currentIndex = 0;
  bool _showFront = true;
  String? _selectedMuscleId = 'chest';

  // Финансы
  int _netWorth = 2450000;
  int _monthlyIncome = 380000;
  int _monthlyExpense = 160000;

  // Здоровье (текущие значения дня и история за 7 дней, последняя точка = сегодня)
  int _dailySteps = 8420;
  int _activeCalories = 540;
  int _proteinGrams = 145;
  List<double> _stepsWeekHistory = [6800, 7400, 9200, 6100, 8900, 11400, 8420];
  List<double> _caloriesWeekHistory = [450, 490, 610, 380, 560, 710, 540];
  List<double> _graphEvolutionHistory = [3, 4, 6, 7, 8, 8, 9];

  String _compareMetricA = 'steps';
  String _compareMetricB = 'calories';

  late Map<String, MuscleGroup> _muscles = _getDefaultMuscles();
  late List<GlobalGoal> _goals = _getDefaultGoals();
  late List<AchievementItem> _achievements = _getDefaultAchievements();
  late List<SalaryStep> _salaryHistory = _getDefaultSalary();

  late List<GraphNode> _graphNodes = _getDefaultGraphNodes();
  late List<GraphEdge> _graphEdges = _getDefaultGraphEdges();
  String? _selectedNodeId;
  int? _dragIndex;
  String _activeCategoryFilter = 'all';

  // Хранилище
  SharedPreferences? _prefs;
  bool _loaded = false; // пока данные не прочитаны, ничего не пишем (иначе затрём сохранённое дефолтами)
  Timer? _saveTimer;
  Timer? _tickTimer;
  String _lastDay = _dayKey(DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // раз в минуту обновляем «восстановление» мышц
    _tickTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _loadFromStorage();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickTimer?.cancel();
    _saveTimer?.cancel();
    _saveNow();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!mounted) return;
      setState(() => _rollOverDays());
      _scheduleSave();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      _saveNow();
    }
  }

  // ---------------- данные по умолчанию ----------------

  MuscleGroup _m(String id, String name, int hoursAgo, double max, List<String> sets, List<double> hist) => MuscleGroup(
        id: id,
        name: name,
        recoveryHours: MuscleGroup.defaultRecoveryHours[id] ?? 48,
        lastTrainedAt: DateTime.now().subtract(Duration(hours: hoursAgo)),
        maxWeight: max,
        lastSets: sets,
        history1RM: hist,
      );

  Map<String, MuscleGroup> _getDefaultMuscles() => {
        'delts': _m('delts', 'Дельтовидные', 14, 36, ['14кг × 15', '16кг × 12'], [28, 30, 32, 34, 36]),
        'chest': _m('chest', 'Грудные мышцы', 48, 120, ['80кг × 12', '100кг × 6'], [95, 100, 107, 115, 120]),
        'abs': _m('abs', 'Пресс и Кор', 72, 25, ['Скручивания +15кг × 20'], [15, 18, 20, 22, 25]),
        'biceps': _m('biceps', 'Бицепс', 36, 45, ['35кг × 10', '40кг × 8'], [35, 37, 40, 42, 45]),
        'forearms': _m('forearms', 'Предплечья', 120, 40, ['Хват 40кг × 40с'], [30, 32, 35, 38, 40]),
        'quads': _m('quads', 'Квадрицепсы', 30, 150, ['100кг × 10', '120кг × 8'], [120, 130, 135, 142, 150]),
        'traps': _m('traps', 'Трапеции', 96, 110, ['Шраги 90кг × 12'], [90, 95, 100, 105, 110]),
        'lats': _m('lats', 'Широчайшие спины', 16, 135, ['Подтягивания +20кг × 6'], [110, 118, 125, 130, 135]),
        'triceps': _m('triceps', 'Трицепс', 72, 50, ['Французский жим 45кг × 8'], [38, 40, 44, 47, 50]),
        'glutes': _m('glutes', 'Ягодичные', 40, 160, ['Мостик 140кг × 10'], [130, 140, 145, 152, 160]),
        'hamstrings': _m('hamstrings', 'Бицепс бедра', 24, 140, ['Мертвая тяга 120кг × 8'], [115, 122, 128, 135, 140]),
        'calves': _m('calves', 'Икроножные', 80, 120, ['Подъемы 100кг × 15'], [95, 100, 108, 114, 120]),
      };

  List<GlobalGoal> _getDefaultGoals() => [
        GlobalGoal(
          id: 'g1',
          title: 'Карьерный левел-ап: доход 500 000 ₽ / мес',
          category: 'Карьера и Финансы',
          checkpoints: [
            GoalCheckpoint(title: 'Пройти аудит навыков и System Design', isCompleted: true),
            GoalCheckpoint(title: 'Грейд Lead / Head (ЗП 380 000 ₽)', isCompleted: true),
            GoalCheckpoint(title: 'Запустить 2-й поток дохода (консалтинг)'),
            GoalCheckpoint(title: 'Оффер на 500к+ с бонусами'),
          ],
        ),
        GlobalGoal(
          id: 'g2',
          title: 'Спорт: Жим 100 кг и Полумарафон',
          category: 'Спорт и Тело',
          checkpoints: [
            GoalCheckpoint(title: 'Жим 90 кг на 5 повторов', isCompleted: true),
            GoalCheckpoint(title: 'Пробежать 10 км без остановки', isCompleted: true),
            GoalCheckpoint(title: 'Жим 100 кг на 1 раз'),
            GoalCheckpoint(title: 'Финиш полумарафона (21.1 км)'),
          ],
        ),
      ];

  // ВАЖНО: список НЕ const — иначе insert()/remove() падали с UnsupportedError.
  List<AchievementItem> _getDefaultAchievements() => [
        const AchievementItem(id: 'a1', title: 'Подушка безопасности 1 000 000 ₽', date: 'Октябрь 2026', category: 'Финансы', iconKey: 'savings'),
        const AchievementItem(id: 'a2', title: 'Жим штанги лежа 95 кг', date: 'Сентябрь 2026', category: 'Сила', iconKey: 'fitness'),
        const AchievementItem(id: 'a3', title: 'Повышение до Lead Engineer', date: 'Август 2026', category: 'Карьера', iconKey: 'career'),
      ];

  List<SalaryStep> _getDefaultSalary() => [
        const SalaryStep(year: '2023', role: 'Junior', salary: 90000),
        const SalaryStep(year: '2024', role: 'Middle', salary: 180000),
        const SalaryStep(year: '2025', role: 'Senior', salary: 280000),
        const SalaryStep(year: '2026', role: 'Lead', salary: 380000),
      ];

  List<GraphNode> _getDefaultGraphNodes() => [
        GraphNode(id: 'n_goal_salary', label: 'Цель: 500к', category: 'mind', position: const Offset(0.22, 0.20), color: AppColors.violet),
        GraphNode(id: 'n_salary', label: 'ЗП: 380к', category: 'wealth', position: const Offset(0.53, 0.33), color: AppColors.green),
        GraphNode(id: 'n_capital', label: 'Капитал 2.45М', category: 'wealth', position: const Offset(0.78, 0.20), color: AppColors.gold),
        GraphNode(id: 'n_cushion', label: 'Подушка 1М', category: 'wealth', position: const Offset(0.84, 0.46), color: AppColors.gold),
        GraphNode(id: 'n_sleep', label: 'Сон / Отдых', category: 'health', position: const Offset(0.53, 0.56), color: Colors.cyanAccent),
        GraphNode(id: 'n_goal_bench', label: 'Цель: Жим 100', category: 'mind', position: const Offset(0.19, 0.75), color: AppColors.violet),
        GraphNode(id: 'n_chest', label: 'Грудь (1RM 120)', category: 'gym', position: const Offset(0.44, 0.86), color: AppColors.green),
        GraphNode(id: 'n_protein', label: 'Белок: 145г', category: 'health', position: const Offset(0.72, 0.74), color: Colors.cyanAccent),
        GraphNode(id: 'n_activity', label: 'Шаги: 8.4k', category: 'health', position: const Offset(0.84, 0.90), color: Colors.cyanAccent),
      ];

  List<GraphEdge> _getDefaultGraphEdges() => const [
        GraphEdge('n_goal_salary', 'n_salary'),
        GraphEdge('n_salary', 'n_capital'),
        GraphEdge('n_capital', 'n_cushion'),
        GraphEdge('n_goal_bench', 'n_chest'),
        GraphEdge('n_chest', 'n_protein'),
        GraphEdge('n_protein', 'n_activity'),
        GraphEdge('n_sleep', 'n_chest'),
        GraphEdge('n_sleep', 'n_salary'),
      ];

  // ---------------- хранилище ----------------

  Future<void> _loadFromStorage() async {
    try {
      _prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 3));
    } catch (_) {
      return; // хранилище недоступно — работаем на дефолтах, но ничего не перезаписываем
    }
    final p = _prefs!;

    // Каждый блок декодируется отдельно: битый JSON одного блока не ломает остальные.
    T? decode<T>(String key, T Function(dynamic) parse) {
      final raw = p.getString(key);
      if (raw == null) return null;
      try {
        return parse(jsonDecode(raw));
      } catch (_) {
        return null;
      }
    }

    final muscles = decode<Map<String, MuscleGroup>>(
        'life_os_muscles', (j) => (j as Map<String, dynamic>).map((k, v) => MapEntry(k, MuscleGroup.fromJson(v))));
    final goals = decode<List<GlobalGoal>>('life_os_goals', (j) => (j as List).map((g) => GlobalGoal.fromJson(g)).toList());
    final ach = decode<List<AchievementItem>>('life_os_achievements', (j) => (j as List).map((a) => AchievementItem.fromJson(a)).toList());
    final sal = decode<List<SalaryStep>>('life_os_salary', (j) => (j as List).map((s) => SalaryStep.fromJson(s)).toList());
    List<GraphNode> parseNodes(dynamic j) => (j as List).map((n) => GraphNode.fromJson(n)).toList();
    final nodes = decode<List<GraphNode>>('life_os_nodes_v3', parseNodes) ?? decode<List<GraphNode>>('life_os_nodes_v2', parseNodes);
    final edges = decode<List<GraphEdge>>('life_os_edges_v2', (j) => (j as List).map((e) => GraphEdge.fromJson(e)).toList());
    List<double> parseD(dynamic j) => (j as List).map((e) => (e as num).toDouble()).toList();
    final steps = decode<List<double>>('life_os_steps_hist', parseD);
    final cals = decode<List<double>>('life_os_cals_hist', parseD);
    final graphHist = decode<List<double>>('life_os_graph_hist', parseD);

    if (!mounted) return;
    setState(() {
      _netWorth = p.getInt('life_os_net_worth') ?? _netWorth;
      _monthlyIncome = p.getInt('life_os_income') ?? _monthlyIncome;
      _monthlyExpense = p.getInt('life_os_expense') ?? _monthlyExpense;
      _dailySteps = p.getInt('life_os_steps') ?? _dailySteps;
      _activeCalories = p.getInt('life_os_cals') ?? _activeCalories;
      _proteinGrams = p.getInt('life_os_prot') ?? _proteinGrams;
      _lastDay = p.getString('life_os_day') ?? _lastDay;

      _muscles = muscles ?? _muscles;
      _goals = goals ?? _goals;
      _achievements = ach ?? _achievements;
      _salaryHistory = sal ?? _salaryHistory;
      _graphNodes = nodes ?? _graphNodes;
      _graphEdges = edges ?? _graphEdges;
      if (steps != null) _stepsWeekHistory = _fit7(steps);
      if (cals != null) _caloriesWeekHistory = _fit7(cals);
      if (graphHist != null) _graphEvolutionHistory = _fit7(graphHist);

      _rollOverDays();
      _syncDerived();
    });
    _loaded = true;
    _scheduleSave();
  }

  List<double> _fit7(List<double> l) {
    final r = List<double>.from(l);
    while (r.length < 7) {
      r.insert(0, r.isEmpty ? 0 : r.first);
    }
    return r.length > 7 ? r.sublist(r.length - 7) : r;
  }

  void _push7(List<double> l, double v) {
    l.add(v);
    while (l.length > 7) {
      l.removeAt(0);
    }
  }

  /// Если наступил новый день — сдвигаем недельные истории и обнуляем дневные счётчики.
  /// Вызывать внутри setState.
  void _rollOverDays() {
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    DateTime last;
    try {
      final p = _lastDay.split('-').map(int.parse).toList();
      last = DateTime.utc(p[0], p[1], p[2]);
    } catch (_) {
      _lastDay = _dayKey(now);
      return;
    }
    final diff = today.difference(last).inDays;
    if (diff <= 0) return;
    for (int i = 0; i < min(diff, 7); i++) {
      _push7(_stepsWeekHistory, 0);
      _push7(_caloriesWeekHistory, 0);
      _push7(_graphEvolutionHistory, _graphNodes.length.toDouble());
    }
    _dailySteps = 0;
    _activeCalories = 0;
    _proteinGrams = 0;
    _lastDay = _dayKey(now);
  }

  /// Производные данные: подписи «системных» узлов графа всегда отражают реальные цифры.
  void _syncDerived() {
    void set(String id, String label) {
      for (final n in _graphNodes) {
        if (n.id == id) n.label = label;
      }
    }

    set('n_salary', 'ЗП: ${_monthlyIncome ~/ 1000}к');
    set('n_capital', 'Капитал ${(_netWorth / 1000000).toStringAsFixed(2)}М');
    set('n_protein', 'Белок: $_proteinGrams г');
    set('n_activity', 'Шаги: ${(_dailySteps / 1000).toStringAsFixed(1)}k');
    final chest = _muscles['chest'];
    if (chest != null) set('n_chest', 'Грудь (1RM ${chest.maxWeight.toInt()})');

    if (_graphEvolutionHistory.isNotEmpty) {
      _graphEvolutionHistory[_graphEvolutionHistory.length - 1] = _graphNodes.length.toDouble();
    }
    if (_stepsWeekHistory.isNotEmpty) _stepsWeekHistory[_stepsWeekHistory.length - 1] = _dailySteps.toDouble();
    if (_caloriesWeekHistory.isNotEmpty) _caloriesWeekHistory[_caloriesWeekHistory.length - 1] = _activeCalories.toDouble();
  }

  /// Единая точка мутации состояния: setState + пересчёт производных + отложенное сохранение.
  void _commit(VoidCallback fn) {
    setState(() {
      fn();
      _syncDerived();
    });
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _saveNow); // дебаунс вместо записи всего на каждый чих
  }

  Future<void> _saveNow() async {
    final p = _prefs;
    if (p == null || !_loaded) return;
    _saveTimer?.cancel();
    try {
      await Future.wait([
        p.setInt('life_os_net_worth', _netWorth),
        p.setInt('life_os_income', _monthlyIncome),
        p.setInt('life_os_expense', _monthlyExpense),
        p.setInt('life_os_steps', _dailySteps),
        p.setInt('life_os_cals', _activeCalories),
        p.setInt('life_os_prot', _proteinGrams),
        p.setString('life_os_day', _lastDay),
        p.setString('life_os_muscles', jsonEncode(_muscles.map((k, v) => MapEntry(k, v.toJson())))),
        p.setString('life_os_goals', jsonEncode(_goals.map((g) => g.toJson()).toList())),
        p.setString('life_os_achievements', jsonEncode(_achievements.map((a) => a.toJson()).toList())),
        p.setString('life_os_salary', jsonEncode(_salaryHistory.map((s) => s.toJson()).toList())),
        p.setString('life_os_nodes_v3', jsonEncode(_graphNodes.map((n) => n.toJson()).toList())),
        p.setString('life_os_edges_v2', jsonEncode(_graphEdges.map((e) => e.toJson()).toList())),
        p.setString('life_os_steps_hist', jsonEncode(_stepsWeekHistory)),
        p.setString('life_os_cals_hist', jsonEncode(_caloriesWeekHistory)),
        p.setString('life_os_graph_hist', jsonEncode(_graphEvolutionHistory)),
      ]);
    } catch (_) {}
  }

  // ---------------- вычисляемые ----------------

  int get systemReadiness {
    if (_muscles.isEmpty) return 0;
    final total = _muscles.values.fold(0.0, (acc, m) => acc + m.recovery);
    return ((total / _muscles.length) * 100).round();
  }

  /// Подписи последних 7 дней, заканчивая сегодняшним.
  List<String> get _weekLabels {
    final now = DateTime.now();
    return List.generate(7, (i) => _dayNames[now.subtract(Duration(days: 6 - i)).weekday - 1]);
  }

  GraphNode? _nodeById(String? id) {
    if (id == null) return null;
    for (final n in _graphNodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  List<double> _getMetricSeries(String key) {
    switch (key) {
      case 'calories':
        return _caloriesWeekHistory;
      case 'chest':
        return _muscles['chest']?.history1RM ?? const [90, 100, 110, 115, 120];
      case 'quads':
        return _muscles['quads']?.history1RM ?? const [110, 125, 135, 145, 150];
      case 'graph':
        return _graphEvolutionHistory;
      default:
        return _stepsWeekHistory;
    }
  }

  // ---------------- диалоги и мутации ----------------

  Future<void> _logWorkoutForMuscle(MuscleGroup muscle) async {
    final r = await showFormDialog(
      context,
      title: 'Записать подход: ${muscle.name}',
      actionLabel: 'Сохранить',
      fields: const [
        FieldSpec('w', 'Вес снаряда (кг)', numeric: true),
        FieldSpec('r', 'Количество повторений', numeric: true),
      ],
      validate: (v) => (_num(v['w']!) ?? 0) > 0 && (_int(v['r']!) ?? 0) > 0,
    );
    if (r == null || !mounted) return;
    final w = _num(r['w']!)!;
    final reps = _int(r['r']!)!;

    _commit(() {
      final e = _round1(_oneRM(w, reps));
      final now = DateTime.now();
      if (e > muscle.maxWeight) muscle.maxWeight = e;

      // В один день — одна точка истории (лучший результат), а не по точке на каждый подход.
      final sameDay = muscle.lastTrainedAt != null && DateUtils.isSameDay(muscle.lastTrainedAt, now);
      if (sameDay && muscle.history1RM.isNotEmpty) {
        muscle.history1RM[muscle.history1RM.length - 1] = max(muscle.history1RM.last, e);
      } else {
        muscle.history1RM.add(e);
      }
      while (muscle.history1RM.length > 8) {
        muscle.history1RM.removeAt(0);
      }

      muscle.lastSets.insert(0, '${_trimNum(w)}кг × $reps');
      if (muscle.lastSets.length > 6) muscle.lastSets.removeLast();
      muscle.lastTrainedAt = now;
    });
  }

  Future<void> _editHealthMetricsDialog() async {
    final r = await showFormDialog(
      context,
      title: 'Сводка активности дня',
      actionLabel: 'Обновить',
      fields: [
        FieldSpec('s', 'Шаги', initial: '$_dailySteps', numeric: true),
        FieldSpec('c', 'Активные калории (ккал)', initial: '$_activeCalories', numeric: true),
        FieldSpec('p', 'Белок (г)', initial: '$_proteinGrams', numeric: true),
      ],
    );
    if (r == null || !mounted) return;
    _commit(() {
      _dailySteps = max(0, _int(r['s']!) ?? _dailySteps);
      _activeCalories = max(0, _int(r['c']!) ?? _activeCalories);
      _proteinGrams = max(0, _int(r['p']!) ?? _proteinGrams);
    });
  }

  Future<void> _addGraphNodeDialog() async {
    final r = await showFormDialog(
      context,
      title: 'Создать узел графа',
      actionLabel: 'Создать',
      accent: AppColors.violet,
      fields: const [
        FieldSpec('title', 'Название узла'),
        FieldSpec('cat', 'Сфера жизни', initial: 'mind', options: {
          'mind': 'Смыслы / Цели',
          'wealth': 'Капитал / Финансы',
          'gym': 'Тело / Тренировки',
          'health': 'Здоровье / Отдых',
        }),
      ],
      validate: (v) => v['title']!.isNotEmpty,
    );
    if (r == null || !mounted) return;
    const colors = {
      'mind': AppColors.violet,
      'wealth': AppColors.gold,
      'gym': AppColors.green,
      'health': Colors.cyanAccent,
    };
    final rnd = Random();
    _commit(() {
      _graphNodes.add(GraphNode(
        id: 'node_${DateTime.now().microsecondsSinceEpoch}',
        label: r['title']!,
        category: r['cat']!,
        // небольшой разброс, чтобы новые узлы не слипались в одну точку
        position: Offset(0.5 + (rnd.nextDouble() - 0.5) * 0.3, 0.5 + (rnd.nextDouble() - 0.5) * 0.3),
        color: colors[r['cat']] ?? AppColors.violet,
      ));
    });
  }

  Future<void> _addGraphEdgeDialog([String? initialFromId]) async {
    if (_graphNodes.length < 2) return;
    final from = _nodeById(initialFromId)?.id ?? _graphNodes.first.id;
    final to = _graphNodes.firstWhere((n) => n.id != from).id;
    final options = {for (final n in _graphNodes) n.id: n.label};

    final r = await showFormDialog(
      context,
      title: 'Связать узлы графа',
      actionLabel: 'Соединить',
      accent: Colors.cyanAccent,
      fields: [
        FieldSpec('from', 'Откуда', initial: from, options: options),
        FieldSpec('to', 'Куда', initial: to, options: options),
      ],
      validate: (v) => v['from'] != v['to'],
    );
    if (r == null || !mounted) return;
    final a = r['from']!, b = r['to']!;
    final exists = _graphEdges.any((e) => (e.fromId == a && e.toId == b) || (e.fromId == b && e.toId == a));
    if (!exists) _commit(() => _graphEdges.add(GraphEdge(a, b)));
  }

  void _deleteGraphNode(String nodeId) {
    _commit(() {
      _graphNodes.removeWhere((n) => n.id == nodeId);
      _graphEdges.removeWhere((e) => e.fromId == nodeId || e.toId == nodeId);
      if (_selectedNodeId == nodeId) _selectedNodeId = null;
    });
  }

  void _autoLayoutRadial() {
    if (_graphNodes.isEmpty) return;
    _commit(() {
      for (int i = 0; i < _graphNodes.length; i++) {
        final angle = (2 * pi * i) / _graphNodes.length - pi / 2;
        _graphNodes[i].position = Offset(0.5 + cos(angle) * 0.36, 0.5 + sin(angle) * 0.36);
      }
    });
  }

  Future<void> _addNewAchievementDialog() async {
    final r = await showFormDialog(
      context,
      title: 'Зафиксировать достижение',
      actionLabel: 'Сохранить',
      fields: const [
        FieldSpec('t', 'Что было достигнуто?'),
        FieldSpec('c', 'Категория', initial: 'Личный рекорд'),
      ],
      validate: (v) => v['t']!.isNotEmpty,
    );
    if (r == null || !mounted) return;
    _commit(() {
      _achievements.insert(
        0,
        AchievementItem(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          title: r['t']!,
          date: _monthYear(DateTime.now()),
          category: r['c']!.isEmpty ? 'Личный рекорд' : r['c']!,
        ),
      );
    });
  }

  Future<void> _addNewGoalDialog() async {
    final r = await showFormDialog(
      context,
      title: 'Новая глобальная цель (OKR)',
      actionLabel: 'Создать',
      accent: AppColors.violet,
      actionTextColor: Colors.white,
      fields: const [
        FieldSpec('t', 'Формулировка цели'),
        FieldSpec('c', 'Категория', initial: 'Стратегия'),
        FieldSpec('cp', 'Чекпоинты (каждый с новой строки)', lines: 4),
      ],
      validate: (v) => v['t']!.isNotEmpty,
    );
    if (r == null || !mounted) return;
    final cps = r['cp']!
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((s) => GoalCheckpoint(title: s))
        .toList();
    _commit(() {
      _goals.add(GlobalGoal(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: r['t']!,
        category: r['c']!.isEmpty ? 'Стратегия' : r['c']!,
        checkpoints: cps,
      ));
    });
  }

  Future<void> _editWealthDialog() async {
    final r = await showFormDialog(
      context,
      title: 'Параметры капитала',
      actionLabel: 'Сохранить',
      accent: AppColors.gold,
      fields: [
        FieldSpec('w', 'Чистый капитал (₽)', initial: '$_netWorth', numeric: true),
        FieldSpec('i', 'Доход в месяц (₽)', initial: '$_monthlyIncome', numeric: true),
        FieldSpec('e', 'Расходы в месяц (₽)', initial: '$_monthlyExpense', numeric: true),
      ],
    );
    if (r == null || !mounted) return;
    _commit(() {
      _netWorth = _int(r['w']!) ?? _netWorth;
      _monthlyIncome = max(0, _int(r['i']!) ?? _monthlyIncome);
      _monthlyExpense = max(0, _int(r['e']!) ?? _monthlyExpense);
    });
  }

  Future<void> _addSalaryStepDialog() async {
    final r = await showFormDialog(
      context,
      title: 'Новая точка на графике ЗП',
      actionLabel: 'Добавить',
      fields: const [
        FieldSpec('y', 'Год / Период'),
        FieldSpec('r', 'Должность'),
        FieldSpec('s', 'Зарплата (₽)', numeric: true),
      ],
      validate: (v) => v['y']!.isNotEmpty && (_int(v['s']!) ?? 0) > 0,
    );
    if (r == null || !mounted) return;
    _commit(() => _salaryHistory.add(SalaryStep(year: r['y']!, role: r['r']!, salary: _int(r['s']!)!)));
  }

  void _toggleCheckpoint(GlobalGoal goal, GoalCheckpoint cp, bool? val) {
    _commit(() {
      cp.isCompleted = val ?? false;
      final achId = 'goal_done_${goal.id}';
      // достижение создаётся один раз, а не при каждом переключении чекбокса
      if (goal.checkpoints.isNotEmpty && goal.progress == 1.0 && !_achievements.any((a) => a.id == achId)) {
        _achievements.insert(
          0,
          AchievementItem(
            id: achId,
            title: 'Достигнута цель: ${goal.title}',
            date: _monthYear(DateTime.now()),
            category: goal.category,
            iconKey: 'verified',
          ),
        );
      }
    });
  }

  // -------------------------------------------------------------------------
  // РЕНДЕР
  // -------------------------------------------------------------------------

  Widget _screen() {
    switch (_currentIndex) {
      case 0:
        return _buildHubScreen();
      case 1:
        return _buildGymScreen();
      case 2:
        return _buildGraphScreen();
      case 3:
        return _buildMindScreen();
      default:
        return _buildWealthScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // строится только активный экран (раньше строились все пять на каждый setState)
      body: SafeArea(child: _screen()),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white10, width: 1))),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: AppColors.panel,
          selectedItemColor: AppColors.green,
          unselectedItemColor: Colors.white38,
          type: BottomNavigationBarType.fixed,
          selectedFontSize: 11,
          unselectedFontSize: 10,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'HUB'),
            BottomNavigationBarItem(icon: Icon(Icons.accessibility_new), label: 'ТЕЛО'),
            BottomNavigationBarItem(icon: Icon(Icons.hub_outlined), activeIcon: Icon(Icons.hub), label: 'ГРАФ'),
            BottomNavigationBarItem(icon: Icon(Icons.track_changes_outlined), activeIcon: Icon(Icons.track_changes), label: 'СМЫСЛЫ'),
            BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_outlined), activeIcon: Icon(Icons.account_balance_wallet), label: 'КАПИТАЛ'),
          ],
        ),
      ),
    );
  }

  // 1. HUB
  Widget _buildHubScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('EXECUTIVE DASHBOARD', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  SizedBox(height: 4),
                  Text(_userName, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.favorite, color: AppColors.green, size: 14),
                    const SizedBox(width: 6),
                    Text('Готовность тела: $systemReadiness%', style: const TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildHealthCard(),
          const SizedBox(height: 16),
          _buildComparisonSection(),
          const SizedBox(height: 16),
          _buildVectorBodyCard(),
        ],
      ),
    );
  }

  Widget _buildComparisonSection() {
    // Ряды разной длины выравниваем по ХВОСТУ (последние n значений) — раньше брались первые n,
    // и точки не соответствовали друг другу по времени.
    final rawA = _getMetricSeries(_compareMetricA);
    final rawB = _getMetricSeries(_compareMetricB);
    final n = min(rawA.length, rawB.length);
    final seriesA = rawA.sublist(rawA.length - n);
    final seriesB = rawB.sublist(rawB.length - n);

    final bothWeekly = _weeklyMetrics.contains(_compareMetricA) && _weeklyMetrics.contains(_compareMetricB);
    final allDays = _weekLabels;
    final labels = bothWeekly ? allDays.sublist(allDays.length - n) : List.generate(n, (i) => '${i + 1}');

    final r = _pearson(seriesA, seriesB);
    String corrText;
    if (r == null) {
      corrText = 'Недостаточно данных для корреляции';
    } else {
      final abs = r.abs();
      final strength = abs >= 0.7 ? 'сильная' : (abs >= 0.4 ? 'умеренная' : 'слабая');
      final dir = abs < 0.2 ? '' : (r > 0 ? ' положительная' : ' отрицательная');
      corrText = 'Корреляция Пирсона: r = ${r.toStringAsFixed(2)} ($strength$dir, n = $n)';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.compare_arrows, color: Colors.cyanAccent, size: 18),
                  SizedBox(width: 8),
                  Text('СРАВНЕНИЕ И КОРРЕЛЯЦИЯ', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.cyanAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: const Text('2 Метрики', style: TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: LabeledDropdown(
                  label: 'Метрика A (Зеленый)',
                  labelColor: AppColors.green,
                  value: _compareMetricA,
                  items: _metricNames,
                  onChanged: (v) => setState(() => _compareMetricA = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LabeledDropdown(
                  label: 'Метрика B (Бирюзовый)',
                  labelColor: Colors.cyanAccent,
                  value: _compareMetricB,
                  items: _metricNames,
                  onChanged: (v) => setState(() => _compareMetricB = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 170,
            width: double.infinity,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: DualLineComparisonPainter(
                  dataA: seriesA,
                  dataB: seriesB,
                  labels: labels,
                  colorA: AppColors.green,
                  colorB: Colors.cyanAccent,
                  unitA: _metricUnits[_compareMetricA] ?? '',
                  unitB: _metricUnits[_compareMetricB] ?? '',
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(corrText, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          const Text('Кривые нормализованы по шкале 0–100% для выявления взаимной корреляции.', style: TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      ),
    );
  }

  // 2. ТЕЛО
  Widget _buildGymScreen() {
    final paths = AnatomicalGeometry.pathsFor(_showFront);
    // порядок — как на силуэте; «икры» теперь есть и в списке заднего вида
    final visible = [for (final k in paths.keys) if (_muscles[k] != null) _muscles[k]!];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('АНАТОМИЧЕСКАЯ КАРТА ТЕЛА', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Container(
                decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  children: [
                    _toggleBtn('Спереди', _showFront, () => setState(() {
                          _showFront = true;
                          _selectedMuscleId = 'chest';
                        })),
                    _toggleBtn('Сзади', !_showFront, () => setState(() {
                          _showFront = false;
                          _selectedMuscleId = 'lats';
                        })),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildVectorBodyCard(),
          const SizedBox(height: 16),
          const Text('СПИСОК МЫШЕЧНЫХ ГРУПП:', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          for (final muscle in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: _selectedMuscleId == muscle.id ? const Color(0xFF1C2330) : AppColors.card,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: _selectedMuscleId == muscle.id ? AppColors.green : Colors.transparent, width: 1.2),
                ),
                child: ListTile(
                  onTap: () => setState(() => _selectedMuscleId = muscle.id),
                  leading: CircleAvatar(
                    backgroundColor: muscle.color.withValues(alpha: 0.2),
                    radius: 14,
                    child: CircleAvatar(backgroundColor: muscle.color, radius: 5),
                  ),
                  title: Text(muscle.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text('1RM: ${muscle.maxWeight.toInt()} кг • ${muscle.lastTrained}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF202630), elevation: 0),
                    onPressed: () => _logWorkoutForMuscle(muscle),
                    child: const Text('+ Подход', style: TextStyle(fontSize: 12, color: AppColors.green)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 3. ГРАФ
  int _hitNode(Offset pos, Size size) {
    int best = -1;
    double bestDist = 36;
    for (int i = 0; i < _graphNodes.length; i++) {
      final p = Offset(_graphNodes[i].position.dx * size.width, _graphNodes[i].position.dy * size.height);
      final d = (p - pos).distance;
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  Widget _buildGraphScreen() {
    final activeNode = _nodeById(_selectedNodeId);
    final connectedNodes = <String>[];
    if (activeNode != null) {
      for (final e in _graphEdges) {
        if (e.fromId != activeNode.id && e.toId != activeNode.id) continue;
        final other = _nodeById(e.fromId == activeNode.id ? e.toId : e.fromId);
        if (other != null) connectedNodes.add(other.label);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SECOND BRAIN GRAPH', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Интерактивная сеть связей', style: TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: AppColors.violet, size: 24),
                    tooltip: 'Добавить узел',
                    onPressed: _addGraphNodeDialog,
                  ),
                  IconButton(
                    icon: const Icon(Icons.alt_route, color: Colors.cyanAccent, size: 24),
                    tooltip: 'Связать узлы',
                    onPressed: () => _addGraphEdgeDialog(_selectedNodeId),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('ИСТОРИЯ РОСТА ЗНАНИЙ (УЗЛЫ)', style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold)),
                  Text('${_graphNodes.length} узлов • ${_graphEdges.length} связей', style: const TextStyle(color: AppColors.violet, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 50,
                width: double.infinity,
                child: CustomPaint(painter: MiniSparklinePainter(data: _graphEvolutionHistory, color: AppColors.violet)),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              _graphFilterPill('all', 'Все'),
              _graphFilterPill('mind', 'Смыслы'),
              _graphFilterPill('wealth', 'Капитал'),
              _graphFilterPill('health', 'Здоровье'),
              _graphFilterPill('gym', 'Тело'),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.panel, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white12)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LayoutBuilder(
                builder: (ctx, c) {
                  final size = Size(c.maxWidth, c.maxHeight);
                  // GestureDetector теперь внутри рамки: координаты касания совпадают с координатами рисования
                  return Stack(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) {
                          final i = _hitNode(d.localPosition, size);
                          setState(() => _selectedNodeId = i >= 0 ? _graphNodes[i].id : null);
                        },
                        onPanStart: (d) {
                          final i = _hitNode(d.localPosition, size);
                          if (i >= 0) {
                            _dragIndex = i;
                            setState(() => _selectedNodeId = _graphNodes[i].id);
                          }
                        },
                        onPanUpdate: (d) {
                          final i = _dragIndex;
                          if (i == null || i >= _graphNodes.length) return;
                          final cur = _graphNodes[i].position;
                          setState(() {
                            _graphNodes[i].position = Offset(
                              _clampD(cur.dx + d.delta.dx / size.width, 0.05, 0.95),
                              _clampD(cur.dy + d.delta.dy / size.height, 0.05, 0.95),
                            );
                          });
                        },
                        onPanEnd: (_) {
                          _dragIndex = null;
                          _scheduleSave();
                        },
                        child: RepaintBoundary(
                          child: CustomPaint(
                            size: size,
                            painter: LifeGraphPainter(
                              nodes: _graphNodes,
                              edges: _graphEdges,
                              selectedNodeId: _selectedNodeId,
                              activeCategoryFilter: _activeCategoryFilter,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: FloatingActionButton.small(
                          heroTag: 'auto_layout',
                          backgroundColor: AppColors.field,
                          tooltip: 'Организовать по кругу',
                          onPressed: _autoLayoutRadial,
                          child: const Icon(Icons.refresh, color: Colors.cyanAccent, size: 20),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        if (activeNode != null)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: activeNode.color.withValues(alpha: 0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          CircleAvatar(radius: 5, backgroundColor: activeNode.color),
                          const SizedBox(width: 8),
                          Expanded(child: Text(activeNode.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                      onPressed: () => setState(() => _selectedNodeId = null),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  connectedNodes.isEmpty ? 'Связей нет' : 'Связан с: ${connectedNodes.join(', ')}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.cyanAccent,
                          side: const BorderSide(color: Colors.cyanAccent),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        onPressed: () => _addGraphEdgeDialog(activeNode.id),
                        icon: const Icon(Icons.link, size: 16),
                        label: const Text('Связать с...', style: TextStyle(fontSize: 11)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.red, size: 20),
                      tooltip: 'Удалить узел',
                      onPressed: () => _deleteGraphNode(activeNode.id),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _graphFilterPill(String catKey, String label) {
    final active = _activeCategoryFilter == catKey;
    return GestureDetector(
      onTap: () => setState(() => _activeCategoryFilter = catKey),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.cyanAccent.withValues(alpha: 0.2) : AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? Colors.cyanAccent : Colors.white12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.cyanAccent : Colors.white60,
            fontSize: 11,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  // Силуэт + мини-график 1RM выбранной мышцы
  Widget _buildVectorBodyCard() {
    final activeMuscle = _muscles[_selectedMuscleId];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.biotech, color: AppColors.green, size: 16),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _showFront ? 'ПРОЕКЦИЯ: ANTERIOR (ФАС)' : 'ПРОЕКЦИЯ: POSTERIOR (ТЫЛ)',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => setState(() {
                  _showFront = !_showFront;
                  _selectedMuscleId = _showFront ? 'chest' : 'lats';
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      const Icon(Icons.flip_camera_android, size: 12, color: AppColors.green),
                      const SizedBox(width: 4),
                      Text(_showFront ? 'Повернуть спиной' : 'Повернуть лицом', style: const TextStyle(color: Colors.white70, fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 380,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final size = Size(constraints.maxWidth, 380);
                return GestureDetector(
                  onTapUp: (d) => _handleAnatomicalTap(d.localPosition, size),
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: size,
                      painter: AnatomicalSilhouettePainter(muscles: _muscles, isFront: _showFront, selectedMuscleId: _selectedMuscleId),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          if (activeMuscle != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: activeMuscle.color.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(radius: 5, backgroundColor: activeMuscle.color),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(activeMuscle.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text(
                              'Готовность: ${(activeMuscle.recovery * 100).round()}% • 1RM: ${activeMuscle.maxWeight.toInt()} кг',
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.green,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          minimumSize: Size.zero,
                        ),
                        onPressed: () => _logWorkoutForMuscle(activeMuscle),
                        child: const Text('Записать подход', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white10, height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('ИСТОРИЯ 1RM (ПРОГРЕСС СИЛЫ):', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                      // раньше показывался последний подход как «рекорд»; теперь — настоящий максимум
                      Text('${activeMuscle.history1RM.reduce(max).toInt()} кг рекорд', style: const TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 42,
                    width: double.infinity,
                    child: CustomPaint(painter: MiniSparklinePainter(data: activeMuscle.history1RM, color: activeMuscle.color)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _handleAnatomicalTap(Offset localPos, Size size) {
    final scale = min(size.width / AnatomicalGeometry.baseWidth, size.height / AnatomicalGeometry.baseHeight);
    final dx = (size.width - AnatomicalGeometry.baseWidth * scale) / 2;
    final dy = (size.height - AnatomicalGeometry.baseHeight * scale) / 2;
    final touch = Offset((localPos.dx - dx) / scale, (localPos.dy - dy) / scale);

    for (final entry in AnatomicalGeometry.pathsFor(_showFront).entries) {
      if (entry.value.contains(touch)) {
        setState(() => _selectedMuscleId = entry.key);
        return;
      }
    }
  }

  Widget _buildHealthCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('HEALTH & ACTIVITY (7 ДНЕЙ)', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.sync, color: AppColors.green, size: 18),
                onPressed: _editHealthMetricsDialog,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _MetricCol('Шаги', _fmtMoney(_dailySteps), 'Цель: 10k', Colors.cyanAccent),
              _MetricCol('Активность', '$_activeCalories ккал', 'Калории', Colors.orangeAccent),
              _MetricCol('Белок', '$_proteinGramsг', 'Норма: 140г', Colors.greenAccent),
            ],
          ),
          const SizedBox(height: 14),
          const Text('ДИНАМИКА ШАГОВ ЗА НЕДЕЛЮ:', style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          SizedBox(
            height: 48,
            width: double.infinity,
            child: CustomPaint(painter: MiniSparklinePainter(data: _stepsWeekHistory, color: Colors.cyanAccent)),
          ),
        ],
      ),
    );
  }

  // 4. СМЫСЛЫ
  Widget _buildMindScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('СТРАТЕГИЧЕСКИЕ ЦЕЛИ', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton(onPressed: _addNewGoalDialog, icon: const Icon(Icons.add_circle, color: AppColors.violet, size: 28)),
            ],
          ),
          const SizedBox(height: 12),
          for (final goal in _goals)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Material(
                color: AppColors.card,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.white10)),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(child: Text(goal.category.toUpperCase(), overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.violet, fontSize: 10, fontWeight: FontWeight.bold))),
                          Row(
                            children: [
                              Text('${(goal.progress * 100).round()}%', style: const TextStyle(color: AppColors.violet, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.white24, size: 18),
                                onPressed: () => _commit(() => _goals.remove(goal)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Text(goal.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: goal.progress,
                        backgroundColor: const Color(0xFF222834),
                        valueColor: const AlwaysStoppedAnimation(AppColors.violet),
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 8),
                      for (final cp in goal.checkpoints)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          activeColor: AppColors.violet,
                          title: Text(
                            cp.title,
                            style: TextStyle(
                              fontSize: 13,
                              decoration: cp.isCompleted ? TextDecoration.lineThrough : null,
                              color: cp.isCompleted ? Colors.white38 : Colors.white,
                            ),
                          ),
                          value: cp.isCompleted,
                          onChanged: (val) => _toggleCheckpoint(goal, cp, val),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ИСТОРИЯ ДОСТИЖЕНИЙ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(onPressed: _addNewAchievementDialog, icon: const Icon(Icons.add_circle, color: AppColors.green, size: 28)),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in _achievements)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                    child: Icon(item.icon, color: AppColors.green, size: 20),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('${item.category} • ${item.date}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white24, size: 16),
                    onPressed: () => _commit(() => _achievements.remove(item)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // 5. КАПИТАЛ
  Widget _buildWealthScreen() {
    final savingsRate = _monthlyIncome > 0 ? (((_monthlyIncome - _monthlyExpense) / _monthlyIncome) * 100).round() : 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('КАПИТАЛ И КАРЬЕРА', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton(onPressed: _editWealthDialog, icon: const Icon(Icons.edit, color: AppColors.gold, size: 22)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF1F242F), AppColors.card], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ЧИСТЫЙ КАПИТАЛ (NET WORTH)', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text('${_fmtMoney(_netWorth)} ₽', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.gold)),
                const SizedBox(height: 4),
                Text(
                  'Норма сбережений (Savings Rate): $savingsRate%',
                  style: TextStyle(color: savingsRate >= 0 ? AppColors.green : AppColors.red, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _moneyTile('ДОХОД / МЕС', _monthlyIncome, Colors.white)),
              const SizedBox(width: 12),
              Expanded(child: _moneyTile('ТРАТЫ / МЕС', _monthlyExpense, AppColors.red)),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ГРАФИК РОСТА ЗАРПЛАТЫ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(onPressed: _addSalaryStepDialog, icon: const Icon(Icons.add_circle, color: AppColors.green, size: 24)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            height: 200,
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
            child: CustomPaint(size: Size.infinite, painter: SalaryLineChartPainter(steps: _salaryHistory)),
          ),
        ],
      ),
    );
  }

  Widget _moneyTile(String title, int value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('${_fmtMoney(value)} ₽', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _toggleBtn(String text, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(color: active ? AppColors.green : Colors.transparent, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: active ? Colors.black : Colors.white60, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _MetricCol extends StatelessWidget {
  final String title;
  final String val;
  final String sub;
  final Color col;
  const _MetricCol(this.title, this.val, this.sub, this.col);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 4),
        Text(val, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: col)),
        const SizedBox(height: 2),
        Text(sub, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 5. ХОЛСТЫ
// ---------------------------------------------------------------------------

/// Сравнение двух рядов. Ряды уже выровнены по длине (хвост), подписи соответствуют точкам.
class DualLineComparisonPainter extends CustomPainter {
  final List<double> dataA;
  final List<double> dataB;
  final List<String> labels;
  final Color colorA;
  final Color colorB;
  final String unitA;
  final String unitB;

  DualLineComparisonPainter({
    required this.dataA,
    required this.dataB,
    required this.labels,
    required this.colorA,
    required this.colorB,
    required this.unitA,
    required this.unitB,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = min(dataA.length, dataB.length);
    if (n < 2) return;

    // Боковые поля: крайние точки и подписи больше не обрезаются.
    const padX = 20.0, top = 28.0, bottom = 22.0;
    final plotW = size.width - padX * 2;
    final plotH = size.height - top - bottom;
    final stepX = plotW / (n - 1);

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1.0;
    for (final f in const [0.0, 0.5, 1.0]) {
      final y = top + plotH * f;
      canvas.drawLine(Offset(padX, y), Offset(size.width - padX, y), gridPaint);
    }

    final minA = dataA.reduce(min), maxA = dataA.reduce(max);
    final minB = dataB.reduce(min), maxB = dataB.reduce(max);

    double yOf(double v, double mn, double mx) {
      final norm = mx == mn ? 0.5 : (v - mn) / (mx - mn); // плоский ряд — по центру, а не прижат к низу
      return top + plotH * (1 - norm);
    }

    final pathA = Path(), pathB = Path();
    final dotA = Paint()..color = colorA, dotB = Paint()..color = colorB;
    final labelStyle = const TextStyle(color: Colors.white38, fontSize: 9);

    for (int i = 0; i < n; i++) {
      final x = padX + i * stepX;
      final yA = yOf(dataA[i], minA, maxA);
      final yB = yOf(dataB[i], minB, maxB);
      if (i == 0) {
        pathA.moveTo(x, yA);
        pathB.moveTo(x, yB);
      } else {
        pathA.lineTo(x, yA);
        pathB.lineTo(x, yB);
      }
      canvas.drawCircle(Offset(x, yA), 4, dotA);
      canvas.drawCircle(Offset(x, yB), 4, dotB);
      if (i < labels.length) {
        _drawText(canvas, labels[i], Offset(x, size.height - 14), labelStyle, anchor: 0.5);
      }
    }

    canvas.drawPath(pathA, Paint()..color = colorA..strokeWidth = 2.5..style = PaintingStyle.stroke);
    canvas.drawPath(pathB, Paint()..color = colorB..strokeWidth = 2.5..style = PaintingStyle.stroke);

    _drawText(canvas, '${dataA.last.toInt()} $unitA', Offset(size.width, 0), TextStyle(color: colorA, fontSize: 9, fontWeight: FontWeight.bold), anchor: 1);
    _drawText(canvas, '${dataB.last.toInt()} $unitB', Offset(size.width, 13), TextStyle(color: colorB, fontSize: 9, fontWeight: FontWeight.bold), anchor: 1);
  }

  @override
  bool shouldRepaint(covariant DualLineComparisonPainter old) => true; // данные мутируются на месте
}

class MiniSparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;

  MiniSparklinePainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    if (data.length == 1) {
      canvas.drawCircle(Offset(size.width / 2, size.height / 2), 4, Paint()..color = color);
      return;
    }

    final minVal = data.reduce(min);
    final maxVal = data.reduce(max);
    final stepX = size.width / (data.length - 1);
    final dotPaint = Paint()..color = color; // один Paint вместо создания в цикле

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final norm = maxVal == minVal ? 0.5 : (data[i] - minVal) / (maxVal - minVal);
      final y = size.height - (norm * (size.height - 12)) - 6;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 2.5, dotPaint);
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          colors: [color.withValues(alpha: 0.3), Colors.transparent],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.drawPath(path, Paint()..color = color..strokeWidth = 2.0..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant MiniSparklinePainter old) => true;
}

class AnatomicalSilhouettePainter extends CustomPainter {
  final Map<String, MuscleGroup> muscles;
  final bool isFront;
  final String? selectedMuscleId;

  AnatomicalSilhouettePainter({required this.muscles, required this.isFront, this.selectedMuscleId});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = min(size.width / AnatomicalGeometry.baseWidth, size.height / AnatomicalGeometry.baseHeight);
    final dx = (size.width - AnatomicalGeometry.baseWidth * scale) / 2;
    final dy = (size.height - AnatomicalGeometry.baseHeight * scale) / 2;

    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(scale);

    _paintMannequinBody(canvas);

    for (final entry in AnatomicalGeometry.pathsFor(isFront).entries) {
      final key = entry.key;
      final path = entry.value;
      final isSelected = key == selectedMuscleId;
      final color = muscles[key]?.color ?? AppColors.green;

      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: isSelected ? 0.55 : 0.22)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, isSelected ? 12 : 6),
      );

      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            colors: [color.withValues(alpha: isSelected ? 0.85 : 0.50), color.withValues(alpha: isSelected ? 0.40 : 0.15)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ).createShader(path.getBounds()),
      );

      canvas.drawPath(
        path,
        Paint()
          ..color = isSelected ? Colors.white : color
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 2.2 : 1.2,
      );
    }

    canvas.restore();
  }

  void _paintMannequinBody(Canvas canvas) {
    final framePaint = Paint()..color = const Color(0xFF13171F)..style = PaintingStyle.fill;
    final strokePaint = Paint()..color = Colors.white10..style = PaintingStyle.stroke..strokeWidth = 1.0;

    const headRect = Rect.fromLTWH(135, 12, 30, 38);
    canvas.drawOval(headRect, framePaint);
    canvas.drawOval(headRect, strokePaint);
    canvas.drawRect(const Rect.fromLTWH(143, 48, 14, 18), framePaint);

    canvas.drawCircle(const Offset(72, 250), 6, framePaint);
    canvas.drawCircle(const Offset(228, 250), 6, framePaint);

    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(112, 436, 18, 16), const Radius.circular(4)), framePaint);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(170, 436, 18, 16), const Radius.circular(4)), framePaint);

    canvas.drawCircle(const Offset(124, 335), 4, strokePaint);
    canvas.drawCircle(const Offset(176, 335), 4, strokePaint);
    canvas.drawCircle(const Offset(84, 175), 3, strokePaint);
    canvas.drawCircle(const Offset(216, 175), 3, strokePaint);
  }

  // Карта muscles — та же ссылка, мутируется на месте, поэтому сравнение по ссылке
  // (как было раньше) НЕ перерисовывало силуэт после записи подхода.
  @override
  bool shouldRepaint(covariant AnatomicalSilhouettePainter old) => true;
}

class LifeGraphPainter extends CustomPainter {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final String? selectedNodeId;
  final String activeCategoryFilter;

  LifeGraphPainter({required this.nodes, required this.edges, this.selectedNodeId, required this.activeCategoryFilter});

  @override
  void paint(Canvas canvas, Size size) {
    if (nodes.isEmpty) return;

    Offset pos(GraphNode n) => Offset(n.position.dx * size.width, n.position.dy * size.height);
    final nodeMap = {for (final n in nodes) n.id: n};

    for (final edge in edges) {
      final from = nodeMap[edge.fromId];
      final to = nodeMap[edge.toId];
      if (from == null || to == null) continue;

      final selected = selectedNodeId != null && (edge.fromId == selectedNodeId || edge.toId == selectedNodeId);
      // ребро приглушается, если НИ один его конец не входит в фильтр (логика сохранена)
      final filteredOut = activeCategoryFilter != 'all' && from.category != activeCategoryFilter && to.category != activeCategoryFilter;

      final a = pos(from), b = pos(to);
      canvas.drawLine(
        a,
        b,
        Paint()
          ..color = selected
              ? Colors.cyanAccent.withValues(alpha: 0.9)
              : (filteredOut ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.18))
          ..strokeWidth = selected ? 2.5 : 1.4,
      );

      if (!filteredOut) {
        canvas.drawCircle((a + b) / 2, selected ? 3.0 : 1.8, Paint()..color = selected ? Colors.cyanAccent : Colors.white24);
      }
    }

    for (final node in nodes) {
      final p = pos(node);
      final selected = node.id == selectedNodeId;
      final filteredOut = activeCategoryFilter != 'all' && node.category != activeCategoryFilter;
      final opacity = filteredOut ? 0.20 : 1.0;

      canvas.drawCircle(
        p,
        selected ? 26 : 18,
        Paint()
          ..color = node.color.withValues(alpha: (selected ? 0.55 : 0.22) * opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawCircle(p, selected ? 13 : 9, Paint()..color = (selected ? Colors.white : node.color).withValues(alpha: opacity));

      final tp = TextPainter(
        text: TextSpan(
          text: node.label,
          style: TextStyle(
            color: (selected ? Colors.white : Colors.white70).withValues(alpha: opacity),
            fontSize: 10,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: max(40.0, size.width - 12));

      // подпись не выходит за границы холста
      final tx = _clampD(p.dx - tp.width / 2, 6, max(6.0, size.width - tp.width - 6));
      final ty = _clampD(p.dy + 15, 2, max(2.0, size.height - tp.height - 6));
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(tx - 4, ty - 2, tp.width + 8, tp.height + 4), const Radius.circular(4)),
        Paint()..color = AppColors.panel.withValues(alpha: 0.85 * opacity),
      );
      tp.paint(canvas, Offset(tx, ty));
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant LifeGraphPainter old) => true;
}

class SalaryLineChartPainter extends CustomPainter {
  final List<SalaryStep> steps;
  SalaryLineChartPainter({required this.steps});

  @override
  void paint(Canvas canvas, Size size) {
    if (steps.isEmpty) return;

    const padX = 24.0; // поля, чтобы первая/последняя подписи не обрезались
    const labelStyle = TextStyle(color: Colors.white70, fontSize: 10);
    final dot = Paint()..color = AppColors.green;

    if (steps.length == 1) {
      final x = size.width / 2, y = size.height / 2;
      canvas.drawCircle(Offset(x, y), 6, dot);
      _drawText(canvas, '${steps[0].year}\n${steps[0].salary ~/ 1000}к', Offset(x, y - 32), labelStyle, anchor: 0.5, align: TextAlign.center);
      return;
    }

    final maxSalary = steps.map((s) => s.salary).reduce(max).toDouble();
    final top = maxSalary * 1.3; // запас сверху под подпись
    final plotW = size.width - padX * 2;
    final stepX = plotW / (steps.length - 1);

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < steps.length; i++) {
      final x = padX + i * stepX;
      final norm = top == 0 ? 0.0 : steps[i].salary / top;
      final y = size.height - (norm * (size.height - 30)) - 20;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }

      canvas.drawCircle(Offset(x, y), 5, dot);
      canvas.drawCircle(Offset(x, y), 2, Paint()..color = Colors.black);
      _drawText(canvas, '${steps[i].year}\n${steps[i].salary ~/ 1000}к', Offset(x, y - 30), labelStyle, anchor: 0.5, align: TextAlign.center);
    }

    fillPath.lineTo(padX + plotW, size.height);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          colors: [AppColors.green.withValues(alpha: 0.35), Colors.transparent],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.drawPath(path, Paint()..color = AppColors.green..strokeWidth = 3.0..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant SalaryLineChartPainter old) => true;
}
