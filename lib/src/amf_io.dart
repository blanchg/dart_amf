library amf_io;

@MirrorsUsed(targets: 'remote_classes', symbols: '*')
import 'dart:mirrors';
import 'dart:math';
import 'dart:typed_data';

import 'metadata.dart';
import 'remote_classes.dart';

class AmfIO {
  static const String EMPTY_STRING = "";
  static const String NULL_STRING = "null";
  static const int AMF0_AMF3 = 17;
  static const int UINT29_MASK = 536870911;
  static const int INT28_MAX_VALUE = 268435455;
  static const int INT28_MIN_VALUE = -268435455;
  static const String CLASS_ALIAS = "_explicitType";
  static const String EXTERNALIZABLE = "_isExternalizable";
  static const UNDEFINED_TYPE = 0;
  static const NULL_TYPE = 1;
  static const FALSE_TYPE = 2;
  static const TRUE_TYPE = 3;
  static const INTEGER_TYPE = 4;
  static const DOUBLE_TYPE = 5;
  static const STRING_TYPE = 6;
  static const XML_TYPE = 7;
  static const DATE_TYPE = 8;
  static const ARRAY_TYPE = 9;
  static const OBJECT_TYPE = 10;
  static const XMLSTRING_TYPE = 11;
  static const BYTEARRAY_TYPE = 12;

  static Map<String, Type> classRegistry = new Map();
  static Map<Type, String> typeRegistry = new Map();

  static void registerClass(String name, Type clazz) {
//    print("$name = $clazz");
    classRegistry[name] = clazz;
    typeRegistry[clazz] = name;
  }

  static void discoverRemoteObjects() {
//    print("Discover");
    currentMirrorSystem().libraries.forEach((uri, lib) {
      lib.declarations.forEach((sym, declaration) {
        if (declaration is ClassMirror) {
          declaration.metadata
          .where((metadata) => metadata.reflectee is RemoteObject)
          .forEach((metadata) {
//              print("    sym: $uri.$sym");
            RemoteObject ro = metadata.reflectee;
            ClassMirror cm = declaration as ClassMirror;
            if (cm.hasReflectedType) {
              AmfIO.registerClass(ro.alias, cm.reflectedType);
            } else {
              print("AMF Can't support generics please type it to Object or more specific");
            }
          });
        }
      });
    });
  }
}

class Writer {
  List<int> data = new List();
  List<Object> objects = [];
  Map<String, int> traits = new Map();
  Map<String, int> strings = new Map();
  int stringCount = 0;
  int traitCount = 0;
  int objectCount = 0;

  void write(int v) {
    data.add(v);
  }

  void writeShort(int v) {
    write(((v & 0xFF00)>>8) & 0xFF);
    write(v & 0xFF);
  }

  int writeUTF(String v, [bool asAmf = false]) {
    List<int> bytearr = new List();
    int c;
    int i;
    int strlen = v.length;;
    int utflen = 0;
    for (i = 0; i < strlen; i++) {
      c = v.codeUnitAt(i);
      if (c > 0 && c < 128) {
        utflen++;
      } else if (c > 2047) {
        utflen += 3;
      } else {
        utflen += 2;
      }
    }
    if (asAmf) {
      writeUInt29((utflen << 1) | 1);
    } else {
      bytearr.add(((utflen & 0xFF00) >> 8) & 0xFF);
      bytearr.add(utflen & 0xFF);
    }
    for(i = 0; i < strlen; i++) {
      c = v.codeUnitAt(i);
      if (c > 0 && c < 128) {
        bytearr.add(c);
      } else if (c > 2047) {
        bytearr.add(224 | (c >> 12));
        bytearr.add(128 | ((c >> 6) & 64));
        if (asAmf) {
          bytearr.add(128 | ((c >> 0) & 63));
        } else {
          bytearr.add(128 | (c & 63));
        }
      } else {
        bytearr.add(192 | (c >> 6));
        if (asAmf) {
          bytearr.add(128 | ((c >> 0) & 63));
        } else {
          bytearr.add(128 | (c & 63));
        }
      }
    }
    writeAll(bytearr);
    return asAmf ? utflen : utflen + 2;
  }

  void writeUInt29(int v) {
    if (v < 128) {
      write(v);
    } else if (v < 16384) {
      write(((v >> 7) & 127) | 128);
      write(v & 127);
    } else if (v < 2097152) {
      write(((v >> 14) & 127) | 128);
      write(((v >> 7) & 127) | 128);
      write(v & 127);
    } else if (v < 0x40000000) {
      write(((v >> 22) & 127) | 128);
      write(((v >> 15) & 127) | 128);
      write(((v >> 8) & 127) | 128);
      write(v & 255);
    } else {
      throw "Integer out of range: $v";
    }
  }

  void writeAll(List<int> bytes) {
    for (int i = 0; i < bytes.length; i++) {
      write(bytes[i]);
    }
  }

  void writeBoolean(bool v) {
    write(v?1:0);
  }

  void writeInt(int v) {
    write(((v & 0xFF000000) >> 24) & 255);
    write(((v & 0xFF0000) >> 16) & 255);
    write(((v & 0xFF00) >> 8) & 255);
    write(((v & 0xFF) >> 0) & 255);
  }

  void writeUnsignedInt(int v) {
    v < 0 && (v == -(v ^ 4294967295) - 1);
    v &= 4294967295;
    write((v >> 24) & 255);
    write((v >> 16) & 255);
    write((v >> 8) & 255);
    write(v & 255);
  }
  //origin unknown
  List<int> _getDouble(double v) {
    List<int> r = [0,0];
    int d = 0;
    int e = 0;
    if (v.isNaN) {
      r[0] = -524288;
      return r;
    }
    if (v < 0 || v == 0 && 1 / v < 0) {
      d = -2147483648;
    } else {
      d = 0;
      v = v.abs();
    }
    if (v == double.INFINITY) {
      r[0] = d | 2146435072;
      return r;
    }
    for (e = 0; v >= 2 && e <= 1023;) {
      e++;
      v /= 2;
    }
    for (; v < 1 && e >= -1022;) {
      e--;
      v *= 2;
    }
    e += 1023;
    if (e == 2047) {
      r[0] = d | 2146435072;
      return r;
    }
    double i;
    if (e == 0) {
      i = v * pow(2, 23) / 2;
      r[1] = (v * pow(2, 52) / 2).round();
    } else {
      i = v * pow(2, 20) - pow(2, 20);
      r[1] = (v * pow(2, 52) - pow(2, 52)).round();
    }
    r[0] = d | e << 20 & 2147418112 | i.floor() & 1048575;
    return r;
  }

  void writeDouble(double v) {
    List<int> parts = this._getDouble(v);
    writeUnsignedInt(parts[0]);
    writeUnsignedInt(parts[1]);
  }

  String getResult() {
    return data.join("");
  }

  void reset() {
    objects = [];
    objectCount = 0;
    traits = {};
    traitCount = 0;
    strings = {};
    stringCount = 0;
  }

  void writeStringWithoutType(String v) {
    if (v.length == 0) {
      writeUInt29(1);
    } else {
      if (stringByReference(v) == null) {
        writeUTF(v, true);
      }
    }
  }

  int stringByReference(String v) {
    int ref = strings[v];
    if (ref != null) {
      this.writeUInt29(ref << 1);
    } else {
      this.strings[v] = stringCount++;
    }
    return ref;
  }

  int objectByReference(Object v) {
    int ref = 0;
    bool found = false;
    for (; ref < objects.length; ref++) {
      if (objects[ref] == v) {
        found = true;
        break;
      }
    }
    if (found) {
      writeUInt29(ref << 1);
    } else {
      objects.add(v);
      objectCount++;
    }

    return found ? ref : null;
  }

  int traitsByReference(List v, String alias) {
    String s = "$alias|";
    for ( int i = 0; i < v.length; i++) {
      s = "${s}${v[i]}|";
    }
    int ref = this.traits[s];
    if (ref != null) {
      this.writeUInt29((ref << 2) | 1);
    } else {
      this.traits[s] = this.traitCount++;
    }
    return ref;
  }

  void writeAmfInt(int v) {
    if (v >= AmfIO.INT28_MIN_VALUE && v <= AmfIO.INT28_MAX_VALUE) {
      v = v & AmfIO.UINT29_MASK;
      this.write(AmfIO.INTEGER_TYPE);
      this.writeUInt29(v);
    } else {
      this.write(AmfIO.DOUBLE_TYPE);
      this.writeDouble(v.toDouble());
    }
  }

  void writeDate(DateTime v) {
    this.write(AmfIO.DATE_TYPE);
    if (objectByReference(v) != null) {
      writeUInt29(1);
      writeDouble(v.millisecondsSinceEpoch.toDouble());
    }
  }

  void writeObject(Object v) {
    if (v == null) {
      this.write(AmfIO.NULL_TYPE);
      return;
    }
    if (v is String) {
      this.write(AmfIO.STRING_TYPE);
      this.writeStringWithoutType(v);
    } else if (v is num) {
      if (v == v.abs()) {
        this.writeAmfInt((v).toInt());
      } else {
        this.write(AmfIO.DOUBLE_TYPE);
        this.writeDouble(v);
      }
    } else if (v is bool) {
      this.write((v
      ? AmfIO.TRUE_TYPE
      : AmfIO.FALSE_TYPE));
    } else if (v is DateTime) {
      this.writeDate(v);
    } else {
      if (v is List) {
        this.writeArray(v);
      } else if (AmfIO.typeRegistry.containsKey(v.runtimeType)) {
        this.writeCustomObject(v);
      } else {
        this.writeMap(v as Map);
      }
    }
  }

  void writeStrictArray(Object v) {
    if (v is List) {
      this.write(0);
      this.write(0);
      this.write(0);
      this.write(1);
      this.write(11); // switch to AMF3
      for (int i = 0; i < v.length; i++) {
        this.writeObject(v[i]);
      };
    } else {
      this.writeObject(v);
    }
  }

  void writeCustomObject(Object v) {
    write(AmfIO.OBJECT_TYPE);
    if (objectByReference(v) == null) {
      InstanceMirror vm = reflect(v);
      List<Symbol> traits = writeTraits(v, vm);
      for (int i = 0; i < traits.length; i++) {
        Symbol prop = traits[i];
        this.writeObject(vm.getField(prop).reflectee);
      }
    }
  }

  List<Symbol> writeTraits(Object v, InstanceMirror vm) {
    List<Symbol> traits = [];
    int count = 0;
    bool externalizable = false;
    bool dynamic = false;

    vm.type.instanceMembers.forEach((symbol, prop) {
      if (!prop.isGetter || prop.isPrivate || !prop.isSynthetic)
        return;
      String name = MirrorSystem.getName(symbol);
//      print("  $name = $prop");
      if (name != "explicitType") {
        traits.add(symbol);
        count++;
      }
    });
    String type = AmfIO.typeRegistry[v.runtimeType];
    if (type == null) {
      type = MirrorSystem.getName(reflectType(v.runtimeType).qualifiedName);
//      print("Type (${v.runtimeType}) not registered, assuming it is $type");
      AmfIO.registerClass(type, v.runtimeType);
    } else if (traitsByReference(traits, type) == null) {
      this.writeUInt29(3 | (externalizable ? 4 : 0) | (dynamic ? 8 : 0) | (count << 4));
      this.writeStringWithoutType(type);
      if (count > 0) {
        traits.forEach((prop) {
          String name = MirrorSystem.getName(prop);
          this.writeStringWithoutType(name);
        });
      }
    }
    return traits;
  }

  void writeMap(Map v) {
    this.write(AmfIO.OBJECT_TYPE);
    if (objectByReference(v) == null) {
      this.writeUInt29(11);
      this.traitCount++; //bogus traits entry here
      this.writeStringWithoutType(AmfIO.EMPTY_STRING); //class name
      v.forEach((key, value) {
        if (key != null) {
          this.writeStringWithoutType(key);
        } else {
          this.writeStringWithoutType(AmfIO.EMPTY_STRING);
        }
        this.writeObject(value);
      });
      this.writeStringWithoutType(AmfIO.EMPTY_STRING); //empty string end of dynamic members
    }
  }

  void writeArray(List v) {
    this.write(AmfIO.ARRAY_TYPE);
    if (objectByReference(v) == null) {
      this.writeUInt29((v.length << 1) | 1);
      this.writeUInt29(1); //empty string implying no named keys
      if (v.length > 0) {
        for (int i = 0; i < v.length; i++) {
          this.writeObject(v[i]);
        }
      }
    }
  }
}

class Reader {
  List objects = [];
  List<Map<String, Object>> traits = [];
  List strings = [];
  ByteData data;
  int pos = 0;

  Reader(this.data);

  int read() {
    return data.getUint8(pos++);
  }

  int readUnsignedShort() {
    int c1 = read() & 0xFF;
//    print(" c1: $c1");
    int c2 = read() & 0xFF;
//    print(" c2: $c2");
    return ((c1 << 8) & 0xFF00) + ((c2 << 0) & 0xFF);
  }

  int readUInt29() {
    // Each byte must be treated as unsigned
    int b = this.read() & 255;
    if (b < 128) {
      return b;
    }
    int value = (b & 127) << 7;
    b = this.read() & 255;
    if (b < 128) {
      return (value | b);
    }
    value = (value | (b & 127)) << 7;
    b = this.read() & 255;
    if (b < 128) {
      return (value | b);
    }
    value = (value | (b & 127)) << 8;
    b = this.read() & 255;
    return (value | b);
  }

  void readFully(List<int> buff, int start, int length) {
    for (int i = start; i < length; i++) {
      buff[i] = this.read();
    }
  }

  String readUTF([int length = -1]) {
    int utflen = (length != -1) ? length : this.readUnsignedShort();
//    print("Reading utf $utflen");
    List chararr = [];
    int p = this.pos;
    int c1, c2, c3;

    while (this.pos < p + utflen) {
      c1 = this.read();
      if (c1 < 128) {

        chararr.add(new String.fromCharCode(c1));
      } else if (c1 > 2047) {
        c2 = this.read();
        c3 = this.read();
        chararr.add(new String.fromCharCode(((c1 & 15) << 12) | ((c2 & 63) << 6) | (c3 & 63)));
      } else {
        c2 = this.read();
        chararr.add(new String.fromCharCode(((c1 & 31) << 6) | (c2 & 63)));
      }
    }
    // The number of chars produced may be less than utflen
    return chararr.join("");
  }

  void reset() {
    this.objects = [];
    this.traits = [];
    this.strings = [];
  }

  Object readObject() {
    int type = read();
//    print("  Read object type: $type");
    return readObjectValue(type);
  }

  Object readHeaderObject() {
    int type = read();
    if (type == 0x11) {
      type = read();
      return readObject();
    } else {
      return readHeaderObjectValue(type);
    }
  }

  String readString() {
    int ref = this.readUInt29();
    if ((ref & 1) == 0) {
      return this.getString(ref >> 1);
    } else {
      int len = (ref >> 1);
      if (len == 0) {
        return AmfIO.EMPTY_STRING;
      }
      String str = this.readUTF(len);
      this.rememberString(str);
      return str;
    }
  }

  void rememberString(String v) {
    this.strings.add(v);
  }

  String getString(int v) {
    return this.strings[v];
  }

  void rememberObject(Object v) {
    this.objects.add(v);
  }

  Object getObject(int v) {
    return this.objects[v];
  }

  Map<String, Object> getTraits(int v) {
    return this.traits[v];
  }

  void rememberTraits(Map<String, Object> v) {
    this.traits.add(v);
  }

  Map<String, Object> readTraits(int ref) {
//    print("Reading traits ref: ${ref} & 3 = (${ref & 3})");
    if ((ref & 3) == 1) {
      return getTraits(ref >> 2);
    } else {

      int count = (ref >> 4);
      String className = this.readString();
//      print("Class '$className' has $count properties");
      Map<String, Object> traits = new Map();
      if (className != null && className != "") {
        traits[AmfIO.CLASS_ALIAS] = className;
      }
      traits[AmfIO.EXTERNALIZABLE] = ((ref & 4) == 4);
//      print("  Externalizable: ${(ref & 4) == 4}");
      List props = [];
      traits["props"] = props;
      for (int i = 0; i < count; i++) {
        props.add(this.readString());
      }
//      print("  Properties $className: $props");
      this.rememberTraits(traits);
      return traits;
    }
  }

  Object readScriptObject() {
    int ref = this.readUInt29();
//    print("Script object ref $ref & 1 == 0: ${((ref & 1) == 0)}");
    if ((ref & 1) == 0) {
      return this.getObject(ref >> 1);
    } else {
      Map<String, Object> traits = this.readTraits(ref);
      Object obj = null;
      Map map = null;
      InstanceMirror im;
      if (traits.containsKey(AmfIO.CLASS_ALIAS)) {
        String clazzName = traits[AmfIO.CLASS_ALIAS];
        Type constructor = AmfIO.classRegistry[clazzName];
//        print("$clazzName = $constructor");
        if (constructor != null){
          ClassMirror cm = reflectClass(constructor);

          obj = cm.newInstance(const Symbol(''), []).reflectee;
          im = reflect(obj);
        } else {
          print("Unregistered class $clazzName encountered");
        }
//        obj[Amf.CLASS_ALIAS] = traits[Amf.CLASS_ALIAS];
      }
      if (obj == null) {
        obj = new Map();
        map = obj;
      }
      this.rememberObject(obj);
      if (traits[AmfIO.EXTERNALIZABLE]) {//externalizable
        String alias;
        if (im != null){
          alias = AmfIO.typeRegistry[obj.runtimeType];
        } else {
          alias = map[AmfIO.CLASS_ALIAS];
        }
        if (alias == "flex.messaging.io.ArrayCollection") {
          ArrayCollection array = new ArrayCollection();
          array.source = this.readObject();
          //map["source"] = this.readObject();
          obj = array;
          map = null;
        }else if (alias == "java.lang.Class") {
          map["clazz"] = this.readObject();
        }else{
          throw "Unsupported external object: $alias";
        }
      } else {
//        print("IM: ${im}");
        if (im != null) {
//          print("Reading props: ${traits["props"]}");
          (traits["props"] as List<String>).forEach((prop) {
            Object value = this.readObject();
            Symbol symbol = MirrorSystem.getSymbol(prop);
//            print("  $prop = $value");
            im.setField(symbol, value);
          });
        } else {
//          print("Reading map props: ${traits["props"]}");
          (traits["props"] as List<String>).forEach((prop) {
            Object value = this.readObject();
            map[prop] = value;
          });
        }
        if ((ref & 11) == 11) {//dynamic
          for (; ;) {
            String name = this.readString();
            if (name == null || name.length == 0) {
              break;
            }
            im.setField(new Symbol(name), this.readObject());
          }
        }
      }
      return obj;
    }
  }

  Object readArray() {
    int ref = this.readUInt29();
    if ((ref & 1) == 0) {
      return this.getObject(ref >> 1);
    }
    int len = (ref >> 1);
    Map<String, Object> map = null;
    int i = 0;
    while (true) {
      String name = this.readString();
//      print("While reading array name is '$name'");
      if (name == null || name.length == 0) {
        break;
      }
      if (map == null) {
        map = new Map();
        this.rememberObject(map);
      }
      map[name] = this.readObject();
    }
    if (map == null) {
//      print("Reading array with length: $len");
      List<Object> array = new List(len);
      this.rememberObject(array);
      for (i = 0; i < len; i++) {
        array[i] = this.readObject();
      }
      return array;
    } else {
      for (i = 0; i < len; i++) {
        map[i.toString()] = this.readObject();
      }
      return map;
    }
  }

  double readDouble() {
    int c1 = this.read() & 255;
    int c2 = this.read() & 255;
    if (c1 == 255) {
      if (c2 == 248)
        return double.NAN;
      if (c2 == 240)
        return double.NEGATIVE_INFINITY;
    } else if (c1 == 127 && c2 == 240) {
      return double.INFINITY;
    }
    int c3 = this.read() & 255;
    int c4 = this.read() & 255;
    int c5 = this.read() & 255;
    int c6 = this.read() & 255;
    int c7 = this.read() & 255;
    int c8 = this.read() & 255;
    if (c1 == 0 && c2 == 0 && c3 ==0 && c4 == 0) return 0.0;
    int d = (c1 << 4 & 2047 | c2 >> 4) - 1023;
    String s2 = ((c2 & 15) << 16 | c3 << 8 | c4).toRadixString(2);
    for (c3 = s2.length; c3 < 20; c3++)
      s2 = "0$s2";
    String s6 = ((c5 & 127) << 24 | c6 << 16 | c7 << 8 | c8).toRadixString(2);
    for (c3 = s6.length; c3 < 31; c3++)
      s6 = "0$s6";
    if ((c5>>7) == 0) {
      c5 = int.parse("${s2}0$s6", radix: 2);
    } else {
      c5 = int.parse("${s2}1$s6", radix: 2);
    }
    if (c5 == 0 && d == -1023)
      return 0.0;
    return (1 - (c1 >> 7 << 1)) * (1 + pow(2, -52) * c5) * pow(2, d);
  }

  DateTime readDate() {
    int ref = this.readUInt29();
    if ((ref & 1) == 0) {
      return this.getObject(ref >> 1);
    }
    int time = this.readDouble().floor();
    DateTime date = new DateTime.fromMillisecondsSinceEpoch(time, isUtc: true);
    this.rememberObject(date);
    return date;
  }

  Map<String, Object> readMap() {
    int ref = this.readUInt29();
    if ((ref & 1) == 0) {
      return this.getObject(ref >> 1);
    }
    int length = (ref >> 1);
    Map<String, Object> map = null;
    if (length > 0) {
      map = new Map();
      this.rememberObject(map);
      String name = this.readObject();
      while (name != null) {
        map[name] = this.readObject();
        name = this.readObject();
      }
    }
    return map;
  }

  List<int> readByteArray() {
    int ref = this.readUInt29();
    if ((ref & 1) == 0) {
      return this.getObject(ref >> 1);
    } else {
      int len = (ref >> 1);
      List<int> ba = new List(len);
      this.readFully(ba, 0, len);
      this.rememberObject(ba);
      return ba;
    }
  }

  Object readHeaderObjectValue(int type) {
    Object value = null;
    switch (type) {
      case 2:
        value = readUTF();
        break;
      default:
        throw "Unknown AMF0 type: $type";
    }
    return value;

  }

  Object readObjectValue(int type) {
    Object value = null;

    switch (type) {
      case AmfIO.STRING_TYPE:
        value = this.readString();
        break;
      case AmfIO.OBJECT_TYPE:
//        try {
        value = this.readScriptObject();
//        } catch (e) {
//          throw "Failed to deserialize: $e";
//        }
        break;
      case AmfIO.ARRAY_TYPE:
        value = this.readArray();
        //value = this.readMap();
        break;
      case AmfIO.FALSE_TYPE:
        value = false;
        break;
      case AmfIO.TRUE_TYPE:
        value = true;
        break;
      case AmfIO.INTEGER_TYPE:
        int temp = this.readUInt29();
        // Symmetric with writing an integer to fix sign bits for
        // negative values...
        value = (temp << 3) >> 3;
        break;
      case AmfIO.DOUBLE_TYPE:
        value = this.readDouble();
        break;
      case AmfIO.UNDEFINED_TYPE:
      case AmfIO.NULL_TYPE:
        break;
      case AmfIO.DATE_TYPE:
        value = this.readDate();
        break;
      case AmfIO.BYTEARRAY_TYPE:
        value = this.readByteArray();
        break;
      case AmfIO.AMF0_AMF3:
        value = this.readObject();
        break;
      default:
        throw "Unknown AMF type: $type";
    }
    return value;
  }

  bool readBoolean() {
    return this.read() == 1;
  }
}

class Serializer {
  Writer writer = new Writer();

  List<int> writeMessage(ActionMessage message) {
//    try {
//      print("version");
    this.writer.writeShort(message.version);
//      print("headers");
    this.writer.writeShort(message.headers.length);
    message.headers.forEach((header){
      this.writeHeader(header);
    });

//      print("bodies");
    this.writer.writeShort(message.bodies.length);
    message.bodies.forEach((body) {
      this.writeBody(body);
    });

//      print("end");
//    } catch (error) {
//      print(error);
//    }
    //return this.writer.getResult();
    return this.writer.data;
  }

  void writeObject(Object object) {
    this.writer.writeObject(object);
  }

  void writeHeader(MessageHeader header) {
    this.writer.writeUTF(header.name);
    this.writer.writeBoolean(header.mustUnderstand);
    this.writer.writeInt(1); //UNKNOWN_CONTENT_LENGTH used to be -1
    this.writer.reset();
    //this.writer.writeObject(header.data);
    this.writer.write(1); //boolean amf0 marker
    this.writer.writeBoolean(true);
  }

  void writeBody(MessageBody body) {
    if (body.targetURI == null) {
      this.writer.writeUTF(AmfIO.NULL_STRING);
    } else {
      this.writer.writeUTF(body.targetURI);
    }
    if (body.responseURI == null) {
      this.writer.writeUTF(AmfIO.NULL_STRING);
    } else {
      this.writer.writeUTF(body.responseURI);
    }
    // this.writer.writeInt(1); //UNKNOWN_CONTENT_LENGTH used to be -1
    // this.writer.reset();
    // this.writer.write(amf.CONST.AMF0_AMF3); //AMF0_AMF3
    // this.writeObject(body.data);

    // Find the body size
    Writer bodyWriter = new Writer();
    bodyWriter.write(17); // AMF3
    bodyWriter.writeObject(body.data);

    this.writer.writeInt(bodyWriter.data.length);
    this.writer.reset();
    this.writer.data.addAll(bodyWriter.data);
  }
}

class Deserializer {
  Reader reader;

  Deserializer(ByteData data) {
//    print("Deserializing data ${data.lengthInBytes}");
    reader = new Reader(data);
  }

  ActionMessage readMessage() {
    ActionMessage message = new ActionMessage();
    message.version = this.reader.readUnsignedShort();
//    print("Version ${message.version}");
    int headerCount = this.reader.readUnsignedShort();
//    print("Headers $headerCount");
    for (int i = 0; i < headerCount; i++) {
      message.headers.add(this.readHeader());
    }
    int bodyCount = this.reader.readUnsignedShort();
//    print("Bodies $bodyCount");
    for (int i = 0; i < bodyCount; i++) {
      message.bodies.add(this.readBody());
    }
    return message;
  }

  MessageHeader readHeader() {
    MessageHeader header = new MessageHeader();
    header.name = this.reader.readUTF();
    header.mustUnderstand = this.reader.readBoolean();
    this.reader.pos += 4; //length
    this.reader.reset();
    header.data = this.readHeaderObject();
//    print("  Header: ${header.name} ${header.mustUnderstand} = ${header.data}");
    return header;
  }

  MessageBody readBody() {
    MessageBody body = new MessageBody();
//    print("  Reading target URI");
    body.targetURI = this.reader.readUTF();
//    print("  Reading response URI");
    body.responseURI = this.reader.readUTF();
//    print("  Body target: '${body.targetURI}' response: '${body.responseURI}'");
    this.reader.pos += 4; //length
    this.reader.reset();
//    print("Reading body data");
    body.data = [this.readObject()];
    return body;
  }

  Object readObject() {
    return this.reader.readObject();
  }

  Object readHeaderObject() {
    return this.reader.readHeaderObject();
  }

}