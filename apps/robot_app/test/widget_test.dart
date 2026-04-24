import 'package:flutter_test/flutter_test.dart';
import 'package:robot_app/main.dart';

void main() {
  testWidgets('RobotDogApp renders BLE entry', (WidgetTester tester) async {
    await tester.pumpWidget(const RobotDogApp());

    expect(find.text('Robot OS Lite'), findsOneWidget);
    expect(find.text('连接机器人 (BLE)'), findsOneWidget);
    expect(find.text('快捷控制'), findsOneWidget);
    expect(find.text('最近收到的数据'), findsOneWidget);
    expect(find.text('未连接'), findsWidgets);
  });
}
