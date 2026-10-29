// Shared eligibility guard for locally learned JSON property names.
// Names are persisted as primitive Hive keys, whose UTF-8 length is one byte;
// rejecting longer names here avoids storage corruption for Unicode names.
import 'dart:convert';

bool isLearnableBodyFieldName(String name) =>
    name.isNotEmpty && name.length <= 255 && utf8.encode(name).length <= 255;
