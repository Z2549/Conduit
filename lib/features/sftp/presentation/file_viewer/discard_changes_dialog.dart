import 'package:conduit/core/l10n/legacy_tr.dart';
import 'package:flutter/material.dart';

/// Asks whether unsaved edits to [fileName] may be thrown away.
///
/// Resolves to true when the user chooses to discard.
Future<bool> confirmDiscardChanges(
  BuildContext context, {
  required String fileName,
}) async {
  final discard = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr('Discard changes?')),
      content: Text('Unsaved edits to $fileName will be lost.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(tr('Keep editing')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(tr('Discard')),
        ),
      ],
    ),
  );
  return discard ?? false;
}
