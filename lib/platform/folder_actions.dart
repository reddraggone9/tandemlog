import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:url_launcher/url_launcher.dart';
import 'log_folder.dart';

/// Small platform boundary for user-mediated selection and external navigation.
class FolderActions {
  bool get requiresPicker => Platform.isAndroid;

  Future<String?> pick() => requiresPicker
      ? AndroidLogFolder.pick()
      : getDirectoryPath(confirmButtonText: 'Use this folder');

  // A SAF tree URI is not a portable filesystem path or generic launch URL.
  Future<bool> canOpen(String location) async =>
      !requiresPicker && await canLaunchUrl(Uri.directory(location));

  Future<void> open(String location) async {
    if (requiresPicker || !await launchUrl(Uri.directory(location))) {
      throw StateError(
        'No file manager could open this folder. Your data is unchanged.',
      );
    }
  }
}
