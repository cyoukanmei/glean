import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/platform/local_files.dart';

/// Profile photos picked from the gallery, copied into the app's documents
/// folder (the picker's own file may be a temporary copy).
class AvatarStore {
  const AvatarStore();

  /// Lets the user pick a photo; returns `file:<path>` or null if cancelled.
  /// The picker scales it down, so a stored avatar stays around 100 KB.
  Future<String?> pickFromGallery(String userId) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return null;
    final dir = p.join(
      (await getApplicationDocumentsDirectory()).path,
      'avatars',
    );
    await createDirectory(dir);
    final ext = p.extension(picked.path).isEmpty
        ? '.jpg'
        : p.extension(picked.path);
    // A new name per pick, so the image cache never shows the old photo.
    final path = p.join(
      dir,
      '$userId-${clock.now().millisecondsSinceEpoch}$ext',
    );
    await copyFile(picked.path, path);
    return 'file:$path';
  }

  /// Deletes a stored photo that is no longer used.
  Future<void> discard(String? avatar) async {
    if (avatar == null || !avatar.startsWith('file:')) return;
    await deleteFile(avatar.substring(5));
  }
}

final avatarStoreProvider = Provider((ref) => const AvatarStore());
