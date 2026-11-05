import 'package:flutter/material.dart';

const meColor = Color(0xFF1565C0);

const _palette = [
  Color(0xFFD81B60),
  Color(0xFF8E24AA),
  Color(0xFF00897B),
  Color(0xFFF4511E),
  Color(0xFF6D4C41),
  Color(0xFF3949AB),
  Color(0xFF7CB342),
  Color(0xFFFFA000),
];

/// Cor pela ordem de entrada no grupo: os 8 primeiros amigos nunca repetem cor.
Color friendColor(int index) => _palette[index % _palette.length];
