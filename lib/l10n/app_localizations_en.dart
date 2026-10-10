// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get actionCancel => 'Cancel';

  @override
  String get actionClose => 'Close';

  @override
  String get actionDone => 'Done';

  @override
  String get actionAdd => 'Add';

  @override
  String get actionRemove => 'Remove';

  @override
  String get actionDelete => 'Delete';

  @override
  String get actionRename => 'Rename';

  @override
  String get actionEdit => 'Edit';

  @override
  String get actionSave => 'Save';

  @override
  String get actionBack => 'Back';

  @override
  String get actionCopy => 'Copy';

  @override
  String get actionReset => 'Reset';

  @override
  String get actionRetry => 'Retry';

  @override
  String get actionContinue => 'Continue';

  @override
  String get actionImport => 'Import';

  @override
  String get actionPaste => 'Paste';

  @override
  String get actionGenerate => 'Generate';

  @override
  String get actionUpload => 'Upload';

  @override
  String get actionInstall => 'Install';

  @override
  String get actionCreate => 'Create';

  @override
  String get actionReplace => 'Replace';

  @override
  String get actionTrust => 'Trust';

  @override
  String get actionReject => 'Reject';

  @override
  String get actionForget => 'Forget';

  @override
  String get actionReinstall => 'Reinstall';

  @override
  String get actionUnlock => 'Unlock';

  @override
  String get actionTryAgain => 'Try again';

  @override
  String get actionShow => 'Show';

  @override
  String get actionHide => 'Hide';

  @override
  String get actionClear => 'Clear';

  @override
  String get actionManage => 'Manage';

  @override
  String get actionRefresh => 'Refresh';

  @override
  String get actionReconnect => 'Reconnect';

  @override
  String get labelPassword => 'Password';

  @override
  String get labelLabel => 'Label';

  @override
  String get labelName => 'Name';

  @override
  String get labelText => 'Text';

  @override
  String get labelHost => 'Host';

  @override
  String get hostFormHost => 'Host or IP';

  @override
  String get hostFormPort => 'Port';

  @override
  String get hostFormUsername => 'Username';

  @override
  String get hostFormDisplayName => 'Display name';

  @override
  String get hostFormSectionConnection => 'Connection';

  @override
  String get hostFormSectionAuthentication => 'Authentication';

  @override
  String get hostFormSectionAdvanced => 'Advanced';

  @override
  String get labelAlgorithm => 'Algorithm';

  @override
  String get labelFingerprint => 'Fingerprint';

  @override
  String get labelVersion => 'Version';

  @override
  String get labelDistribution => 'Distribution';

  @override
  String get labelDiskUsage => 'Disk usage';

  @override
  String get labelAndroidFiles => 'Android files';

  @override
  String get labelTags => 'Tags';

  @override
  String get labelFiles => 'Files';

  @override
  String get labelMachines => 'Machines';

  @override
  String get labelSnippets => 'Snippets';

  @override
  String get terminalCloseCompose => 'Close compose';

  @override
  String get actionCopyPath => 'Copy path';

  @override
  String get actionDownload => 'Download';

  @override
  String get actionDownloadAsTar => 'Download as tar';

  @override
  String get labelOpenSourceLicenses => 'Open-source licenses';

  @override
  String get securityKeyChooseTitle => 'Choose security key';

  @override
  String get securityKeyPinLabel => 'FIDO2 PIN';

  @override
  String get securityKeyPinTitle => 'Security key PIN';

  @override
  String get securityKeyPinBody =>
      'Enter the PIN for your hardware security key.';

  @override
  String get languageTitle => 'Language';

  @override
  String get languageSystem => 'System default';

  @override
  String get languageSubtitle =>
      'Applies to the whole app immediately. No restart needed.';

  @override
  String get hostFormMachineName => 'Machine name';

  @override
  String get appearanceTitle => 'Appearance';

  @override
  String get appearanceSubtitle =>
      'Pick a developer palette. The home screen, editor, and dialogs share the same look.';

  @override
  String get appearanceShowLocalShell => 'Show local shell';

  @override
  String get appearanceShowLocalShellHint =>
      'Show the local terminal shortcut on the home screen.';

  @override
  String get backupTitle => 'Backup and restore';

  @override
  String get appearanceBackupRestoreHint =>
      'Export settings and machines or import a saved backup.';

  @override
  String get appearanceThemeSystem => 'System';

  @override
  String get appearanceThemeDark => 'Dark';

  @override
  String get appearanceThemeLight => 'Light';

  @override
  String get appearanceFontSize => 'Font size';

  @override
  String get appearanceKeyRows => 'Key rows';

  @override
  String get appearanceEnterSends => 'Enter sends';

  @override
  String get appearanceSendMouseTaps => 'Send mouse taps';

  @override
  String get appearanceSendMouseTapsHint =>
      'Forward terminal taps as mouse clicks when apps enable mouse tracking.';

  @override
  String get appearanceGlobalSnippets => 'Global snippets';

  @override
  String get appearanceGlobalSnippetsHint =>
      'Shown from the Snip key-row menu on every machine.';

  @override
  String get appearanceAddRow => 'Add row';

  @override
  String get appearanceEditKeys => 'Edit keys';

  @override
  String get appearanceRemoveRow => 'Remove row';

  @override
  String get appearanceCustom => 'Custom';

  @override
  String get appearanceCustomKey => 'Custom key';

  @override
  String get appearanceSendEnterAfterText => 'Send Enter after text';

  @override
  String get appearanceControlKey => 'Control key';

  @override
  String get appearanceKeyPassphraseHint =>
      'Leave empty for an unencrypted key.';

  @override
  String get appearanceTmuxPrefixHint =>
      'Used by the Tmux and Tmux+ key-row buttons.';

  @override
  String get appearanceTmuxSessionHint =>
      'Attach to the named tmux session, or create it if needed.';

  @override
  String get appearanceTmuxAutostart =>
      'Conduit attaches to this session, or creates it.';

  @override
  String get appearanceDisableRunOnConnect => 'Disable run on connect';

  @override
  String get appearanceRunOnConnect => 'Run on connect';

  @override
  String appearanceKeyRowsCount(String count) {
    return 'Key Rows ($count)';
  }

  @override
  String appearanceRowLabel(String index) {
    return 'Row $index';
  }

  @override
  String appearanceRowKeysTitle(String index) {
    return 'Row $index Keys';
  }

  @override
  String appearanceKeyCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count keys',
      one: '1 key',
    );
    return '$_temp0';
  }

  @override
  String get paletteCaptionCatppuccin => 'Mocha, calm and polished';

  @override
  String get paletteCaptionTokyoNight => 'Deep blue IDE focus';

  @override
  String get paletteCaptionDracula => 'High-contrast neon classic';

  @override
  String get paletteCaptionNord => 'Arctic, restrained, cool';

  @override
  String get paletteCaptionGruvbox => 'Warm retro terminal energy';

  @override
  String get paletteCaptionSolarized => 'Balanced low-glare contrast';

  @override
  String get paletteCaptionOneDark => 'Atom-inspired editor calm';

  @override
  String get paletteCaptionRosePine => 'Muted dusk, soft contrast';

  @override
  String get paletteCaptionEverforest => 'Green low-glare woodland';

  @override
  String get paletteCaptionMonokai => 'Punchy classic code color';

  @override
  String get paletteCaptionAyuDark => 'Warm amber night coding';

  @override
  String get paletteCaptionKanagawa => 'Muted ink and wave tones';

  @override
  String get paletteCaptionNightOwl => 'Crisp blue late-night focus';

  @override
  String get paletteCaptionPalenight => 'Soft violet editor glow';

  @override
  String get paletteCaptionSynthwave => 'Electric retro terminal pop';

  @override
  String get paletteCaptionGithubDark => 'Quiet modern code contrast';

  @override
  String get hostsTrustedKeys => 'Trusted keys';

  @override
  String get hostsLock => 'Lock';

  @override
  String get hostsStatSaved => 'Saved';

  @override
  String get hostsStatLiveSessions => 'Live sessions';

  @override
  String get hostsResumeSessions => 'Resume sessions';

  @override
  String get hostsSavedMachines => 'Saved machines';

  @override
  String get hostsSavedMachinesHint =>
      'SSH and Mosh connections you have saved.';

  @override
  String get hostsSortMachines => 'Sort machines';

  @override
  String get hostsErrorTitle => 'Something went wrong';

  @override
  String get hostsEmptyTitle => 'No saved machines yet';

  @override
  String get commonNoMatches => 'No matches';

  @override
  String get commonNoMatchesHint => 'Try a different search or clear filters.';

  @override
  String get hostsPickMachine => 'Pick a machine to spin up a new tab.';

  @override
  String get hostsGrantFileAccess =>
      'Grant file access, then open the shell again.';

  @override
  String get hostsDuplicateTitle => 'Duplicate machine';

  @override
  String get hostsDuplicateBody =>
      'Copy the saved password and key material into the new machine?';

  @override
  String get hostsDuplicateWithoutSecrets => 'Without secrets';

  @override
  String get hostsDuplicateWithSecrets => 'Copy secrets';

  @override
  String get hostsDeleteTitle => 'Delete machine?';

  @override
  String hostsCopiedEndpoint(String endpoint) {
    return 'Copied $endpoint';
  }

  @override
  String hostsDeleteBody(String name) {
    return 'Conduit will forget “$name”.';
  }

  @override
  String hostsActiveSessionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count active',
      one: '1 active',
    );
    return '$_temp0';
  }

  @override
  String get hostFormEditTitle => 'Edit machine';

  @override
  String get hostFormNewTitle => 'New machine';

  @override
  String get hostFormEditSubtitle =>
      'Update connection details and credentials.';

  @override
  String get hostFormNewSubtitle => 'Connection profile and credentials.';

  @override
  String get hostFormSave => 'Save changes';

  @override
  String get hostFormAdd => 'Add machine';

  @override
  String get hostFormStoredLocally =>
      'Stored on-device only • never synced to the cloud';

  @override
  String get hostFormRenameHardwareKey => 'Rename hardware key';

  @override
  String hostFormRemoveHardwareKeyTitle(String label) {
    return 'Remove \"$label\"?';
  }

  @override
  String get hostFormRemoveHardwareKeyBody =>
      'The stub is removed from this host. Your security key and the server are not affected.';

  @override
  String get hostFormReplaceKeyTitle => 'Replace key?';

  @override
  String get hostFormReplaceKeyBody =>
      'The private key field already has content. Replace it?';

  @override
  String get hostFormGenerateKeyTitle => 'Generate Ed25519 key';

  @override
  String get hostFormGenerateKeyBody =>
      'A new key pair is created on this device. The public key is shown next so you can add it to the server.';

  @override
  String get hostFormKeyLabelHint => 'Shown as the key comment.';

  @override
  String get hostFormKeyPassphrase => 'Passphrase (optional)';

  @override
  String get hostFormKeyPassphraseHint =>
      'Encrypts the private key. Leave empty for none.';

  @override
  String get hostFormOfferTempKey => 'Offer temporary public key';

  @override
  String get hostFormOfferTempKeyHint =>
      'Helps servers that authenticate externally but still expect a public-key login attempt.';

  @override
  String get hostFormPrivateKey => 'Private key';

  @override
  String get hostFormKeyPassphraseLabel => 'Key passphrase';

  @override
  String get hostFormPrivateKeyHint =>
      'Use a normal SSH private key. If the key is encrypted, enter its passphrase below.';

  @override
  String get hostFormPrivateKeyEmpty => 'Import, paste, or generate a key.';

  @override
  String get hostFormForwardAgent => 'Forward SSH agent';

  @override
  String get hostFormForwardAgentHint =>
      'Let hosts you connect to use this key to authenticate onward. Hardware keys prompt for a touch on each use.';

  @override
  String get hostFormConnectionTimeout => 'Connection timeout';

  @override
  String get hostFormConnectWithMosh => 'Connect with Mosh';

  @override
  String get hostFormConnectWithMoshHint =>
      'Roaming UDP session over SSH. Requires mosh-server on the host and open UDP ports.';

  @override
  String get hostFormMoshLocale => 'Mosh locale';

  @override
  String get hostFormMoshLocaleHint =>
      'Must be a UTF-8 locale installed on the host.';

  @override
  String get hostFormMoshPorts => 'Mosh UDP ports';

  @override
  String get hostFormMoshPortsHint =>
      'Port or range like 60000:61000. Empty uses 60001:60999.';

  @override
  String get hostFormPredictiveEcho => 'Predictive echo (experimental)';

  @override
  String get hostFormPredictiveEchoHint =>
      'Show local input previews on laggy Mosh sessions.';

  @override
  String get hostFormStartTmux => 'Start tmux on connect';

  @override
  String get hostFormTmuxSession => 'Tmux session name';

  @override
  String get hostFormTmuxDirectory => 'Tmux start directory';

  @override
  String get hostFormTmuxPrefix => 'Tmux prefix';

  @override
  String get hostFormTmuxDirectoryHint =>
      'Used when a new tmux session is created. An existing tmux session keeps its directory.';

  @override
  String get hostFormHostSnippets => 'Host snippets';

  @override
  String get hostFormHostSnippetsHint =>
      'Shown in the Snip key-row menu for this machine. Hidden snippets are useful for passwords or other secrets.';

  @override
  String get authPasswordHint => 'Use the account password for SSH login.';

  @override
  String get authPasswordDetail => 'Use this for password-only SSH login.';

  @override
  String get authHardwareKey => 'Hardware key';

  @override
  String get authPrivateKeyHint => 'Use a PEM or OpenSSH private key.';

  @override
  String get authHardwareKeyHint =>
      'Use one or more security keys over USB or NFC.';

  @override
  String get authExternal => 'External';

  @override
  String get authExternalHint =>
      'Use this when authentication is handled outside Conduit, without storing a password or private key in the app.';

  @override
  String get authHardwareKeyDetail =>
      'Add the OpenSSH *_sk key stub for each security key you own. When you connect, Conduit asks whichever key you present to sign over USB or NFC.';

  @override
  String get hardwareKeysTitle => 'Hardware keys';

  @override
  String get hardwareKeysEmpty =>
      'No hardware keys yet. Add the OpenSSH *_sk stub for each security key you want to use with this host. Any of them will unlock the connection.';

  @override
  String hardwareKeysCount(String count) {
    return 'Hardware keys ($count)';
  }

  @override
  String get hardwareKeysOptions => 'Key options';

  @override
  String get hostCardOptions => 'Machine options';

  @override
  String get hostCardDuplicate => 'Duplicate';

  @override
  String get hostCardCopyAddress => 'Copy address';

  @override
  String get hostCardViewPublicKey => 'View public key';

  @override
  String get hostKeyPassphraseMismatch =>
      'That passphrase did not match this key.';

  @override
  String get hostsSearchHint => 'Search machines, hosts, tags…';

  @override
  String get hostFormTagsHint =>
      'production, edge, eu-west…  press enter to add';

  @override
  String get hostFormAddTag => 'Add tag';

  @override
  String publicKeyCreatedBody(String algorithm) {
    return 'A new $algorithm key is saved on this device. Add the public key below to the server, then connect.';
  }

  @override
  String get publicKeyInstructions =>
      'Add this line to ~/.ssh/authorized_keys on the host you want to reach.';

  @override
  String get publicKeySave => 'Save .pub';

  @override
  String get publicKeyCopied => 'Public key copied to clipboard';

  @override
  String get publicKeySaved => 'Public key saved';

  @override
  String get publicKeySaveFailed => 'Could not save the public key';

  @override
  String get publicKeyPrivateNote =>
      'The private half never leaves this device. It is held in platform secure storage with your other credentials.';

  @override
  String get addHardwareKeyTitle => 'Add hardware key';

  @override
  String get addHardwareKeyBody =>
      'Import or paste the OpenSSH *_sk stub that ssh-keygen created for this security key. The stub only points to the key; the private part never leaves the hardware.';

  @override
  String get addHardwareKeyStubLabel => 'OpenSSH hardware key stub';

  @override
  String get addHardwareKeyStubHint =>
      'Import or paste the id_ed25519_sk or id_ecdsa_sk file.';

  @override
  String get addHardwareKeyPassphrase => 'Stub passphrase';

  @override
  String get addHardwareKeyPassphraseHint => 'This stub file is encrypted.';

  @override
  String get addHardwareKeyLabelHint =>
      'Shown when Conduit asks for this key, e.g. \"5C work\" or \"NFC backup\".';

  @override
  String get addHardwareKeySubmit => 'Add key';

  @override
  String get terminalRecallLine => 'Recall a sent line';

  @override
  String get terminalComposeHint => 'Compose a line, Enter to send …';

  @override
  String get terminalNoSessions => 'No sessions open';

  @override
  String get terminalBackToMachines => 'Back to machines';

  @override
  String get terminalFunctionKeys => 'Function keys';

  @override
  String get terminalTmuxActions => 'Tmux actions';

  @override
  String get terminalNoSnippets => 'No snippets saved';

  @override
  String get commonWorking => 'Working…';

  @override
  String get trustedKeysTitle => 'Trusted host keys';

  @override
  String get trustedKeysSubtitle => 'Servers Conduit has connected to before.';

  @override
  String get trustedKeysEmpty =>
      'Connect to a host and you’ll be asked to trust its key - the fingerprint lands here.';

  @override
  String get trustedKeysEmptyTitle => 'No trusted keys yet';

  @override
  String get trustedKeysForgetTitle => 'Forget trusted key?';

  @override
  String get hostKeyPreviouslyTrusted => 'Previously trusted:';

  @override
  String trustedKeysForgetBody(String host, String port) {
    return 'Conduit will prompt again the next time you connect to $host:$port.';
  }

  @override
  String get hostKeyChangedTitle => 'Host key changed';

  @override
  String get hostKeyTrustTitle => 'Trust this host?';

  @override
  String get hostKeyTrustNew => 'Trust new key';

  @override
  String hostKeyUnknownBody(String host, String port) {
    return 'Conduit has not connected to $host:$port before. Verify the fingerprint matches the one reported by the server (e.g. `ssh-keygen -E md5 -lf <key>`).';
  }

  @override
  String hostKeyMismatchBody(String host, String port) {
    return 'The server at $host:$port is presenting a different key than the one you previously trusted. This can indicate a man-in-the-middle attack, or the server may have been legitimately rekeyed.';
  }

  @override
  String get keyChecking => 'Checking key…';

  @override
  String get keyCheckingPassphrase => 'Checking passphrase…';

  @override
  String get keySectionTitle => 'Section key';

  @override
  String get localShellReadyBody =>
      'Open a shell, or run several sessions side by side.';

  @override
  String localShellUpdateHint(String command) {
    return 'Update packages from inside the shell with  $command . ';
  }

  @override
  String get sftpOpening => 'Opening files…';

  @override
  String get sftpOpenFailed => 'Could not open files';

  @override
  String get sftpEmptyTitle => 'Empty folder';

  @override
  String get sftpEmptyBody =>
      'Upload a file or create a folder to get started.';

  @override
  String get sftpNewFolder => 'New folder';

  @override
  String get sftpFolderName => 'Folder name';

  @override
  String get sftpNewName => 'New name';

  @override
  String get sftpItemOptions => 'Item options';

  @override
  String get sftpSearchFolder => 'Search folder';

  @override
  String get sftpClearSearch => 'Clear search';

  @override
  String get sftpSortFiles => 'Sort files';

  @override
  String get sftpSortModified => 'Modified';

  @override
  String get sftpSortSize => 'Size';

  @override
  String get sftpSortType => 'Type';

  @override
  String get sftpKindFolder => 'folder';

  @override
  String get sftpKindFile => 'file';

  @override
  String get sftpUploading => 'Uploading';

  @override
  String get sftpDownloading => 'Downloading';

  @override
  String sftpDeleteBody(String name) {
    return '“$name” will be removed from the server.';
  }

  @override
  String sftpItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String sftpFolderCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count folders',
      one: '1 folder',
    );
    return '$_temp0';
  }

  @override
  String sftpFileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return '$_temp0';
  }

  @override
  String get snippetAdd => 'Add snippet';

  @override
  String get snippetEdit => 'Edit snippet';

  @override
  String get snippetCommandLabel => 'Command or text';

  @override
  String get snippetSendEnter => 'Send Enter after snippet';

  @override
  String get snippetHidden => 'Hidden snippet';

  @override
  String get snippetHiddenHint => 'Use for passwords or other secrets.';

  @override
  String get snippetEmpty => 'No snippets saved.';

  @override
  String get backupBody =>
      'Backups include appearance, terminal settings, saved machines, order, and trusted host keys.';

  @override
  String get backupExportPlain => 'Export without secrets';

  @override
  String get backupExportPlainHint =>
      'Passwords and private key material are removed.';

  @override
  String get backupExportEncrypted => 'Export encrypted with secrets';

  @override
  String get backupExportEncryptedHint =>
      'Credentials are protected with a backup password.';

  @override
  String get backupImport => 'Import backup';

  @override
  String get backupImportHint =>
      'Imported machines are merged into this device.';

  @override
  String get backupPassword => 'Backup password';

  @override
  String get backupEnterPassword => 'Enter password';

  @override
  String get backupConfirmPassword => 'Confirm password';

  @override
  String get backupShowPassword => 'Show password';

  @override
  String get backupHidePassword => 'Hide password';

  @override
  String get backupPasswordHint =>
      'Use at least 12 characters and at least three of lowercase, uppercase, numbers, and symbols.';

  @override
  String get lockSubtitle => 'Private SSH workspaces, protected locally.';

  @override
  String get lockFooter => 'Encrypted SSH sessions • zero cloud sync';

  @override
  String get lockContinueWithoutAuth => 'Continue without auth';

  @override
  String get localShellNew => 'New local shell';

  @override
  String get localShellRenameTitle => 'Rename shell';

  @override
  String get localShellNewSession => 'New session';

  @override
  String get localShellIncompleteTitle => 'Setup is incomplete';

  @override
  String get localShellResumeInstall => 'Resume install';

  @override
  String get localShellChecking => 'Checking local shells…';

  @override
  String get localShellHint => 'Run commands locally, no server required.';

  @override
  String get localShellSetUp => 'Set up a local shell';

  @override
  String get localShellNameHint =>
      'Shown on the home screen and terminal tabs.';

  @override
  String get localShellSetupTitle => 'Run Linux on this phone';

  @override
  String get localShellSetupBody =>
      'A full Linux userland running locally through proot - no server, no root. Pick a distribution; you can set up as many shells as you like, including several of the same distribution.';

  @override
  String get localShellSetupCaption => 'Arch, Debian, Ubuntu, Alpine and more';

  @override
  String get localShellInstallHint =>
      'The image downloads once and unpacks on your device. Wi-Fi recommended.';

  @override
  String get localShellLicensesBody =>
      'The local shell uses proot and root filesystem images packaged through Termux, maintained by their upstream distributions. Conduit redistributes the bundled tools under their own open-source licenses.';

  @override
  String get localShellStageUnpacking =>
      'Unpacking root filesystem… (this can take a few minutes)';

  @override
  String get localShellStageConfiguring => 'Running first-time setup…';

  @override
  String localShellStageDownloading(String distro) {
    return 'Downloading $distro…';
  }

  @override
  String localShellReinstallTitle(String name) {
    return 'Reinstall $name?';
  }

  @override
  String localShellRemoveTitle(String name) {
    return 'Remove $name?';
  }

  @override
  String localShellReadyTitle(String distro) {
    return '$distro is ready';
  }

  @override
  String localShellSettingUp(String distro) {
    return 'Setting up $distro';
  }

  @override
  String localShellRemoveBody(String name) {
    return 'This deletes this environment and everything in it. Any open $name tabs will be closed first. Other shells are not affected.';
  }

  @override
  String localShellReinstallBody(String name) {
    return 'This wipes this environment - including any packages you installed - and downloads a fresh image. Any open $name tabs will be closed first.';
  }

  @override
  String localShellInstallWithSize(String size) {
    return 'Install · $size';
  }

  @override
  String localShellDownloadWithSize(String size) {
    return 'Download $size';
  }

  @override
  String get commonUnknown => 'unknown';
}
