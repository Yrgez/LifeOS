import 'dart:convert';
import 'dart:typed_data';

/// Текст файла выписки из байтов. Чистая логика без Flutter.
///
/// Банки выгружают CSV в UTF-8 (часто с BOM), UTF-16 или в Windows-1251 — русские буквы в 1251, прочитанные как
/// UTF-8, превращаются в «кракозябры». Порядок: метка BOM → строгий UTF-8 → Windows-1251.
/// null — это не текст (например, файл Excel .xlsx: в нём нулевые байты).

class DecodedText {
  final String text;
  final String encoding; // для подписи «кодировка: Windows-1251»
  const DecodedText(this.text, this.encoding);
}

DecodedText? decodeStatementBytes(Uint8List bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return _utf8(bytes.sublist(3), 'UTF-8');
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) return DecodedText(_utf16(bytes.sublist(2), little: true), 'UTF-16');
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) return DecodedText(_utf16(bytes.sublist(2), little: false), 'UTF-16');
  // нулевые байты в тексте не встречаются — это архив или двоичный формат
  if (bytes.contains(0)) return null;
  return _utf8(bytes, 'UTF-8') ?? DecodedText(decodeWindows1251(bytes), 'Windows-1251');
}

DecodedText? _utf8(List<int> bytes, String name) {
  try {
    return DecodedText(utf8.decode(bytes), name);
  } on FormatException {
    return null;
  }
}

String _utf16(List<int> b, {required bool little}) {
  final units = <int>[for (var i = 0; i + 1 < b.length; i += 2) little ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]];
  return String.fromCharCodes(units);
}

/// Windows-1251: 0x00–0x7F — ASCII, 0xC0–0xFF — «А»…«я», остальное — по таблице.
String decodeWindows1251(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    if (b < 0x80) {
      sb.writeCharCode(b);
    } else if (b >= 0xC0) {
      sb.writeCharCode(0x0410 + b - 0xC0);
    } else {
      sb.writeCharCode(_cp1251High[b - 0x80]);
    }
  }
  return sb.toString();
}

// 0x80–0xBF
const _cp1251High = [
  0x0402, 0x0403, 0x201A, 0x0453, 0x201E, 0x2026, 0x2020, 0x2021, 0x20AC, 0x2030, 0x0409, 0x2039, 0x040A, 0x040C, 0x040B, 0x040F, //
  0x0452, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0xFFFD, 0x2122, 0x0459, 0x203A, 0x045A, 0x045C, 0x045B, 0x045F,
  0x00A0, 0x040E, 0x045E, 0x0408, 0x00A4, 0x0490, 0x00A6, 0x00A7, 0x0401, 0x00A9, 0x0404, 0x00AB, 0x00AC, 0x00AD, 0x00AE, 0x0407,
  0x00B0, 0x00B1, 0x0406, 0x0456, 0x0491, 0x00B5, 0x00B6, 0x00B7, 0x0451, 0x2116, 0x0454, 0x00BB, 0x0458, 0x0405, 0x0455, 0x0457,
];
