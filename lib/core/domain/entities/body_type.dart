/// The kind of payload a request carries. Persisted as a wire string on the
/// config model (Hive field 11, default `'raw'`) so legacy records — which have
/// a plain `body` string and no body-type — read back as [BodyType.raw].
enum BodyType {
  none('none'),
  raw('raw'),
  urlencoded('urlencoded'),
  multipart('multipart'),
  binary('binary')
  ;

  const BodyType(this.wire);

  final String wire;

  static BodyType fromWire(String? value) {
    for (final t in BodyType.values) {
      if (t.wire == value) return t;
    }
    return BodyType.raw;
  }
}
