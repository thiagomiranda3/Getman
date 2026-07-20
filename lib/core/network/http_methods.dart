// HttpMethods.all: the single source of the supported HTTP method list
// (GET/POST/PUT/DELETE/PATCH).
//
// Gotcha: this is the one place the method list is spelled out — never
// hardcode ['GET','POST',...] at a call site (method dropdown, code-gen
// targets, etc.); read HttpMethods.all instead so adding a method is a
// one-line change.

class HttpMethods {
  HttpMethods._();

  static const List<String> all = ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'];
}
