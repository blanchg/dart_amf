import 'dart:html';

import 'amf.dart';

Amf amf = null;
void main() {
  querySelector('#sample_text_id')
    ..text = 'Click me!'
    ..onClick.listen(reverseText);

  amf = new Amf('http://localhost:3030/minestar/messagebroker/amf');
  Amf.registerClass("minestar.ciods.security.PrivilegeDto", PrivilegeDto);

}

class PrivilegeDto {
  String name;
  List<Object> actions;
}

void reverseText(MouseEvent event) {
  var text = querySelector('#sample_text_id').text;
  var buffer = new StringBuffer();
  for (int i = text.length - 1; i >= 0; i--) {
    buffer.write(text[i]);
  }
  querySelector('#sample_text_id').text = buffer.toString();

  print("Starting to call amf");
//  amf.invoke("monitorUCC", "getSupportedMonitors", [],
//      (res) {
//        print('success: $res');
//        amf.login("MineStar", "MineStar",
//        (res) {
//          print("Logged in $res");
//          amf.invoke("applicationService",  "getSessionInformation", [],
//          (res) => print("Session: $res"),
//          (err) => print("Sesison error: ${(err as ErrorMessage).faultString}"));
//        },
//        (err) => print("Failed to login $err"));
//        amf.invoke("userUCC",  "getUserLogonDetails", ["MineStar"],
//          (res) => print('User: $res'),
//          (err) => print('Error: $err'));
//      },
//      (err) => print("Failed: ${(err as ErrorMessage).faultString}"));
  amf.invoke("monitorUCC", "getServerTime", [],
  (res) {
    print("Server time ${(res as num).toInt()}");
    amf.login("MineStar", "MineStar",
        (res) {
          print("Logged in $res");
          amf.invoke("applicationService", "getSessionInformation", [],
              (res) => print("Session: $res"),
              (err) => print("Sesison error: ${(err as ErrorMessage).faultString}"));
        },
        (err) => print("Failed to login ${(err as ErrorMessage).faultString}"));
  },
  (err) {
    print("Could not get server time $err");
  });
  print("Finished amf");
}
