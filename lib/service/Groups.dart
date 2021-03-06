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

import 'dart:async';
import 'dart:convert';
import 'dart:core';

import 'package:http/http.dart';
import 'package:illinois/model/Groups.dart';
//import 'package:flutter/services.dart' show rootBundle;
import 'package:illinois/service/Auth.dart';
import 'package:illinois/service/Config.dart';
import 'package:illinois/service/Network.dart';
import 'package:illinois/service/NotificationService.dart';
import 'package:illinois/utils/Utils.dart';

class Groups /* with Service */ {

  static const String notifyUserMembershipUpdated   = "edu.illinois.rokwire.groups.membership.updated";
  static const String notifyGroupCreated            = "edu.illinois.rokwire.group.created";
  static const String notifyGroupUpdated            = "edu.illinois.rokwire.group.updated";

  static final Map<String,String> _apiHeader        = {Network.RokwireAppId : "edu.illinois.covid"};

  Map<String, Member> _userMembership;

  // Singletone instance

  static final Groups _service = Groups._internal();
  Groups._internal();

  factory Groups() {
    return _service;
  }

  // Emulation

  /*Future<Map<String, dynamic>> get _sampleJson async {
      Map<String, dynamic> result;
      try {
        String sampleSource = await rootBundle.loadString('assets/sample.groups.json');
        result = (sampleSource != null) ? json.decode(sampleSource) : null;
      }
      catch(e) {
        print(e.toString());
      }
      return result ?? {};
  }*/

  // Current User Membership

  Member getUserMembership(String groupId) {
    return (_userMembership != null) ? _userMembership[groupId] : null;
  }

  // Enumeration APIs

  Future<List<String>> get categories async {
    String url = '${Config().groupsUrl}/group-categories';
    try {
      Response response = await Network().get(url, auth: Network.AppAuth, headers: _apiHeader);
      int responseCode = response?.statusCode ?? -1;
      String responseBody = response?.body;
      List<dynamic> categoriesJson = ((response != null) && (responseCode == 200)) ? jsonDecode(responseBody) : null;
      if(AppCollection.isCollectionNotEmpty(categoriesJson)){
        return categoriesJson.map((e) => e.toString()).toList();
      }
    } catch (e) {
      print(e);
    }
    return <String>[];
  }


  // Groups APIs

  Future<List<Group>> loadGroups({bool myGroups = false}) async {
    String url = myGroups ? '${Config().groupsUrl}/user/groups' : '${Config().groupsUrl}/groups';
    try {
      Response response = await Network().get(url, auth: myGroups ? Network.ShibbolethUserAuth : (Auth().isShibbolethLoggedIn) ? Network.ShibbolethUserAuth : Network.AppAuth, headers: _apiHeader);
      int responseCode = response?.statusCode ?? -1;
      String responseBody = response?.body;
      List<dynamic> groupsJson = ((response != null) && (responseCode == 200)) ? jsonDecode(responseBody) : null;
      if(AppCollection.isCollectionNotEmpty(groupsJson)){
        return groupsJson.map((e) => Group.fromJson(e)).toList();
      }
    } catch (e) {
      print(e);
    }
    return <Group>[];
  }

  Future<Group>loadGroup(String groupId) async {
    if(AppString.isStringNotEmpty(groupId)) {
      String url = '${Config().groupsUrl}/groups/$groupId';
      try {
        Response response = await Network().get(url, auth: Auth().isShibbolethLoggedIn ? Network.ShibbolethUserAuth : Network.AppAuth,headers: _apiHeader);
        int responseCode = response?.statusCode ?? -1;
        String responseBody = response?.body;
        Map<String, dynamic> groupsJson = ((response != null) && (responseCode == 200)) ? jsonDecode(responseBody) : null;
        return groupsJson != null ? Group.fromJson(groupsJson) : null;
      } catch (e) {
        print(e);
      }
    }
    return null;
  }

  Future<String>createGroup(Group group) async {
    if(group != null) {
      String url = '${Config().groupsUrl}/groups';
      try {
        Map<String, dynamic> json = group.toJson(withId: false);
        json["creator_email"] = Auth()?.authUser?.email ?? "";
        json["creator_name"] = Auth()?.authUser?.fullName ?? "";
        json["creator_photo_url"] = "";
        String body = jsonEncode(json);
        Response response = await Network().post(url, auth: Network.ShibbolethUserAuth, body: body, headers: _apiHeader);
        int responseCode = response?.statusCode ?? -1;
        String responseBody = response?.body;
        Map<String, dynamic> jsonData = ((response != null) && (responseCode == 200)) ? jsonDecode(responseBody) : null;
        if(jsonData != null){
          String groupId = jsonData['inserted_id'];
          NotificationService().notify(notifyGroupCreated, group.id);
          return groupId;
        }
      } catch (e) {
        print(e);
      }
    }
    return null;
  }

  Future<bool>updateGroup(Group group) async {
    if(group != null) {
      String url = '${Config().groupsUrl}/groups/${group.id}';
      try {
        Map<String, dynamic> json = group.toJson();
        String body = jsonEncode(json);
        Response response = await Network().put(url, auth: Network.ShibbolethUserAuth, body: body, headers: _apiHeader);
        if((response?.statusCode ?? -1) == 200){
          NotificationService().notify(notifyGroupUpdated, group.id);
          return true;
        }
      } catch (e) {
        print(e);
      }
    }
    return false;
  }

  // Members APIs

  Future<bool> requestMembership(Group group, List<GroupMembershipAnswer> answers) async{
    if(group != null) {
      String url = '${Config().groupsUrl}/group/${group.id}/pending-members';
      try {
        Map<String, dynamic> json = {};
        json["email"] = Auth()?.authUser?.email ?? "";
        json["name"] = Auth()?.authUser?.fullName ?? "";
        json["creator_photo_url"] = "";
        json["member_answers"] = AppCollection.isCollectionNotEmpty(answers) ? answers.map((e) => e.toJson()).toList() : <GroupMembershipAnswer>[];

        String body = jsonEncode(json);
        Response response = await Network().post(url, auth: Network.ShibbolethUserAuth, body: body, headers: _apiHeader);
        if((response?.statusCode ?? -1) == 200){
          NotificationService().notify(notifyGroupUpdated, group.id);
          return true;
        }
      } catch (e) {
        print(e);
      }
    }
    return false; // fail
  }

  Future<bool> cancelRequestMembership(String groupId) async{
    if(groupId != null) {
      String url = '${Config().groupsUrl}/group/$groupId/pending-members';
      try {
        Response response = await Network().delete(url, auth: Network.ShibbolethUserAuth, headers: _apiHeader);
        if((response?.statusCode ?? -1) == 200){
          NotificationService().notify(notifyGroupUpdated, groupId);
          return true;
        }
      } catch (e) {
        print(e);
      }
    }
    return false; // fail
  }

  Future<bool> leaveGroup(String groupId) async{
    if(groupId != null) {
      String url = '${Config().groupsUrl}/group/$groupId/members';
      try {
        Response response = await Network().delete(url, auth: Network.ShibbolethUserAuth, headers: _apiHeader);
        if((response?.statusCode ?? -1) == 200){
          NotificationService().notify(notifyGroupUpdated, groupId);
          return true;
        }
      } catch (e) {
        print(e);
      }
    }
    return false; // fail
  }

  Future<bool> acceptMembership(String groupId, String memberId, bool decision, String reason) async{
    if(AppString.isStringNotEmpty(groupId) && AppString.isStringNotEmpty(memberId) && decision != null) {
      Map<String, dynamic> bodyMap = {"approve": decision, "reject_reason": reason};
      String body = jsonEncode(bodyMap);
      String url = '${Config().groupsUrl}/memberships/$memberId/approval';
      try {
        Response response = await Network().put(url, auth: Network.ShibbolethUserAuth, body: body, headers: _apiHeader);
        if((response?.statusCode ?? -1) == 200){
          NotificationService().notify(notifyGroupUpdated, groupId);
          return true;
        }
      } catch (e) {
        print(e);
      }
    }
    return false; // fail
  }

  Future<bool> updateMembership(String groupId, String memberId, GroupMemberStatus status) async{
    if(AppString.isStringNotEmpty(groupId) && AppString.isStringNotEmpty(memberId)) {
      Map<String, dynamic> bodyMap = {"status":groupMemberStatusToString(status)};
      String body = jsonEncode(bodyMap);
      String url = '${Config().groupsUrl}/memberships/$memberId';
      try {
        Response response = await Network().put(url, auth: Network.ShibbolethUserAuth, body: body, headers: _apiHeader);
        if((response?.statusCode ?? -1) == 200){
          NotificationService().notify(notifyGroupUpdated, groupId);
          return true;
        }
      } catch (e) {
        print(e);
      }
    }
    return false; // fail
  }

  Future<bool> deleteMembership(String groupId, String memberId) async{
    if(AppString.isStringNotEmpty(groupId) && AppString.isStringNotEmpty(memberId)) {
      String url = '${Config().groupsUrl}/memberships/$memberId';
      try {
        Response response = await Network().delete(url, auth: Network.ShibbolethUserAuth, headers: _apiHeader);
        if((response?.statusCode ?? -1) == 200){
          NotificationService().notify(notifyGroupUpdated, groupId);
          return true;
        }
      } catch (e) {
        print(e);
      }
    }
    return false; // fail
  }


// Events
  Future<List<dynamic>> loadEventIds(String groupId) async{
    if(AppString.isStringNotEmpty(groupId)) {
      String url = '${Config().groupsUrl}/group/$groupId/events';
      try {
        Response response = await Network().get(url, auth: Network.ShibbolethUserAuth, headers: _apiHeader);
        if((response?.statusCode ?? -1) == 200){
          //Successfully loaded ids
          String responseBody = response?.body;
          List<dynamic> eventIdsJson = (response != null) ? jsonDecode(responseBody) : null;
          return eventIdsJson;
        }
      } catch (e) {
        print(e);
      }
    }
    return null; // fail
  }

  /*Future<List<GroupEvent>> loadEvents(String groupId, {int limit = -1}) async {
    List<dynamic> eventIds = await loadEventIds(groupId);
    List<Event> events = AppCollection.isCollectionNotEmpty(eventIds)? await ExploreService().loadEventsByIds(Set<String>.from(eventIds)) : null;
    if(AppCollection.isCollectionNotEmpty(events)){
      //limit the result count // limit available events
      List<Event> visibleEvents = (limit>0 && events.length>limit)? events.sublist(0,limit) : events;
      return visibleEvents?.map((Event event) => GroupEvent.fromJson(event?.toJson()))?.toList();
    }
    return null;
  }*/

  Future<bool> linkEventToGroup({String groupId, String eventId}) async {
    if(AppString.isStringNotEmpty(groupId) && AppString.isStringNotEmpty(eventId)) {
      String url = '${Config().groupsUrl}/group/$groupId/events';
      try {
        Map<String, dynamic> bodyMap = {"event_id":eventId};
        String body = jsonEncode(bodyMap);
        Response response = await Network().post(url, auth: Network.ShibbolethUserAuth,body: body, headers: _apiHeader);
        if((response?.statusCode ?? -1) == 200){
          NotificationService().notify(notifyGroupUpdated, groupId);
          return true;
        }
      } catch (e) {
        print(e);
      }
    }
    return false; // fail
  }

  Future<bool> removeEventFromGroup({String groupId, String eventId}) async {
    if(AppString.isStringNotEmpty(groupId) && AppString.isStringNotEmpty(eventId)) {
      String url = '${Config().groupsUrl}/group/$groupId/event/$eventId';
      try {
        Response response = await Network().delete(url, auth: Network.ShibbolethUserAuth, headers: _apiHeader);
        if((response?.statusCode ?? -1) == 200){
          NotificationService().notify(notifyGroupUpdated, groupId);
          return true;
        }
      } catch (e) {
        print(e);
      }
    }
    return false;
  }

  Future<bool> deleteEventFromGroup({String groupId, String eventId}) async {
    //TBD
    return false;
  }

  /*Future<Event> createGroupEvent(String groupId, Event event) async {
    //TBD
    return Future<Event>.delayed(Duration(seconds: 1), (){ return event; });
  }

  Future<bool> updateGroupEvents(String groupId, List<Event> events) async {
    return Future<bool>.delayed(Duration(seconds: 1), (){ return true; });
  }

  // Event Comments

  Future<bool> postEventComment(String groupId, String eventId, GroupEventComment comment) {
    return Future<bool>.delayed(Duration(seconds: 1), (){ return true; });
  }*/
}