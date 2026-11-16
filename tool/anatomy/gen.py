"""Генератор анатомической фигуры LIFE OS.
Запуск: python3 tool/anatomy/gen.py preview.html  (SVG-превью)
        python3 tool/anatomy/gen.py - --dart lib/ui/painters/anatomy_geometry.dart

Генератор анатомической фигуры: левая половина задаётся точками, правая — зеркально.
Контуры сглаживаются (Catmull-Rom → кубические Безье). Выход: SVG-превью и Dart-файл геометрии."""
import sys
W, H = 300, 600
CX = W / 2

def mirror(pts): return [(W - x, y) for x, y in pts]

def smooth(pts, closed=True, t=0.5):
    n = len(pts)
    d = f"M{pts[0][0]:.1f},{pts[0][1]:.1f}"
    rng = range(n) if closed else range(n - 1)
    for i in rng:
        p0 = pts[(i - 1) % n] if (closed or i > 0) else pts[i]
        p1 = pts[i]; p2 = pts[(i + 1) % n]
        p3 = pts[(i + 2) % n] if (closed or i + 2 < n) else p2
        c1 = (p1[0] + (p2[0] - p0[0]) * t / 3, p1[1] + (p2[1] - p0[1]) * t / 3)
        c2 = (p2[0] - (p3[0] - p1[0]) * t / 3, p2[1] - (p3[1] - p1[1]) * t / 3)
        d += f" C{c1[0]:.1f},{c1[1]:.1f} {c2[0]:.1f},{c2[1]:.1f} {p2[0]:.1f},{p2[1]:.1f}"
    return d + (" Z" if closed else "")

# ---------- силуэт (левая половина, сверху вниз по внешнему краю, затем вверх по внутренней стороне ноги) ----------
SIL_L = [
    (140, 88), (138, 104), (118, 114), (92, 120), (74, 128), (63, 145), (60, 170),
    (58, 200), (54, 232), (49, 262), (43, 298), (40, 322), (35, 342), (37, 362), (45, 373), (54, 367), (58, 347), (61, 326),
    (67, 298), (75, 268), (81, 244), (86, 210), (92, 186), (97, 180),
    (99, 204), (101, 232), (104, 256), (100, 282), (95, 306),
    (93, 344), (97, 392), (104, 428), (107, 446),
    (105, 474), (109, 508), (115, 540), (115, 556), (108, 568), (111, 578), (137, 578), (141, 567), (137, 552),
    (139, 522), (141, 484), (141, 452), (143, 434),
    (145, 392), (147, 352), (149, 322),
]
SIL = SIL_L + list(reversed(mirror(SIL_L)))
HEAD = (CX, 54, 26, 34)  # центр, полуоси

# ---------- мышцы: (группа или None, точки левой половины) ----------
FRONT = [
    ('traps', [(141, 100), (130, 109), (110, 117), (124, 121), (145, 116)]),
    ('delts', [(108, 120), (88, 123), (70, 134), (62, 154), (62, 176), (72, 184), (86, 166), (100, 146), (110, 130)]),
    ('chest', [(147, 123), (118, 122), (104, 130), (96, 150), (100, 172), (118, 188), (147, 190)]),
    ('biceps', [(66, 186), (60, 204), (58, 226), (62, 240), (76, 240), (86, 218), (90, 196), (88, 186), (78, 182)]),
    ('forearms', [(54, 248), (48, 272), (44, 298), (42, 318), (58, 322), (66, 298), (74, 272), (79, 250), (70, 244)]),
    ('abs', [(131, 196), (148, 195), (148, 217), (131, 219)]),
    ('abs', [(130, 223), (148, 222), (148, 244), (130, 246)]),
    ('abs', [(130, 250), (148, 249), (148, 271), (131, 273)]),
    ('abs', [(132, 277), (148, 276), (148, 308), (140, 306), (134, 293)]),
    ('abs', [(127, 196), (104, 204), (101, 236), (103, 262), (111, 288), (127, 300), (127, 250)]),
    (None, [(148, 312), (140, 320), (141, 358), (144, 376), (148, 370)]),  # приводящие
    ('quads', [(99, 312), (93, 348), (96, 394), (104, 424), (115, 428), (117, 380), (114, 336), (106, 314)]),
    ('quads', [(121, 304), (117, 340), (120, 396), (128, 426), (137, 410), (140, 360), (137, 320), (131, 306)]),
    ('quads', [(141, 380), (139, 404), (134, 430), (144, 432), (146, 406)]),
    ('calves', [(108, 452), (104, 482), (108, 520), (115, 540), (121, 520), (122, 472), (119, 454)]),  # передняя большеберцовая
    ('calves', [(126, 456), (134, 476), (138, 502), (134, 526), (127, 520), (124, 482)]),  # внутренняя икроножная
]
BACK = [
    ('traps', None),  # симметричный ромб задаётся целиком ниже
    ('delts', [(108, 120), (88, 123), (70, 134), (62, 154), (62, 176), (72, 184), (86, 166), (100, 146), (110, 130)]),
    ('lats', [(112, 134), (98, 146), (98, 170), (120, 180), (134, 164), (132, 142)]),  # лопаточные — к спине
    ('lats', [(100, 186), (98, 214), (104, 248), (124, 274), (140, 268), (141, 224), (135, 188)]),
    (None, [(144, 232), (140, 262), (142, 292), (148, 298), (149, 240)]),  # разгибатели спины
    ('triceps', [(66, 186), (60, 204), (58, 226), (62, 240), (76, 240), (86, 218), (90, 196), (88, 186), (78, 182)]),
    ('forearms', [(54, 248), (48, 272), (44, 298), (42, 318), (58, 322), (66, 298), (74, 272), (79, 250), (70, 244)]),
    ('glutes', [(148, 300), (118, 298), (99, 316), (98, 346), (116, 362), (148, 354)]),
    ('hamstrings', [(100, 366), (96, 396), (104, 428), (120, 428), (122, 390), (118, 366)]),
    ('hamstrings', [(125, 366), (127, 398), (128, 428), (143, 430), (146, 394), (146, 368)]),
    ('calves', [(108, 448), (103, 476), (108, 508), (124, 500), (126, 462), (120, 448)]),
    ('calves', [(129, 448), (128, 474), (131, 506), (142, 496), (142, 466), (139, 448)]),
]
TRAPS_BACK = [(150, 94), (164, 106), (193, 120), (176, 132), (161, 172), (150, 222), (139, 172), (124, 132), (107, 120), (136, 106)]

def muscles(view):
    out = []
    for g, pts in (FRONT if view == 'front' else BACK):
        if pts is None:
            out.append((g, smooth(TRAPS_BACK, t=0.35)))
            continue
        out.append((g, smooth(pts)))
        out.append((g, smooth(list(reversed(mirror(pts))))))
    return out

def svg(view):
    body = f'<ellipse cx="{HEAD[0]}" cy="{HEAD[1]}" rx="{HEAD[2]}" ry="{HEAD[3]}" fill="#262C35"/><path d="{smooth(SIL, t=0.5)}" fill="#262C35"/>'
    hl = {'front': {'chest': '#E5484D', 'quads': '#C2474C', 'delts': '#8E4A52'}, 'back': {'lats': '#D8DEE6', 'glutes': '#C2474C', 'hamstrings': '#B0454B'}}[view]
    for g, d in muscles(view):
        fill = hl.get(g, '#3A4452' if g else '#313946')
        body += f'<path d="{d}" fill="{fill}" stroke="#141416" stroke-width="2.2" stroke-linejoin="round"/>'
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" style="background:#141416">{body}</svg>'

if __name__ == '__main__' and '--dart' not in sys.argv:
    html = '<html><body style="margin:0;background:#141416;display:flex;gap:20px">' + svg('front') + svg('back') + '</body></html>'
    open(sys.argv[1], 'w').write(html)

def dart():
    def block(view):
        groups, order, neutral = {}, [], []
        for g, d in muscles(view):
            if g is None:
                neutral.append(d)
            else:
                if g not in groups:
                    groups[g] = []; order.append(g)
                groups[g].append(d)
        lines = [f"  static final Map<String, Path> {view}Paths = {{"]
        for g in order:
            lines.append(f"    '{g}': _paths(const [")
            for d in groups[g]:
                lines.append(f"      '{d}',")
            lines.append("    ]),")
        lines.append("  };")
        lines.append(f"  static final Path {view}Neutral = _paths(const [")
        for d in neutral:
            lines.append(f"      '{d}',")
        lines.append("  ]);")
        return "\n".join(lines)
    return f'''// СГЕНЕРИРОВАНО: tool/anatomy/gen.py — правьте точки там и перегенерируйте, а не этот файл.
import 'package:flutter/material.dart';

/// Плоская анатомическая фигура (собственный рисунок, не стоковое изображение): база {W}×{H}.
/// Мышцы сгруппированы по id групп приложения — по ним работают выбор, восстановление и нажатия.
/// Нейтральные сегменты (приводящие, разгибатели спины) рисуются, но не выбираются.
class AnatomicalGeometry {{
  static const double baseWidth = {W}.0;
  static const double baseHeight = {H}.0;

{block('front')}

{block('back')}

  static final Path _silhouette = _paths(const ['{smooth(SIL, t=0.5)}']);
  static const Rect _head = Rect.fromLTRB({HEAD[0]-HEAD[2]}, {HEAD[1]-HEAD[3]}, {HEAD[0]+HEAD[2]}, {HEAD[1]+HEAD[3]});

  static Map<String, Path> pathsFor(bool front) => front ? frontPaths : backPaths;
  static Path neutralFor(bool front) => front ? frontNeutral : backNeutral;

  /// Силуэт: голова и тело.
  static void paintSilhouette(Canvas canvas, Paint fill) {{
    canvas.drawOval(_head, fill);
    canvas.drawPath(_silhouette, fill);
  }}

  /// Разбор путей из генератора: только абсолютные M, C и Z.
  static Path _paths(List<String> ds) {{
    final p = Path();
    for (final d in ds) {{
      final t = RegExp(r'[MCZ]|-?[0-9.]+').allMatches(d).map((m) => m.group(0)!).toList();
      var i = 0;
      double n() => double.parse(t[i++]);
      while (i < t.length) {{
        switch (t[i++]) {{
          case 'M':
            p.moveTo(n(), n());
          case 'C':
            p.cubicTo(n(), n(), n(), n(), n(), n());
          case 'Z':
            p.close();
        }}
      }}
    }}
    return p;
  }}
}}
'''

if __name__ == '__main__' and len(sys.argv) > 2 and sys.argv[2] == '--dart':
    open(sys.argv[3], 'w').write(dart())
