library spring_remote;

import 'src/metadata.dart';

@RemoteObject("org.springframework.security.authentication.BadCredentialsException")
class BadCredentialsException {
  String message;
  List suppressed;
  String localizedMessage;
  String cause;
  UsernamePasswordAuthenticationToken authentication;
  String extraInformation;
}

@RemoteObject("org.springframework.security.authentication.UsernamePasswordAuthenticationToken")
class UsernamePasswordAuthenticationToken {
  WebAuthenticationDetails details;
  bool authenticated;
}

@RemoteObject("org.springframework.security.web.authentication.WebAuthenticationDetails")
class WebAuthenticationDetails {

}