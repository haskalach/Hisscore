// Minimal static file server for previewing the built web app.
// Not part of the app; used only for local manual testing.
import 'dart:io';

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.parse(args[0]) : 8766;
  final root = Directory.current.path;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('Serving $root on http://localhost:$port');
  await for (final request in server) {
    var path = request.uri.path;
    if (path == '/' || path.isEmpty) path = '/index.html';
    final file = File('$root$path');
    if (await file.exists()) {
      final ext = file.path.split('.').last;
      request.response.headers.contentType = _contentType(ext);
      // This serves a directory that gets overwritten by every rebuild —
      // never let the browser cache a stale bundle across runs.
      request.response.headers.set('Cache-Control', 'no-store, must-revalidate');
      await request.response.addStream(file.openRead());
    } else {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Not found');
    }
    await request.response.close();
  }
}

ContentType _contentType(String ext) {
  switch (ext) {
    case 'html':
      return ContentType.html;
    case 'js':
      return ContentType('application', 'javascript');
    case 'json':
      return ContentType.json;
    case 'css':
      return ContentType('text', 'css');
    case 'wasm':
      return ContentType('application', 'wasm');
    case 'png':
      return ContentType('image', 'png');
    default:
      return ContentType.binary;
  }
}
