import 'package:p2p_messenger/api/classes/interfaces.dart';
import 'package:p2p_messenger/api/models/message.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class FileStorage implements IFileStorage {
  @override
  Future<String> uploadFile(String fileName, List<int> bytes) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  @override
  Future<List<int>> downloadFile(String fileUrl) async {
    final file = File(fileUrl);
    return await file.readAsBytes();
  }

  @override
  Future<void> deleteFile(String fileUrl) async {
    final file = File(fileUrl);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<List<String>> uploadFiles(List<FileAttachment> attachments) async {
    return await Future.wait(attachments.map((a) async => await uploadFile(a.fileName, a.content)));
  }
}