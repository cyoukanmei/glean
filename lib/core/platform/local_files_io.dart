import 'dart:io';

import 'package:flutter/painting.dart';

/// Whether this build can keep files of its own (photos).
const supportsLocalFiles = true;

Future<void> createDirectory(String path) =>
    Directory(path).create(recursive: true);

Future<void> copyFile(String from, String to) => File(from).copy(to);

Future<void> deleteFile(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}

/// An image stored at [path] on the device.
ImageProvider? localImage(String path) => FileImage(File(path));
