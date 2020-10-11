/*
 * Copyright 2020 Board of Trustees of the University of Illinois.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:illinois/utils/AppDateTime.dart';
import 'package:illinois/service/Auth.dart';
import 'package:illinois/service/Localization.dart';
import 'package:illinois/utils/Crypt.dart';
import 'package:illinois/utils/Utils.dart';
import 'package:illinois/service/Styles.dart';
import 'package:intl/intl.dart';
import "package:pointycastle/export.dart";


////////////////////////////////
// Covid19Status

class Covid19Status {
  final String id;
  final String userId;
  final DateTime dateUtc;
  final String encryptedKey;
  final String encryptedBlob;
  Covid19StatusBlob blob;

  Covid19Status({this.id, this.userId, this.dateUtc, this.encryptedKey, this.encryptedBlob, this.blob});

  factory Covid19Status.fromJson(Map<String, dynamic> json) {
    return (json != null) ? Covid19Status(
      id: json['id'],
      userId: json['user_id'],
      dateUtc: healthDateTimeFromString(json['date']),
      encryptedKey: json['encrypted_key'],
      encryptedBlob: json['encrypted_blob'],
        ) : null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'date': healthDateTimeToString(dateUtc),
      'encrypted_key': encryptedKey,
      'encrypted_blob': encryptedBlob,
    };
  }

  static Future<Covid19Status> decryptedFromJson(Map<String, dynamic> json, PrivateKey privateKey) async {
    try {
      Covid19Status value = Covid19Status.fromJson(json);
      if ((value != null) && (value.encryptedKey != null) && (value.encryptedBlob != null) && (privateKey != null)) {
        String blobString = await compute(_decryptBlob, {
          'encryptedKey': value.encryptedKey,
          'encryptedBlob': value.encryptedBlob,
          'privateKey': privateKey
        });
        value.blob = Covid19StatusBlob.fromJson(AppJson.decodeMap(blobString));
      }
      return value;
    }
    catch(e) { print(e?.toString()); }
    return null;
  }

  Future<Covid19Status> encrypted(PublicKey publicKey) async {
    Map<String, dynamic> encrypted = await compute(_encryptBlob, {
      'blob': AppJson.encode(blob?.toJson()),
      'publicKey': publicKey
    });
    return Covid19Status(
      id: id,
      userId: userId,
      dateUtc: dateUtc,
      encryptedKey: encrypted['encryptedKey'],
      encryptedBlob: encrypted['encryptedBlob'],
    );
  }
}

///////////////////////////////
// Covid19StatusBlob

class Covid19StatusBlob {

  final String healthStatus;
  final int priority;

  final String nextStep;
  final String nextStepHtml;
  final DateTime nextStepDateUtc;

  final String eventExplanation;
  final String eventExplanationHtml;

  final String reason;
  final String warning;

  final Covid19HistoryBlob historyBlob;

  static const String _nextStepDateMacro = '{next_step_date}';
  static const String _nextStepDateFormat = 'EEEE, MMM d';

  Covid19StatusBlob({this.healthStatus, this.priority, this.nextStep, this.nextStepHtml, this.nextStepDateUtc, this.eventExplanation, this.eventExplanationHtml, this.reason, this.warning, this.historyBlob});

  factory Covid19StatusBlob.fromJson(Map<String, dynamic> json) {
    return (json != null) ? Covid19StatusBlob(
      healthStatus: json['health_status'],
      priority: json['priority'],
      nextStep: json['next_step'],
      nextStepHtml: json['next_step_html'],
      nextStepDateUtc: healthDateTimeFromString(json['next_step_date']),
      eventExplanation: json['event_explanation'],
      eventExplanationHtml: json['event_explanation_html'],
      reason: json['reason'],
      warning: json['warning'],
      historyBlob: Covid19HistoryBlob.fromJson(json['history_blob']),
    ) : null;
  }

  Map<String, dynamic> toJson() {
    return {
      'health_status': healthStatus,
      'priority': priority,
      'next_step': nextStep,
      'next_step_html': nextStepHtml,
      'next_step_date': healthDateTimeToString(nextStepDateUtc),
      'event_explanation': eventExplanation,
      'event_explanation_html': eventExplanationHtml,
      'reason': reason,
      'warning': warning,
      'history_blob': historyBlob?.toJson(),
    };
  }

  String get displayNextStep {
    return _processMacros(nextStep);
  }

  String get displayNextStepHtml {
    return _processMacros(nextStepHtml);
  }

  String displayNextStepDate({String format = _nextStepDateFormat}) {
    if (nextStepDateUtc != null) {
      DateTime nextStepMidnightLocal = AppDateTime.midnight(nextStepDateUtc);
      if (nextStepMidnightLocal == AppDateTime.todayMidnightLocal) {
        return Localization().getStringEx('model.explore.time.today', 'Today').toLowerCase();
      }
      else if (nextStepMidnightLocal == AppDateTime.tomorrowMidnightLocal) {
        return Localization().getStringEx('model.explore.time.tomorrow', 'Tomorrow').toLowerCase();
      }
      else {
        return AppDateTime.formatDateTime(nextStepDateUtc.toLocal(), format: format);
      }
    }
    return null;
  }

  String get displayEventExplanation {
    return _processMacros(eventExplanation);
  }

  String get displayEventExplanationHtml {
    return _processMacros(eventExplanationHtml);
  }

  String get displayReason {
    return _processMacros(reason);
  }

  String get displayWarning {
    return _processMacros(warning);
  }

  String _processMacros(String value) {
    if ((value != null) && (nextStepDateUtc != null) && value.contains(_nextStepDateMacro)) {
      return value.replaceAll(_nextStepDateMacro, displayNextStepDate() ?? '');
    }
    return value;
  }

  bool get requiresTest {
    // TBD
    return (nextStep?.toLowerCase()?.contains("test") ?? false) ||
      (nextStepHtml?.toLowerCase()?.contains("test") ?? false);  
  }

  String get localizedHealthStatus {
    return localizedHealthStatusFromKey(healthStatus);
  }

  String get localizedHealthStatusType {
    return localizedHealthStatusTypeFromKey(healthStatus);
  }

  String get localizedHealthStatusDescription {
    return localizedHealthStatusDescriptionFromKey(healthStatus);
  }

  static String localizedHealthStatusFromKey(String key) {
    return _localizedHealthStatusFromKey("com.illinois.covid19.status.long.${key.toLowerCase()}", AppString.capitalize(key));
  }

  static String localizedHealthStatusTypeFromKey(String key) {
    return _localizedHealthStatusFromKey("com.illinois.covid19.status.type.${key.toLowerCase()}", AppString.capitalize(key));
  }

  static String localizedHealthStatusDescriptionFromKey(String key) {
    return _localizedHealthStatusFromKey("com.illinois.covid19.status.description.${key.toLowerCase()}", AppString.capitalize(key));
  }

  static String _localizedHealthStatusFromKey(String key, String defaultValue) {
    if(key != null){
      return Localization().getStringEx(key, defaultValue);
    }
    return defaultValue;
  }
}

///////////////////////////////
// Covid19HealthStatus

const String kCovid19HealthStatusRed       = 'red';
const String kCovid19HealthStatusOrange    = 'orange';
const String kCovid19HealthStatusYellow    = 'yellow';
const String kCovid19HealthStatusGreen     = 'green';
const String kCovid19HealthStatusUnchanged = 'no change';

Color covid19HealthStatusColor(String status) {
  switch (status) {
    case kCovid19HealthStatusRed:    return Styles().colors.healthStatusRed;
    case kCovid19HealthStatusOrange: return Styles().colors.healthStatusOrange;
    case kCovid19HealthStatusYellow: return Styles().colors.healthStatusYellow;
    case kCovid19HealthStatusGreen:  return Styles().colors.healthStatusGreen;
    default:                         return null;
  }
}

bool covid19HealthStatusIsValid(String status) {
  return (status != null) && (status != kCovid19HealthStatusUnchanged);
}

int covid19HealthStatusWeight(String status) {
  switch (status) {
    case kCovid19HealthStatusRed:    return 4;
    case kCovid19HealthStatusOrange: return 3;
    case kCovid19HealthStatusYellow: return 2;
    case kCovid19HealthStatusGreen:  return 1;
    default:                         return 0;
  }
}

////////////////////////////////
// Covid19Access

const String kCovid19AccessGranted   = 'granted';
const String kCovid19AccessDenied    = 'denied';


///////////////////////////////
// Covid19History

class Covid19History {
  final String id;
  final String userId;
  final DateTime dateUtc;
  final Covid19HistoryType type;

  final String encryptedKey;
  final String encryptedBlob;
  
  final String locationId;
  final String countyId;
  final String encryptedImageKey;
  final String encryptedImageBlob;

  Covid19HistoryBlob blob;

  Covid19History({this.id, this.userId, this.dateUtc, this.type, this.encryptedKey, this.encryptedBlob, this.locationId, this.countyId, this.encryptedImageKey, this.encryptedImageBlob });

  factory Covid19History.fromJson(Map<String, dynamic> json) {
    return (json != null) ? Covid19History(
      id: json['id'],
      userId: json['user_id'],
      dateUtc: healthDateTimeFromString(json['date']),
      type: covid19HistoryTypeFromString(json['type']),

      encryptedKey: json['encrypted_key'],
      encryptedBlob: json['encrypted_blob'],

      locationId: json['location_id'],
      countyId: json['county_id'],
      encryptedImageKey: json['encrypted_image_key'],
      encryptedImageBlob: json['encrypted_image_blob'],
    ) : null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'date': healthDateTimeToString(dateUtc),
      'type': covid19HistoryTypeToString(type),

      'encrypted_key': encryptedKey,
      'encrypted_blob': encryptedBlob,

      'location_id': locationId,
      'county_id': countyId,
      'encrypted_image_key': encryptedImageKey,
      'encrypted_image_blob': encryptedImageBlob,
    };
  }

  static Future<Covid19History> decryptedFromJson(Map<String, dynamic> json, Map<Covid19HistoryType, PrivateKey> privateKeys ) async {
    try {
      Covid19History value = Covid19History.fromJson(json);
      PrivateKey privateKey = privateKeys[value.type];
      if ((value != null) && (value.encryptedKey != null) && (value.encryptedBlob != null) && (privateKey != null)) {
        String blobString = await compute(_decryptBlob, {
          'encryptedKey': value.encryptedKey,
          'encryptedBlob': value.encryptedBlob,
          'privateKey': privateKey
        });
        value.blob = Covid19HistoryBlob.fromJson(AppJson.decodeMap(blobString));
      }
      return value;
    }
    catch(e) { print(e?.toString()); }
    return null;
  }

  static Future<Covid19History> encryptedFromBlob({String id, String userId, DateTime dateUtc, Covid19HistoryType type, Covid19HistoryBlob blob, String locationId, String countyId, String image, PublicKey publicKey}) async {
    Map<String, dynamic> encrypted = await compute(_encryptBlob, {
      'blob': AppJson.encode(blob?.toJson()),
      'publicKey': publicKey
    });
    Map<String, dynamic> encryptedImage = (image != null) ? await compute(_encryptBlob, {
      'blob': image,
      'publicKey': publicKey
    }) : null;
    return Covid19History(
      id: id,
      userId: userId,
      dateUtc: dateUtc,
      type: type,
      encryptedKey: encrypted['encryptedKey'],
      encryptedBlob: encrypted['encryptedBlob'],
      locationId: locationId,
      countyId: countyId,
      encryptedImageKey: (encryptedImage != null) ? encryptedImage['encryptedKey'] : null,
      encryptedImageBlob: (encryptedImage != null) ? encryptedImage['encryptedBlob'] : null,
    );
  }

  bool get isTest {
    return (type == Covid19HistoryType.test) || (type == Covid19HistoryType.manualTestNotVerified) || (type == Covid19HistoryType.manualTestVerified);
  }

  bool get isManualTest {
    return (type == Covid19HistoryType.manualTestNotVerified) || (type == Covid19HistoryType.manualTestVerified);
  }

  bool get isTestVerified {
    return (type == Covid19HistoryType.test) || (type == Covid19HistoryType.manualTestVerified);
  }

  bool get canTestUpdateStatus {
    return (type == Covid19HistoryType.test) || (type == Covid19HistoryType.manualTestVerified);
  }

  bool get isSymptoms {
    return (type == Covid19HistoryType.symptoms);
  }

  bool get isContactTrace {
    return (type == Covid19HistoryType.contactTrace);
  }

  bool get isAction {
    return (type == Covid19HistoryType.action);
  }

  DateTime get dateMidnightLocal {
    if (dateUtc != null) {
      DateTime dateLocal = dateUtc.toLocal();
      return DateTime(dateLocal.year, dateLocal.month, dateLocal.day);
    }
    else {
      return null;
    }
  }

  bool matchEvent(Covid19Event event) {
    if (event.isTest) {
      return this.isTest &&
        (this.dateUtc == event?.blob?.dateUtc) &&
        (this.blob?.provider == event?.provider) &&
        (this.blob?.providerId == event?.providerId) &&
        (this.blob?.testType == event?.blob?.testType) &&
        (this.blob?.testResult == event?.blob?.testResult);
    }
    else if (event.isAction) {
      return this.isAction &&
        (this.dateUtc == event?.blob?.dateUtc) &&
        (this.blob?.actionType == event?.blob?.actionType) &&
        (this.blob?.actionText == event?.blob?.actionText);
    }
    else {
      return false;
    }
  }

  static Future<List<Covid19History>> listFromJson(List<dynamic> json, Map<Covid19HistoryType, PrivateKey> privateKeys) async {
    List<Covid19History> values;
    if (json != null) {
      values = [];
      for (dynamic entry in json) {
          Covid19History value = await Covid19History.decryptedFromJson((entry as Map)?.cast<String, dynamic>(), privateKeys);
          values.add(value);
      }
    }
    return values;
  }

  /*static List<dynamic> listToJson(List<Covid19History> values) {
    List<dynamic> json;
    if (values != null) {
      json = [];
      for (Covid19History value in values) {
        json.add(value?.toJson());
      }
    }
    return json;
  }*/

  static Covid19History traceInList(List<Covid19History> values, { String tek }) {
    if ((values != null) && (tek != null)) {
      for (Covid19History history in values) {
        if ((history.type == Covid19HistoryType.contactTrace) && (history.blob?.traceTEK == tek)) {
          return history;
        }
      }
    }
    return null;
  }

  static bool listContainsEvent(List<Covid19History> histories, Covid19Event event) {
    if ((histories != null) && (event != null)) {
      for (Covid19History history in histories) {
         if (history.matchEvent(event)) {
           return true;
         }
      }
    }
    return false;
  }

  static Covid19History mostRecent(List<Covid19History> histories) {
    if (histories != null) {
      DateTime nowUtc = DateTime.now().toUtc();
      for (int index = 0; index < histories.length; index++) {
        Covid19History history = histories[index];
        if ((history.dateUtc != null) && (history.dateUtc.isBefore(nowUtc))) {
          return history;
        }
      }
    }
    return null;
  }

  static Covid19History mostRecentTest(List<Covid19History> histories) {
    if (histories != null) {
      DateTime nowUtc = DateTime.now().toUtc();
      for (int index = 0; index < histories.length; index++) {
        Covid19History history = histories[index];
        if (history.isTestVerified && (history.dateUtc != null) && (history.dateUtc.isBefore(nowUtc))) {
          return history;
        }
      }
    }
    return null;
  }

  static List<Covid19History> pastList(List<Covid19History> histories) {
    List<Covid19History> result;
    if (histories != null) {
      result = List<Covid19History>();
      DateTime nowUtc = DateTime.now().toUtc();
      for (int index = 0; index < histories.length; index++) {
        Covid19History history =  histories[index];
        if ((history.dateUtc != null) && (history.dateUtc.isBefore(nowUtc))) {
          result.add(history);
        }
      }
    }
    return result;
  }

  static Covid19History mostRecentContactTrace(List<Covid19History> histories, { DateTime minDateUtc, DateTime maxDateUtc }) {
    if (histories != null) {
      for (int index = 0; index < histories.length; index++) {
        Covid19History history = histories[index];
        if (history.isContactTrace &&
            ((minDateUtc == null) || ((history.dateUtc != null) && history.dateUtc.isAfter(minDateUtc))) &&
            ((maxDateUtc == null) || ((history.dateUtc != null) && history.dateUtc.isBefore(maxDateUtc)))) {
          return history;
        }
      }
    }
    return null;
  }
}

////////////////////////////////
// Covid19HistoryBlob

class Covid19HistoryBlob {
  final String provider;
  final String providerId;
  final String location;
  final String locationId;
  final String countyId;
  final String testType;
  final String testResult;
  
  final List<HealthSymptom> symptoms;
  
  final int traceDuration;
  final String traceTEK;
  
  final String actionType;
  final String actionText;

  Covid19HistoryBlob({
    this.provider, this.providerId, this.location, this.locationId, this.countyId, this.testType, this.testResult,
    this.symptoms,
    this.traceDuration, this.traceTEK,
    this.actionType, this.actionText,
  });

  factory Covid19HistoryBlob.fromJson(Map<String, dynamic> json) {
    return (json != null) ? Covid19HistoryBlob(
      provider: json['provider'],
      providerId: json['provider_id'],
      location: json['location'],
      locationId: json['location_id'],
      countyId: json['county_id'],
      testType: json['test_type'],
      testResult: json['result'],
      
      symptoms: HealthSymptom.listFromJson(json['symptoms']),
      
      traceDuration: json['trace_duration'],
      traceTEK: json['trace_tek'],
      
      actionType: json['action_type'],
      actionText: json['action_text'],
    ) : null;
  }

  Map<String, dynamic> toJson() {
    return {
      'provider': provider,
      'provider_id': providerId,
      'location': location,
      'location_id': locationId,
      'county_id': countyId,
      'test_type': testType,
      'result': testResult,
      
      'symptoms': HealthSymptom.listToJson(symptoms),
      
      'trace_duration': traceDuration,
      'trace_tek': traceTEK,
      
      'action_type': actionType,
      'action_text': actionText,
    };
  }

  bool get isTest {
    return (providerId != null) || (locationId != null) || (testType != null) || (testResult != null);
  }

  bool get isSymptoms {
    return (symptoms != null);
  }

  bool get isContactTrace {
    return ((traceDuration != null) /*&& (traceTEK != null)*/);
  }

  bool get isAction {
    return (actionType != null);
  }

  Set<String> get symptomsIds {
    Set<String> symptomsIds;
    if (symptoms != null) {
      symptomsIds = Set<String>();
      for (HealthSymptom symptom in symptoms) {
        symptomsIds.add(symptom.id);
      }
    }
    return symptomsIds;
  }

  String get symptomsDisplayString {
    String result = "";
    if (symptoms != null) {
      for (HealthSymptom symptom in symptoms) {
        if (0 < result.length) {
          result += ", ";
        }
        result += symptom.name;
      }
    }
    return result;
  }

  int get traceDurationInMinutes {
    return (traceDuration != null) ? (traceDuration / 60000).round() : null;
  }

  String get traceDurationDisplayString {
    int durationInSeconds = (traceDuration != null) ? traceDuration ~/ 1000 : null;
    if (durationInSeconds != null) {
      if (durationInSeconds < 60) {
        return "$durationInSeconds second" + (1 != durationInSeconds ? "s" : "");
      }
      else {
        int durationInMinutes = durationInSeconds ~/ 60;
        if (durationInMinutes < TimeOfDay.minutesPerHour) {
          return "$durationInMinutes minute" + (1 != durationInMinutes ? "s" : "");
        } else {
          int exposureHours = durationInMinutes ~/ TimeOfDay.minutesPerHour;
          return "$exposureHours hour" + (1 != exposureHours ? "s" : "");
        }

      }
    }
    return null;
  }

  String get actionDisplayString {
    return actionText ?? actionType;
  }
}

////////////////////////////////
// Covid19HistoryType

enum Covid19HistoryType { test, manualTestVerified, manualTestNotVerified, symptoms, contactTrace, action }

Covid19HistoryType covid19HistoryTypeFromString(String value) {
  if (value == 'received_test') {
    return Covid19HistoryType.test;
  }
  else if (value == 'verified_manual_test') {
    return Covid19HistoryType.manualTestVerified;
  }
  else if (value == 'unverified_manual_test') {
    return Covid19HistoryType.manualTestNotVerified;
  }
  else if (value == 'symptoms') {
    return Covid19HistoryType.symptoms;
  }
  else if (value == 'trace') {
    return Covid19HistoryType.contactTrace;
  }
  else if (value == 'action') {
    return Covid19HistoryType.action;
  }
  else {
    return null;
  }
}

String covid19HistoryTypeToString(Covid19HistoryType value) {
  switch (value) {
    case Covid19HistoryType.test: return 'received_test';
    case Covid19HistoryType.manualTestVerified: return 'verified_manual_test';
    case Covid19HistoryType.manualTestNotVerified: return 'unverified_manual_test';
    case Covid19HistoryType.symptoms: return 'symptoms';
    case Covid19HistoryType.contactTrace: return 'trace';
    case Covid19HistoryType.action: return 'action';
  }
  return null;
}

///////////////////////////////
// Covid19Event

class Covid19Event {
  final String   id;
  final String   provider;
  final String   providerId;
  final String   userId;
  final String   encryptedKey;
  final String   encryptedBlob;
  final bool     processed;
  final DateTime dateCreated;
  final DateTime dateUpdated;

  Covid19EventBlob blob;

  Covid19Event({this.id, this.provider, this.providerId, this.userId, this.encryptedKey, this.encryptedBlob, this.processed, this.dateCreated, this.dateUpdated});

  factory Covid19Event.fromJson(Map<String, dynamic> json) {
    return (json != null) ? Covid19Event(
      id:            AppJson.stringValue(json['id']),
      provider:      AppJson.stringValue(json['provider']),
      providerId:    AppJson.stringValue(json['provider_id']),
      userId:        AppJson.stringValue(json['user_id']),
      encryptedKey:  AppJson.stringValue(json['encrypted_key']),
      encryptedBlob: AppJson.stringValue(json['encrypted_blob']),
      processed:     AppJson.boolValue(json['processed']),
      dateCreated:   healthDateTimeFromString(AppJson.stringValue(json['date_created'])),
      dateUpdated:   healthDateTimeFromString(AppJson.stringValue(json['date_updated'])),
    ) : null;
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['id']              = id;
    json['provider']        = provider;
    json['provider_id']     = providerId;
    json['user_id']         = userId;
    json['encrypted_key']   = encryptedKey;
    json['encrypted_blob']  = encryptedBlob;
    json['processed']       = processed;
    json['date_created']    = healthDateTimeToString(dateCreated);
    json['date_updated']    = healthDateTimeToString(dateUpdated);
    return json;
  }

  static Future<Covid19Event> decryptedFromJson(Map<String, dynamic> json, PrivateKey privateKey) async {
    try {
      Covid19Event value = Covid19Event.fromJson(json);
      if ((value != null) && (value.encryptedKey != null) && (value.encryptedBlob != null) && (privateKey != null)) {
        String blobString = await compute(_decryptBlob, {
          'encryptedKey': value.encryptedKey,
          'encryptedBlob': value.encryptedBlob,
          'privateKey': privateKey
        });
        value.blob = Covid19EventBlob.fromJson(AppJson.decodeMap(blobString));
      }
      return value;
    }
    catch(e) { print(e?.toString()); }
    return null;
  }

  static Future<List<Covid19Event>> listFromJson(List<dynamic> json, PrivateKey privateKey) async {
    List<Covid19Event> values;
    if (json != null) {
      values = [];
      for (dynamic entry in json) {
          Covid19Event value = await Covid19Event.decryptedFromJson(entry, privateKey);
          values.add(value);
      }
    }
    return values;
  }

  bool get isTest {
    return (blob != null) && blob.isTest && (providerId != null);
  }

  bool get isAction {
    return (blob != null) && blob.isAction;
  }
}

///////////////////////////////
// Covid19EventBlob

class Covid19EventBlob {
  final DateTime dateUtc;

  final String   testType;
  final String   testResult;

  final String   actionType;
  final String   actionText;

  Covid19EventBlob({this.dateUtc, this.testType, this.testResult, this.actionType, this.actionText});

  factory Covid19EventBlob.fromJson(Map<String, dynamic> json) {
    return (json != null) ? Covid19EventBlob(
      dateUtc:       healthDateTimeFromString(AppJson.stringValue(json['Date'])),
      testType:      AppJson.stringValue(json['TestName']),
      testResult:    AppJson.stringValue(json['Result']),
      actionType:    AppJson.stringValue(json['ActionType']),
      actionText:    AppJson.stringValue(json['ActionText']),
    ) : null;
  }

  Map<String, dynamic> toJson() {
    if ((testType != null) || (testResult != null)) {
      return {
        'Date': healthDateTimeToString(dateUtc),
        'TestName': testType,
        'Result': testResult,
      };
    }
    else if ((actionType != null) || (actionText != null)) {
      return {
        'Date': healthDateTimeToString(dateUtc),
        'ActionType': actionType,
        'ActionText': actionText,
      };
    }
    else {
      return {
        'Date': healthDateTimeToString(dateUtc),
      };
    }
  }

  bool get isTest {
    return AppString.isStringNotEmpty(testType) && AppString.isStringNotEmpty(testResult);
  }

  bool get isAction {
    return AppString.isStringNotEmpty(actionType);
  }
}


///////////////////////////////
// Covid19OSFTest

class Covid19OSFTest {
  final String provider;
  final String providerId;
  final String testType;
  final String testResult;
  final DateTime dateUtc;

  Covid19OSFTest({this.provider, this.providerId,  this.testType, this.testResult, this.dateUtc,});
}


///////////////////////////////
// Covid19ManualTest

class Covid19ManualTest {
  final String provider;
  final String providerId;
  final String location;
  final String locationId;
  final String countyId;
  final String testType;
  final String testResult;
  final DateTime dateUtc;
  final String image;

  Covid19ManualTest({this.provider, this.providerId, this.location, this.locationId, this.countyId, this.testType, this.testResult, this.dateUtc, this.image});
}

///////////////////////////////
// HealthUser

class HealthUser {
  String uuid;
  String publicKeyString;
  PublicKey _publicKey;
  bool consent;
  bool exposureNotification;
  bool repost;
  String encryptedKey;
  String encryptedBlob;

  HealthUser({this.uuid, this.publicKeyString, PublicKey publicKey, this.consent, this.exposureNotification, this.repost, this.encryptedKey, this.encryptedBlob}) {
    _publicKey = publicKey;
  }

  factory HealthUser.fromJson(Map<String, dynamic> json) {
    return (json != null) ? HealthUser(
      uuid: json['uuid'],
      publicKeyString: json['public_key'],
      consent: json['consent'],
      exposureNotification: json['exposure_notification'],
      repost: json['re_post'],
      encryptedKey: json['encrypted_key'],
      encryptedBlob: json['encrypted_blob'],
    ) : null;
  }

  Map<String, dynamic> toJson() {
    return {
      'uuid': uuid,
      'public_key': publicKeyString,
      'consent': consent,
      'exposure_notification': exposureNotification,
      're_post': repost,
      'encrypted_key': encryptedKey,
      'encrypted_blob': encryptedBlob,
    };
  }

  Future<void> encryptBlob(HealthUserBlob blob, PublicKey publicKey) async {
    Map<String, dynamic> encrypted = await compute(_encryptBlob, {
      'blob': AppJson.encode(blob?.toJson()),
      'publicKey': publicKey
    });
    encryptedKey = encrypted['encryptedKey'];
    encryptedBlob = encrypted['encryptedBlob'];
  }


  factory HealthUser.fromUser(HealthUser user) {
    return (user != null) ? HealthUser(
      uuid: user.uuid,
      publicKeyString: user.publicKeyString,
      publicKey: user.publicKey,
      consent: user.consent,
      exposureNotification: user.exposureNotification,
      repost: user.repost,
      encryptedKey: user.encryptedKey,
      encryptedBlob: user.encryptedBlob,
    ) : null;
  }

  PublicKey get publicKey {
    if ((_publicKey == null) && (publicKeyString != null)) {
      _publicKey = RsaKeyHelper.parsePublicKeyFromPem(publicKeyString);
    }
    return _publicKey;
  }

  set publicKey(PublicKey value) {
    _publicKey = value;
    publicKeyString = (value != null) ? RsaKeyHelper.encodePublicKeyToPemPKCS1(value) : null;
  }

  bool operator ==(o) =>
      o is HealthUser &&
          o.uuid == uuid &&
          o.publicKeyString == publicKeyString &&
          o.consent == consent &&
          o.exposureNotification == exposureNotification &&
          o.repost == repost &&
          o.encryptedKey == encryptedKey &&
          o.encryptedBlob == encryptedBlob;

  int get hashCode =>
      (uuid?.hashCode ?? 0) ^
      (publicKeyString?.hashCode ?? 0) ^
      (consent?.hashCode ?? 0) ^
      (exposureNotification?.hashCode ?? 0) ^
      (repost?.hashCode ?? 0) ^
      (encryptedKey?.hashCode ?? 0) ^
      (encryptedBlob?.hashCode ?? 0);
}

///////////////////////////////
// HealthUserBlob

class HealthUserBlob {
  String info;

  HealthUserBlob({this.info});

  factory HealthUserBlob.fromJson(Map<String, dynamic> json) {
    return (json != null) ? HealthUserBlob(
      info: json['info'],
    ) : null;
  }

  Map<String, dynamic> toJson() {
    return {
      'info': info
    };
  }
}

///////////////////////////////
// HealthOSFAuth

class HealthOSFAuth{
  final String accessToken;
  final String tokenType;
  final int expiresIn;
  final String scope;
  final String patient;

  HealthOSFAuth({this.accessToken, this.tokenType, this.expiresIn, this.scope, this.patient});

  factory HealthOSFAuth.fromJson(Map<String,dynamic>json){
    return HealthOSFAuth(
      accessToken: json["access_token"],
      tokenType: json["token_type"],
      expiresIn: json["expires_in"],
      scope: json["scope"],
      patient: json["patient"],
    );
  }

  toJson(){
    return {
      "access_token": accessToken,
      "token_type": tokenType,
      "expires_in": expiresIn,
      "scope": scope,
      "patient": patient,
    };
  }
}

///////////////////////////////
// HealthServiceProvider

class HealthServiceProvider {
  String id;
  String name;
  bool allowManualTest;
  List<HealthServiceMechanism> availableMechanisms;

  HealthServiceProvider({this.id, this.name, this.allowManualTest, this.availableMechanisms});

  factory HealthServiceProvider.fromJson(Map<String, dynamic> json) {
    return (json != null) ? HealthServiceProvider(
      id: json['id'],
      name: json['provider_name'],
      allowManualTest: json['manual_test'],
      availableMechanisms: healthServiceMechanismListFromJson(json["available_mechanisms"]),
    ) : null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'provider_name': name,
      'manual_test': allowManualTest,
      "available_mechanisms" : healthServiceMechanismListToJson(availableMechanisms)
    };
  }

  static List<HealthServiceProvider> listFromJson(List<dynamic> json) {
    List<HealthServiceProvider> values;
    if (json != null) {
      values = [];
      for (dynamic entry in json) {
          HealthServiceProvider value;
          try { value = HealthServiceProvider.fromJson((entry as Map)?.cast<String, dynamic>()); }
          catch(e) { print(e?.toString()); }
          values.add(value);
      }
    }
    return values;
  }

  static List<dynamic> listToJson(List<HealthServiceProvider> values) {
    List<dynamic> json;
    if (values != null) {
      json = [];
      for (HealthServiceProvider value in values) {
        json.add(value?.toJson());
      }
    }
    return json;
  }
}

////////////////////////////////
//HealthServiceMechanism

enum HealthServiceMechanism{epic, mcKinley, none}

HealthServiceMechanism healthServiceMechanismFromString(String value) {
  if (value != null) {
    if (value == 'Epic') {
      return HealthServiceMechanism.epic;
    }
    else if (value == 'McKinley') {
      return HealthServiceMechanism.mcKinley;
    }
    else if (value == 'McKinley') {
      return HealthServiceMechanism.mcKinley;
    }
  }
  return null;
}

String healthServiceMechanismToString(HealthServiceMechanism value) {
  if (value != null) {
    if (value == HealthServiceMechanism.epic) {
      return 'Epic';
    }
    else if (value == HealthServiceMechanism.mcKinley) {
      return 'McKinley';
    }
    else if (value == HealthServiceMechanism.mcKinley) {
      return 'McKinley';
    }
  }
  return null;
}

List<HealthServiceMechanism> healthServiceMechanismListFromJson(List<dynamic> json) {
  List<HealthServiceMechanism> values;
  if (json != null) {
    values = [];
    for (dynamic entry in json) {
      HealthServiceMechanism value;
      try { value = healthServiceMechanismFromString((entry as String)); }
      catch(e) { print(e?.toString()); }
      values.add(value);
    }
  }
  return values;
}

List<dynamic>  healthServiceMechanismListToJson(List<HealthServiceMechanism> values) {
  List<dynamic> json;
  if (values != null) {
    json = [];
    for (HealthServiceMechanism value in values) {
      json.add(healthServiceMechanismToString(value));
    }
  }
  return json;
}



///////////////////////////////
// HealthServiceLocation

class HealthServiceLocation {
  String id;
  String name;
  String contact;
  String city;
  String address1;
  String address2;
  String state;
  String country;
  String zip;
  String url;
  String notes;
  double latitude;
  double longitude;
  HealthLocationWaitTimeColor waitTimeColor;
  List<String> availableTests;
  List<HealthLocationDayOfOperation> daysOfOperation;
  HealthServiceLocation({this.id, this.name, this.availableTests, this.contact, this.city, this.address1, this.address2, this.state, this.country, this.zip, this.url, this.notes, this.latitude, this.longitude, this.waitTimeColor, this.daysOfOperation});

  factory HealthServiceLocation.fromJson(Map<String, dynamic> json) {
    List jsoTests = json['available_tests'];
    List jsonDaysOfOperation = json['days_of_operation'];
    return (json != null) ? HealthServiceLocation(
      id: json['id'],
      name: json['name'],
      contact: json["contact"],
      city: json["city"],
      state: json["state"],
      country: json["country"],
      address1: json["address_1"],
      address2: json["address_2"],
      zip: json["zip"],
      url: json["url"],
      notes: json["notes"],
      latitude: AppJson.doubleValue(json["latitude"]),
      longitude: AppJson.doubleValue(json["longitude"]),
      waitTimeColor: HealthServiceLocation.waitTimeColorFromString(json['wait_time_color']),
      availableTests: jsoTests!=null ? List.from(jsoTests) : null,
      daysOfOperation: jsonDaysOfOperation!=null ? HealthLocationDayOfOperation.listFromJson(jsonDaysOfOperation) : null,
    ) : null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'contact': contact,
      'city': city,
      'state': state,
      'country': country,
      'address_1': address1,
      'address_2': address2,
      'zip': zip,
      'url': url,
      'notes': notes,
      'latitude': latitude,
      'longitude': longitude,
      'wait_time_color': HealthServiceLocation.waitTimeColorToKeyString(waitTimeColor),
      'available_tests': availableTests,
    };
  }

  String get fullAddress{
    String address = "";
    address = address1?? "";
    if(address2?.isNotEmpty?? false) {
      address += address.isNotEmpty ? ", " : "";
      address += address2;
    }
    if(city?.isNotEmpty?? false) {
      address += address.isNotEmpty ? ", " : "";
      address += city;
    }
    if(state?.isNotEmpty?? false) {
      address += address.isNotEmpty ? ", " : "";
      address += state;
    }
    return address;
  }

  static List<HealthServiceLocation> listFromJson(List<dynamic> json) {
    List<HealthServiceLocation> values;
    if (json != null) {
      values = [];
      for (dynamic entry in json) {
        HealthServiceLocation value;
        try { value = HealthServiceLocation.fromJson((entry as Map)?.cast<String, dynamic>()); }
        catch(e) { print(e?.toString()); }
        values.add(value);
      }
    }
    return values;
  }

  static List<dynamic> listToJson(List<HealthServiceLocation> values) {
    List<dynamic> json;
    if (values != null) {
      json = [];
      for (HealthServiceLocation value in values) {
        json.add(value?.toJson());
      }
    }
    return json;
  }

  static HealthLocationWaitTimeColor waitTimeColorFromString(String colorString) {
    if (colorString == 'red') {
      return HealthLocationWaitTimeColor.red;
    } else if (colorString == 'yellow') {
      return HealthLocationWaitTimeColor.yellow;
    } else if (colorString == 'green') {
      return HealthLocationWaitTimeColor.green;
    } else if (colorString == 'grey') {
      return HealthLocationWaitTimeColor.grey;
    } else {
      return null;
    }
  }

  static String waitTimeColorToKeyString(HealthLocationWaitTimeColor color) {
    switch (color) {
      case HealthLocationWaitTimeColor.red:
        return 'red';
      case HealthLocationWaitTimeColor.yellow:
        return 'yellow';
      case HealthLocationWaitTimeColor.green:
        return 'green';
      case HealthLocationWaitTimeColor.grey:
        return 'grey';
      default:
        return null;
    }
  }

  static Color waitTimeColorHex(HealthLocationWaitTimeColor color) {
    switch (color) {
      case HealthLocationWaitTimeColor.red:
        return Styles().colors.healthLocationWaitTimeColorRed;
      case HealthLocationWaitTimeColor.yellow:
        return Styles().colors.healthLocationWaitTimeColorYellow;
      case HealthLocationWaitTimeColor.green:
        return Styles().colors.healthLocationWaitTimeColorGreen;
      default:
        return Styles().colors.healthLocationWaitTimeColorGrey;
    }
  }
}

///////////////////////////////
// HealthLocationDayOfOperation

class HealthLocationDayOfOperation {
  final String name;
  final String openTime;
  final String closeTime;

  final int weekDay;
  final int openMinutes;
  final int closeMinutes;

  HealthLocationDayOfOperation({this.name, this.openTime, this.closeTime}) :
    weekDay = (name != null) ? AppDateTime.getWeekDayFromString(name.toLowerCase()) : null,
    openMinutes = _timeMinutes(openTime),
    closeMinutes = _timeMinutes(closeTime);

  factory HealthLocationDayOfOperation.fromJson(Map<String,dynamic> json){
    return (json != null) ? HealthLocationDayOfOperation(
      name: json["name"],
      openTime: json["open_time"],
      closeTime: json["close_time"],
    ) : null;
  }

  String get displayString{
    return "$name $openTime to $closeTime";
  }

  bool get isOpen {
    if ((openMinutes != null) && (closeMinutes != null)) {
      int nowWeekDay = DateTime.now().weekday;
      int nowMinutes = _timeOfDayMinutes(TimeOfDay.now());
      return nowWeekDay == weekDay && openMinutes < nowMinutes && nowMinutes < closeMinutes;
    }
    return false;
  }

  bool get willOpen {
    if (openMinutes != null) {
      int nowWeekDay = DateTime.now().weekday;
      int nowMinutes = _timeOfDayMinutes(TimeOfDay.now());
      return nowWeekDay == weekDay && nowMinutes < openMinutes;
    }

    return false;
  }

  static List<HealthLocationDayOfOperation> listFromJson(List<dynamic> json) {
    List<HealthLocationDayOfOperation> values;
    if (json != null) {
      values = [];
      for (dynamic entry in json) {
        HealthLocationDayOfOperation value;
        try { value = HealthLocationDayOfOperation.fromJson((entry as Map)?.cast<String, dynamic>()); }
        catch(e) { print(e?.toString()); }
        values.add(value);
      }
    }
    return values;
  }

  // Helper function for conversion work time string to number of minutes

  static int _timeMinutes(String time, {String format = 'hh:mma'}) {
    DateTime dateTime = (time != null) ? AppDateTime.parseDateTime(time.toUpperCase(), format: format) : null;
    TimeOfDay timeOfDay = (dateTime != null) ? TimeOfDay.fromDateTime(dateTime) : null;
    return _timeOfDayMinutes(timeOfDay);
  }

  static int _timeOfDayMinutes(TimeOfDay timeOfDay) {
    return (timeOfDay != null) ? (timeOfDay.hour * 60 + timeOfDay.minute) : null;
  }
}

///////////////////////////////
// HealthLocationWaitTimeColor

enum HealthLocationWaitTimeColor { red, yellow, green, grey }

///////////////////////////////
// HealthTestType

class HealthTestType {
  String id;
  String name;
  List<HealthTestTypeResult> results;

  HealthTestType({this.id, this.name, this.results});

  factory HealthTestType.fromJson(Map<String, dynamic> json) {
    return (json != null) ? HealthTestType(
      id: json['id'],
      name: json['name'],
      results: HealthTestTypeResult.listFromJson(json['results']),
    ) : null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'results': HealthTestTypeResult.listToJson(results),
    };
  }

  static List<HealthTestType> listFromJson(List<dynamic> json) {
    List<HealthTestType> values;
    if (json != null) {
      values = [];
      for (dynamic entry in json) {
        HealthTestType value;
        try { value = HealthTestType.fromJson((entry as Map)?.cast<String, dynamic>()); }
        catch(e) { print(e?.toString()); }
        values.add(value);
      }
    }
    return values;
  }

  static List<dynamic> listToJson(List<HealthTestType> values) {
    List<dynamic> json;
    if (values != null) {
      json = [];
      for (HealthTestType value in values) {
        json.add(value?.toJson());
      }
    }
    return json;
  }
}

///////////////////////////////
// HealthTestRuleResult

class HealthTestTypeResult {
  String id;
  String name;
  String nextStep;
  int nextStepOffset;
  int nextStepExpiresOffset;

  HealthTestTypeResult({this.id, this.name, this.nextStep, this.nextStepOffset,this.nextStepExpiresOffset});

  factory HealthTestTypeResult.fromJson(Map<String, dynamic> json) {
    return (json != null) ? HealthTestTypeResult(
        id: json['id'],
        name: json['name'],
        nextStep: json['next_step'],
        nextStepOffset: json['next_step_offset'],
        nextStepExpiresOffset: json['result_expires_offset']
    ) : null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'next_step': nextStep,
      'next_step_offset': nextStepOffset,
      'result_expires_offset': nextStepExpiresOffset,
    };
  }

  DateTime nextStepDate(DateTime testDate) {
    return ((testDate != null) && (nextStepOffset != null)) ?
    testDate.add(Duration(hours: nextStepOffset)) : null;
  }

  static List<HealthTestTypeResult> listFromJson(List<dynamic> json) {
    List<HealthTestTypeResult> values;
    if (json != null) {
      values = [];
      for (dynamic entry in json) {
        HealthTestTypeResult value;
        try { value = HealthTestTypeResult.fromJson((entry as Map)?.cast<String, dynamic>()); }
        catch(e) { print(e?.toString()); }
        values.add(value);
      }
    }
    return values;
  }

  static List<dynamic> listToJson(List<HealthTestTypeResult> values) {
    List<dynamic> json;
    if (values != null) {
      json = [];
      for (HealthTestTypeResult value in values) {
        json.add(value?.toJson());
      }
    }
    return json;
  }
}

///////////////////////////////
// HealthCounty

class HealthCounty {
  String id;
  String name;
  String nameDisplayText;
  String state;
  String country;
  List<HealthGuideline> guidelines;

  HealthCounty({this.id, this.name, this.nameDisplayText, this.state, this.country,this.guidelines});

  factory HealthCounty.fromJson(Map<String, dynamic> json) {
    String name = json['name'];
    String state = json['state_province'];
    String nameDisplayText = AppString.isStringNotEmpty(state) ? "$name, $state" : name;
    return (json != null) ? HealthCounty(
      id: json['id'],
      name: name,
      nameDisplayText: nameDisplayText,
      state: state,
      country: json['country'],
      guidelines: HealthGuideline.fromJsonList(json['guidelines']),
    ) : null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'state': state,
      'country': country,
      'guidelines': HealthGuideline.listToJson(guidelines),
    };
  }

  static HealthCounty defaultCounty(Iterable<HealthCounty> counties) {
    if ((counties != null) && (0 < counties.length)) {
      for (HealthCounty county in counties) {
        if (county.name == 'Champaign') {
          return county;
        }
      }
      return counties.first;
    }
    return null;
  }

  static LinkedHashMap<String, HealthCounty> listToMap(List<HealthCounty> counties) {
    LinkedHashMap<String, HealthCounty> countiesMap;
    if (counties != null) {
      countiesMap = LinkedHashMap<String, HealthCounty>();
      for (HealthCounty county in counties) {
        countiesMap[county.id] = county;
      }
    }
    return countiesMap;
  }

  static List<HealthCounty> listFromJson(List<dynamic> json) {
    List<HealthCounty> values;
    if (json != null) {
      values = [];
      for (dynamic entry in json) {
          HealthCounty value;
          try { value = HealthCounty.fromJson((entry as Map)?.cast<String, dynamic>()); }
          catch(e) { print(e?.toString()); }
          values.add(value);
      }
    }
    return values;
  }

  static List<dynamic> listToJson(List<HealthCounty> values) {
    List<dynamic> json;
    if (values != null) {
      json = [];
      for (HealthCounty value in values) {
        json.add(value?.toJson());
      }
    }
    return json;
  }
}


///////////////////////////////
// HealthGuideline

class HealthGuideline {
  String id;
  String name;
  List<HealthGuidelineItem> items;

  HealthGuideline({this.id,this.name,this.items});

  factory HealthGuideline.fromJson(Map<String, dynamic> json) {
    if (json == null) {
      return null;
    }
    return HealthGuideline(
        id: json['id'],
        name: json['name'],
        items: HealthGuidelineItem.fromJsonList(json["items"])
    );
  }

  static List<HealthGuideline> fromJsonList(List<dynamic> jsonList) {
    List<HealthGuideline> sections;
    if (jsonList != null) {
      sections = List();
      for (dynamic jsonEntry in jsonList) {
        sections.add(HealthGuideline.fromJson(jsonEntry));
      }
    }
    return sections;
  }

  static List<dynamic> listToJson(List<HealthGuideline> values) {
    List<dynamic> json;
    if (values != null) {
      json = [];
      for (HealthGuideline value in values) {
        json.add(value?.toJson());
      }
    }
    return json;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': HealthGuidelineItem.listToJson(items),
    };
  }
}

///////////////////////////////
// HealthGuidelineItem

class HealthGuidelineItem {
  String icon;
  String description;
  String type;

  HealthGuidelineItem({this.icon,this.description,this.type});

  factory HealthGuidelineItem.fromJson(Map<String, dynamic> json) {
    if (json == null) {
      return null;
    }
    return HealthGuidelineItem(
      icon: json['icon'],
      description: json['description'],
      type: json['type'],
    );
  }

  static List<HealthGuidelineItem> fromJsonList(List<dynamic> jsonList) {
    List<HealthGuidelineItem> guidelineItems;
    if (jsonList != null) {
      guidelineItems = List();
      for (dynamic jsonEntry in jsonList) {
        guidelineItems.add(HealthGuidelineItem.fromJson(jsonEntry));
      }
    }
    return guidelineItems;
  }

  static List<dynamic> listToJson(List<HealthGuidelineItem> values) {
    List<dynamic> json;
    if (values != null) {
      json = [];
      for (HealthGuidelineItem value in values) {
        json.add(value?.toJson());
      }
    }
    return json;
  }

  Map<String, dynamic> toJson() {
    return {
      'icon': icon,
      'description': description,
      'type': type,
    };
  }
}

///////////////////////////////
// HealthSymptom

class HealthSymptom {
  final String id;
  final String name;

  HealthSymptom({this.id, this.name});

  factory HealthSymptom.fromJson(Map<String, dynamic> json) {
    return (json != null) ? HealthSymptom(
      id: json['id'],
      name: json['name'],
    ) : null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
    };
  }

  static List<HealthSymptom> listFromJson(List<dynamic> json) {
    List<HealthSymptom> values;
    if (json != null) {
      values = [];
      for (dynamic entry in json) {
          HealthSymptom value;
          try { value = HealthSymptom.fromJson((entry as Map)?.cast<String, dynamic>()); }
          catch(e) { print(e?.toString()); }
          values.add(value);
      }
    }
    return values;
  }

  static List<dynamic> listToJson(List<HealthSymptom> values) {
    List<dynamic> json;
    if (values != null) {
      json = [];
      for (HealthSymptom value in values) {
        json.add(value?.toJson());
      }
    }
    return json;
  }
}

///////////////////////////////
// HealthSymptomsGroup

class HealthSymptomsGroup {
  final String id;
  final String name;
  final String group;
  final bool visible;
  final List<HealthSymptom> symptoms;

  HealthSymptomsGroup({this.id, this.name, this.group, this.visible, this.symptoms});

  factory HealthSymptomsGroup.fromJson(Map<String, dynamic> json) {
    return (json != null) ? HealthSymptomsGroup(
      id: json['id'],
      name: json['name'],
      visible: json['visible'],
      group: json['group'],
      symptoms: HealthSymptom.listFromJson(json['symptoms']),
    ) : null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'group': group,
      'visible': visible,
      'symptoms': HealthSymptom.listToJson(symptoms),
    };
  }

  static Map<String, int> getCounts(List<HealthSymptomsGroup> groups, Set<String> selected) {
    Map<String, int> counts = Map<String, int>();
    if ((groups != null) && (selected != null)) {
      for (HealthSymptomsGroup group in groups) {
        int count = 0;
        if (group.symptoms != null) {
          for (HealthSymptom symptom in group.symptoms) {
            if (selected.contains(symptom.id)) {
              count++;
            }
          }
        }
        counts[group.name] = count;
      }
    }
    return counts;
  }

  static List<HealthSymptom> getSymptoms(List<HealthSymptomsGroup> groups, Set<String> selected) {
    List<HealthSymptom> symptoms = List<HealthSymptom>();
    if ((groups != null) && (selected != null)) {
      for (HealthSymptomsGroup group in groups) {
        if ((group.symptoms != null)) {
          for (HealthSymptom symptom in group.symptoms) {
            if (selected.contains(symptom.id)) {
              symptoms.add(symptom);
            }
          }
        }
      }
    }
    return symptoms;
  }

  static List<HealthSymptomsGroup> listFromJson(List<dynamic> json) {
    List<HealthSymptomsGroup> values;
    if (json != null) {
      values = [];
      for (dynamic entry in json) {
          HealthSymptomsGroup value;
          try { value = HealthSymptomsGroup.fromJson((entry as Map)?.cast<String, dynamic>()); }
          catch(e) { print(e?.toString()); }
          values.add(value);
      }
    }
    return values;
  }

  static List<dynamic> listToJson(List<HealthSymptomsGroup> values) {
    List<dynamic> json;
    if (values != null) {
      json = [];
      for (HealthSymptomsGroup value in values) {
        json.add(value?.toJson());
      }
    }
    return json;
  }
}

///////////////////////////////
// HealthRulesSet

class HealthRulesSet {
  final HealthTestRulesSet tests;
  final HealthSymptomsRulesSet symptoms;
  final HealthContactTraceRulesSet contactTrace;
  final HealthActionRulesSet actions;
  final HealthDefaultsSet defaults;
  final Map<String, _HealthRuleStatus> statuses;
  final Map<String, dynamic> constants;

  static const String UserTestMonitorInterval = 'UserTestMonitorInterval';

  HealthRulesSet({this.tests, this.symptoms, this.contactTrace, this.actions, this.defaults, this.statuses, Map<String, dynamic> constants}) :
    this.constants = constants ?? Map<String, dynamic>();

  factory HealthRulesSet.fromJson(Map<String, dynamic> json) {
    return (json != null) ? HealthRulesSet(
      tests: HealthTestRulesSet.fromJson(json['tests']),
      symptoms: HealthSymptomsRulesSet.fromJson(json['symptoms']),
      contactTrace: HealthContactTraceRulesSet.fromJson(json['contact_trace']),
      actions: HealthActionRulesSet.fromJson(json['actions']),
      defaults: HealthDefaultsSet.fromJson(json['defaults']),
      statuses: _HealthRuleStatus.mapFromJson(json['statuses']),
      constants: json['constants'],
    ) : null;
  }

  int get userTestMonitorInterval {
    return constants[UserTestMonitorInterval];
  }

  set userTestMonitorInterval(int value) {
    constants[UserTestMonitorInterval] = value;
  }
}

///////////////////////////////
// HealthDefaultsSet

class HealthDefaultsSet {
  final _HealthRuleStatus status;

  HealthDefaultsSet({this.status});

  factory HealthDefaultsSet.fromJson(Map<String, dynamic> json) {
    return (json != null) ? HealthDefaultsSet(
      status: _HealthRuleStatus.fromJson(json['status']),
    ) : null;
  }
}


///////////////////////////////
// HealthTestRulesSet

class HealthTestRulesSet {
  final List<HealthTestRule> _rules;

  HealthTestRulesSet({List<HealthTestRule> rules}) : _rules = rules;

  factory HealthTestRulesSet.fromJson(Map<String, dynamic> json) {
    return (json != null) ? HealthTestRulesSet(
      rules: HealthTestRule.listFromJson(json['rules'])
    ) : null;
  }

  HealthTestRuleResult matchRuleResult({ Covid19HistoryBlob blob, HealthRulesSet rules }) {
    if ((_rules != null) && (blob != null)) {
      for (HealthTestRule rule in _rules) {
        if ((rule?.testType != null) && (rule?.testType?.toLowerCase() == blob?.testType?.toLowerCase()) && (rule.results != null)) {
          for (HealthTestRuleResult ruleResult in rule.results) {
            if ((ruleResult?.testResult != null) && (ruleResult.testResult.toLowerCase() == blob?.testResult?.toLowerCase())) {
              return ruleResult;
            }
          }
        }
      }
    }
    return null;
  }
}


///////////////////////////////
// HealthTestRule

class HealthTestRule {
  final String testType;
  final String category;
  final List<HealthTestRuleResult> results;

  HealthTestRule({this.testType, this.category, this.results});

  factory HealthTestRule.fromJson(Map<String, dynamic> json) {
    return (json != null) ? HealthTestRule(
      testType: json['test_type'],
      category: json['category'],
      results: HealthTestRuleResult.listFromJson(json['results']),
    ) : null;
  }

  static List<HealthTestRule> listFromJson(List<dynamic> json) {
    List<HealthTestRule> values;
    if (json != null) {
      values = [];
      for (dynamic entry in json) {
          try { values.add(HealthTestRule.fromJson((entry as Map)?.cast<String, dynamic>())); }
          catch(e) { print(e?.toString()); }
      }
    }
    return values;
  }
}

///////////////////////////////
// HealthTestRuleResult

class HealthTestRuleResult {
  final String testResult;
  final String category;
  final _HealthRuleStatus status;

  HealthTestRuleResult({this.testResult, this.category, this.status});

  factory HealthTestRuleResult.fromJson(Map<String, dynamic> json) {
    return (json != null) ? HealthTestRuleResult(
      testResult: json['result'],
      category: json['category'],
      status: _HealthRuleStatus.fromJson(json['status']),
    ) : null;
  }

  static List<HealthTestRuleResult> listFromJson(List<dynamic> json) {
    List<HealthTestRuleResult> values;
    if (json != null) {
      values = [];
      for (dynamic entry in json) {
          try { values.add(HealthTestRuleResult.fromJson((entry as Map)?.cast<String, dynamic>())); }
          catch(e) { print(e?.toString()); }
      }
    }
    return values;
  }

  static HealthTestRuleResult matchRuleResult(List<HealthTestRuleResult> results, { Covid19HistoryBlob blob }) {
    if (results != null) {
      for (HealthTestRuleResult result in results) {
        if (result._matchBlob(blob)) {
          return result;
        }
      }
    }
    return null;
  }

  bool _matchBlob(Covid19HistoryBlob blob) {
    return ((testResult != null) && (testResult.toLowerCase() == blob?.testResult?.toLowerCase()));
  }
}

///////////////////////////////
// HealthSymptomsRulesSet

class HealthSymptomsRulesSet {
  final List<HealthSymptomsRule> _rules;
  final List<HealthSymptomsGroup> groups;

  HealthSymptomsRulesSet({List<HealthSymptomsRule> rules, this.groups}) : _rules = rules;

  factory HealthSymptomsRulesSet.fromJson(Map<String, dynamic> json) {
    return (json != null) ? HealthSymptomsRulesSet(
      rules: HealthSymptomsRule.listFromJson(json['rules']),
      groups: HealthSymptomsGroup.listFromJson(json['groups']),
    ) : null;
  }

  HealthSymptomsRule matchRule({ Covid19HistoryBlob blob, HealthRulesSet rules }) {
    if ((_rules != null) && (groups != null) && (blob?.symptomsIds != null)) {
     Map<String, int> counts = HealthSymptomsGroup.getCounts(groups, blob.symptomsIds);
      for (HealthSymptomsRule rule in _rules) {
        if (rule._matchCounts(counts, rules: rules)) {
          return rule;
        }
      }
    }
    return null;
  }
}

///////////////////////////////
// HealthSymptomsRule

class HealthSymptomsRule {
  final Map<String, _HealthRuleIntInterval> counts;
  final _HealthRuleStatus status;
  
  HealthSymptomsRule({this.counts, this.status});

  factory HealthSymptomsRule.fromJson(Map<String, dynamic> json) {
    return (json != null) ? HealthSymptomsRule(
      counts: _countsFromJson(json['counts']),
      status: _HealthRuleStatus.fromJson(json['status']),
    ) : null;
  }

  static List<HealthSymptomsRule> listFromJson(List<dynamic> json) {
    List<HealthSymptomsRule> values;
    if (json != null) {
      values = [];
      for (dynamic entry in json) {
          try { values.add(HealthSymptomsRule.fromJson((entry as Map)?.cast<String, dynamic>())); }
          catch(e) { print(e?.toString()); }
      }
    }
    return values;
  }

  static Map<String, _HealthRuleIntInterval> _countsFromJson(Map<String, dynamic> json) {
    Map<String, _HealthRuleIntInterval> values;
    if (json != null) {
      values = Map<String, _HealthRuleIntInterval>();
      json.forEach((key, value) {
        values[key] = _HealthRuleIntInterval.fromJson(value);
      });
    }
    return values;
  }

  bool _matchCounts(Map<String, int> testCounts, { HealthRulesSet rules }) {
    if (this.counts != null) {
      for (String groupName in this.counts.keys) {
        _HealthRuleIntInterval value = this.counts[groupName];
        int count = (testCounts != null) ? testCounts[groupName] : null;
        if (!value.match(count, rules: rules)) {
          return false;
        }

      }
    }
    return true;
  }
}

///////////////////////////////
// HealthContactTraceRulesSet

class HealthContactTraceRulesSet {
  final List<HealthContactTraceRule> _rules;

  HealthContactTraceRulesSet({List<HealthContactTraceRule> rules}) : _rules = rules;

  factory HealthContactTraceRulesSet.fromJson(Map<String, dynamic> json) {
    return (json != null) ? HealthContactTraceRulesSet(
      rules: HealthContactTraceRule.listFromJson(json['rules']),
    ) : null;
  }

  HealthContactTraceRule matchRule({ Covid19HistoryBlob blob, HealthRulesSet rules }) {
    if ((_rules != null) && (blob != null)) {
      for (HealthContactTraceRule rule in _rules) {
        if (rule._matchBlob(blob, rules: rules)) {
          return rule;
        }
      }
    }
    return null;
  }
}

///////////////////////////////
// HealthContactTraceRule

class HealthContactTraceRule {
  final _HealthRuleIntInterval duration;
  final _HealthRuleStatus status;

  HealthContactTraceRule({this.duration, this.status});

  factory HealthContactTraceRule.fromJson(Map<String, dynamic> json) {
    return (json != null) ? HealthContactTraceRule(
      duration: _HealthRuleIntInterval.fromJson(json['duration']),
      status: _HealthRuleStatus.fromJson(json['status']),
    ) : null;
  }

  static List<HealthContactTraceRule> listFromJson(List<dynamic> json) {
    List<HealthContactTraceRule> values;
    if (json != null) {
      values = [];
      for (dynamic entry in json) {
          try { values.add(HealthContactTraceRule.fromJson((entry as Map)?.cast<String, dynamic>())); }
          catch(e) { print(e?.toString()); }
      }
    }
    return values;
  }

  bool _matchBlob(Covid19HistoryBlob blob, { HealthRulesSet rules }) {
    return (duration != null) && duration.match(blob?.traceDurationInMinutes, rules: rules);
  }
}

///////////////////////////////
// HealthActionRulesSet

class HealthActionRulesSet {
  final List<HealthActionRule> _rules;

  HealthActionRulesSet({List<HealthActionRule> rules}) : _rules = rules;

  factory HealthActionRulesSet.fromJson(Map<String, dynamic> json) {
    return (json != null) ? HealthActionRulesSet(
      rules: HealthActionRule.listFromJson(json['rules']),
    ) : null;
  }

  HealthActionRule matchRule({ Covid19HistoryBlob blob, HealthRulesSet rules }) {
    if (_rules != null) {
      for (HealthActionRule rule in _rules) {
        if (rule._matchBlob(blob, rules: rules)) {
          return rule;
        }
      }
    }
    return null;
  }
}

///////////////////////////////
// HealthActionRule

class HealthActionRule {
  final String type;
  final _HealthRuleStatus status;

  HealthActionRule({this.type, this.status});

  factory HealthActionRule.fromJson(Map<String, dynamic> json) {
    return (json != null) ? HealthActionRule(
      type: json['type'],
      status: _HealthRuleStatus.fromJson(json['status']),
    ) : null;
  }

  static List<HealthActionRule> listFromJson(List<dynamic> json) {
    List<HealthActionRule> values;
    if (json != null) {
      values = [];
      for (dynamic entry in json) {
          try { values.add(HealthActionRule.fromJson((entry as Map)?.cast<String, dynamic>())); }
          catch(e) { print(e?.toString()); }
      }
    }
    return values;
  }

  bool _matchBlob(Covid19HistoryBlob blob, {HealthRulesSet rules}) {
    return (type != null) && (type.toLowerCase() == blob?.actionType?.toLowerCase());
  }
}

///////////////////////////////
// _HealthRuleStatus

abstract class _HealthRuleStatus {
  
  _HealthRuleStatus();
  
  factory _HealthRuleStatus.fromJson(dynamic json) {
    if (json is Map) {
      if (json['condition'] != null) {
        try { return HealthRuleConditionalStatus.fromJson(json.cast<String, dynamic>()); }
        catch (e) { print(e?.toString()); }
      }
      else {
        try { return HealthRuleStatus.fromJson(json.cast<String, dynamic>()); }
        catch (e) { print(e?.toString()); }
      }
    }
    else if (json is String) {
      return HealthRuleReferenceStatus.fromJson(json);
    }
    return null;
  }

  static Map<String, _HealthRuleStatus> mapFromJson(Map<String, dynamic> json) {
    Map<String, _HealthRuleStatus> result;
    if (json != null) {
      result = Map<String, _HealthRuleStatus>();
      json.forEach((String key, dynamic value) {
        try { result[key] =  _HealthRuleStatus.fromJson(value); }
        catch (e) { print(e?.toString()); }
      });
    }
    return result;
  }

  HealthRuleStatus eval({ List<Covid19History> history, int historyIndex, HealthRulesSet rules });
}

///////////////////////////////
// HealthRuleStatus

class HealthRuleStatus extends _HealthRuleStatus {

  final String healthStatus;
  final int priority;

  final String nextStep;
  final String nextStepHtml;
  final _HealthRuleIntInterval nextStepInterval;

  final String eventExplanation;
  final String eventExplanationHtml;

  final String reason;
  final String warning;

  HealthRuleStatus({this.healthStatus, this.priority, this.nextStep, this.nextStepHtml, this.nextStepInterval, this.eventExplanation, this.eventExplanationHtml, this.reason, this.warning });

  factory HealthRuleStatus.fromJson(Map<String, dynamic> json) {
    return (json != null) ? HealthRuleStatus(
      healthStatus: json['health_status'],
      priority: json['priority'],
      nextStep: json['next_step'],
      nextStepHtml: json['next_step_html'],
      nextStepInterval: _HealthRuleIntInterval.fromJson(json['next_step_interval']),
      eventExplanation: json['event_explanation'],
      eventExplanationHtml: json['event_explanation_html'],
      reason: json['reason'],
      warning: json['warning'],
    ) : null;
  }

  HealthRuleStatus eval({ List<Covid19History> history, int historyIndex, HealthRulesSet rules }) {
    return this;
  }

  bool canUpdateStatus({Covid19StatusBlob blob}) {
    int blobStatusWeight = covid19HealthStatusWeight(blob?.healthStatus);
    int newStatusWeight =  (this.healthStatus != null) ? covid19HealthStatusWeight(this.healthStatus) : blobStatusWeight;
    if (blobStatusWeight < newStatusWeight) {
      // status downgrade
      return true;
    }
    else {
      // status upgrade or preserve
      int blobStatusPriority = blob?.priority ?? 0;
      int newStatusPriority = this.priority ?? 0;
      return (newStatusPriority < 0) || (blobStatusPriority <= newStatusPriority);
    }
  }

  DateTime nextStepDateUtc(DateTime startDateUtc, { HealthRulesSet rules }) {
    int numberOfDays = nextStepInterval?.value(rules: rules);
    return ((startDateUtc != null) && (numberOfDays != null)) ?
       startDateUtc.add(Duration(days: numberOfDays)) : null;
  }
}

///////////////////////////////
// HealthRuleReferenceStatus

class HealthRuleReferenceStatus extends _HealthRuleStatus {
  final String reference;
  HealthRuleReferenceStatus({this.reference});

  factory HealthRuleReferenceStatus.fromJson(String json) {
    return (json != null) ? HealthRuleReferenceStatus(
      reference: json,
    ) : null;
  }

  HealthRuleStatus eval({ List<Covid19History> history, int historyIndex, HealthRulesSet rules }) {
    // Only test rules currently use reference status.
    _HealthRuleStatus status = (rules?.statuses != null) ? rules?.statuses[reference] : null;
    return status?.eval(history: history, historyIndex: historyIndex, rules: rules);
  }
}

///////////////////////////////
// HealthRuleConditionalStatus

class HealthRuleConditionalStatus extends _HealthRuleStatus {
  final String condition;
  final Map<String, dynamic> params;
  final _HealthRuleStatus successStatus;
  final _HealthRuleStatus failStatus;

  HealthRuleConditionalStatus({this.condition, this.params, this.successStatus, this.failStatus});

  factory HealthRuleConditionalStatus.fromJson(Map<String, dynamic> json) {
    return (json != null) ? HealthRuleConditionalStatus(
      condition: json['condition'],
      params: json['params'],
      successStatus: _HealthRuleStatus.fromJson(json['success']) ,
      failStatus: _HealthRuleStatus.fromJson(json['fail']),
    ) : null;
  }

  HealthRuleStatus eval({ List<Covid19History> history, int historyIndex, HealthRulesSet rules }) {
    _HealthRuleStatus result;
    if (condition == 'require-test') {
      result = _evalRequireTest(history: history, historyIndex: historyIndex, rules: rules);
    }
    else if (condition == 'require-symptoms') {
      result = _evalRequireSymptoms(history: history, historyIndex: historyIndex, rules: rules);
    }
    else if (condition == 'timeout') {
      result = _evalTimeout(history: history, historyIndex: historyIndex, rules: rules);
    }
    else if (condition == 'test-user') {
      result = _evalTestUser(rules: rules);
    }
    else if (condition == 'test-interval') {
      result = _evalTestInterval(rules: rules);
    }
    return result?.eval(history: history, historyIndex: historyIndex, rules: rules);
  }

  _HealthRuleStatus _evalRequireTest({ List<Covid19History> history, int historyIndex, HealthRulesSet rules }) {
    
    Covid19History historyEntry = ((history != null) && (historyIndex != null) && (0 <= historyIndex) && (historyIndex < history.length)) ? history[historyIndex] : null;
    DateTime historyDateMidnightLocal = historyEntry?.dateMidnightLocal;
    if (historyDateMidnightLocal == null) {
      return null;
    }
    
    _HealthRuleIntInterval interval = _HealthRuleIntInterval.fromJson(params['interval']);
    if (interval == null) {
      return null;
    }

    dynamic category = params['category'];
    if (category is List) {
      category = Set.from(category);
    }

    int scope = interval.scope(rules: rules) ?? 0;
    if (0 < scope) { // check only newer items than the current
      for (int index = historyIndex - 1; 0 <= index; index--) {
        if (_evalRequireTestEntryFulfills(history[index], historyDateMidnightLocal: historyDateMidnightLocal, interval: interval, rules: rules, category: category)) {
          return successStatus;
        }
      }
    }
    else if (0 < scope) { // check only older items than the current
      for (int index = historyIndex + 1; index < history.length; index++) {
        if (_evalRequireTestEntryFulfills(history[index], historyDateMidnightLocal: historyDateMidnightLocal, interval: interval, rules: rules, category: category)) {
          return successStatus;
        }
      }
    }
    else { // check all history items
      for (int index = 0; index < history.length; index++) {
        if ((index != historyIndex) && _evalRequireTestEntryFulfills(history[index], historyDateMidnightLocal: historyDateMidnightLocal, interval: interval, rules: rules, category: category)) {
          return successStatus;
        }
      }
    }

    // If positive time interval is not already expired - do not return failed status yet.
    if ((interval.current(rules: rules) == true) && _evalCurrentIntervalFulfills(interval, historyDateMidnightLocal: historyDateMidnightLocal, rules: rules)) {
      return successStatus;
    }

    return failStatus;
  }

  static bool _evalRequireTestEntryFulfills(Covid19History entry, { DateTime historyDateMidnightLocal,  _HealthRuleIntInterval interval, HealthRulesSet rules, dynamic category }) {
    if (entry.isTest && entry.canTestUpdateStatus) {
      DateTime entryDateMidnightLocal = entry.dateMidnightLocal;
      final difference = entryDateMidnightLocal.difference(historyDateMidnightLocal).inDays;
      if (interval.match(difference, rules: rules)) {
        if (category == null) {
          return true; // any test matches
        }
        else {
          HealthTestRuleResult entryRuleResult = rules?.tests?.matchRuleResult(blob: entry?.blob);
          if ((entryRuleResult != null) && (entryRuleResult.category != null) &&
              (((category is String) && (category == entryRuleResult.category)) ||
                ((category is Set) && category.contains(entryRuleResult.category))))
          {
            return true; // only tests from given category matches
          }
        }
      }
    }
    return false;
  }

  _HealthRuleStatus _evalRequireSymptoms({ List<Covid19History> history, int historyIndex, HealthRulesSet rules }) {
    Covid19History historyEntry = ((history != null) && (historyIndex != null) && (0 <= historyIndex) && (historyIndex < history.length)) ? history[historyIndex] : null;
    DateTime historyDateMidnightLocal = historyEntry?.dateMidnightLocal;
    if (historyDateMidnightLocal == null) {
      return null;
    }

    _HealthRuleIntInterval interval = _HealthRuleIntInterval.fromJson(params['interval']);
    if (interval == null) {
      return null;
    }

    int scope = interval.scope(rules: rules) ?? 0;
    if (0 < scope) { // check only newer items than the current
      for (int index = historyIndex - 1; 0 <= index; index--) {
        if (_evalRequireSymptomsEntryFulfills(history[index], historyDateMidnightLocal: historyDateMidnightLocal, interval: interval, rules: rules)) {
          return successStatus;
        }
      }
    }
    else if (0 < scope) { // check only older items than the current
      for (int index = historyIndex + 1; index < history.length; index++) {
        if (_evalRequireSymptomsEntryFulfills(history[index], historyDateMidnightLocal: historyDateMidnightLocal, interval: interval, rules: rules)) {
          return successStatus;
        }
      }
    }
    else { // check all history items
      for (int index = 0; index < history.length; index++) {
        if ((index != historyIndex) && _evalRequireSymptomsEntryFulfills(history[index], historyDateMidnightLocal: historyDateMidnightLocal, interval: interval, rules: rules)) {
          return successStatus;
        }
      }
    }

    // If positive time interval is not already expired - do not return failed status yet.
    if ((interval.current(rules: rules) == true) && _evalCurrentIntervalFulfills(interval, historyDateMidnightLocal: historyDateMidnightLocal, rules: rules)) {
      return successStatus;
    }

    return failStatus;
  }

  static bool _evalRequireSymptomsEntryFulfills(Covid19History entry, { DateTime historyDateMidnightLocal,  _HealthRuleIntInterval interval, HealthRulesSet rules }) {
    if (entry.isSymptoms) {
      DateTime entryDateMidnightLocal = entry.dateMidnightLocal;
      final difference = entryDateMidnightLocal.difference(historyDateMidnightLocal).inDays;
      if (interval.match(difference, rules: rules)) {
        return true;
      }
    }
    return false;
  }

  _HealthRuleStatus _evalTestUser({ HealthRulesSet rules }) {
    dynamic role = params['role'];
    if ((role != null) && !_matchStringTarget(target: Auth().authCard?.role, source: role)) {
      return failStatus;
    }
    dynamic studentLevel = params['student_level'];
    if ((studentLevel != null) && !_matchStringTarget(target: Auth().authCard?.studentLevel, source: studentLevel)) {
      return failStatus;
    }
    return successStatus;
  }

  _HealthRuleStatus _evalTestInterval({ HealthRulesSet rules }) {
    dynamic interval = _HealthRuleIntInterval.fromJson(params['interval']);
    return (interval?.valid(rules: rules) ?? false) ? successStatus : failStatus;
  }

  static bool _matchStringTarget({dynamic source, String target}) {
    if (target != null) {
      if (source is String) {
        return source.toLowerCase() == target.toLowerCase();
      }
      else if (source is List) {
        for (dynamic sourceEntry in source) {
          if ((sourceEntry is String) && (sourceEntry.toLowerCase() == target.toLowerCase())) {
            return true;
          }
        }
      }
    }
    return false;
  }

  _HealthRuleStatus _evalTimeout({ List<Covid19History> history, int historyIndex, HealthRulesSet rules }) {
    Covid19History historyEntry = ((history != null) && (historyIndex != null) && (0 <= historyIndex) && (historyIndex < history.length)) ? history[historyIndex] : null;
    DateTime historyDateMidnightLocal = historyEntry?.dateMidnightLocal;
    if (historyDateMidnightLocal == null) {
      return null;
    }

    _HealthRuleIntInterval interval = _HealthRuleIntInterval.fromJson(params['interval']);
    if (interval == null) {
      return null;
    }

    return _evalCurrentIntervalFulfills(interval, historyDateMidnightLocal: historyDateMidnightLocal, rules: rules) ?
      failStatus : successStatus; // while current time is within interval 'timeout' condition fails
  }

  static bool _evalCurrentIntervalFulfills(_HealthRuleIntInterval currentInterval, { DateTime historyDateMidnightLocal, HealthRulesSet rules } ) {
    if (currentInterval != null) {
      final difference = AppDateTime.todayMidnightLocal.difference(historyDateMidnightLocal).inDays;
      if (currentInterval.match(difference, rules: rules)) {
        return true;
      }
    }
    return false;
  }
}

///////////////////////////////
// _HealthRuleIntInterval

abstract class _HealthRuleIntInterval {
  _HealthRuleIntInterval();
  
  factory _HealthRuleIntInterval.fromJson(dynamic json) {
    if (json is int) {
      return HealthRuleIntValue.fromJson(json);
    }
    else if (json is String) {
      return HealthRuleIntReference.fromJson(json);
    }
    else if (json is Map) {
      return HealthRuleIntInterval.fromJson(json.cast<String, dynamic>());
    }
    else {
      return null;
    }
  }

  bool match(int value, { HealthRulesSet rules });
  int  value({ HealthRulesSet rules });
  bool valid({ HealthRulesSet rules });
  int  scope({ HealthRulesSet rules });
  bool current({ HealthRulesSet rules });
}

///////////////////////////////
// HealthRuleIntValue

class HealthRuleIntValue extends _HealthRuleIntInterval {
  final int _value;
  
  HealthRuleIntValue({int value}) :
    _value = value;

  factory HealthRuleIntValue.fromJson(dynamic json) {
    return (json is int) ? HealthRuleIntValue(value: json) : null;
  }

  @override
  bool match(int value, { HealthRulesSet rules }) {
    return (_value == value);
  }

  @override int  value({ HealthRulesSet rules })   { return _value; }
  @override bool valid({ HealthRulesSet rules })   { return (_value != null); }
  @override int  scope({ HealthRulesSet rules })   { return null; }
  @override bool current({ HealthRulesSet rules }) { return null; }
}

///////////////////////////////
// HealthRuleIntInterval

class HealthRuleIntInterval extends _HealthRuleIntInterval {
  final _HealthRuleIntInterval _min;
  final _HealthRuleIntInterval _max;
  final int _scope;
  final bool _current;
  
  HealthRuleIntInterval({_HealthRuleIntInterval min, _HealthRuleIntInterval max, int scope, bool current}) :
    _min = min,
    _max = max,
    _scope = scope,
    _current = current;
    

  factory HealthRuleIntInterval.fromJson(Map<String, dynamic> json) {
    return (json != null) ? HealthRuleIntInterval(
      min: _HealthRuleIntInterval.fromJson(json['min']) ,
      max: _HealthRuleIntInterval.fromJson(json['max']),
      scope: _scopeFromJson(json['scope']),
      current: json['current']
    ) : null;
  }

  @override
  bool match(int value, { HealthRulesSet rules }) {
    if (value != null) {
      if (_min != null) {
        int minValue = _min.value(rules: rules);
        if ((minValue == null) || (minValue > value)) {
          return false;
        }
      }
      if (_max != null) {
        int maxValue = _max.value(rules: rules);
        if ((maxValue == null) || (maxValue < value)) {
          return false;
        }
      }
      return true;
    }
    return false;
  }

  @override bool valid({ HealthRulesSet rules })   {
    return ((_min == null) || _min.valid(rules: rules)) &&
           ((_max == null) || _max.valid(rules: rules));
  }

  @override int  value({ HealthRulesSet rules }) { return null; }
  @override int  scope({ HealthRulesSet rules }) { return _scope; }
  @override bool current({ HealthRulesSet rules }) { return _current; }

  static int _scopeFromJson(dynamic value) {
    if (value is String) {
      if (value == 'future') {
        return 1;
      }
      else if (value == 'past') {
        return -1;
      }
    }
    else if (value is int) {
      if (0 < value) {
        return 1;
      }
      else if (value < 0) {
        return -1;
      }
    }
    return null;
  }
}

///////////////////////////////
// HealthRuleIntReference

class HealthRuleIntReference extends _HealthRuleIntInterval {
  final String _reference;
  _HealthRuleIntInterval _referenceValue;

  HealthRuleIntReference({String reference}) :
    _reference = reference;

  factory HealthRuleIntReference.fromJson(dynamic json) {
    return (json is String) ? HealthRuleIntReference(reference: json) : null;
  }

  _HealthRuleIntInterval referenceValue({ HealthRulesSet rules }) {
    if (_referenceValue == null) {
      dynamic value = (rules?.constants != null) ? rules.constants[_reference] : null;
      _referenceValue = _HealthRuleIntInterval.fromJson(value);
    }
    return _referenceValue;
  }

  @override
  bool match(int value, { HealthRulesSet rules }) {
    return referenceValue(rules: rules)?.match(value, rules: rules) ?? false;
  }
  
  @override bool valid({ HealthRulesSet rules })   { return referenceValue(rules: rules)?.valid(rules: rules) ?? false; }
  @override int  value({ HealthRulesSet rules })   { return referenceValue(rules: rules)?.value(rules: rules); }
  @override int  scope({ HealthRulesSet rules })   { return referenceValue(rules: rules)?.scope(rules: rules); }
  @override bool current({ HealthRulesSet rules }) { return referenceValue(rules: rules)?.current(rules: rules); }
}

///////////////////////////////
// Health DateTime

final List<String> _covid19ServerDateFormatsIn  = [
  "yyyy-MM-ddTHH:mm:ss.SSSZ",
  "yyyy-MM-ddTHH:mm:ss.SSZ",
  "yyyy-MM-ddTHH:mm:ss.SZ",
  "yyyy-MM-ddTHH:mm:ssZ",
];
final String _covid19ServerDateFormatOut = "yyyy-MM-ddTHH:mm:ss.SSS";

DateTime healthDateTimeFromString(String dateTimeString) {
  if (dateTimeString != null) {
    for (String dateFormat in _covid19ServerDateFormatsIn) {
      if (dateTimeString.length == dateFormat.length) {
        try { return DateFormat(dateFormat).parse(dateTimeString, true); }
        catch (e) { print(e?.toString()); }
      }
    }
  }
  return null;
}

String healthDateTimeToString(DateTime dateTime) {
  if (dateTime != null) {
    try { return DateFormat(_covid19ServerDateFormatOut).format(dateTime) + 'Z'; }
    catch (e) { print(e?.toString()); }
  }
  return null;
}

///////////////////////////////
// Blob Encryption & Decryption

String _decryptBlob(Map<String, dynamic> param) {
  String encKey = (param != null) ? param['encryptedKey'] : null;
  String encBlob = (param != null) ? param['encryptedBlob'] : null;
  PrivateKey privateKey = (param != null) ? param['privateKey'] : null;

  Uint8List aesKey = ((privateKey != null) && (encKey != null)) ? RSACrypt.decryptBytes(encKey, privateKey) : null;
  String blob = ((aesKey != null) && (encBlob != null)) ? AESCrypt.decrypt(encBlob, aesKey) : null;
  return blob;
}

Map<String, dynamic> _encryptBlob(Map<String, dynamic> param) {
  String blob = (param != null) ? param['blob'] : null;
  PublicKey publicKey =  (param != null) ? param['publicKey'] : null;
  Uint8List aesKey = AESCrypt.randomKey();

  String encryptedBlob = ((blob != null) && (aesKey != null)) ? AESCrypt.encrypt(blob, aesKey) : null;
  String encryptedKey = ((blob != null) && (aesKey != null) && (publicKey != null)) ? RSACrypt.encryptBytes(aesKey, publicKey) : null;

  return {
    'encryptedKey': encryptedKey,
    'encryptedBlob': encryptedBlob,
  };
}



