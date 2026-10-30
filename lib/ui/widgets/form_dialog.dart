import 'package:flutter/material.dart';

import '../../core/theme.dart';

class FieldSpec {
  final String key;
  final String label;
  final String initial;
  final bool numeric;
  final int lines;
  final bool obscure; // скрывать ввод (пароли)
  final Map<String, String>? options; // если задано — выпадающий список (value -> подпись)
  const FieldSpec(this.key, this.label, {this.initial = '', this.numeric = false, this.lines = 1, this.obscure = false, this.options});
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
                        obscureText: f.obscure,
                        minLines: f.obscure ? 1 : f.lines,
                        maxLines: f.obscure ? 1 : f.lines,
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
