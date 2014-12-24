import 'dart:html';

import 'package:dart_amf/dart_amf.dart';
// Interacting with spring so include their definitions
import 'package:dart_amf/spring_remote.dart';

// This is here to stop the spring_remote.dart from becoming unused
BadCredentialsException x;

Amf amf = null;

void main() {
  querySelector('#sample_text_id')
    ..text = 'Click to login'
    ..onClick.listen(login);

  amf = new Amf('http://localhost:3030/minestar/messagebroker/amf');

}

@RemoteObject("server.package.MyClass")
class MyClass {
  String name;
  List<Object> actions;
}

void login(MouseEvent event) {
  querySelector('#sample_text_id').text = 'Busy';

  print("Starting to call amf");
  amf.login("username", "password", (res) {
    print("Logged in $res");
    querySelector('#result_id')
      ..text = "Logged in $res";
    querySelector('#sample_text_id').text = 'Done';

    amf.invoke("server", "methodOnServer",[new MyClass()], (res)=>print(res), (err)=>print(err));
  }, (err) {
    print("Failed to login ${(err as ErrorMessage).faultString}");
    querySelector('#result_id')
      ..text = "Failed to login ${(err as ErrorMessage).faultString}";
    querySelector('#sample_text_id').text = 'Failed';
  });
  print("Finished amf");
}
