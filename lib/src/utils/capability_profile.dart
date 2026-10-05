/*
 * esc_pos_utils
 * Created by Andrey U.
 * 
 * Copyright (c) 2019-2020. All rights reserved.
 * See LICENSE for distribution and usage details.
 */

import 'dart:convert' show json;

import 'package:resource_portable/resource.dart';

class CodePage {
  CodePage(this.id, this.name);

  int id;
  String name;
}

class CapabilityProfile {
  String name;
  List<CodePage> codePages;

  CapabilityProfile._internal(this.name, this.codePages);

  static Future<Map>? _capabilities;

  /// The `capabilities.json` (loaded and parsed once).
  static Future<Map> _loadCapabilities() => _capabilities ??=
          Resource('package:esc_pos_dart/resources/capabilities.json')
              .readAsString()
              .then((content) => json.decode(content) as Map)
              .catchError((Object e) {
        // Allow a new attempt:
        _capabilities = null;
        throw e;
      });

  /// Public factory
  static Future<CapabilityProfile> load({String name = 'default'}) async {
    Map capabilities = await _loadCapabilities();

    var profile = capabilities['profiles'][name];

    if (profile == null) {
      throw Exception("The CapabilityProfile '$name' does not exist");
    }

    List<CodePage> list = [];
    profile['codePages'].forEach((k, v) {
      list.add(CodePage(int.parse(k), v));
    });

    // Call the private constructor
    return CapabilityProfile._internal(name, list);
  }

  /// Returns the `ESC t` ID of the [codePage] name (case-insensitive).
  int getCodePageId(String? codePage) {
    var name = codePage?.trim().toUpperCase();
    return codePages
        .firstWhere((cp) => cp.name.toUpperCase() == name,
            orElse: () => throw Exception(
                "Code Page '$codePage' isn't defined for this profile"))
        .id;
  }

  /// Returns the code page name of the `ESC t` [id], or `null` if not defined.
  String? getCodePageName(int id) {
    for (var cp in codePages) {
      if (cp.id == id) {
        return cp.name == 'Unknown' ? null : cp.name;
      }
    }
    return null;
  }

  static Future<List<dynamic>> getAvailableProfiles() async {
    Map capabilities = await _loadCapabilities();

    var profiles = capabilities['profiles'];

    List<dynamic> res = [];

    profiles.forEach((k, v) {
      res.add({
        'key': k,
        'vendor': v['vendor'] is String ? v['vendor'] : '',
        'model': v['model'] is String ? v['model'] : '',
        'description': v['description'] is String ? v['description'] : '',
      });
    });

    return res;
  }
}
