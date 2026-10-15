import 'package:bujuan/common/netease_api/src/api/play/bean.dart';
import 'package:bujuan/pages/user/personal_landscape.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'wide_remote_test.dart' as fixture;

void main() {
  for (final size in [
    const Size(844, 390),
    const Size(640, 300),
    const Size(1280, 800)
  ]) {
    testWidgets(
        'three columns and original shortcuts fit beside cards at $size',
        (tester) async {
      var fm = 0;
      Play? opened;
      final liked = Play()
        ..id = 'liked'
        ..name = '喜欢的音乐'
        ..trackCount = 23;
      await fixture.mount(
          tester,
          PersonalLandscape(
              nickname: '测试用户',
              avatar: '',
              liked: liked,
              playlists: List.generate(
                  10,
                  (i) => Play()
                    ..id = '$i'
                    ..name = '收藏歌单 $i'
                    ..trackCount = 10),
              actions: [
                PersonalAction('每日', TablerIcons.calendar, () {}),
                PersonalAction('FM', TablerIcons.vinyl, () => fm++),
                PersonalAction('播客', TablerIcons.brand_apple_podcast, () {}),
                PersonalAction('云盘', TablerIcons.cloud_fog, () {})
              ],
              onPlaylist: (p) => opened = p,
              onManage: () {},
              onAvatar: () {},
              onSearch: () {}),
          size: size);
      expect(tester.takeException(), isNull);
      final cardRect =
          tester.getRect(find.byKey(const ValueKey('personal-list:liked')));
      expect(cardRect.height, closeTo(112 * .8, .001));
      // Move left by a third of the previous remaining 19.25px gap; preserve
      // card width and the fixed search/shortcut column on every screen size.
      const shift = 19.25 - 19.25 / 3;
      expect(cardRect.left, closeTo(6 + shift, .01));
      expect(cardRect.width, closeTo((size.width - 122) / 3, .01));
      expect(tester.getCenter(find.byKey(const ValueKey('personal-avatar'))).dx,
          closeTo(34 + shift, .01));
      final actionRect =
          tester.getRect(find.byKey(const ValueKey('personal-action:FM')));
      expect(
          actionRect.left,
          greaterThan(tester
              .getRect(find.byKey(const ValueKey('personal-list:1')))
              .right));
      final lastCard =
          tester.getRect(find.byKey(const ValueKey('personal-list:1')));
      expect(tester.getRect(find.text('查看/管理')).right,
          closeTo(lastCard.right, .01));
      expect(lastCard.right, closeTo(size.width - 96 + shift, .01));
      expect(tester.getCenter(find.byKey(const ValueKey('personal-search'))).dx,
          closeTo(size.width - 45, .01));
      expect(actionRect.width, greaterThanOrEqualTo(48));
      expect(
          tester.getCenter(find.byKey(const ValueKey('personal-search'))).dx,
          closeTo(
              tester
                  .getCenter(find.byKey(const ValueKey('personal-action:每日')))
                  .dx,
              .01));
      final grid = tester.widget<GridView>(find.byType(GridView));
      expect(grid.scrollDirection, Axis.vertical);
      expect(
          (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
              .crossAxisCount,
          3);
      await tester.tap(find.byKey(const ValueKey('personal-list:liked')));
      expect(opened, same(liked));
      // The right edge must still be tappable after moving the last card.
      await tester.tapAt(Offset(lastCard.right - 1, lastCard.center.dy));
      expect(opened?.id, '1');
      await tester.tap(find.byKey(const ValueKey('personal-action:FM')));
      expect(fm, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
