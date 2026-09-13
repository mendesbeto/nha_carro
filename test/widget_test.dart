import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nhacarro/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app starts on registration screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const NhaCarroApp());
    await tester.pumpAndSettle();

    expect(find.text('Crie a sua conta'), findsOneWidget);
    expect(
        find.text(
            'Escolha o perfil que melhor se encaixa no seu uso do NhaCarro.'),
        findsOneWidget);
  });
}
