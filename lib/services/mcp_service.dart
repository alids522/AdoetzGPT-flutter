import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:mcp_dart/mcp_dart.dart';

import '../models.dart';

class McpConnection {
  McpServerConfig config;
  McpClient? client;
  StreamableHttpClientTransport? transport;
  List<Tool>? tools;

  McpConnection({required this.config});
}

class McpService extends ChangeNotifier {
  final Map<String, McpConnection> _connections = {};
  
  List<McpServerConfig> get connectedServers => _connections.values.map((c) => c.config).toList();
  
  Future<void> connectToServer(McpServerConfig config) async {
    final connection = McpConnection(config: config);
    _connections[config.id] = connection;
    notifyListeners();
    
    try {
      connection.client = McpClient(
        Implementation(name: 'adoetzgpt-mcp-client', version: '1.0.0'),
      );

      final uri = Uri.parse(config.url);
      
      // We pass headers to the transport options via requestInit
      connection.transport = StreamableHttpClientTransport(
        uri,
        opts: StreamableHttpClientTransportOptions(
          requestInit: {
            'headers': config.headers,
          },
        ),
      );

      await connection.client!.connect(connection.transport!).timeout(const Duration(seconds: 15));
      
      final toolsResult = await connection.client!.listTools();
      connection.tools = toolsResult.tools;
      
      notifyListeners();
      debugPrint('Connected to MCP Server successfully: ${config.url}');
    } catch (e) {
      debugPrint('Failed to connect to MCP Server ${config.url}: $e');
      _connections.remove(config.id);
      notifyListeners();
      rethrow;
    }
  }
  
  Future<void> disconnectServer(String id) async {
    final connection = _connections.remove(id);
    if (connection != null && connection.transport != null) {
      try {
        await connection.transport!.close();
      } catch (e) {
        debugPrint('Error closing transport: $e');
      }
    }
    notifyListeners();
  }
  
  void updateConfig(McpServerConfig config) {
    if (_connections.containsKey(config.id)) {
      _connections[config.id]!.config = config;
      notifyListeners();
    }
  }

  Future<List<Tool>> getAllAvailableTools() async {
    final allTools = <Tool>[];
    for (final connection in _connections.values) {
      if (connection.config.enabled && connection.tools != null) {
        allTools.addAll(connection.tools!);
      }
    }
    return allTools;
  }
  
  Future<dynamic> callTool(String name, Map<String, dynamic> args) async {
    // Find which server has this tool
    for (final connection in _connections.values) {
      if (!connection.config.enabled || connection.tools == null || connection.client == null) continue;
      final tool = connection.tools!.where((t) => t.name == name).firstOrNull;
      if (tool != null) {
        final params = CallToolRequest(name: name, arguments: args);
        return await connection.client!.callTool(params);
      }
    }
    throw Exception('Tool $name not found on any connected MCP server');
  }
  
  @override
  void dispose() {
    for (final connection in _connections.values) {
      try {
        connection.transport?.close();
      } catch (_) {}
    }
    _connections.clear();
    super.dispose();
  }
}
