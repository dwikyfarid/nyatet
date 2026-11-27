import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/main_play.dart' as play;
import 'package:nyatet/main_sideload.dart' as sideload;

/// D-38/REL-04: build yang salah tidak boleh "lolos" jadi build Play.
/// Kalau ada yang membalik konstanta ini, uji gagal sebelum dirilis.
void main() {
  test('build play mematikan cek update, build sideload menyalakannya', () {
    expect(play.kUpdateCheckerEnabled, isFalse);
    expect(sideload.kUpdateCheckerEnabled, isTrue);
  });
}
