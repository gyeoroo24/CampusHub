import 'dart:convert';
import 'dart:typed_data';

import 'text_file_picker_stub.dart'
    if (dart.library.html) 'text_file_picker_web.dart' as impl;

/// A text file the user picked (a CSV export, say).
class PickedTextFile {
  final String name;
  final String text;

  const PickedTextFile(this.name, this.text);
}

/// Lets the user choose a text file and reads it (UTF-8, or Windows-1252 from Excel; see [decodeText]). Null if they cancel, or where picking
/// files isn't supported (the app is web-first; elsewhere people paste the text instead).
/// [accept] is the browser's accept list, e.g. '.csv,.tsv,.txt'.
Future<PickedTextFile?> pickTextFile({String accept = '.csv,.tsv,.txt'}) => impl.pickTextFile(accept);

/// Whether [pickTextFile] can open a file chooser here.
bool get canPickTextFiles => impl.canPickTextFiles;

/// Windows-1252 characters 0x80-0x9F (where it differs from Latin-1): curly quotes, dashes, the euro sign.
const _cp1252 = {
  0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021,
  0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018,
  0x92: 0x2019, 0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02DC,
  0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178,
};

/// A CSV's text. UTF-8 (with or without a byte-order mark) when the bytes are valid UTF-8; otherwise
/// Windows-1252, which is what Excel's "CSV (Comma delimited)" writes on Windows. Non-breaking spaces
/// become plain spaces.
String decodeText(Uint8List bytes) {
  var start = 0;
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) start = 3;
  String text;
  try {
    text = utf8.decode(bytes.sublist(start));
  } on FormatException {
    text = String.fromCharCodes([for (final b in bytes) _cp1252[b] ?? b]);
  }
  return text.replaceAll('\u00a0', ' ');
}
