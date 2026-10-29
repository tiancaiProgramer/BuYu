import '../../common/app_style.dart';
import '../music/mixed_search_view.dart';
import '../music/source_access.dart';
import '../../common/music/mixed_search.dart';
import 'package:auto_route/auto_route.dart';
import 'package:bujuan/widget/my_get_view.dart';
import 'package:bujuan/widget/request_widget/request_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../common/netease_api/src/api/play/bean.dart';
import '../../common/netease_api/src/api/search/bean.dart';
import '../../common/netease_api/src/dio_ext.dart';
import '../../common/netease_api/src/netease_handler.dart';
import '../../widget/app_bar.dart';
import '../../widget/custom_filed.dart';
import '../../widget/mobile/flashy_navbar.dart';
import '../../widget/request_widget/request_loadmore_view.dart';
import '../play_list/playlist_view.dart';

class SearchView extends StatefulWidget {
  const SearchView({Key? key, this.songSearch}) : super(key: key);
  final MixedSearch? songSearch;

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> with TickerProviderStateMixin {
  late final SourceAccess _access;
  final TextEditingController _search = TextEditingController();
  final PageController _pageController = PageController();
  List<FlashyNavbarItem> items = [
    FlashyNavbarItem(icon: const Icon(TablerIcons.brand_tiktok)),
    FlashyNavbarItem(icon: const Icon(TablerIcons.playlist)),
    FlashyNavbarItem(icon: const Icon(TablerIcons.disc)),
    FlashyNavbarItem(icon: const Icon(TablerIcons.users)),
  ];
  List<Tab> get tabs => [
        Tab(
          text: _access.sources.length > 1 ? '双源单曲' : '单曲',
        ),
        if (_access.visibility.showNetease)
          const Tab(
            text: '网易歌单',
          ),
        if (_access.visibility.showNetease)
          const Tab(
            text: '网易专辑',
          ),
        if (_access.visibility.showNetease)
          const Tab(
            text: '网易歌手',
          ),
      ];
  TabController? _tabController;

  String searchContent = '';

  DioMetaData searchSongDioMetaData(String keyword, int type,
      {bool cloudSearch = true, int offset = 0, int limit = 30}) {
    var params = {'s': keyword, 'type': type, 'limit': limit, 'offset': offset};
    return DioMetaData(_searchUrl(cloudSearch),
        data: params, options: joinOptions());
  }

  DioMetaData searchHotKeyDioMetaData() {
    return DioMetaData(joinUri('/weapi/search/hot'),
        data: {'type': 1111},
        options: joinOptions(userAgent: UserAgent.Mobile));
  }

  Uri _searchUrl(bool cloudSearch) => cloudSearch
      ? joinUri('/weapi/cloudsearch/pc')
      : joinUri('/weapi/search/get');

  @override
  void initState() {
    super.initState();
    _access = SourceAccess()..addListener(_accountsChanged);
    _search.addListener(listener);
    _tabController = TabController(length: tabs.length, vsync: this);
  }

  void _accountsChanged() {
    if (!mounted) return;
    setState(() {
      if (_tabController!.length != tabs.length) {
        final previous = _tabController!;
        _tabController = TabController(length: tabs.length, vsync: this);
        previous.dispose();
      }
    });
  }

  listener() {
    if (_search.text.isEmpty) {
      setState(() {
        searchContent = '';
      });
    }
  }

  @override
  void dispose() {
    _access.removeListener(_accountsChanged);
    _access.dispose();
    _search.removeListener(listener);
    _search.dispose();
    _pageController.dispose();
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MyGetView(
        child: Scaffold(
      // This route is opaque. Paint its background during the transition too,
      // so the previous page cannot show through the search field or body.
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      resizeToAvoidBottomInset: false,
      appBar: MyAppBar(
        backgroundColor: Colors.transparent,
        leadingWidth: 0.w,
        leading: const SizedBox.shrink(),
        title: CustomFiled(
          iconData: TablerIcons.search,
          textEditingController: _search,
          hitText: '输入歌曲、歌手、歌单...',
          textInputAction: TextInputAction.search,
          onSubmitted: (String value) {
            if (value.isNotEmpty) {
              searchContent = value;
              setState(() {});
            }
          },
        ),
        actions: [
          IconButton(
            onPressed: () {
              AutoRouter.of(context).pop();
            },
            icon: const Icon(TablerIcons.x),
            iconSize: 54.w,
          )
        ],
      ),
      body: Visibility(
          visible: searchContent.isNotEmpty,
          replacement: !_access.visibility.showNetease
              ? Center(
                  child: Text(_access.sources.isEmpty
                      ? '暂无已登录的平台，请先登录音乐账号'
                      : '输入关键词搜索QQ音乐'))
              : RequestWidget<SearchKeyWrapX>(
                  dioMetaData: searchHotKeyDioMetaData(),
                  childBuilder: (data) => Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 30.w, vertical: 30.w),
                        child: Wrap(
                          children: data.result.hots
                              .map((e) => InkWell(
                                    child: Container(
                                      margin: EdgeInsets.symmetric(
                                          horizontal: 6.w, vertical: 15.w),
                                      padding: EdgeInsets.symmetric(
                                          vertical: 5.w, horizontal: 10.w),
                                      decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSecondary,
                                          borderRadius:
                                              BorderRadius.circular(30.w)),
                                      child: Text(
                                        e.first ?? '',
                                        style: TextStyle(fontSize: 26.sp),
                                      ),
                                    ),
                                    onTap: () {
                                      _search.text = e.first ?? '';
                                      searchContent = _search.text;
                                      setState(() {});
                                    },
                                  ))
                              .toList(),
                        ),
                      )),
          child: Column(
            children: [
              TabBar(
                tabs: tabs,
                controller: _tabController,
                labelColor: BuYuStyle.action(Theme.of(context)),
                unselectedLabelColor: Theme.of(context).iconTheme.color,
                indicatorSize: TabBarIndicatorSize.label,
                indicatorColor: Theme.of(context).primaryColor,
                indicatorPadding:
                    EdgeInsets.symmetric(horizontal: 15.w, vertical: 0),
              ),
              Expanded(
                  child: TabBarView(
                controller: _tabController,
                children: [
                  _buildSongSearchView(),
                  if (_access.visibility.showNetease)
                    _buildPlayListSearchView(),
                  if (_access.visibility.showNetease) _buildAlbumSearchView(),
                  if (_access.visibility.showNetease) _buildArtistsSearchView(),
                ],
              )),
            ],
          )),
    ));
  }

  Widget _buildSongSearchView() =>
      MixedSongSearchView(query: searchContent, search: widget.songSearch);

  Widget _buildPlayListSearchView() {
    return RequestLoadMoreWidget<SearchPlaylistWrapX, Play>(
      dioMetaData: searchSongDioMetaData(searchContent, 1000),
      childBuilder: (List<Play> playlist) {
        return ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          itemExtent: 120.w,
          itemBuilder: (context, index) => PlayListItem(play: playlist[index]),
          itemCount: playlist.length,
        );
      },
      listKey: const ['result', 'playlists'],
    );
  }

  Widget _buildAlbumSearchView() {
    return RequestLoadMoreWidget<SearchAlbumsWrapX, Album>(
      dioMetaData: searchSongDioMetaData(searchContent, 10),
      childBuilder: (List<Album> playlist) {
        return ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          itemExtent: 120.w,
          itemBuilder: (context, index) =>
              AlbumItem(index: index, album: playlist[index]),
          itemCount: playlist.length,
        );
      },
      listKey: const ['result', 'albums'],
    );
  }

  Widget _buildArtistsSearchView() {
    return RequestLoadMoreWidget<SearchArtistsWrapX, Artists>(
      dioMetaData: searchSongDioMetaData(searchContent, 100),
      childBuilder: (List<Artists> playlist) {
        return ListView.builder(
          itemExtent: 120.w,
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          itemBuilder: (context, index) =>
              ArtistsItem(index: index, artists: playlist[index]),
          itemCount: playlist.length,
        );
      },
      listKey: const ['result', 'artists'],
    );
  }
}
