import 'package:flutter_test/flutter_test.dart';
import 'package:robot_app/main.dart';

void main() {
  testWidgets('RobotDogApp boots', (tester) async {
    await tester.pumpWidget(const RobotDogApp());

    expect(find.text('Robot OS Lite'), findsOneWidget);
    expect(find.text('机器狗控制台 / 图形化动作编排'), findsOneWidget);
    expect(find.text('快捷控制'), findsOneWidget);
  });
}
