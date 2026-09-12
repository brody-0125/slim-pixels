import 'dart:io';
import 'dart:typed_data';

import 'package:slim_pixels/slim_pixels.dart';

void main(List<String> args) {
  final slim = SlimPixels(args[0]);
  final input = File(args[1]).readAsBytesSync();
  final jpeg = slim.transform(input, {
    'operations': [],
    'format': 'jpeg',
    'quality': 90,
  });
  final golden = File(
    '${File(args[1]).parent.path}/rgb-q90.jpg',
  ).readAsBytesSync();
  if (jpeg.length != golden.length)
    throw StateError('JPEG golden size differs');
  for (var i = 0; i < jpeg.length; i++) {
    if (jpeg[i] != golden[i]) throw StateError('JPEG golden bytes differ');
  }
  var boundaryFailures = 0;
  try {
    slim.transform(Uint8List(0), {});
  } on ArgumentError {
    boundaryFailures++;
  }
  try {
    slim.transform(input, {'padding': 'x' * 65537});
  } on ArgumentError {
    boundaryFailures++;
  }
  if (boundaryFailures != 2) {
    throw StateError('Dart input/request boundary validation failed');
  }
  final invalid = <Map<String, Object?>>[
    {
      'operations': [
        {
          'resize': {'width': 0, 'height': 4, 'filter': 'lanczos3'},
        },
      ],
      'format': 'png',
      'quality': 90,
    },
    {
      'operations': [
        {
          'crop': {'x': 999999, 'y': 0, 'width': 2, 'height': 2},
        },
      ],
      'format': 'png',
      'quality': 90,
    },
    {
      'operations': [
        {
          'resize': {'width': 4, 'height': 4, 'filter': 'unknown'},
        },
      ],
      'format': 'png',
      'quality': 90,
    },
    {'operations': [], 'format': 'jpeg', 'quality': 0},
    {
      'operations': ['unknown'],
      'format': 'png',
      'quality': 90,
    },
  ];
  var failures = 0;
  for (final req in invalid) {
    try {
      slim.transform(input, req);
    } on StateError {
      failures++;
    }
  }
  if (failures != invalid.length)
    throw StateError('Expected ${invalid.length} failures, got $failures');
  final plan = <String, Object?>{
    'operations': [
      {
        'crop': {'x': 1, 'y': 2, 'width': 12, 'height': 10},
      },
      {
        'resize': {'width': 6, 'height': 5, 'filter': 'lanczos3'},
      },
      'rotate90',
      'flip_horizontal',
    ],
    'format': 'png',
    'quality': 90,
  };
  final a = slim.transform(input, plan),
      b = slim.transform(input, {...plan, 'scalar': true});
  if (a.length != b.length) throw StateError('SIMD/scalar length mismatch');
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) throw StateError('SIMD/scalar output mismatch');
  }
  final header = ByteData.sublistView(a);
  if (header.getUint32(16) != 5 || header.getUint32(20) != 6)
    throw StateError('Pipeline dimensions differ');
  for (var i = 0; i < 1000; i++) {
    slim.transform(input, plan);
  }
  stdout.writeln(
    'PASS: five invalid requests, valid request after failures, geometry dimensions, SIMD/scalar equality, 1000 create-copy-free cycles.',
  );
}
