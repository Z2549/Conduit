import 'package:conduit/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';

export 'package:conduit/l10n/app_localizations.dart' show AppLocalizations;

/// Shorthand for `AppLocalizations.of(context)`.
///
/// `l10n.yaml` sets `nullable-getter: false`, so this never returns null and
/// callers can use `context.l10n.someMessage` directly.
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
