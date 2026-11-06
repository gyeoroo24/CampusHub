import 'package:campus_hub/core/widgets/filter_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('changes are a draft until Show results; Reset goes back to the defaults', (tester) async {
    Set<String>? applied;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => FiltersButton(
          activeCount: 1,
          onPressed: () => showFilterSheet<Set<String>>(
            context,
            title: 'Filter listings',
            initial: {'Books'},
            defaults: {'All'},
            onApply: (v) => applied = v,
            sections: (context, draft, update) => [
              FilterSection(
                title: 'Category',
                child: FilterChoices<String>(
                  options: const [
                    (value: 'All', label: 'All', icon: null),
                    (value: 'Books', label: 'Books', icon: null),
                    (value: 'Cycles', label: 'Cycles', icon: null),
                  ],
                  selected: draft,
                  onTap: (c) => update({c}),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    expect(find.text('Filters (1)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('filters_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cycles'));
    await tester.pump();
    expect(applied, isNull); // nothing changes until applying

    await tester.tap(find.byKey(const Key('filter_sheet_reset')));
    await tester.pump();
    expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'All')).selected, isTrue);

    await tester.tap(find.text('Cycles'));
    await tester.tap(find.byKey(const Key('filter_sheet_apply')));
    await tester.pumpAndSettle();
    expect(applied, {'Cycles'});
    expect(find.text('Filter listings'), findsNothing);
  });
}
