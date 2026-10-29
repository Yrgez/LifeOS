import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:life_os/data/app_data.dart';
import 'package:life_os/data/app_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('первый запуск: данных нет → null', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await PrefsAppRepository().load(), isNull);
  });

  test('save → load возвращает те же данные', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = PrefsAppRepository();
    final d = AppData.defaults()..netWorth = 777;
    await repo.save(d);
    final back = await PrefsAppRepository().load();
    expect(back!.netWorth, 777);
  });

  test('миграция со старого формата (отдельные ключи)', () async {
    SharedPreferences.setMockInitialValues({
      'life_os_net_worth': 5000000,
      'life_os_income': 400000,
      'life_os_steps_hist': jsonEncode([1, 2, 3, 4, 5, 6, 7]),
      'life_os_nodes_v2': jsonEncode([
        {'id': 'n1', 'label': 'N', 'category': 'mind', 'dx': 180.0, 'dy': 240.0, 'color': 0xFF7C4DFF}
      ]),
      'life_os_muscles': jsonEncode({
        'chest': {'id': 'chest', 'name': 'Грудь', 'recovery': 0.95, 'maxWeight': 120, 'lastSets': [], 'history1RM': [120], 'lastTrained': 'x', 'isFront': true}
      }),
    });
    final d = (await PrefsAppRepository().load())!;
    expect(d.netWorth, 5000000);
    expect(d.monthlyIncome, 400000);
    expect(d.stepsWeekHistory.last, 7);
    expect(d.graphNodes.single.position.dx, closeTo(0.5, 1e-9));
    expect(d.muscles['chest']!.recovery, closeTo(0.95, 0.01));
    expect(d.goals, isNotEmpty); // отсутствующее поле → значение по умолчанию
  });

  test('повреждённый блоб: копия откладывается, берутся данные старого формата/по умолчанию', () async {
    SharedPreferences.setMockInitialValues({PrefsAppRepository.dataKey: '{не json'});
    final p = await SharedPreferences.getInstance();
    final d = await PrefsAppRepository().load();
    expect(d, isNull);
    expect(p.getString(PrefsAppRepository.corruptKey), '{не json');
  });

  test('схема новее поддерживаемой → исключение (данные не затираются)', () async {
    SharedPreferences.setMockInitialValues({
      PrefsAppRepository.dataKey: jsonEncode({'schemaVersion': kSchemaVersion + 1}),
    });
    expect(PrefsAppRepository().load(), throwsA(isA<SchemaTooNewException>()));
  });
}
