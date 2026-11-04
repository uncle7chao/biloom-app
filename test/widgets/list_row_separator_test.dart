// fork 的列表走自有设计（widgets/list_selected.dart），不渲染上游 v0.9.2 的
// iOS 式行分隔线（_ListRowSeparator 只存在于 ui 版 DecorationListItem，fork
// 的行组件不挂它）。上游的分隔线绘制断言在本仓库没有对应实现，整段删除；
// 这里只保留与分隔线无关的通用回归用例。
import 'package:fl_clash/widgets/widgets.dart' hide generateSection;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('a row repainted on its way into the keep-alive bucket settles', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    late StateSetter rebuild;
    await tester.pumpWidget(
      TestApp(
        child: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return CustomScrollView(
                controller: controller,
                slivers: [
                  SliverList(
                    delegate: SliverChildListDelegate(
                      [
                        KeepAlive(
                          keepAlive: true,
                          child: RepaintBoundary(
                            child: DecorationListItem(
                              title: const Text('row 0'),
                              onPressed: () {},
                            ),
                          ),
                        ),
                        const SizedBox(height: 5000),
                      ],
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: false,
                      addSemanticIndexes: false,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    rebuild(() {});
    controller.jumpTo(4000);
    await tester.pump();
    for (
      var frame = 0;
      frame < 5 && tester.binding.hasScheduledFrame;
      frame++
    ) {
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
