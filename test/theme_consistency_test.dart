// Community maintenance and new features: tiancaiProgramer.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:bujuan/common/app_style.dart';
import 'package:bujuan/common/constants/colors.dart';
import 'package:bujuan/pages/music/library_actions.dart';
import 'package:bujuan/widget/adaptive_option_sheet.dart';
import 'package:bujuan/widget/buyu_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for(final dark in [false,true]) for(final size in [const Size(390,844),const Size(640,300)]) {
    testWidgets('menus, dialog and sheet remain readable and actionable dark=$dark size=$size',(tester)async {
      tester.view.devicePixelRatio=1;tester.view.physicalSize=size;
      addTearDown(tester.view.resetDevicePixelRatio);addTearDown(tester.view.resetPhysicalSize);
      final theme=dark?AppTheme.dark:AppTheme.light;
      String? selected,name;bool quality=false;
      const boundaryKey=ValueKey('theme-shot');
      Future<void> snapshot(String kind)async{
        const folder=String.fromEnvironment('BUYU_THEME_SHOTS');
        if(folder.isEmpty)return;
        final boundary=tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
        await tester.runAsync(()async{
          final image=await boundary.toImage(pixelRatio:1);
          final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
          await Directory(folder).create(recursive:true);
          await File('$folder/${dark?'dark':'light'}-${size.width>size.height?'landscape':'portrait'}-$kind.png').writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(RepaintBoundary(key:boundaryKey,child:MaterialApp(theme:theme,home:Builder(builder:(context)=>Scaffold(
        appBar:AppBar(title:const Text('音乐账号与收藏')),
        body:SingleChildScrollView(child:Column(children:[
          Wrap(spacing:8,children:[BuYuChoiceChip(label:const Text('QQ音乐'),selected:true,onSelected:(_){}),BuYuChoiceChip(label:const Text('网易云'),selected:false,onSelected:(_){})]),
          PopupMenuButton<String>(tooltip:'歌单管理',onSelected:(v)=>selected=v,itemBuilder:(_)=>[const PopupMenuItem(value:'rename',child:Text('重命名')),const PopupMenuItem(value:'delete',child:Text('删除云端歌单'))]),
          TextButton(onPressed:()async{name=await libraryNameDialog(context,'修改歌单名称');},child:const Text('打开名称弹窗')),
          TextButton(onPressed:()=>showModalBottomSheet<void>(context:context,isScrollControlled:true,builder:(sheet)=>AdaptiveOptionSheet(title:'选择下载音质',children:[
            RadioListTile<bool>(value:false,groupValue:false,title:const Text('标准'),onChanged:(_)=>Navigator.pop(sheet)),
            RadioListTile<bool>(value:true,groupValue:false,title:const Text('极高'),onChanged:(_){quality=true;Navigator.pop(sheet);}),
          ])),child:const Text('打开音质面板')),
        ])))))));
      await tester.pumpAndSettle();
      final chip=tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip,'QQ音乐'));
      expect(BuYuStyle.contrast(chip.labelStyle!.color!,chip.selectedColor!),greaterThanOrEqualTo(4.5));
      await tester.tap(find.byTooltip('歌单管理'));await tester.pumpAndSettle();
      final menuText=DefaultTextStyle.of(tester.element(find.text('重命名'))).style.color!;
      expect(BuYuStyle.contrast(menuText,theme.popupMenuTheme.color!),greaterThanOrEqualTo(4.5));
      await snapshot('menu');
      await tester.tap(find.text('重命名'));await tester.pumpAndSettle();expect(selected,'rename');
      await tester.tap(find.text('打开名称弹窗'));await tester.pumpAndSettle();
      final actionText=DefaultTextStyle.of(tester.element(find.text('保存'))).style.color!;
      expect(BuYuStyle.contrast(actionText,theme.dialogTheme.backgroundColor!),greaterThanOrEqualTo(4.5));
      await snapshot('dialog');
      await tester.enterText(find.byType(TextField),'新名称');await tester.tap(find.text('保存'));await tester.pumpAndSettle();expect(name,'新名称');
      await tester.ensureVisible(find.text('打开音质面板'));await tester.tap(find.text('打开音质面板'));await tester.pumpAndSettle();
      await snapshot('sheet');
      await tester.tap(find.text('极高'));await tester.pumpAndSettle();expect(quality,true);
      expect(tester.takeException(),isNull);
      expect(theme.primaryColor,const Color(0xffe56260));
      expect(theme.cardColor,dark?const Color(0xffecebeb):const Color(0xff2c2c2c),reason:'保留原有头像侧栏反色背景');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
