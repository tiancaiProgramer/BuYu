// Community maintenance and new features: tiancaiProgramer.
import 'dart:convert';
import 'dart:typed_data';
import 'package:bujuan/common/netease_api/src/api/user/api.dart';
import 'package:bujuan/common/netease_api/src/dio_ext.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class WebApi with ApiUser {}
class RenameAdapter implements HttpClientAdapter {
  final paths=<String>[];
  final bodies=<dynamic>[];
  int firstCode=403;
  @override Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body, Future? cancel) async {
    paths.add(options.uri.path);bodies.add(options.data);
    final data=paths.length==1?{'code':firstCode}:{'code':200,'/api/playlist/update/name':{'code':200}};
    return ResponseBody.fromString(jsonEncode(data),200,headers:{Headers.contentTypeHeader:['application/json']});
  }
  @override void close({bool force=false}) {}
}
void main(){
  test('web rename rejection uses name-only batch with safely encoded quoted name',()async{
    final old=Https.dio.httpClientAdapter,adapter=RenameAdapter();Https.dio.httpClientAdapter=adapter;
    addTearDown(()=>Https.dio.httpClientAdapter=old);
    final result=await WebApi().updateUserPlayListName('123','带 "引号" 的名字');
    expect(result.code,200);expect(adapter.paths,['/weapi/playlist/update/name','/weapi/batch']);
    final data=adapter.bodies.last as Map;
    expect(data.keys,['/api/playlist/update/name']);
    expect(jsonDecode(data.values.single as String),{'id':'123','name':'带 "引号" 的名字'});
  });
  test('successful standalone rename does not send a second write',()async{
    final old=Https.dio.httpClientAdapter,adapter=RenameAdapter()..firstCode=200;Https.dio.httpClientAdapter=adapter;
    addTearDown(()=>Https.dio.httpClientAdapter=old);
    expect((await WebApi().updateUserPlayListName('123','new')).code,200);
    expect(adapter.paths.length,1);
  });
}
