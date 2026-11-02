import 'text_file_picker_stub.dart'
    if (dart.library.html) 'text_file_picker_web.dart' as impl;

/// A text file the user picked (a CSV export, say).
class PickedTextFile {
  final String name;
  final String text;

  const PickedTextFile(this.name, this.text);
}

/// Lets the user choose a text file and reads it as UTF-8. Null if they cancel, or where picking
/// files isn't supported (the app is web-first; elsewhere people paste the text instead).
/// [accept] is the browser's accept list, e.g. '.csv,.tsv,.txt'.
Future<PickedTextFile?> pickTextFile({String accept = '.csv,.tsv,.txt'}) => impl.pickTextFile(accept);

/// Whether [pickTextFile] can open a file chooser here.
bool get canPickTextFiles => impl.canPickTextFiles;
