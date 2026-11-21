import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../models/day_checkin.dart';
import '../../state/app_controller.dart';
import '../widgets/toast.dart';

/// «Сегодня», «Вчера» или дата — о каком дне отметка.
String checkInDayLabel(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(day.year, day.month, day.day);
  if (d == today) return 'Сегодня';
  if (d == DateTime(today.year, today.month, today.day - 1)) return 'Вчера';
  return shortDate(d);
}

/// Переключатель оценки 1–5: круглые кнопки, выбранная — белая.
class RatingPicker extends StatelessWidget {
  final int? value;
  final ValueChanged<int> onSelected;
  final String keyPrefix;
  const RatingPicker({super.key, required this.value, required this.onSelected, this.keyPrefix = 'rating'});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (var r = DayCheckIn.minRating; r <= DayCheckIn.maxRating; r++) ...[
            if (r > DayCheckIn.minRating) const SizedBox(width: 8),
            Expanded(
              // программа чтения экрана слышит «Оценка 3 из 5», а не просто «3»; высота 48 — область нажатия Android
              child: Semantics(
                button: true,
                selected: value == r,
                inMutuallyExclusiveGroup: true,
                label: 'Оценка $r из ${DayCheckIn.maxRating}',
                onTap: () => onSelected(r),
                excludeSemantics: true,
                child: Material(
                  key: ValueKey('${keyPrefix}_$r'),
                  color: value == r ? AppColors.accent : AppColors.field,
                  shape: const StadiumBorder(side: BorderSide(color: AppColors.border)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => onSelected(r),
                    child: SizedBox(
                      height: 48,
                      child: Center(
                        child: Text('$r', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: value == r ? Colors.black : AppColors.text)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
}

/// Отметка дня: оценка, метки, строка дневника. Правка сохраняется новой версией.
class CheckInScreen extends StatefulWidget {
  final AppController controller;
  final DateTime day;
  final int? initialRating; // оценка, выбранная на плитке «Сегодня»
  const CheckInScreen({super.key, required this.controller, required this.day, this.initialRating});

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  AppController get c => widget.controller;
  int? _rating;
  late List<String> _tags;
  late final TextEditingController _note;
  final _newTag = TextEditingController();

  @override
  void initState() {
    super.initState();
    final cur = c.checkInFor(widget.day);
    _rating = widget.initialRating ?? cur?.rating;
    _tags = [...?cur?.tags];
    _note = TextEditingController(text: cur?.note ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    _newTag.dispose();
    super.dispose();
  }

  void _addTag(String raw) {
    final t = DayCheckIn.normalizeTag(raw);
    if (t.isEmpty || t.length > DayCheckIn.maxTagLength || _tags.contains(t) || _tags.length >= DayCheckIn.maxTags) return;
    setState(() => _tags.add(t));
    _newTag.clear();
  }

  bool get _canSave => _rating != null || _tags.isNotEmpty || _note.text.trim().isNotEmpty;

  void _save() {
    if (_newTag.text.trim().isNotEmpty) _addTag(_newTag.text);
    final id = c.setCheckIn(widget.day, rating: _rating, tags: _tags, note: _note.text);
    if (id == null) {
      showToast(context, 'Отметка не сохранена: проверьте метки и дату');
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final versions = c.checkInVersions(widget.day);
    final suggestions = [for (final t in c.checkInTagSuggestions) if (!_tags.contains(t)) t].take(12).toList();
    return Scaffold(
      appBar: AppBar(title: Text('${checkInDayLabel(widget.day, c.now)} · ${fmtDate(widget.day)}'), backgroundColor: AppColors.panel, elevation: 0),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const Text('Как прошёл день?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          RatingPicker(value: _rating, onSelected: (r) => setState(() => _rating = _rating == r ? null : r)),
          const SizedBox(height: 6),
          const Text(DayCheckIn.ratingHint, style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 24),
          const Text('МЕТКИ', style: AppText.caption),
          const SizedBox(height: 4),
          const Text('Что было в этот день: «кофе после обеда», «прогулка», «плохо спал»', style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in _tags)
                InputChip(key: ValueKey('tag_on_$t'), label: Text(t), selected: true, showCheckmark: false, onDeleted: () => setState(() => _tags.remove(t))),
              for (final t in suggestions) ActionChip(key: ValueKey('tag_add_$t'), label: Text(t), onPressed: () => _addTag(t)),
            ],
          ),
          TextField(
            key: const ValueKey('checkin_new_tag'),
            controller: _newTag,
            maxLength: DayCheckIn.maxTagLength,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'Новая метка',
              counterText: '',
              suffixIcon: IconButton(icon: const Icon(Icons.add), tooltip: 'Добавить метку', onPressed: () => _addTag(_newTag.text)),
            ),
            onSubmitted: _addTag,
          ),
          const SizedBox(height: 12),
          const Text('ЗАМЕТКА', style: AppText.caption),
          TextField(
            key: const ValueKey('checkin_note'),
            controller: _note,
            maxLines: 3,
            minLines: 1,
            maxLength: DayCheckIn.maxNote,
            decoration: const InputDecoration(hintText: 'Одна строка о дне — необязательно', counterText: ''),
            onChanged: (_) => setState(() {}),
          ),
          if (versions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Записано ${fmtDate(versions.first.recordedAt)} ${fmtTime(versions.first.recordedAt)}'
                '${versions.length > 1 ? ' · правок: ${versions.length - 1}, последняя ${fmtTime(versions.last.recordedAt)}' : ''}. '
                'Правка сохранится новой версией.',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ),
          const SizedBox(height: 20),
          FilledButton(
            key: const ValueKey('checkin_save'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(48)),
            onPressed: _canSave ? _save : null,
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}

