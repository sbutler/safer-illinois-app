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

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:illinois/model/Groups.dart';
import 'package:illinois/service/Analytics.dart';
import 'package:illinois/service/Auth.dart';
import 'package:illinois/service/Groups.dart';
import 'package:illinois/service/Localization.dart';
import 'package:illinois/service/NotificationService.dart';
import 'package:illinois/ui/groups/GroupMembershipRequestPanel.dart';
import 'package:illinois/ui/groups/GroupWidgets.dart';
import 'package:illinois/ui/widgets/ExpandableText.dart';
import 'package:illinois/ui/widgets/RibbonButton.dart';
import 'package:illinois/ui/widgets/RoundedButton.dart';
import 'package:illinois/service/Styles.dart';
import 'package:illinois/ui/widgets/TrianglePainter.dart';
import 'package:illinois/utils/Utils.dart';
import 'package:sprintf/sprintf.dart';
import 'package:url_launcher/url_launcher.dart';

import 'GroupMembersPanel.dart';
import 'GroupSettingsPanel.dart';

enum _DetailTab { Events, About }

class GroupPanel extends StatefulWidget {

  final String groupId;

  GroupPanel({this.groupId});

  @override
  _GroupPanelState createState() => _GroupPanelState();
}

class _GroupPanelState extends State<GroupPanel> implements NotificationsListener {

  Group              _group;
  bool               _loading = false;
  bool               _cancelling = false;
  bool               _leaving = false;
  List<Member>       _groupAdmins;

  _DetailTab       _currentTab = _DetailTab.Events;

  bool get _isMember {
    if(_group?.members?.isNotEmpty ?? false){
      for(Member member in _group.members){
        if(member.email == Auth()?.authUser?.email){
          return true;
        }
      }
    }
    return false;
  }
  
  bool get _isAdmin {
    if(_group?.members?.isNotEmpty ?? false){
      for(Member member in _group.members){
        if(member.email == Auth()?.authUser?.email && member.status == GroupMemberStatus.admin){
          return true;
        }
      }
    }
    return false;
  }

  bool get isPublic {
    return _group?.privacy == GroupPrivacy.public;
  }

  bool get isFavorite {
    return false;
  }

  @override
  void initState() {
    super.initState();
    NotificationService().subscribe(this, [Groups.notifyUserMembershipUpdated, Groups.notifyGroupCreated, Groups.notifyGroupUpdated]);
    _loadGroup();
  }

  @override
  void dispose() {
    super.dispose();

    NotificationService().unsubscribe(this);
  }

  void _loadGroup(){
    setState(() {
      _loading = true;
    });
    Groups().loadGroup(widget.groupId).then((Group group){
      if (mounted) {
        setState(() {
          _loading = false;
          if(group != null) {
            _group = group;
            _groupAdmins = _group.getMembersByStatus(GroupMemberStatus.admin);
          }
        });
      }
    });
  }

  void _cancelMembershipRequest(){
    setState(() {
      _cancelling = true;
    });
    Groups().cancelRequestMembership(widget.groupId).whenComplete((){
      if (mounted) {
        setState(() {
          _cancelling = false;
        });
        _loadGroup();
      }
    });
  }

  Future<void> _leaveGroup(Function setStateEx){
    setStateEx(() {
      _leaving = true;
    });
    return Groups().leaveGroup(widget.groupId).whenComplete((){
      if (mounted) {
        setStateEx(() {
          _leaving = false;
        });
        _loadGroup();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_loading == true) {
      content = _buildLoadingContent();
    }
    else if (_group != null) {
      content = _buildGroupContent();
    }
    else {
      content = _buildErrorContent();
    }

    return Scaffold(
      appBar: AppBar(
        leading: HeaderBackButton(),
        actions: [
          Semantics(
              label:  Localization().getStringEx("panel.group_detail.label.options", 'Options'),
              button: true,
              excludeSemantics: true,
              child: IconButton(
                icon: Image.asset(
                  'images/groups-more-inactive.png',
                ),
                onPressed:_onGroupOptionsTap,
              ))
        ],
      ),
      backgroundColor: Styles().colors.background,
      body: content,
    );
  }

  // NotificationsListener

  @override
  void onNotification(String name, dynamic param) {
    if (name == Groups.notifyUserMembershipUpdated) {
      setState(() {});
    }
    else if (param == widget.groupId && (name == Groups.notifyGroupCreated || name == Groups.notifyGroupUpdated)){
      _loadGroup();
    }
  }

  // Content Builder

  Widget _buildLoadingContent() {
    return Stack(children: <Widget>[
      Column(children: <Widget>[
        Expanded(
          child: Center(
            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Styles().colors.fillColorSecondary), ),
          ),
        ),
      ]),
      SafeArea(
        child: HeaderBackButton()
      ),
    ],);
  }

  Widget _buildErrorContent() {
    return Stack(children: <Widget>[
      Column(children: <Widget>[
        Expanded(
          child: Center(
            child: Padding(padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(Localization().getStringEx("panel.group_detail.label.error_message", 'Failed to load group data.'),  style: TextStyle(fontFamily: Styles().fontFamilies.bold, fontSize: 20, color: Styles().colors.fillColorPrimary),)
            ),
          ),
        ),
      ]),
      SafeArea(
        child: HeaderBackButton()
      ),
    ],);
  }

  Widget _buildGroupContent() {
    List<Widget> content = [
      _buildImageHeader(),
      _buildGroupInfo()
    ];
    if (_isMember) {
      content.add(_buildTabs());
      if (_currentTab == _DetailTab.About) {
        content.add(_buildAbout());
      }
    }
    else {
      content.add(_buildAbout());
      content.add(_buildAdmins());
    }

    return Column(children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: content,
            ),
          ),
        ),
        _buildMembershipRequest(),
        _buildCancelMembershipRequest(),
      ],
    );
  }

  Widget _buildImageHeader(){
    return Container(
      height: 200,
      color: Styles().colors.background,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          AppString.isStringNotEmpty(_group?.imageURL) ?  Positioned.fill(child:Image.network(_group?.imageURL, fit: BoxFit.cover, headers: AppImage.getAuthImageHeaders(),)) : Container(),
          CustomPaint(
            painter: TrianglePainter(painterColor: Styles().colors.fillColorSecondaryTransparent05, left: false),
            child: Container(
              height: 53,
            ),
          ),
          CustomPaint(
            painter: TrianglePainter(painterColor: Styles().colors.white),
            child: Container(
              height: 30,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupInfo() {
    List<Widget> commands = [];

    String members;
    int membersCount = _group?.membersCount ?? 0;
    if (membersCount == 0) {
      members = Localization().getStringEx("panel.group_detail.members.count.empty", "No Current Members");
    }
    else if (membersCount == 1) {
      members = Localization().getStringEx("panel.group_detail.members.count.one", "1 Current Member");
    }
    else {
      members = sprintf(Localization().getStringEx("panel.group_detail.members.count.format", "%s Current Members"),[membersCount]);
    }

    if(_isMember){
      if(_isAdmin){
        commands.add(RibbonButton(
          height: null,
          label: Localization().getStringEx("panel.group_detail.button.manage_members.title", "Manage Members"),
          hint: Localization().getStringEx("panel.group_detail.button.manage_members.hint", ""),
          leftIcon: 'images/icon-member.png',
          padding: EdgeInsets.symmetric(vertical: 14, horizontal: 0),
          onTap: onTapMembers,
        ));
        commands.add(Container(height: 1, color: Styles().colors.surfaceAccent,));
        commands.add(RibbonButton(
          height: null,
          label: Localization().getStringEx("panel.group_detail.button.group_settings.title", "Group Settings"),
          hint: Localization().getStringEx("panel.group_detail.button.group_settings.hint", ""),
          leftIcon: 'images/icon-gear.png',
          padding: EdgeInsets.symmetric(vertical: 14, horizontal: 0),
          onTap: onTapSettings,
        ));
      }
    } else {
      String tags = "";
      if (_group?.tags?.isNotEmpty ?? false) {
        for (String tag in _group.tags) {
          if (0 < (tag?.length ?? 0)) {
            tags+=((tags.isNotEmpty? ", ": "") + tag ?? '');
          }
        }
      }

      commands.add(
        RibbonButton(label: Localization().getStringEx("panel.group_detail.button.website.title", 'Website'),
          icon: 'images/external-link.png',
          leftIcon: 'images/globe.png',
          padding: EdgeInsets.symmetric(horizontal: 0),
          onTap: (){ _onWebsite(); },)
      );
      if(tags?.isNotEmpty ?? false) {
        commands.add(Container(height: 12,));
        commands.add(
          Padding(padding: EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child:
              RichText(
                text: new TextSpan(
                  style: TextStyle(color: Styles().colors.textSurface,
                      fontFamily: Styles().fontFamilies.bold,
                      fontSize: 12),
                  children: <TextSpan>[
                    new TextSpan(text: Localization().getStringEx("panel.group_detail.label.tags", "Group Tags: ")),
                    new TextSpan(
                        text: tags,
                        style: TextStyle(
                            fontFamily: Styles().fontFamilies.regular)),
                  ],
                ),
              )
              )
            ],),
          ),);
      }
    }

    return Container(color: Colors.white,
      child: Stack(children: <Widget>[
        Padding(padding: EdgeInsets.only(left: 16, right: 16, top: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _isMember? Container():
                Padding(padding: EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: <Widget>[
                    Expanded(child:
                      Text(_group?.category?.toUpperCase() ?? '', style: TextStyle(fontFamily: Styles().fontFamilies.bold, fontSize: 12, color: Styles().colors.fillColorPrimary),),
                    ),
                  ],),),
              (!_isMember)? Container():
                Container(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: <Widget>[
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _group.currentUserStatusColor,
                          borderRadius: BorderRadius.all(Radius.circular(2)),
                        ),
                        child: Center(
                          child:
                          Semantics(
                            label: _group?.currentUserStatusText?.toLowerCase(),
                            excludeSemantics: true,
                            child: Text(_group.currentUserStatusText.toUpperCase(),
                              style: TextStyle(
                                  fontFamily: Styles().fontFamilies.bold,
                                  fontSize: 12,
                                  color: Styles().colors.white
                              ),
                            )
                          ),
                        ),
                      ),
                      Expanded(child: Container(),),
                    ],
                  ),
                ),
              Padding(padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(_group?.title ?? '',  style: TextStyle(fontFamily: Styles().fontFamilies.extraBold, fontSize: 32, color: Styles().colors.fillColorPrimary),),
              ),
              Padding(padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(members,  style: TextStyle(fontFamily: Styles().fontFamilies.bold, fontSize: 16, color: Styles().colors.textBackground, ),)
              ),
              Padding(padding: EdgeInsets.symmetric(vertical: 4),
                child: Column(children: commands,),
              ),
            ],),
          ),
        ],),
      );
  }

  Widget _buildTabs() {
    List<Widget> tabs = [];
    for (_DetailTab tab in _DetailTab.values) {
      String title;
      switch(tab) {
        case _DetailTab.Events: title = Localization().getStringEx("panel.group_detail.button.events.title", 'Events'); break;
        case _DetailTab.About: title = Localization().getStringEx("panel.group_detail.button.about.title", 'About'); break;
      }
      bool selected = (_currentTab == tab);

      if (0 < tabs.length) {
        tabs.add(Padding(padding: EdgeInsets.only(left: 8),child: Container(),));
      }

      tabs.add(Row(mainAxisSize: MainAxisSize.max, children: <Widget>[
        RoundedButton(label: title,
          backgroundColor: selected ? Styles().colors.fillColorPrimary : Styles().colors.background,
          textColor: selected ? Colors.white :  Styles().colors.fillColorPrimary,
          fontFamily: selected ? Styles().fontFamilies.bold : Styles().fontFamilies.regular,
          fontSize: 16,
          padding: EdgeInsets.symmetric(horizontal: 16),
          borderColor: selected ? Styles().colors.fillColorPrimary : Styles().colors.surfaceAccent,
          borderWidth: 1,
          height: 22 + 16*MediaQuery.of(context).textScaleFactor,
          onTap:() { _onTab(tab); }
        ),
      ],));
    }

    return
      Row(children: [
        Expanded(
          child: Container(
            child: Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children:tabs),
                )
            ),
          )
        )
      ],);
  }


  Widget _buildAbout() {
    String description = _group?.description ?? '';
    return Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(padding: EdgeInsets.only(bottom: 16), child:
          Text( Localization().getStringEx("panel.group_detail.label.about_us",  'About us'), style: TextStyle(fontFamily: Styles().fontFamilies.extraBold, fontSize: 16, color: Color(0xff494949), ),),
        ),
        ExpandableText(description, style: TextStyle(fontFamily: Styles().fontFamilies.regular, fontSize: 16, color: Styles().colors.textBackground, ), trimLines: 4, iconColor: Styles().colors.fillColorPrimary,),
      ],),);
  }

  Widget _buildAdmins() {
    List<Widget> content = [];
    if (0 < (_groupAdmins?.length ?? 0)) {
      content.add(Padding(padding: EdgeInsets.only(left: 16), child: Container()),);
      for (Member officer in _groupAdmins) {
        if (1 < content.length) {
          content.add(Padding(padding: EdgeInsets.only(left: 8), child: Container()),);
        }
        content.add(_OfficerCard(groupMember: officer,));
      }
      content.add(Padding(padding: EdgeInsets.only(left: 16), child: Container()),);
    }
    return
      Stack(children: [
        Container(
            height: 112,
            color: Styles().colors.backgroundVariant,
            child:
            Column(children: [
              Container(height: 80,),
              Container(
                  height: 32,
                  child: CustomPaint(
                    painter: TrianglePainter(painterColor: Styles().colors.background),
                    child: Container(),
                  )
              ),
            ],)
        ),
        Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(padding: EdgeInsets.only(left: 16, right: 16, bottom: 16), child:
            Text( Localization().getStringEx("panel.group_detail.label.admins",  'Admins'), style: TextStyle(fontFamily: Styles().fontFamilies.extraBold, fontSize: 20, color: Styles().colors.fillColorPrimary, ),),
          ),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child:
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: content),
          ),
        ],),)
      ],);
  }

  Widget _buildMembershipRequest() {
    return
      Auth().isShibbolethLoggedIn && _group.currentUserCanJoin
          ? Container(color: Colors.white,
              child: Padding(padding: EdgeInsets.all(16),
                  child: ScalableRoundedButton(label: Localization().getStringEx("panel.group_detail.button.request_to_join.title",  'Request to join'),
                    backgroundColor: Styles().colors.white,
                    textColor: Styles().colors.fillColorPrimary,
                    fontFamily: Styles().fontFamilies.bold,
                    fontSize: 16,
                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    borderColor: Styles().colors.fillColorSecondary,
                    borderWidth: 2,
                    onTap:() { _onMembershipRequest();  }
                  ),
              ),
            )
          : Container();
  }

  Widget _buildCancelMembershipRequest() {
    return
      Auth().isShibbolethLoggedIn && _group.currentUserIsPendingMember
          ? Stack(
            alignment: Alignment.center,
            children: [
              Container(color: Colors.white,
                  child: Padding(padding: EdgeInsets.all(16),
                    child: ScalableRoundedButton(label: Localization().getStringEx("panel.group_detail.button.cancel_request.title",  'Cancel Request'),
                        backgroundColor: Styles().colors.white,
                        textColor: Styles().colors.fillColorPrimary,
                        fontFamily: Styles().fontFamilies.bold,
                        fontSize: 16,
                        padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        borderColor: Styles().colors.fillColorSecondary,
                        borderWidth: 2,
                        onTap:() { _onCancelMembershipRequest();  }
                    ),
                  )),
              _cancelling ? CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Styles().colors.fillColorSecondary), ) : Container(),
            ],
          )
          : Container();
  }

  Widget _buildCancelRequestDialog(BuildContext context) {
    return Dialog(
      backgroundColor: Styles().colors.fillColorPrimary,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.symmetric(vertical: 26),
              child: Text(
                Localization().getStringEx("panel.group_detail.label.confirm.cancel",  "Are you sure you want to cancel your request to join this group?"),
                textAlign: TextAlign.left,
                style: TextStyle(fontFamily: Styles().fontFamilies.medium, fontSize: 16, color: Styles().colors.white),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                RoundedButton(
                  label: Localization().getStringEx("panel.group_detail.button.back.title",   "Back"),
                  fontFamily: "ProximaNovaRegular",
                  textColor: Styles().colors.fillColorPrimary,
                  borderColor: Styles().colors.white,
                  backgroundColor: Styles().colors.white,
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  onTap: ()=>Navigator.pop(context),
                ),
                Container(width: 16,),
                RoundedButton(
                  label:  Localization().getStringEx("panel.group_detail.button.dialog.cancel_request.title",   "Cancel request"),
                  fontFamily: "ProximaNovaBold",
                  textColor: Styles().colors.fillColorPrimary,
                  borderColor: Styles().colors.white,
                  backgroundColor: Styles().colors.white,
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  onTap: (){
                    _cancelMembershipRequest();
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaveGroupDialog(BuildContext context) {
    return Dialog(
      backgroundColor: Styles().colors.fillColorPrimary,
      child: StatefulBuilder(
          builder: (context, setStateEx){
            return Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 26),
                    child: Text(
                      Localization().getStringEx("panel.group_detail.label.confirm.leave", "Are you sure you want to leave this group?"),
                      textAlign: TextAlign.left,
                      style: TextStyle(fontFamily: Styles().fontFamilies.medium, fontSize: 16, color: Styles().colors.white),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      RoundedButton(
                        label: Localization().getStringEx("panel.group_detail.button.back.title", "Back"),
                        fontFamily: "ProximaNovaRegular",
                        textColor: Styles().colors.fillColorPrimary,
                        borderColor: Styles().colors.white,
                        backgroundColor: Styles().colors.white,
                        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        onTap: ()=>Navigator.pop(context),
                      ),
                      Container(width: 16,),
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          RoundedButton(
                            label:Localization().getStringEx("panel.group_detail.button.leave.title", "Leave"),
                            fontFamily: "ProximaNovaBold",
                            textColor: Styles().colors.fillColorPrimary,
                            borderColor: Styles().colors.white,
                            backgroundColor: Styles().colors.white,
                            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                            onTap: (){
                              _leaveGroup(setStateEx).then((value) => Navigator.pop(context));
                            },
                          ),
                          _leaving ? CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Styles().colors.fillColorSecondary), ) : Container(),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
    );
  }

  void _onGroupOptionsTap(){
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        isScrollControlled: true,
        isDismissible: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context){
          return Container(
            padding: EdgeInsets.symmetric(horizontal: 16,vertical: 17),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(height: 48,),
                RibbonButton(
                  height: null,
                  leftIcon: "images/icon-leave-group.png",
                  label: Localization().getStringEx("panel.group_detail.button.leave_group.title", "Leave group"),
                  onTap: (){
                    showDialog(context: context, builder: (context)=>_buildLeaveGroupDialog(context)).then((value) => Navigator.pop(context));
                  },
                ),
              ],
            ),
          );
        }
    );
  }

  void _onTab(_DetailTab tab) {
    setState(() {
      _currentTab = tab;
    });
  }

  void _onWebsite() {
    String url = _group?.webURL;
    if (url != null) {
      launch(url);
    }
  }

  void onTapMembers(){
    Analytics().logPage(name: "Group Members");
    Navigator.push(context, CupertinoPageRoute(builder: (context) => GroupMembersPanel(groupId: _group.id)));
  }

  void onTapSettings(){
    Analytics().logPage(name: "Group Settings");
    Navigator.push(context, CupertinoPageRoute(builder: (context) => GroupSettingsPanel(group: _group,)));
  }

  void _onMembershipRequest() {
    Navigator.push(context, CupertinoPageRoute(builder: (context) => GroupMembershipRequestPanel(group: _group)));
  }

  void _onCancelMembershipRequest(){
    showDialog(context: context, builder: (context) => _buildCancelRequestDialog(context));
  }
}

class _OfficerCard extends StatelessWidget {
  final Member groupMember;
  
  _OfficerCard({this.groupMember});

  @override
  Widget build(BuildContext context) {

    return Container(
      width: 128,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Container(height: 144, width: 128,
          decoration: BoxDecoration(
            image: DecorationImage(image: AppString.isStringNotEmpty(groupMember?.photoURL) ? NetworkImage(groupMember?.photoURL) : AssetImage('images/missing-photo-placeholder.png'), fit: BoxFit.contain),
              borderRadius: BorderRadius.all(Radius.circular(4))),
          ),
        Padding(padding: EdgeInsets.only(top: 4),
          child: Text(groupMember?.name ?? "", style: TextStyle(fontFamily: Styles().fontFamilies.bold, fontSize: 16, color: Styles().colors.fillColorPrimary),),),
        Text(groupMember?.officerTitle ?? "", style: TextStyle(fontFamily: Styles().fontFamilies.regular, fontSize: 16, color: Styles().colors.textBackground),),
      ],),
    );
  }
}