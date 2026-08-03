// Deriving a readable train name from a provider abbreviation.
//
// This produces a DERIVED name, not the railway's. `YPR TVCN GR EXP` is the whole
// value RailKit returns for 12257 and the whole value on the ticket; there is no
// longer form to fetch, and 12257 is not in the local train catalog either.
//
// The all-or-nothing station rule is the load-bearing part. `TVCN` and `SMVB` are
// genuinely absent from the 8,989-entry station catalog, so a per-token expansion
// would print "Yesvantpur Jn TVCN Garib Rath Express" — which reads as a typo
// rather than as a code left alone.
import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/utils/train_name.dart';

/// Stands in for the real catalog. TVCN and SMVB are absent here because they are
/// absent there.
String? catalog(String code) => const {
      'YPR': 'Yesvantpur Jn',
      'KYJ': 'Kayankulam Jn',
      'TVC': 'Trivandrum Central',
      'CAPE': 'Kanyakumari',
      'SBC': 'Bangalore City Jn',
      'LTT': 'Lokmanya Tilak Term',
      'MYS': 'Mysore Jn',
      'NDLS': 'New Delhi',
      'BCT': 'Mumbai Central',
    }[code];

void main() {
  group('abbreviation expansion only', () {
    test('the real 12257 name, with no catalog', () {
      expect(expandTrainName('YPR TVCN GR EXP'),
          'YPR TVCN Garib Rath Express');
    });

    test('common suffixes', () {
      expect(expandTrainName('TVC LTT EXP'), 'TVC LTT Express');
      expect(expandTrainName('TVCN SMVB SPL'), 'TVCN SMVB Special');
      expect(expandTrainName('QLN UBL SPL'), 'QLN UBL Special');
    });

    test('names already readable are left alone', () {
      // Null, not the same string back — the caller omits the line entirely.
      expect(expandTrainName('CAPE SBC EXPRESS'), isNull);
      expect(expandTrainName('MUMBAI RAJDHANI'), isNull);
      expect(expandTrainName(''), isNull);
      expect(expandTrainName('   '), isNull);
    });
  });

  group('station expansion is all-or-nothing', () {
    test('every code resolving gives the full readable form', () {
      expect(
        expandTrainName('TVC LTT EXP', station: catalog),
        'Trivandrum Central – Lokmanya Tilak Term Express',
      );
    });

    test('ONE missing code leaves every code alone', () {
      // TVCN is not in the catalog. The half-expanded
      // "Yesvantpur Jn TVCN Garib Rath Express" must not be produced.
      final out = expandTrainName('YPR TVCN GR EXP', station: catalog)!;
      expect(out, 'YPR TVCN Garib Rath Express');
      expect(out, isNot(contains('Yesvantpur')));
    });

    test('a name with no leading codes is unaffected by the catalog', () {
      expect(expandTrainName('MUMBAI RAJDHANI', station: catalog), isNull);
    });

    test('the code run stops at the first non-code token', () {
      // Only the leading run is treated as codes; GR is an abbreviation, not a
      // station, so it terminates the run rather than being looked up.
      expect(
        expandTrainName('YPR KYJ GR EXP', station: catalog),
        'Yesvantpur Jn – Kayankulam Jn Garib Rath Express',
      );
    });

    test('a single leading code still expands', () {
      expect(expandTrainName('NDLS EXP', station: catalog),
          'New Delhi Express');
    });
  });

  group('nothing is invented', () {
    test('unknown abbreviations pass through untouched', () {
      expect(expandTrainName('YPR ZZQ EXP'), 'YPR ZZQ Express');
    });

    test('a name of only unknown tokens yields null, not a guess', () {
      expect(expandTrainName('ZZQ QQZ'), isNull);
    });

    test('an abbreviation is never applied to a longer word containing it', () {
      // 'EXPO' must not become 'Expresso' or match EXP.
      expect(expandTrainName('YPR EXPO'), isNull);
    });

    test('lowercase input is handled without mangling the output', () {
      expect(expandTrainName('ypr tvcn gr exp'), isNotNull);
      expect(expandTrainName('ypr tvcn gr exp'), contains('Garib Rath'));
    });
  });
}
