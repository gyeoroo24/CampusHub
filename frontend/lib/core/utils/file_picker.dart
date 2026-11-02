import 'dart:typed_data';

import 'file_picker_stub.dart' if (dart.library.html) 'file_picker_web.dart' as impl;

/// A file the user picked, read into memory (a menu PDF or photo, say).
class PickedFile {
  final String name;
  final Uint8List bytes;
  final String mimeType;

  const PickedFile(this.name, this.bytes, this.mimeType);

  bool get isPdf => mimeType == 'application/pdf' || name.toLowerCase().endsWith('.pdf');
}

/// Lets the user choose one file of the [accept] types (e.g. 'application/pdf,image/*'), up to [maxBytes].
/// Null if they cancel, or where picking files isn't supported (the app is web-first).
Future<PickedFile?> pickFile({required String accept, int maxBytes = 20 * 1024 * 1024}) =>
    impl.pickFile(accept, maxBytes);

/// Whether [pickFile] can open a file chooser here.
bool get canPickFiles => impl.canPickFiles;
