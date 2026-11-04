// DO NOT EDIT. This is code generated via package:intl/generate_localized.dart
// This is a library that provides messages for a en locale. All the
// messages from the main program should be duplicated here with the same
// function name.

// Ignore issues from commonly used lints in this file.
// ignore_for_file:unnecessary_brace_in_string_interps, unnecessary_new
// ignore_for_file:prefer_single_quotes,comment_references, directives_ordering
// ignore_for_file:annotate_overrides,prefer_generic_function_type_aliases
// ignore_for_file:unused_import, file_names, avoid_escaping_inner_quotes
// ignore_for_file:unnecessary_string_interpolations, unnecessary_string_escapes

import 'package:intl/intl.dart';
import 'package:intl/message_lookup_by_library.dart';

final messages = new MessageLookup();

typedef String MessageIfAbsent(String messageStr, List<dynamic> args);

class MessageLookup extends MessageLookupByLibrary {
  String get localeName => 'en';

  static String m0(count) =>
      "${Intl.plural(count, other: '${count} selected')}";

  static String m1(name) => "Added ${name} to local proxies";

  static String m2(name) => "${name} is already in local proxies";

  static String m3(count, skipped) =>
      "${count} to add, ${skipped} skipped as existing";

  static String m4(detail) => "Couldn\'t clear the data: ${detail}";

  static String m5(code) =>
      "Windows refused to run BiLoomCore.exe (error ${code}). An app control policy such as Smart App Control or AppLocker blocks unsigned programs; allow BiLoom in that policy or turn it off, then try again.";

  static String m6(name) =>
      "The app failed to finish launching twice in a row. To break the loop, the profile ${name} has been deselected and automatic setup was skipped. You can select it again at any time.";

  static String m7(url) => "Do you want to create a profile from ${url}?";

  static String m8(count, label) =>
      "${Intl.plural(count, one: '1 SUB-RULE rule was dropped, since custom profiles do not support sub-rules', other: '${label} SUB-RULE rules were dropped, since custom profiles do not support sub-rules')}";

  static String m9(message) => "The core cannot parse this proxy: ${message}";

  static String m10(proxy, target) =>
      "${proxy} dials through ${target}, which leads back to ${proxy}, so the dial loops";

  static String m11(name) =>
      "The name ${name} is already used by another proxy or proxy group";

  static String m12(path) =>
      "Proxy groups reference each other in a loop: ${path}";

  static String m13(name) =>
      "The empty fallback must be a proxy, but ${name} does not exist or is a proxy group";

  static String m14(name, message) =>
      "${name} is not a valid regex: ${message}";

  static String m15(name) => "The dialer proxy ${name} does not exist";

  static String m16(names) => "These proxy providers do not exist: ${names}";

  static String m17(names) =>
      "These proxies or policies do not exist: ${names}";

  static String m18(name) =>
      "${name} is a built-in policy name and cannot be used here";

  static String m19(count) =>
      "${count} items have problems, and applying this profile may fail";

  static String m20(count) =>
      "${Intl.plural(count, one: '1 day ago', other: '${count} days ago')}";

  static String m21(count) => "${Intl.plural(count, other: '${count}d ago')}";

  static String m22(label) =>
      "Are you sure you want to delete the selected ${label}?";

  static String m23(label) => "Are you sure you want to delete this ${label}?";

  static String m24(label) => "${label} details";

  static String m25(name) =>
      "Dialing through ${name} leads back to the proxy that uses it, so the connection was stopped";

  static String m26(label) => "${label} cannot be empty";

  static String m27(count) =>
      "${Intl.plural(count, one: '1 entry', other: '${count} entries')}";

  static String m28(label) => "${label} already exists";

  static String m29(count) => "${count} items failed";

  static String m30(label, message) => "${label}: ${message}";

  static String m31(name) => "${name} is already up to date";

  static String m32(name) => "${name} updated";

  static String m33(count) =>
      "${Intl.plural(count, one: '1 group', other: '${count} groups')}";

  static String m34(count) => "${count} timed out";

  static String m35(action) =>
      "Already used by “${action}”. Saving moves it here.";

  static String m36(modifiers) => "Include at least one of ${modifiers}";

  static String m37(count) =>
      "${Intl.plural(count, one: '1 hour ago', other: '${count} hours ago')}";

  static String m38(count) => "${Intl.plural(count, other: '${count}h ago')}";

  static String m39(count) =>
      "${Intl.plural(count, one: '1 hour', other: '${count} hours')}";

  static String m40(target) => "${target} is an invalid policy";

  static String m41(proxyName) => "${proxyName} is an invalid proxy";

  static String m42(providerName) =>
      "${providerName} is an invalid proxy provider";

  static String m43(ruleSet) => "${ruleSet} is an invalid rule set";

  static String m44(subRule) => "${subRule} is an invalid SUB_RULE";

  static String m45(count) =>
      "${Intl.plural(count, one: '1 item', other: '${count} items')}";

  static String m46(line, message) => "Line ${line}: ${message}";

  static String m47(appName) =>
      "1. Open System Settings > Privacy & Security\n2. Choose Location Services\n3. Find and check ${appName} in the list\n\nWhen you are done, return to the app to continue. Thank you for your cooperation.";

  static String m48(label, max) => "${label} must be at most ${max} characters";

  static String m49(size) => "Released ${size}";

  static String m50(count) =>
      "${Intl.plural(count, one: '1 minute ago', other: '${count} minutes ago')}";

  static String m51(count) => "${Intl.plural(count, other: '${count}m ago')}";

  static String m52(count) =>
      "${Intl.plural(count, one: '1 month ago', other: '${count} months ago')}";

  static String m53(count) => "${Intl.plural(count, other: '${count}mo ago')}";

  static String m54(code) =>
      "The server denied access (HTTP ${code}). The link may have expired, or the credentials are wrong";

  static String m55(code) => "The server rejected the request (HTTP ${code})";

  static String m56(code) =>
      "Nothing was found at this address (HTTP ${code}). Check that the URL is correct";

  static String m57(detail) => "Network request failed: ${detail}";

  static String m58(code) =>
      "The server ran into a problem (HTTP ${code}). Try again later";

  static String m59(label) => "No ${label} yet";

  static String m60(label, min, max) =>
      "${label} must be between ${min} and ${max}";

  static String m61(label) => "${label} must be a number";

  static String m62(label) => "${label} must be between 1024 and 49151";

  static String m63(port) => "Port ${port}";

  static String m64(days) =>
      "${Intl.plural(days, one: '1 day left', other: '${days} days left')}";

  static String m65(date, days) =>
      "Expires ${date}, ${Intl.plural(days, one: '1 day', other: '${days} days')} left";

  static String m66(time) => "Updated ${time}";

  static String m67(label, profiles) =>
      "${label} is still used by ${profiles}, which will not work properly once it is deleted. Are you sure you want to delete it?";

  static String m68(count, label) =>
      "${Intl.plural(count, one: '1 proxy', other: '${label} proxies')}";

  static String m69(name, count) => "${name} and others (${count} proxies)";

  static String m70(removed) =>
      "These proxies will be deleted: ${removed}. A line whose name changed counts as a new proxy, and custom profiles naming the deleted ones will flag them as missing. Apply anyway?";

  static String m71(removed, added) =>
      "These proxies will be deleted: ${removed}. These will be added: ${added}. A line whose name changed counts as a new proxy, and custom profiles naming the deleted ones will flag them as missing. Apply anyway?";

  static String m72(name) => "Proxy chain \"${name}\" created";

  static String m73(front) => "Front: ${front}";

  static String m74(name) => "Node \"${name}\" copied to the target profile";

  static String m75(name) =>
      "An identical node already exists in the target profile; reusing \"${name}\"";

  static String m76(front, exit) => "Active: ${front} → ${exit}";

  static String m77(label) =>
      "${label} is still named by rules, proxy groups, dialer proxies, DNS or NTP in this profile, which stop working once it is deleted. Are you sure you want to delete it?";

  static String m78(count, label) =>
      "${Intl.plural(count, one: '1 proxy group', other: '${label} proxy groups')}";

  static String m79(count) => "Fixed ${count} group(s)";

  static String m80(count) =>
      "Found ${count} relay proxy group(s). The core removed this type, so keeping it makes the entire profile fail to load. Change them to \"Selector\" now?";

  static String m81(count, label) =>
      "${Intl.plural(count, one: '1 rule', other: '${label} rules')}";

  static String m82(appName) => "${appName} (Safe mode)";

  static String m83(count) =>
      "${Intl.plural(count, one: '1 second', other: '${count} seconds')}";

  static String m84(count) => "${count} in effect";

  static String m85(count) => "${count} selected";

  static String m86(count) =>
      "${Intl.plural(count, one: '1 issue', other: '${count} issues')}";

  static String m87(count) =>
      "${Intl.plural(count, one: '1 setting', other: '${count} settings')}";

  static String m88(link) => "No proxy could be read from ${link}";

  static String m89(label) => "${label} must be a single item";

  static String m90(value) => "Peak ${value}";

  static String m91(value) => "Total ${value}";

  static String m92(transport) => "${transport} Headers";

  static String m93(label) => "${label} must be a URL";

  static String m94(count) =>
      "${Intl.plural(count, one: '1 year ago', other: '${count} years ago')}";

  static String m95(count) => "${Intl.plural(count, other: '${count}y ago')}";

  final messages = _notInlinedMessages(_notInlinedMessages);
  static Map<String, Function> _notInlinedMessages(_) => <String, Function>{
    "about": MessageLookupByLibrary.simpleMessage("About"),
    "accessControl": MessageLookupByLibrary.simpleMessage("Access control"),
    "accessControlAllowDesc": MessageLookupByLibrary.simpleMessage(
      "Only selected apps go through the VPN",
    ),
    "accessControlDesc": MessageLookupByLibrary.simpleMessage(
      "Access control picks which apps use the proxy.",
    ),
    "accessControlDisabledDesc": MessageLookupByLibrary.simpleMessage(
      "App access control is disabled",
    ),
    "accessControlNotAllowDesc": MessageLookupByLibrary.simpleMessage(
      "Selected apps are excluded from the VPN",
    ),
    "accessControlSelectedCount": m0,
    "accessControlSettings": MessageLookupByLibrary.simpleMessage(
      "Access control settings",
    ),
    "account": MessageLookupByLibrary.simpleMessage("Account"),
    "action": MessageLookupByLibrary.simpleMessage("Action"),
    "actionDelayTest": MessageLookupByLibrary.simpleMessage("Test all delays"),
    "actionDirectMode": MessageLookupByLibrary.simpleMessage("Direct mode"),
    "actionGlobalMode": MessageLookupByLibrary.simpleMessage("Global mode"),
    "actionMode": MessageLookupByLibrary.simpleMessage("Switch mode"),
    "actionProxy": MessageLookupByLibrary.simpleMessage("System proxy"),
    "actionRuleMode": MessageLookupByLibrary.simpleMessage("Rule mode"),
    "actionStart": MessageLookupByLibrary.simpleMessage("Start/Stop"),
    "actionTun": MessageLookupByLibrary.simpleMessage("TUN"),
    "actionUpdateProfiles": MessageLookupByLibrary.simpleMessage(
      "Update profiles",
    ),
    "actionView": MessageLookupByLibrary.simpleMessage("Show/Hide"),
    "activeConnections": MessageLookupByLibrary.simpleMessage("Active"),
    "activity": MessageLookupByLibrary.simpleMessage("Activities"),
    "activityLoadFailed": MessageLookupByLibrary.simpleMessage(
      "Failed to load the page",
    ),
    "add": MessageLookupByLibrary.simpleMessage("Add"),
    "addCustomProxy": MessageLookupByLibrary.simpleMessage("Add proxy"),
    "addFilters": MessageLookupByLibrary.simpleMessage("Add filters"),
    "addNodeManualMode": MessageLookupByLibrary.simpleMessage("Manual entry"),
    "addNodePasteMode": MessageLookupByLibrary.simpleMessage("Paste"),
    "addNodeProtocol": MessageLookupByLibrary.simpleMessage("Protocol"),
    "addNodeTargetProfile": MessageLookupByLibrary.simpleMessage(
      "Target profile",
    ),
    "addNodes": MessageLookupByLibrary.simpleMessage("Add nodes"),
    "addOverrideEntry": MessageLookupByLibrary.simpleMessage(
      "Add override entry",
    ),
    "addProfile": MessageLookupByLibrary.simpleMessage("Add profile"),
    "addProxies": MessageLookupByLibrary.simpleMessage("Add proxies"),
    "addProxyChain": MessageLookupByLibrary.simpleMessage("Add proxy chain"),
    "addProxyChainDesc": MessageLookupByLibrary.simpleMessage(
      "Creates a standalone chain node copied from the exit node; traffic goes through the front proxy first, and the chain is filed under the \"Proxy Chain\" tab",
    ),
    "addProxyGroup": MessageLookupByLibrary.simpleMessage("Add proxy group"),
    "addProxyNode": MessageLookupByLibrary.simpleMessage("Add node"),
    "addProxyNodeDesc": MessageLookupByLibrary.simpleMessage(
      "Paste a share link or YAML fragment — vless / vmess / ss / trojan / hysteria2 and more",
    ),
    "addProxyProviders": MessageLookupByLibrary.simpleMessage(
      "Add proxy providers",
    ),
    "addRule": MessageLookupByLibrary.simpleMessage("Add rule"),
    "addSettingEntry": MessageLookupByLibrary.simpleMessage("Add setting"),
    "addSsid": MessageLookupByLibrary.simpleMessage("Add SSID"),
    "addToLocalProxies": MessageLookupByLibrary.simpleMessage(
      "Add to local proxies",
    ),
    "addWidget": MessageLookupByLibrary.simpleMessage("Add widget"),
    "addedRules": MessageLookupByLibrary.simpleMessage("Added rules"),
    "addedToLocalProxies": m1,
    "additionalParameters": MessageLookupByLibrary.simpleMessage(
      "Additional parameters",
    ),
    "additionalPrefix": MessageLookupByLibrary.simpleMessage("Name prefix"),
    "additionalSuffix": MessageLookupByLibrary.simpleMessage("Name suffix"),
    "address": MessageLookupByLibrary.simpleMessage("Address"),
    "addressHelp": MessageLookupByLibrary.simpleMessage(
      "WebDAV server address",
    ),
    "addressTip": MessageLookupByLibrary.simpleMessage(
      "Please enter a valid WebDAV address",
    ),
    "advancedConfig": MessageLookupByLibrary.simpleMessage(
      "Advanced configuration",
    ),
    "advancedConfigDesc": MessageLookupByLibrary.simpleMessage(
      "Advanced configuration holds network, DNS, added rules, and scripts.",
    ),
    "ageEncryptedProfile": MessageLookupByLibrary.simpleMessage(
      "Encrypted profile",
    ),
    "ageSecretKey": MessageLookupByLibrary.simpleMessage("Age secret key"),
    "ageSecretKeyRequiredTip": MessageLookupByLibrary.simpleMessage(
      "This profile is encrypted with age and needs an age secret key to decrypt",
    ),
    "agree": MessageLookupByLibrary.simpleMessage("Agree"),
    "allReferencedProxies": MessageLookupByLibrary.simpleMessage(
      "All referenced proxies",
    ),
    "allReferencedProxyProviders": MessageLookupByLibrary.simpleMessage(
      "All referenced proxy providers",
    ),
    "allowBypass": MessageLookupByLibrary.simpleMessage(
      "Allow apps to bypass VPN",
    ),
    "allowBypassDesc": MessageLookupByLibrary.simpleMessage(
      "When enabled, some apps can bypass the VPN",
    ),
    "allowLan": MessageLookupByLibrary.simpleMessage("Allow LAN"),
    "allowLanDesc": MessageLookupByLibrary.simpleMessage(
      "Allow proxy access over the LAN",
    ),
    "allowedIps": MessageLookupByLibrary.simpleMessage("Allowed IPs"),
    "alreadyInLocalProxies": m2,
    "answers": MessageLookupByLibrary.simpleMessage("Answers"),
    "app": MessageLookupByLibrary.simpleMessage("App"),
    "appAccessControl": MessageLookupByLibrary.simpleMessage(
      "App access control",
    ),
    "appIconDesign": MessageLookupByLibrary.simpleMessage("App icon design"),
    "appProxiesEmpty": MessageLookupByLibrary.simpleMessage("No local proxies"),
    "appendSystemDns": MessageLookupByLibrary.simpleMessage(
      "Append system DNS",
    ),
    "appendSystemDnsTip": MessageLookupByLibrary.simpleMessage(
      "Force-append the system DNS to the configuration",
    ),
    "application": MessageLookupByLibrary.simpleMessage("Application"),
    "applicationDesc": MessageLookupByLibrary.simpleMessage(
      "Adjust application settings",
    ),
    "applied": MessageLookupByLibrary.simpleMessage("Applied"),
    "applyNow": MessageLookupByLibrary.simpleMessage("Apply now"),
    "authentication": MessageLookupByLibrary.simpleMessage("Authentication"),
    "authenticationDesc": MessageLookupByLibrary.simpleMessage(
      "Authentication asks for a username and password on the local proxy port.",
    ),
    "authenticationSystemProxyDesc": MessageLookupByLibrary.simpleMessage(
      "The system proxy is not applied while authentication is on.",
    ),
    "authorize": MessageLookupByLibrary.simpleMessage("Authorize"),
    "authorized": MessageLookupByLibrary.simpleMessage("Authorized"),
    "auto": MessageLookupByLibrary.simpleMessage("Auto"),
    "autoCheckUpdate": MessageLookupByLibrary.simpleMessage(
      "Auto check for updates",
    ),
    "autoCheckUpdateDesc": MessageLookupByLibrary.simpleMessage(
      "Check for updates automatically when the app starts",
    ),
    "autoCloseConnections": MessageLookupByLibrary.simpleMessage(
      "Auto close connections",
    ),
    "autoCloseConnectionsDesc": MessageLookupByLibrary.simpleMessage(
      "Auto close connections drops open connections when you switch proxies.",
    ),
    "autoExitTest": MessageLookupByLibrary.simpleMessage("Auto exit test"),
    "autoExitTestDesc": MessageLookupByLibrary.simpleMessage(
      "Re-tests nodes without fresh records once a day to keep region labels accurate; recent results are skipped",
    ),
    "autoInclude": MessageLookupByLibrary.simpleMessage("Auto-include"),
    "autoLaunch": MessageLookupByLibrary.simpleMessage("Auto launch"),
    "autoLaunchDesc": MessageLookupByLibrary.simpleMessage(
      "Launch automatically at system startup",
    ),
    "autoRun": MessageLookupByLibrary.simpleMessage("Auto run"),
    "autoRunDesc": MessageLookupByLibrary.simpleMessage(
      "Auto run starts the proxy when the app opens.",
    ),
    "autoSetSystemDns": MessageLookupByLibrary.simpleMessage(
      "Auto-set system DNS",
    ),
    "autoUpdate": MessageLookupByLibrary.simpleMessage("Auto update"),
    "autoUpdateInterval": MessageLookupByLibrary.simpleMessage(
      "Auto-update interval",
    ),
    "back": MessageLookupByLibrary.simpleMessage("Back"),
    "backgroundBlur": MessageLookupByLibrary.simpleMessage("Background blur"),
    "backup": MessageLookupByLibrary.simpleMessage("Backup"),
    "backupAndRestore": MessageLookupByLibrary.simpleMessage(
      "Backup and restore",
    ),
    "backupAndRestoreDesc": MessageLookupByLibrary.simpleMessage(
      "Sync data via WebDAV or files",
    ),
    "backupFromNewerVersion": MessageLookupByLibrary.simpleMessage(
      "This backup comes from a newer version of the app. Update the app before restoring it",
    ),
    "backupSuccess": MessageLookupByLibrary.simpleMessage("Backup successful"),
    "basicConfig": MessageLookupByLibrary.simpleMessage("Basic configuration"),
    "basicConfigDesc": MessageLookupByLibrary.simpleMessage(
      "Modify the basic configuration globally",
    ),
    "basicInfo": MessageLookupByLibrary.simpleMessage("Basic info"),
    "basicStrategy": MessageLookupByLibrary.simpleMessage("Basic strategies"),
    "batchAdd": MessageLookupByLibrary.simpleMessage("Batch add"),
    "batchImport": MessageLookupByLibrary.simpleMessage("Batch import"),
    "batchLinkInputTip": MessageLookupByLibrary.simpleMessage(
      "One link per line",
    ),
    "batchListInputTip": MessageLookupByLibrary.simpleMessage(
      "One item per line, or separated by commas",
    ),
    "batchMapInputTip": MessageLookupByLibrary.simpleMessage(
      "One entry per line: key, a space, then value",
    ),
    "batchPreviewTip": m3,
    "batchUrlInputTip": MessageLookupByLibrary.simpleMessage(
      "One URL per line",
    ),
    "batteryOptimizationDesc": MessageLookupByLibrary.simpleMessage(
      "Ignore battery optimization keeps the app running in the background.",
    ),
    "batteryOptimizationStatusTip": MessageLookupByLibrary.simpleMessage(
      "Due to system limitations, the battery optimization status cannot be read correctly while running",
    ),
    "bestPresetApply": MessageLookupByLibrary.simpleMessage("Apply"),
    "bestPresetDesc": MessageLookupByLibrary.simpleMessage(
      "Pick the best takeover mode for this device automatically",
    ),
    "bestPresetFirstRunTip": MessageLookupByLibrary.simpleMessage(
      "We can pick the takeover mode that fits this device: TUN mode when the device grants the needed privileges, otherwise the system proxy. Apply now?",
    ),
    "bestPresetSystemProxyApplied": MessageLookupByLibrary.simpleMessage(
      "System proxy is now enabled (the app is not running as administrator, so TUN is unavailable; restart it as administrator to use TUN)",
    ),
    "bestPresetTitle": MessageLookupByLibrary.simpleMessage(
      "Restore recommended settings",
    ),
    "bestPresetTunApplied": MessageLookupByLibrary.simpleMessage(
      "TUN mode is now enabled",
    ),
    "bind": MessageLookupByLibrary.simpleMessage("Bind"),
    "blacklistMode": MessageLookupByLibrary.simpleMessage("Blacklist mode"),
    "blockConnection": MessageLookupByLibrary.simpleMessage("Block connection"),
    "brightness": MessageLookupByLibrary.simpleMessage("Brightness"),
    "bypassDomain": MessageLookupByLibrary.simpleMessage("Bypass domains"),
    "bypassDomainDesc": MessageLookupByLibrary.simpleMessage(
      "Bypass domains apply only while the system proxy is on.",
    ),
    "bypassPrivateRoute": MessageLookupByLibrary.simpleMessage(
      "Bypass private addresses",
    ),
    "bypassPrivateRouteDesc": MessageLookupByLibrary.simpleMessage(
      "With Bypass private addresses on, LAN, loopback and multicast addresses skip TUN.",
    ),
    "cache": MessageLookupByLibrary.simpleMessage("Cache"),
    "cacheAlgorithm": MessageLookupByLibrary.simpleMessage("Cache algorithm"),
    "cacheCorrupt": MessageLookupByLibrary.simpleMessage(
      "The cache is corrupted. Clear it?",
    ),
    "cacheMaxSize": MessageLookupByLibrary.simpleMessage("Cache size"),
    "cameraPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "Allow camera access in system settings to scan QR codes, or choose a QR code image from the album.",
    ),
    "cameraPermissionRequired": MessageLookupByLibrary.simpleMessage(
      "Camera permission required",
    ),
    "cameraUnavailable": MessageLookupByLibrary.simpleMessage(
      "Camera unavailable",
    ),
    "cancel": MessageLookupByLibrary.simpleMessage("Cancel"),
    "cancelSelectAll": MessageLookupByLibrary.simpleMessage("Deselect all"),
    "cannotSave": MessageLookupByLibrary.simpleMessage("Can\'t save"),
    "changeProxyFailedTip": MessageLookupByLibrary.simpleMessage(
      "Failed to switch proxy; the previous selection has been restored",
    ),
    "changelogBreaking": MessageLookupByLibrary.simpleMessage(
      "Breaking changes",
    ),
    "changelogFeatures": MessageLookupByLibrary.simpleMessage("New features"),
    "changelogFixes": MessageLookupByLibrary.simpleMessage("Bug fixes"),
    "changelogPerformance": MessageLookupByLibrary.simpleMessage("Performance"),
    "changelogReverts": MessageLookupByLibrary.simpleMessage("Reverts"),
    "checkCertificate": MessageLookupByLibrary.simpleMessage(
      "Verify TLS certificates",
    ),
    "checkCertificateDesc": MessageLookupByLibrary.simpleMessage(
      "With TLS verification off, subscriptions and backups are open to man-in-the-middle attacks.",
    ),
    "checkUpdate": MessageLookupByLibrary.simpleMessage("Check for updates"),
    "checkUpdateError": MessageLookupByLibrary.simpleMessage(
      "The app is already up to date",
    ),
    "checkUpdateFailed": MessageLookupByLibrary.simpleMessage(
      "Could not reach the update server. Check your connection and try again.",
    ),
    "cipher": MessageLookupByLibrary.simpleMessage("Cipher"),
    "clearData": MessageLookupByLibrary.simpleMessage("Clear data"),
    "clearDataAndExitTip": MessageLookupByLibrary.simpleMessage(
      "This deletes all profiles, settings, and local data, then closes the app. Open it again to start fresh.",
    ),
    "clearDataFailed": m4,
    "clearDnsCache": MessageLookupByLibrary.simpleMessage("Clear DNS cache"),
    "clearDnsCacheFailed": MessageLookupByLibrary.simpleMessage(
      "Failed to clear DNS cache",
    ),
    "clearSearch": MessageLookupByLibrary.simpleMessage("Clear search"),
    "clientFingerprint": MessageLookupByLibrary.simpleMessage(
      "Client fingerprint",
    ),
    "clipboardEmpty": MessageLookupByLibrary.simpleMessage(
      "The clipboard has no usable content",
    ),
    "clipboardExport": MessageLookupByLibrary.simpleMessage(
      "Export to clipboard",
    ),
    "clipboardImport": MessageLookupByLibrary.simpleMessage(
      "Import from clipboard",
    ),
    "clipboardWriteFailed": MessageLookupByLibrary.simpleMessage(
      "Couldn\'t copy to the clipboard. The selection may be too large",
    ),
    "close": MessageLookupByLibrary.simpleMessage("Close"),
    "closeConnections": MessageLookupByLibrary.simpleMessage(
      "Close connections",
    ),
    "color": MessageLookupByLibrary.simpleMessage("Color"),
    "colorSchemes": MessageLookupByLibrary.simpleMessage("Color schemes"),
    "colorStyle": MessageLookupByLibrary.simpleMessage("Color style"),
    "columns": MessageLookupByLibrary.simpleMessage("Columns"),
    "compact": MessageLookupByLibrary.simpleMessage("Compact"),
    "compatible": MessageLookupByLibrary.simpleMessage("Compatibility mode"),
    "configDataDetected": MessageLookupByLibrary.simpleMessage(
      "Data detected in the configuration",
    ),
    "confirm": MessageLookupByLibrary.simpleMessage("Confirm"),
    "confirmClearAllData": MessageLookupByLibrary.simpleMessage(
      "Are you sure you want to clear all data?",
    ),
    "confirmDeleteProxyGroup": MessageLookupByLibrary.simpleMessage(
      "Are you sure you want to delete this proxy group?",
    ),
    "confirmExitWindow": MessageLookupByLibrary.simpleMessage(
      "Are you sure you want to exit the current window?",
    ),
    "confirmForceCrashCore": MessageLookupByLibrary.simpleMessage(
      "Are you sure you want to force crash the core?",
    ),
    "confirmOverwriteTip": MessageLookupByLibrary.simpleMessage(
      "Confirming will overwrite existing data",
    ),
    "congestionControl": MessageLookupByLibrary.simpleMessage(
      "Congestion control",
    ),
    "congestionController": MessageLookupByLibrary.simpleMessage(
      "TCP congestion control",
    ),
    "congestionControllerDesc": MessageLookupByLibrary.simpleMessage(
      "TCP congestion control works only with the mips stack.",
    ),
    "connected": MessageLookupByLibrary.simpleMessage("Connected"),
    "connecting": MessageLookupByLibrary.simpleMessage("Connecting…"),
    "connection": MessageLookupByLibrary.simpleMessage("Connection"),
    "connectionHeroTapToConnect": MessageLookupByLibrary.simpleMessage(
      "Tap to connect",
    ),
    "connectionHeroTapToDisconnect": MessageLookupByLibrary.simpleMessage(
      "Tap to disconnect",
    ),
    "connectionStateConnected": MessageLookupByLibrary.simpleMessage(
      "Connected",
    ),
    "connectionStateConnecting": MessageLookupByLibrary.simpleMessage(
      "Connecting…",
    ),
    "connectionStateDisconnected": MessageLookupByLibrary.simpleMessage(
      "Disconnected",
    ),
    "connectionStats": MessageLookupByLibrary.simpleMessage("Connection stats"),
    "connectionStatsDesc": MessageLookupByLibrary.simpleMessage(
      "Live connections, recent requests and DNS queries",
    ),
    "connections": MessageLookupByLibrary.simpleMessage("Connections"),
    "connectionsCloseFiltered": MessageLookupByLibrary.simpleMessage(
      "Close filtered",
    ),
    "connectionsDesc": MessageLookupByLibrary.simpleMessage(
      "View current connection data",
    ),
    "connectionsFilterChain": MessageLookupByLibrary.simpleMessage("Node"),
    "connectionsFilterProcess": MessageLookupByLibrary.simpleMessage("Process"),
    "connectionsFilterRule": MessageLookupByLibrary.simpleMessage("Rule"),
    "connectionsStat": MessageLookupByLibrary.simpleMessage("Connections"),
    "connectivity": MessageLookupByLibrary.simpleMessage("Connectivity: "),
    "content": MessageLookupByLibrary.simpleMessage("Content"),
    "contentNotEmpty": MessageLookupByLibrary.simpleMessage(
      "Content cannot be empty",
    ),
    "contentScheme": MessageLookupByLibrary.simpleMessage("Content"),
    "controlGlobalAddedRules": MessageLookupByLibrary.simpleMessage(
      "Control global added rules",
    ),
    "convertToLocalProfile": MessageLookupByLibrary.simpleMessage(
      "Convert to local profile",
    ),
    "convertToLocalProfileDesc": MessageLookupByLibrary.simpleMessage(
      "Detach the subscription link so future updates no longer overwrite this profile",
    ),
    "copy": MessageLookupByLibrary.simpleMessage("Copy"),
    "copyEnvVar": MessageLookupByLibrary.simpleMessage(
      "Copy environment variables",
    ),
    "copyLink": MessageLookupByLibrary.simpleMessage("Copy link"),
    "copyNode": MessageLookupByLibrary.simpleMessage("Copy node"),
    "copyShareLink": MessageLookupByLibrary.simpleMessage("Copy share link"),
    "copySuccess": MessageLookupByLibrary.simpleMessage("Copied successfully"),
    "core": MessageLookupByLibrary.simpleMessage("Core"),
    "coreBlockedByPolicyTip": m5,
    "coreBlockedBySmartAppControlTip": MessageLookupByLibrary.simpleMessage(
      "Windows Smart App Control blocked BiLoomCore.exe because it is not signed. Open Windows Security → App & browser control → Smart App Control settings, choose Off, then start BiLoom again. Smart App Control cannot be turned back on without reinstalling Windows.",
    ),
    "coreStatus": MessageLookupByLibrary.simpleMessage("Core status"),
    "country": MessageLookupByLibrary.simpleMessage("Region"),
    "crashDetected": MessageLookupByLibrary.simpleMessage("Crash detected"),
    "crashDetectedTip": m6,
    "crashTest": MessageLookupByLibrary.simpleMessage("Crash test"),
    "create": MessageLookupByLibrary.simpleMessage("Create"),
    "createProfile": MessageLookupByLibrary.simpleMessage("Add custom profile"),
    "createProfileDesc": MessageLookupByLibrary.simpleMessage(
      "Start from scratch and add nodes manually",
    ),
    "createProfileFromUrlTip": m7,
    "creationTime": MessageLookupByLibrary.simpleMessage("Creation time"),
    "currentExit": MessageLookupByLibrary.simpleMessage("Current exit"),
    "currentOutboundDesc": MessageLookupByLibrary.simpleMessage(
      "Holds the start button and can\'t be removed",
    ),
    "currentSelected": MessageLookupByLibrary.simpleMessage("Current"),
    "custom": MessageLookupByLibrary.simpleMessage("Custom"),
    "customColor": MessageLookupByLibrary.simpleMessage("Custom color"),
    "customImportDroppedSubRules": m8,
    "customIssueCoreRejected": m9,
    "customIssueDialerLoop": m10,
    "customIssueDuplicateName": m11,
    "customIssueEmptyName": MessageLookupByLibrary.simpleMessage(
      "The name is empty",
    ),
    "customIssueGroupLoop": m12,
    "customIssueInvalidEmptyFallback": m13,
    "customIssueInvalidFilter": m14,
    "customIssueMissingDialer": m15,
    "customIssueMissingProviders": m16,
    "customIssueMissingProxies": m17,
    "customIssueNoProxySource": MessageLookupByLibrary.simpleMessage(
      "No proxies or proxy providers are selected, so the core rejects this group",
    ),
    "customIssueReservedName": m18,
    "customIssuesSummary": m19,
    "customOverwriteRequired": MessageLookupByLibrary.simpleMessage(
      "Custom proxy groups live in the overwrite data, so subscription updates cannot wipe them. Switch to custom mode now?",
    ),
    "customProfile": MessageLookupByLibrary.simpleMessage("Custom"),
    "customProfileResources": MessageLookupByLibrary.simpleMessage(
      "Custom profile resources",
    ),
    "customProfileResourcesDesc": MessageLookupByLibrary.simpleMessage(
      "Custom profile resources are the proxies, rule providers, filters, and icon sets you add yourself for custom profiles to use.",
    ),
    "cut": MessageLookupByLibrary.simpleMessage("Cut"),
    "dark": MessageLookupByLibrary.simpleMessage("Dark"),
    "dashboard": MessageLookupByLibrary.simpleMessage("Dashboard"),
    "dashboardAddableSection": MessageLookupByLibrary.simpleMessage(
      "Available to add",
    ),
    "dataChangedSave": MessageLookupByLibrary.simpleMessage(
      "Data changes detected. Save them?",
    ),
    "databaseWriteFailedTip": MessageLookupByLibrary.simpleMessage(
      "Failed to save the change; it has been rolled back",
    ),
    "daysAgo": m20,
    "daysAgoShort": m21,
    "defaultNameserver": MessageLookupByLibrary.simpleMessage(
      "Default nameserver",
    ),
    "defaultNameserverDesc": MessageLookupByLibrary.simpleMessage(
      "Used to resolve DNS servers",
    ),
    "defaultSelected": MessageLookupByLibrary.simpleMessage(
      "Default selection",
    ),
    "defaultText": MessageLookupByLibrary.simpleMessage("Default"),
    "definitionNotMap": MessageLookupByLibrary.simpleMessage(
      "The configuration must be a YAML mapping with a name and a type",
    ),
    "delay": MessageLookupByLibrary.simpleMessage("Delay"),
    "delayFailed": MessageLookupByLibrary.simpleMessage("Failed"),
    "delayTest": MessageLookupByLibrary.simpleMessage("Delay test"),
    "delayTestTimeout": MessageLookupByLibrary.simpleMessage(
      "Delay test timeout",
    ),
    "delete": MessageLookupByLibrary.simpleMessage("Delete"),
    "deleteMultipTip": m22,
    "deleteNode": MessageLookupByLibrary.simpleMessage("Delete node"),
    "deleteNodeConfirm": MessageLookupByLibrary.simpleMessage(
      "The node will be removed from the profile and all its references cleaned up. Delete it?",
    ),
    "deleteNodeMissing": MessageLookupByLibrary.simpleMessage(
      "These nodes were not found (possibly already deleted):",
    ),
    "deleteNodeSuccess": MessageLookupByLibrary.simpleMessage("Deleted nodes:"),
    "deleteNodesConfirm": MessageLookupByLibrary.simpleMessage(
      "The selected nodes will be removed from the profile and all their references cleaned up. Delete them?",
    ),
    "deleteSelected": MessageLookupByLibrary.simpleMessage("Delete selected"),
    "deleteTip": m23,
    "desc": MessageLookupByLibrary.simpleMessage(
      "A multi-platform proxy client, deeply customized from FlClash. Simple and easy to use, with no ads on the desktop version.",
    ),
    "destination": MessageLookupByLibrary.simpleMessage("Destination"),
    "destinationGeoIP": MessageLookupByLibrary.simpleMessage(
      "Destination GeoIP",
    ),
    "destinationIPASN": MessageLookupByLibrary.simpleMessage(
      "Destination IP ASN",
    ),
    "details": m24,
    "detectionTip": MessageLookupByLibrary.simpleMessage(
      "Relies on a third-party API; for reference only",
    ),
    "developerMode": MessageLookupByLibrary.simpleMessage("Developer mode"),
    "developerModeEnableTip": MessageLookupByLibrary.simpleMessage(
      "Developer mode is enabled.",
    ),
    "dialerProxy": MessageLookupByLibrary.simpleMessage("Dialer proxy"),
    "dialerProxyDesc": MessageLookupByLibrary.simpleMessage(
      "Dialer proxy is the outbound used to reach the NTP server.",
    ),
    "dialerProxyLoopStopped": m25,
    "direct": MessageLookupByLibrary.simpleMessage("Direct"),
    "disableIcmpForwarding": MessageLookupByLibrary.simpleMessage(
      "Disable ICMP forwarding",
    ),
    "disableIcmpForwardingDesc": MessageLookupByLibrary.simpleMessage(
      "With ICMP forwarding disabled, TUN answers ping itself, so ping no longer shows the real latency.",
    ),
    "disableKeepAlive": MessageLookupByLibrary.simpleMessage(
      "Disable TCP keep-alive",
    ),
    "disableUDP": MessageLookupByLibrary.simpleMessage("Disable UDP"),
    "disabled": MessageLookupByLibrary.simpleMessage("Disabled"),
    "discardChanges": MessageLookupByLibrary.simpleMessage(
      "Discard the changes?",
    ),
    "disclaimer": MessageLookupByLibrary.simpleMessage("Disclaimer"),
    "disclaimerAcceptContent": MessageLookupByLibrary.simpleMessage(
      "By installing, copying, or using the Software, you are deemed to have read and agreed to this entire statement. If you disagree with any of its terms, stop using and uninstall the Software immediately.",
    ),
    "disclaimerAcceptTitle": MessageLookupByLibrary.simpleMessage("Acceptance"),
    "disclaimerAcknowledgeLabel": MessageLookupByLibrary.simpleMessage(
      "I have read and understand this statement",
    ),
    "disclaimerAcknowledgeTip": MessageLookupByLibrary.simpleMessage(
      "To confirm you understand, read the following statement and check the box below:",
    ),
    "disclaimerAcknowledgeTitle": MessageLookupByLibrary.simpleMessage(
      "Confirm the statement",
    ),
    "disclaimerChangesContent": MessageLookupByLibrary.simpleMessage(
      "The developers may revise this statement with any release, and the revision takes effect when that release is published. Continuing to use the Software after updating means you accept the revised statement.",
    ),
    "disclaimerChangesTitle": MessageLookupByLibrary.simpleMessage(
      "Changes to this statement",
    ),
    "disclaimerDesc": MessageLookupByLibrary.simpleMessage(
      "Before using BiLoom (\"the Software\"), please read this statement carefully and make sure you understand all of it. Tapping \"Agree\" means you have read, understood, and accept every term below. If you do not agree, tap \"Exit\" and stop using the Software.",
    ),
    "disclaimerLiabilityContent": MessageLookupByLibrary.simpleMessage(
      "To the maximum extent permitted by applicable law, neither the developers nor any contributor shall be liable for any direct, indirect, incidental, special, punitive, or consequential damages arising from the use of or inability to use the Software, including but not limited to data loss, device damage, network failures, business interruption, lost profits, or any resulting legal dispute, even if advised of the possibility of such damages.",
    ),
    "disclaimerLiabilityTitle": MessageLookupByLibrary.simpleMessage(
      "Limitation of liability",
    ),
    "disclaimerLicenseContent": MessageLookupByLibrary.simpleMessage(
      "The Software is developed as a modification of FlClash (GPL-3.0) and is open source under the GPL-3.0 license. You may use, modify, and distribute it freely as long as you comply with that license, which requires derivative works to be released under GPL-3.0 as well and the original copyright notices to be kept.\n\nThird-party components in the Software, including the Clash.Meta core, follow their own licenses. The original authors are not responsible for any issue arising from modified or redistributed versions.",
    ),
    "disclaimerLicenseTitle": MessageLookupByLibrary.simpleMessage(
      "Open-source license",
    ),
    "disclaimerNoServiceStatement": MessageLookupByLibrary.simpleMessage(
      "The Software itself does not provide any proxy server, node, subscription, or network access service, and has no partnership, agency, or guarantee relationship with any provider of such services.",
    ),
    "disclaimerPrivacyContent": MessageLookupByLibrary.simpleMessage(
      "The Software does not collect or upload your subscription URLs, node details, configuration content, visited websites, connection records, traffic content, or logs. This data stays on your device and the developers have no access to it.\n\nThe Software only reaches the network when you use a feature that needs it, such as fetching the subscription URL you provided when updating a profile, or contacting GitHub when checking for updates.\n\nThe Software includes no analytics or crash reporting service on any platform.",
    ),
    "disclaimerPrivacyTitle": MessageLookupByLibrary.simpleMessage(
      "Data collection and privacy",
    ),
    "disclaimerResponsibilityContent": MessageLookupByLibrary.simpleMessage(
      "You are responsible for making sure that using the Software is lawful where you live, and you alone bear the legal responsibility for everything you do with it and its consequences.\n\nThe subscriptions, nodes, and configurations you import are your own choice. Whether their source is lawful, their content is safe, and their service is reliable is a matter between you and their providers.",
    ),
    "disclaimerResponsibilityTitle": MessageLookupByLibrary.simpleMessage(
      "Your responsibility",
    ),
    "disclaimerRestateHint": MessageLookupByLibrary.simpleMessage(
      "Enter the statement above",
    ),
    "disclaimerRestateMismatch": MessageLookupByLibrary.simpleMessage(
      "Does not match the statement",
    ),
    "disclaimerRestateTip": MessageLookupByLibrary.simpleMessage(
      "To confirm you understand, enter the following statement in full in the field below:",
    ),
    "disclaimerRestateTitle": MessageLookupByLibrary.simpleMessage(
      "Restate the statement",
    ),
    "disclaimerSoftwareContent": MessageLookupByLibrary.simpleMessage(
      "The Software is an open-source network proxy client built on the Clash.Meta (mihomo) core. It only provides local tooling such as configuration management, rule-based routing, and traffic forwarding.",
    ),
    "disclaimerSoftwareTitle": MessageLookupByLibrary.simpleMessage(
      "Nature of the software",
    ),
    "disclaimerThirdPartyContent": MessageLookupByLibrary.simpleMessage(
      "Subscription links, configuration files, rule sets, scripts, external resources, and external links are all provided by third parties. The developers cannot and do not review or guarantee their legality, accuracy, security, or availability.\n\nAny data leak, financial loss, account ban, or other loss caused by third-party content is to be settled between you and the third party; the developers bear no responsibility for it.",
    ),
    "disclaimerThirdPartyTitle": MessageLookupByLibrary.simpleMessage(
      "Third-party content",
    ),
    "disclaimerUsageContent": MessageLookupByLibrary.simpleMessage(
      "The Software is intended only for non-commercial uses such as learning, exchange, and technical research. Using it for any commercial purpose is strictly prohibited, including but not limited to paid distribution, bundled sales, use as part of a commercial service, or doing business in the name of the Software. Any commercial activity is unrelated to the Software and its developers.\n\nUsing the Software for anything that violates the laws and regulations of your country or region is strictly prohibited, including but not limited to bypassing lawfully imposed network access restrictions, spreading illegal content, launching network attacks, or infringing the lawful rights of others.",
    ),
    "disclaimerUsageTitle": MessageLookupByLibrary.simpleMessage(
      "Restrictions on use",
    ),
    "disclaimerWarrantyContent": MessageLookupByLibrary.simpleMessage(
      "The Software is provided \"as is\" and \"as available\", without warranty of any kind, express or implied, including but not limited to warranties of merchantability, fitness for a particular purpose, non-infringement, uninterrupted availability, freedom from errors, or freedom from security vulnerabilities.\n\nThe developers do not guarantee that the Software will meet your needs or that it will run without interruption or error.",
    ),
    "disclaimerWarrantyTitle": MessageLookupByLibrary.simpleMessage(
      "No warranty",
    ),
    "disconnected": MessageLookupByLibrary.simpleMessage("Disconnected"),
    "discoverNewVersion": MessageLookupByLibrary.simpleMessage(
      "New version found",
    ),
    "dnsCacheCleared": MessageLookupByLibrary.simpleMessage(
      "DNS cache cleared",
    ),
    "dnsDesc": MessageLookupByLibrary.simpleMessage(
      "Update DNS-related settings",
    ),
    "dnsHijackDesc": MessageLookupByLibrary.simpleMessage(
      "Without this entry, TUN hijacks every DNS query to port 53 (any:53).",
    ),
    "dnsHijacking": MessageLookupByLibrary.simpleMessage("DNS hijacking"),
    "dnsLeakCheck": MessageLookupByLibrary.simpleMessage("DNS leak check"),
    "dnsLeakCheckDesc": MessageLookupByLibrary.simpleMessage(
      "Check whether the system DNS is taken over by the core",
    ),
    "dnsLeakExplain": MessageLookupByLibrary.simpleMessage(
      "In fake-ip mode the core answers every domain with an address from the fake-ip range; a real public IP here means the query never reached the core. Under \"system proxy only\" that is unavoidable: the system proxy affects only apps that honour it, and DNS queries made by Windows itself are not among them. Switch to TUN to take over the whole system.",
    ),
    "dnsLeakFailed": MessageLookupByLibrary.simpleMessage(
      "No resolver answered",
    ),
    "dnsLeakMode": MessageLookupByLibrary.simpleMessage("Current takeover"),
    "dnsLeakNotApplicable": MessageLookupByLibrary.simpleMessage(
      "Cannot be judged in this mode",
    ),
    "dnsLeakNotTakenOver": MessageLookupByLibrary.simpleMessage(
      "Not taken over",
    ),
    "dnsLeakOnline": MessageLookupByLibrary.simpleMessage("Open online test"),
    "dnsLeakRun": MessageLookupByLibrary.simpleMessage("Run check"),
    "dnsLeakRunning": MessageLookupByLibrary.simpleMessage("Checking..."),
    "dnsLeakTakenOver": MessageLookupByLibrary.simpleMessage(
      "Taken over by the core",
    ),
    "dnsMode": MessageLookupByLibrary.simpleMessage("DNS mode"),
    "dnsOverrideDesc": MessageLookupByLibrary.simpleMessage(
      "Entries added here replace the DNS of every URL and file profile; anything not added keeps the profile\'s own setting. Custom profiles set their DNS in their content.",
    ),
    "dnsQueries": MessageLookupByLibrary.simpleMessage("DNS queries"),
    "docked": MessageLookupByLibrary.simpleMessage("Docked"),
    "domain": MessageLookupByLibrary.simpleMessage("Domain"),
    "done": MessageLookupByLibrary.simpleMessage("Done"),
    "download": MessageLookupByLibrary.simpleMessage("Download"),
    "downloadBandwidth": MessageLookupByLibrary.simpleMessage(
      "Download bandwidth",
    ),
    "duration": MessageLookupByLibrary.simpleMessage("Duration"),
    "edit": MessageLookupByLibrary.simpleMessage("Edit"),
    "editDashboard": MessageLookupByLibrary.simpleMessage("Edit dashboard"),
    "editGlobalRules": MessageLookupByLibrary.simpleMessage(
      "Edit global rules",
    ),
    "editNode": MessageLookupByLibrary.simpleMessage("Edit node"),
    "editNodeSuccess": MessageLookupByLibrary.simpleMessage("Node updated"),
    "editProxy": MessageLookupByLibrary.simpleMessage("Edit proxy"),
    "editProxyGroup": MessageLookupByLibrary.simpleMessage("Edit proxy group"),
    "editRule": MessageLookupByLibrary.simpleMessage("Edit rule"),
    "editSsid": MessageLookupByLibrary.simpleMessage("Edit SSID"),
    "editorUnavailable": MessageLookupByLibrary.simpleMessage(
      "Editor unavailable",
    ),
    "elapsed": MessageLookupByLibrary.simpleMessage("Took"),
    "emptyFallback": MessageLookupByLibrary.simpleMessage("Empty fallback"),
    "emptyTip": m26,
    "en": MessageLookupByLibrary.simpleMessage("English"),
    "enabled": MessageLookupByLibrary.simpleMessage("Enabled"),
    "entries": MessageLookupByLibrary.simpleMessage(" entries"),
    "entriesCount": m27,
    "error": MessageLookupByLibrary.simpleMessage("Error"),
    "errorDetails": MessageLookupByLibrary.simpleMessage("Error details"),
    "es": MessageLookupByLibrary.simpleMessage("Spanish"),
    "exclude": MessageLookupByLibrary.simpleMessage("Hide from recent tasks"),
    "excludeDesc": MessageLookupByLibrary.simpleMessage(
      "Hide the app from recent tasks while it is in the background",
    ),
    "excludeDstPort": MessageLookupByLibrary.simpleMessage(
      "Excluded destination ports",
    ),
    "excludeDstPortDesc": MessageLookupByLibrary.simpleMessage(
      "Traffic to excluded destination ports skips TUN.",
    ),
    "excludeFilter": MessageLookupByLibrary.simpleMessage("Exclude filter"),
    "excludeInterface": MessageLookupByLibrary.simpleMessage(
      "Excluded interfaces",
    ),
    "excludeInterfaceDesc": MessageLookupByLibrary.simpleMessage(
      "Traffic arriving on excluded interfaces, such as docker0, skips TUN.",
    ),
    "excludeProxyFilter": MessageLookupByLibrary.simpleMessage(
      "Exclude proxy filter",
    ),
    "excludeSrcPort": MessageLookupByLibrary.simpleMessage(
      "Excluded source ports",
    ),
    "excludeSrcPortDesc": MessageLookupByLibrary.simpleMessage(
      "Traffic from excluded source ports skips TUN.",
    ),
    "excludeSsids": MessageLookupByLibrary.simpleMessage("Exclude SSIDs"),
    "excludeSsidsDesc": MessageLookupByLibrary.simpleMessage(
      "When connected to Wi-Fi with an excluded SSID, the app\'s running state switches automatically.",
    ),
    "excludeType": MessageLookupByLibrary.simpleMessage("Exclude type"),
    "excludeUid": MessageLookupByLibrary.simpleMessage("Excluded user IDs"),
    "excludeUidDesc": MessageLookupByLibrary.simpleMessage(
      "Traffic from processes of excluded user IDs skips TUN.",
    ),
    "existsTip": m28,
    "exit": MessageLookupByLibrary.simpleMessage("Exit"),
    "exitFullScreen": MessageLookupByLibrary.simpleMessage("Exit full screen"),
    "exitNodes": MessageLookupByLibrary.simpleMessage("Exit nodes"),
    "expand": MessageLookupByLibrary.simpleMessage("Standard"),
    "expectedStatus": MessageLookupByLibrary.simpleMessage("Expected status"),
    "expireTime": MessageLookupByLibrary.simpleMessage("Expiration time"),
    "exportFile": MessageLookupByLibrary.simpleMessage("Export file"),
    "exportLogs": MessageLookupByLibrary.simpleMessage("Export logs"),
    "exportSuccess": MessageLookupByLibrary.simpleMessage("Export successful"),
    "expressiveScheme": MessageLookupByLibrary.simpleMessage("Expressive"),
    "extend": MessageLookupByLibrary.simpleMessage("Extend"),
    "extendMode": MessageLookupByLibrary.simpleMessage("Extend mode"),
    "extendScript": MessageLookupByLibrary.simpleMessage("Extend script"),
    "externalController": MessageLookupByLibrary.simpleMessage(
      "External controller",
    ),
    "externalControllerDesc": MessageLookupByLibrary.simpleMessage(
      "The external controller lets you control the core on port 9090.",
    ),
    "externalControllerSecret": MessageLookupByLibrary.simpleMessage(
      "External controller secret",
    ),
    "externalFetch": MessageLookupByLibrary.simpleMessage("External fetch"),
    "externalLink": MessageLookupByLibrary.simpleMessage("External link"),
    "extraLarge": MessageLookupByLibrary.simpleMessage("Extra large"),
    "fade": MessageLookupByLibrary.simpleMessage("Fade"),
    "failedCount": m29,
    "failedItem": m30,
    "fakeipFilter": MessageLookupByLibrary.simpleMessage("Fake-IP filter"),
    "fakeipFilterMode": MessageLookupByLibrary.simpleMessage(
      "Fake-IP filter mode",
    ),
    "fakeipFilterModeDesc": MessageLookupByLibrary.simpleMessage(
      "In Fake-IP filter mode, blacklist excludes matches, whitelist fakes only matches, and rule matches as rules.",
    ),
    "fakeipRange": MessageLookupByLibrary.simpleMessage("Fake-IP range"),
    "fakeipRange6": MessageLookupByLibrary.simpleMessage(
      "Fake-IP range (IPv6)",
    ),
    "fakeipTtl": MessageLookupByLibrary.simpleMessage("Fake-IP TTL"),
    "fallback": MessageLookupByLibrary.simpleMessage("Fallback"),
    "fallbackDesc": MessageLookupByLibrary.simpleMessage(
      "Usually an overseas DNS",
    ),
    "fallbackFilter": MessageLookupByLibrary.simpleMessage("Fallback filter"),
    "favoriteNode": MessageLookupByLibrary.simpleMessage("Favorite node"),
    "fidelityScheme": MessageLookupByLibrary.simpleMessage("Fidelity"),
    "file": MessageLookupByLibrary.simpleMessage("File"),
    "fileDesc": MessageLookupByLibrary.simpleMessage(
      "Upload a profile file directly",
    ),
    "fileIsUpdate": MessageLookupByLibrary.simpleMessage(
      "The file has been modified. Save the changes?",
    ),
    "filter": MessageLookupByLibrary.simpleMessage("Filter"),
    "filters": MessageLookupByLibrary.simpleMessage("Filters"),
    "findProcessMode": MessageLookupByLibrary.simpleMessage("Find process"),
    "findProcessModeDesc": MessageLookupByLibrary.simpleMessage(
      "Enabling causes some performance loss",
    ),
    "floating": MessageLookupByLibrary.simpleMessage("Floating"),
    "followProfile": MessageLookupByLibrary.simpleMessage("Follow profile"),
    "followSystem": MessageLookupByLibrary.simpleMessage("Follow system"),
    "fontFamily": MessageLookupByLibrary.simpleMessage("Font family"),
    "fontSize": MessageLookupByLibrary.simpleMessage("Size"),
    "forceDnsMapping": MessageLookupByLibrary.simpleMessage(
      "Force DNS mapping",
    ),
    "forceDnsMappingDesc": MessageLookupByLibrary.simpleMessage(
      "Force DNS mapping also sniffs connections whose domain came from a DNS mapping.",
    ),
    "forceDomain": MessageLookupByLibrary.simpleMessage("Force domains"),
    "forceDomainDesc": MessageLookupByLibrary.simpleMessage(
      "Force domains are sniffed too; other connections that already have a domain are left alone.",
    ),
    "forceRestartCoreTip": MessageLookupByLibrary.simpleMessage(
      "Are you sure you want to force restart the core?",
    ),
    "forkedFrom": MessageLookupByLibrary.simpleMessage("Based on BiLoom"),
    "fr": MessageLookupByLibrary.simpleMessage("French"),
    "fruitSaladScheme": MessageLookupByLibrary.simpleMessage("Fruit salad"),
    "general": MessageLookupByLibrary.simpleMessage("General"),
    "generalOverrideDesc": MessageLookupByLibrary.simpleMessage(
      "Entries added here replace the setting of every profile; anything not added keeps the profile\'s own setting, or the core default when the profile has none.",
    ),
    "generateRegionGroups": MessageLookupByLibrary.simpleMessage(
      "Group by region",
    ),
    "generateRegionGroupsDone": MessageLookupByLibrary.simpleMessage(
      "Region groups created",
    ),
    "generateRegionGroupsEmpty": MessageLookupByLibrary.simpleMessage(
      "No recognisable regions",
    ),
    "generateRegionGroupsKeep": MessageLookupByLibrary.simpleMessage(
      "Left as is",
    ),
    "generateRegionGroupsPreview": MessageLookupByLibrary.simpleMessage(
      "Groups to create",
    ),
    "generateRegionGroupsRemoveTip": MessageLookupByLibrary.simpleMessage(
      "These groups reference nodes that no longer exist; keeping them makes the whole config fail to load",
    ),
    "generateRegionGroupsTip": MessageLookupByLibrary.simpleMessage(
      "Sorts nodes into strategy groups by egress region so a region\'s nodes are quick to find. The groups live in the override data, so updating the subscription keeps them.",
    ),
    "generateRegionGroupsUnknown": MessageLookupByLibrary.simpleMessage(
      "Nodes with an unrecognised region are not grouped",
    ),
    "geoAutoUpdate": MessageLookupByLibrary.simpleMessage("Auto update"),
    "geoAutoUpdateInterval": MessageLookupByLibrary.simpleMessage(
      "Auto-update interval",
    ),
    "geoAutoUpdateIntervalTip": MessageLookupByLibrary.simpleMessage(
      "The auto-update interval must be greater than 0",
    ),
    "geoOptions": MessageLookupByLibrary.simpleMessage("Geo options"),
    "geoResources": MessageLookupByLibrary.simpleMessage("Geo"),
    "geoSkipped": m31,
    "geoUpdated": m32,
    "geodataLoader": MessageLookupByLibrary.simpleMessage(
      "Geo low-memory mode",
    ),
    "geodataLoaderDesc": MessageLookupByLibrary.simpleMessage(
      "Use the low-memory Geo loader",
    ),
    "geoipCode": MessageLookupByLibrary.simpleMessage("GeoIP code"),
    "global": MessageLookupByLibrary.simpleMessage("Global"),
    "go": MessageLookupByLibrary.simpleMessage("Go"),
    "goDownload": MessageLookupByLibrary.simpleMessage("Download"),
    "goToConfigureAddedRules": MessageLookupByLibrary.simpleMessage(
      "Go to added rules configuration",
    ),
    "goToConfigureScript": MessageLookupByLibrary.simpleMessage(
      "Go to script configuration",
    ),
    "grid": MessageLookupByLibrary.simpleMessage("Grid"),
    "groupCount": m33,
    "groupCountUnit": MessageLookupByLibrary.simpleMessage("groups"),
    "groupTimeoutCount": m34,
    "groupsUpdateFailedTip": MessageLookupByLibrary.simpleMessage(
      "Failed to load proxy groups. Check the config or restart the core",
    ),
    "hasCacheChange": MessageLookupByLibrary.simpleMessage(
      "Cache the changes?",
    ),
    "hashByInUser": MessageLookupByLibrary.simpleMessage(
      "Hash by inbound user",
    ),
    "healthCheck": MessageLookupByLibrary.simpleMessage("Health check"),
    "helperCorruptTip": MessageLookupByLibrary.simpleMessage(
      "Helper service unavailable; TUN mode cannot be enabled. Reinstall BiLoom to restore it.",
    ),
    "hex": MessageLookupByLibrary.simpleMessage("Hex"),
    "hideFromList": MessageLookupByLibrary.simpleMessage("Hide from list"),
    "hideIp": MessageLookupByLibrary.simpleMessage("Hide IP"),
    "hidePassword": MessageLookupByLibrary.simpleMessage("Hide password"),
    "hideTimeoutProxies": MessageLookupByLibrary.simpleMessage(
      "Hide timed-out proxies",
    ),
    "hopInterval": MessageLookupByLibrary.simpleMessage("Hop interval"),
    "host": MessageLookupByLibrary.simpleMessage("Host"),
    "hostname": MessageLookupByLibrary.simpleMessage("Hostname"),
    "hostsDesc": MessageLookupByLibrary.simpleMessage("Append hosts"),
    "hotkeyConflict": MessageLookupByLibrary.simpleMessage("Hotkey conflict"),
    "hotkeyConflictWith": m35,
    "hotkeyDesc": MessageLookupByLibrary.simpleMessage(
      "Global hotkeys work even while the window is hidden. Tap an action to record its key combination.",
    ),
    "hotkeyManagement": MessageLookupByLibrary.simpleMessage(
      "Hotkey management",
    ),
    "hotkeyManagementDesc": MessageLookupByLibrary.simpleMessage(
      "Control the app with the keyboard",
    ),
    "hotkeyNeedsModifier": m36,
    "hotkeyNotSet": MessageLookupByLibrary.simpleMessage("Not set"),
    "hotkeyUnavailable": MessageLookupByLibrary.simpleMessage(
      "Not registered, it may be taken by another app",
    ),
    "hours": MessageLookupByLibrary.simpleMessage("hours"),
    "hoursAgo": m37,
    "hoursAgoShort": m38,
    "hoursCount": m39,
    "hue": MessageLookupByLibrary.simpleMessage("Hue"),
    "icon": MessageLookupByLibrary.simpleMessage("Icon"),
    "iconRecords": MessageLookupByLibrary.simpleMessage("Icon records"),
    "iconSets": MessageLookupByLibrary.simpleMessage("Icon sets"),
    "iconSetsEmptyTip": MessageLookupByLibrary.simpleMessage(
      "No icon sets yet. Add them in Custom profile resources → Icon sets",
    ),
    "iconStyle": MessageLookupByLibrary.simpleMessage("Icon style"),
    "iconStyleFilled": MessageLookupByLibrary.simpleMessage("Filled"),
    "iconStyleHidden": MessageLookupByLibrary.simpleMessage("Hidden"),
    "iconStylePlain": MessageLookupByLibrary.simpleMessage("Plain"),
    "iconUrl": MessageLookupByLibrary.simpleMessage("Icon URL"),
    "ignoreBatteryOptimization": MessageLookupByLibrary.simpleMessage(
      "Ignore battery optimization",
    ),
    "import": MessageLookupByLibrary.simpleMessage("Import"),
    "importConfigInvalid": MessageLookupByLibrary.simpleMessage(
      "This file is not a config that can be imported",
    ),
    "importConfigReplaceTip": MessageLookupByLibrary.simpleMessage(
      "Importing replaces the proxy groups, rules and settings this profile has now",
    ),
    "importFile": MessageLookupByLibrary.simpleMessage("Import from file"),
    "importFromLink": MessageLookupByLibrary.simpleMessage("Import from link"),
    "importFromURL": MessageLookupByLibrary.simpleMessage("Import from URL"),
    "importUrl": MessageLookupByLibrary.simpleMessage("Import from URL"),
    "inbound": MessageLookupByLibrary.simpleMessage("Inbound"),
    "includeAllProxies": MessageLookupByLibrary.simpleMessage(
      "Include all proxies",
    ),
    "includeAllProxiesTip": MessageLookupByLibrary.simpleMessage(
      "Imports all proxies outside proxy groups; extra proxy groups can be added below",
    ),
    "includeAllProxyProviders": MessageLookupByLibrary.simpleMessage(
      "Include all proxy providers",
    ),
    "includeAllProxyProvidersTip": MessageLookupByLibrary.simpleMessage(
      "When enabled, the imported proxy providers are overridden",
    ),
    "includeInterface": MessageLookupByLibrary.simpleMessage(
      "Included interfaces",
    ),
    "includeInterfaceDesc": MessageLookupByLibrary.simpleMessage(
      "Only traffic arriving on included interfaces goes through TUN, and excluded interfaces no longer apply.",
    ),
    "includeUid": MessageLookupByLibrary.simpleMessage("Included user IDs"),
    "includeUidDesc": MessageLookupByLibrary.simpleMessage(
      "Only traffic from processes of included user IDs goes through TUN.",
    ),
    "infiniteTime": MessageLookupByLibrary.simpleMessage("Never expires"),
    "init": MessageLookupByLibrary.simpleMessage("Init"),
    "initFailed": MessageLookupByLibrary.simpleMessage("Startup failed"),
    "initFailedTip": MessageLookupByLibrary.simpleMessage(
      "BiLoom ran into an error while starting and can\'t continue. Copy the details to report the problem. If it keeps happening, clearing the data usually lets the app start again.",
    ),
    "initiator": MessageLookupByLibrary.simpleMessage("Initiator"),
    "initiatorShort": MessageLookupByLibrary.simpleMessage("From"),
    "inputCorrectHotkey": MessageLookupByLibrary.simpleMessage(
      "Please enter a valid hotkey",
    ),
    "inputProxyGroupName": MessageLookupByLibrary.simpleMessage(
      "Enter the proxy group name",
    ),
    "inputRuleContent": MessageLookupByLibrary.simpleMessage(
      "Enter the rule content",
    ),
    "installedAppsPermissionDeniedMessage":
        MessageLookupByLibrary.simpleMessage(
          "The app list permission was denied, so installed apps cannot be listed. Please grant it manually in system settings.",
        ),
    "installedAppsPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "This system hides the installed app list until the permission is granted. Authorize it to configure the per-app proxy.",
    ),
    "installedAppsPermissionRequired": MessageLookupByLibrary.simpleMessage(
      "App list permission required",
    ),
    "installedFonts": MessageLookupByLibrary.simpleMessage("Installed fonts"),
    "intelligentSelected": MessageLookupByLibrary.simpleMessage(
      "Smart selection",
    ),
    "intentAi": MessageLookupByLibrary.simpleMessage("AI services"),
    "intentGroups": MessageLookupByLibrary.simpleMessage("Intent groups"),
    "intentGroupsDone": MessageLookupByLibrary.simpleMessage(
      "Intent groups applied",
    ),
    "intentGroupsTip": MessageLookupByLibrary.simpleMessage(
      "Route matching domains into a dedicated group per intent: checking one creates its group and rules (rules go before the subscription rules), unchecking removes both.",
    ),
    "intentSocial": MessageLookupByLibrary.simpleMessage("Social"),
    "intentStreaming": MessageLookupByLibrary.simpleMessage("Streaming"),
    "interfaceName": MessageLookupByLibrary.simpleMessage("Interface name"),
    "interfaceNameDesc": MessageLookupByLibrary.simpleMessage(
      "Interface name is the network interface outbound connections use.",
    ),
    "interfaceNameMode": MessageLookupByLibrary.simpleMessage(
      "Outbound interface",
    ),
    "interfaceNameModeClear": MessageLookupByLibrary.simpleMessage("Clear"),
    "interfaceNameModeCustom": MessageLookupByLibrary.simpleMessage("Custom"),
    "interfaceNameModeFollow": MessageLookupByLibrary.simpleMessage(
      "Follow config",
    ),
    "internet": MessageLookupByLibrary.simpleMessage("Internet"),
    "interval": MessageLookupByLibrary.simpleMessage("Interval"),
    "intranetIP": MessageLookupByLibrary.simpleMessage("Intranet IP"),
    "invalidBackupFile": MessageLookupByLibrary.simpleMessage(
      "Invalid backup file",
    ),
    "invalidCidrContent": MessageLookupByLibrary.simpleMessage(
      "Enter an IP range in CIDR form such as 192.168.0.0/16",
    ),
    "invalidDscpContent": MessageLookupByLibrary.simpleMessage(
      "A DSCP mark cannot exceed 63",
    ),
    "invalidHostContent": MessageLookupByLibrary.simpleMessage(
      "Enter a domain or an IP address",
    ),
    "invalidIconSet": MessageLookupByLibrary.simpleMessage(
      "Not a valid icon set",
    ),
    "invalidLinkTip": MessageLookupByLibrary.simpleMessage(
      "Not a subscription link or a proxy share link",
    ),
    "invalidListenContent": MessageLookupByLibrary.simpleMessage(
      "Enter an address and port such as 0.0.0.0:1053",
    ),
    "invalidNetworkContent": MessageLookupByLibrary.simpleMessage(
      "Only tcp or udp is supported",
    ),
    "invalidPolicy": m40,
    "invalidPortRangeContent": MessageLookupByLibrary.simpleMessage(
      "Enter a port or a range such as 443 or 8000-9000",
    ),
    "invalidProfileQrcode": MessageLookupByLibrary.simpleMessage(
      "This QR code doesn\'t contain a profile link",
    ),
    "invalidProxy": m41,
    "invalidProxyProvider": m42,
    "invalidRangeContent": MessageLookupByLibrary.simpleMessage(
      "Enter numbers or ranges such as 80 or 8000-9000, separated by /",
    ),
    "invalidRuleSet": m43,
    "invalidSubRule": m44,
    "ipAddress": MessageLookupByLibrary.simpleMessage("IP address"),
    "ipAsn": MessageLookupByLibrary.simpleMessage("ASN"),
    "ipFlagAbuser": MessageLookupByLibrary.simpleMessage("Abuse history"),
    "ipFlagProxy": MessageLookupByLibrary.simpleMessage("Proxy"),
    "ipFlagTor": MessageLookupByLibrary.simpleMessage("Tor"),
    "ipFlagVpn": MessageLookupByLibrary.simpleMessage("VPN"),
    "ipFlags": MessageLookupByLibrary.simpleMessage("Flags"),
    "ipOrganization": MessageLookupByLibrary.simpleMessage("Organization"),
    "ipQualityFailed": MessageLookupByLibrary.simpleMessage(
      "Couldn\'t determine the IP type",
    ),
    "ipQualityGood": MessageLookupByLibrary.simpleMessage("Good"),
    "ipQualityLevel": MessageLookupByLibrary.simpleMessage("Level"),
    "ipQualityNormal": MessageLookupByLibrary.simpleMessage("Normal"),
    "ipQualityRetry": MessageLookupByLibrary.simpleMessage("Check again"),
    "ipQualityRisky": MessageLookupByLibrary.simpleMessage("Risky"),
    "ipQualityShort": MessageLookupByLibrary.simpleMessage("Quality"),
    "ipQualitySource": MessageLookupByLibrary.simpleMessage("Answered by"),
    "ipQualitySources": MessageLookupByLibrary.simpleMessage("Sources"),
    "ipSourceIpMismatch": MessageLookupByLibrary.simpleMessage(
      "Different outbound IP",
    ),
    "ipSourceNoType": MessageLookupByLibrary.simpleMessage("No type"),
    "ipSourceRateLimited": MessageLookupByLibrary.simpleMessage("Rate limited"),
    "ipType": MessageLookupByLibrary.simpleMessage("Type"),
    "ipTypeBusiness": MessageLookupByLibrary.simpleMessage("Business"),
    "ipTypeHosting": MessageLookupByLibrary.simpleMessage("Data center"),
    "ipTypeMobile": MessageLookupByLibrary.simpleMessage("Mobile network"),
    "ipTypeResidential": MessageLookupByLibrary.simpleMessage("Residential"),
    "ipTypeUnknown": MessageLookupByLibrary.simpleMessage("Unknown type"),
    "ipVersion": MessageLookupByLibrary.simpleMessage("IP version"),
    "ipcidr": MessageLookupByLibrary.simpleMessage("IP/CIDR"),
    "ipv6Desc": MessageLookupByLibrary.simpleMessage(
      "IPv6 traffic is received only while IPv6 is on.",
    ),
    "ipv6InboundDesc": MessageLookupByLibrary.simpleMessage(
      "With IPv6 on, the VPN allows IPv6 inbound.",
    ),
    "ipv6Timeout": MessageLookupByLibrary.simpleMessage("IPv6 timeout (ms)"),
    "itemsCount": m45,
    "ja": MessageLookupByLibrary.simpleMessage("Japanese"),
    "justNow": MessageLookupByLibrary.simpleMessage("Just now"),
    "keepAliveIdle": MessageLookupByLibrary.simpleMessage(
      "TCP keep-alive idle",
    ),
    "keepAliveIntervalDesc": MessageLookupByLibrary.simpleMessage(
      "TCP keep-alive interval",
    ),
    "key": MessageLookupByLibrary.simpleMessage("Key"),
    "ko": MessageLookupByLibrary.simpleMessage("Korean"),
    "label": MessageLookupByLibrary.simpleMessage("Label"),
    "language": MessageLookupByLibrary.simpleMessage("Language"),
    "large": MessageLookupByLibrary.simpleMessage("Large"),
    "lastUpdated": MessageLookupByLibrary.simpleMessage("Last updated"),
    "launchInterrupted": MessageLookupByLibrary.simpleMessage(
      "Launch did not finish",
    ),
    "launchInterruptedTip": MessageLookupByLibrary.simpleMessage(
      "The app exited unexpectedly while it was starting up last time. Automatic setup was skipped for this launch; you can start it manually to retry.",
    ),
    "layout": MessageLookupByLibrary.simpleMessage("Layout"),
    "light": MessageLookupByLibrary.simpleMessage("Light"),
    "lineIssueTip": m46,
    "lineWrap": MessageLookupByLibrary.simpleMessage("Word wrap"),
    "link": MessageLookupByLibrary.simpleMessage("Link"),
    "liquidGlass": MessageLookupByLibrary.simpleMessage("Liquid Glass"),
    "list": MessageLookupByLibrary.simpleMessage("List"),
    "listen": MessageLookupByLibrary.simpleMessage("Listen"),
    "listenRoutingMark": MessageLookupByLibrary.simpleMessage(
      "Listen routing mark",
    ),
    "listenRoutingMarkDesc": MessageLookupByLibrary.simpleMessage(
      "Listen routing mark works only on Linux.",
    ),
    "liveConnections": MessageLookupByLibrary.simpleMessage("Live connections"),
    "loading": MessageLookupByLibrary.simpleMessage("Loading…"),
    "local": MessageLookupByLibrary.simpleMessage("Local"),
    "localBackupDesc": MessageLookupByLibrary.simpleMessage(
      "Back up data locally",
    ),
    "localImage": MessageLookupByLibrary.simpleMessage("Local image"),
    "localNetworkDeniedTip": MessageLookupByLibrary.simpleMessage(
      "Local network permission denied: using the gvisor stack, LAN is unreachable.",
    ),
    "localProxies": MessageLookupByLibrary.simpleMessage("Local proxies"),
    "locationPermission": MessageLookupByLibrary.simpleMessage(
      "Location permission",
    ),
    "locationPermissionDeniedMessage": MessageLookupByLibrary.simpleMessage(
      "Location permission was denied, so the current Wi-Fi name cannot be read. Please enable location permission manually in system settings.",
    ),
    "locationPermissionDesc": MessageLookupByLibrary.simpleMessage(
      "The system requires location permission to read the Wi-Fi name. On Android choose \"Allow all the time\", otherwise the Wi-Fi name cannot be read while the app is in the background.",
    ),
    "locationPermissionGuide": m47,
    "locationPermissionRequired": MessageLookupByLibrary.simpleMessage(
      "Location permission required",
    ),
    "log": MessageLookupByLibrary.simpleMessage("Log"),
    "logLevel": MessageLookupByLibrary.simpleMessage("Log level"),
    "logcat": MessageLookupByLibrary.simpleMessage("Logcat"),
    "logcatDesc": MessageLookupByLibrary.simpleMessage(
      "Turning off Logcat hides the logs entry.",
    ),
    "logs": MessageLookupByLibrary.simpleMessage("Logs"),
    "logsAndDiagnostics": MessageLookupByLibrary.simpleMessage(
      "Logs and diagnostics",
    ),
    "logsDesc": MessageLookupByLibrary.simpleMessage("Captured log records"),
    "logsTest": MessageLookupByLibrary.simpleMessage("Logs test"),
    "loopback": MessageLookupByLibrary.simpleMessage("UWP loopback exemption"),
    "loopbackDesc": MessageLookupByLibrary.simpleMessage(
      "Used for UWP loopback exemption",
    ),
    "loose": MessageLookupByLibrary.simpleMessage("Loose"),
    "manageNodes": MessageLookupByLibrary.simpleMessage("Manage nodes"),
    "matchCase": MessageLookupByLibrary.simpleMessage("Match case"),
    "matchSourceIp": MessageLookupByLibrary.simpleMessage("Match source IP"),
    "matchTarget": MessageLookupByLibrary.simpleMessage("MATCH-TARGET"),
    "matchTargetDesc": MessageLookupByLibrary.simpleMessage(
      "Where rules targeting MATCH-TARGET go. Defaults to the target of the final MATCH rule in this profile.",
    ),
    "matchTargetTitle": MessageLookupByLibrary.simpleMessage("Match target"),
    "maxFailedTimes": MessageLookupByLibrary.simpleMessage("Max failures"),
    "maxLengthTip": m48,
    "maximize": MessageLookupByLibrary.simpleMessage("Maximize"),
    "memoryAppResident": MessageLookupByLibrary.simpleMessage(
      "Resident memory",
    ),
    "memoryAppShared": MessageLookupByLibrary.simpleMessage("App & shared"),
    "memoryCoreHeapIdle": MessageLookupByLibrary.simpleMessage("Heap idle"),
    "memoryCoreHeapInuse": MessageLookupByLibrary.simpleMessage("Heap in use"),
    "memoryCoreNotRunning": MessageLookupByLibrary.simpleMessage(
      "Core is not running",
    ),
    "memoryCoreRuntime": MessageLookupByLibrary.simpleMessage(
      "Runtime overhead",
    ),
    "memoryCoreStack": MessageLookupByLibrary.simpleMessage("Goroutine stacks"),
    "memoryEstimateDesc": MessageLookupByLibrary.simpleMessage(
      "Estimated from process resident memory; it may differ from what the system reports.",
    ),
    "memoryEstimateSharedDesc": MessageLookupByLibrary.simpleMessage(
      "The Core runs inside the app process. Its share is estimated from runtime stats, and the rest counts as app and shared memory.",
    ),
    "memoryInfo": MessageLookupByLibrary.simpleMessage("Memory info"),
    "memoryInfoDesc": MessageLookupByLibrary.simpleMessage(
      "Memory the app and the core use",
    ),
    "memoryReleased": MessageLookupByLibrary.simpleMessage("Memory released"),
    "memoryReleasedSize": m49,
    "messageTest": MessageLookupByLibrary.simpleMessage("Message test"),
    "messageTestTip": MessageLookupByLibrary.simpleMessage(
      "This is a message.",
    ),
    "min": MessageLookupByLibrary.simpleMessage("Minimal"),
    "minimize": MessageLookupByLibrary.simpleMessage("Minimize"),
    "minimizeOnExit": MessageLookupByLibrary.simpleMessage("Minimize on exit"),
    "minimizeOnExitDesc": MessageLookupByLibrary.simpleMessage(
      "Override the default system exit behavior",
    ),
    "minutes": MessageLookupByLibrary.simpleMessage("minutes"),
    "minutesAgo": m50,
    "minutesAgoShort": m51,
    "mixedPort": MessageLookupByLibrary.simpleMessage("Mixed port"),
    "mode": MessageLookupByLibrary.simpleMessage("Mode"),
    "monochromeIcon": MessageLookupByLibrary.simpleMessage("Monochrome icon"),
    "monochromeScheme": MessageLookupByLibrary.simpleMessage("Monochrome"),
    "monthsAgo": m52,
    "monthsAgoShort": m53,
    "more": MessageLookupByLibrary.simpleMessage("More"),
    "multipleValuesTip": MessageLookupByLibrary.simpleMessage(
      "Separate multiple values with commas",
    ),
    "name": MessageLookupByLibrary.simpleMessage("Name"),
    "nameserver": MessageLookupByLibrary.simpleMessage("Nameserver"),
    "nameserverDesc": MessageLookupByLibrary.simpleMessage(
      "Used to resolve domains",
    ),
    "nameserverPolicy": MessageLookupByLibrary.simpleMessage(
      "Nameserver policy",
    ),
    "nameserverPolicyDesc": MessageLookupByLibrary.simpleMessage(
      "Specify the nameserver policy for matching domains",
    ),
    "navigationBarStyle": MessageLookupByLibrary.simpleMessage("Bottom bar"),
    "network": MessageLookupByLibrary.simpleMessage("Network"),
    "networkAccessDeniedError": m54,
    "networkBadResponseError": m55,
    "networkCancelledError": MessageLookupByLibrary.simpleMessage(
      "The request was cancelled",
    ),
    "networkConnectionError": MessageLookupByLibrary.simpleMessage(
      "Couldn\'t connect to the server. Check your network connection or proxy settings",
    ),
    "networkDesc": MessageLookupByLibrary.simpleMessage(
      "Adjust network-related settings",
    ),
    "networkDetection": MessageLookupByLibrary.simpleMessage(
      "Network detection",
    ),
    "networkException": MessageLookupByLibrary.simpleMessage(
      "Network error, please check your connection and try again",
    ),
    "networkHostLookupError": MessageLookupByLibrary.simpleMessage(
      "Couldn\'t resolve the server address. Check that the URL is correct and DNS is working",
    ),
    "networkName": MessageLookupByLibrary.simpleMessage("Network name"),
    "networkNotFoundError": m56,
    "networkRateLimitedError": MessageLookupByLibrary.simpleMessage(
      "Too many requests (HTTP 429). Wait a moment and try again",
    ),
    "networkRequestFailed": m57,
    "networkSecret": MessageLookupByLibrary.simpleMessage("Network secret"),
    "networkServerError": m58,
    "networkSpeed": MessageLookupByLibrary.simpleMessage("Network speed"),
    "networkTakeover": MessageLookupByLibrary.simpleMessage("Traffic takeover"),
    "networkTimeoutError": MessageLookupByLibrary.simpleMessage(
      "The request timed out. Check your network or proxy, then try again",
    ),
    "networkTlsError": MessageLookupByLibrary.simpleMessage(
      "Secure connection failed. The server\'s certificate may be invalid, or the connection is being intercepted",
    ),
    "networkType": MessageLookupByLibrary.simpleMessage("Network type"),
    "neutralScheme": MessageLookupByLibrary.simpleMessage("Neutral"),
    "nextMatch": MessageLookupByLibrary.simpleMessage("Next match"),
    "no": MessageLookupByLibrary.simpleMessage("No"),
    "noData": MessageLookupByLibrary.simpleMessage("No data"),
    "noHotKey": MessageLookupByLibrary.simpleMessage("No hotkeys yet"),
    "noInfo": MessageLookupByLibrary.simpleMessage("No info"),
    "noLongerRemind": MessageLookupByLibrary.simpleMessage(
      "Don\'t remind me again",
    ),
    "noNetwork": MessageLookupByLibrary.simpleMessage("No network"),
    "noNetworkApp": MessageLookupByLibrary.simpleMessage("No-network apps"),
    "noProxyNodes": MessageLookupByLibrary.simpleMessage(
      "No nodes in this profile yet",
    ),
    "noProxySet": MessageLookupByLibrary.simpleMessage("No proxy configured"),
    "noRecords": MessageLookupByLibrary.simpleMessage("No records"),
    "noResolve": MessageLookupByLibrary.simpleMessage("Don\'t resolve IP"),
    "noResolveHostname": MessageLookupByLibrary.simpleMessage(
      "Don\'t resolve hostname",
    ),
    "noSearchResults": MessageLookupByLibrary.simpleMessage(
      "No matching results",
    ),
    "nodes": MessageLookupByLibrary.simpleMessage("Nodes"),
    "nonTextProviderFile": MessageLookupByLibrary.simpleMessage(
      "This external resource is not a text file",
    ),
    "none": MessageLookupByLibrary.simpleMessage("None"),
    "notRunning": MessageLookupByLibrary.simpleMessage("Not running"),
    "notSelectedTip": MessageLookupByLibrary.simpleMessage(
      "The current proxy group cannot be selected",
    ),
    "ntpInterval": MessageLookupByLibrary.simpleMessage(
      "Sync interval (minutes)",
    ),
    "ntpStatusDesc": MessageLookupByLibrary.simpleMessage(
      "NTP takes the time from an NTP server instead of the system clock.",
    ),
    "nullProfileDesc": MessageLookupByLibrary.simpleMessage(
      "Add a profile to get started",
    ),
    "nullTip": m59,
    "numberRangeTip": m60,
    "numberTip": m61,
    "obfs": MessageLookupByLibrary.simpleMessage("Obfuscation"),
    "obfsHost": MessageLookupByLibrary.simpleMessage("Obfuscation host"),
    "obfsMode": MessageLookupByLibrary.simpleMessage("Obfuscation mode"),
    "obfsParam": MessageLookupByLibrary.simpleMessage("Obfuscation parameter"),
    "obfsPassword": MessageLookupByLibrary.simpleMessage(
      "Obfuscation password",
    ),
    "onDemand": MessageLookupByLibrary.simpleMessage("On demand"),
    "onDemandDesc": MessageLookupByLibrary.simpleMessage(
      "On demand pauses the proxy on excluded Wi-Fi.",
    ),
    "onlyIcon": MessageLookupByLibrary.simpleMessage("Icon only"),
    "onlyStatisticsProxy": MessageLookupByLibrary.simpleMessage(
      "Only count proxy traffic",
    ),
    "onlyStatisticsProxyDesc": MessageLookupByLibrary.simpleMessage(
      "When enabled, only proxy traffic is counted",
    ),
    "openInBrowser": MessageLookupByLibrary.simpleMessage("Open in browser"),
    "optional": MessageLookupByLibrary.simpleMessage("Optional"),
    "options": MessageLookupByLibrary.simpleMessage("Options"),
    "other": MessageLookupByLibrary.simpleMessage("Other"),
    "otherContributors": MessageLookupByLibrary.simpleMessage(
      "Other contributors",
    ),
    "outbound": MessageLookupByLibrary.simpleMessage("Outbound"),
    "outboundExit": MessageLookupByLibrary.simpleMessage("Exit"),
    "outboundIp": MessageLookupByLibrary.simpleMessage("Outbound IP"),
    "outboundMode": MessageLookupByLibrary.simpleMessage("Outbound mode"),
    "override": MessageLookupByLibrary.simpleMessage("Override"),
    "overrideDestination": MessageLookupByLibrary.simpleMessage(
      "Override destination",
    ),
    "overrideDestinationDesc": MessageLookupByLibrary.simpleMessage(
      "Override destination connects to the sniffed domain instead of the original address.",
    ),
    "overrideDns": MessageLookupByLibrary.simpleMessage("Override DNS"),
    "overrideDnsDesc": MessageLookupByLibrary.simpleMessage(
      "When enabled, the DNS options in the profile are overridden",
    ),
    "overrideEntries": MessageLookupByLibrary.simpleMessage("Override entries"),
    "overrideMode": MessageLookupByLibrary.simpleMessage("Override mode"),
    "overrideScript": MessageLookupByLibrary.simpleMessage("Override script"),
    "overwriteTypeCustom": MessageLookupByLibrary.simpleMessage("Custom"),
    "overwriteTypeCustomDesc": MessageLookupByLibrary.simpleMessage(
      "Custom mode: fully customize proxy groups and rules",
    ),
    "palette": MessageLookupByLibrary.simpleMessage("Palette"),
    "parsePureIp": MessageLookupByLibrary.simpleMessage("Parse pure IP"),
    "parsePureIpDesc": MessageLookupByLibrary.simpleMessage(
      "Parse pure IP sniffs connections that carry only an IP address.",
    ),
    "password": MessageLookupByLibrary.simpleMessage("Password"),
    "paste": MessageLookupByLibrary.simpleMessage("Paste"),
    "pasteFromClipboard": MessageLookupByLibrary.simpleMessage(
      "Paste from clipboard",
    ),
    "peers": MessageLookupByLibrary.simpleMessage("Peers"),
    "pickFromAlbum": MessageLookupByLibrary.simpleMessage("Choose from album"),
    "pinWindow": MessageLookupByLibrary.simpleMessage("Pin window"),
    "pleaseBindWebDAV": MessageLookupByLibrary.simpleMessage(
      "Please bind WebDAV",
    ),
    "pleaseEnterScriptName": MessageLookupByLibrary.simpleMessage(
      "Please enter a script name",
    ),
    "pleaseUploadValidQrcode": MessageLookupByLibrary.simpleMessage(
      "Please upload a valid QR code",
    ),
    "plugin": MessageLookupByLibrary.simpleMessage("Plugin"),
    "pluginCipher": MessageLookupByLibrary.simpleMessage("Plugin cipher"),
    "pluginHost": MessageLookupByLibrary.simpleMessage("Plugin host"),
    "pluginMode": MessageLookupByLibrary.simpleMessage("Plugin mode"),
    "pluginPassword": MessageLookupByLibrary.simpleMessage("Plugin password"),
    "pluginPath": MessageLookupByLibrary.simpleMessage("Plugin path"),
    "pluginUsername": MessageLookupByLibrary.simpleMessage("Plugin username"),
    "port": MessageLookupByLibrary.simpleMessage("Port"),
    "portConflictTip": MessageLookupByLibrary.simpleMessage(
      "Please enter a different port",
    ),
    "portHopping": MessageLookupByLibrary.simpleMessage("Port hopping"),
    "portTip": m62,
    "portValue": m63,
    "ports": MessageLookupByLibrary.simpleMessage("Ports"),
    "preSharedKey": MessageLookupByLibrary.simpleMessage("Pre-shared key"),
    "preferH3Desc": MessageLookupByLibrary.simpleMessage(
      "Prefer HTTP/3 for DoH",
    ),
    "preferred": MessageLookupByLibrary.simpleMessage("Preferred"),
    "prerequisites": MessageLookupByLibrary.simpleMessage("Prerequisites"),
    "pressKeyboard": MessageLookupByLibrary.simpleMessage(
      "Press a key combination",
    ),
    "preview": MessageLookupByLibrary.simpleMessage("Preview"),
    "previousMatch": MessageLookupByLibrary.simpleMessage("Previous match"),
    "privateKey": MessageLookupByLibrary.simpleMessage("Private key"),
    "privateKeyPassphrase": MessageLookupByLibrary.simpleMessage(
      "Private key passphrase",
    ),
    "process": MessageLookupByLibrary.simpleMessage("Process"),
    "profile": MessageLookupByLibrary.simpleMessage("Profile"),
    "profileAutoUpdateIntervalInvalidValidationDesc":
        MessageLookupByLibrary.simpleMessage("Please enter a valid interval"),
    "profileAutoUpdateIntervalNullValidationDesc":
        MessageLookupByLibrary.simpleMessage(
          "Please enter the auto-update interval",
        ),
    "profileConvertedToLocal": MessageLookupByLibrary.simpleMessage(
      "Converted to a local profile",
    ),
    "profileDaysLeft": m64,
    "profileExpiresIn": m65,
    "profileHasUpdate": MessageLookupByLibrary.simpleMessage(
      "The profile has been modified. Turn off auto update?",
    ),
    "profileNameNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Please enter the profile name",
    ),
    "profileSettingsDesc": MessageLookupByLibrary.simpleMessage(
      "Applies to this profile only; anything not added uses its default.",
    ),
    "profileTunSettingsDesc": MessageLookupByLibrary.simpleMessage(
      "Applies to this profile only and takes precedence over the TUN override entries in the network settings.",
    ),
    "profileUpdatedAt": m66,
    "profileUrlInvalidValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Please enter a valid profile URL",
    ),
    "profileUrlNullValidationDesc": MessageLookupByLibrary.simpleMessage(
      "Please enter the profile URL",
    ),
    "profiles": MessageLookupByLibrary.simpleMessage("Profiles"),
    "profilesSort": MessageLookupByLibrary.simpleMessage("Sort profiles"),
    "project": MessageLookupByLibrary.simpleMessage("Project"),
    "protocol": MessageLookupByLibrary.simpleMessage("Protocol"),
    "protocolParam": MessageLookupByLibrary.simpleMessage("Protocol parameter"),
    "protocolVersion": MessageLookupByLibrary.simpleMessage("Protocol version"),
    "providerInUse": m67,
    "providerUrlTip": MessageLookupByLibrary.simpleMessage(
      "Only remote providers are supported",
    ),
    "providers": MessageLookupByLibrary.simpleMessage("External resources"),
    "proxies": MessageLookupByLibrary.simpleMessage("Proxies"),
    "proxiesCount": m68,
    "proxiesEmpty": MessageLookupByLibrary.simpleMessage("Proxies are empty"),
    "proxiesProfileLabel": m69,
    "proxiesRemovedTip": m70,
    "proxiesReplacedTip": m71,
    "proxyChainClear": MessageLookupByLibrary.simpleMessage("Remove chain"),
    "proxyChainCleared": MessageLookupByLibrary.simpleMessage(
      "Proxy chain removed",
    ),
    "proxyChainCreated": m72,
    "proxyChainDefaultName": MessageLookupByLibrary.simpleMessage(
      "Proxy Chain",
    ),
    "proxyChainExisting": m73,
    "proxyChainExit": MessageLookupByLibrary.simpleMessage("Exit node"),
    "proxyChainExitHint": MessageLookupByLibrary.simpleMessage(
      "The one that finally reaches the internet",
    ),
    "proxyChainFront": MessageLookupByLibrary.simpleMessage("Front proxy"),
    "proxyChainFrontHint": MessageLookupByLibrary.simpleMessage(
      "Traffic goes through it first — a node or a group",
    ),
    "proxyChainGroupsSection": MessageLookupByLibrary.simpleMessage("Groups"),
    "proxyChainNameLabel": MessageLookupByLibrary.simpleMessage("Chain name"),
    "proxyChainNoNodes": MessageLookupByLibrary.simpleMessage(
      "This profile has no inline nodes. A chain is written into the profile itself, so nodes coming from a proxy provider cannot be chained — add a node first.",
    ),
    "proxyChainNodeCopied": m74,
    "proxyChainNodeReused": m75,
    "proxyChainNodesSection": MessageLookupByLibrary.simpleMessage("Nodes"),
    "proxyChainPickExit": MessageLookupByLibrary.simpleMessage(
      "Choose an exit node",
    ),
    "proxyChainPickFront": MessageLookupByLibrary.simpleMessage(
      "Choose a front proxy",
    ),
    "proxyChainPickerTopHint": MessageLookupByLibrary.simpleMessage(
      "Only the 20 fastest nodes per profile are listed; use search to find more",
    ),
    "proxyChainSaved": m76,
    "proxyChains": MessageLookupByLibrary.simpleMessage("Proxy chain"),
    "proxyDelayTestHint": MessageLookupByLibrary.simpleMessage("Tap to test"),
    "proxyDelayTestNow": MessageLookupByLibrary.simpleMessage("Test"),
    "proxyDetectedAbnormal": MessageLookupByLibrary.simpleMessage(
      "The selected proxies are abnormal",
    ),
    "proxyExitFailed": MessageLookupByLibrary.simpleMessage("Failed"),
    "proxyExitMismatch": MessageLookupByLibrary.simpleMessage(
      "Differs from the region in its name",
    ),
    "proxyExitTest": MessageLookupByLibrary.simpleMessage("Test exit"),
    "proxyExitTestHint": MessageLookupByLibrary.simpleMessage(
      "Test exit: measure the real exit region of this node",
    ),
    "proxyFieldAlpn": MessageLookupByLibrary.simpleMessage(
      "ALPN (comma separated)",
    ),
    "proxyFieldAlterId": MessageLookupByLibrary.simpleMessage("alterId"),
    "proxyFieldCipher": MessageLookupByLibrary.simpleMessage("Cipher"),
    "proxyFieldDown": MessageLookupByLibrary.simpleMessage(
      "Download bandwidth",
    ),
    "proxyFieldFingerprint": MessageLookupByLibrary.simpleMessage(
      "Client fingerprint",
    ),
    "proxyFieldFlow": MessageLookupByLibrary.simpleMessage("Flow"),
    "proxyFieldGrpcService": MessageLookupByLibrary.simpleMessage(
      "gRPC service name",
    ),
    "proxyFieldHopInterval": MessageLookupByLibrary.simpleMessage(
      "Hop interval (s)",
    ),
    "proxyFieldName": MessageLookupByLibrary.simpleMessage("Node name"),
    "proxyFieldNetwork": MessageLookupByLibrary.simpleMessage("Transport"),
    "proxyFieldObfs": MessageLookupByLibrary.simpleMessage("Obfuscation"),
    "proxyFieldObfsPassword": MessageLookupByLibrary.simpleMessage(
      "Obfuscation password",
    ),
    "proxyFieldPassword": MessageLookupByLibrary.simpleMessage("Password"),
    "proxyFieldPort": MessageLookupByLibrary.simpleMessage("Port"),
    "proxyFieldPorts": MessageLookupByLibrary.simpleMessage(
      "Port range (e.g. 20000-30000)",
    ),
    "proxyFieldPublicKey": MessageLookupByLibrary.simpleMessage(
      "Reality public key",
    ),
    "proxyFieldReality": MessageLookupByLibrary.simpleMessage("Enable Reality"),
    "proxyFieldServer": MessageLookupByLibrary.simpleMessage("Server"),
    "proxyFieldShortId": MessageLookupByLibrary.simpleMessage(
      "Reality Short ID",
    ),
    "proxyFieldSkipCertVerify": MessageLookupByLibrary.simpleMessage(
      "Skip certificate verification",
    ),
    "proxyFieldSni": MessageLookupByLibrary.simpleMessage("SNI"),
    "proxyFieldTls": MessageLookupByLibrary.simpleMessage("TLS"),
    "proxyFieldUdp": MessageLookupByLibrary.simpleMessage("Enable UDP"),
    "proxyFieldUp": MessageLookupByLibrary.simpleMessage("Upload bandwidth"),
    "proxyFieldUsername": MessageLookupByLibrary.simpleMessage("Username"),
    "proxyFieldUuid": MessageLookupByLibrary.simpleMessage("UUID"),
    "proxyFieldWsHost": MessageLookupByLibrary.simpleMessage("WS Host"),
    "proxyFieldWsPath": MessageLookupByLibrary.simpleMessage("WS path"),
    "proxyFilter": MessageLookupByLibrary.simpleMessage("Proxy filter"),
    "proxyFormAdvanced": MessageLookupByLibrary.simpleMessage("Advanced"),
    "proxyFormMissingRequired": MessageLookupByLibrary.simpleMessage(
      "Required fields are missing",
    ),
    "proxyFormOptionNone": MessageLookupByLibrary.simpleMessage("None"),
    "proxyGroup": MessageLookupByLibrary.simpleMessage("Proxy group"),
    "proxyGroupDetectedAbnormal": MessageLookupByLibrary.simpleMessage(
      "The current proxy group is abnormal",
    ),
    "proxyGroupEmpty": MessageLookupByLibrary.simpleMessage(
      "Proxy group is empty",
    ),
    "proxyGroupInUse": m77,
    "proxyGroupNameDuplicate": MessageLookupByLibrary.simpleMessage(
      "Duplicate proxy group name",
    ),
    "proxyGroupNameEmpty": MessageLookupByLibrary.simpleMessage(
      "Proxy group name cannot be empty",
    ),
    "proxyGroupsAfterStart": MessageLookupByLibrary.simpleMessage(
      "Groups show up here once the core starts",
    ),
    "proxyGroupsCount": m78,
    "proxyNameserver": MessageLookupByLibrary.simpleMessage("Proxy nameserver"),
    "proxyNameserverDesc": MessageLookupByLibrary.simpleMessage(
      "Used to resolve proxy node domains",
    ),
    "proxyProviderDetectedAbnormal": MessageLookupByLibrary.simpleMessage(
      "The selected proxy providers are abnormal",
    ),
    "proxyProviders": MessageLookupByLibrary.simpleMessage("Proxy providers"),
    "proxyProvidersEmpty": MessageLookupByLibrary.simpleMessage(
      "Proxy providers are empty",
    ),
    "proxyProvidersNotEmpty": MessageLookupByLibrary.simpleMessage(
      "Proxy providers cannot be empty",
    ),
    "proxyRegionAll": MessageLookupByLibrary.simpleMessage("All"),
    "proxyRegionCdn": MessageLookupByLibrary.simpleMessage("CF relay"),
    "proxyRegionFilter": MessageLookupByLibrary.simpleMessage(
      "Filter by region",
    ),
    "proxyType": MessageLookupByLibrary.simpleMessage("Proxy type"),
    "pruneCache": MessageLookupByLibrary.simpleMessage("Prune cache"),
    "publicKey": MessageLookupByLibrary.simpleMessage("Public key"),
    "pureBlack": MessageLookupByLibrary.simpleMessage("Pure black"),
    "pureBlackMode": MessageLookupByLibrary.simpleMessage("Pure black mode"),
    "qrcode": MessageLookupByLibrary.simpleMessage("QR code"),
    "qrcodeDesc": MessageLookupByLibrary.simpleMessage(
      "Scan a QR code to obtain a profile",
    ),
    "qrcodeTooLongTip": MessageLookupByLibrary.simpleMessage(
      "This link is too long for a QR code. Use Copy link instead.",
    ),
    "quickActions": MessageLookupByLibrary.simpleMessage("Quick actions"),
    "quickEdit": MessageLookupByLibrary.simpleMessage("Quick edit"),
    "quickFill": MessageLookupByLibrary.simpleMessage("Quick fill"),
    "rainbowScheme": MessageLookupByLibrary.simpleMessage("Rainbow"),
    "recentRequests": MessageLookupByLibrary.simpleMessage("Recent requests"),
    "recommendedIcons": MessageLookupByLibrary.simpleMessage("Suggested"),
    "recordType": MessageLookupByLibrary.simpleMessage("Record type"),
    "redirPort": MessageLookupByLibrary.simpleMessage("Redir port"),
    "redo": MessageLookupByLibrary.simpleMessage("Redo"),
    "regex": MessageLookupByLibrary.simpleMessage("Regex"),
    "relayGroupFixed": m79,
    "relayGroupRemovedConfirm": m80,
    "relayGroupRemovedTip": MessageLookupByLibrary.simpleMessage(
      "The relay group type was removed by the core — it breaks the whole profile",
    ),
    "releaseMemory": MessageLookupByLibrary.simpleMessage("Release memory"),
    "releaseMemoryFailed": MessageLookupByLibrary.simpleMessage(
      "Failed to release memory",
    ),
    "remote": MessageLookupByLibrary.simpleMessage("Remote"),
    "remoteBackupDesc": MessageLookupByLibrary.simpleMessage(
      "Back up data to WebDAV",
    ),
    "remoteDestination": MessageLookupByLibrary.simpleMessage(
      "Remote destination",
    ),
    "remoteDnsResolve": MessageLookupByLibrary.simpleMessage(
      "Remote DNS resolution",
    ),
    "remove": MessageLookupByLibrary.simpleMessage("Remove"),
    "rename": MessageLookupByLibrary.simpleMessage("Rename"),
    "replace": MessageLookupByLibrary.simpleMessage("Replace"),
    "replaceAll": MessageLookupByLibrary.simpleMessage("Replace all"),
    "request": MessageLookupByLibrary.simpleMessage("Request"),
    "requestHeaders": MessageLookupByLibrary.simpleMessage("Request headers"),
    "requests": MessageLookupByLibrary.simpleMessage("Requests"),
    "requestsAndUpdates": MessageLookupByLibrary.simpleMessage(
      "Requests and updates",
    ),
    "requestsDesc": MessageLookupByLibrary.simpleMessage(
      "View recent request records",
    ),
    "required": MessageLookupByLibrary.simpleMessage("Required"),
    "reset": MessageLookupByLibrary.simpleMessage("Reset"),
    "resetPageChangesTip": MessageLookupByLibrary.simpleMessage(
      "This page has changes. Are you sure you want to reset?",
    ),
    "resetTip": MessageLookupByLibrary.simpleMessage(
      "Are you sure you want to reset?",
    ),
    "resourceUpdateInterval": MessageLookupByLibrary.simpleMessage(
      "Auto-update interval",
    ),
    "resourceUpdateIntervalTip": MessageLookupByLibrary.simpleMessage(
      "The auto-update interval must be greater than 0",
    ),
    "resources": MessageLookupByLibrary.simpleMessage("Resources"),
    "resourcesDesc": MessageLookupByLibrary.simpleMessage(
      "Information about external resources",
    ),
    "respectRules": MessageLookupByLibrary.simpleMessage("Respect rules"),
    "respectRulesDesc": MessageLookupByLibrary.simpleMessage(
      "Respect rules routes DNS connections by the rules and needs a Proxy Server Nameserver.",
    ),
    "responseCode": MessageLookupByLibrary.simpleMessage("Response code"),
    "restart": MessageLookupByLibrary.simpleMessage("Restart"),
    "restartCoreTip": MessageLookupByLibrary.simpleMessage(
      "Are you sure you want to restart the core?",
    ),
    "restore": MessageLookupByLibrary.simpleMessage("Restore"),
    "restoreAllData": MessageLookupByLibrary.simpleMessage("Restore all data"),
    "restoreException": MessageLookupByLibrary.simpleMessage("Restore error"),
    "restoreFromFileDesc": MessageLookupByLibrary.simpleMessage(
      "Restore data from a file",
    ),
    "restoreFromWebDAVDesc": MessageLookupByLibrary.simpleMessage(
      "Restore data from WebDAV",
    ),
    "restoreOnlyConfig": MessageLookupByLibrary.simpleMessage(
      "Restore profiles only",
    ),
    "restoreStrategy": MessageLookupByLibrary.simpleMessage("Restore strategy"),
    "restoreStrategyCompatible": MessageLookupByLibrary.simpleMessage(
      "Compatible",
    ),
    "restoreStrategyOverride": MessageLookupByLibrary.simpleMessage("Override"),
    "restoreSuccess": MessageLookupByLibrary.simpleMessage(
      "Restore successful",
    ),
    "result": MessageLookupByLibrary.simpleMessage("Result"),
    "retry": MessageLookupByLibrary.simpleMessage("Retry"),
    "routeAddress": MessageLookupByLibrary.simpleMessage("Route addresses"),
    "routeAddressDesc": MessageLookupByLibrary.simpleMessage(
      "Configure the listened route addresses",
    ),
    "routeExcludeAddress": MessageLookupByLibrary.simpleMessage(
      "Route exclude addresses",
    ),
    "routeMode": MessageLookupByLibrary.simpleMessage("Route mode"),
    "routeModeBypassPrivate": MessageLookupByLibrary.simpleMessage(
      "Bypass private addresses",
    ),
    "routeModeConfig": MessageLookupByLibrary.simpleMessage("Use config"),
    "routingMark": MessageLookupByLibrary.simpleMessage("Routing mark"),
    "ru": MessageLookupByLibrary.simpleMessage("Russian"),
    "rule": MessageLookupByLibrary.simpleMessage("Rule"),
    "ruleActionAndDesc": MessageLookupByLibrary.simpleMessage(
      "Logical rule AND",
    ),
    "ruleActionDomainDesc": MessageLookupByLibrary.simpleMessage(
      "Match the full domain",
    ),
    "ruleActionDomainKeywordDesc": MessageLookupByLibrary.simpleMessage(
      "Match a domain keyword",
    ),
    "ruleActionDomainRegexDesc": MessageLookupByLibrary.simpleMessage(
      "Match a domain regex",
    ),
    "ruleActionDomainSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "Match a domain suffix",
    ),
    "ruleActionDomainWildcardDesc": MessageLookupByLibrary.simpleMessage(
      "Wildcard match; only * and ? are supported",
    ),
    "ruleActionDscpDesc": MessageLookupByLibrary.simpleMessage(
      "Match the DSCP mark (tproxy UDP inbound only)",
    ),
    "ruleActionDstPortDesc": MessageLookupByLibrary.simpleMessage(
      "Match the destination port range",
    ),
    "ruleActionGeoipDesc": MessageLookupByLibrary.simpleMessage(
      "Match the IP\'s country code",
    ),
    "ruleActionGeositeDesc": MessageLookupByLibrary.simpleMessage(
      "Match domains in Geosite",
    ),
    "ruleActionInNameDesc": MessageLookupByLibrary.simpleMessage(
      "Match the inbound name",
    ),
    "ruleActionInPortDesc": MessageLookupByLibrary.simpleMessage(
      "Match the inbound port",
    ),
    "ruleActionInTypeDesc": MessageLookupByLibrary.simpleMessage(
      "Match the inbound type",
    ),
    "ruleActionInUserDesc": MessageLookupByLibrary.simpleMessage(
      "Match the inbound username; separate multiple usernames with /",
    ),
    "ruleActionIpAsnDesc": MessageLookupByLibrary.simpleMessage(
      "Match the IP\'s ASN",
    ),
    "ruleActionIpCidr6Desc": MessageLookupByLibrary.simpleMessage(
      "Match an IP address range; IP-CIDR6 is just an alias",
    ),
    "ruleActionIpCidrDesc": MessageLookupByLibrary.simpleMessage(
      "Match an IP address range",
    ),
    "ruleActionIpSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "Match an IP suffix range",
    ),
    "ruleActionMatchDesc": MessageLookupByLibrary.simpleMessage(
      "Match all requests, no conditions needed",
    ),
    "ruleActionNetworkDesc": MessageLookupByLibrary.simpleMessage(
      "Match TCP or UDP",
    ),
    "ruleActionNotDesc": MessageLookupByLibrary.simpleMessage(
      "Logical rule NOT",
    ),
    "ruleActionOrDesc": MessageLookupByLibrary.simpleMessage("Logical rule OR"),
    "ruleActionProcessNameDesc": MessageLookupByLibrary.simpleMessage(
      "Match by process name; matches the package name on Android",
    ),
    "ruleActionProcessNameRegexDesc": MessageLookupByLibrary.simpleMessage(
      "Match by process name regex; matches the package name on Android",
    ),
    "ruleActionProcessNameWildcardDesc": MessageLookupByLibrary.simpleMessage(
      "Match by process name wildcard; only * and ? are supported",
    ),
    "ruleActionProcessPathDesc": MessageLookupByLibrary.simpleMessage(
      "Match by the full process path",
    ),
    "ruleActionProcessPathRegexDesc": MessageLookupByLibrary.simpleMessage(
      "Match by process path regex",
    ),
    "ruleActionProcessPathWildcardDesc": MessageLookupByLibrary.simpleMessage(
      "Match by process path wildcard; only * and ? are supported",
    ),
    "ruleActionRematchNameDesc": MessageLookupByLibrary.simpleMessage(
      "Match the rematch name; separate multiple names with /",
    ),
    "ruleActionRuleSetDesc": MessageLookupByLibrary.simpleMessage(
      "Reference a rule set; requires rule-providers",
    ),
    "ruleActionSrcGeoipDesc": MessageLookupByLibrary.simpleMessage(
      "Match the source IP\'s country code",
    ),
    "ruleActionSrcIpAsnDesc": MessageLookupByLibrary.simpleMessage(
      "Match the source IP\'s ASN",
    ),
    "ruleActionSrcIpCidrDesc": MessageLookupByLibrary.simpleMessage(
      "Match a source IP address range",
    ),
    "ruleActionSrcIpSuffixDesc": MessageLookupByLibrary.simpleMessage(
      "Match a source IP suffix range",
    ),
    "ruleActionSrcPortDesc": MessageLookupByLibrary.simpleMessage(
      "Match the source port range",
    ),
    "ruleActionSubRuleDesc": MessageLookupByLibrary.simpleMessage(
      "Match into a sub-rule; mind the parentheses",
    ),
    "ruleActionUidDesc": MessageLookupByLibrary.simpleMessage(
      "Match the Linux user ID",
    ),
    "ruleEmpty": MessageLookupByLibrary.simpleMessage("Rule is empty"),
    "ruleListInvalid": MessageLookupByLibrary.simpleMessage(
      "The rules must be a YAML list with one rule per item, such as - DOMAIN,example.com,DIRECT",
    ),
    "ruleName": MessageLookupByLibrary.simpleMessage("Rule name"),
    "rulePresetBittorrentDirect": MessageLookupByLibrary.simpleMessage(
      "BitTorrent direct",
    ),
    "rulePresetBlockDot": MessageLookupByLibrary.simpleMessage(
      "Block DNS over TLS",
    ),
    "rulePresetBlockLoopback": MessageLookupByLibrary.simpleMessage(
      "Block proxy loopback",
    ),
    "rulePresetBlockQuic": MessageLookupByLibrary.simpleMessage("Block QUIC"),
    "rulePresetBlockStun": MessageLookupByLibrary.simpleMessage("Block STUN"),
    "rulePresetLanDirect": MessageLookupByLibrary.simpleMessage("LAN direct"),
    "rulePresetSystemServicesDirect": MessageLookupByLibrary.simpleMessage(
      "Apple and Microsoft direct",
    ),
    "ruleProviders": MessageLookupByLibrary.simpleMessage("Rule providers"),
    "ruleSet": MessageLookupByLibrary.simpleMessage("Rule set"),
    "ruleSetEmptyTip": MessageLookupByLibrary.simpleMessage(
      "The rule set has no usable entries",
    ),
    "ruleSetInvalidTip": MessageLookupByLibrary.simpleMessage(
      "This mrs file cannot be read",
    ),
    "ruleSetMixedTip": MessageLookupByLibrary.simpleMessage(
      "The rule set mixes domains and IP ranges, so its type cannot be told",
    ),
    "ruleTarget": MessageLookupByLibrary.simpleMessage("Rule target"),
    "ruleTextInvalid": MessageLookupByLibrary.simpleMessage(
      "The rule must start with a supported type, such as DOMAIN,example.com,DIRECT",
    ),
    "rules": MessageLookupByLibrary.simpleMessage("Rules"),
    "rulesCount": m81,
    "runTime": MessageLookupByLibrary.simpleMessage("Run time"),
    "running": MessageLookupByLibrary.simpleMessage("Running"),
    "runtimeConfig": MessageLookupByLibrary.simpleMessage("Runtime config"),
    "safeMode": MessageLookupByLibrary.simpleMessage("Safe mode"),
    "safeModeAppTitle": m82,
    "saturation": MessageLookupByLibrary.simpleMessage("Saturation"),
    "save": MessageLookupByLibrary.simpleMessage("Save"),
    "saveChanges": MessageLookupByLibrary.simpleMessage("Save the changes?"),
    "script": MessageLookupByLibrary.simpleMessage("Script"),
    "scriptModeDesc": MessageLookupByLibrary.simpleMessage(
      "Script mode: rewrites the whole profile with an extension script",
    ),
    "scrollToSelected": MessageLookupByLibrary.simpleMessage(
      "Scroll to selected",
    ),
    "search": MessageLookupByLibrary.simpleMessage("Search"),
    "seconds": MessageLookupByLibrary.simpleMessage("seconds"),
    "secondsCount": m83,
    "secretKey": MessageLookupByLibrary.simpleMessage("Key"),
    "sectionsInEffect": m84,
    "select": MessageLookupByLibrary.simpleMessage("Select"),
    "selectAll": MessageLookupByLibrary.simpleMessage("Select all"),
    "selectMatchTarget": MessageLookupByLibrary.simpleMessage(
      "Select MATCH-TARGET",
    ),
    "selectProxies": MessageLookupByLibrary.simpleMessage("Select proxies"),
    "selectProxyProviders": MessageLookupByLibrary.simpleMessage(
      "Select proxy providers",
    ),
    "selectRuleSet": MessageLookupByLibrary.simpleMessage(
      "Please select a rule set",
    ),
    "selectSplitStrategy": MessageLookupByLibrary.simpleMessage(
      "Please select a split strategy",
    ),
    "selectSubRule": MessageLookupByLibrary.simpleMessage(
      "Please select a sub-rule",
    ),
    "selected": MessageLookupByLibrary.simpleMessage("Selected"),
    "selectedCountTitle": m85,
    "send": MessageLookupByLibrary.simpleMessage("Send"),
    "sendFromPhone": MessageLookupByLibrary.simpleMessage("Send from phone"),
    "sendFromPhoneConfirmTitle": MessageLookupByLibrary.simpleMessage(
      "Import the link from your phone?",
    ),
    "sendFromPhoneNoNetwork": MessageLookupByLibrary.simpleMessage(
      "This device is not connected to a local network",
    ),
    "sendFromPhonePageHint": MessageLookupByLibrary.simpleMessage(
      "Subscription link or proxy share link",
    ),
    "sendFromPhonePageSent": MessageLookupByLibrary.simpleMessage(
      "Sent. Confirm the import on the other device.",
    ),
    "sendFromPhonePageTitle": MessageLookupByLibrary.simpleMessage(
      "Send a link to BiLoom",
    ),
    "sendFromPhonePermissionDenied": MessageLookupByLibrary.simpleMessage(
      "Receiving a link from your phone needs the Nearby devices permission, which lets BiLoom reach the local network. Turn it on in the app\'s settings.",
    ),
    "sendFromPhoneTip": MessageLookupByLibrary.simpleMessage(
      "Scan the code with your phone\'s camera and paste the link on the page that opens. Both devices need to be on the same network.",
    ),
    "server": MessageLookupByLibrary.simpleMessage("Server"),
    "serviceAbnormalCount": m86,
    "serviceAllAvailable": MessageLookupByLibrary.simpleMessage(
      "All available",
    ),
    "serviceAvailable": MessageLookupByLibrary.simpleMessage("Available"),
    "serviceBlocked": MessageLookupByLibrary.simpleMessage("Blocked"),
    "serviceCheckAll": MessageLookupByLibrary.simpleMessage("Check all"),
    "serviceComingSoon": MessageLookupByLibrary.simpleMessage("Coming soon"),
    "serviceDisallowedIsp": MessageLookupByLibrary.simpleMessage(
      "Disallowed ISP",
    ),
    "serviceFailed": MessageLookupByLibrary.simpleMessage("Check failed"),
    "serviceManage": MessageLookupByLibrary.simpleMessage("Manage services"),
    "serviceOriginalsOnly": MessageLookupByLibrary.simpleMessage(
      "Originals only",
    ),
    "servicePending": MessageLookupByLibrary.simpleMessage("Not checked"),
    "serviceRestricted": MessageLookupByLibrary.simpleMessage(
      "Access restricted",
    ),
    "serviceShownOnDashboard": MessageLookupByLibrary.simpleMessage(
      "Shown on the dashboard",
    ),
    "serviceStatus": MessageLookupByLibrary.simpleMessage("Service status"),
    "serviceUnavailable": MessageLookupByLibrary.simpleMessage("Unavailable"),
    "serviceUnsupportedRegion": MessageLookupByLibrary.simpleMessage(
      "Region not supported",
    ),
    "settingEntries": MessageLookupByLibrary.simpleMessage("settings"),
    "settings": MessageLookupByLibrary.simpleMessage("Settings"),
    "settingsCount": m87,
    "shareLinkFallback": MessageLookupByLibrary.simpleMessage(
      "Share links are not supported for this node type yet; node details copied instead",
    ),
    "shareLinkUnreadable": m88,
    "shareLinksInvalid": MessageLookupByLibrary.simpleMessage(
      "No proxy could be read from the links",
    ),
    "shareQrcodeTip": MessageLookupByLibrary.simpleMessage(
      "Scan with BiLoom on another device to import this profile.",
    ),
    "show": MessageLookupByLibrary.simpleMessage("Show"),
    "showLess": MessageLookupByLibrary.simpleMessage("Collapse"),
    "showMore": MessageLookupByLibrary.simpleMessage("Expand"),
    "showNotificationStopAction": MessageLookupByLibrary.simpleMessage(
      "Stop button in notification",
    ),
    "showNotificationStopActionDesc": MessageLookupByLibrary.simpleMessage(
      "Show a stop button on the persistent notification. Turn it off if your system keeps the notification expanded because of it",
    ),
    "showPassword": MessageLookupByLibrary.simpleMessage("Show password"),
    "shrink": MessageLookupByLibrary.simpleMessage("Compact"),
    "sidebar": MessageLookupByLibrary.simpleMessage("Sidebar"),
    "sidebarBlurDesc": MessageLookupByLibrary.simpleMessage(
      "Background blur lets the desktop behind the window show through the sidebar.",
    ),
    "silentLaunch": MessageLookupByLibrary.simpleMessage("Silent launch"),
    "silentLaunchDesc": MessageLookupByLibrary.simpleMessage(
      "Silent launch starts without showing the window.",
    ),
    "singleAdd": MessageLookupByLibrary.simpleMessage("Single add"),
    "singleImport": MessageLookupByLibrary.simpleMessage("Single import"),
    "singleShareLinkOnly": MessageLookupByLibrary.simpleMessage(
      "Enter one link here; edit several from the quick edit of the list",
    ),
    "singleValueTip": m89,
    "size": MessageLookupByLibrary.simpleMessage("Size"),
    "skipCertVerify": MessageLookupByLibrary.simpleMessage(
      "Skip certificate verification",
    ),
    "skipDomain": MessageLookupByLibrary.simpleMessage("Skip domains"),
    "skipDomainDesc": MessageLookupByLibrary.simpleMessage(
      "A sniffed domain on the Skip domains list is not used.",
    ),
    "skipDstAddress": MessageLookupByLibrary.simpleMessage(
      "Skip destination addresses",
    ),
    "skipSrcAddress": MessageLookupByLibrary.simpleMessage(
      "Skip source addresses",
    ),
    "skippedDuplicateNodes": MessageLookupByLibrary.simpleMessage(
      "Skipped — these names already exist in this profile",
    ),
    "slide": MessageLookupByLibrary.simpleMessage("Slide"),
    "sliders": MessageLookupByLibrary.simpleMessage("Sliders"),
    "smartAntidetection": MessageLookupByLibrary.simpleMessage(
      "Smart anti-detection",
    ),
    "smartAntidetectionDesc": MessageLookupByLibrary.simpleMessage(
      "Automatically fills in TLS fingerprints and other anti-detection parameters, and retries with a different fingerprint when a node fails to connect. No manual setup.",
    ),
    "sniffProtocols": MessageLookupByLibrary.simpleMessage("Protocols"),
    "sniffer": MessageLookupByLibrary.simpleMessage("Sniffer"),
    "snifferStatusDesc": MessageLookupByLibrary.simpleMessage(
      "The sniffer reads the domain from TLS, HTTP and QUIC traffic so rules can match it.",
    ),
    "socksPort": MessageLookupByLibrary.simpleMessage("SOCKS port"),
    "softStyle": MessageLookupByLibrary.simpleMessage("Soft"),
    "sort": MessageLookupByLibrary.simpleMessage("Sort"),
    "source": MessageLookupByLibrary.simpleMessage("Source"),
    "sourceIp": MessageLookupByLibrary.simpleMessage("Source IP"),
    "specialProxy": MessageLookupByLibrary.simpleMessage("Special proxy"),
    "specialRules": MessageLookupByLibrary.simpleMessage("Special rules"),
    "spectrum": MessageLookupByLibrary.simpleMessage("Spectrum"),
    "speedStatistics": MessageLookupByLibrary.simpleMessage("Speed statistics"),
    "splitStrategy": MessageLookupByLibrary.simpleMessage("Split strategy"),
    "splitStrategyNotEmpty": MessageLookupByLibrary.simpleMessage(
      "Split strategy cannot be empty",
    ),
    "ssidsEmpty": MessageLookupByLibrary.simpleMessage("SSIDs are empty"),
    "stackMode": MessageLookupByLibrary.simpleMessage("Stack mode"),
    "stackTrace": MessageLookupByLibrary.simpleMessage("Stack trace"),
    "standard": MessageLookupByLibrary.simpleMessage("Standard"),
    "standardModeDesc": MessageLookupByLibrary.simpleMessage(
      "Standard mode: adds rules on top of the profile",
    ),
    "start": MessageLookupByLibrary.simpleMessage("Start"),
    "startFromScratch": MessageLookupByLibrary.simpleMessage(
      "Start from scratch",
    ),
    "startVpn": MessageLookupByLibrary.simpleMessage("Starting VPN…"),
    "startupAndBackground": MessageLookupByLibrary.simpleMessage(
      "Startup and background",
    ),
    "status": MessageLookupByLibrary.simpleMessage("Status"),
    "statusDesc": MessageLookupByLibrary.simpleMessage(
      "With DNS off, the system DNS is used.",
    ),
    "stop": MessageLookupByLibrary.simpleMessage("Stop"),
    "stopVpn": MessageLookupByLibrary.simpleMessage("Stopping VPN…"),
    "strategy": MessageLookupByLibrary.simpleMessage("Strategy"),
    "strictRoute": MessageLookupByLibrary.simpleMessage("Strict route"),
    "strictRouteDesc": MessageLookupByLibrary.simpleMessage(
      "Strict route keeps traffic such as DNS from bypassing TUN, and with IPv6 off it blocks this device\'s IPv6 connections.",
    ),
    "style": MessageLookupByLibrary.simpleMessage("Style"),
    "subRule": MessageLookupByLibrary.simpleMessage("Sub-rule"),
    "subRuleEmpty": MessageLookupByLibrary.simpleMessage("Sub-rule is empty"),
    "subRuleNotEmpty": MessageLookupByLibrary.simpleMessage(
      "Sub-rule cannot be empty",
    ),
    "submit": MessageLookupByLibrary.simpleMessage("Submit"),
    "subscribeOverwriteWarning": MessageLookupByLibrary.simpleMessage(
      "This profile comes from a subscription link; updating it will overwrite the nodes you add",
    ),
    "subscriptionInfo": MessageLookupByLibrary.simpleMessage(
      "Subscription info",
    ),
    "sudoPasswordTitle": MessageLookupByLibrary.simpleMessage(
      "Enter your password for sudo",
    ),
    "suspended": MessageLookupByLibrary.simpleMessage("Suspended…"),
    "switchProfile": MessageLookupByLibrary.simpleMessage("Switch profile"),
    "switchToTun": MessageLookupByLibrary.simpleMessage("Switch to TUN"),
    "switchToTunDesc": MessageLookupByLibrary.simpleMessage(
      "The virtual network adapter takes over all traffic, so even the system\'s own DNS queries are intercepted",
    ),
    "sync": MessageLookupByLibrary.simpleMessage("Sync"),
    "system": MessageLookupByLibrary.simpleMessage("System"),
    "systemApp": MessageLookupByLibrary.simpleMessage("System apps"),
    "systemProxy": MessageLookupByLibrary.simpleMessage("System proxy"),
    "systemProxyDesc": MessageLookupByLibrary.simpleMessage(
      "Set the system proxy",
    ),
    "tab": MessageLookupByLibrary.simpleMessage("Tab"),
    "tabAnimation": MessageLookupByLibrary.simpleMessage("Tab animation"),
    "tabAnimationDesc": MessageLookupByLibrary.simpleMessage(
      "Only effective in mobile view",
    ),
    "tapIconToRetry": MessageLookupByLibrary.simpleMessage(
      "Tap the icon to retry",
    ),
    "tapToAuthorize": MessageLookupByLibrary.simpleMessage("Tap to authorize"),
    "target": MessageLookupByLibrary.simpleMessage("Target"),
    "tcpConcurrent": MessageLookupByLibrary.simpleMessage("TCP concurrent"),
    "tcpConcurrentDesc": MessageLookupByLibrary.simpleMessage(
      "Allow concurrent TCP connections",
    ),
    "testInterval": MessageLookupByLibrary.simpleMessage("Test interval"),
    "testUrl": MessageLookupByLibrary.simpleMessage("Test URL"),
    "testWhenUsed": MessageLookupByLibrary.simpleMessage("Test when used"),
    "textScale": MessageLookupByLibrary.simpleMessage("Text scaling"),
    "textScalePreview": MessageLookupByLibrary.simpleMessage(
      "Text in the app will look like this",
    ),
    "theme": MessageLookupByLibrary.simpleMessage("Theme"),
    "themeColor": MessageLookupByLibrary.simpleMessage("Theme color"),
    "themeDesc": MessageLookupByLibrary.simpleMessage(
      "Set dark mode and adjust colors",
    ),
    "themeMode": MessageLookupByLibrary.simpleMessage("Theme mode"),
    "tight": MessageLookupByLibrary.simpleMessage("Tight"),
    "time": MessageLookupByLibrary.simpleMessage("Time"),
    "timeout": MessageLookupByLibrary.simpleMessage("Timeout"),
    "tintedStyle": MessageLookupByLibrary.simpleMessage("Tinted"),
    "tip": MessageLookupByLibrary.simpleMessage("Tip"),
    "toggle": MessageLookupByLibrary.simpleMessage("Toggle"),
    "toggleLabel": MessageLookupByLibrary.simpleMessage("Toggle labels"),
    "tolerance": MessageLookupByLibrary.simpleMessage("Tolerance"),
    "tonalSpotScheme": MessageLookupByLibrary.simpleMessage("Tonal spot"),
    "tools": MessageLookupByLibrary.simpleMessage("Tools"),
    "torch": MessageLookupByLibrary.simpleMessage("Flashlight"),
    "total": MessageLookupByLibrary.simpleMessage("Total"),
    "totalDownload": MessageLookupByLibrary.simpleMessage("Downloaded"),
    "totalTraffic": MessageLookupByLibrary.simpleMessage("Total traffic"),
    "totalUpload": MessageLookupByLibrary.simpleMessage("Uploaded"),
    "tproxyPort": MessageLookupByLibrary.simpleMessage("TProxy port"),
    "traffic": MessageLookupByLibrary.simpleMessage("Traffic"),
    "trafficPeak": m90,
    "trafficTotal": m91,
    "trafficUsage": MessageLookupByLibrary.simpleMessage("Traffic usage"),
    "transport": MessageLookupByLibrary.simpleMessage("Transport"),
    "transportHeaders": m92,
    "tun": MessageLookupByLibrary.simpleMessage("TUN"),
    "tunAuthorizationFailed": MessageLookupByLibrary.simpleMessage(
      "TUN could not be authorized, so it was turned off.",
    ),
    "tunDesc": MessageLookupByLibrary.simpleMessage(
      "TUN works only in administrator mode.",
    ),
    "tunOverrideDesc": MessageLookupByLibrary.simpleMessage(
      "Entries added here replace the TUN settings of every profile; anything not added keeps the profile\'s own setting. Entries a custom profile adds itself take precedence.",
    ),
    "turnOff": MessageLookupByLibrary.simpleMessage("Turn off"),
    "turnOn": MessageLookupByLibrary.simpleMessage("Turn on"),
    "udpRelayMode": MessageLookupByLibrary.simpleMessage("UDP relay mode"),
    "udpTimeout": MessageLookupByLibrary.simpleMessage("UDP timeout"),
    "udpTimeoutDesc": MessageLookupByLibrary.simpleMessage(
      "The UDP timeout is in seconds and works only with the gvisor, system and mixed stacks.",
    ),
    "ultra": MessageLookupByLibrary.simpleMessage("Ultra"),
    "undo": MessageLookupByLibrary.simpleMessage("Undo"),
    "unfavoriteNode": MessageLookupByLibrary.simpleMessage("Unfavorite node"),
    "unifiedDelay": MessageLookupByLibrary.simpleMessage("Unified delay"),
    "unifiedDelayDesc": MessageLookupByLibrary.simpleMessage(
      "Remove extra delays such as handshakes",
    ),
    "unknown": MessageLookupByLibrary.simpleMessage("Unknown"),
    "unknownNetworkError": MessageLookupByLibrary.simpleMessage(
      "Unknown network error",
    ),
    "unmaximize": MessageLookupByLibrary.simpleMessage("Restore down"),
    "unnamed": MessageLookupByLibrary.simpleMessage("Unnamed"),
    "unpinWindow": MessageLookupByLibrary.simpleMessage("Unpin window"),
    "update": MessageLookupByLibrary.simpleMessage("Update"),
    "updateFailedTip": MessageLookupByLibrary.simpleMessage(
      "Last update failed",
    ),
    "updateSubscription": MessageLookupByLibrary.simpleMessage(
      "Update subscription",
    ),
    "upload": MessageLookupByLibrary.simpleMessage("Upload"),
    "uploadBandwidth": MessageLookupByLibrary.simpleMessage("Upload bandwidth"),
    "url": MessageLookupByLibrary.simpleMessage("URL"),
    "urlDesc": MessageLookupByLibrary.simpleMessage(
      "Obtain a profile from a URL",
    ),
    "urlTip": m93,
    "useHosts": MessageLookupByLibrary.simpleMessage("Use hosts"),
    "useSystemHosts": MessageLookupByLibrary.simpleMessage("Use system hosts"),
    "usedShort": MessageLookupByLibrary.simpleMessage("used"),
    "usedTraffic": MessageLookupByLibrary.simpleMessage("Used traffic"),
    "userAgent": MessageLookupByLibrary.simpleMessage("User-Agent"),
    "username": MessageLookupByLibrary.simpleMessage("Username"),
    "value": MessageLookupByLibrary.simpleMessage("Value"),
    "vibrantScheme": MessageLookupByLibrary.simpleMessage("Vibrant"),
    "view": MessageLookupByLibrary.simpleMessage("View"),
    "virtualIpv4": MessageLookupByLibrary.simpleMessage("Virtual IPv4"),
    "vividStyle": MessageLookupByLibrary.simpleMessage("Vivid"),
    "vpnConfigChangeDetected": MessageLookupByLibrary.simpleMessage(
      "VPN-related configuration change detected",
    ),
    "vpnEnableDesc": MessageLookupByLibrary.simpleMessage(
      "VPN routes all system traffic through VpnService automatically.",
    ),
    "vpnTip": MessageLookupByLibrary.simpleMessage(
      "Changes take effect after restarting the VPN",
    ),
    "webDAVConfiguration": MessageLookupByLibrary.simpleMessage(
      "WebDAV configuration",
    ),
    "whitelistMode": MessageLookupByLibrary.simpleMessage("Whitelist mode"),
    "writeToSystem": MessageLookupByLibrary.simpleMessage("Write to system"),
    "writeToSystemDesc": MessageLookupByLibrary.simpleMessage(
      "Write to system also sets the system clock; Android ignores it.",
    ),
    "yearsAgo": m94,
    "yearsAgoShort": m95,
    "yes": MessageLookupByLibrary.simpleMessage("Yes"),
    "zhCN": MessageLookupByLibrary.simpleMessage("Simplified Chinese"),
  };
}
