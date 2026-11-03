// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'file_picker.dart';

const _types = {'pdf': 'application/pdf', 'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
  'webp': 'image/webp', 'heic': 'image/heic', 'zip': 'application/zip', 'txt': 'text/plain', 'csv': 'text/csv',
  'md': 'text/markdown',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'};

Future<PickedFile?> pickFile(String accept, int maxBytes) {
  final completer = Completer<PickedFile?>();
  // Safari only fires change for an input that is in the page, so add a hidden one for the pick.
  final input = html.FileUploadInputElement()
    ..accept = accept
    ..style.display = 'none';
  html.document.body?.append(input);
  input.onChange.first.then((_) {
    input.remove();
    final file = input.files?.isNotEmpty == true ? input.files!.first : null;
    if (file == null) {
      completer.complete(null);
      return;
    }
    if (file.size > maxBytes) {
      completer.completeError(Exception('${file.name} is larger than ${maxBytes ~/ (1024 * 1024)} MB.'));
      return;
    }
    final ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : '';
    // Our own table first: browsers disagree on some types (zip as application/x-zip-compressed, .md as nothing).
    final type = _types[ext] ?? (file.type.isNotEmpty ? file.type : 'application/octet-stream');
    final reader = html.FileReader();
    reader.onLoad.first.then((_) {
      final result = reader.result;
      final bytes = result is ByteBuffer ? result.asUint8List() : result as Uint8List;
      completer.complete(PickedFile(file.name, bytes, type));
    });
    reader.onError.first.then((_) => completer.completeError(Exception("Couldn't read ${file.name}.")));
    reader.readAsArrayBuffer(file);
  });
  input.click();
  return completer.future;
}

bool get canPickFiles => true;
