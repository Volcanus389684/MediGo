import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class ExtractedPrescriptionItem {
  const ExtractedPrescriptionItem({
    required this.medicine,
    required this.sourceLine,
    this.strength,
    this.quantity,
    required this.confidence,
  });

  final String medicine;
  final String sourceLine;
  final String? strength;
  final int? quantity;
  final double confidence;

  String get matchedMedicine => medicine;
}

class PrescriptionExtractor {
  PrescriptionExtractor._();

  static Future<List<ExtractedPrescriptionItem>> extractPrintedMedicineLines({
    required String imagePath,
    required List<String> knownMedicineNames,
  }) async {
    if (kIsWeb) return const [];

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));
      final lines = result.blocks
          .expand((block) => block.lines)
          .map((line) => line.text.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      return parsePrintedLines(lines, knownMedicineNames);
    } finally {
      await recognizer.close();
    }
  }

  static List<ExtractedPrescriptionItem> parsePrintedLines(
    List<String> lines,
    List<String> knownMedicineNames,
  ) {
    final sortedNames = [...knownMedicineNames]
      ..sort((a, b) => b.length.compareTo(a.length));
    final results = <ExtractedPrescriptionItem>[];
    final standaloneQuantities = <int>[];
    final seen = <String>{};

    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final rawLine = lines[lineIndex];
      final line = rawLine.trim();
      if (RegExp(r'\b(clinic|doctor|license|signature|seal|address|phone|date|note)\b', caseSensitive: false).hasMatch(line)) {
        continue;
      }
      final standaloneQuantity = _quantityFromLine(line);
      if (_findMedicine(line, sortedNames) == null && standaloneQuantity != null) {
        standaloneQuantities.add(standaloneQuantity);
      }
      final match = _findMedicine(line, sortedNames);
      if (match == null || !seen.add(_normalize(match))) continue;

      var explicitQuantity = _quantityFromLine(line);
      var strength = _strengthFromLine(line);
      final sourceLines = <String>[line];
      for (var nextIndex = lineIndex + 1; nextIndex < lines.length && nextIndex <= lineIndex + 6; nextIndex++) {
        final nextLine = lines[nextIndex].trim();
        if (nextLine.isEmpty || _isMetadataLine(nextLine)) continue;
        if (_findMedicine(nextLine, sortedNames) != null) break;
        sourceLines.add(nextLine);
        final nextQuantity = _quantityFromLine(nextLine);
        if (nextQuantity != null) explicitQuantity = nextQuantity;
        strength ??= _strengthFromLine(nextLine);
      }
      final confidence = explicitQuantity != null ? 0.95 : strength != null ? 0.82 : 0.7;

      results.add(ExtractedPrescriptionItem(
        medicine: match,
        sourceLine: sourceLines.join(' | '),
        strength: strength,
        quantity: explicitQuantity,
        confidence: confidence,
      ));
    }
    var quantityIndex = 0;
    return results.map((item) {
      if (item.quantity != null || quantityIndex >= standaloneQuantities.length) return item;
      final quantity = standaloneQuantities[quantityIndex++];
      return ExtractedPrescriptionItem(
        medicine: item.medicine,
        sourceLine: item.sourceLine,
        strength: item.strength,
        quantity: quantity,
        confidence: 0.88,
      );
    }).toList();
  }

  static String? _findMedicine(String line, List<String> names) {
    for (final medicine in names) {
      final pattern = RegExp(r'\b' + RegExp.escape(medicine.trim()).replaceAll(r'\ ', r'\s+') + r'\b', caseSensitive: false);
      if (pattern.hasMatch(line)) return medicine;
    }
    return null;
  }

  static bool _isMetadataLine(String line) => RegExp(r'\b(clinic|doctor|license|signature|seal|address|phone|date|note)\b', caseSensitive: false).hasMatch(line);

  static int? _quantityFromLine(String line) {
    final match = RegExp(r'(?:quantity|qty|amount|total)\s*[:\-]?\s*(\d+)\s*(?:tablets?|capsules?|pills?|packets?|units?)?\b|\bx\s*(\d+)\b|\b(\d+)\s*(?:tablets?|capsules?|pills?|packets?|units?)\s*$', caseSensitive: false).firstMatch(line);
    return int.tryParse(match?.group(1) ?? match?.group(2) ?? match?.group(3) ?? '');
  }

  static String? _strengthFromLine(String line) {
    final match = RegExp(r'\b(\d+(?:\.\d+)?)\s*(mg|mcg|g|ml)\b', caseSensitive: false).firstMatch(line);
    return match == null ? null : '${match.group(1)} ${match.group(2)}';
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
}
