import 'package:flutter/material.dart';

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
