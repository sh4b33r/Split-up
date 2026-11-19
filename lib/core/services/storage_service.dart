import 'package:firebase_storage/firebase_storage.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';

/// Receipt, payment-proof and profile photos in Firebase Storage.
class StorageService extends GetxService {
  static const _maxBytes = 5 * 1024 * 1024; // matches storage.rules

  Future<XFile?> pick({bool camera = false}) async {
    try {
      return await ImagePicker().pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
    } catch (_) {
      throw const ApiException("Couldn't open your photos. Check the app's permissions.");
    }
  }

  /// Uploads a receipt or proof photo for a room and returns its URL.
  Future<String> uploadRoomPhoto(String roomId, String folder, String uid, XFile file) =>
      _upload('rooms/$roomId/$folder/${DateTime.now().millisecondsSinceEpoch}_$uid', file);

  Future<String> uploadAvatar(String uid, XFile file) =>
      _upload('users/$uid/avatar_${DateTime.now().millisecondsSinceEpoch}', file);

  Future<String> _upload(String path, XFile file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length > _maxBytes) throw const ApiException('That photo is larger than 5 MB.');
    final name = file.name.toLowerCase();
    final type =
        file.mimeType ??
        (name.endsWith('.png')
            ? 'image/png'
            : name.endsWith('.webp')
            ? 'image/webp'
            : name.endsWith('.heic')
            ? 'image/heic'
            : 'image/jpeg');
    try {
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putData(bytes, SettableMetadata(contentType: type));
      return await ref.getDownloadURL();
    } on FirebaseException {
      throw const ApiException("Couldn't upload the photo. Please try again.");
    }
  }
}
