import 'package:flutter_test/flutter_test.dart';
import 'package:photon_chat/profanity_filter.dart';

void main() {
  group('filterProfanity', () {
    test('leaves innocent words that contain bad substrings untouched', () {
      const innocent = [
        'tamam', 'zaman', 'amaç', 'adam', 'amca', 'ama', 'hamam', 'kamera',
        'malzeme', 'normal', 'class', 'pass', 'assignment', 'gotten', 'radio',
        'musik', 'sıkıntı', 'sık sık', 'şık', 'kapıcı', 'bokser', 'memeli',
        'babanın evi', 'ananın yemeği', 'ITALYA', 'SIKINTI', 'İstanbul', 'Tamam mı?',
      ];
      for (final w in innocent) {
        expect(filterProfanity(w), w, reason: w);
      }
    });

    test('censors whole profane words with same-length masks', () {
      expect(filterProfanity('sen bir salaksın'), 'sen bir salaksın'); // ek almış hafif hakaret: tam eşleşme değil
      expect(filterProfanity('salak'), '*****');
      expect(filterProfanity('siktir git'), '****** git');
      expect(filterProfanity('siktirgit'), '*********');
      expect(filterProfanity('orospunun'), '*********');
      expect(filterProfanity('AMK'), '***');
      expect(filterProfanity('what the fuck'), 'what the ****');
      expect(filterProfanity('SHIT'), '****');
      expect(filterProfanity('it oğlu'), '*******');
    });

    test('catches leetspeak', () {
      expect(filterProfanity('s1k'), '***');
      expect(filterProfanity('sh1t'), '****');
    });

    test('keeps punctuation and emoji intact', () {
      expect(filterProfanity('selam! 😀 amk.'), 'selam! 😀 ***.');
      expect(filterProfanity(''), '');
    });
  });
}
