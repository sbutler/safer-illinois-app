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

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:http/http.dart' as Http;
import 'package:illinois/model/Auth.dart';
import 'package:illinois/service/Auth.dart';
import 'package:illinois/service/Connectivity.dart';
import 'package:illinois/service/Analytics.dart';
import 'package:illinois/service/Config.dart';
import 'package:illinois/service/Health.dart';
import 'package:illinois/service/Log.dart';
import 'package:illinois/utils/Utils.dart';

import 'FirebaseCrashlytics.dart';

/*enum NetworkAuth {
  App,
  AuthUser,
  RokmetroUser,
  HealthUserAccount
}*/

class Network  {

  // Headers
  static const String RokwireApiKey = 'ROKWIRE-API-KEY';
  static const String RokwireHSApiKey = 'ROKWIRE-HS-API-KEY';
  static const String RokwireAccountId = 'ROKWIRE-ACC-ID';
  static const String RokwireAppId = 'APP';
  static const String RokwireAppVersion = 'V';

  // Auth
  static const int AppAuth            = 1;
  static const int ShibbolethUserAuth = 2;
//static const int RokmetroUserAuth   = 4; // Disable Rokmetro auth
  static const int RokmetroUserAuth   = ShibbolethUserAuth;
  static const int HealthAccountAuth  = 8;

  static const int HealthUserAuth     = RokmetroUserAuth | HealthAccountAuth;

  static final Network _network = new Network._internal();
  factory Network() {
    return _network;
  }

  Network._internal();

  Future<Http.Response> _get2(dynamic url, { String body, Encoding encoding, Map<String, String> headers, int timeout, Http.Client client }) async {
    try {

      Uri uri = _uriFromUrlString(url);

      if (uri != null) {
        
        Http.Client localClient;
        if (client == null) {
          client = localClient = Http.Client();
        }

        Http.Request request = Http.Request("GET", uri);
        
        if (headers != null) {
          headers.forEach((String key, String value) {
            request.headers[key] = value;
          });
        }
        
        if (encoding != null) {
          request.encoding = encoding;  
        }
        
        if (body != null) {
          request.body = body;
        }

        Future<Http.StreamedResponse> responseStreamFuture = client.send(request);
        if ((responseStreamFuture != null) && (timeout != null)) {
          responseStreamFuture = responseStreamFuture.timeout(Duration(seconds: timeout));
        }

        Http.StreamedResponse responseStream = await responseStreamFuture;

        if (localClient != null) {
          localClient.close();
        }

        return (responseStream != null) ? Http.Response.fromStream(responseStream) : null;
      }
    } catch (e) { 
      Log.d(e?.toString());
      FirebaseCrashlytics().recordError(e, null);
    }
    return null;
  }

  Future<Http.Response> _get(url, { String body, Encoding encoding, Map<String, String> headers, int auth, int timeout, Http.Client client} ) async {
    if (Connectivity().isNotOffline) {
      try {
        Uri uri = _uriFromUrlString(url);

        if (uri != null) {

          Map<String, String> requestHeaders = await _prepareHeaders(headers, auth, uri);
          
          Future<Http.Response> response;
          if (body != null) {
            response = _get2(uri, headers: requestHeaders, body: body, encoding: encoding, timeout: timeout, client: client);
          }
          else if (client != null) {
            response = client.get(uri, headers: requestHeaders);
          }
          else {
            response = Http.get(uri, headers: requestHeaders);
          }
          
          if ((response != null) && (timeout != null)) {
            response = response.timeout(Duration(seconds: timeout), onTimeout: _responseTimeoutHandler);
          }

          return response;
        }
      } catch (e) { 
        Log.d(e?.toString());
        FirebaseCrashlytics().recordError(e, null);
      }
    }
    return null;
  }

  Future<Http.Response> get(url, { String body, Encoding encoding, Map<String, String> headers, int auth, Http.Client client, int timeout = 60, bool sendAnalytics = true, String analyticsUrl, bool analyticsAnonymous }) async {
    Http.Response response;
    try {
      response = await _get(url, headers: headers, body: body, encoding: encoding, auth: auth, client: client, timeout: timeout);

      if (_requiresTokenRefresh(response, auth)) {
        if (await _refreshToken(auth) != null) {
          response = await _get(url, headers: headers, body: body, encoding: encoding, auth: auth, client: client, timeout: timeout);
        }
      }
    } catch (e) {
      Log.d(e?.toString());
      FirebaseCrashlytics().recordError(e, null);
    }

    if (sendAnalytics) {
      Analytics().logHttpResponse(response, requestMethod:'GET', requestUrl: analyticsUrl ?? url, anonymous: analyticsAnonymous);
    }

    _saveCookiesFromResponse(url, response);

    return response;
  }

  Future<Http.Response> _post(url, { body, Encoding encoding, Map<String, String> headers, int auth, int timeout}) async{
    if (Connectivity().isNotOffline) {
      try {
        Uri uri = _uriFromUrlString(url);
        Future<Http.Response> response = (uri != null) ? Http.post(uri, headers: await _prepareHeaders(headers, auth, uri), body: body, encoding: encoding) : null;
        return ((response != null) && (timeout != null)) ? response.timeout(Duration(seconds: timeout), onTimeout: _responseTimeoutHandler) : response;
      } catch (e) {
        Log.d(e?.toString());
        FirebaseCrashlytics().recordError(e, null);
      }
    }
    return null;
  }

  Future<Http.Response> post(url, { body, Encoding encoding, Map<String, String> headers, int auth, int timeout = 60, bool sendAnalytics = true, String analyticsUrl, bool analyticsAnonymous }) async{
    Http.Response response;
    try {
      response = await _post(url, body: body, encoding: encoding, headers: headers, auth: auth, timeout: timeout);

      if (_requiresTokenRefresh(response, auth)) {
        if (await _refreshToken(auth) != null) {
          response = await _post(url, body: body, encoding: encoding, headers: headers, auth: auth, timeout: timeout);
        }
      }
    } catch (e) {
      Log.d(e?.toString());
      FirebaseCrashlytics().recordError(e, null);
    }


    if (sendAnalytics) {
      Analytics().logHttpResponse(response, requestMethod:'POST', requestUrl: analyticsUrl ?? url, anonymous: analyticsAnonymous);
    }

    _saveCookiesFromResponse(url, response);

    return response;
  }

  Future<Http.Response> _put(url, { body, Encoding encoding, Map<String, String> headers, int auth, int timeout, Http.Client client }) async {
    if (Connectivity().isNotOffline) {
      try {
        Uri uri = _uriFromUrlString(url);
        Future<Http.Response> response = (uri != null) ?
          ((client != null) ?
            client.put(uri, headers: await _prepareHeaders(headers, auth, uri), body: body, encoding: encoding) :
              Http.put(uri, headers: await _prepareHeaders(headers, auth, uri), body: body, encoding: encoding)) :
            null;

        return ((response != null) && (timeout != null)) ? response.timeout(Duration(seconds: timeout), onTimeout: _responseTimeoutHandler) : response;

      } catch (e) {
        Log.d(e?.toString());
        FirebaseCrashlytics().recordError(e, null);
      }
    }
    return null;
  }

  Future<Http.Response> put(url, { body, Encoding encoding, Map<String, String> headers, int auth, int timeout = 60, Http.Client client, bool sendAnalytics = true, String analyticsUrl, bool analyticsAnonymous }) async {
    Http.Response response;
    try {
      response = await _put(url, body: body, encoding: encoding, headers: headers, auth: auth, timeout: timeout, client: client);

      if (_requiresTokenRefresh(response, auth)) {
        if (await _refreshToken(auth) != null) {
          response = await _put(url, body: body, encoding: encoding, headers: headers, auth: auth, timeout: timeout, client: client);
        }
      }
    } catch (e) {
      Log.d(e?.toString());
      FirebaseCrashlytics().recordError(e, null);
    }

    if (sendAnalytics) {
      Analytics().logHttpResponse(response, requestMethod:'PUT', requestUrl: analyticsUrl ?? url, anonymous: analyticsAnonymous);
    }

    _saveCookiesFromResponse(url, response);

    return response;
  }

  Future<Http.Response> _patch(url, { body, Encoding encoding, Map<String, String> headers, int auth, int timeout }) async {
    if (Connectivity().isNotOffline) {
      try {
        Uri uri = _uriFromUrlString(url);
        Future<Http.Response> response = (uri != null) ? Http.patch(uri, headers: await _prepareHeaders(headers, auth, uri), body: body, encoding: encoding) : null;
        return ((response != null) && (timeout != null)) ? response.timeout(Duration(seconds: timeout), onTimeout: _responseTimeoutHandler) : response;
      } catch (e) {
        Log.d(e?.toString());
        FirebaseCrashlytics().recordError(e, null);
      }
    }
    return null;
  }

  Future<Http.Response> patch(url, { body, Encoding encoding, Map<String, String> headers, int auth, int timeout = 60, bool sendAnalytics = true, String analyticsUrl, bool analyticsAnonymous }) async {
    Http.Response response;
    try {
      response = await _patch(url, body: body, encoding: encoding, headers: headers, auth: auth, timeout: timeout);

      if (_requiresTokenRefresh(response, auth)) {
        if (await _refreshToken(auth) != null) {
          response = await _patch(url, body: body, encoding: encoding, headers: headers, auth: auth, timeout: timeout);
        }
      }
    } catch (e) {
      Log.d(e?.toString());
      FirebaseCrashlytics().recordError(e, null);
    }

    if (sendAnalytics) {
      Analytics().logHttpResponse(response, requestMethod:'PATCH', requestUrl: analyticsUrl ?? url, anonymous: analyticsAnonymous);
    }

    _saveCookiesFromResponse(url, response);

    return response;
  }

  Future<Http.Response> _delete(url, { Map<String, String> headers, int auth, int timeout }) async {
    if (Connectivity().isNotOffline) {
      try {
        Uri uri = _uriFromUrlString(url);
        Future<Http.Response> response = (uri != null) ? Http.delete(uri, headers: await _prepareHeaders(headers, auth, uri)) : null;
        return ((response != null) && (timeout != null)) ? response.timeout(Duration(seconds: timeout), onTimeout: _responseTimeoutHandler) : response;
      } catch (e) {
        Log.d(e?.toString());
        FirebaseCrashlytics().recordError(e, null);
      }
    }
    return null;
  }

  Future<Http.Response> delete(url, { Map<String, String> headers, int auth, int timeout = 60, bool sendAnalytics = true, String analyticsUrl, bool analyticsAnonymous }) async {
    Http.Response response;
    try {
      response = await _delete(url, headers: headers, auth: auth, timeout: timeout);

      if (_requiresTokenRefresh(response, auth)) {
        if (await _refreshToken(auth) != null) {
          response = await _delete(url, headers: headers, auth: auth, timeout: timeout);
        }
      }
    } catch (e) {
      Log.d(e?.toString());
      FirebaseCrashlytics().recordError(e, null);
    }

    if (sendAnalytics) {
      Analytics().logHttpResponse(response, requestMethod:'DELETE', requestUrl: analyticsUrl ?? url, anonymous: analyticsAnonymous);
    }

    _saveCookiesFromResponse(url, response);

    return response;
  }

  Future<String> _read(url, { Map<String, String> headers, int auth, int timeout = 60 }) async {
    if (Connectivity().isNotOffline) {
      try {
        Uri uri = _uriFromUrlString(url);
        Future<String> response = (uri != null) ? Http.read(uri, headers: await _prepareHeaders(headers, auth, uri)) : null;
        return ((response != null) && (timeout != null)) ? response.timeout(Duration(seconds: timeout)) : response;
      } catch (e) {
        Log.d(e?.toString());
        FirebaseCrashlytics().recordError(e, null);
      }
    }
    return null;
  }

  Future<String> read(url, { Map<String, String> headers, int auth, int timeout = 60 }) async {
    try {
      return await _read(url, headers: headers, auth: auth, timeout: timeout);
    } catch (e) {
      Log.d(e?.toString());
      FirebaseCrashlytics().recordError(e, null);
    }
    return null;
  }

  Future<Uint8List> _readBytes(url, { Map<String, String> headers, int auth, int timeout = 60 }) async{
    if (Connectivity().isNotOffline) {
      try {
        Uri uri = _uriFromUrlString(url);
        Future<Uint8List> response = (uri != null) ? Http.readBytes(uri, headers: await _prepareHeaders(headers, auth, uri)) : null;
        return ((response != null) && (timeout != null)) ? response.timeout(Duration(seconds: timeout), onTimeout: _responseBytesHandler) : response;
      } catch (e) {
        Log.d(e?.toString());
        FirebaseCrashlytics().recordError(e, null);
      }
    }
    return null;
  }

  Future<Uint8List> readBytes(url, { Map<String, String> headers, int auth, int timeout = 60 }) async {
    try {
      return _readBytes(url, headers: headers, auth: auth, timeout: timeout);
    } catch (e) {
      Log.d(e?.toString());
      FirebaseCrashlytics().recordError(e, null);
    }
    return null;    
  }

  Future<Map<String, String>> _prepareHeaders(Map<String, String> headers, int auth, Uri uri) async {

    Map<String, String> result;

    if (auth != null) {
      if ((auth & AppAuth) != 0) {
        String rokwireApiKey = Config().rokwireApiKey;
        if ((rokwireApiKey != null) && rokwireApiKey.isNotEmpty) {
          if (result == null) {
            result = (headers != null) ? Map.from(headers) : Map();
          }
          result[RokwireApiKey] = rokwireApiKey;
        }
      }
      
      if ((auth & ShibbolethUserAuth) != 0) {
        String authorizationHeader = Auth().authToken?.authIdTokenHeader;
        if ((authorizationHeader != null) && authorizationHeader.isNotEmpty) {
          if (result == null) {
            result = (headers != null) ? Map.from(headers) : Map();
          }
          result[HttpHeaders.authorizationHeader] = authorizationHeader;
        }
      }
      // Disable Rokmetro auth
      /*else if ((auth & RokmetroUserAuth) != 0) {
        String authorizationHeader = Auth().rokmetroToken?.authIdTokenHeader;
        if ((authorizationHeader != null) && authorizationHeader.isNotEmpty) {
          if (result == null) {
            result = (headers != null) ? Map.from(headers) : Map();
          }
          result[HttpHeaders.authorizationHeader] = authorizationHeader;
        }
      }*/

      if ((auth & HealthAccountAuth) != 0) {
        String rokwireAccountId = Health().userAccountId;
        if ((rokwireAccountId != null) && rokwireAccountId.isNotEmpty) {
          if (result == null) {
            result = (headers != null) ? Map.from(headers) : Map();
          }
          result[RokwireAccountId] = rokwireAccountId;
        }
      }
    }
    

    //cookies
    if (uri != null) {
      String cookies = await _loadCookiesForRequest(uri);
      if (AppString.isStringNotEmpty(cookies)) {
        if (result == null) {
          result = (headers != null) ? Map.from(headers) : Map();
        }
        result["Cookie"] = cookies;
      }
    }

    return (result != null) ? result : headers;
  }

  bool _requiresTokenRefresh(Http.Response response, int auth) {
    return (response?.statusCode == 401) && (auth != null) && ((auth & (ShibbolethUserAuth | RokmetroUserAuth)) != 0) && (Auth().authToken != null);
  }

  Future<AuthToken> _refreshToken(int auth) async {
    if (auth != null) {
      if ((auth & ShibbolethUserAuth) != 0) {
        return await Auth().refreshAuthToken();
      }
      // Disable Rokmetro auth
      /*else if ((auth & RokmetroUserAuth) != 0) {
        return await Auth().refreshRokmetroToken();
      }*/
    }
    return null;
  }


  void _saveCookiesFromResponse(String url, Http.Response response) {
    Uri uri = _uriFromUrlString(url);
    if ((uri == null) || response == null)
      return;

    Map<String, String> responseHeaders = response.headers;
    if (responseHeaders == null)
      return;

    String setCookie = responseHeaders["set-cookie"];
    if (AppString.isStringEmpty(setCookie))
      return;

    //Split format like this "AWSALB2=12342; Path=/; Expires=Mon, 21 Oct 2019 12:48:37 GMT,AWSALB=1234; Path=/; Expires=Mon, 21 Oct 2019 12:48:37 GMT"
    List<String> cookiesData = setCookie.split(new RegExp(",(?! )")); //comma not followed by a space
    if (cookiesData == null || cookiesData.length == 0)
      return;

    List<Cookie> cookies = <Cookie>[];
    for (String cookieData in cookiesData) {
      Cookie cookie = Cookie.fromSetCookieValue(cookieData);
      cookies.add(cookie);
    }

    var cj = new CookieJar();
    cj.saveFromResponse(uri, cookies);
  }

  Future<String> _loadCookiesForRequest(Uri uri) async{
    if(uri != null) {
      var cj = new CookieJar();
      List<Cookie> cookies = await cj.loadForRequest(uri);
      if (cookies == null || cookies.length == 0)
        return null;

      String result = "";
      for (Cookie cookie in cookies) {
        result += cookie.name + "=" + cookie.value + "; ";
      }

      //remove the last "; "
      result = result.substring(0, result.length - 2);

      return result;
    }
    return null;
  }

  Http.Response _responseTimeoutHandler() {
    return null;
  }

  Uint8List _responseBytesHandler() {
    return null;
  }

  Uri _uriFromUrlString(dynamic url){
    Uri uri;
    if (url is Uri) {
      uri = url;
    }
    else if (url is String) {
      uri = Uri.tryParse(url);
    }
    else if (url != null) {
      uri = Uri.tryParse(url.toString());
    }
    return uri;
  }
}

