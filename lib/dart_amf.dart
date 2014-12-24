library amf;

import 'dart:html';
import 'dart:collection';
@MirrorsUsed(targets: 'amf', symbols: '*')
import 'dart:mirrors';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';

import 'src/amf_io.dart';
export 'src/metadata.dart';
import 'src/remote_classes.dart';
export 'src/remote_classes.dart';


/**
 * Provides access to BlazeDS backend
 *
 * Annotate classes with @RemoteObject(alias) so they will be typed correctly
 * on the server and in the client.
 *
 * Reads the AMF bytes directly, it does use dart:mirrors to construct and
 * set the properties on the classes marked @RemoteObject.
 *
 * The server must use CORS or be on the same host and port for this to work
 */
class Amf {

  /**
   * The timeout used for the underlying dart:html/HttpRequest
   */
  int requestTimeout = 30000;

  /**
   * If true (default) then will send a unique messageId with each message
   */
  bool sendMessageId = true;

  static Uuid _uuid = new Uuid();

  ListQueue<List> _messageQueue = new ListQueue();
  String _clientId = null;
  int _sequence = 1;
  String _endpoint = "";
  String _baseEndpoint = "";
  Map<String, String> _headers = null;
  bool _busy = false;

  /**
   * Creates a connection to a remote BlazeDS server
   * The server must use CORS or be on the same host and port for this to work
   */
  Amf(String endpoint, [int timeout = 30000]) {
    AmfIO.discoverRemoteObjects();
    _init(endpoint, timeout);
  }

  void _init(String endpoint, [int timeout = 30000]) {
    _clientId = null;
    _sequence = 1;
    this._baseEndpoint = endpoint;
    this._endpoint = endpoint;
    this.requestTimeout = timeout;
    this._headers = new Map();
  }

  /**
   * Used to authenticate with BlazeDS
   * Uses basic authentication so should only be used over HTTPS
   */
  void login(String username, String password, Function onResult, Function onStatus) {
    String combined = "$username:$password";
    String encoded = window.btoa(combined);
    invoke("auth", "auth", encoded, onResult, onStatus);
  }

  ActionMessage _createMessage(String destination, [String operation, Object params]) {
    ActionMessage actionMessage = new ActionMessage();
    MessageBody messageBody = new MessageBody();
    Object msg;
    if (destination == "ping") {
      _sequence = 1;
      messageBody.responseURI = "/${_sequence++}";
      CommandMessage message = new CommandMessage();
      message.destination = destination;
      msg = message;
    } else if (destination == "auth") {
      messageBody.responseURI = "/${_sequence++}";
      CommandMessage message = new CommandMessage(8);
      message.destination = destination;
      message.body = params;
      message.headers = new Map();
      message.headers["DSId"] = _clientId;
      message.clientId = null;
      msg = message;
    } else {
      messageBody.responseURI = "/${_sequence++}";
      RemotingMessage message = new RemotingMessage();
      message.destination = destination;
      message.operation = operation;
      message.body = params;
      message.timeToLive = 0;
      message.timestamp = 0;
      if (sendMessageId) {
        message.messageId = _uuid.v1();
      }
      message.headers = new Map();
      message.clientId = _clientId;
      message.headers["DSId"] = _clientId;
      _headers.forEach((key, value) => message.headers[key] = value);
      msg = message;
    }

    messageBody.data = [msg];
    actionMessage.bodies.add(messageBody);
    return actionMessage;
  }

  /**
   * Used to invoke a remote service running in BlazeDS
   */
  void invoke(String destination, String operation, Object params, Function onResult, Function onStatus) {
    if (_clientId == null && _messageQueue.length == 0) {
//      print("Doing initial ping to get a client id");
      _messageQueue.add([_createMessage("ping", "ping"), (res) {
      }, onStatus]);
      _processQueue();
    }

    _messageQueue.add([_createMessage(destination, operation, params), onResult, onStatus]);
    if (_clientId != null) {
      _processQueue();
    }
  }

  void _processQueue() {
    if (_busy || _messageQueue.length == 0)
      return;
    _busy = true;
    HttpRequest request = new HttpRequest();
    request.withCredentials = true;
    List args = _messageQueue.removeFirst();
    _send(request, args[0], args[1], args[2]);
//    print("Sending to ${args[0].bodies[0].data[0].destination}");
    if (args[0].bodies[0].data[0] is CommandMessage) {
      CommandMessage msg = args[0].bodies[0].data[0];
      if (msg.operation == 5) {
        //ping
        return;
      } else if (msg.operation == 8) {
        // login
        this._headers["DSRemoteCredentials"] = '';
        this._headers["DSRemoteCredentialsCharset"] = null;
      }
    }
  }

  void _send(HttpRequest request, ActionMessage message, Function onResult, Function onStatus) {
    Serializer serializer = new Serializer();
    request.onReadyStateChange.listen((e) {
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
                this._headers[msgHeader.name] = msgHeader.data;
              }
            });
            response.bodies.forEach((body) {
              if (body.targetURI != null && body.targetURI.indexOf("/onResult") > -1) {

//                if (body.targetURI == "/1/onResult") {
                AcknowledgeMessage data = body.data[0];
//                  print("Setting clientId: ${data.clientId}");
                this._clientId = data.clientId.toString();
                // this.parent.headers.DSId = body.data.clientId;
                data.headers.forEach((headerName, value) {
//                    print("  Setting $headerName to ${value}");
                  this._headers[headerName] = value;
                });
                _messageQueue.forEach((args) {
//                  print("      Setting each message clientId and DSId to $_clientId");
                  args[0].bodies[0].data[0].clientId = _clientId;
                  args[0].bodies[0].data[0].headers["DSId"] = _clientId;
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
            _busy = false;
//            if (_clientId != null) {
            _processQueue();
//            }
          } else {
            onStatus("Wrong content-type, expected application/x-amf but got ${header}");
          }
        } else {
          onStatus("Server error: ${e}");
        }
      }
    });
    request.open("POST", _endpoint);

  }
}