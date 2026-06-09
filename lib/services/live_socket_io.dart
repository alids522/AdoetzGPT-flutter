import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

WebSocketChannel connectLiveSocket(Uri uri) {
  return IOWebSocketChannel.connect(
    uri,
    pingInterval: const Duration(seconds: 20),
    connectTimeout: const Duration(seconds: 20),
  );
}
