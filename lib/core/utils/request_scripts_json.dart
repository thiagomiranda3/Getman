// Portable primitive script bundle shared by workspace and Postman extensions.
// Only source, version and enablement cross the sharing boundary; trust and
// execution diagnostics are local and never read from imported JSON.
import 'package:getman/core/domain/entities/request_scripts.dart';

class RequestScriptsJson {
  RequestScriptsJson._();
  static Map<String, dynamic> toJson(RequestScripts scripts) => {
    'apiVersion': scripts.apiVersion,
    'preRequest': scripts.preRequest,
    'postResponse': scripts.postResponse,
    'preRequestEnabled': scripts.preRequestEnabled,
    'postResponseEnabled': scripts.postResponseEnabled,
  };
  static RequestScripts fromJson(Object? raw) {
    if (raw is! Map) return const RequestScripts();
    return RequestScripts(
      apiVersion: raw['apiVersion'] is int ? raw['apiVersion'] as int : 1,
      preRequest: raw['preRequest'] is String
          ? raw['preRequest'] as String
          : '',
      postResponse: raw['postResponse'] is String
          ? raw['postResponse'] as String
          : '',
      preRequestEnabled: raw['preRequestEnabled'] != false,
      postResponseEnabled: raw['postResponseEnabled'] != false,
    );
  }
}
