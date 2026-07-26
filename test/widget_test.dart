import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_train/main.dart';

void main() {
  testWidgets('MyTrainApp smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ProviderScope(child: MyTrainApp()));
    expect(find.byType(MyTrainApp), findsOneWidget);
  });
}
