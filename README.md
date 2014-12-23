Introduction
============

DartAmf provides a native Dart interface to a BlazeDS backend using AMF.

How To
------

Sample of creating an amf channel and invoking a call

    Amf channel = new Amf('http://my-server/messaging/amf');
    channel.invoke("destination", "source", "operation"
    	(result) => print("Success $result"),
    	(error) => print("Error $error"));

Custom classes need to be registered before you can receive them as Dart typed objects.

	class Animal {

	}

    BigInt extends num {
    	
    }

    Amf.registerClass("server.package.Animal", Animal);
    Amf.registerClass("another.server.package.BigInt", BigInt);