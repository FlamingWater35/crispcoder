import 'package:crispcoder/features/logs/logs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    LogsScreen.clear();
  });

  testWidgets('shows empty state when no logs', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LogsScreen()));

    expect(find.text('No log output yet.'), findsOneWidget);
    expect(find.byType(Scrollbar), findsNothing);
  });

  testWidgets('renders log entries from buffer', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LogsScreen()));

    LogsScreen.push('12:00:00.000\nSome message here');
    // Pump in small steps so the 100ms debounce timer fires
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('12:00:00.000'), findsOneWidget);
    expect(find.text('Some message here'), findsOneWidget);
    expect(find.byType(Scrollbar), findsOneWidget);
  });

  testWidgets('clear empties the buffer and cancels pending debounce',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LogsScreen()));

    LogsScreen.push('12:00:00.000 First');
    // Immediately clear BEFORE the 100ms debounce fires
    LogsScreen.clear();

    expect(find.text('No log output yet.'), findsOneWidget);

    // Advance time past the debounce: buffer must stay empty (timer canceled)
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('No log output yet.'), findsOneWidget);
  });

  testWidgets('search filters log entries', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LogsScreen()));

    LogsScreen.push('12:00:00.000\nalpha message');
    LogsScreen.push('12:00:01.000\nbeta message');
    await tester.pump(const Duration(milliseconds: 150));

    expect(find.text('alpha message'), findsOneWidget);
    expect(find.text('beta message'), findsOneWidget);

    await tester.enterText(find.byType(SearchBar), 'alpha');
    await tester.pump();

    expect(find.text('alpha message'), findsOneWidget);
    expect(find.text('beta message'), findsNothing);
  });

  testWidgets('jump-to-bottom FAB appears when scrolled away from bottom',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LogsScreen()));

    // Many entries so the list scrolls
    for (var i = 0; i < 100; i++) {
      LogsScreen.push('12:00:00.000\nmessage number $i');
    }
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();

    // Initially no scroll → FAB hidden
    expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);

    // Scroll down a little (not to bottom) → FAB appears
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);

    // Scroll to bottom → FAB hides
    await tester.drag(find.byType(ListView), const Offset(0, -10000));
    await tester.pump();
    expect(find.byIcon(Icons.arrow_downward_rounded), findsNothing);
  });
}
