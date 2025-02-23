// Copyright (c) 2022, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

Future<void> _buildLib(String input, String output) async {
  final args = [
    '-shared',
    '-fpic',
    '-x',
    'objective-c',
    input,
    '-framework',
    'Foundation',
    '-o',
    output,
  ];
  final process = await Process.start('clang', args);
  unawaited(stdout.addStream(process.stdout));
  unawaited(stderr.addStream(process.stderr));
  final result = await process.exitCode;
  if (result != 0) {
    throw ProcessException('clang', args, 'Build failed', result);
  }
  print('Generated file: $output');
}

Future<void> _buildSwift(
    String input, String outputHeader, String outputLib) async {
  final args = [
    '-c',
    input,
    '-emit-objc-header-path',
    outputHeader,
    '-emit-library',
    '-o',
    outputLib,
  ];
  final process = await Process.start('swiftc', args);
  unawaited(stdout.addStream(process.stdout));
  unawaited(stderr.addStream(process.stderr));
  final result = await process.exitCode;
  if (result != 0) {
    throw ProcessException('swiftc', args, 'Build failed', result);
  }
  print('Generated files: $outputHeader and $outputLib');
}

Future<void> _generateBindings(String config) async {
  final args = [
    'run',
    'ffigen',
    '--config',
    'test/native_objc_test/$config',
  ];
  final process =
      await Process.start(Platform.executable, args, workingDirectory: '../..');
  unawaited(stdout.addStream(process.stdout));
  unawaited(stderr.addStream(process.stderr));
  final result = await process.exitCode;
  if (result != 0) {
    throw ProcessException('dart', args, 'Generating bindings', result);
  }
  print('Generated bindings for: $config');
}

List<String> _getTestNames() {
  const configSuffix = '_config.yaml';
  final names = <String>[];
  for (final entity in Directory.current.listSync()) {
    final filename = entity.uri.pathSegments.last;
    if (filename.endsWith(configSuffix)) {
      names.add(filename.substring(0, filename.length - configSuffix.length));
    }
  }
  return names;
}

Future<void> build(List<String> testNames) async {
  print('Building Dynamic Library for Objective C Native Tests...');
  for (final name in testNames) {
    final mFile = '${name}_test.m';
    if (await File(mFile).exists()) {
      await _buildLib(mFile, '${name}_test.dylib');
    }
  }

  print('Building Dynamic Library and Header for Swift Tests...');
  for (final name in testNames) {
    final swiftFile = '${name}_test.swift';
    if (await File(swiftFile).exists()) {
      await _buildSwift(
          swiftFile, '${name}_test-Swift.h', '${name}_test.dylib');
    }
  }

  print('Generating Bindings for Objective C Native Tests...');
  for (final name in testNames) {
    await _generateBindings('${name}_config.yaml');
  }
}

Future<void> clean(List<String> testNames) async {
  print('Deleting generated and built files...');
  final filenames = [
    for (final name in testNames) ...[
      '${name}_bindings.dart',
      '${name}_test_bindings.dart',
      '${name}_test.dylib'
    ],
  ];
  Future.wait(filenames.map((fileName) async {
    final file = File(fileName);
    final exists = await file.exists();
    if (exists) await file.delete();
  }));
}

Future<void> main(List<String> arguments) async {
  if (!Platform.isMacOS) {
    throw OSError('Objective C tests are only supported on MacOS');
  }

  if (arguments.isNotEmpty && arguments[0] == 'clean') {
    return await clean(_getTestNames());
  }

  return await build(arguments.isNotEmpty ? arguments : _getTestNames());
}
