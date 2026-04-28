import 'package:flutter_test/flutter_test.dart';
import 'package:rpg_puc_survival/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RpgPucSurvivalApp());
    expect(find.byType(RpgPucSurvivalApp), findsOneWidget);
  });
}
