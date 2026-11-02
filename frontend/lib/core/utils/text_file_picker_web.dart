// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'text_file_picker.dart';

/// Larger than any sheet the API accepts (2 MB of text), with room for a byte-order mark.
const _maxBytes = 3 * 1024 * 1024;

Future<PickedTextFile?> pickTextFile(String accept) {
  final completer = Completer<PickedTextFile?>();
  final input = html.FileUploadInputElement()..accept = accept;
  input.onChange.first.then((_) {
    final file = input.files?.isNotEmpty == true ? input.files!.first : null;
    if (file == null) {
      completer.complete(null);
      return;
    }
    if (file.size > _maxBytes) {
      completer.completeError(Exception('${file.name} is larger than 3 MB. Split it into smaller files.'));
      return;
    }
    final reader = html.FileReader();
    reader.onLoad.first.then((_) => completer.complete(PickedTextFile(file.name, '${reader.result}')));
    reader.onError.first.then((_) => completer.completeError(Exception("Couldn't read ${file.name}.")));
    reader.readAsText(file, 'UTF-8');
  });
  input.click();
  return completer.future;
}

bool get canPickTextFiles => true;
