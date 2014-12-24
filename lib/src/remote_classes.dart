library remote_classes;

import 'metadata.dart';
import 'dart:collection';

class AbstractMessage {
  String clientId;
  String destination;
  String messageId;
  int timestamp;
  int timeToLive;
  Map<String, String> headers;
  Object body;
}

@RemoteObject("flex.messaging.io.amf.ActionMessage")
class ActionMessage {
  int version = 3;
  List<MessageHeader> headers = [];
  List<MessageBody> bodies = [];
}

@RemoteObject("flex.messaging.io.amf.MessageBody")
class MessageBody {
  String targetURI = "null";
  String responseURI = "/1";
  List<Object> data;
}

@RemoteObject("flex.messaging.io.amf.MessageBody")
class MessageHeader {
  String name = "";
  bool mustUnderstand = false;
  Object data = null;
}

@RemoteObject("flex.messaging.messages.CommandMessage")
class CommandMessage {
  int operation;
  String destination;
  String clientId;
  Map<String, String> headers;
  Object body;
  CommandMessage([this.operation = 5]);
}

@RemoteObject("flex.messaging.messages.RemotingMessage")
class RemotingMessage extends AbstractMessage {
  String source = "";
  String operation;
  List parameters;
}

@RemoteObject("flex.messaging.messages.AcknowledgeMessage")
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

@RemoteObject("flex.messaging.messages.ErrorMessage")
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

@RemoteObject("flex.messaging.io.ArrayCollection")
class ArrayCollection extends ListMixin {

  List source;

  int get length => source.length;
      set length(int value) => source.length = value;

  Object operator [] (int index)          => source[index];
    operator []=(int index, Object value) => source[index] = value;

  void addAll(Iterable<Object> iterable) => source.addAll(iterable);
}