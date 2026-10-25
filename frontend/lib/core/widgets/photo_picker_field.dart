import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../config/server_config.dart';
import '../models/photo.dart';
import '../services/upload_service.dart';

/// A photo the user picked but hasn't uploaded yet.
class PickedPhoto {
  final Uint8List bytes;
  final String contentType;
  final String name;

  const PickedPhoto({required this.bytes, required this.contentType, required this.name});
}

/// The image types the API accepts for listing and report photos (see backend storage.py).
const _allowedTypes = {'image/jpeg', 'image/png', 'image/webp', 'image/heic'};
const _maxBytes = 10 * 1024 * 1024;

String _contentTypeFor(XFile file) {
  final mime = file.mimeType?.toLowerCase();
  if (mime != null && _allowedTypes.contains(mime)) return mime;
  final name = file.name.toLowerCase();
  if (name.endsWith('.png')) return 'image/png';
  if (name.endsWith('.webp')) return 'image/webp';
  if (name.endsWith('.heic')) return 'image/heic';
  return 'image/jpeg';
}

/// Uploads the picked photos and returns them in order, ready to attach to a new post.
///
/// Live mode: each file goes to storage through a presigned upload (`POST /uploads`), and the
/// returned key is what the post sends as `photo_keys`. Mock mode: nothing is uploaded; the photo
/// keeps its bytes as a data URL so the mock feed can show it.
Future<List<Photo>> uploadPickedPhotos(WidgetRef ref, List<PickedPhoto> picked, {required String kind}) async {
  final photos = <Photo>[];
  final mock = ref.read(serverConfigProvider).useMockData;
  for (var i = 0; i < picked.length; i++) {
    final p = picked[i];
    if (mock) {
      photos.add(Photo(s3Key: '', url: 'data:${p.contentType};base64,${base64Encode(p.bytes)}', sortOrder: i));
      continue;
    }
    final key = await ref.read(uploadServiceProvider).uploadPhoto(bytes: p.bytes, kind: kind, contentType: p.contentType);
    photos.add(Photo(s3Key: key, url: '', sortOrder: i));
  }
  return photos;
}

/// "Add photos" row with thumbnails and remove buttons. The first photo is the cover.
class PhotoPickerField extends StatefulWidget {
  final List<PickedPhoto> photos;
  final ValueChanged<List<PickedPhoto>> onChanged;
  final int maxPhotos;
  final bool enabled;

  const PhotoPickerField({
    super.key,
    required this.photos,
    required this.onChanged,
    this.maxPhotos = 10,
    this.enabled = true,
  });

  @override
  State<PhotoPickerField> createState() => _PhotoPickerFieldState();
}

class _PhotoPickerFieldState extends State<PhotoPickerField> {
  String? _error;

  Future<void> _pick() async {
    final files = await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 2000);
    if (files.isEmpty) return;
    final next = [...widget.photos];
    final skipped = <String>[];
    for (final f in files) {
      if (next.length >= widget.maxPhotos) {
        skipped.add('${f.name} (limit is ${widget.maxPhotos} photos)');
        continue;
      }
      final bytes = await f.readAsBytes();
      if (bytes.length > _maxBytes) {
        skipped.add('${f.name} (over 10 MB)');
        continue;
      }
      next.add(PickedPhoto(bytes: bytes, contentType: _contentTypeFor(f), name: f.name));
    }
    setState(() => _error = skipped.isEmpty ? null : 'Skipped ${skipped.join(', ')}');
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canAdd = widget.enabled && widget.photos.length < widget.maxPhotos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Photos (optional, up to ${widget.maxPhotos}; the first one is the cover)',
            style: TextStyle(fontSize: 12, color: theme.hintColor)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < widget.photos.length; i++)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(widget.photos[i].bytes, width: 72, height: 72, fit: BoxFit.cover),
                  ),
                  if (i == 0)
                    Positioned(
                      left: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        color: Colors.black54,
                        child: const Text('Cover', style: TextStyle(color: Colors.white, fontSize: 9)),
                      ),
                    ),
                  if (widget.enabled)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: InkWell(
                        onTap: () => widget.onChanged([...widget.photos]..removeAt(i)),
                        child: Container(
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          padding: const EdgeInsets.all(2),
                          child: Tooltip(
                            message: 'Remove photo',
                            child: Icon(Icons.close_rounded, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            if (canAdd)
              InkWell(
                onTap: _pick,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo_outlined, size: 20, color: theme.colorScheme.primary),
                      const SizedBox(height: 2),
                      Text('Add', style: TextStyle(fontSize: 11, color: theme.colorScheme.primary)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_error!, style: TextStyle(fontSize: 11, color: theme.colorScheme.error)),
          ),
      ],
    );
  }
}
