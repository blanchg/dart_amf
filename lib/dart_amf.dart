library amf;

import 'dart:html';
import 'dart:collection';
import 'dart:math' as Math;
@MirrorsUsed(targets: 'amf', symbols: '*')
import 'dart:mirrors';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';

class Amf {
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

  static Uuid uuid = new Uuid();

  int requestTimeout = 30000;
  int requestPoolSize = 6;
  List<HttpRequest> requestPool = [];
  ListQueue<List> messageQueue = new ListQueue();
  bool sendMessageId = true;
  String clientId = null;
  int sequence = 1;
  String endpoint = "";
  String baseEndpoint = "";
  Map<String, String> headers = null;
  Function doNothing = ()=>{};
  static Map<String, Type> classRegistry = new Map();
  static Map<Type, String> typeRegistry = new Map();

  Amf([String endpoint, int timeout = 30000]) {
    Amf.registerClass("flex.messaging.messages.AcknowledgeMessage", AcknowledgeMessage);
    Amf.registerClass("flex.messaging.messages.ErrorMessage", ErrorMessage);
    Amf.registerClass("flex.messaging.io.ArrayCollection", ArrayCollection);
    Amf.registerClass("flex.messaging.io.amf.ActionMessage", ActionMessage);
    Amf.registerClass("flex.messaging.io.amf.MessageBody", MessageBody);
    Amf.registerClass("flex.messaging.io.amf.MessageHeader", MessageHeader);
    Amf.registerClass("flex.messaging.messages.CommandMessage", CommandMessage);
    Amf.registerClass("flex.messaging.messages.RemotingMessage", RemotingMessage);
    init(endpoint, timeout);
  }

  void init(String endpoint, [int timeout = 30000]) {
    clientId = null;
    sequence = 1;
    this.baseEndpoint = endpoint;
    this.endpoint = endpoint;
    this.requestTimeout = timeout;
    this.headers = new Map();
  }

  static void registerClass(String name, Type clazz) {
    classRegistry[name] = clazz;
    typeRegistry[clazz] = name;
  }

  void addHeader(String name, String value) {
    headers[name] = value;
  }

  void login(String username, String password, Function onResult, Function onStatus) {
    String encoded = window.btoa("$username:$password");
//    messageQueue.add([createMessage("auth", "auth", null, encoded), onResult, onStatus]);
    invoke("auth", null, encoded, onResult, onStatus);
//    _processQueue();
  }

  ActionMessage createMessage(String destination, [String operation, Object params]) {
    ActionMessage actionMessage = new ActionMessage();
    MessageBody messageBody = new MessageBody();
    Object msg;
    messageBody.responseURI = "/${sequence++}";
    if (destination == "ping") {
      sequence = 1;
      messageBody.responseURI = "/${sequence++}";
      CommandMessage message = new CommandMessage();
//      print("Ping message operation ${message.operation}");
      message.destination = destination;
      msg = message;
    } else if (destination == "auth") {
      CommandMessage message = new CommandMessage(8);
//      print("Auth message operation ${message.operation}");
      message.destination = destination;
      message.body = params;
      message.headers = new Map();
//      print("Auth client id $clientId");
      message.headers["DSId"] = clientId;
      message.clientId = null;
      msg = message;
    } else {
      RemotingMessage message = new RemotingMessage();
      message.destination = destination;
      message.operation = operation;
      message.body = params;
      message.timeToLive = 0;
      message.timestamp = 0;
      if (sendMessageId) {
        message.messageId = uuid.v1();
      }
      message.headers = new Map();
      message.clientId = clientId;
      message.headers["DSId"] = clientId;
      headers.forEach((key, value) => message.headers[key] = value);
      msg = message;
    }

    messageBody.data = [msg];
    actionMessage.bodies.add(messageBody);
    return actionMessage;
  }

  void invoke(String destination, String operation, Object params, Function onResult, Function onStatus) {
    if (clientId == null && messageQueue.length == 0) {
//      print("Doing initial ping to get a client id");
      messageQueue.add([createMessage("ping", "ping"), (res){}, onStatus]);
      _processQueue();
    }

    messageQueue.add([createMessage(destination, operation, params), onResult, onStatus]);
    if (clientId != null) {
      _processQueue();
    }
  }

  bool busy = false;
  void _processQueue() {
    if (busy || messageQueue.length == 0)
      return;
    busy = true;
    HttpRequest request;
    if (requestPool.length == 0) {
      request = new HttpRequest();
      request.withCredentials = true;
//      requestPool.add(request);
    } else {
      request = requestPool.single;

    }
    List args = messageQueue.removeFirst();
    _send(request, args[0], args[1], args[2]);
//    print("Sending to ${args[0].bodies[0].data[0].destination}");
    if (args[0].bodies[0].data[0] is CommandMessage) {
      CommandMessage msg = args[0].bodies[0].data[0];
      if (msg.operation == 5) { //ping
        return;
      } else if (msg.operation == 8) { // login
        this.headers["DSRemoteCredentials"] = '';
        this.headers["DSRemoteCredentialsCharset"] = null;
      }
    }
  }

  void _send(HttpRequest request, ActionMessage message, Function onResult, Function onStatus) {
    Serializer serializer = new Serializer();
    request.onReadyStateChange.listen ((e) {
      if (request.readyState == 1) {
        request.setRequestHeader("content-type", "application/x-amf; charset=UTF-8");
        request.setRequestHeader("x-flash-version", "15,0,0,223");
        request.setRequestHeader("Pragma", "no-cache");
        request.responseType = "arraybuffer";
//        print("Before serialzing");
        request.send(new Uint8List.fromList(serializer.writeMessage(message)));
//        print("after serialzing");
      } else if (request.readyState == 4) {
        if (request.status >= 200 && request.status <= 300) {
          String header = request.getResponseHeader("content-type");
          if (header != null && header.indexOf("application/x-amf") > -1) {
            Deserializer deserializer = new Deserializer(new ByteData.view(request.response));
            ActionMessage response = deserializer.readMessage();
            response.headers.forEach((msgHeader) {
              if (msgHeader.name == "AppendToGatewayUrl") {
//                endpoint = baseEndpoint + msgHeader.data;
//                cookie.set("jsessionid",  msgHeader.data.split('=')[1], path: '/minestar');
              } else {
//              print("  Setting actionmessage $msgHeader");
                this.headers[msgHeader.name] = msgHeader.data;
              }
            });
            response.bodies.forEach((body) {
              if (body.targetURI != null && body.targetURI.indexOf("/onResult") > -1) {

//                if (body.targetURI == "/1/onResult") {
                  AcknowledgeMessage data = body.data[0];
//                  print("Setting clientId: ${data.clientId}");
                  this.clientId = data.clientId.toString();
                  // this.parent.headers.DSId = body.data.clientId;
                  data.headers.forEach((headerName, value) {
//                    print("  Setting $headerName to ${value}");
                    this.headers[headerName] = value;
                  });
                  messageQueue.forEach((args) {
//                    print("      Setting each message clientId and DSId to $clientId");
//                    args[0].bodies[0].data[0].clientId = clientId;
//                    args[0].bodies[0].data[0].headers["DSId"] = clientId;
                  });
                if (body.targetURI == "/1/onResult") {
                } else {
                  onResult(body.data[0].body);
                }
              } else {
                if (body.data.length == 0) {
                  onStatus("No bodies returned");
                } else {
                  Object data = body.data[0];
                  if (data is ErrorMessage) {
                    onStatus(data);
                  }
                }
              }
            });
            busy = false;
            if (clientId != null) {
              _processQueue();
            }
          } else {
            onStatus("Wrong content-type, expected application/x-amf but got ${header}");
          }
        } else {
          onStatus("Server error: ${e}");
        }
      }
    });
    request.open("POST", endpoint);

  }


//  static Math.Random rand = new Math.Random();
////https://gist.github.com/jed/982883
//  static uuid([int a = 0, int b = 0]){
//    if (a != 0) {
//      int c = b;
//      if (b == 0) {
//        c = (rand.nextDouble()*16.0).floor();
//
//      }
//      (b>>b/4).toRadixString(16);
//    } else {
//      ((1e7)+(0-1e3)+(0-4e3)+(0-8e3)+(0-1e11)).replace(/1|0|(8)/g,)
//    }
//  }
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
      i = v * Math.pow(2, 23) / 2;
      r[1] = (v * Math.pow(2, 52) / 2).round();
    } else {
      i = v * Math.pow(2, 20) - Math.pow(2, 20);
      r[1] = (v * Math.pow(2, 52) - Math.pow(2, 52)).round();
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
    if (v >= Amf.INT28_MIN_VALUE && v <= Amf.INT28_MAX_VALUE) {
      v = v & Amf.UINT29_MASK;
      this.write(Amf.INTEGER_TYPE);
      this.writeUInt29(v);
    } else {
      this.write(Amf.DOUBLE_TYPE);
      this.writeDouble(v.toDouble());
    }
  }

  void writeDate(DateTime v) {
    this.write(Amf.DATE_TYPE);
    if (objectByReference(v) != null) {
      writeUInt29(1);
      writeDouble(v.millisecondsSinceEpoch.toDouble());
    }
  }

  void writeObject(Object v) {
    if (v == null) {
      this.write(Amf.NULL_TYPE);
      return;
    }
    if (v is String) {
      this.write(Amf.STRING_TYPE);
      this.writeStringWithoutType(v);
    } else if (v is num) {
      if (v == v.abs()) {
        this.writeAmfInt((v).toInt());
      } else {
        this.write(Amf.DOUBLE_TYPE);
        this.writeDouble(v);
      }
    } else if (v is bool) {
      this.write((v
      ? Amf.TRUE_TYPE
      : Amf.FALSE_TYPE));
    } else if (v is DateTime) {
      this.writeDate(v);
    } else {
      if (v is List) {
        this.writeArray(v);
      } else if (Amf.typeRegistry.containsKey(v.runtimeType)) {
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
    write(Amf.OBJECT_TYPE);
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
    String type = Amf.typeRegistry[v.runtimeType];
    if (type == null) {
      type = MirrorSystem.getName(reflectType(v.runtimeType).qualifiedName);
//      print("Type (${v.runtimeType}) not registered, assuming it is $type");
      Amf.registerClass(type, v.runtimeType);
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
    this.write(Amf.OBJECT_TYPE);
    if (objectByReference(v) == null) {
      this.writeUInt29(11);
      this.traitCount++; //bogus traits entry here
      this.writeStringWithoutType(Amf.EMPTY_STRING); //class name
      v.forEach((key, value) {
        if (key != null) {
          this.writeStringWithoutType(key);
        } else {
          this.writeStringWithoutType(Amf.EMPTY_STRING);
        }
        this.writeObject(value);
      });
      this.writeStringWithoutType(Amf.EMPTY_STRING); //empty string end of dynamic members
    }
  }

  void writeArray(List v) {
    this.write(Amf.ARRAY_TYPE);
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
        return Amf.EMPTY_STRING;
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
        traits[Amf.CLASS_ALIAS] = className;
      }
      traits[Amf.EXTERNALIZABLE] = ((ref & 4) == 4);
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
      if (traits.containsKey(Amf.CLASS_ALIAS)) {
        String clazzName = traits[Amf.CLASS_ALIAS];
        Type constructor = Amf.classRegistry[clazzName];
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
      if (traits[Amf.EXTERNALIZABLE]) {//externalizable
        String alias;
        if (im != null){
          alias = Amf.typeRegistry[obj.runtimeType];
        } else {
          alias = map[Amf.CLASS_ALIAS];
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
    return (1 - (c1 >> 7 << 1)) * (1 + Math.pow(2, -52) * c5) * Math.pow(2, d);
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
      case Amf.STRING_TYPE:
        value = this.readString();
        break;
      case Amf.OBJECT_TYPE:
//        try {
          value = this.readScriptObject();
//        } catch (e) {
//          throw "Failed to deserialize: $e";
//        }
        break;
      case Amf.ARRAY_TYPE:
        value = this.readArray();
        //value = this.readMap();
        break;
      case Amf.FALSE_TYPE:
        value = false;
        break;
      case Amf.TRUE_TYPE:
        value = true;
        break;
      case Amf.INTEGER_TYPE:
        int temp = this.readUInt29();
        // Symmetric with writing an integer to fix sign bits for
        // negative values...
        value = (temp << 3) >> 3;
        break;
      case Amf.DOUBLE_TYPE:
        value = this.readDouble();
        break;
      case Amf.UNDEFINED_TYPE:
      case Amf.NULL_TYPE:
        break;
      case Amf.DATE_TYPE:
        value = this.readDate();
        break;
      case Amf.BYTEARRAY_TYPE:
        value = this.readByteArray();
        break;
      case Amf.AMF0_AMF3:
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
      this.writer.writeUTF(Amf.NULL_STRING);
    } else {
      this.writer.writeUTF(body.targetURI);
    }
    if (body.responseURI == null) {
      this.writer.writeUTF(Amf.NULL_STRING);
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

class AbstractMessage {
  String clientId;
  String destination;
  String messageId;
  int timestamp;
  int timeToLive;
  Map<String, String> headers;
  Object body;
}

class ActionMessage {
  int version = 3;
  List<MessageHeader> headers = [];
  List<MessageBody> bodies = [];
}

class MessageBody {
  String targetURI = Amf.NULL_STRING;
  String responseURI = "/1";
  List<Object> data;
}

class MessageHeader {
  String name = "";
  bool mustUnderstand = false;
  Object data = null;
}

class CommandMessage {
  int operation;
  String destination;
  String clientId;
  Map<String, String> headers;
  Object body;
  CommandMessage([this.operation = 5]);
}

class RemotingMessage extends AbstractMessage {
  String source = "";
  String operation;
  List parameters;
}

class AcknowledgeMessage {
  Object body;
  Map headers = {};
  String messageId;
  String destination;
  String clientId;
  String correlationId;
  double timestamp;
  double timeToLive;
}

class ErrorMessage {
  String faultCode;
  Map headers = {};
  String faultDetail;
  String faultString;
  Object rootCause;
  Object body;
  String correlationId;
  String clientId;
  double timeToLive;
  String destination;
  double timestamp;
  Object extendedData;
  String messageId;
}

class ArrayCollection<E> extends ListMixin {

  List<E> source;

  int get length => source.length;
      set length(int value) => source.length = value;

  E operator [] (int index)          => source[index];
    operator []=(int index, E value) => source[index] = value;

  void addAll(Iterable<E> iterable) => source.addAll(iterable);
}