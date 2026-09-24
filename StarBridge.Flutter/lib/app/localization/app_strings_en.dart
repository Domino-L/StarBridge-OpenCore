import 'general_settings_strings.dart';
import 'notification_settings_strings.dart';
import 'notification_audio_strings.dart';
import 'profile_settings_strings.dart';
import 'official_fleet_strings.dart';
import 'party_rooms_strings.dart';
import 'friends_strings.dart';
import 'communities_strings.dart';
import 'settings_capability_strings.dart';
import 'sync_privacy_strings.dart';
import 'local_privacy_strings.dart';
import 'privacy_scope_settings_strings.dart';
import 'legacy_migration_strings.dart';
import 'local_profile_strings.dart';
import 'startup_strings.dart';
import 'gameplay_time_strings.dart';
import 'game_log_strings.dart';
import 'help_support_strings.dart';
import 'overlay_settings_strings.dart';
import 'home_strings.dart';

const englishAppStrings = <String, String>{
  'app.name': 'StarBridge',
  'navigation.home': 'Home',
  'navigation.home.description': 'Current state and next steps',
  'navigation.rooms': 'Rooms',
  'navigation.rooms.description': 'Casual matchmaking and instant play',
  'navigation.operations': 'Operations',
  'navigation.operations.description': 'Planned organization and fleet work',
  'navigation.officialFleet': 'Main fleet',
  'navigation.officialFleet.description': 'RSI main fleet workspace',
  'navigation.marketplace': 'Marketplace',
  'navigation.marketplace.description':
      'Trading and services (not in the initial release)',
  'navigation.communities': 'Communities',
  'navigation.communities.description': 'Long-term cross-fleet organizations',
  'navigation.hangar': 'My Hangar',
  'navigation.hangar.description': 'Ships, loadouts, and sharing',
  'navigation.overlay': 'Overlay',
  'navigation.overlay.description': 'In-game scenes and layout',
  'navigation.tools': 'Tools',
  'navigation.tools.description':
      'Personal utilities (not in the initial release)',
  'navigation.settings': 'Settings',
  'navigation.settings.description': 'Appearance, language, and preferences',
  'navigation.friends': 'Friends',
  'navigation.friends.description': 'Friends, messages, and recent players',
  'navigation.notifications': 'Notifications',
  'navigation.notifications.description': 'System and collaboration updates',
  'navigation.account': 'Account',
  'navigation.account.description': 'Identity and profile',
  'navigation.profile': 'Profile',
  'navigation.profile.description': 'Public identity and profile showcase',
  'navigation.personal': 'Personal',
  'deferredFeature.title': 'This area is not available yet',
  'deferredFeature.marketplace.body': 'Trading and service features will be connected after the Flutter client is stable. The initial release keeps this route reserved.',
  'deferredFeature.tools.body': 'Personal utilities will be introduced in later stages. The initial release does not expose simulated controls or placeholder actions.',
  'top.overlayScene': 'Overlay scene',
  'top.friends': 'Friends',
  'top.notifications': 'Notifications',
  'top.account': 'Account',
  'exampleScene.open': 'Open example scene',
  'exampleScene.compact': 'Example',
  'exampleScene.exit': 'Exit example',
  'exampleScene.notice.title': 'Example scene is active',
  'exampleScene.notice.body': 'Demo accounts and sample data are shown only for interface review. Real accounts are not read or changed.',
  ...englishProfileSettingsStrings,
  ...englishGeneralSettingsStrings,
  ...englishNotificationSettingsStrings,
  ...audioEn,
  ...englishSettingsCapabilityStrings,
  ...englishSyncPrivacyStrings,
  ...englishLocalPrivacyStrings,
  ...englishPrivacyScopeSettingsStrings,
  ...englishOfficialFleetStrings,
  ...englishPartyRoomsStrings,
  ...friendsEn,
  ...communitiesEn,
  ...englishLegacyMigrationStrings,
  ...englishLocalProfileStrings,
  ...englishStartupStrings,
  ...gameplayTimeEn,
  ...gameLogEn,
  ...helpSupportEnUs,
  ...overlaySettingsEn,
  ...homeEn,
  'account.notSignedIn': 'Not signed in',
  'account.loading': 'Reading account state…',
  'account.signedOut.title': 'Continue with your SCM account',
  'account.signedOut.body': 'Authorization completes in your system browser. Sign-in credentials stay in StarBridge\'s local account service and are never exposed to the interface.',
  'account.credentialUnavailable.title': 'SCM is temporarily unavailable',
  'account.credentialUnavailable.body': 'Your sign-in credential is still stored securely on this PC, but StarBridge cannot reach SCM right now. The credential will not be deleted, and the old account will not be enabled automatically.',
  'account.credentialUnavailable.retry': 'Check connection again',
  'account.credentialUnavailable.checking':
      'Checking the SCM connection again…',
  'account.reauthorization.title': 'Reconnect your SCM account',
  'account.reauthorization.body': 'SCM rejected or revoked the previous credential stored on this PC. StarBridge stopped using the invalid credential; account data and sensitive actions remain paused until you authorize again.',
  'account.reauthorization.action': 'Reconnect SCM account',
  'account.login.action': 'Sign in with SCM',
  'account.login.menu': 'Sign in',
  'account.login.waiting': 'Complete authorization in your browser. StarBridge will continue when you return.',
  'account.login.cancel': 'Cancel sign-in',
  'account.login.cancelling': 'Cancelling sign-in…',
  'account.login.cancelled':
      'Sign-in was cancelled. You can retry at any time.',
  'account.login.success': 'Your SCM account is connected.',
  'account.action.refresh': 'Refresh account profile',
  'account.action.retry': 'Retry',
  'account.value.notSet': 'Not set',
  'account.email.notShared': 'SCM did not provide an email address',
  'account.source.live': 'Current from SCM',
  'account.source.cached': 'Offline cache',
  'account.source.unavailable': 'Profile unavailable',
  'account.preferences.title': 'Profile preferences',
  'account.preferences.body': 'Only SCM-supported language preferences and standard time zones are synchronized. The app interface language remains independent.',
  'account.preferences.locale': 'SCM language preference',
  'account.preferences.timeZone': 'SCM time zone',
  'account.preferences.save': 'Save changes',
  'account.preferences.draft': 'Unsaved changes are kept when switching pages and cleared when you sign out.',
  'account.preferences.discard': 'Discard changes',
  'account.preferences.saving': 'Saving…',
  'account.preferences.authorizing':
      'Complete authorization in your browser to continue saving.',
  'account.preferences.cancelled':
      'Saving cancelled. Your choices are still on this page.',
  'account.preferences.readOnly':
      'Profile preferences are read-only in this version.',
  'account.action.unavailable': 'This action is not available in this version.',
  'account.cache.failed':
      'Could not clear the profile cache. Please try again.',
  'account.preferences.cachedReadOnly': 'This is an offline cached profile. Reconnect and load the current SCM profile before editing.',
  'account.preferences.noChanges': 'There are no profile changes to save.',
  'account.preferences.saved':
      'Profile preferences were saved and read back from SCM.',
  'account.locale.zhCN': 'Simplified Chinese (zh-CN)',
  'account.locale.enUS': 'English (en-US)',
  'account.identity.title': 'RSI game identity',
  'account.identity.handle': 'Verified Handle',
  'account.identity.match': 'Your RSI game identity is verified. StarBridge checks it again whenever you enter the game.',
  'account.identity.mismatch': 'The current game identity does not match the SCM account record. Actions that require game identity confirmation are paused.',
  'account.identity.awaiting': 'No identity has been recognized from the current game session. This does not unlink your verified identity.',
  'account.identity.reverify':
      'SCM requires the RSI identity to be verified again.',
  'account.identity.revoked': 'RSI identity verification was revoked.',
  'account.identity.unknown': 'RSI identity status is temporarily unavailable.',
  'account.identity.writesAllowed':
      'Game identity is confirmed. Related actions are available.',
  'account.identity.writesBlocked': 'Actions that require game identity confirmation are paused. Profile viewing and local features remain available.',
  'account.session.title': 'Session and local cache',
  'account.session.body': 'The cache contains only profile details that can be displayed. Sign-in credentials and permission information are not stored.',
  'account.cache.clear': 'Clear profile cache',
  'account.cache.clearing': 'Clearing cache…',
  'account.cache.cleared':
      'The local profile cache for this account was cleared.',
  'account.logout.action': 'Sign out',
  'account.logout.signingOut': 'Signing out…',
  'account.logout.success': 'You are fully signed out of SCM.',
  'account.compatibility.title': 'Legacy data compatibility',
  'account.recovery.title': 'Recover legacy account password',
  'account.legacyLogin.title': 'Legacy StarBridge sign-in',
  'account.legacyLogin.body': 'Sign in with your existing email and password. Sign-in credentials are encrypted on this device; your password is not saved.',
  'account.legacySession.status': 'Legacy account signed in',
  'account.legacySession.body': 'You are using your existing StarBridge account. SCM authorization is optional and separate.',
  'account.legacySession.scmFailed': 'SCM authorization did not complete. Your existing account remains signed in. You can try authorizing again when needed.',
  'account.legacySession.unavailable': 'Unable to verify this session right now. Your credentials are retained. Try refreshing later.',
  'account.legacySession.refresh': 'Refresh account status',
  'account.legacyLogin.password': 'Legacy password',
  'account.legacyLogin.submit': 'Sign in to legacy account',
  'account.legacyLogin.skip': 'Continue browsing',
  'account.legacyLogin.retry': 'Try again later',
  'account.legacyLogin.verified':
      'Legacy account verified and credentials saved securely.',
  'account.legacyLogin.rejected':
      'Incorrect email or password. Check them and try again.',
  'account.legacyLogin.invalidInput': 'Enter your legacy email and password.',
  'account.legacyLogin.throttled':
      'Too many attempts. Wait for the countdown before trying again.',
  'account.legacyLogin.unavailable':
      'Unable to confirm sign-in. Try again later.',
  'account.legacyLogin.storageUnavailable': 'Account verified, but credentials could not be saved. Check local storage and try again.',
  'account.legacyLogin.busy':
      'Another account operation is in progress. Try again shortly.',
  'account.legacyLogin.sessionChanged': 'Account status changed. Close this window and check the current account.',
  'account.legacyLogin.cancelled':
      'Stopped waiting. Credentials already saved are not removed.',
  'account.recovery.body': 'Reset only your old StarBridge password, not your SCM password. Use the email registered to your legacy account.',
  'account.recovery.email': 'Legacy account email',
  'account.recovery.send': 'Send verification code',
  'account.recovery.resend': 'Send again',
  'account.recovery.code': 'Six-digit email code',
  'account.recovery.password': 'New password',
  'account.recovery.passwordHint': '8–128 characters',
  'account.recovery.confirmPassword': 'Repeat new password',
  'account.recovery.submit': 'Reset legacy password',
  'account.recovery.close': 'Close',
  'account.recovery.codeRequested': 'Request accepted. Check your legacy account inbox and spam folder. Verification codes are valid for 10 minutes.',
  'account.recovery.reset': 'Password reset. Use your new password next time you verify the legacy account.',
  'account.recovery.invalidEmail': 'Enter a valid legacy account email.',
  'account.recovery.invalidCode':
      'The code is incorrect or expired. Check it or request a new one.',
  'account.recovery.invalidPassword':
      'The new password must have 8–128 characters.',
  'account.recovery.commonPassword':
      'This password is too common. Choose a longer, unique password.',
  'account.recovery.mismatch': 'The passwords do not match.',
  'account.recovery.throttled':
      'Too many requests. Wait for the countdown before trying again.',
  'account.recovery.unavailable': 'The result could not be confirmed. Try again later. If you just submitted a reset, you can also try verifying the old account with your new password.',
  'account.recovery.busy': 'An operation is already in progress. Please wait.',
  'account.recovery.cancelled': 'Stopped waiting. Closing this window does not undo a submitted password reset.',
  'account.compatibility.body':
      'Check the legacy account link and compatibility service connection.',
  'account.compatibility.unavailable':
      'Legacy data compatibility has not been read yet.',
  'account.compatibility.unlinked': 'This SCM account is not linked to a legacy account. Registration is not available in this version.',
  'account.compatibility.linkedRelayPending': 'The old account is linked, but legacy fleets, friends, chat, and other data channels are not connected yet.',
  'account.compatibility.ready':
      'The legacy account session has been verified.',
  'account.compatibility.refreshAction': 'Refresh compatibility status',
  'account.compatibility.relayUnavailable': 'The old account is linked, but the legacy data service is temporarily unavailable.',
  'account.compatibility.authorizationRequired': 'The legacy data service rejected the current SCM authorization. Sign in again and retry.',
  'account.compatibility.accountMismatch': 'The SCM-linked identity does not match the legacy account, so data access was blocked.',
  'account.compatibility.unknown':
      'The legacy-data link could not be confirmed. Refresh and try again.',
  'account.compatibility.retryAction': 'Retry legacy connection',
  'account.compatibility.savedCredential': 'A protected migration credential is available on this PC. It will be removed after a successful link.',
  'account.compatibility.continueSaved': 'Continue legacy-data link',
  'account.compatibility.verifyManually': 'Verify with account password',
  'account.compatibility.linkAction': 'Link old account',
  'account.compatibility.createAction': 'Create compatibility profile',
  'account.compatibility.cancel': 'Cancel current operation',
  'account.compatibility.cancelling': 'Cancelling…',
  'account.compatibility.cancelled': 'Stopped waiting. If the link was already submitted, refresh to check its status.',
  'account.compatibility.linked':
      'The old account is linked and SCM confirmed the result.',
  'account.compatibility.created':
      'The compatibility profile was created and SCM confirmed the result.',
  'account.compatibility.dialog.title': 'Link an old StarBridge account',
  'account.compatibility.dialog.body': 'Verify an existing account and link it to your current SCM account. Browser authorization may follow. These credentials will not be saved.',
  'account.compatibility.dialog.accountName': 'Old account name or email',
  'account.compatibility.dialog.password': 'Old account password',
  'account.compatibility.dialog.required': 'This field is required',
  'account.compatibility.dialog.security': 'The password is used only for this verification and is sent through the local Native Host. It is not saved, logged, or returned to the interface.',
  'account.compatibility.dialog.cancel': 'Cancel',
  'account.compatibility.dialog.submit': 'Verify and link',
  'account.compatibility.dialog.close': 'Close account-link window',
  'account.compatibility.createDialog.title':
      'Create a legacy compatibility profile?',
  'account.compatibility.createDialog.body': 'New users need this internal profile for legacy fleet, friend, and chat capabilities. It cannot recover any old-account history.',
  'account.compatibility.createDialog.confirm': 'Create compatibility profile',
  'account.error.hostUnavailable': 'The local account service is temporarily unavailable, so account state cannot be read.',
  'account.error.timeout':
      'The operation timed out. Refresh the status and try again.',
  'account.error.sessionChanged':
      'The account session changed, so the old result was discarded.',
  'account.error.environmentNotEnabled': 'This client currently supports only the local integration environment and cannot connect to the production SCM website yet.',
  'account.error.reauthorizationRequired':
      'The SCM session must be authorized again.',
  'account.error.writeForbidden':
      'This account cannot edit profile preferences.',
  'account.error.writeConflict':
      'The profile changed elsewhere. Reload it before saving again.',
  'account.error.directoryUnavailable': 'The SCM time-zone directory is unavailable. No profile fields were changed.',
  'account.error.invalidResponse': 'The local account service returned incompatible profile data. Processing stopped safely.',
  'account.error.writeRejected':
      'The profile change is invalid and was not sent.',
  'account.error.unavailable':
      'Account data is temporarily unavailable. Please try again.',
  'account.error.compatibilityUnavailable':
      'Legacy data compatibility is temporarily unavailable.',
  'account.error.compatibilityWriteUnavailable': 'The legacy-data operation could not be completed. An unknown result was not treated as success.',
  'account.error.compatibilityConflict': 'That old account or compatibility profile is already linked to another SCM account. Nothing was changed.',
  'account.error.compatibilityExistingLinkMismatch': 'This SCM account already has a different old-account link. Check the account before continuing.',
  'account.error.legacyCredentialsRequired': 'No migration credential is available. Enter the old account name or email and password.',
  'account.error.legacyCredentialsRejected':
      'The old account name or password was rejected. No link was created.',
  'account.error.operationNotInProgress':
      'There is no account operation to cancel.',
  'overlay.scene.default': 'Default scene',
  'overlay.scene.room': 'Room scene',
  'overlay.scene.operation': 'Operation scene',
  'overlay.hostUnavailable': 'Native Host is unavailable',
  'overlay.capabilityUnavailable':
      'Overlay scenes will be available when the capability is connected',
  'status.host': 'Host',
  'status.game': 'Game',
  'status.identity': 'Identity',
  'status.network': 'Network',
  'status.connected': 'Connected',
  'status.disconnected': 'Disconnected',
  'status.notRunning': 'Not running',
  'status.unconfirmed': 'Unconfirmed',
  'status.confirmed': 'Confirmed',
  'status.waitingForHost': 'Waiting for Host',
  'status.normal': 'Normal',
  'presence.online': 'App online',
  'presence.away': 'Away',
  'presence.inGame': 'In game',
  'presence.notInGame': 'Game not running',
  'presence.gameUnknown': 'Game status unknown',
  'presence.unknown': 'Connection unconfirmed',
  'presence.offline': 'Offline',
  'sync.current': 'Current',
  'sync.hostUnavailable': 'Waiting for Host sync',
  'sync.cached': 'Using offline cache',
  'sync.issue': 'Sync needs attention',
  'connection.host.disconnected.title': 'Client connection interrupted',
  'connection.host.disconnected.detail':
      'Native Host is unavailable. StarBridge is reconnecting automatically.',
  'connection.account.unavailable.title': 'Cannot reach the server',
  'connection.account.unavailable.detail':
      'Online features are unavailable. Local features remain usable.',
  'connection.account.reauthorize.title': 'SCM sign-in needs attention',
  'connection.account.reauthorize.detail':
      'Sign in again to continue syncing account and fleet data.',
  'connection.account.cached.title': 'Using offline data',
  'connection.account.cached.detail':
      'The latest SCM data will load after the connection recovers.',
  'connection.account.limited.title': 'Some synchronization is unavailable',
  'connection.account.limited.detail': 'The operation did not finish. Existing data is preserved and can be retried.',
  'connection.account.actionFailed.title': 'Account action needs attention',
  'connection.relay.unavailable.title': 'Legacy data service unavailable',
  'connection.relay.unavailable.detail': 'Your SCM account and migrated features remain available. Legacy data and online collaboration are temporarily unavailable.',
  'connection.action.retryNow': 'Retry now',
  'connection.action.retrying': 'Retrying…',
  'window.minimize': 'Minimize',
  'window.maximize': 'Maximize',
  'window.restore': 'Restore',
  'window.close': 'Close',
};
