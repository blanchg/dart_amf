Introduction
============

DartAmf provides a native Dart interface to a BlazeDS backend using AMF.

It is using the dart:html HttpRequest so it will work in a browser but unlikely to work from a commandline without modification.

Based heavily on a modified https://github.com/davidef/amfjs/ (Apache 2.0 License) which was based on Surrey's R-AMF (AMF 99) implementation https://code.google.com/p/r-amf/

How To
------

Sample of creating an amf channel and invoking a call

    Amf channel = new Amf('http://my-server/messaging/amf');
    channel.invoke("destination", "operation"
    	(result) => print("Success $result"),
    	(error) => print("Error $error"));

Custom classes need to be registered before you can receive them as Dart typed objects.

	class Animal {

	}

    BigInt extends num {
    	
    }

    Amf.registerClass("server.package.Animal", Animal);
    Amf.registerClass("another.server.package.BigInt", BigInt);