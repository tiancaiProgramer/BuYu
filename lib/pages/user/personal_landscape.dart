import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import '../../common/netease_api/src/api/play/bean.dart';
import '../../widget/simple_extended_image.dart';

class PersonalAction {
  const PersonalAction(this.title, this.icon, this.onPressed);
  final String title;
  final IconData icon;
  final VoidCallback onPressed;
}

/// Repositions the existing shortcuts without changing the portrait page.
class PersonalLandscape extends StatelessWidget {
  // Move back left by a third of the previous remaining gap, while keeping
  // card sizes and the search/shortcut centre 45px from the right unchanged.
  static const _contentShift = (14 + (74 - 25) / 2) / 3;
  static const _railWidth = 48.0;
  static const _railRight = 8 + (74 - _railWidth) / 2;
  static const _remainingGap = 14 + (74 - _railWidth) / 2 - _contentShift;
  static const _gridRight = 8 + 6 + (74 - _railWidth) / 2 - _contentShift;

  const PersonalLandscape(
      {super.key,
      required this.nickname,
      required this.avatar,
      required this.liked,
      required this.playlists,
      required this.actions,
      required this.onPlaylist,
      required this.onManage,
      required this.onAvatar,
      required this.onSearch});
  final String nickname, avatar;
  final Play liked;
  final List<Play> playlists;
  final List<PersonalAction> actions;
  final ValueChanged<Play> onPlaylist;
  final VoidCallback onManage, onAvatar, onSearch;

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
          toolbarHeight: 52,
          leadingWidth: 68 + _contentShift,
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: (Theme.of(context).brightness == Brightness.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: Colors.transparent,
                  systemNavigationBarContrastEnforced: false),
          leading: Padding(
              padding: const EdgeInsets.only(left: _contentShift),
              child: IconButton(
                  key: const ValueKey('personal-avatar'),
                  onPressed: onAvatar,
                  icon: SimpleExtendedImage.avatar(avatar, width: 40))),
          // CJK glyphs sit slightly below the centre of their line box.
          // Align the visible text with the avatar, retaining its font metrics.
          title: Transform.translate(
              offset: const Offset(0, -1),
              child: Text('喜欢的音乐 · 我的歌单',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Theme.of(context).iconTheme.color,
                      fontSize: 17,
                      fontWeight: FontWeight.w600))),
          actions: [
            TextButton(
                key: const ValueKey('personal-manage'),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(64, 48),
                    alignment: Alignment.centerRight,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                onPressed: onManage,
                child: Text('查看/管理',
                    style: TextStyle(
                        color: Theme.of(context).primaryColor, fontSize: 14))),
            const SizedBox(width: _remainingGap),
            SizedBox(
                width: _railWidth,
                child: Center(
                    child: IconButton(
                        key: const ValueKey('personal-search'),
                        onPressed: onSearch,
                        icon: const Icon(TablerIcons.search, size: 25)))),
            const SizedBox(width: _railRight),
          ]),
      body: Row(children: [
        const SizedBox(width: _contentShift),
        Expanded(child: LayoutBuilder(builder: (context, constraints) {
          final lists = [liked, ...playlists];
          return Scrollbar(
              child: GridView.builder(
                  key: const PageStorageKey('user:landscape-grid'),
                  padding: const EdgeInsets.fromLTRB(6, 4, _gridRight, 4),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisExtent: 112 * .8,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 10),
                  itemCount: lists.length,
                  itemBuilder: (_, i) {
                    final list = lists[i];
                    String id;
                    try {
                      id = list.id;
                    } catch (_) {
                      id = '';
                    }
                    return Material(
                        color: Theme.of(context).primaryColor.withOpacity(.045),
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                            key: ValueKey(
                                'personal-list:${id.isEmpty ? i : id}'),
                            borderRadius: BorderRadius.circular(10),
                            onTap: id.isEmpty ? null : () => onPlaylist(list),
                            child: LayoutBuilder(builder: (_, card) {
                              final cover = math.min(
                                  math.max(0.0, card.maxHeight - 24),
                                  math.min(
                                      66.0,
                                      math.max(
                                          32.0, (card.maxWidth - 24) * .32)));
                              return Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(children: [
                                    SimpleExtendedImage(list.coverImgUrl ?? '',
                                        width: cover,
                                        height: cover,
                                        borderRadius: BorderRadius.circular(8),
                                        cacheWidth: 256),
                                    const SizedBox(width: 10),
                                    Expanded(
                                        child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(
                                              i == 0
                                                  ? '喜欢的音乐'
                                                  : list.name ?? '',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 16, height: 1.2)),
                                          const SizedBox(height: 6),
                                          Text('${list.trackCount ?? 0} 首',
                                              maxLines: 1,
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  height: 1.2,
                                                  color: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.color
                                                      ?.withOpacity(.7))),
                                        ])),
                                  ]));
                            })));
                  }));
        })),
        SizedBox(
            width: _railWidth,
            child: Column(children: [
              for (final action in actions)
                Expanded(
                    child: InkWell(
                        key: ValueKey('personal-action:${action.title}'),
                        onTap: action.onPressed,
                        child: Center(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              Icon(action.icon, size: 25),
                              const SizedBox(height: 5),
                              Text(action.title,
                                  style: const TextStyle(
                                      fontSize: 13, height: 1.2)),
                            ])))),
            ])),
        const SizedBox(width: _railRight),
      ]));
}
