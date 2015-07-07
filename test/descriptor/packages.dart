// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Pub-specific scheduled_test descriptors.
library descriptor.packages_file;

import "dart:io" show File;
import "dart:async" show Future;
import "dart:convert" show UTF8;

import 'package:package_config/packages_file.dart' as packages_file;
import 'package:path/path.dart' as p;
import 'package:scheduled_test/descriptor.dart';
import 'package:scheduled_test/scheduled_test.dart';

import '../test_pub.dart';

/// Describes a `.packages` file and its contents.
class PackagesFileDescriptor extends Descriptor {
  // RegExp recognizing semantic version numbers.
  static final _semverRE =
      new RegExp(r"^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)"
                r"(?:-[a-zA-Z\d-]+)?(?:\+[a-zA-Z\d-]+)?$");

  /// A map from package names to strings describing where the packages are
  /// located on disk.
  final Map<String, String> _dependencies;

  /// Describes a `.packages` file with the given dependencies.
  ///
  /// [dependencies] maps package names to strings describing where the packages
  /// are located on disk.
  PackagesFileDescriptor([this._dependencies]) : super('.packages');

  Future create([String parent]) => schedule(() {
    if (parent == null) parent = defaultRoot;
    var contents = const <int>[];
    if (_dependencies != null) {
      var mapping = {};
      _dependencies.forEach((package, version) {
        var packagePath;
        if (_semverRE.hasMatch(version)) {
          // If it's a semver, it's a cache reference.
          packagePath = p.join(cachePath, "$package-$version");
        } else {
          // Otherwise it's a path relative to the .pubspec file,
          // which is also the relative path wrt. the .packages file.
          packagePath = p.fromUri(version);
        }
        mapping[package] = p.toUri(p.join(packagePath, "lib", ""));
      });
      var buffer = new StringBuffer();
      packages_file.write(buffer, mapping);
      contents = UTF8.encode(buffer.toString());
    }
    return new File(p.join(parent, name)).writeAsBytes(contents);
  }, "creating file '$name'");

  Future validate([String parent]) =>
    schedule(() => validateNow(parent), "validating file '$name'");

  Future validateNow([String parent]) {
    // Copied from FileDescriptor in scheduled_test.
    if (parent == null) parent = defaultRoot;
    var fullPath = p.join(parent, name);
    if (!new File(fullPath).existsSync()) {
      fail("File not found: '$fullPath'.");
    }
    return new File(fullPath).readAsBytes()
        .then((bytes) => _validateNow(bytes, fullPath));
  }

  /// A function that throws an error if [binaryContents] doesn't match the
  /// expected contents of the descriptor.
  void _validateNow(List<int> binaryContents, String fullPath) {
    var fileUri = p.toUri(fullPath);
    var map = packages_file.parse(binaryContents, fileUri);

    for (var package in _dependencies.keys) {
      if (!map.containsKey(package)) {
        fail(".packages does not contain $package entry");
      }

      var description = _dependencies[package];
      if (_semverRE.hasMatch(description)) {
        if (!map[package].path.contains(description)) {
          fail(".packages of $package has incorrect version. "
               "Expected $description, found location: ${map[package]}.");
        }
      } else {
        var expected = p.normalize(p.join(
            p.dirname(fullPath), p.fromUri(description), 'lib'));
        expected = new File(expected).resolveSymbolicLinksSync();
        var actual = new File(p.normalize(p.absolute(p.fromUri(map[package]))))
            .resolveSymbolicLinksSync();

        if (expected != actual) {
          fail("Relative path: Expected $description, found ${map[package]}");
        }
      }
    }

    if (map.length != _dependencies.length) {
      for (var key in map.keys) {
        if (!_dependencies.containsKey(key)) {
          fail(".packages file contains unexpected entry: $key");
        }
      }
    }
  }

  String describe() => name;
}
