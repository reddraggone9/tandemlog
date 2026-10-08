import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../lib/activation.dart';

void main(List<String> args) {
  final directory = Directory(args.single);
  final lab = ActivationLab(
    name: 'fresh-process',
    writer: '22222222-2222-4222-8222-222222222222',
    config: const LabConfig(
      space: '11111111-1111-4111-8111-111111111111',
      issuer: '22222222-2222-4222-8222-222222222222',
      activationRef: 'owner-baseline-1',
    ),
    directory: directory,
    nowNs: () => BigInt.from(1000),
  );
  stdout.writeln(
    jsonEncode({
      'title': lab.text('66666666-6666-4666-8666-666666666666', 'title'),
      'canonicalSha256': sha256
          .convert(File('${directory.path}/records.jsonl').readAsBytesSync())
          .toString(),
    }),
  );
  lab.close();
}
