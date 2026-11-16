import 'utils.dart';

/// Основная валюта приложения. Одна на все данные: смена валюты меняет только обозначение,
/// суммы НЕ пересчитываются (курс неизвестен — приложение ничего не запрашивает из сети).
class Currency {
  final String code;
  final String symbol;
  final String name;
  const Currency(this.code, this.symbol, this.name);
}

const currencies = [
  Currency('RUB', '₽', 'Российский рубль'),
  Currency('USD', '\$', 'Доллар США'),
  Currency('EUR', '€', 'Евро'),
  Currency('GBP', '£', 'Фунт стерлингов'),
  Currency('CNY', '¥', 'Китайский юань'),
  Currency('KZT', '₸', 'Казахстанский тенге'),
  Currency('BYN', 'Br', 'Белорусский рубль'),
  Currency('UAH', '₴', 'Украинская гривна'),
  Currency('GEL', '₾', 'Грузинский лари'),
  Currency('AMD', '֏', 'Армянский драм'),
  Currency('TRY', '₺', 'Турецкая лира'),
  Currency('AED', 'AED', 'Дирхам ОАЭ'),
];

const kDefaultCurrency = 'RUB';

Currency? currencyByCode(String code) {
  for (final c in currencies) {
    if (c.code == code) return c;
  }
  return null;
}

/// Текущая валюта для форматирования. Устанавливает контроллер ([AppController]) при загрузке и смене;
/// так формат не нужно протаскивать через каждый виджет.
Currency _current = currencies.first;
Currency get currentCurrency => _current;
set currentCurrency(Currency c) => _current = c;

/// Обозначение текущей валюты: «₽», «$»…
String get cur => _current.symbol;

/// Сумма с обозначением валюты: «1 000 ₽».
String fmtCur(int v) => '${fmtMoney(v)} $cur';
