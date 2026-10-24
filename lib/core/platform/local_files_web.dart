import 'package:flutter/painting.dart';

/// Whether this build can keep files of its own (photos).
const supportsLocalFiles = false;

Future<void> createDirectory(String path) =>
    throw UnsupportedError('no file system on the web');

Future<void> copyFile(String from, String to) =>
    throw UnsupportedError('no file system on the web');

Future<void> deleteFile(String path) async {}

/// An image stored at [path] on the device: none on the web.
ImageProvider? localImage(String path) => null;
