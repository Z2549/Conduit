import 'package:conduit/core/l10n/l10n.dart';
import 'package:conduit/core/l10n/legacy_zh.dart';

/// Translation lookup for the screens that still carry English literals.
///
/// The ARB-backed [AppLocalizations] remains the source of truth for new code
/// (`context.l10n.someKey`). [tr] exists so an existing UI of a thousand
/// strings can be translated without threading a `BuildContext` through every
/// widget, controller and service: the English text itself is the key.
///
/// Untranslated strings fall through unchanged, so a missing entry shows
/// English rather than nothing.
String tr(String english) {
  final locale = AppLocalizationsHolder.current.localeName;
  if (!locale.startsWith('zh')) {
    return english;
  }
  return legacyZh[english] ?? english;
}
