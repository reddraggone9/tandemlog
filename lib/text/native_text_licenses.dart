import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Registered at launch, loaded only when the platform license page requests
/// notices. The same reviewed text ships as a Flutter asset on every target.
void registerNativeTextLicenses() {
  LicenseRegistry.addLicense(() async* {
    final notices = await rootBundle.loadString(
      'native/text_engine/THIRD_PARTY_NOTICES.txt',
    );
    yield LicenseEntryWithLineBreaks(const ['Tandemlog text engine'], notices);
  });
}
